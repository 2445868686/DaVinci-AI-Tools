local SCRIPT_NAME = "DaVinci TTS"
local SCRIPT_VERSION = " 1.0.0"
local SCRIPT_AUTHOR = "HEIBA"
local SCRIPT_KOFI_URL = "https://ko-fi.com/heiba"
local SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"
local OPENAI_FM_URL = "https://openai.fm"
local SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
local SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"
local SUPABASE_TIMEOUT = 5
local AZURE_SPEECH_PROVIDER = "AZURE_SPEECH"

local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

print(string.format("%s | %s | %s", SCRIPT_NAME, trim(SCRIPT_VERSION), SCRIPT_AUTHOR))

local json = require("dkjson")

local PATH_SEP = package.config:sub(1, 1)

local App = {
    State = {},
    Config = {
        Azure = {},
        MiniMax = {},
        OpenAI = {},
        Settings = {},
    },
    Services = {},
    Utils = {},
    UI = {},
    Utils = {},
    Paths = {},
}

local Utils = App.Utils
local Config = App.Config
local Paths = App.Paths
local Services = App.Services
App.Azure = {}
App.Subtitles = {}
App.Settings = {}
App.State.providerSecrets = App.State.providerSecrets or {}
local AZURE_STYLE_LABELS = {}
App.URLS = {
    AzureRegister = "https://speech.microsoft.com/portal/voicegallery",
    OpenAIRegister = "https://platform.openai.com/signup",
    MiniMaxRegisterCn = "https://platform.minimaxi.com/registration",
    MiniMaxRegisterIntl = "https://intl.minimaxi.com/login",
}

local GENDER_LABELS = {
    Female = { cn = "女性", en = "Female" },
    Male = { cn = "男性", en = "Male" },
    Neutral = { cn = "中性", en = "Neutral" },
    Child = { cn = "儿童", en = "Child" },
}

local MINIMAX_MODELS = {
    "speech-2.6-hd",
    "speech-2.6-turbo",
    "speech-02-hd",
    "speech-02-turbo",
    "speech-01-hd",
    "speech-01-turbo",
}

local MINIMAX_SOUND_EFFECTS = {
    { id = "default", cn = "默认", en = "Default" },
    { id = "spacious_echo", cn = "空旷回音", en = "Spacious Echo" },
    { id = "auditorium_echo", cn = "礼堂广播", en = "Auditorium" },
    { id = "lofi_telephone", cn = "电话失真", en = "Lo-Fi Telephone" },
    { id = "robotic", cn = "机械音", en = "Robotic" },
}

local MINIMAX_EMOTIONS = {
    { id = "default", cn = "默认", en = "Default" },
    { id = "happy", cn = "高兴", en = "Happy" },
    { id = "sad", cn = "悲伤", en = "Sad" },
    { id = "angry", cn = "愤怒", en = "Angry" },
    { id = "fearful", cn = "害怕", en = "Fearful" },
    { id = "disgusted", cn = "厌恶", en = "Disgusted" },
    { id = "surprised", cn = "惊讶", en = "Surprised" },
    { id = "neutral", cn = "中性", en = "Neutral" },
}

local OPENAI_MODELS = {
    "gpt-4o-mini-tts",
    "tts-1",
    "tts-1-hd",
}

local SHARED_FORMATS = {
    { id = "mp3", label = "MP3", azureId = "audio-48khz-96kbitrate-mono-mp3" },
    { id = "wav", label = "WAV", azureId = "riff-48khz-16bit-mono-pcm" },
}


local LOCALE_NAME_LABELS = {}
local clampIndex

local function percentDelta(value)
    return (value - 1.0) * 100.0
end

function App.Azure.formatProsodyValue(value)
    if not value then
        return nil
    end
    local delta = percentDelta(value)
    if math.abs(delta) < 0.01 then
        return nil
    end
    local sign = delta >= 0 and "+" or "-"
    return string.format("%s%.2f%%", sign, math.abs(delta))
end

function App.Azure.escapeText(text)
    local placeholders = {}
    local counter = 0
    local function preserve(tag)
        counter = counter + 1
        local key = "__SSML_TAG_" .. counter .. "__"
        placeholders[key] = tag
        return key
    end
    local processed = text
    processed = processed:gsub("<phoneme.-</phoneme>", preserve)
    processed = processed:gsub("<break%s+.-/>", preserve)
    processed = processed:gsub("&", "&amp;")
    processed = processed:gsub("<", "&lt;")
    processed = processed:gsub(">", "&gt;")
    processed = processed:gsub("'", "&apos;")
    processed = processed:gsub('"', "&quot;")
    for key, tag in pairs(placeholders) do
        processed = processed:gsub(key, tag)
    end
    return processed
end

function App.Azure.buildProsodyAttributes(rate, pitch, volume)
    local attrs = {}
    local rateAttr = App.Azure.formatProsodyValue(rate or 1.0)
    local pitchAttr = App.Azure.formatProsodyValue(pitch or 1.0)
    local volumeAttr = App.Azure.formatProsodyValue(volume or 1.0)
    if rateAttr then
        table.insert(attrs, string.format('rate="%s"', rateAttr))
    end
    if pitchAttr then
        table.insert(attrs, string.format('pitch="%s"', pitchAttr))
    end
    if volumeAttr then
        table.insert(attrs, string.format('volume="%s"', volumeAttr))
    end
    if #attrs == 0 then
        return nil
    end
    return " " .. table.concat(attrs, " ")
end

function App.Azure.appendContent(buffer, content, prosodyAttrs)
    if prosodyAttrs then
        table.insert(buffer, "<prosody" .. prosodyAttrs .. ">" .. content .. "</prosody>")
    else
        table.insert(buffer, content)
    end
end

function App.Azure.buildSsml(params)
    local locale = params.locale or "en-US"
    local voiceId = params.voiceId or "en-US-AriaNeural"
    local style = params.style or "default"
    local styleDegree = params.styleDegree
    local multilingual = params.multilingualCode
    if multilingual == "Default" then
        multilingual = nil
    end
    local text = params.text or ""
    local lines = {}
    for line in tostring(text):gmatch("([^\r\n]+)") do
        table.insert(lines, line)
    end
    if #lines == 0 then
        table.insert(lines, text)
    end

    local buffer = {}
    table.insert(buffer, string.format('<speak version="1.0" xml:lang="%s" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="http://www.w3.org/2001/mstts" xmlns:emo="http://www.w3.org/2009/10/emotionml">', locale))
    table.insert(buffer, string.format('<voice name="%s">', voiceId))
    if multilingual and multilingual ~= "" and multilingual ~= "Default" then
        table.insert(buffer, string.format('<lang xml:lang="%s">', multilingual))
    end

    for _, rawLine in ipairs(lines) do
        local trimmed = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local content = App.Azure.escapeText(trimmed)
            local prosodyAttrs = App.Azure.buildProsodyAttributes(params.rate, params.pitch, params.volume)
            table.insert(buffer, "<s>")
            if style and style ~= "" and style ~= "default" then
                local expressAttrs = string.format(' style="%s"', style)
                if styleDegree and math.abs(styleDegree - 1.0) > 0.01 then
                    expressAttrs = expressAttrs .. string.format(' styledegree="%.2f"', styleDegree)
                end
                table.insert(buffer, "<mstts:express-as" .. expressAttrs .. ">")
                App.Azure.appendContent(buffer, content, prosodyAttrs)
                table.insert(buffer, "</mstts:express-as>")
            else
                App.Azure.appendContent(buffer, content, prosodyAttrs)
            end
            table.insert(buffer, "</s>")
        end
    end

    if multilingual and multilingual ~= "" and multilingual ~= "Default" then
        table.insert(buffer, "</lang>")
    end
    table.insert(buffer, "</voice>")
    table.insert(buffer, "</speak>")
    print(table.concat(buffer))
    return table.concat(buffer)
end

function App.Azure.getOutputExtension(formatId)
    if not formatId or formatId == "" then
        return ".wav"
    end
    local lower = formatId:lower()
    if lower:find("mp3", 1, true) then
        return ".mp3"
    elseif lower:find("ogg", 1, true) then
        return ".ogg"
    elseif lower:find("webm", 1, true) then
        return ".webm"
    end
    return ".wav"
end

function App.Settings.getSharedFormat()
    local formats = Config.Settings.formats or SHARED_FORMATS
    local items = App.UI.items or {}
    local idx = 0
    if items.outputFormatCombo and items.outputFormatCombo.CurrentIndex ~= nil then
        idx = clampIndex(items.outputFormatCombo.CurrentIndex, #formats)
    elseif App.State.azure and App.State.azure.outputFormatIndex then
        idx = clampIndex(App.State.azure.outputFormatIndex, #formats)
    end
    local entry = formats[idx + 1] or formats[1]
    App.State.azure = App.State.azure or {}
    App.State.azure.outputFormatIndex = idx
    return entry, idx
end

function App.Settings.getSharedFormatId()
    local entry = App.Settings.getSharedFormat()
    if not entry then
        return "mp3"
    end
    return entry.id or "mp3"
end

function App.Settings.getAzureFormatId()
    local entry = App.Settings.getSharedFormat()
    if not entry then
        return "riff-48khz-16bit-mono-pcm"
    end
    return entry.azureId or entry.id or "riff-48khz-16bit-mono-pcm"
end

function App.Azure.deriveSampleRate(formatId)
    if not formatId or formatId == "" then
        return 44100
    end
    local lower = formatId:lower()
    local khz = lower:match("(%d+)khz")
    if khz then
        local value = tonumber(khz)
        if value and value > 0 then
            return math.floor(value * 1000)
        end
    end
    return 44100
end

function App.Azure.buildOutputPath(params)
    local baseDir = params.outputDir
    if not baseDir or baseDir == "" then
        return nil, "missing_output_dir"
    end
    if not Utils.ensureDir(baseDir) then
        return nil, "ensure_failed"
    end
    local extension = App.Azure.getOutputExtension(params.outputFormat)
    local path, err = Utils.nextAvailableFile(baseDir, {
        baseName = params.text or "audio",
        extension = extension,
        pattern = "%s_%s_%02d%s",
        replaceSpaces = true,
        maxBaseLength = 24,
    })
    if not path then
        return nil, err or "name_generation_failed"
    end
    return path
end

------------------------------------------------------------------
-- runShellCommand
------------------------------------------------------------------


Services.HttpClient = Services.HttpClient or {}
local httpClient = Services.HttpClient
local runHiddenWindowsCommand, runShellCommand
do
    local okHttps, https = pcall(require, "ssl.https")
    local okLtn12, ltn12 = pcall(require, "ltn12")
    if okHttps and okLtn12 and https and ltn12 then
        httpClient.https = {
            get = function(url, headers, timeout)
                local sinkTable = {}
                local requestHeaders = {}
                if headers then
                    for k, v in pairs(headers) do
                        requestHeaders[k] = v
                    end
                end
                requestHeaders["content-length"] = "0"
                local ok, statusCode, respHeaders, statusLine = https.request({
                    url = url,
                    method = "GET",
                    headers = requestHeaders,
                    sink = ltn12.sink.table(sinkTable),
                    protocol = "tlsv1_2",
                    verify = "none",
                    timeout = timeout or SUPABASE_TIMEOUT,
                })
                if not ok then
                    return nil, statusCode or statusLine or "request_failed"
                end
                local body = table.concat(sinkTable)
                local code = tonumber(statusCode) or tonumber(respHeaders and respHeaders.status) or statusCode
                return body, code
            end,
            postJson = function(url, payload, headers, timeout)
                local sinkTable = {}
                local requestHeaders = {}
                if headers then
                    for k, v in pairs(headers) do
                        requestHeaders[k] = v
                    end
                end
                local bodyStr = payload or ""
                requestHeaders["content-type"] = "application/json"
                requestHeaders["content-length"] = tostring(#bodyStr)
                local ok, statusCode, respHeaders, statusLine = https.request({
                    url = url,
                    method = "POST",
                    headers = requestHeaders,
                    source = ltn12.source.string(bodyStr),
                    sink = ltn12.sink.table(sinkTable),
                    protocol = "tlsv1_2",
                    verify = "none",
                    timeout = timeout or SUPABASE_TIMEOUT,
                })
                if not ok then
                    return nil, statusCode or statusLine or "request_failed"
                end
                local body = table.concat(sinkTable)
                local code = tonumber(statusCode) or tonumber(respHeaders and respHeaders.status) or statusCode
                return body, code
            end
        }
    end
end

function Services.httpGet(url, headers, timeout)
    if httpClient.https then
        local body, code = httpClient.https.get(url, headers, timeout)
        if body then return body, code end
    end

    local headerParts = {}
    if headers then
        for k, v in pairs(headers) do
            local cleanValue = tostring(v):gsub('"', '\\"')
            table.insert(headerParts, string.format('-H "%s: %s"', k, cleanValue))
        end
    end
    local maxTime = timeout or SUPABASE_TIMEOUT
    local curlCommand = string.format('curl -sS -m %d %s "%s"', maxTime, table.concat(headerParts, " "), url)
    local sep = package.config:sub(1, 1)

    if sep == "\\" then
        local outPath, err = Utils.makeTempPath("out")
        if not outPath then return nil, "tmpname_failed:" .. tostring(err) end
        local redirected = string.format('%s > "%s" 2>nul', curlCommand, outPath)
        local ok = runShellCommand and runShellCommand(redirected)
        local file = io.open(outPath, "rb")
        local body = file and file:read("*a") or ""
        if file then file:close() end
        os.remove(outPath)
        if not ok then return nil, "curl_hidden_failed" end
        if body == "" then return nil, "empty_response" end
        return body, nil
    end

    curlCommand = curlCommand .. " 2>/dev/null"
    local pipe = io.popen(curlCommand, "r")
    if not pipe then return nil, "curl_popen_failed" end
    local body = pipe:read("*a") or ""
    pipe:close()
    if body == "" then return nil, "empty_response" end
    return body, nil
end


function Services.httpPostJson(url, payload, headers, timeout)
    local bodyStr = payload or ""
    if httpClient.https and httpClient.https.postJson then
        local body, code = httpClient.https.postJson(url, bodyStr, headers, timeout)
        if body then return body, code end
    end

    local headerParts, hasContentType = {}, false
    if headers then
        for k, v in pairs(headers) do
            local cleanValue = tostring(v):gsub('"', '\\"')
            table.insert(headerParts, string.format('-H "%s: %s"', k, cleanValue))
            if type(k) == "string" and k:lower() == "content-type" then
                hasContentType = true
            end
        end
    end
    if not hasContentType then
        table.insert(headerParts, '-H "Content-Type: application/json"')
    end

    local maxTime = timeout or SUPABASE_TIMEOUT
    local sep = package.config:sub(1, 1)

    -- 用我们自己的临时文件
    local tempPayload, err1 = Utils.makeTempPath("json")
    if not tempPayload then return nil, "tmpname_failed:" .. tostring(err1) end
    local f, err2 = io.open(tempPayload, "wb")
    if not f then return nil, "payload_tmp_open_failed:" .. tostring(err2) end
    f:write(bodyStr)
    f:close()

    if sep == "\\" then
        local outputPath, err3 = Utils.makeTempPath("out")
        if not outputPath then os.remove(tempPayload); return nil, "tmpname_failed:" .. tostring(err3) end

        local curlCommand = string.format(
            'curl -sS -m %d -X POST %s --data-binary "@%s" "%s"',
            maxTime, table.concat(headerParts, " "), tempPayload, url
        )
        local redirected = string.format('%s > "%s" 2>nul', curlCommand, outputPath)
        local ok = runShellCommand and runShellCommand(redirected)

        local of = io.open(outputPath, "rb")
        local body = of and of:read("*a") or ""
        if of then of:close() end
        os.remove(outputPath)
        os.remove(tempPayload)

        if not ok then return nil, "curl_hidden_failed" end
        if body == "" then return nil, "empty_response" end
        return body, nil
    else
        local curlCommand = string.format(
            'curl -sS -m %d -X POST %s --data-binary @%q "%s" 2>/dev/null',
            maxTime, table.concat(headerParts, " "), tempPayload, url
        )
        local pipe = io.popen(curlCommand, "r")
        if not pipe then os.remove(tempPayload); return nil, "curl_popen_failed" end
        local body = pipe:read("*a") or ""
        pipe:close()
        os.remove(tempPayload)
        if body == "" then return nil, "empty_response" end
        return body, nil
    end
end

function Services.supabaseCheckUpdate(pluginId)
    if not pluginId or pluginId == "" then
        return nil
    end
    local url = string.format("%s/functions/v1/check_update?pid=%s", SUPABASE_URL, Utils.urlEncode(pluginId))
    local headers = {
        Authorization = "Bearer " .. SUPABASE_ANON_KEY,
        apikey = SUPABASE_ANON_KEY,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
    }
    local body, status = Services.httpGet(url, headers, SUPABASE_TIMEOUT)
    if not body then
        if status then
            print(string.format("[Update] Supabase request failed: %s", tostring(status)))
        end
        return nil
    end
    if status and status ~= 200 then
        if status ~= 400 and status ~= 404 then
            print(string.format("[Update] Unexpected status code: %s", tostring(status)))
        end
        return nil
    end
    local decoded, pos, err = json.decode(body)
    if type(decoded) ~= "table" then
        print(string.format("[Update] Invalid response: %s (pos=%s, err=%s)", tostring(body), tostring(pos), tostring(err)))
        return nil
    end
    return decoded
end

local SEP = package.config:sub(1, 1)

local IS_WINDOWS = (SEP == "\\")

if IS_WINDOWS then
    local ok, ffi = pcall(require, "ffi")
    if ok then
        local kernel32 = ffi.load("kernel32")
        local CP_UTF8 = 65001
        local CREATE_NO_WINDOW = 0x08000000
        local STARTF_USESHOWWINDOW = 0x00000001
        local INFINITE = 0xFFFFFFFF

        ffi.cdef[[
            typedef unsigned short WORD;
            typedef unsigned long DWORD;
            typedef int BOOL;
            typedef void* HANDLE;
            typedef wchar_t* LPWSTR;
            typedef const wchar_t* LPCWSTR;
            typedef void* LPVOID;
            typedef unsigned char BYTE;

            typedef struct _STARTUPINFOW {
                DWORD cb;
                LPWSTR lpReserved;
                LPWSTR lpDesktop;
                LPWSTR lpTitle;
                DWORD dwX;
                DWORD dwY;
                DWORD dwXSize;
                DWORD dwYSize;
                DWORD dwXCountChars;
                DWORD dwYCountChars;
                DWORD dwFillAttribute;
                DWORD dwFlags;
                WORD wShowWindow;
                WORD cbReserved2;
                BYTE *lpReserved2;
                HANDLE hStdInput;
                HANDLE hStdOutput;
                HANDLE hStdError;
            } STARTUPINFOW;

            typedef struct _PROCESS_INFORMATION {
                HANDLE hProcess;
                HANDLE hThread;
                DWORD dwProcessId;
                DWORD dwThreadId;
            } PROCESS_INFORMATION;

            BOOL CreateProcessW(
                LPCWSTR lpApplicationName,
                LPWSTR lpCommandLine,
                LPVOID lpProcessAttributes,
                LPVOID lpThreadAttributes,
                BOOL bInheritHandles,
                DWORD dwCreationFlags,
                LPVOID lpEnvironment,
                LPCWSTR lpCurrentDirectory,
                STARTUPINFOW *lpStartupInfo,
                PROCESS_INFORMATION *lpProcessInformation
            );

            DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds);
            BOOL GetExitCodeProcess(HANDLE hProcess, DWORD *lpExitCode);
            BOOL CloseHandle(HANDLE hObject);
            DWORD GetLastError(void);
            int MultiByteToWideChar(unsigned int CodePage, DWORD dwFlags,
                                    const char *lpMultiByteStr, int cbMultiByte,
                                    wchar_t *lpWideCharStr, int cchWideChar);
        ]]

        local function utf8ToWideBuffer(str)
            local required = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
            if required == 0 then
                return nil
            end
            local buffer = ffi.new("wchar_t[?]", required)
            if kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buffer, required) == 0 then
                return nil
            end
            return buffer
        end

        runHiddenWindowsCommand = function(command)
            local comspec = os.getenv("COMSPEC") or "C:\\Windows\\System32\\cmd.exe"
            local fullCommand = string.format('"%s" /c %s', comspec, command)
            local cmdBuffer = utf8ToWideBuffer(fullCommand)
            if not cmdBuffer then
                return false, "command_encoding_failed"
            end

            local startupInfo = ffi.new("STARTUPINFOW")
            startupInfo.cb = ffi.sizeof(startupInfo)
            startupInfo.dwFlags = STARTF_USESHOWWINDOW
            startupInfo.wShowWindow = 0 -- SW_HIDE

            local processInfo = ffi.new("PROCESS_INFORMATION")
            local created = kernel32.CreateProcessW(
                nil,
                cmdBuffer,
                nil,
                nil,
                false,
                CREATE_NO_WINDOW,
                nil,
                nil,
                startupInfo,
                processInfo
            )

            if created == 0 then
                return false, kernel32.GetLastError()
            end

            kernel32.WaitForSingleObject(processInfo.hProcess, INFINITE)

            local exitCodeArr = ffi.new("DWORD[1]", 0)
            kernel32.GetExitCodeProcess(processInfo.hProcess, exitCodeArr)
            kernel32.CloseHandle(processInfo.hProcess)
            kernel32.CloseHandle(processInfo.hThread)

            return exitCodeArr[0] == 0, exitCodeArr[0]
        end
    end
end

function runShellCommand(command)
    if IS_WINDOWS and type(runHiddenWindowsCommand) == "function" then
        local ok, code = runHiddenWindowsCommand(command)
        if not ok then
            print(string.format("Command failed (%s)", tostring(code)))
        end
        return ok == true
    end

    local res, how, code = os.execute(command)
    if type(res) == "number" then
        return res == 0
    end
    if res == true then
        if how == "exit" then
            return (code or 0) == 0
        end
        return true
    end
    return false
end
------------------------------------------------------------------
-- runShellCommand
------------------------------------------------------------------

function clampIndex(value, size)
    if type(value) ~= "number" then
        return 0
    end
    if size <= 0 then
        return 0
    end
    if value < 0 then
        return 0
    end
    if value > size - 1 then
        return size - 1
    end
    return value
end

function Utils.joinPath(...)
    local parts = { ... }
    if #parts == 0 then
        return ""
    end
    local path = tostring(parts[1] or "")
    for i = 2, #parts do
        local part = tostring(parts[i] or "")
        if part ~= "" then
            local last = path:sub(-1)
            if path ~= "" and last ~= PATH_SEP and last ~= "/" and last ~= "\\" and part:sub(1, 1) ~= PATH_SEP and part:sub(1, 1) ~= "/" then
                path = path .. PATH_SEP
            elseif path ~= "" and (last == "/" or last == "\\") and (part:sub(1, 1) == "/" or part:sub(1, 1) == "\\") then
                part = part:sub(2)
            end
            path = path .. part
        end
    end
    return path
end

local function discoverScriptDir()
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    local dir = source:match("(.*[\\/])")
    if not dir or dir == "" then
        return "."
    end
    dir = dir:gsub("[\\/]+$", "")
    return dir
end

Paths.scriptDir = discoverScriptDir()
Paths.configDir = Utils.joinPath(Paths.scriptDir, "config")
Paths.voicesDir = Utils.joinPath(Paths.scriptDir, "voices")
Paths.tempDir = Utils.joinPath(Paths.scriptDir, "temp")

function Paths.inConfig(...)
    return Utils.joinPath(Paths.configDir, ...)
end

function Paths.inVoices(...)
    return Utils.joinPath(Paths.voicesDir, ...)
end

-- Windows UTF-8 safe file operations to avoid ANSI fopen codepage issues
local winfs = {}
if IS_WINDOWS then
    local okFfi, ffi = pcall(require, "ffi")
    if okFfi and ffi then
        local okKernel, kernel32 = pcall(ffi.load, "kernel32")
        local okMsvcrt, msvcrt = pcall(ffi.load, "msvcrt")
        if okKernel and okMsvcrt and kernel32 and msvcrt then
            local CP_UTF8 = 65001

            ffi.cdef[[
                typedef unsigned short WCHAR;
                typedef unsigned int UINT;
                typedef long LONG;
                typedef unsigned long DWORD;
                typedef unsigned long size_t;
                typedef struct _iobuf FILE;

                int MultiByteToWideChar(UINT CodePage, DWORD dwFlags,
                                        const char* lpMultiByteStr, int cbMultiByte,
                                        WCHAR* lpWideCharStr, int cchWideChar);
                FILE* _wfopen(const WCHAR* filename, const WCHAR* mode);
                int fclose(FILE* stream);
                size_t fread(void* ptr, size_t size, size_t count, FILE* stream);
                size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream);
                int fseek(FILE* stream, long offset, int origin);
                long ftell(FILE* stream);
            ]]

            local function utf8ToWide(str)
                local needed = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
                if needed == 0 then return nil end
                local buf = ffi.new("WCHAR[?]", needed)
                if kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, needed) == 0 then
                    return nil
                end
                return buf
            end

            local function openWide(path, mode)
                local wpath = utf8ToWide(path or "")
                local wmode = utf8ToWide(mode or "rb")
                if not wpath or not wmode then
                    return nil, "path_encoding_failed"
                end
                local f = msvcrt._wfopen(wpath, wmode)
                if f == nil then
                    return nil, "wfopen_failed"
                end
                return f
            end

            function winfs.readFile(path)
                local f, err = openWide(path, "rb")
                if not f then return nil, err end
                msvcrt.fseek(f, 0, 2) -- SEEK_END
                local size = tonumber(msvcrt.ftell(f)) or 0
                if size < 0 then size = 0 end
                msvcrt.fseek(f, 0, 0) -- SEEK_SET
                local buf = ffi.new("uint8_t[?]", size)
                local read = msvcrt.fread(buf, 1, size, f)
                msvcrt.fclose(f)
                return ffi.string(buf, read)
            end

            function winfs.writeFile(path, content)
                local f, err = openWide(path, "wb")
                if not f then return false, err end
                local data = content or ""
                local len = #data
                local written = msvcrt.fwrite(data, 1, len, f)
                msvcrt.fclose(f)
                if written ~= len then
                    return false, "write_failed"
                end
                return true
            end

            function winfs.fileExists(path)
                local f = select(1, openWide(path, "rb"))
                if f then
                    msvcrt.fclose(f)
                    return true
                end
                return false
            end

            function winfs.getFileSize(path)
                local f = select(1, openWide(path, "rb"))
                if not f then return nil end
                msvcrt.fseek(f, 0, 2)
                local size = tonumber(msvcrt.ftell(f))
                msvcrt.fclose(f)
                return size
            end
        end
    end
end

function Utils.readFile(path)
    if IS_WINDOWS and winfs.readFile then
        local content, err = winfs.readFile(path)
        if content then
            return content
        end
    end
    local fh, err = io.open(path, "r")
    if not fh then
        return nil, err
    end
    local content = fh:read("*a")
    fh:close()
    return content
end

function Utils.writeFile(path, content)
    if IS_WINDOWS and winfs.writeFile then
        local ok, err = winfs.writeFile(path, content)
        if ok ~= nil then
            return ok, err
        end
    end
    local fh, err = io.open(path, "wb")
    if not fh then
        return false, err
    end
    fh:write(content or "")
    fh:close()
    return true
end

function Utils.getTempDir()
    return Paths.tempDir
end

function Utils.makeTempPath(ext)
    local dir = Utils.getTempDir() or Paths.scriptDir
    if not Utils.ensureDir(dir) then
        return nil, "temp_dir_unavailable"
    end
    local prefix = string.format("tmp_%s_%d_", SCRIPT_NAME:gsub("%s+", ""):lower(), os.time())
    local counter = 0
    local suffix = ext or ""
    if suffix ~= "" and suffix:sub(1, 1) ~= "." then
        suffix = "." .. suffix
    end
    local path
    repeat
        counter = counter + 1
        path = Utils.joinPath(dir, string.format("%s%04d%s", prefix, counter, suffix))
        if counter > 1000 then
            return nil, "temp_name_exhausted"
        end
    until not Utils.fileExists(path)
    return path
end

function Utils.urlEncode(str)
    if not str then
        return ""
    end
    return tostring(str):gsub("[^%w%-%._~]", function(ch)
        return string.format("%%%02X", ch:byte())
    end)
end

local function tableIsArray(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local maxIndex = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k > maxIndex then
            maxIndex = k
        end
        count = count + 1
    end
    if maxIndex == 0 then
        return true
    end
    return maxIndex == count
end

local function cloneForJson(value)
    if type(value) ~= "table" then
        return value
    end
    if tableIsArray(value) then
        local result = {}
        local length = #value
        for i = 1, length do
            result[i] = cloneForJson(value[i])
        end
        return result
    end
    local result = {}
    local order = rawget(value, "__order")
    local metaOrder = {}
    if type(order) == "table" then
        for _, key in ipairs(order) do
            if key ~= "__order" and value[key] ~= nil then
                table.insert(metaOrder, key)
            end
        end
    end
    for k, v in pairs(value) do
        if k ~= "__order" then
            result[k] = cloneForJson(v)
        end
    end
    if #metaOrder > 0 then
        setmetatable(result, { __jsonorder = metaOrder })
    end
    return result
end

function Utils.writeJsonOrdered(path, data, state)
    local prepared = cloneForJson(data)
    local encodeState = state or { indent = "  " }
    local ok, content = pcall(json.encode, prepared, encodeState)
    if not ok then
        return false, content
    end
    return Utils.writeFile(path, content)
end

function Utils.fileExists(path)
    if not path or path == "" then
        return false
    end
    if IS_WINDOWS and winfs.fileExists then
        return winfs.fileExists(path)
    end
    local fh = io.open(path, "rb")
    if fh then
        fh:close()
        return true
    end
    return false
end

function Utils.getFileSize(path)
    if IS_WINDOWS and winfs.getFileSize then
        return winfs.getFileSize(path)
    end
    local fh = io.open(path, "rb")
    if not fh then
        return nil
    end
    local size = fh:seek("end")
    fh:close()
    return size
end

function Utils.ensureDir(path)
    if not path or path == "" then
        return true
    end

    local okLfs, lfs = pcall(require, "lfs")
    if okLfs and lfs then
        local attr = lfs.attributes(path)
        if attr and attr.mode == "directory" then
            return true
        end
    elseif bmd and type(bmd.fileexists) == "function" then
        local ok, exists = pcall(bmd.fileexists, path)
        if ok and exists then
            return true
        end
    end

    if PATH_SEP == "\\" then
        local command = string.format('if not exist "%s" mkdir "%s"', path, path)
        local ok = runShellCommand(command)
        if not ok then
            print("Failed to create directory: " .. tostring(path))
            return false
        end
        return true
    else
        local escaped = path:gsub("'", "'\\''")
        local ok = runShellCommand("mkdir -p '" .. escaped .. "'")
        if not ok then
            print("Failed to create directory: " .. tostring(path))
            return false
        end
        return true
    end
end

function Utils.removeDir(path)
    if not path or path == "" then
        return true
    end
    local sep = package.config:sub(1, 1)
    local command
    if sep == "\\" then
        command = string.format('rmdir /S /Q "%s"', path)
    else
        command = string.format("rm -rf '%s'", path:gsub("'", "'\\''"))
    end
    local ok = runShellCommand(command)
    return ok ~= false
end

function Utils.sanitizeFileName(text, maxLen)
    maxLen = maxLen or 32
    local sanitized = tostring(text or ""):gsub("[\r\n]", " ")
    sanitized = sanitized:gsub("[%z\1-\31]", " ")
    sanitized = sanitized:gsub("[<>:\"/\\|%?*]", " ")
    sanitized = sanitized:gsub("%s+", " ")
    sanitized = sanitized:match("^%s*(.-)%s*$") or ""
    
    if sanitized == "" then
        sanitized = "audio"
    end
    -- 6. UTF-8 安全截取 (防止切断汉字)
    if #sanitized > maxLen then
        local tmp = sanitized:sub(1, maxLen)
        local byte = string.byte(tmp, -1)
        -- 如果最后一个字节是 UTF-8 后续字节 (10xxxxxx, 即 128-191)，说明切在字中间了
        while byte and byte >= 128 and byte < 192 do
            tmp = tmp:sub(1, -2)
            byte = string.byte(tmp, -1)
        end
        -- 如果剩下一个孤立的起始字节 (11xxxxxx, 即 >= 192)，也去掉
        if byte and byte >= 192 then
             tmp = tmp:sub(1, -2)
        end
        sanitized = tmp
    end
    
    return sanitized
end

function Utils.nextAvailableFile(dir, options)
    options = options or {}
    if not dir or dir == "" then
        return nil, "missing_dir"
    end

    local baseName = Utils.sanitizeFileName(options.baseName or "audio", options.maxBaseLength or 32)
    if options.replaceSpaces then
        baseName = baseName:gsub("%s+", "_")
    end

    local extension = options.extension or ""
    if extension ~= "" and extension:sub(1, 1) ~= "." then
        extension = "." .. extension
    end

    local timestamp
    if options.timestamp ~= nil then
        timestamp = tostring(options.timestamp)
    else
        local fmt = options.timestampFormat or "%Y%m%d-%H%M%S"
        timestamp = os.date(fmt)
    end

    local pattern = options.pattern or "%s_%s_%02d%s"
    local index = options.startIndex or 1
    local maxAttempts = options.maxAttempts
    local attempts = 0

    while true do
        local candidateName = string.format(pattern, baseName, timestamp, index, extension)
        local candidatePath = Utils.joinPath(dir, candidateName)
        if not Utils.fileExists(candidatePath) then
            return candidatePath
        end
        index = index + 1
        attempts = attempts + 1
        if maxAttempts and attempts >= maxAttempts then
            return nil, "name_exhausted"
        end
    end
end

local jsonObjectMeta = {
    __newindex = function(t, k, v)
        rawset(t, k, v)
        if type(k) ~= "number" then
            local order = rawget(t, "__order")
            if not order then
                order = {}
                rawset(t, "__order", order)
            end
            order[#order + 1] = k
        end
    end,
}

function Utils.decodeJsonWithOrder(content)
    if not content then
        return nil, "empty content"
    end
    local data, pos, err = json.decode(content, 1, nil, jsonObjectMeta)
    if not data then
        local msg = err or ("JSON decode error at position " .. tostring(pos))
        return nil, msg
    end
    return data
end

function Utils.readJson(path)
    local content, err = Utils.readFile(path)
    if not content then
        return nil, err
    end
    return Utils.decodeJsonWithOrder(content)
end

function Utils.iterObject(tbl)
    if type(tbl) ~= "table" then
        return function()
        end
    end
    local order = rawget(tbl, "__order")
    if order and #order > 0 then
        local index = 0
        local count = #order
        return function()
            index = index + 1
            if index <= count then
                local key = order[index]
                return key, rawget(tbl, key)
            end
        end
    end
    return pairs(tbl)
end

local function buildLabelPair(cn, en)
    local textCn = cn or en or ""
    local textEn = en or cn or ""
    return { cn = textCn, en = textEn }
end

local function normalizeVoiceLabel(name, fallback)
    if type(name) == "string" and #name > 0 then
        return buildLabelPair(name, name)
    end
    return buildLabelPair(fallback or "Unknown", fallback or "Unknown")
end

local function mapGenderLabel(gender)
    return GENDER_LABELS[gender] or buildLabelPair(gender or "Other", gender or "Other")
end

local function resolveLocaleLabels(locale, localeName)
    local entry = LOCALE_NAME_LABELS[locale]
    local cn = (entry and entry.cn) or localeName or locale
    local en = (entry and entry.en) or localeName or locale
    if entry and not entry.en then
        entry.en = en
    end
    return { cn = cn, en = en }
end

function Config.load()
    local settings = Utils.readJson(Paths.inConfig("TTS_settings.json")) or {}
    Config.Settings.saved = settings
    Config.Settings.locale = settings.EN and "en" or (settings.CN and "cn" or "en")
    Config.Settings.outputPath = settings.Path or ""
    Config.Settings.info = {
        cn = Utils.readFile(Paths.inConfig("script_info_cn.html")) or "",
        en = Utils.readFile(Paths.inConfig("script_info_en.html")) or "",
    }
    Config.Settings.cloneInfo = {
        cn = Utils.readFile(Paths.inConfig("script_clone_info_cn.html")) or "",
        en = Utils.readFile(Paths.inConfig("script_clone_info_en.html")) or "",
    }
    Config.Status = Utils.readJson(Paths.inConfig("status.json")) or {}
    
    -- 加载语言标签 JSON
    local localeLabelsPath = Paths.inConfig("locale_labels.json")
    local localeLabels = Utils.readJson(localeLabelsPath)
    if type(localeLabels) == "table" then
        LOCALE_NAME_LABELS = localeLabels
    else
        LOCALE_NAME_LABELS = {}
    end
    -- 新增：加载风格标签 JSON
    local styleLabelsPath = Paths.inConfig("style_labels.json")
    local styleLabelsData = Utils.readJson(styleLabelsPath)
    if type(styleLabelsData) == "table" then
        AZURE_STYLE_LABELS = styleLabelsData
    else
        AZURE_STYLE_LABELS = {}
    end

    local minimaxVoicesPath = Paths.inVoices("minimax_voices.json")
    local minimaxVoicesData = Utils.readJson(minimaxVoicesPath) or {}
    local openaiVoicesPath = Paths.inVoices("openai_voices.json")
    local openaiVoicesData = Utils.readJson(openaiVoicesPath) or {}
    local azureVoiceListPath = Paths.inVoices("azure_voices.json")
    local azureVoiceList = Utils.readJson(azureVoiceListPath) or {}
    local edgeVoiceListPath = Paths.inVoices("edge_voices.json")
    local edgeVoicesData = Utils.readJson(edgeVoiceListPath) or {}

    Config.Settings.formats = SHARED_FORMATS

    local azure = Config.Azure
    local styleLabels = {}
    azure.languageOrder = {}
    azure.languagesList = {}
    azure.languages = {}
    azure.voiceTypeOrder = {}
    azure.voiceTypes = {}
    azure.voiceTypesList = {}
    azure.voiceMultilingualMap = {}
    azure.edgeVoices = edgeVoicesData or {}
    azure.outputFormats = {}
    for _, fmt in ipairs(SHARED_FORMATS) do
        table.insert(azure.outputFormats, { id = fmt.azureId, label = fmt.label, formatId = fmt.id })
    end
    azure.styleLabels = styleLabels

    local seenLocales = {}
    local seenVoiceTypes = {}
    for _, voiceInfo in ipairs(azureVoiceList) do
        if type(voiceInfo) == "table" then
            local locale = voiceInfo.Locale or voiceInfo.LocaleName or "Unknown"
            local localeName = voiceInfo.LocaleName or locale
            if locale and not seenLocales[locale] then
                seenLocales[locale] = true
                local langLabels = resolveLocaleLabels(locale, localeName)
                table.insert(azure.languageOrder, locale)
                table.insert(azure.languagesList, {
                    id = locale,
                    labels = langLabels,
                })
                azure.languages[locale] = {
                    labels = langLabels,
                    voices = {},
                }
            end
            local langBucket = azure.languages[locale]
            if langBucket then
                local voiceId = voiceInfo.ShortName or voiceInfo.Name or string.format("%s_%d", locale or "voice", #langBucket.voices + 1)
                local gender = voiceInfo.Gender or "Neutral"
                if gender and not seenVoiceTypes[gender] then
                    seenVoiceTypes[gender] = true
                    azure.voiceTypes[gender] = { labels = mapGenderLabel(gender) }
                    table.insert(azure.voiceTypeOrder, gender)
                end
                local styles = {}
                if type(voiceInfo.StyleList) == "table" then
                    for _, styleCode in ipairs(voiceInfo.StyleList) do
                        if styleCode and styleCode ~= "" then
                            table.insert(styles, styleCode)
                            -- 修改：使用加载的 JSON 数据填充 styleLabels
                            if not styleLabels[styleCode] then
                                local labelData = AZURE_STYLE_LABELS[styleCode]
                                if labelData then
                                    styleLabels[styleCode] = labelData
                                else
                                    styleLabels[styleCode] = { en = styleCode, cn = styleCode }
                                end
                            end
                        end
                    end
                end
                local multilingual = {}
                if type(voiceInfo.SecondaryLocaleList) == "table" then
                    for _, code in ipairs(voiceInfo.SecondaryLocaleList) do
                        if code and code ~= "" then
                            table.insert(multilingual, code)
                        end
                    end
                end
                local labelSource = voiceInfo.LocalName or voiceInfo.DisplayName or voiceInfo.Name or voiceId
                local voiceEntry = {
                    id = voiceId,
                    type = gender or "Neutral",
                    labels = normalizeVoiceLabel(labelSource, voiceId),
                    styles = styles,
                    multilingual = multilingual,
                }
                table.insert(langBucket.voices, voiceEntry)
                if #multilingual > 0 then
                    azure.voiceMultilingualMap[voiceId] = multilingual
                end
            end
        end
    end

    if #azure.languageOrder == 0 then
        local fallbackLocale = "zh-CN"
        azure.languageOrder = { fallbackLocale }
        azure.languagesList = {
            { id = fallbackLocale, labels = buildLabelPair("中文（普通话）", "Chinese (Mandarin)") },
        }
        azure.languages[fallbackLocale] = {
            labels = buildLabelPair("中文（普通话）", "Chinese (Mandarin)"),
            voices = {
                {
                    id = "zh-CN-XiaoxiaoNeural",
                    type = "Female",
                    labels = buildLabelPair("晓晓", "Xiaoxiao"),
                    styles = {},
                    multilingual = {},
                },
            },
        }
        azure.voiceTypes.Female = { labels = mapGenderLabel("Female") }
        azure.voiceTypeOrder = { "Female" }
    end

    if #azure.voiceTypeOrder == 0 then
        azure.voiceTypeOrder = { "Neutral" }
        azure.voiceTypes.Neutral = { labels = mapGenderLabel("Neutral") }
    end

    azure.voiceTypesList = {}
    for _, typeId in ipairs(azure.voiceTypeOrder) do
        local typeEntry = azure.voiceTypes[typeId]
        if typeEntry then
            table.insert(azure.voiceTypesList, { id = typeId, labels = typeEntry.labels })
        end
    end
    azure.languageTranslations = {}
    for k, v in pairs(LOCALE_NAME_LABELS) do
        if v and v.cn then
            azure.languageTranslations[k] = v.cn
        end
    end

    local minimax = Config.MiniMax
    minimax.models = {}
    for _, id in ipairs(MINIMAX_MODELS) do
        table.insert(minimax.models, { id = id, labels = buildLabelPair(id, id) })
    end

    minimax.soundEffects = {}
    for _, entry in ipairs(MINIMAX_SOUND_EFFECTS) do
        table.insert(minimax.soundEffects, { id = entry.id, labels = buildLabelPair(entry.cn, entry.en) })
    end

    minimax.emotions = {}
    for _, entry in ipairs(MINIMAX_EMOTIONS) do
        table.insert(minimax.emotions, { id = entry.id, labels = buildLabelPair(entry.cn, entry.en) })
    end

    minimax.languages = {}
    minimax.voices = {}
    local languageOrder = {}
    local languageSeen = {}
    minimax.cloneMap = {}
    minimax.cloneLangCounts = {}
    minimax.voiceFilePath = voicesListPath

    local function ensureLanguageEntry(lang)
        if not minimax.voices[lang] then
            minimax.voices[lang] = {}
        end
        if not languageSeen[lang] then
            table.insert(languageOrder, lang)
            languageSeen[lang] = true
        end
        if minimax.cloneLangCounts[lang] == nil then
            minimax.cloneLangCounts[lang] = 0
        end
        return minimax.voices[lang]
    end

    local function appendVoices(list, options)
        options = options or {}
        local isClone = options.isClone
        for _, voice in ipairs(list or {}) do
            local lang = voice.language or "Unknown"
            local voiceList = ensureLanguageEntry(lang)
            local entry = {
                id = voice.voice_id,
                labels = buildLabelPair(voice.voice_name or voice.voice_id, voice.voice_name or voice.voice_id),
                isClone = isClone and true or nil,
            }
            if isClone then
                local insertAt = (minimax.cloneLangCounts[lang] or 0) + 1
                table.insert(voiceList, insertAt, entry)
                minimax.cloneLangCounts[lang] = insertAt
                if voice.voice_id then
                    minimax.cloneMap[voice.voice_id] = lang
                end
            else
                table.insert(voiceList, entry)
            end
        end
    end

    appendVoices(minimaxVoicesData.minimax_clone_voices or {}, { isClone = true })
    appendVoices(minimaxVoicesData.minimax_system_voice or {})
    appendVoices(minimaxVoicesData.minimax_system_voice_en or {})

    if #languageOrder == 0 then
        languageOrder = { "中文（普通话）" }
        minimax.voices[languageOrder[1]] = {
            { id = "default_voice", labels = buildLabelPair("默认音色", "Default Voice") },
        }
    end

    for _, lang in ipairs(languageOrder) do
        table.insert(minimax.languages, { id = lang, labels = buildLabelPair(lang, lang) })
    end

    minimax.cloneDefaults = {
        onlyAddId = true,
        needNoiseReduction = false,
        needVolumeNormalization = false,
        previewText = "",
        displayInfo = Config.Settings.cloneInfo.cn or "",
    }

    minimax.defaults = {
        apiKey = settings.minimax_API_KEY or "",
        groupId = settings.minimax_GROUP_ID or "",
        intl = settings.minimax_intlCheckBox or false,
        modelIndex = clampIndex(settings.minimax_Model or 0, #minimax.models),
        languageIndex = clampIndex(settings.minimax_Language or 0, #minimax.languages),
        voiceIndex = settings.minimax_Voice or 0,
        emotionIndex = clampIndex(settings.minimax_Emotion or 0, #minimax.emotions),
        soundEffectIndex = clampIndex(settings.minimax_VoiceEffect or 0, #minimax.soundEffects),
        voiceTimbre = settings.minimax_VoiceTimbre or 0,
        voiceIntensity = settings.minimax_VoiceIntensity or 0,
        voicePitch = settings.minimax_VoicePitch or 0,
        rate = settings.minimax_Rate or 1.0,
        volume = settings.minimax_Volume or 1.0,
        pitch = settings.minimax_Pitch or 0,
        subtitle = settings.minimax_SubtitleCheckBox or false,
        breakMs = settings.minimax_Break or 50,
    }

    local openai = Config.OpenAI
    openai.models = {}
    for _, id in ipairs(OPENAI_MODELS) do
        table.insert(openai.models, { id = id, labels = buildLabelPair(id, id) })
    end

    openai.voices = {}
    for _, voiceId in ipairs((openaiVoicesData or {}).voices or {}) do
        table.insert(openai.voices, { id = voiceId, labels = buildLabelPair(voiceId, voiceId) })
    end
    if #openai.voices == 0 then
        openai.voices = {
            { id = "alloy", labels = buildLabelPair("alloy", "alloy") },
        }
    end

    local instructionData = Utils.readJson(Paths.inConfig("instruction.json")) or {}
    openai.presets = {}
    openai.presetMap = {}
    for presetName, presetInfo in Utils.iterObject(instructionData) do
        local description = ""
        if type(presetInfo) == "table" then
            description = presetInfo.Description or ""
        end
        local entry = {
            id = presetName,
            labels = buildLabelPair(presetName, presetName),
            description = description,
        }
        table.insert(openai.presets, entry)
        openai.presetMap[presetName] = entry
    end
    if #openai.presets == 0 then
        local entry = { id = "Custom", labels = buildLabelPair("Custom", "Custom"), description = "" }
        openai.presets = { entry }
        openai.presetMap = { Custom = entry }
    end

    openai.defaults = {
        apiKey = settings.OpenAI_API_KEY or "",
        baseUrl = settings.OpenAI_BASE_URL or "",
        modelIndex = clampIndex(settings.OpenAI_Model or 0, #openai.models),
        voiceIndex = clampIndex(settings.OpenAI_Voice or 0, #openai.voices),
        presetIndex = clampIndex(settings.OpenAI_Preset or 0, #openai.presets),
        rate = settings.OpenAI_Rate or 1.0,
        instruction = settings.OpenAI_Instruction or "",
    }

    Config.Settings.defaults = {
        outputPath = Config.Settings.outputPath,
        locale = Config.Settings.locale,
        copyright = "关注公众号：游艺所\\n\\n>>>点击查看更多信息<<<\\n\\n© 2024, Copyright by HB.",
        outputFormatIndex = clampIndex(settings.OUTPUT_FORMATS or 0, #SHARED_FORMATS),
    }

    local useApiSetting = settings.USE_API
    if useApiSetting == nil then
        local legacyDisable = settings.UNUSE_API
        if legacyDisable ~= nil then
            useApiSetting = not legacyDisable
        else
            useApiSetting = false
        end
    end
    Config.Azure.defaults = {
        apiKey = settings.API_KEY or "",
        region = settings.REGION or "",
        useApi = useApiSetting and true or false,
        languageIndex = clampIndex(settings.LANGUAGE or 0, #azure.languageOrder),
        voiceTypeIndex = clampIndex(settings.TYPE or 0, #azure.voiceTypeOrder),
        voiceIndex = settings.NAME or 0,
        styleIndex = settings.STYLE or 0,
        multilingualIndex = settings.MULTILINGUAL or 0,
        breakMs = settings.BREAKTIME or settings.BREAK or 50,
        styleDegree = settings.STYLEDEGREE or 1.0,
        rate = settings.RATE or 1.0,
        pitch = settings.PITCH or 1.0,
        volume = settings.VOLUME or 1.0,
        outputFormatIndex = clampIndex(Config.Settings.defaults.outputFormatIndex or 0, #azure.outputFormats),
    }
end

Config.load()

App.State.locale = Config.Settings.locale or "en"

local SCREEN_WIDTH = 1920
local SCREEN_HEIGHT = 1080
local WINDOW_WIDTH = 850
local WINDOW_HEIGHT = 450
local X_CENTER = math.floor((SCREEN_WIDTH - WINDOW_WIDTH) / 2)
local Y_CENTER = math.floor((SCREEN_HEIGHT - WINDOW_HEIGHT) / 2)

local resolve = resolve or Resolve()
if not resolve then
    error("Resolve application is not available.")
end

local fusion = fu or resolve:Fusion()
if not fusion then
    error("Fusion context unavailable.")
end

local ui = fusion.UIManager
local dispatcher = bmd.UIDispatcher(ui)

local loadingWin = dispatcher:AddWindow({
    ID = "LoadingWin",
    WindowTitle = "Loading",
    Geometry = { X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT },
    Spacing = 10,
    StyleSheet = "*{font-size:14px;}",
}, ui:VGroup{
    Weight = 1,
    ui:Label{
        ID = "UpdateLabel",
        Text = "",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        WordWrap = true,
        Visible = false,
        StyleSheet = "color:#bbb; font-size:20px;",
    },
    ui:Label{
        ID = "LoadLabel",
        Text = "Loading...",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
    },
    ui:HGroup{
        Weight = 0,
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        ui:Button{
            ID = "ConfirmButton",
            Text = "OK",
            Visible = false,
            Enabled = false,
            MinimumSize = { 80, 28 },
        },
    },
})

loadingWin:Show()

local msgbox = dispatcher:AddWindow({
    ID = "MsgBox",
    WindowTitle = "Info",
    Geometry = { 750, 400, 350, 100 },
    Spacing = 10,
}, ui:VGroup{
    Weight = 1,
    ui:Label{
        ID = "InfoLabel",
        Text = "",
        Alignment = { AlignCenter = true },
        WordWrap = true,
    },
    ui:HGroup{
        Weight = 0,
        Alignment = { AlignHCenter = true },
        ui:Button{
            ID = "OkButton",
            Text = "OK",
        },
    },
})

local win = dispatcher:AddWindow({
    ID = "MainWin",
    WindowTitle = SCRIPT_NAME .. SCRIPT_VERSION,
    Geometry = { X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT },
    Spacing = 10,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    Weight = 1,
    ui:TabBar{
        ID = "MyTabs",
        Weight = 0,
    },
    ui:Stack{
        ID = "MyStack",
        Weight = 1,
        ui:VGroup{
            ID = "Azure TTS",
            Weight = 1,
            ui:HGroup{
                Weight = 1,
                ui:VGroup{
                    Weight = 0.7,
                    ui:TextEdit{
                        ID = "azureText",
                        Text = "",
                        PlaceholderText = "",
                        Font = ui:Font{ PixelSize = 15 },
                        Weight = 0.9,
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "azureGetSubButton",
                            Text = "从时间线获取字幕",
                            Weight = 0.7,
                        },
                        ui:SpinBox{
                            ID = "azureBreakSpinBox",
                            Value = 50,
                            Minimum = 0,
                            Maximum = 5000,
                            SingleStep = 50,
                            Weight = 0.1,
                        },
                        ui:Label{
                            ID = "azureBreakLabel",
                            Text = "ms",
                            Weight = 0.1,
                        },
                        ui:Button{
                            ID = "azureBreakButton",
                            Text = "停顿",
                            Weight = 0.1,
                        },
                    },
                },
                ui:VGroup{
                    Weight = 1,
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureLanguageLabel",
                            Text = "语言",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "azureLanguageCombo",
                            Text = "",
                            MinimumSize = { 200, 20 },
                            MaximumSize = { 300, 50 },
                            Weight = 0.8,
                        },
                        ui:Label{
                            ID = "azureVoiceTypeLabel",
                            Text = "类型",
                            Alignment = { AlignRight = false },
                            Weight = 0,
                        },
                        ui:ComboBox{
                            ID = "azureVoiceTypeCombo",
                            Text = "",
                            Weight = 0,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureVoiceLabel",
                            Text = "名称",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "azureVoiceCombo",
                            Text = "",
                            MinimumSize = { 200, 20 },
                            MaximumSize = { 400, 50 },
                            Weight = 0.8,
                        },
                        ui:Button{
                            ID = "azurePlayButton",
                            Text = "播放预览",
                            Weight = 0,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureMultilingualLabel",
                            Text = "语言技能",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "azureMultilingualCombo",
                            Text = "",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureStyleLabel",
                            Text = "风格",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "azureStyleCombo",
                            Text = "",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureStyleDegreeLabel",
                            Text = "风格强度",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "azureStyleDegreeSlider",
                            Value = 100,
                            Minimum = 0,
                            Maximum = 200,
                            Orientation = "Horizontal",
                            Weight = 0.5,
                        },
                        ui:DoubleSpinBox{
                            ID = "azureStyleDegreeSpinBox",
                            Value = 1.0,
                            Minimum = 0.0,
                            Maximum = 2.0,
                            SingleStep = 0.01,
                            Weight = 0.3,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureRateLabel",
                            Text = "语速",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "azureRateSlider",
                            Value = 100,
                            Minimum = 0,
                            Maximum = 300,
                            Orientation = "Horizontal",
                            Weight = 0.5,
                        },
                        ui:DoubleSpinBox{
                            ID = "azureRateSpinBox",
                            Value = 1.0,
                            Minimum = 0.0,
                            Maximum = 3.0,
                            SingleStep = 0.01,
                            Weight = 0.3,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azurePitchLabel",
                            Text = "音高",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "azurePitchSlider",
                            Value = 100,
                            Minimum = 50,
                            Maximum = 150,
                            Orientation = "Horizontal",
                            Weight = 0.5,
                        },
                        ui:DoubleSpinBox{
                            ID = "azurePitchSpinBox",
                            Value = 1.0,
                            Minimum = 0.5,
                            Maximum = 1.5,
                            SingleStep = 0.01,
                            Weight = 0.3,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "azureVolumeLabel",
                            Text = "音量",
                            Alignment = { AlignRight = false },
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "azureVolumeSlider",
                            Value = 100,
                            Minimum = 0,
                            Maximum = 150,
                            Orientation = "Horizontal",
                            Weight = 0.5,
                        },
                        ui:DoubleSpinBox{
                            ID = "azureVolumeSpinBox",
                            Value = 1.0,
                            Minimum = 0.0,
                            Maximum = 1.5,
                            SingleStep = 0.01,
                            Weight = 0.3,
                        },
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "azureFromSubButton",
                            Text = "朗读当前字幕",
                        },
                        ui:Button{
                            ID = "azureFromTxtButton",
                            Text = "朗读文本框",
                        },
                        ui:Button{
                            ID = "azureResetButton",
                            Text = "重置",
                        },
                    },
                },
            },
        },
        ui:VGroup{
            ID = "Minimax TTS",
            Weight = 1,
            ui:HGroup{
                Weight = 1,
                ui:VGroup{
                    Weight = 0.7,
                    ui:TextEdit{
                        ID = "minimaxText",
                        PlaceholderText = "",
                        Weight = 0.9,
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "minimaxGetSubButton",
                            Text = "从时间线获取字幕",
                            Weight = 0.7,
                        },
                        ui:SpinBox{
                            ID = "minimaxBreakSpinBox",
                            Value = 50,
                            Minimum = 1,
                            Maximum = 9999,
                            SingleStep = 50,
                            Weight = 0.1,
                        },
                        ui:Label{
                            ID = "minimaxBreakLabel",
                            Text = "ms",
                            Weight = 0.1,
                        },
                        ui:Button{
                            ID = "minimaxBreakButton",
                            Text = "停顿",
                            Weight = 0.1,
                        },
                    },
                },
                ui:VGroup{
                    Weight = 1,
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxModelLabel",
                            Text = "模型:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "minimaxModelCombo",
                            Text = "选择模型",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxLanguageLabel",
                            Text = "语言:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "minimaxLanguageCombo",
                            Text = "选择语言",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxVoiceLabel",
                            Text = "音色:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "minimaxVoiceCombo",
                            Text = "选择人声",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Button{
                            ID = "minimaxPreviewButton",
                            Text = "试听",
                            Weight = 0.1,
                        },
                        ui:Button{
                            ID = "ShowMiniMaxClone",
                            Text = "",
                            Weight = 0.1,
                        },
                        ui:Button{
                            ID = "minimaxDeleteVoice",
                            Text = "",
                            Weight = 0.1,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Button{
                            ID = "minimaxVoiceEffectButton",
                            Text = "音色效果调节",
                            Weight = 1,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxEmotionLabel",
                            Text = "情绪:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "minimaxEmotionCombo",
                            Text = "",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxRateLabel",
                            Text = "速度:",
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "minimaxRateSlider",
                            Minimum = 50,
                            Maximum = 200,
                            Value = 100,
                            SingleStep = 1,
                            Weight = 0.6,
                        },
                        ui:DoubleSpinBox{
                            ID = "minimaxRateSpinBox",
                            Minimum = 0.50,
                            Maximum = 2.00,
                            Value = 1.00,
                            SingleStep = 0.01,
                            Decimals = 2,
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxVolumeLabel",
                            Text = "音量:",
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "minimaxVolumeSlider",
                            Minimum = 10,
                            Maximum = 1000,
                            Value = 100,
                            SingleStep = 1,
                            Weight = 0.6,
                        },
                        ui:DoubleSpinBox{
                            ID = "minimaxVolumeSpinBox",
                            Minimum = 0.10,
                            Maximum = 10.00,
                            Value = 1.00,
                            SingleStep = 0.01,
                            Decimals = 2,
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "minimaxPitchLabel",
                            Text = "音调:",
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "minimaxPitchSlider",
                            Minimum = -1200,
                            Maximum = 1200,
                            SingleStep = 1,
                            Weight = 0.6,
                        },
                        ui:SpinBox{
                            ID = "minimaxPitchSpinBox",
                            Minimum = -12,
                            Maximum = 12,
                            Value = 0,
                            SingleStep = 1,
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:CheckBox{
                            ID = "minimaxSubtitleCheckBox",
                            Text = "生成字幕",
                            Checked = false,
                            Alignment = { AlignLeft = true },
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "minimaxFromSubButton",
                            Text = "朗读当前字幕",
                        },
                        ui:Button{
                            ID = "minimaxFromTxtButton",
                            Text = "朗读文本框",
                        },
                        ui:Button{
                            ID = "minimaxResetButton",
                            Text = "重置",
                        },
                    },
                },
            },
        },
        ui:VGroup{
            ID = "OpenAI TTS",
            Weight = 1,
            ui:HGroup{
                Weight = 1,
                ui:VGroup{
                    Weight = 0.7,
                    ui:TextEdit{
                        ID = "OpenAIText",
                        PlaceholderText = "",
                        Weight = 0.9,
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "OpenAIGetSubButton",
                            Text = "从时间线获取字幕",
                            Weight = 0.7,
                        },
                    },
                },
                ui:VGroup{
                    Weight = 1,
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "OpenAIModelLabel",
                            Text = "模型:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "OpenAIModelCombo",
                            Text = "选择模型",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "OpenAIVoiceLabel",
                            Text = "音色:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "OpenAIVoiceCombo",
                            Text = "选择人声",
                            Weight = 0.6,
                        },
                        ui:Button{
                            ID = "OpenAIPreviewButton",
                            Text = "试听",
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "OpenAIPresetLabel",
                            Text = "预设:",
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "OpenAIPresetCombo",
                            Text = "预设",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "OpenAIInstructionLabel",
                            Text = "指令:",
                            Weight = 0.2,
                        },
                        ui:TextEdit{
                            ID = "OpenAIInstructionText",
                            PlaceholderText = "",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "OpenAIRateLabel",
                            Text = "速度:",
                            Weight = 0.2,
                        },
                        ui:Slider{
                            ID = "OpenAIRateSlider",
                            Minimum = 25,
                            Maximum = 400,
                            Value = 100,
                            SingleStep = 1,
                            Weight = 0.6,
                        },
                        ui:DoubleSpinBox{
                            ID = "OpenAIRateSpinBox",
                            Minimum = 0.25,
                            Maximum = 4.00,
                            Value = 1.00,
                            SingleStep = 0.01,
                            Decimals = 2,
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0,
                        ui:Button{
                            ID = "OpenAIFromSubButton",
                            Text = "朗读当前字幕",
                        },
                        ui:Button{
                            ID = "OpenAIFromTxtButton",
                            Text = "朗读文本框",
                        },
                        ui:Button{
                            ID = "OpenAIResetButton",
                            Text = "重置",
                        },
                    },
                },
            },
        },
        ui:HGroup{
            ID = "Config",
            Weight = 1,
            ui:VGroup{
                Weight = 0.5,
                Spacing = 10,
                ui:HGroup{
                    Weight = 1,
                    ui:TextEdit{
                        ID = "infoTxt",
                        Text = "",
                        ReadOnly = true,
                        Font = ui:Font{ PixelSize = 14 },
                    },
                },
            },
            ui:VGroup{
                Weight = 0.5,
                Spacing = 10,
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "PathLabel",
                            Text = "保存路径",
                        Alignment = { AlignLeft = true },
                        Weight = 0.2,
                    },
                    ui:LineEdit{
                        ID = "Path",
                        Text = "",
                        PlaceholderText = "",
                        ReadOnly = false,
                        Weight = 0.6,
                    },
                        ui:Button{
                            ID = "Browse",
                            Text = "浏览",
                            Weight = 0.2,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            ID = "outputFormatLabel",
                            Text = "输出格式",
                            Alignment = { AlignLeft = true },
                            Weight = 0.2,
                        },
                        ui:ComboBox{
                            ID = "outputFormatCombo",
                            Text = "Output_Format",
                            Weight = 0.8,
                        },
                    },
                    ui:HGroup{
                        Weight = 0.1,
                        ui:Label{
                            Text = "Azure API",
                        Alignment = { AlignLeft = true },
                        Weight = 0.1,
                    },
                    ui:Button{
                        ID = "ShowAzure",
                        Text = "配置",
                        Weight = 0.1,
                    },
                },
                ui:HGroup{
                    Weight = 0.1,
                    ui:Label{
                        Text = "MiniMax API",
                        Alignment = { AlignLeft = true },
                        Weight = 0.1,
                    },
                    ui:Button{
                        ID = "ShowMiniMax",
                        Text = "配置",
                        Weight = 0.1,
                    },
                },
                ui:HGroup{
                    Weight = 0.1,
                    ui:Label{
                        Text = "OpenAI API",
                        Alignment = { AlignLeft = true },
                        Weight = 0.1,
                    },
                    ui:Button{
                        ID = "ShowOpenAI",
                        Text = "配置",
                        Weight = 0.1,
                    },
                },
                ui:HGroup{
                    Weight = 0.1,
                    ui:CheckBox{
                        ID = "LangEnCheckBox",
                        Text = "EN",
                        Checked = true,
                        Alignment = { AlignRight = true },
                        Weight = 0,
                    },
                    ui:CheckBox{
                        ID = "LangCnCheckBox",
                        Text = "简体中文",
                        Checked = false,
                        Alignment = { AlignRight = true },
                        Weight = 1,
                    },
                    ui:Button{
                        ID = "openGuideButton",
                        Text = "教程",
                        Weight = 0.1,
                    },
                },
                ui:Button{
                    ID = "CopyrightButton",
                    Text = "关注公众号：游艺所\n\n>>>点击查看更多信息<<<\n\n© 2024, Copyright by HB.",
                    Alignment = { AlignHCenter = true, AlignVCenter = true },
                    Font = ui:Font{ PixelSize = 12, StyleName = "Bold" },
                    Flat = true,
                    TextColor = { 0.1, 0.3, 0.9, 1 },
                    BackgroundColor = { 1, 1, 1, 0 },
                    Weight = 0.8,
                },
            },
        },
    },
})

local azureConfigWin = dispatcher:AddWindow({
    ID = "AzureConfigWin",
    WindowTitle = "Azure API",
    Geometry = { 900, 400, 400, 200 },
    Hidden = true,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    ui:Label{
        ID = "AzureLabel",
        Text = "填写Azure API信息",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            ID = "RegionLabel",
            Text = "区域",
            Alignment = { AlignRight = false },
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "Region",
            Text = "",
            Weight = 0.8,
        },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            ID = "ApiKeyLabel",
            Text = "密钥",
            Alignment = { AlignRight = false },
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "ApiKey",
            Text = "",
            EchoMode = "Password",
            Weight = 0.8,
        },
    },
    ui:CheckBox{
        ID = "UseAPICheckBox",
        Text = "Use API",
        Checked = true,
        Alignment = { AlignLeft = true },
        Weight = 0.1,
    },
    ui:HGroup{
        Weight = 1,
        ui:Button{
            ID = "AzureConfirm",
            Text = "确定",
            Weight = 1,
        },
        ui:Button{
            ID = "AzureRegisterButton",
            Text = "注册",
            Weight = 1,
        },
    },
})

local openaiConfigWin = dispatcher:AddWindow({
    ID = "OpenAIConfigWin",
    WindowTitle = "OpenAI API",
    Geometry = { 900, 400, 400, 200 },
    Hidden = true,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    ui:Label{
        ID = "OpenAILabel",
        Text = "填写OpenAI API信息",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            ID = "OpenAIBaseURLLabel",
            Text = "Base URL",
            Alignment = { AlignRight = false },
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "OpenAIBaseURL",
            Text = "",
            PlaceholderText = "https://api.openai.com",
            Weight = 0.8,
        },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            ID = "OpenAIApiKeyLabel",
            Text = "密钥",
            Alignment = { AlignRight = false },
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "OpenAIApiKey",
            Text = "",
            EchoMode = "Password",
            Weight = 0.8,
        },
    },
    ui:HGroup{
        Weight = 1,
        ui:Button{
            ID = "OpenAIConfirm",
            Text = "确定",
            Weight = 1,
        },
        ui:Button{
            ID = "OpenAIRegisterButton",
            Text = "注册",
            Weight = 1,
        },
    },
})

local minimaxConfigWin = dispatcher:AddWindow({
    ID = "MiniMaxConfigWin",
    WindowTitle = "MiniMax API",
    Geometry = { 900, 400, 400, 200 },
    Hidden = true,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    ui:Label{
        ID = "minimaxLabel",
        Text = "填写MiniMax API信息",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            Text = "GroupID",
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "minimaxGroupID",
            Weight = 0.8,
        },
    },
    ui:HGroup{
        Weight = 1,
        ui:Label{
            ID = "minimaxApiKeyLabel",
            Text = "密钥",
            Weight = 0.2,
        },
        ui:LineEdit{
            ID = "minimaxApiKey",
            EchoMode = "Password",
            Weight = 0.8,
        },
    },
    ui:CheckBox{
        ID = "intlCheckBox",
        Text = "海外",
        Checked = false,
        Alignment = { AlignLeft = true },
        Weight = 0.1,
    },
    ui:HGroup{
        Weight = 1,
        ui:Button{
            ID = "MiniMaxConfirm",
            Text = "确定",
            Weight = 1,
        },
        ui:Button{
            ID = "minimaxRegisterButton",
            Text = "注册",
            Weight = 1,
        },
    },
})

local minimaxCloneWin = dispatcher:AddWindow({
    ID = "MiniMaxCloneWin",
    WindowTitle = "MiniMax Clone",
    Geometry = { X_CENTER, Y_CENTER, 600, 420 },
    Hidden = true,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    ui:HGroup{
        Weight = 0.1,
        ui:Label{
            ID = "minimaxCloneLabel",
            Text = "MiniMax 克隆音色",
            Alignment = { AlignHCenter = true, AlignVCenter = true },
            Weight = 0.1,
        },
    },
    ui:HGroup{
        Weight = 1,
        ui:VGroup{
            Weight = 1,
            Spacing = 10,
            ui:CheckBox{
                ID = "minimaxOnlyAddID",
                Text = "已有克隆音色",
                Checked = true,
                Alignment = { AlignRight = true },
                Weight = 0.1,
            },
            ui:HGroup{
                Weight = 0.1,
                ui:Label{
                    ID = "minimaxCloneVoiceNameLabel",
                    Text = "Name",
                    Weight = 0.2,
                },
                ui:LineEdit{
                    ID = "minimaxCloneVoiceName",
                    Weight = 0.8,
                },
            },
            ui:HGroup{
                Weight = 0.1,
                ui:Label{
                    ID = "minimaxCloneVoiceIDLabel",
                    Text = "ID",
                    Weight = 0.2,
                },
                ui:LineEdit{
                    ID = "minimaxCloneVoiceID",
                    Weight = 0.8,
                },
            },
            ui:HGroup{
                Weight = 0.1,
                ui:Label{
                    ID = "minimaxCloneFileIDLabel",
                    Text = "File ID",
                    Weight = 0.2,
                },
                ui:LineEdit{
                    ID = "minimaxCloneFileID",
                    Enabled = false,
                    Weight = 0.8,
                },
            },
            ui:HGroup{
                Weight = 0.1,
                ui:CheckBox{
                    ID = "minimaxNeedNoiseReduction",
                    Text = "是否开启降噪",
                    Checked = false,
                    Alignment = { AlignLeft = true },
                    Weight = 0.1,
                },
                ui:CheckBox{
                    ID = "minimaxNeedVolumeNormalization",
                    Text = "音量归一化",
                    Checked = false,
                    Alignment = { AlignLeft = true },
                    Weight = 0.1,
                },
            },
            ui:Label{
                ID = "minimaxClonePreviewLabel",
                Text = "输入试听文本(限制300字以内)：",
                Weight = 0.2,
            },
            ui:TextEdit{
                ID = "minimaxClonePreviewText",
                Text = "",
            },
        },
        ui:VGroup{
            Weight = 1,
            Spacing = 10,
            ui:HGroup{
                Weight = 1,
                ui:TextEdit{
                    ID = "minimaxcloneinfoTxt",
                    Text = "",
                    ReadOnly = true,
                    Font = ui:Font{ PixelSize = 14 },
                },
            },
        },
    },
    ui:HGroup{
        Weight = 0.1,
        ui:Label{
            ID = "minimaxCloneStatus",
            Text = "",
            Weight = 0.2,
        },
    },
    ui:HGroup{
        Weight = 0.1,
        ui:Button{
            ID = "MiniMaxCloneConfirm",
            Text = "添加",
            Weight = 1,
        },
        ui:Button{
            ID = "MiniMaxCloneCancel",
            Text = "取消",
            Weight = 1,
        },
    },
})

local minimaxVoiceModifyWin = dispatcher:AddWindow({
    ID = "MiniMaxVoiceModifyWin",
    WindowTitle = "MiniMax Effect",
    Geometry = { X_CENTER, Y_CENTER, 320, 320 },
    Hidden = true,
    StyleSheet = [[
        * {
            font-size: 14px;
        }
    ]],
}, ui:VGroup{
    ui:Label{
        ID = "minimaxVoiceModifyTitle",
        Text = "音色效果调节",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
    },
    ui:VGroup{
        Weight = 1,
        Spacing = 8,
        ui:VGroup{
            Weight = 0,
            ui:Label{
                ID = "minimaxTimbreLabel",
                Text = "低沉 / 明亮",
                Alignment = { AlignLeft = true },
            },
            ui:HGroup{
                ui:SpinBox{
                    ID = "minimaxTimbreSpinBoxLeft",
                    Minimum = -100,
                    Maximum = 0,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                },
                ui:Slider{
                    ID = "minimaxTimbreSlider",
                    Minimum = -100,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Orientation = "Horizontal",
                    Weight = 0.4,
                },
                ui:SpinBox{
                    ID = "minimaxTimbreSpinBoxRight",
                    Minimum = 0,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                    Prefix = "+",
                },
            },
        },
        ui:VGroup{
            Weight = 0,
            ui:Label{
                ID = "minimaxIntensityLabel",
                Text = "力量感 / 柔和",
                Alignment = { AlignLeft = true },
            },
            ui:HGroup{
                ui:SpinBox{
                    ID = "minimaxIntensitySpinBoxLeft",
                    Minimum = -100,
                    Maximum = 0,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                },
                ui:Slider{
                    ID = "minimaxIntensitySlider",
                    Minimum = -100,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Orientation = "Horizontal",
                    Weight = 0.4,
                },
                ui:SpinBox{
                    ID = "minimaxIntensitySpinBoxRight",
                    Minimum = 0,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                    Prefix = "+",
                },
            },
        },
        ui:VGroup{
            Weight = 0,
            ui:Label{
                ID = "minimaxModifyPitchLabel",
                Text = "磁性 / 清脆",
                Alignment = { AlignLeft = true },
            },
            ui:HGroup{
                ui:SpinBox{
                    ID = "minimaxModifyPitchSpinBoxLeft",
                    Minimum = -100,
                    Maximum = 0,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                },
                ui:Slider{
                    ID = "minimaxModifyPitchSlider",
                    Minimum = -100,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Orientation = "Horizontal",
                    Weight = 0.4,
                },
                ui:SpinBox{
                    ID = "minimaxModifyPitchSpinBoxRight",
                    Minimum = 0,
                    Maximum = 100,
                    Value = 0,
                    SingleStep = 1,
                    Weight = 0.2,
                    Prefix = "+",
                },
            },
        },
        ui:HGroup{
            ui:Label{
                ID = "minimaxSoundEffectLabel",
                Text = "音效:",
                Weight = 0.2,
            },
            ui:ComboBox{
                ID = "minimaxSoundEffectCombo",
                Text = "",
                Weight = 0.8,
            },
        },
    },
    ui:HGroup{
        Weight = 0,
        ui:Button{
            ID = "MiniMaxVoiceModifyConfirm",
            Text = "确定",
            Weight = 1,
        },
        ui:Button{
            ID = "MiniMaxVoiceModifyCancel",
            Text = "取消",
            Weight = 1,
        },
    },
})

local items = win:GetItems()
local msgboxItems = msgbox:GetItems()
local azureConfigItems = azureConfigWin:GetItems()
local openaiConfigItems = openaiConfigWin:GetItems()
local minimaxConfigItems = minimaxConfigWin:GetItems()
local minimaxCloneItems = minimaxCloneWin:GetItems()
local minimaxVoiceModifyItems = minimaxVoiceModifyWin:GetItems()
local loadingItems = loadingWin:GetItems()

App.State.azure = {}
App.State.minimax = {}
App.State.openai = {}

App.UI.items = items
App.UI.msgboxItems = msgboxItems
App.UI.azureItems = azureConfigItems
App.UI.openaiItems = openaiConfigItems
App.UI.minimaxItems = minimaxConfigItems
App.UI.minimaxCloneItems = minimaxCloneItems
App.UI.minimaxVoiceModifyItems = minimaxVoiceModifyItems
App.UI.loadingItems = loadingItems

-- Throttle slider/spin synchronization so rapid key repeats do not flood the UI loop.
local sliderSyncLastUpdates = {}
local SLIDER_SYNC_INTERVAL = 0.1

local function monotonicTime()
    if type(bmd) == "table" then
        if type(bmd.gettime) == "function" then
            local ok, value = pcall(bmd.gettime)
            if ok and type(value) == "number" then
                return value
            end
        end
        if type(bmd.ftime) == "function" then
            local ok, value = pcall(bmd.ftime)
            if ok and type(value) == "number" then
                return value
            end
        end
    end
    return os.clock()
end

local function shouldProcessSliderSync(key, interval)
    interval = interval or SLIDER_SYNC_INTERVAL
    local now = monotonicTime()
    local last = sliderSyncLastUpdates[key] or 0
    if now - last < interval then
        return false
    end
    sliderSyncLastUpdates[key] = now
    return true
end

local function eventNumericValue(ev)
    if not ev then
        return nil
    end
    if ev.Value ~= nil then
        return tonumber(ev.Value)
    end
    if type(ev) == "table" then
        local value = ev["Value"]
        if value ~= nil then
            return tonumber(value)
        end
    end
    return nil
end

local sliderLocks = {}

local function roundTo(value, decimals)
    if decimals == nil or decimals < 0 then
        return value
    end
    local factor = 10 ^ decimals
    return math.floor(value * factor + 0.5) / factor
end

local function controlMinMax(control)
    if not control then
        return nil, nil
    end
    local minValue = control.Minimum
    local maxValue = control.Maximum
    if minValue ~= nil then
        minValue = tonumber(minValue)
    end
    if maxValue ~= nil then
        maxValue = tonumber(maxValue)
    end
    return minValue, maxValue
end

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        value = minValue
    end
    if maxValue ~= nil and value > maxValue then
        value = maxValue
    end
    return value
end

local function clampToControl(value, control)
    local minValue, maxValue = controlMinMax(control)
    return clamp(value, minValue, maxValue)
end

-- forward declaration for safe setter used below
local setValueSafe

-- MiniMax voice modify helpers (timbre/intensity/pitch + effect selection)
local VOICE_MODIFY_WIDGETS = {
    timbre = {
        slider = "minimaxTimbreSlider",
        left = "minimaxTimbreSpinBoxLeft",
        right = "minimaxTimbreSpinBoxRight",
    },
    intensity = {
        slider = "minimaxIntensitySlider",
        left = "minimaxIntensitySpinBoxLeft",
        right = "minimaxIntensitySpinBoxRight",
    },
    pitch = {
        slider = "minimaxModifyPitchSlider",
        left = "minimaxModifyPitchSpinBoxLeft",
        right = "minimaxModifyPitchSpinBoxRight",
    },
}

local voiceModifySyncing = false
local voiceModifySnapshot = nil
local voiceModifyLastUpdates = {
    timbre = 0,
    intensity = 0,
    pitch = 0,
}
local VOICE_MODIFY_UPDATE_INTERVAL = 0.1

local function clampVoiceModify(value)
    value = tonumber(value) or 0
    if value > 100 then
        value = 100
    elseif value < -100 then
        value = -100
    end
    return value
end

local function setVoiceModifyValue(name, value)
    if not App.UI.minimaxVoiceModifyItems then
        return
    end
    local widgets = VOICE_MODIFY_WIDGETS[name]
    if not widgets then
        return
    end
    local items = App.UI.minimaxVoiceModifyItems
    value = clampVoiceModify(value)
    voiceModifySyncing = true
    setValueSafe(items[widgets.slider], value)
    setValueSafe(items[widgets.left], value < 0 and value or 0)
    setValueSafe(items[widgets.right], value > 0 and value or 0)
    voiceModifySyncing = false
    local state = App.State.minimax or {}
    if name == "timbre" then
        state.voiceTimbre = value
    elseif name == "intensity" then
        state.voiceIntensity = value
    elseif name == "pitch" then
        state.voicePitch = value
    end
end

local function getVoiceModifyState()
    local state = App.State.minimax or {}
    return {
        timbre = state.voiceTimbre or 0,
        intensity = state.voiceIntensity or 0,
        pitch = state.voicePitch or 0,
        soundEffectIndex = state.voiceEffectIndex or state.soundEffectIndex or 0,
    }
end

local function applyVoiceModifyState(newState)
    if not newState then
        return
    end
    setVoiceModifyValue("timbre", newState.timbre or 0)
    setVoiceModifyValue("intensity", newState.intensity or 0)
    setVoiceModifyValue("pitch", newState.pitch or 0)
    if App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo then
        App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo.CurrentIndex = newState.soundEffectIndex or 0
    end
    local state = App.State.minimax or {}
    state.voiceEffectIndex = newState.soundEffectIndex or 0
end

local function syncVoiceModifyFromControl(name, senderId, value)
    if voiceModifySyncing then
        return
    end
    if not App.UI.minimaxVoiceModifyItems then
        return
    end
    local widgets = VOICE_MODIFY_WIDGETS[name]
    if not widgets then
        return
    end
    local now = monotonicTime()
    if now - (voiceModifyLastUpdates[name] or 0) < VOICE_MODIFY_UPDATE_INTERVAL then
        return
    end
    voiceModifyLastUpdates[name] = now
    value = clampVoiceModify(value)
    voiceModifySyncing = true
    if senderId ~= widgets.slider then
        setValueSafe(App.UI.minimaxVoiceModifyItems[widgets.slider], value)
    end
    if senderId ~= widgets.left then
        setValueSafe(App.UI.minimaxVoiceModifyItems[widgets.left], value < 0 and value or 0)
    end
    if senderId ~= widgets.right then
        setValueSafe(App.UI.minimaxVoiceModifyItems[widgets.right], value > 0 and value or 0)
    end
    voiceModifySyncing = false
    local state = App.State.minimax or {}
    if name == "timbre" then
        state.voiceTimbre = value
    elseif name == "intensity" then
        state.voiceIntensity = value
    elseif name == "pitch" then
        state.voicePitch = value
    end
end

local function onShowVoiceModifyWindow()
    voiceModifySnapshot = getVoiceModifyState()
    applyVoiceModifyState(voiceModifySnapshot)
    if minimaxVoiceModifyWin and minimaxVoiceModifyWin.Show then
        minimaxVoiceModifyWin:Show()
    end
end

local function onVoiceModifyConfirm()
    if App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo then
        App.State.minimax.voiceEffectIndex = App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo.CurrentIndex or 0
    end
    if minimaxVoiceModifyWin and minimaxVoiceModifyWin.Hide then
        minimaxVoiceModifyWin:Hide()
    end
end

local function onVoiceModifyCancel()
    if voiceModifySnapshot then
        applyVoiceModifyState(voiceModifySnapshot)
    end
    if minimaxVoiceModifyWin and minimaxVoiceModifyWin.Hide then
        minimaxVoiceModifyWin:Hide()
    end
end

local function handleVoiceModifyEffectChange(ev)
    if not App.UI.minimaxVoiceModifyItems then
        return
    end
    App.State.minimax.voiceEffectIndex = App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo.CurrentIndex or 0
end

local function logInfo(message)
    print(string.format("[DaVinci TTS] %s", message))
end

local function sleepSeconds(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return
    end
    if bmd and type(bmd.wait) == "function" then
        bmd.wait(seconds)
        return
    end
    if IS_WINDOWS then
        local millis = math.max(1, math.floor(seconds * 1000 + 0.5))
        local command = string.format('powershell -Command "Start-Sleep -Milliseconds %d"', millis)
        os.execute(command)
    else
        os.execute(string.format("sleep %.3f", seconds))
    end
end

local function openUrl(url)
    if not url or url == "" then
        return false
    end
    if bmd and type(bmd.openurl) == "function" then
        local ok = pcall(bmd.openurl, url)
        if ok then
            return true
        end
    end
    local command
    if IS_WINDOWS then
        command = string.format('start "" "%s"', url)
    elseif PATH_SEP == "/" then
        command = string.format('open "%s"', url)
    else
        command = string.format('xdg-open "%s"', url)
    end
    return runShellCommand(command)
end

local function withSliderLock(key, fn)
    if sliderLocks[key] then
        return
    end
    sliderLocks[key] = true
    local ok, err = pcall(fn)
    if not ok then
        logInfo(string.format("Slider sync error (%s): %s", tostring(key), tostring(err)))
    end
    sliderLocks[key] = nil
end

local function setCheckedSafe(control, value)
    if control then
        control.Checked = value and true or false
    end
end

setValueSafe = function(control, value)
    if control and value ~= nil then
        control.Value = value
    end
end

local function buildSliderSyncHandler(key, targetId, multiplier, decimals, interval)
    decimals = decimals or 0
    local tolerance = decimals > 0 and (0.5 / (10 ^ decimals)) or 0.5
    interval = interval or SLIDER_SYNC_INTERVAL
    return function(ev)
        if sliderLocks[key] then
            return
        end
        local numericValue = eventNumericValue(ev)
        if numericValue == nil then
            return
        end
        local target = items[targetId]
        if not target then
            return
        end
        local converted = numericValue * multiplier
        if decimals > 0 then
            converted = roundTo(converted, decimals)
        else
            converted = math.floor(converted + 0.5)
        end
        converted = clampToControl(converted, target)
        local current = target.Value
        if current ~= nil and math.abs(current - converted) < tolerance then
            return
        end
        if not shouldProcessSliderSync(key, interval) then
            return
        end
        withSliderLock(key, function()
            setValueSafe(target, converted)
        end)
    end
end

function App.UI.localizeLabel(value)
    if type(value) == "table" then
        local locale = App.State.locale or "en"
        return value[locale] or value.en or value.cn or ""
    end
    return tostring(value)
end

local function getFirstEntry(entries)
    return entries and entries[1] or nil
end

local function scaledValue(value, scale)
    return math.floor(((value or 0) * scale) + 0.5)
end

local function setTextSafe(control, value)
    if control then
        control.Text = value or ""
    end
end



local function insertPlainTextSafe(control, text)
    if not control or not text or text == "" then
        return
    end
    if control.InsertPlainText then
        control:InsertPlainText(text)
    else
        local existing = control.Text or ""
        control.Text = existing .. text
    end
end

local function formatBreakSeconds(seconds)
    if not seconds then
        return "0"
    end
    local formatted = string.format("%.3f", seconds)
    formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    if formatted == "" then
        formatted = "0"
    end
    return formatted
end

local function readCurrentIndex(control, defaultValue)
    if control and control.CurrentIndex ~= nil then
        return control.CurrentIndex
    end
    return defaultValue or 0
end

local function readValue(control, defaultValue)
    if control and control.Value ~= nil then
        return control.Value
    end
    return defaultValue or 0
end

local function readChecked(control, defaultValue)
    if control and control.Checked ~= nil then
        return control.Checked and true or false
    end
    return defaultValue and true or false
end

local function readText(control)
    if not control then
        return ""
    end
    if control.Text ~= nil then
        return control.Text
    end
    if control.PlainText ~= nil then
        return control.PlainText
    end
    return ""
end

local function readPlainTextSafe(control)
    if not control then
        return ""
    end
    if control.PlainText ~= nil then
        return control.PlainText
    end
    if control.Text ~= nil then
        return control.Text
    end
    return ""
end

local function truncateForLog(str, limit)
    if type(str) ~= "string" then
        return tostring(str)
    end
    limit = limit or 800
    if #str <= limit then
        return str
    end
    return string.format("%s... (total %d chars)", str:sub(1, limit), #str)
end












local function setVisibleSafe(control, value)
    if control ~= nil then
        control.Visible = value and true or false
    end
end

local function setEnabledSafe(control, value)
    if control ~= nil then
        control.Enabled = value and true or false
    end
end



local function toLittleEndian(value, bytes)
    local parts = {}
    for i = 1, bytes do
        parts[i] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(parts)
end

function Utils.createDummyAudioFile(seconds)
    seconds = seconds or 1
    local ok, tmpName = pcall(os.tmpname)
    if not ok then
        return nil, tmpName
    end
    local path = tmpName .. ".wav"
    local sampleRate = 44100
    local numChannels = 1
    local bitsPerSample = 16
    local bytesPerSample = bitsPerSample / 8
    local numSamples = math.max(1, math.floor(sampleRate * seconds))
    local dataSize = numSamples * numChannels * bytesPerSample
    local chunkSize = 36 + dataSize
    local byteRate = sampleRate * numChannels * bytesPerSample
    local blockAlign = numChannels * bytesPerSample
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err
    end
    local function write(str)
        file:write(str)
    end
    write("RIFF")
    write(toLittleEndian(chunkSize, 4))
    write("WAVE")
    write("fmt ")
    write(toLittleEndian(16, 4))
    write(toLittleEndian(1, 2))
    write(toLittleEndian(numChannels, 2))
    write(toLittleEndian(sampleRate, 4))
    write(toLittleEndian(byteRate, 4))
    write(toLittleEndian(blockAlign, 2))
    write(toLittleEndian(bitsPerSample, 2))
    write("data")
    write(toLittleEndian(dataSize, 4))
    write(string.rep(string.char(0), dataSize))
    file:close()
    return path, {
        durationSeconds = numSamples / sampleRate,
        durationSamples = numSamples,
        sampleRate = sampleRate,
    }
end

local providerSecretCache = App.State.providerSecrets or {}
App.State.providerSecrets = providerSecretCache

local function localizedText(cnText, enText)
    if App.State.locale == "cn" then
        return cnText or enText
    end
    return enText or cnText
end

local function fetch_provider_secret(provider)
    local cleanProvider = trim(provider or "")
    if cleanProvider == "" then
        return nil, "missing_provider"
    end
    local cached = providerSecretCache[cleanProvider]
    if cached ~= nil then
        return cached
    end
    local encoder = (Utils and Utils.urlEncode) or function(text)
        return tostring(text or ""):gsub("[^%w%-%._~]", function(ch)
            return string.format("%%%02X", string.byte(ch))
        end)
    end
    local url = string.format("%s/functions/v1/getApiKey?provider=%s", SUPABASE_URL, encoder(cleanProvider))
    local headers = {
        Authorization = "Bearer " .. SUPABASE_ANON_KEY,
        apikey = SUPABASE_ANON_KEY,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
    }
    local body, status = Services.httpGet(url, headers, SUPABASE_TIMEOUT)
    if not body then
        return nil, status or "request_failed"
    end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, "decode_failed"
    end
    local apiKey = decoded.api_key or decoded.apiKey or decoded.key or decoded.secret
    apiKey = type(apiKey) == "string" and trim(apiKey) or ""
    if apiKey == "" then
        return nil, "missing_key"
    end
    providerSecretCache[cleanProvider] = apiKey
    return apiKey
end

App.Providers = {
    Azure = {},
    MiniMax = {},
    OpenAI = {},
}

function App.Providers.Azure.speak(params)
    local debugParams = {}
    for k, v in pairs(params or {}) do
        if k ~= "apiKey" then
            debugParams[k] = v
        end
    end
    logInfo(string.format("Azure.speak called with params: %s", json.encode(debugParams)))
    local apiKey = trim(params.apiKey or "")
    local region = trim(params.region or "")
    if not params.useApi then
        local secret, fetchErr = fetch_provider_secret(AZURE_SPEECH_PROVIDER)
        if not secret then
            local prefix = App.State.locale == "cn" and "自动获取 Azure Key 失败：" or "Failed to fetch Azure key: "
            return false, prefix .. tostring(fetchErr or "unknown")
        end
        apiKey = secret
        region = "eastus"
    elseif apiKey == "" or region == "" then
        return false, "Azure API Key 或 Region 未配置"
    end
    local ssml = App.Azure.buildSsml(params)
    local ssmlPath, tmpErr = Utils.makeTempPath("ssml")
    if not ssmlPath then
        return false, "创建临时 SSML 文件失败: " .. tostring(tmpErr)
    end
    local wrote, writeErr = Utils.writeFile(ssmlPath, ssml)
    if not wrote then
        return false, "写入 SSML 文件失败: " .. tostring(writeErr)
    end

    local responseInfoPath, infoErr = Utils.makeTempPath("curlinfo")
    if not responseInfoPath then
        os.remove(ssmlPath)
        return false, "创建临时信息文件失败: " .. tostring(infoErr)
    end

    local outputPath
    if params.outputPath and params.outputPath ~= "" then
        outputPath = params.outputPath
    else
        local generatedPath, pathErr = App.Azure.buildOutputPath(params)
        if not generatedPath then
            local message
            if pathErr == "missing_output_dir" then
                message = localizedText("请先设置保存路径。", "Please set a save path before synthesizing.")
            elseif pathErr == "ensure_failed" then
                message = localizedText("保存路径无效或无法创建。", "Save path is invalid or cannot be created.")
            else
                message = localizedText("无法准备保存路径：", "Unable to prepare save path: ") .. tostring(pathErr or "unknown")
            end
            return false, message
        end
        outputPath = generatedPath
    end
    Utils.ensureDir(outputPath:match("^(.*)[/\\]") or "")

    local function escapeQuotes(str)
        return (str or ""):gsub('"', '\\"')
    end

    local command = string.format(
        'curl -sS -f -w "%%{http_code}" -X POST "https://%s.tts.speech.microsoft.com/cognitiveservices/v1" -H "Content-Type: application/ssml+xml" -H "X-Microsoft-OutputFormat: %s" -H "Ocp-Apim-Subscription-Key: %s" -H "User-Agent: heiba-azure-tts-curl/1.0" --data-binary @"%s" --output "%s" > "%s" 2>&1',
        region,
        params.outputFormat or "riff-24khz-16bit-mono-pcm",
        escapeQuotes(apiKey),
        escapeQuotes(ssmlPath),
        escapeQuotes(outputPath),
        escapeQuotes(responseInfoPath)
    )

    local ok = runShellCommand(command)
    os.remove(ssmlPath)
    local responseInfo = Utils.readFile(responseInfoPath)
    if responseInfo and responseInfo ~= "" then
        responseInfo = responseInfo:gsub("%s+$", "")
        logInfo(string.format("Azure response info: %s", truncateForLog(responseInfo, 800)))
    else
        responseInfo = ""
        logInfo("Azure response info: <empty>")
    end
    os.remove(responseInfoPath)
    if not ok then
        local errMessage = (responseInfo ~= "" and responseInfo) or "curl 调用失败"
        return false, string.format("调用 Azure API 失败：%s", errMessage)
    end

    local size = Utils.getFileSize(outputPath)
    if not size or size == 0 then
        return false, "Azure API 返回空音频文件。"
    end

    local sampleRate = App.Azure.deriveSampleRate(params.outputFormat)
    return true, {
        path = outputPath,
        durationSamples = params.durationSamples or 0,
        sampleRate = sampleRate,
        debugInfo = responseInfo and responseInfo:gsub("%s+$", "") or "",
    }
end

function App.Providers.MiniMax.speak(params)
    logInfo(string.format("MiniMax.speak called with params: %s", json.encode(params)))

    local items = App.UI.items or {}
    local minimaxItems = App.UI.minimaxItems or {}
    local cfg = App.Config.MiniMax or {}
    local defaults = cfg.defaults or {}

    local function readComboEntry(list, combo, fallbackIndex)
        list = list or {}
        local index = 0
        if combo and combo.CurrentIndex ~= nil then
            index = clampIndex(combo.CurrentIndex, #list)
        else
            index = clampIndex(fallbackIndex or 0, #list)
        end
        return list[index + 1], index
    end

    local function hexToBinary(hex)
        if type(hex) ~= "string" then
            return nil, "invalid_hex_string"
        end
        hex = hex:gsub("%s+", "")
        if hex == "" then
            return nil, "empty_hex_string"
        end
        if #hex % 2 == 1 then
            hex = "0" .. hex
        end
        local buffer = {}
        for i = 1, #hex, 2 do
            local byte = tonumber(hex:sub(i, i + 1), 16)
            if not byte then
                return nil, "hex_decode_failed"
            end
            buffer[#buffer + 1] = string.char(byte)
        end
        return table.concat(buffer)
    end

    local apiKey = trim((minimaxItems.minimaxApiKey and minimaxItems.minimaxApiKey.Text) or defaults.apiKey or "")
    local groupId = trim((minimaxItems.minimaxGroupID and minimaxItems.minimaxGroupID.Text) or defaults.groupId or "")
    local isIntl = (minimaxItems.intlCheckBox and minimaxItems.intlCheckBox.Checked) or defaults.intl or false
    if apiKey == "" then
        return false, "MiniMax API Key 未配置"
    end
    if groupId == "" then
        return false, "MiniMax Group ID 未配置"
    end

    local outputDir = trim((items.Path and items.Path.Text) or Config.Settings.outputPath or "")
    if outputDir == "" then
        return false, "请先设置保存路径"
    end
    if not Utils.ensureDir(outputDir) then
        return false, "保存路径不可用或无法创建"
    end

    local models = cfg.models or {}
    local modelEntry = readComboEntry(models, items.minimaxModelCombo, App.State.minimax.modelIndex)
    local modelId = (modelEntry and modelEntry.id) or params.modelDisplay or App.State.minimax.model or (models[1] and models[1].id) or "speech-2.5-hd-preview"

    local voiceId = params.voiceId or App.State.minimax.voice
    if not voiceId or voiceId == "" then
        return false, "MiniMax 音色未选择"
    end

    local emotions = cfg.emotions or {}
    local emotionEntry = readComboEntry(emotions, items.minimaxEmotionCombo, App.State.minimax.emotionIndex)
    local emotionId = emotionEntry and emotionEntry.id or App.State.minimax.emotion
    if emotionId == "default" or emotionId == "" then
        emotionId = nil
    end

    local soundEffects = cfg.soundEffects or {}
    local effectEntry = readComboEntry(
        soundEffects,
        (App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo),
        App.State.minimax.voiceEffectIndex or App.State.minimax.soundEffectIndex
    )
    local effectId = effectEntry and effectEntry.id or App.State.minimax.soundEffect
    if effectId == "default" or effectId == "" then
        effectId = nil
    end
    if App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo then
        App.State.minimax.voiceEffectIndex = App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo.CurrentIndex or 0
    else
        App.State.minimax.voiceEffectIndex = App.State.minimax.voiceEffectIndex or App.State.minimax.soundEffectIndex
    end
    App.State.minimax.soundEffect = effectId or App.State.minimax.soundEffect

    local sharedFormatId = App.Settings.getSharedFormatId()
    local formatId = sharedFormatId or "wav"

    local baseUrl = isIntl and "https://api.minimaxi.com" or "https://api.minimax.chat"
    local url = string.format("%s/v1/t2a_v2?GroupId=%s", baseUrl, groupId)

    local payload = {
        model = modelId,
        text = params.text,
        stream = false,
        subtitle_enable = params.subtitle and true or false,
        voice_setting = {
            voice_id = voiceId,
            speed = params.rate or 1.0,
            vol = params.volume or 1.0,
            pitch = params.pitch or 0,
        },
        audio_setting = {
            sample_rate = 32000,
            bitrate = 128000,
            format = formatId,
            channel = 2,
        },
    }

    if emotionId then
        payload.voice_setting.emotion = emotionId
    end
    local voiceModify = {}
    local timbre = App.State.minimax.voiceTimbre or 0
    local intensity = App.State.minimax.voiceIntensity or 0
    local vmPitch = App.State.minimax.voicePitch or 0
    if timbre ~= 0 then voiceModify.timbre = timbre end
    if intensity ~= 0 then voiceModify.intensity = intensity end
    if vmPitch ~= 0 then voiceModify.pitch = vmPitch end
    if effectId then voiceModify.sound_effects = effectId end
    if next(voiceModify) then
        payload.voice_modify = voiceModify
    end

    local payloadStr = json.encode(payload)
    logInfo(string.format("MiniMax payload: %s", truncateForLog(payloadStr or "", 1200)))
    local headers = {
        Authorization = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json",
    }

    local body, status = Services.httpPostJson(url, payloadStr, headers, 120)
    logInfo(string.format("MiniMax HTTP status: %s", tostring(status or "unknown")))
    if not body then
        return false, string.format("MiniMax 请求失败：%s", tostring(status))
    end
    logInfo(string.format("MiniMax raw response: %s", truncateForLog(body, 1200)))
    if status and status ~= 200 then
        return false, string.format("MiniMax HTTP 状态码异常：%s", tostring(status))
    end

    local resp, decodeErr = json.decode(body)
    if not resp then
        return false, string.format("MiniMax 响应解析失败：%s", tostring(decodeErr))
    end

    local baseResp = resp.base_resp or resp.baseResp or {}
    local statusCode = tonumber(baseResp.status_code or baseResp.statusCode)
    if statusCode and statusCode ~= 0 then
        local statusMsg = baseResp.status_msg or baseResp.statusMsg or "未知错误"
        return false, string.format("MiniMax API 错误 (%s)：%s", tostring(statusCode), tostring(statusMsg))
    end

    local data = resp.data or {}
    local audioHex = data.audio or data.audio_data
    if not audioHex or audioHex == "" then
        return false, "MiniMax 返回空音频数据"
    end

    local audioBinary, hexErr = hexToBinary(audioHex)
    if not audioBinary then
        return false, string.format("MiniMax 音频解码失败：%s", tostring(hexErr))
    end

    local outputPath, nameErr = Utils.nextAvailableFile(outputDir, {
        baseName = params.text or "audio",
        extension = formatId,
        maxBaseLength = 24,
        maxAttempts = 99,
    })
    if not outputPath then
        local reason = nameErr and (": " .. tostring(nameErr)) or ""
        return false, "MiniMax 无法生成输出文件名" .. reason
    end

    local wrote, writeErr = Utils.writeFile(outputPath, audioBinary)
    if not wrote then
        return false, string.format("MiniMax 写入音频失败：%s", tostring(writeErr))
    end

    local sampleRate = payload.audio_setting.sample_rate or 32000
    return true, {
        path = outputPath,
        durationSamples = params.durationSamples or 0,
        sampleRate = sampleRate,
        subtitleUrl = data.subtitle_file,
    }
end

function App.Providers.OpenAI.speak(params)
    logInfo(string.format("OpenAI.speak called with params: %s", json.encode(params)))

    local items = App.UI.items or {}
    local openaiItems = App.UI.openaiItems or {}
    local cfg = App.Config.OpenAI or {}
    local defaults = cfg.defaults or {}

    local text = trim(params.text or "")
    if text == "" then
        return false, "请输入要合成的文本。"
    end
    if #text > 4096 then
        return false, "OpenAI 文本长度超过 4096 字符限制。"
    end

    local function normalizeBaseUrl(url)
        url = trim(url or "")
        if url == "" then
            return "https://api.openai.com"
        end
        url = url:gsub("%s+$", "")
        url = url:gsub("/+$", "")
        if url == "" then
            return "https://api.openai.com"
        end
        return url
    end

    local function selectEntry(list, combo, fallbackIndex, fallbackId)
        list = list or {}
        local index = 0
        if combo and combo.CurrentIndex ~= nil then
            index = clampIndex(combo.CurrentIndex, #list)
        elseif fallbackIndex ~= nil then
            index = clampIndex(fallbackIndex, #list)
        end
        local entry = list[index + 1]
        if entry then
            return entry, entry.id, index
        end
        return nil, fallbackId, index
    end

    local apiKey = trim((openaiItems.OpenAIApiKey and openaiItems.OpenAIApiKey.Text) or defaults.apiKey or "")
    if apiKey == "" then
        return false, "OpenAI API Key 未配置"
    end

    local baseUrl = normalizeBaseUrl((openaiItems.OpenAIBaseURL and openaiItems.OpenAIBaseURL.Text) or defaults.baseUrl or "")
    local versionedBase = baseUrl
    if not versionedBase:match("/v%d+$") then
        versionedBase = versionedBase .. "/v1"
    end
    local url = versionedBase .. "/audio/speech"

    local models = cfg.models or {}
    local modelEntry, modelId = selectEntry(models, items.OpenAIModelCombo, App.State.openai and App.State.openai.modelIndex, App.State.openai and App.State.openai.model or "gpt-4o-mini-tts")
    modelId = modelId or (models[1] and models[1].id) or "gpt-4o-mini-tts"

    local voices = cfg.voices or {}
    local voiceEntry, voiceId = selectEntry(voices, items.OpenAIVoiceCombo, App.State.openai and App.State.openai.voiceIndex, App.State.openai and App.State.openai.voice or "alloy")
    voiceId = voiceId or (voices[1] and voices[1].id) or "alloy"

    local formatId = (App.Settings.getSharedFormatId() or "mp3"):lower()

    local speed = tonumber(params.rate) or (App.State.openai and App.State.openai.rate) or 1.0
    if speed < 0.25 then speed = 0.25 end
    if speed > 4.0 then speed = 4.0 end

    local instructions = trim(params.instruction or "")
    if instructions ~= "" and (modelId == "tts-1" or modelId == "tts-1-hd") then
        instructions = ""
    end

    local outputDir = trim((items.Path and items.Path.Text) or Config.Settings.outputPath or "")
    if outputDir == "" then
        return false, "请先设置保存路径"
    end
    if not Utils.ensureDir(outputDir) then
        return false, "保存路径不可用或无法创建"
    end

    local payload = {
        model = modelId,
        input = text,
        voice = voiceId,
        response_format = formatId,
        speed = speed,
        stream = false,
    }
    if instructions ~= "" then
        payload.instructions = instructions
    end

    local payloadStr = json.encode(payload)
    local headers = {
        Authorization = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json",
    }

    local function decodeJson(bodyStr)
        local ok, decoded = pcall(json.decode, bodyStr)
        if ok and type(decoded) == "table" then
            return decoded
        end
        return nil
    end

    local body, status = Services.httpPostJson(url, payloadStr, headers, 120)
    logInfo(string.format("OpenAI HTTP status: %s", tostring(status or "unknown")))
    if not body then
        return false, string.format("OpenAI 请求失败：%s", tostring(status))
    end
    if body == "" then
        logInfo("OpenAI response body is empty")
        return false, "OpenAI 返回空响应"
    end
    local firstNonWhitespace = body:match("^%s*(.)")
    if firstNonWhitespace == "{" or firstNonWhitespace == "[" then
        logInfo(string.format("OpenAI response JSON: %s", truncateForLog(body, 1200)))
    else
        logInfo(string.format("OpenAI response size: %d bytes", #body))
    end

    local numericStatus = tonumber(status)
    if numericStatus and (numericStatus < 200 or numericStatus >= 300) then
        local decoded = decodeJson(body)
        local errMessage = string.format("HTTP %d", numericStatus)
        if decoded then
            if decoded.error then
                if type(decoded.error) == "table" then
                    errMessage = decoded.error.message or decoded.error.type or errMessage
                else
                    errMessage = tostring(decoded.error)
                end
            elseif decoded.message then
                errMessage = decoded.message
            end
        end
        return false, string.format("OpenAI 请求失败：%s", tostring(errMessage))
    end

    if firstNonWhitespace == "{" or firstNonWhitespace == "[" then
        local decoded = decodeJson(body)
        if decoded then
            local errMessage = "未知错误"
            if decoded.error then
                if type(decoded.error) == "table" then
                    errMessage = decoded.error.message or decoded.error.type or errMessage
                else
                    errMessage = tostring(decoded.error)
                end
            elseif decoded.message then
                errMessage = decoded.message
            end
            return false, string.format("OpenAI 错误：%s", tostring(errMessage))
        end
    end

    local outputPath, nameErr = Utils.nextAvailableFile(outputDir, {
        baseName = text,
        extension = formatId,
        maxBaseLength = 24,
        maxAttempts = 99,
    })
    if not outputPath then
        local reason = nameErr and (": " .. tostring(nameErr)) or ""
        return false, "OpenAI 无法生成输出文件名" .. reason
    end

    local wrote, writeErr = Utils.writeFile(outputPath, body)
    if not wrote then
        return false, string.format("OpenAI 写入音频失败：%s", tostring(writeErr))
    end

    return true, {
        path = outputPath,
        durationSamples = params.durationSamples or 0,
        sampleRate = 44100,
    }
end

local function timecodeToFrames(timecode, frameRate)
    if not timecode or timecode == "" then
        return 0
    end
    frameRate = tonumber(frameRate) or 0
    if frameRate <= 0 then
        return 0
    end

    local hours, minutes, seconds, separator, frames = timecode:match("^(%d%d):(%d%d):(%d%d)([:;])(%d%d%d?)$")
    if not hours then
        return 0
    end

    hours = tonumber(hours)
    minutes = tonumber(minutes)
    seconds = tonumber(seconds)
    frames = tonumber(frames)

    local isDropFrame = separator == ";"
    local function isRate(target)
        return math.abs(frameRate - target) < 0.01
    end
    if isDropFrame then
        local nominalFrameRate
        if isRate(23.976) or isRate(29.97) or isRate(59.94) or isRate(119.88) then
            nominalFrameRate = math.floor(frameRate * 1000 / 1001 + 0.5)
        else
            nominalFrameRate = math.floor(frameRate + 0.5)
        end
        local dropFrames = math.floor(nominalFrameRate / 15 + 0.5)
        local totalMinutes = hours * 60 + minutes
        local totalDroppedFrames = dropFrames * (totalMinutes - math.floor(totalMinutes / 10))
        local frameCount = ((hours * 3600) + (minutes * 60) + seconds) * nominalFrameRate + frames
        return frameCount - totalDroppedFrames
    else
        local nominalFrameRate
        if isRate(23.976) or isRate(29.97) or isRate(47.952) or isRate(59.94) or isRate(95.904) or isRate(119.88) then
            nominalFrameRate = math.floor(frameRate * 1000 / 1001 + 0.5)
        else
            nominalFrameRate = frameRate
        end
        return ((hours * 3600) + (minutes * 60) + seconds) * nominalFrameRate + frames
    end
end



App.TimelineIO = {}

function App.TimelineIO.getFirstEmptyTrack(timeline, startFrame, endFrame, mediaType)
    local trackIndex = 1
    while true do
        local items = timeline:GetItemListInTrack(mediaType, trackIndex)
        if not items or #items == 0 then
            return trackIndex
        end

        local isEmpty = true
        for _, item in ipairs(items) do
            local itemStart = item:GetStart()
            local itemEnd = item:GetEnd()
            if itemStart and itemEnd and itemStart <= endFrame and startFrame <= itemEnd then
                isEmpty = false
                break
            end
        end

        if isEmpty then
            return trackIndex
        end

        trackIndex = trackIndex + 1
    end
end
function App.TimelineIO.insertAudio(path, startOffsetSamples, durationSamples, recordFrame)
    if not path or path == "" then
        return false, "Audio path is empty"
    end

    logInfo(string.format("TimelineIO.insertAudio start. path=%s", tostring(path)))
    local resolveInstance, project, timeline, err = App.ResolveCtx.get()
    if err then
        logInfo(string.format("TimelineIO.insertAudio aborted: %s", tostring(err)))
        return false, err
    end
    if not project or not timeline then
        logInfo("TimelineIO.insertAudio aborted: project or timeline unavailable.")
        return false, "Project or timeline unavailable"
    end

    local mediaPool = project:GetMediaPool()
    if not mediaPool then
        logInfo("TimelineIO.insertAudio aborted: media pool unavailable.")
        return false, "Media pool unavailable"
    end

    local rootFolder = mediaPool:GetRootFolder()
    if not rootFolder then
        logInfo("TimelineIO.insertAudio aborted: root folder unavailable.")
        return false, "Root folder unavailable"
    end

    local ttsFolder = nil
    local subFolders = rootFolder:GetSubFolderList() or {}
    for _, folder in ipairs(subFolders) do
        if folder:GetName() == "TTS" then
            ttsFolder = folder
            break
        end
    end
    if not ttsFolder then
        ttsFolder = mediaPool:AddSubFolder(rootFolder, "TTS")
    end
    if not ttsFolder then
        logInfo("TimelineIO.insertAudio aborted: failed to locate/create TTS folder.")
        return false, "Failed to locate or create TTS folder"
    end

    mediaPool:SetCurrentFolder(ttsFolder)
    local importedItems = mediaPool:ImportMedia({ path })
    if not importedItems or not importedItems[1] then
        logInfo(string.format("TimelineIO.insertAudio aborted: failed to import media %s", tostring(path)))
        return false, string.format("Failed to import media: %s", tostring(path))
    end

    local clip = importedItems[1]
    logInfo(string.format("TimelineIO.insertAudio imported clip '%s'", tostring(clip:GetName() or "?")))

    local frameRateSetting
    if timeline.GetSetting then
        frameRateSetting = timeline:GetSetting("timelineFrameRate")
    end
    if not frameRateSetting and project.GetSetting then
        frameRateSetting = project:GetSetting("timelineFrameRate")
    end
    local frameRate = tonumber(frameRateSetting) or 24

    local startFrame
    if recordFrame ~= nil then
        startFrame = math.floor(recordFrame + 0.5)
    end
    if not startFrame then
        local currentTimecode = timeline:GetCurrentTimecode()
        if not currentTimecode or currentTimecode == "" then
            if timeline.GetStartTimecode then
                currentTimecode = timeline:GetStartTimecode()
            else
                currentTimecode = "00:00:00:00"
            end
        end
        startFrame = timecodeToFrames(currentTimecode, frameRate)
    end
    if (not startFrame or startFrame < 0) and timeline.GetCurrentFrame then
        local currentFrame = timeline:GetCurrentFrame()
        if type(currentFrame) == "number" and currentFrame >= 0 then
            startFrame = math.floor(currentFrame + 0.5)
        end
    end
    startFrame = startFrame or 0
    local clipSampleRate = tonumber(clip:GetClipProperty("SampleRate") or clip:GetClipProperty("AudioSampleRate"))
    if clipSampleRate and clipSampleRate > 0 and startOffsetSamples and startOffsetSamples > 0 then
        local offsetFrames = math.floor((startOffsetSamples / clipSampleRate) * frameRate + 0.5)
        startFrame = startFrame + offsetFrames
    end

    local durationTimecode = clip:GetClipProperty("Duration")
    local clipDurationFrames = timecodeToFrames(durationTimecode, frameRate)
    if clipDurationFrames <= 0 and durationSamples and clipSampleRate and clipSampleRate > 0 then
        clipDurationFrames = math.floor((durationSamples / clipSampleRate) * frameRate + 0.5)
    end
    if clipDurationFrames <= 0 then
        clipDurationFrames = 1
    end

    local endFrame = startFrame + clipDurationFrames - 1
    local trackIndex = App.TimelineIO.getFirstEmptyTrack(timeline, startFrame, endFrame, "audio")

    local audioTrackCount = timeline:GetTrackCount("audio") or 0
    while audioTrackCount < trackIndex do
        timeline:AddTrack("audio")
        audioTrackCount = audioTrackCount + 1
    end

    local clipInfo = {
        mediaPoolItem = clip,
        mediaType = 2,
        startFrame = 0,
        --endFrame = clipDurationFrames - 1,
        trackIndex = trackIndex,
        recordFrame = startFrame,
        stereoEye = "both",
    }

    local appended, appendErr = mediaPool:AppendToTimeline({ clipInfo })
    if appended == nil or appended == false then
        logInfo(string.format(
            "AppendToTimeline failed for '%s': %s",
            tostring(clip:GetName()),
            tostring(appendErr)
        ))
        return false, appendErr or "Failed to append clip to timeline"
    end

    logInfo(string.format(
        "Appended audio clip '%s' to timeline at frame %d on audio track %d",
        tostring(clip:GetName()),
        startFrame,
        trackIndex
    ))
    return true
end

App.MiniMaxClone = {}
do
    local Clone = App.MiniMaxClone
    Clone.markerKey = "clone"
    Clone.previewUrls = {
        intl = "https://www.minimax.io/audio/voices",
        cn = "https://www.minimaxi.com/audio/voices",
    }
    Clone.tempDir = Utils.joinPath(Paths.scriptDir, "clone_cache")

    local function getStatusText(key, fallback)
        if not key then
            return fallback
        end
        local entries = Config.Status or {}
        local entry = entries[key]
        if type(entry) == "table" then
            local locale = App.State.locale == "cn" and 2 or 1
            local text = entry[locale] or entry[1] or entry[2]
            if text and text ~= "" then
                return text
            end
        end
        return fallback or key
    end

    local function showStatus(key, fallback)
        local text = getStatusText(key, fallback)
        if App.UI.msgboxItems then
            setTextSafe(App.UI.msgboxItems.InfoLabel, text or "")
            if msgbox and msgbox.Show then
                msgbox:Show()
            end
        else
            logInfo(text or "")
        end
    end
    Clone.showStatus = showStatus

    local function minimaxItems()
        return App.UI.minimaxItems or {}
    end

    local function cloneItems()
        return App.UI.minimaxCloneItems or {}
    end

    local function getVoiceFilePath()
        if App.Config.MiniMax and App.Config.MiniMax.voiceFilePath then
            return App.Config.MiniMax.voiceFilePath
        end
        return Paths.inVoices("minimax_voices.json")
    end

    local function ensureTempDir()
        Utils.ensureDir(Clone.tempDir)
        return Clone.tempDir
    end

    local function addLanguageIfMissing(language)
        local cfg = App.Config.MiniMax
        cfg.cloneLangCounts = cfg.cloneLangCounts or {}
        cfg.cloneMap = cfg.cloneMap or {}
        if not cfg.voices[language] then
            cfg.voices[language] = {}
        end
        local exists = false
        for _, entry in ipairs(cfg.languages or {}) do
            if entry.id == language then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(cfg.languages, { id = language, labels = buildLabelPair(language, language) })
        end
        if cfg.cloneLangCounts[language] == nil then
            cfg.cloneLangCounts[language] = 0
        end
    end

    local function insertCloneIntoCache(voiceName, voiceId, language)
        local cfg = App.Config.MiniMax
        language = language or App.State.minimax.language or "中文（普通话）"
        addLanguageIfMissing(language)
        local entry = {
            id = voiceId,
            labels = buildLabelPair(voiceName or voiceId, voiceName or voiceId),
            isClone = true,
        }
        table.insert(cfg.voices[language], 1, entry)
        cfg.cloneLangCounts[language] = (cfg.cloneLangCounts[language] or 0) + 1
        cfg.cloneMap[voiceId] = language
    end

    local function removeCloneFromCache(voiceId)
        local cfg = App.Config.MiniMax
        cfg.cloneMap = cfg.cloneMap or {}
        cfg.cloneLangCounts = cfg.cloneLangCounts or {}
        local language = cfg.cloneMap[voiceId]
        if not language then
            for lang, list in pairs(cfg.voices or {}) do
                for idx, entry in ipairs(list) do
                    if entry.isClone and entry.id == voiceId then
                        table.remove(list, idx)
                        cfg.cloneLangCounts[lang] = math.max((cfg.cloneLangCounts[lang] or 1) - 1, 0)
                        cfg.cloneMap[voiceId] = nil
                        return true
                    end
                end
            end
            return false
        end
        local list = cfg.voices[language]
        if not list then
            return false
        end
        for idx, entry in ipairs(list) do
            if entry.isClone and entry.id == voiceId then
                table.remove(list, idx)
                cfg.cloneLangCounts[language] = math.max((cfg.cloneLangCounts[language] or 1) - 1, 0)
                cfg.cloneMap[voiceId] = nil
                return true
            end
        end
        return false
    end

    function Clone.refreshVoices(selectVoiceId)
        if selectVoiceId then
            App.State.minimax.voice = selectVoiceId
        end
        App.UI.refreshMiniMaxVoices({
            selectVoiceId = selectVoiceId,
        })
    end

    function Clone.loadVoiceData()
        local path = getVoiceFilePath()
        local content, err = Utils.readFile(path)
        if not content then
            return nil, err or "read_failed"
        end
        local data, decodeErr = Utils.decodeJsonWithOrder(content)
        if not data then
            return nil, decodeErr
        end
        return data, path
    end

    function Clone.saveVoiceData(data)
        local path = getVoiceFilePath()
        return Utils.writeJsonOrdered(path, data, { indent = "  " })
    end

    function Clone.addCloneVoice(voiceName, voiceId, language)
        local data, err = Clone.loadVoiceData()
        if not data then
            return false, err
        end
        if type(data.minimax_clone_voices) ~= "table" then
            data.minimax_clone_voices = {}
        end
        local normalizedName = voiceName and voiceName:lower()
        for _, entry in ipairs(data.minimax_clone_voices) do
            if (voiceId ~= "" and entry.voice_id == voiceId) or (normalizedName and entry.voice_name and entry.voice_name:lower() == normalizedName) then
                return false, getStatusText("error_2039")
            end
        end
        table.insert(data.minimax_clone_voices, 1, {
            voice_id = voiceId,
            voice_name = voiceName,
            description = {},
            created_time = os.date("%Y-%m-%d"),
            language = language,
        })
        local ok, writeErr = Clone.saveVoiceData(data)
        if not ok then
            return false, writeErr
        end
        insertCloneIntoCache(voiceName, voiceId, language)
        return true
    end

    function Clone.deleteCloneVoice(entry)
        if not entry or not entry.isClone then
            return false, getStatusText("delete_clone_error")
        end
        local data, err = Clone.loadVoiceData()
        if not data then
            return false, err
        end
        if type(data.minimax_clone_voices) ~= "table" then
            return false, getStatusText("delete_clone_error")
        end
        local filtered = {}
        local removed = false
        for _, v in ipairs(data.minimax_clone_voices) do
            if v.voice_id == entry.id or (entry.labels and entry.labels.en and v.voice_name == entry.labels.en) then
                removed = true
            else
                table.insert(filtered, v)
            end
        end
        if not removed then
            return false, getStatusText("delete_clone_error")
        end
        data.minimax_clone_voices = filtered
        local ok, writeErr = Clone.saveVoiceData(data)
        if not ok then
            return false, writeErr
        end
        removeCloneFromCache(entry.id)
        return true
    end

    local function removeCloneMarker()
        local _, _, timeline = App.ResolveCtx.get()
        if not timeline then
            return
        end
        if timeline.DeleteMarkerByCustomData then
            pcall(function()
                timeline:DeleteMarkerByCustomData(Clone.markerKey)
            end)
        end
        if timeline.DeleteMarkerAtFrame then
            pcall(function()
                timeline:DeleteMarkerAtFrame(0)
            end)
        end
    end

    local function addCloneMarker()
        local _, _, timeline, err = App.ResolveCtx.get()
        if err or not timeline then
            showStatus("create_timeline")
            return false
        end
        removeCloneMarker()
        local name = (App.State.locale == "cn") and "克隆标记" or "Clone Marker"
        local note = (App.State.locale == "cn")
            and "拖拽Mark点范围确定克隆音频的范围，大于10秒，小于5分钟"
            or "Drag the marker points to mark audio range (10 seconds to 5 minutes)."
        local ok, result = pcall(function()
            return timeline:AddMarker(0, "Red", name, note, 750, Clone.markerKey)
        end)
        if not ok or not result then
            logInfo("Failed to add clone marker: " .. tostring(result))
            return false
        end
        return true
    end

    function Clone.toggleMode(isAddOnly)
        local items = cloneItems()
        if not items then
            return
        end
        setEnabledSafe(items.minimaxNeedNoiseReduction, not isAddOnly)
        setEnabledSafe(items.minimaxNeedVolumeNormalization, not isAddOnly)
        setEnabledSafe(items.minimaxClonePreviewText, not isAddOnly)
        local addText = (App.State.locale == "cn") and "添加" or "Add"
        local cloneText = (App.State.locale == "cn") and "克隆" or "Clone"
        setTextSafe(items.MiniMaxCloneConfirm, isAddOnly and addText or cloneText)
        if isAddOnly then
            removeCloneMarker()
        else
            addCloneMarker()
        end
    end

    function Clone.onShowWindow()
        local items = cloneItems()
        if not items then
            return
        end
        ensureTempDir()
        setTextSafe(items.minimaxCloneFileID, "")
        setCheckedSafe(items.minimaxOnlyAddID, true)
        Clone.toggleMode(true)
        minimaxCloneWin:Show()
        win:Hide()
    end

    function Clone.onCloseWindow()
        removeCloneMarker()
        local items = cloneItems()
        if items then
            setTextSafe(items.minimaxCloneFileID, "")
        end
        win:Show()
        minimaxCloneWin:Hide()
        
    end

    local function loadAudioPreset(project)
        local ok = false
        local list = project:GetRenderPresetList() or {}
        for _, preset in ipairs(list) do
            local name = preset
            if type(preset) == "table" then
                name = preset.PresetName or preset.Name
            end
            if type(name) == "string" and name:lower():find("audio only", 1, true) then
                ok = project:LoadRenderPreset(name)
                if ok then
                    break
                end
            end
        end
        if not ok then
            ok = project:LoadRenderPreset("Audio Only")
        end
        return ok
    end

    function Clone.renderAudioByMarker()
        local resolveInstance, project, timeline, err = App.ResolveCtx.get()
        if err or not project or not timeline then
            return nil, err or "timeline_unavailable"
        end
        local ok = pcall(function() project:SetCurrentRenderMode(1) end)
        if not ok then
            return nil, "render_mode_failed"
        end
        if not loadAudioPreset(project) then
            logInfo("Failed to load audio render preset.")
        end
        local markers = timeline:GetMarkers()
        if not markers or not next(markers) then
            showStatus("insert_mark")
            return nil, "no_markers"
        end
        local firstFrame
        for frame in pairs(markers) do
            if not firstFrame or frame < firstFrame then
                firstFrame = frame
            end
        end
        local markerInfo = markers[firstFrame]
        if not markerInfo or not markerInfo.duration then
            showStatus("insert_mark")
            return nil, "invalid_marker"
        end
        local frameRate = tonumber(project:GetSetting("timelineFrameRate")) or tonumber(timeline:GetSetting("timelineFrameRate")) or 24
        local durationFrames = tonumber(markerInfo.duration) or 0
        local durationSeconds = durationFrames / frameRate
        if durationSeconds < 10 or durationSeconds > 300 then
            showStatus("duration_seconds")
            return nil, "invalid_duration"
        end
        local timelineStart = timeline:GetStartFrame() or 0
        local markIn = timelineStart + firstFrame
        local markOut = markIn + durationFrames - 1
        local dir = ensureTempDir()
        local uniqueId = os.date("%Y%m%d%H%M%S")
        if timeline.GetUniqueId then
            local ok, value = pcall(function()
                return timeline:GetUniqueId()
            end)
            if ok and value and tostring(value) ~= "" then
                uniqueId = tostring(value)
            end
        end
        local baseName = string.format("clone_%s", uniqueId)
        local settings = {
            SelectAllFrames = false,
            MarkIn = markIn,
            MarkOut = markOut,
            TargetDir = dir,
            CustomName = baseName,
            UniqueFilenameStyle = 1,
            ExportVideo = false,
            ExportAudio = true,
            AudioCodec = "LinearPCM",
            AudioBitDepth = 16,
            AudioSampleRate = 48000,
        }
        project:SetRenderSettings(settings)
        local jobId = project:AddRenderJob()
        if not jobId then
            return nil, "add_job_failed"
        end
        local started = project:StartRendering({ jobId }, false)
        if not started then
            project:DeleteRenderJob(jobId)
            return nil, "render_start_failed"
        end
        showStatus("render_audio")
        while project:IsRenderingInProgress() do
            sleepSeconds(0.5)
        end
        project:DeleteRenderJob(jobId)
        local outputPath = Utils.joinPath(dir, baseName .. ".wav")
        if not Utils.fileExists(outputPath) then
            return nil, "render_output_missing"
        end
        if resolve and resolve.OpenPage then
            pcall(function()
                resolve:OpenPage("edit")
            end)
        end
        return outputPath
    end

    local function runCurl(command)
        local ok = runShellCommand(command)
        return ok
    end

    local function escapeShell(str)
        return (str or ""):gsub('"', '\\"')
    end

    function Clone.uploadFileForClone(filePath, apiKey, groupId, isIntl)
        local baseUrl = isIntl and "https://api.minimaxi.chat" or "https://api.minimax.chat"
        local url = string.format("%s/v1/files/upload?GroupId=%s", baseUrl, Utils.urlEncode(groupId or ""))
        local responsePath, err = Utils.makeTempPath("upload")
        if not responsePath then
            return nil, err
        end
        local command = string.format(
            'curl -sS -f -X POST "%s" -H "Authorization: Bearer %s" -F "purpose=voice_clone" -F "file=@%s" -o "%s"',
            url,
            escapeShell(apiKey),
            escapeShell(filePath),
            escapeShell(responsePath)
        )
        local ok = runCurl(command)
        local body = Utils.readFile(responsePath)
        os.remove(responsePath)
        logInfo(string.format("MiniMax clone upload response: %s", truncateForLog(body or "<empty>", 800)))
        if not ok then
            return nil, body or "upload_failed"
        end
        local resp, decodeErr = json.decode(body)
        if not resp then
            return nil, decodeErr
        end
        local base = resp.base_resp or resp.baseResp or {}
        local statusCode = tonumber(base.status_code or base.statusCode)
        if statusCode and statusCode ~= 0 then
            return {
                error_code = statusCode,
                error_message = base.status_msg or base.statusMsg or "unknown_error",
            }
        end
        local fileId = resp.file and resp.file.file_id
        if type(fileId) == "number" then
            fileId = string.format("%.0f", fileId)
        elseif fileId ~= nil then
            fileId = tostring(fileId)
        end
        return {
            file_id = fileId,
        }
    end

    function Clone.submitCloneJob(payload)
        local cfg = App.Config.MiniMax or {}
        local baseUrl = payload.isIntl and "https://api.minimaxi.chat" or "https://api.minimax.chat"
        local url = string.format("%s/v1/voice_clone?GroupId=%s", baseUrl, Utils.urlEncode(payload.groupId or ""))
        local fileIdDigits = tostring(payload.fileId or "")
        if not fileIdDigits:match("^%d+$") then
            return nil, "invalid_file_id"
        end
        local fileIdLiteral = { value = fileIdDigits }
        setmetatable(fileIdLiteral, {
            __tojson = function(t)
                return t.value
            end
        })
        local body = {
            file_id = fileIdLiteral,
            voice_id = payload.voiceId,
            need_noise_reduction = payload.needNoiseReduction and true or false,
            need_volume_normalization = payload.needVolumeNormalization and true or false,
        }
        if payload.previewText and payload.previewText ~= "" then
            body.text = payload.previewText
            body.model = "speech-2.6-hd"
        end
        local headers = {
            Authorization = "Bearer " .. tostring(payload.apiKey or ""),
            ["Content-Type"] = "application/json",
        }
        local logPayload = {}
        for k, v in pairs(body) do
            logPayload[k] = v
        end
        logPayload.file_id = payload.fileId
        local bodyStr = json.encode(body)
        logInfo(string.format("MiniMax clone submit payload: %s", truncateForLog(json.encode(logPayload), 800)))
        local respBody, status = Services.httpPostJson(url, bodyStr, headers, 120)
        logInfo(string.format("MiniMax clone submit response (%s): %s", tostring(status or "unknown"), truncateForLog(respBody or "<empty>", 800)))
        if not respBody then
            return nil, status or "clone_request_failed"
        end
        local resp, decodeErr = json.decode(respBody)
        if not resp then
            return nil, decodeErr
        end
        local base = resp.base_resp or resp.baseResp or {}
        local statusCode = tonumber(base.status_code or base.statusCode)
        if statusCode and statusCode ~= 0 then
            return {
                error_code = statusCode,
                error_message = base.status_msg or base.statusMsg or "clone_failed",
            }
        end
        return {
            demo_url = resp.demo_audio,
        }
    end

    function Clone.downloadDemo(url, destPath)
        local body, status = Services.httpGet(url, nil, 120)
        if not body or (status and tonumber(status) ~= 200) then
            return false
        end
        local ok, err = Utils.writeFile(destPath, body)
        if not ok then
            return false, err
        end
        return true
    end

    function Clone.showErrorCode(code)
        if not code then
            return
        end
        local key = "error_" .. tostring(code)
        if Config.Status and Config.Status[key] then
            showStatus(key)
        else
            showStatus(nil, string.format("MiniMax 错误：%s", tostring(code)))
        end
    end

    function Clone.handleConfirm()
        local uiItems = App.UI.items
        local cloneUI = cloneItems()
        local miniItems = minimaxItems()
        if not uiItems or not cloneUI or not miniItems then
            return
        end
        local apiKey = trim((miniItems.minimaxApiKey and miniItems.minimaxApiKey.Text) or "")
        local groupId = trim((miniItems.minimaxGroupID and miniItems.minimaxGroupID.Text) or "")
        if apiKey == "" or groupId == "" then
            showStatus("enter_api_key")
            return
        end
        local outputDir = trim((uiItems.Path and uiItems.Path.Text) or Config.Settings.outputPath or "")
        if outputDir == "" then
            showStatus("select_save_path")
            return
        end
        Utils.ensureDir(outputDir)
        local voiceName = trim((cloneUI.minimaxCloneVoiceName and cloneUI.minimaxCloneVoiceName.Text) or "")
        local voiceId = trim((cloneUI.minimaxCloneVoiceID and cloneUI.minimaxCloneVoiceID.Text) or "")
        if voiceName == "" or voiceId == "" then
            showStatus("clone_id_error")
            return
        end
        local language = (uiItems.minimaxLanguageCombo and uiItems.minimaxLanguageCombo.CurrentText) or App.State.minimax.language or "中文（普通话）"
        local addOnly = cloneUI.minimaxOnlyAddID and cloneUI.minimaxOnlyAddID.Checked
        if addOnly then
            local ok, err = Clone.addCloneVoice(voiceName, voiceId, language)
            if not ok then
                showStatus(nil, err)
                return
            end
            Clone.refreshVoices(voiceId)
            showStatus("add_clone_succeed")
            setTextSafe(cloneUI.minimaxCloneVoiceName, "")
            setTextSafe(cloneUI.minimaxCloneVoiceID, "")
            setTextSafe(cloneUI.minimaxCloneFileID, "")
            return
        end
        showStatus(nil, (App.State.locale == "cn") and "请确认克隆参数（音色ID、文本、Mark等）是否正确。" or "Please double-check clone parameters (voice id, preview text, markers) before continuing.")
        local fileIdText = trim((cloneUI.minimaxCloneFileID and cloneUI.minimaxCloneFileID.Text) or "")
        local fileId
        if not fileIdText or fileIdText == "" then
            local audioPath, audioErr = Clone.renderAudioByMarker()
            if not audioPath then
                showStatus(nil, getStatusText("render_audio_failed", audioErr or "render_failed"))
                return
            end
            local size = Utils.getFileSize(audioPath)
            if size and size > 20 * 1024 * 1024 then
                showStatus("file_size")
                return
            end
            local uploadResult, uploadErr = Clone.uploadFileForClone(audioPath, apiKey, groupId, miniItems.intlCheckBox and miniItems.intlCheckBox.Checked)
            if not uploadResult then
                showStatus(nil, uploadErr or "upload_failed")
                return
            end
            if uploadResult.error_code then
                Clone.showErrorCode(uploadResult.error_code)
                return
            end
            if type(uploadResult.file_id) == "number" then
                fileId = string.format("%.0f", uploadResult.file_id)
            else
                fileId = uploadResult.file_id and tostring(uploadResult.file_id) or ""
            end
            setTextSafe(cloneUI.minimaxCloneFileID, fileId)
        else
            fileId = fileIdText
        end
        if not fileId or fileId == "" then
            showStatus("file_upload")
            return
        end
        local submitFileId = fileId
        showStatus("file_clone")
        local cloneResp, cloneErr = Clone.submitCloneJob({
            apiKey = apiKey,
            groupId = groupId,
            fileId = submitFileId,
            voiceId = voiceId,
            isIntl = miniItems.intlCheckBox and miniItems.intlCheckBox.Checked,
            needNoiseReduction = cloneUI.minimaxNeedNoiseReduction and cloneUI.minimaxNeedNoiseReduction.Checked,
            needVolumeNormalization = cloneUI.minimaxNeedVolumeNormalization and cloneUI.minimaxNeedVolumeNormalization.Checked,
            previewText = (cloneUI.minimaxClonePreviewText and cloneUI.minimaxClonePreviewText.PlainText) or "",
        })
        if not cloneResp then
            showStatus(nil, cloneErr)
            return
        end
        if cloneResp.error_code then
            Clone.showErrorCode(cloneResp.error_code)
            return
        end
        if cloneResp.demo_url then
            showStatus("download_preclone")
            local demoPath = Utils.joinPath(outputDir, string.format("preview_%s.mp3", voiceId))
            local ok, err = Clone.downloadDemo(cloneResp.demo_url, demoPath)
            if ok then
                App.TimelineIO.insertAudio(demoPath, 0, 0, nil)
            else
                logInfo("Failed to download demo: " .. tostring(err))
            end
        end
        local ok, err = Clone.addCloneVoice(voiceName, voiceId, language)
        if not ok then
            showStatus(nil, err)
            return
        end
        Clone.refreshVoices(voiceId)
        showStatus("clone_success")
    end
end

App.ResolveCtx = {}

function App.ResolveCtx.get()
    local resolveInstance = resolve or Resolve()
    if not resolveInstance then
        return nil, nil, nil, "Resolve not available"
    end
    local projectManager = resolveInstance:GetProjectManager()
    if not projectManager then
        return resolveInstance, nil, nil, "ProjectManager unavailable"
    end
    local project = projectManager:GetCurrentProject()
    if not project then
        return resolveInstance, nil, nil, "No active project"
    end
    local timeline = project:GetCurrentTimeline()
    if not timeline then
        return resolveInstance, project, nil, "No active timeline"
    end
    return resolveInstance, project, timeline, nil
end

local function resolveTimelineFrameRate(project, timeline)
    if timeline and timeline.GetSetting then
        local value = timeline:GetSetting("timelineFrameRate")
        local frameRate = tonumber(value)
        if frameRate and frameRate > 0 then
            return frameRate
        end
    end
    if project and project.GetSetting then
        local value = project:GetSetting("timelineFrameRate")
        local frameRate = tonumber(value)
        if frameRate and frameRate > 0 then
            return frameRate
        end
    end
    return nil
end

local function getCurrentFrameNumber(timeline, frameRate)
    if timeline and timeline.GetCurrentFrame then
        local currentFrame = timeline:GetCurrentFrame()
        if type(currentFrame) == "number" and currentFrame >= 0 then
            return math.floor(currentFrame + 0.5)
        end
    end
    if timeline and timeline.GetCurrentTimecode then
        local timecode = timeline:GetCurrentTimecode()
        if timecode and timecode ~= "" then
            local frame = timecodeToFrames(timecode, frameRate)
            if frame and frame >= 0 then
                return frame
            end
        end
    end
    return nil
end

local function isTrackEnabled(timeline, trackIndex)
    if not timeline then
        return false
    end
    if timeline.GetIsTrackEnabled then
        local ok, enabled = pcall(function()
            return timeline:GetIsTrackEnabled("subtitle", trackIndex)
        end)
        if ok and enabled ~= nil then
            return enabled and true or false
        end
    end
    return true
end

local function sortSubtitles(entries)
    table.sort(entries, function(a, b)
        if a.startFrame == b.startFrame then
            if a.trackIndex == b.trackIndex then
                return (a.index or 0) < (b.index or 0)
            end
            return (a.trackIndex or 0) < (b.trackIndex or 0)
        end
        return (a.startFrame or 0) < (b.startFrame or 0)
    end)
end

function App.Subtitles.getCurrent()
    local resolveInstance, project, timeline, err = App.ResolveCtx.get()
    if err then
        return nil, err
    end
    if not project or not timeline then
        return nil, "当前项目或时间线不可用。"
    end

    local frameRate = resolveTimelineFrameRate(project, timeline)
    if not frameRate then
        return nil, "无法获取时间线帧率。"
    end

    local currentFrame = getCurrentFrameNumber(timeline, frameRate)
    if not currentFrame then
        return nil, "无法确定当前帧位置。"
    end

    local trackCount = timeline:GetTrackCount("subtitle") or 0
    for trackIndex = 1, trackCount do
        if isTrackEnabled(timeline, trackIndex) then
            local items = timeline:GetItemListInTrack("subtitle", trackIndex) or {}
            for itemIndex, item in ipairs(items) do
                local startFrame = item:GetStart()
                local endFrame = item:GetEnd()
                if startFrame and endFrame and startFrame <= currentFrame and currentFrame <= endFrame then
                    local text = item:GetName() or ""
                    return {
                        text = text,
                        startFrame = startFrame,
                        endFrame = endFrame,
                        trackIndex = trackIndex,
                        index = itemIndex,
                        frameRate = frameRate,
                    }
                end
            end
        end
    end
    return nil, "未在当前播放头找到字幕，请将播放头移至字幕块。"
end

function App.Subtitles.collectAll()
    local resolveInstance, project, timeline, err = App.ResolveCtx.get()
    if err then
        return nil, err
    end
    if not project or not timeline then
        return nil, "当前项目或时间线不可用。"
    end

    local frameRate = resolveTimelineFrameRate(project, timeline)
    if not frameRate then
        return nil, "无法获取时间线帧率。"
    end

    local results = {}
    local trackCount = timeline:GetTrackCount("subtitle") or 0
    for trackIndex = 1, trackCount do
        if isTrackEnabled(timeline, trackIndex) then
            local items = timeline:GetItemListInTrack("subtitle", trackIndex) or {}
            for itemIndex, item in ipairs(items) do
                local startFrame = item:GetStart()
                local endFrame = item:GetEnd()
                local text = item:GetName() or ""
                results[#results + 1] = {
                    text = text,
                    startFrame = startFrame,
                    endFrame = endFrame,
                    trackIndex = trackIndex,
                    index = itemIndex,
                }
            end
        end
    end

    if #results > 0 then
        sortSubtitles(results)
    end

    return {
        subtitles = results,
        frameRate = frameRate,
    }
end

function App.Subtitles.concatText(subtitles)
    if not subtitles then
        return ""
    end
    local buffer = {}
    for _, entry in ipairs(subtitles) do
        local text = entry.text
        if text and text ~= "" then
            buffer[#buffer + 1] = text
        end
    end
    return table.concat(buffer, "\n")
end


App.Controller = {
    activeProvider = "azure",
}

local STATUS_MESSAGE_MAP = {
    ["没能读到字幕，请稍后再试。"] = { cn = "没能读到字幕，请稍后再试。", en = "Couldn't read subtitles right now. Please try again." },
    ["Couldn't read subtitles right now. Please try again."] = { cn = "没能读到字幕，请稍后再试。", en = "Couldn't read subtitles right now. Please try again." },
    ["时间线里还没有字幕。"] = { cn = "时间线里还没有字幕。", en = "There are no subtitles on the timeline yet." },
    ["时间线中没有字幕。"] = { cn = "时间线里还没有字幕。", en = "There are no subtitles on the timeline yet." },
    ["There are no subtitles on the timeline yet."] = { cn = "时间线里还没有字幕。", en = "There are no subtitles on the timeline yet." },
    ["播放头下没有字幕，请把播放头移到字幕上。"] = { cn = "播放头下没有字幕，请把播放头移到字幕上。", en = "No subtitle under the playhead. Move the playhead onto a subtitle clip." },
    ["未在当前播放头找到字幕，请将播放头移至字幕块。"] = { cn = "播放头下没有字幕，请把播放头移到字幕上。", en = "No subtitle under the playhead. Move the playhead onto a subtitle clip." },
    ["No subtitle under the playhead. Move the playhead onto a subtitle clip."] = { cn = "播放头下没有字幕，请把播放头移到字幕上。", en = "No subtitle under the playhead. Move the playhead onto a subtitle clip." },
    ["请先输入要转换的文字。"] = { cn = "请先输入要转换的文字。", en = "Please enter the text you want to turn into speech." },
    ["请输入要合成的文本。"] = { cn = "请先输入要转换的文字。", en = "Please enter the text you want to turn into speech." },
    ["Please enter the text you want to turn into speech."] = { cn = "请先输入要转换的文字。", en = "Please enter the text you want to turn into speech." },
    ["正在准备生成语音..."] = { cn = "正在准备生成语音...", en = "Getting your speech ready..." },
    ["Getting your speech ready..."] = { cn = "正在准备生成语音...", en = "Getting your speech ready..." },
    ["生成完成，音频已放到时间线。"] = { cn = "生成完成，音频已放到时间线。", en = "Audio generated and placed on the timeline." },
    ["Audio generated and placed on the timeline."] = { cn = "生成完成，音频已放到时间线。", en = "Audio generated and placed on the timeline." },
    ["合成成功，音频已挂载"] = { cn = "生成完成，音频已放到时间线。", en = "Audio generated and placed on the timeline." },
    ["语音生成成功，但没有返回音频文件。"] = { cn = "语音生成成功，但没有返回音频文件。", en = "Speech generated, but no audio file was returned." },
    ["Speech generated, but no audio file was returned."] = { cn = "语音生成成功，但没有返回音频文件。", en = "Speech generated, but no audio file was returned." },
    ["合成成功（无音频路径）"] = { cn = "语音生成成功，但没有返回音频文件。", en = "Speech generated, but no audio file was returned." },
    ["准备发送请求..."] = { cn = "正在准备生成语音...", en = "Getting your speech ready..." }, -- legacy wording kept for compatibility
    ["无法获取字幕。"] = { cn = "没能读到字幕，请稍后再试。", en = "Couldn't read subtitles right now. Please try again." },
    ["合成成功，但插入失败："] = { cn = "语音生成好了，但放到时间线时出错：", en = "Speech generated, but placing it on the timeline failed:" },
    ["合成失败："] = { cn = "语音生成失败：", en = "Speech generation failed:" },
    ["语音生成好了，但放到时间线时出错："] = { cn = "语音生成好了，但放到时间线时出错：", en = "Speech generated, but placing it on the timeline failed:" },
    ["语音生成失败："] = { cn = "语音生成失败：", en = "Speech generation failed:" },
}

local STATUS_PATTERNS = {
    {
        pattern = "^已载入%s*(%d+)%s*条字幕。$",
        format = function(locale, count)
            if locale == "en" then
                return string.format("Loaded %s subtitles.", count)
            end
            return string.format("已载入 %s 条字幕。", count)
        end,
    },
    {
        pattern = "^Loaded%s*(%d+)%s*subtitles%.?$",
        format = function(locale, count)
            if locale == "cn" then
                return string.format("已载入 %s 条字幕。", count)
            end
            return string.format("Loaded %s subtitles.", count)
        end,
    },
    {
        pattern = "^语音生成好了，但放到时间线时出错：(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "en" then
                return string.format("Speech generated, but placing it on the timeline failed: %s", reason)
            end
            return string.format("语音生成好了，但放到时间线时出错：%s", reason)
        end,
    },
    {
        pattern = "^合成成功，但插入失败：(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "en" then
                return string.format("Speech generated, but placing it on the timeline failed: %s", reason)
            end
            return string.format("语音生成好了，但放到时间线时出错：%s", reason)
        end,
    },
    {
        pattern = "^Speech generated, but placing it on the timeline failed:%s*(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "cn" then
                return string.format("语音生成好了，但放到时间线时出错：%s", reason)
            end
            return string.format("Speech generated, but placing it on the timeline failed: %s", reason)
        end,
    },
    {
        pattern = "^语音生成失败：(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "en" then
                return string.format("Speech generation failed: %s", reason)
            end
            return string.format("语音生成失败：%s", reason)
        end,
    },
    {
        pattern = "^合成失败：(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "en" then
                return string.format("Speech generation failed: %s", reason)
            end
            return string.format("语音生成失败：%s", reason)
        end,
    },
    {
        pattern = "^Speech generation failed:%s*(.+)$",
        format = function(locale, err)
            local reason = trim(err or "")
            if locale == "cn" then
                return string.format("语音生成失败：%s", reason)
            end
            return string.format("Speech generation failed: %s", reason)
        end,
    },
}

local unpackArgs = table.unpack or unpack

local function getPreferredLocale()
    local ui = App.UI.items or {}
    if ui.LangCnCheckBox and ui.LangCnCheckBox.Checked then
        return "cn"
    end
    if ui.LangEnCheckBox and ui.LangEnCheckBox.Checked then
        return "en"
    end
    return (App.State.locale == "cn") and "cn" or "en"
end

local function localizeStatusMessage(raw)
    local text = trim(raw or "")
    if text == "" then
        return ""
    end
    local locale = getPreferredLocale()
    local template = STATUS_MESSAGE_MAP[text]
    if template then
        return template[locale] or template.cn or template.en or text
    end
    for _, entry in ipairs(STATUS_PATTERNS) do
        local captures = { text:match(entry.pattern) }
        if #captures > 0 then
            return entry.format(locale, unpackArgs(captures))
        end
    end
    return text
end

local function controllerSetStatus(_, message)
    local text = ""
    if message ~= nil then
        text = trim(tostring(message))
    end
    text = localizeStatusMessage(text)
    local msgItems = App.UI.msgboxItems
    if text == "" then
        if msgItems then
            setTextSafe(msgItems.InfoLabel, "")
        end
        if msgbox and msgbox.Hide then
            msgbox:Hide()
        end
        return
    end
    if msgItems then
        setTextSafe(msgItems.InfoLabel, text)
    end
    if msgbox and msgbox.Show then
        msgbox:Show()
    else
        logInfo(text)
    end
end

local function readPlainText(control)
    if not control then
        return ""
    end
    return control.PlainText or control.Text or ""
end

local function readComboSelection(combo, entries)
    if not combo then
        return nil, nil
    end
    local index = clampIndex(combo.CurrentIndex or 0, entries and #entries or 0)
    local entry = entries and entries[index + 1]
    return entry, index
end

function App.Controller.setAllTextInputs(text)
    if text == nil then
        return
    end
    local items = App.UI.items or {}
    setTextSafe(items.azureText, text)
    setTextSafe(items.minimaxText, text)
    setTextSafe(items.OpenAIText, text)
end

App.Settings.keyOrder = {
    "API_KEY",
    "REGION",
    "LANGUAGE",
    "TYPE",
    "NAME",
    "STYLE",
    "MULTILINGUAL",
    "RATE",
    "PITCH",
    "VOLUME",
    "STYLEDEGREE",
    "BREAKTIME",
    "OUTPUT_FORMATS",
    "USE_API",
    "Path",
    "minimax_API_KEY",
    "minimax_GROUP_ID",
    "minimax_intlCheckBox",
    "minimax_Model",
    "minimax_Voice",
    "minimax_Language",
    "minimax_SubtitleCheckBox",
    "minimax_Emotion",
    "minimax_Rate",
    "minimax_Volume",
    "minimax_Pitch",
    "minimax_Break",
    "minimax_VoiceTimbre",
    "minimax_VoiceIntensity",
    "minimax_VoicePitch",
    "minimax_VoiceEffect",
    "OpenAI_API_KEY",
    "OpenAI_BASE_URL",
    "OpenAI_Model",
    "OpenAI_Voice",
    "OpenAI_Rate",
    "OpenAI_Instruction",
    "OpenAI_Preset",
    "CN",
    "EN",
}

function App.Settings.collect()
    local items = App.UI.items or {}
    local azureItems = App.UI.azureItems or {}
    local minimaxItems = App.UI.minimaxItems or {}
    local openaiItems = App.UI.openaiItems or {}
    local stateAzure = App.State.azure or {}
    local stateMini = App.State.minimax or {}
    local stateOpenAI = App.State.openai or {}
    local settings = {
        API_KEY = trim(readText(azureItems.ApiKey)),
        REGION = trim(readText(azureItems.Region)),
        LANGUAGE = readCurrentIndex(items.azureLanguageCombo, stateAzure.languageIndex or 0),
        TYPE = readCurrentIndex(items.azureVoiceTypeCombo, stateAzure.voiceTypeIndex or 0),
        NAME = readCurrentIndex(items.azureVoiceCombo, stateAzure.voiceIndex or 0),
        STYLE = readCurrentIndex(items.azureStyleCombo, stateAzure.styleIndex or 0),
        MULTILINGUAL = readCurrentIndex(items.azureMultilingualCombo, stateAzure.multilingualIndex or 0),
        RATE = readValue(items.azureRateSpinBox, stateAzure.rate or 1.0),
        PITCH = readValue(items.azurePitchSpinBox, stateAzure.pitch or 1.0),
        VOLUME = readValue(items.azureVolumeSpinBox, stateAzure.volume or 1.0),
        STYLEDEGREE = readValue(items.azureStyleDegreeSpinBox, stateAzure.styleDegree or 1.0),
        BREAKTIME = readValue(items.azureBreakSpinBox, stateAzure.breakMs or 50),
        OUTPUT_FORMATS = readCurrentIndex(items.outputFormatCombo or items.azureOutputFormatCombo, stateAzure.outputFormatIndex or 0),
        USE_API = readChecked(azureItems.UseAPICheckBox, stateAzure.useApi ~= false),
        Path = trim(readText(items.Path)),
        minimax_API_KEY = trim(readText(minimaxItems.minimaxApiKey)),
        minimax_GROUP_ID = trim(readText(minimaxItems.minimaxGroupID)),
        minimax_intlCheckBox = readChecked(minimaxItems.intlCheckBox, stateMini.intl or false),
        minimax_Model = readCurrentIndex(items.minimaxModelCombo, stateMini.modelIndex or 0),
        minimax_Voice = readCurrentIndex(items.minimaxVoiceCombo, stateMini.voiceIndex or 0),
        minimax_Language = readCurrentIndex(items.minimaxLanguageCombo, stateMini.languageIndex or 0),
        minimax_SubtitleCheckBox = readChecked(items.minimaxSubtitleCheckBox, stateMini.subtitle or false),
        minimax_Emotion = readCurrentIndex(items.minimaxEmotionCombo, stateMini.emotionIndex or 0),
        minimax_Rate = readValue(items.minimaxRateSpinBox, stateMini.rate or 1.0),
        minimax_Volume = readValue(items.minimaxVolumeSpinBox, stateMini.volume or 1.0),
        minimax_Pitch = readValue(items.minimaxPitchSpinBox, stateMini.pitch or 0),
        minimax_Break = readValue(items.minimaxBreakSpinBox, stateMini.breakMs or 50),
        minimax_VoiceTimbre = readValue(App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxTimbreSlider, stateMini.voiceTimbre or 0),
        minimax_VoiceIntensity = readValue(App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxIntensitySlider, stateMini.voiceIntensity or 0),
        minimax_VoicePitch = readValue(App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxModifyPitchSlider, stateMini.voicePitch or 0),
        minimax_VoiceEffect = readCurrentIndex(App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo, stateMini.voiceEffectIndex or stateMini.soundEffectIndex or 0),
        OpenAI_API_KEY = trim(readText(openaiItems.OpenAIApiKey)),
        OpenAI_BASE_URL = trim(readText(openaiItems.OpenAIBaseURL)),
        OpenAI_Model = readCurrentIndex(items.OpenAIModelCombo, stateOpenAI.modelIndex or 0),
        OpenAI_Voice = readCurrentIndex(items.OpenAIVoiceCombo, stateOpenAI.voiceIndex or 0),
        OpenAI_Rate = readValue(items.OpenAIRateSpinBox, stateOpenAI.rate or 1.0),
        OpenAI_Instruction = readPlainTextSafe(items.OpenAIInstructionText),
        OpenAI_Preset = readCurrentIndex(items.OpenAIPresetCombo, stateOpenAI.presetIndex or 0),
        CN = readChecked(items.LangCnCheckBox, Config.Settings.locale == "cn"),
        EN = readChecked(items.LangEnCheckBox, Config.Settings.locale ~= "cn"),
    }
    return settings
end

function App.Settings.save()
    local ok, result = pcall(App.Settings.collect)
    if not ok then
        logInfo(string.format("Settings collection failed: %s", tostring(result)))
        return false, result
    end
    local settings = result or {}
    Config.Settings.saved = settings
    if not Utils.ensureDir(Paths.configDir) then
        return false, "无法创建配置目录"
    end
    local state = { indent = "  ", keyorder = App.Settings.keyOrder }
    local okEncode, content = pcall(json.encode, settings, state)
    if not okEncode then
        logInfo(string.format("Settings encode failed: %s", tostring(content)))
        return false, content
    end
    local okWrite, err = Utils.writeFile(Paths.inConfig("TTS_settings.json"), content)
    if not okWrite then
        logInfo(string.format("Settings write failed: %s", tostring(err)))
        return false, err
    end
    logInfo("Settings saved to config/TTS_settings.json")
    return true
end

function App.Controller.collectAzureParams(source)
    local items = App.UI.items
    local azureItems = App.UI.azureItems or {}
    local stateAzure = App.State.azure or {}
    local outputDir = trim((items.Path and items.Path.Text) or Config.Settings.outputPath or "")
    local params = {
        source = source,
        text = readPlainText(items.azureText),
        breakMs = items.azureBreakSpinBox and items.azureBreakSpinBox.Value or stateAzure.breakMs,
        styleDegree = items.azureStyleDegreeSpinBox and items.azureStyleDegreeSpinBox.Value or stateAzure.styleDegree,
        rate = items.azureRateSpinBox and items.azureRateSpinBox.Value or stateAzure.rate,
        pitch = items.azurePitchSpinBox and items.azurePitchSpinBox.Value or stateAzure.pitch,
        volume = items.azureVolumeSpinBox and items.azureVolumeSpinBox.Value or stateAzure.volume,
        outputFormat = App.Settings.getAzureFormatId(),
        languageDisplay = items.azureLanguageCombo and items.azureLanguageCombo.CurrentText or "",
        voiceDisplay = items.azureVoiceCombo and items.azureVoiceCombo.CurrentText or "",
        voiceTypeDisplay = items.azureVoiceTypeCombo and items.azureVoiceTypeCombo.CurrentText or "",
        styleDisplay = items.azureStyleCombo and items.azureStyleCombo.CurrentText or "",
        multilingualDisplay = items.azureMultilingualCombo and items.azureMultilingualCombo.CurrentText or "",
        locale = stateAzure.language,
        startOffsetSamples = 0,
        durationSamples = 0,
        outputDir = outputDir,
        style = stateAzure.style or "default",
    }
    local formatEntry, fmtIndex = App.Settings.getSharedFormat()
    if formatEntry then
        params.outputFormat = formatEntry.azureId or formatEntry.id or params.outputFormat
        stateAzure.outputFormat = params.outputFormat
        stateAzure.outputFormatIndex = fmtIndex or 0
    end
    local voiceEntry = App.State.azure.voiceList and App.State.azure.voiceList[(items.azureVoiceCombo and (items.azureVoiceCombo.CurrentIndex or 0) or 0) + 1]
    if voiceEntry then
        params.voiceId = voiceEntry.id
        params.voiceGender = voiceEntry.type
    else
        params.voiceId = stateAzure.voiceId
    end
    params.multilingualCode = stateAzure.multilingual
    params.multilingualOptions = stateAzure.multilingualOptions
    params.provider = "azure"
    params.apiKey = trim((azureItems.ApiKey and azureItems.ApiKey.Text) or Config.Azure.defaults.apiKey or "")
    params.region = trim((azureItems.Region and azureItems.Region.Text) or Config.Azure.defaults.region or "")
    local useApi = readChecked(azureItems.UseAPICheckBox, stateAzure.useApi ~= false)
    params.useApi = useApi
    App.State.azure.useApi = useApi
    if not params.outputFormat or params.outputFormat == "" then
        local defaultFmt = App.Config.Azure.outputFormats and App.Config.Azure.outputFormats[1]
        params.outputFormat = defaultFmt and defaultFmt.id or "riff-24khz-16bit-mono-pcm"
    end
    return params
end

function App.Controller.collectMiniMaxParams(source)
    local items = App.UI.items
    local params = {
        source = source,
        text = readPlainText(items.minimaxText),
        breakMs = items.minimaxBreakSpinBox and items.minimaxBreakSpinBox.Value or App.State.minimax.breakMs,
        rate = items.minimaxRateSpinBox and items.minimaxRateSpinBox.Value or App.State.minimax.rate,
        volume = items.minimaxVolumeSpinBox and items.minimaxVolumeSpinBox.Value or App.State.minimax.volume,
        pitch = items.minimaxPitchSpinBox and items.minimaxPitchSpinBox.Value or App.State.minimax.pitch,
        subtitle = items.minimaxSubtitleCheckBox and items.minimaxSubtitleCheckBox.Checked or App.State.minimax.subtitle,
        modelDisplay = items.minimaxModelCombo and items.minimaxModelCombo.CurrentText or "",
        languageDisplay = items.minimaxLanguageCombo and items.minimaxLanguageCombo.CurrentText or "",
        voiceDisplay = items.minimaxVoiceCombo and items.minimaxVoiceCombo.CurrentText or "",
        emotionDisplay = items.minimaxEmotionCombo and items.minimaxEmotionCombo.CurrentText or "",
        soundEffectDisplay = (App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo.CurrentText) or "",
        startOffsetSamples = 0,
        durationSamples = 0,
    }
    local voices = App.State.minimax.voiceList or {}
    local voiceEntry = voices[(items.minimaxVoiceCombo and (items.minimaxVoiceCombo.CurrentIndex or 0) or 0) + 1]
    if voiceEntry then
        params.voiceId = voiceEntry.id
    else
        params.voiceId = App.State.minimax.voice
    end
    params.provider = "minimax"
    return params
end

function App.Controller.collectOpenAIParams(source)
    local items = App.UI.items
    local params = {
        source = source,
        text = readPlainText(items.OpenAIText),
        rate = items.OpenAIRateSpinBox and items.OpenAIRateSpinBox.Value or App.State.openai.rate,
        instruction = readPlainText(items.OpenAIInstructionText),
        modelDisplay = items.OpenAIModelCombo and items.OpenAIModelCombo.CurrentText or "",
        voiceDisplay = items.OpenAIVoiceCombo and items.OpenAIVoiceCombo.CurrentText or "",
        presetDisplay = items.OpenAIPresetCombo and items.OpenAIPresetCombo.CurrentText or "",
        startOffsetSamples = 0,
        durationSamples = 0,
    }
    params.provider = "openai"
    return params
end

function App.Controller.collectParams(providerId, source)
    if providerId == "azure" then
        return App.Controller.collectAzureParams(source)
    elseif providerId == "minimax" then
        return App.Controller.collectMiniMaxParams(source)
    elseif providerId == "openai" then
        return App.Controller.collectOpenAIParams(source)
    end
    return { provider = providerId, source = source }
end

function App.Controller.onProviderChanged(index)
    local providers = { "azure", "minimax", "openai", "settings" }
    local providerId = providers[(index or 0) + 1] or "azure"
    if providerId == "settings" then
        providerId = App.Controller.activeProvider or "azure"
    end
    App.Controller.activeProvider = providerId
    logInfo(string.format("Active provider switched to %s", providerId))
    controllerSetStatus(providerId, " ")
end

function App.Controller.onFetchTimelineSubtitles(providerId)
    providerId = providerId or App.Controller.activeProvider or "azure"
    local info, err = App.Subtitles.collectAll()
    if not info then
        local message = err or "没能读到字幕，请稍后再试。"
        controllerSetStatus(providerId, message)
        logInfo(string.format("Timeline subtitle fetch failed: %s", tostring(message)))
        return false
    end
    local subtitles = info.subtitles or {}
    if #subtitles == 0 then
        local message = err or "时间线里还没有字幕。"
        controllerSetStatus(providerId, message)
        logInfo("Timeline subtitle fetch completed: no subtitles found.")
        return false
    end
    local combinedText = App.Subtitles.concatText(subtitles)
    App.Controller.setAllTextInputs(combinedText)
    controllerSetStatus(providerId, string.format("已载入 %d 条字幕。", #subtitles))
    logInfo(string.format("Loaded %d subtitles from timeline", #subtitles))
    return true
end

local function timelineInsert(path, startOffsetSamples, durationSamples, recordFrame)
    local ok, err = App.TimelineIO.insertAudio(
        path,
        startOffsetSamples or 0,
        durationSamples or 0,
        recordFrame
    )
    if not ok then
        return false, err
    end
    return true
end

function App.Controller.onSynthesizeClicked(providerId, source)
    providerId = providerId or App.Controller.activeProvider or "azure"
    local params = App.Controller.collectParams(providerId, source or "text")
    local providerModule = App.Providers.Azure
    if providerId == "minimax" then
        providerModule = App.Providers.MiniMax
    elseif providerId == "openai" then
        providerModule = App.Providers.OpenAI
    end
    if params.source == "subtitle" then
        local subtitleInfo, err = App.Subtitles.getCurrent()
        if not subtitleInfo or not subtitleInfo.text or trim(subtitleInfo.text) == "" then
            local message = err or "播放头下没有字幕，请把播放头移到字幕上。"
            controllerSetStatus(providerId, message)
            logInfo(string.format("Subtitle synthesis aborted: %s", tostring(message)))
            return
        end
        params.subtitleInfo = subtitleInfo
        params.text = trim(subtitleInfo.text or "")
        params.recordFrame = subtitleInfo.startFrame
        params.subtitleStartFrame = subtitleInfo.startFrame
        params.subtitleEndFrame = subtitleInfo.endFrame
        params.timelineFrameRate = subtitleInfo.frameRate
        params.startOffsetSamples = 0
        params.durationSamples = 0
        if subtitleInfo.startFrame and subtitleInfo.endFrame then
            params.subtitleDurationFrames = (subtitleInfo.endFrame - subtitleInfo.startFrame) + 1
        end
        App.Controller.setAllTextInputs(params.text)
    else
        params.text = trim(params.text or "")
    end
    if params.text == "" then
        controllerSetStatus(providerId, "请先输入要转换的文字。")
        return
    end
    controllerSetStatus(providerId, "正在准备生成语音...")
    local ok, result = providerModule.speak(params)
    if ok then
        local audioPath = result
        local startOffset = params.startOffsetSamples or 0
        local durationSamples = params.durationSamples or 0
        local recordFrame = params.recordFrame
        if type(result) == "table" then
            audioPath = result.path or result[1]
            startOffset = result.startOffsetSamples or startOffset
            durationSamples = result.durationSamples or durationSamples
            recordFrame = result.recordFrame or recordFrame
        end
        if audioPath and audioPath ~= "" then
            local inserted, insertErr = timelineInsert(audioPath, startOffset, durationSamples, recordFrame)
            if inserted then
                controllerSetStatus(providerId, "生成完成，音频已放到时间线。")
            else
                controllerSetStatus(providerId, string.format("语音生成好了，但放到时间线时出错：%s", tostring(insertErr)))
            end
        else
            controllerSetStatus(providerId, "语音生成成功，但没有返回音频文件。")
        end
    else
        controllerSetStatus(providerId, string.format("语音生成失败：%s", tostring(result)))
    end
end

function App.UI.populateCombo(combo, entries, defaultId, getId, getLabel, defaultIndex)
    assert(combo, "ComboBox handle is required")
    combo:Clear()
    if not entries or #entries == 0 then
        combo.CurrentIndex = 0
        return nil, 0
    end

    getId = getId or function(entry)
        return entry.id or entry
    end

    getLabel = getLabel or function(entry)
        return App.UI.localizeLabel(entry.labels or entry.label or entry)
    end

    local matchedIndex = 0
    if defaultId ~= nil then
        for idx, entry in ipairs(entries) do
            combo:AddItem(getLabel(entry))
            if getId(entry) == defaultId and matchedIndex == 0 then
                matchedIndex = idx - 1
            end
        end
    else
        for _, entry in ipairs(entries) do
            combo:AddItem(getLabel(entry))
        end
    end

    local finalIndex = matchedIndex
    if defaultIndex ~= nil then
        finalIndex = clampIndex(defaultIndex, #entries)
    end

    combo.CurrentIndex = finalIndex
    return entries[finalIndex + 1], finalIndex
end

function App.UI.findAzureVoice(languageId, voiceId)
    local lang = App.Config.Azure.languages[languageId]
    if not lang then
        return nil
    end
    for _, voice in ipairs(lang.voices or {}) do
        if voice.id == voiceId then
            return voice
        end
    end
    return nil
end

function App.UI.localizeAzureStyle(styleCode)
    if not styleCode then
        -- 修改：使用全局变量 AZURE_STYLE_LABELS
        return App.UI.localizeLabel(AZURE_STYLE_LABELS["default"] or { en = "Default", cn = "默认" })
    end
    local labels = App.Config.Azure.styleLabels[styleCode]
    if not labels then
         -- 修改：使用全局变量 AZURE_STYLE_LABELS
        labels = AZURE_STYLE_LABELS[styleCode]
    end
    if not labels then
        labels = { en = styleCode, cn = styleCode }
    end
    return App.UI.localizeLabel(labels)
end

function App.UI.populateAzureStyles(languageId, voiceId, defaultStyle)
    local combo = App.UI.items.azureStyleCombo
    combo:Clear()
    combo:AddItem(App.UI.localizeAzureStyle("default"))
    local options = { "default" }
    local currentIndex = 0
    local voice = App.UI.findAzureVoice(languageId, voiceId)
    if voice then
        local seen = { default = true }
        for _, styleCode in ipairs(voice.styles or {}) do
            if styleCode and styleCode ~= "" and not seen[styleCode] then
                seen[styleCode] = true
                table.insert(options, styleCode)
                combo:AddItem(App.UI.localizeAzureStyle(styleCode))
                if defaultStyle and defaultStyle == styleCode then
                    currentIndex = (#options - 1)
                end
            end
        end
    end
    combo.CurrentIndex = currentIndex
    combo.Enabled = (#options > 1)
    App.State.azure.styleOptions = options
    local selectedStyle = options[currentIndex + 1] or "default"
    if not selectedStyle or selectedStyle == "" then
        selectedStyle = "default"
    end
    App.State.azure.style = selectedStyle
    App.State.azure.styleIndex = currentIndex
end

function App.UI.populateAzureMultilingual(languageId, voiceId, defaultValue)
    local combo = App.UI.items.azureMultilingualCombo
    combo:Clear()
    local defaultLabel = App.UI.localizeLabel({ en = "Default", cn = "默认" })
    combo:AddItem(defaultLabel)
    local currentIndex = 0
    local voice = App.UI.findAzureVoice(languageId, voiceId)
    local selectedValue = "Default"
    local options = {}
    if voice then
        for _, entry in ipairs(voice.multilingual or {}) do
            if entry and entry ~= "" and entry ~= "Default" then
                table.insert(options, entry)
            end
        end
        if #options == 0 then
            local mapped = App.Config.Azure.voiceMultilingualMap and App.Config.Azure.voiceMultilingualMap[voice.id]
            if mapped then
                for _, entry in ipairs(mapped) do
                    table.insert(options, entry)
                end
            end
        end
    end
    App.State.azure.multilingualOptions = options
    local showChinese = false
    if App.UI.items.LangCnCheckBox and App.UI.items.LangCnCheckBox.Checked then
        showChinese = true
    elseif App.State.locale == "cn" then
        showChinese = true
    end
    local translations = App.Config.Azure.languageTranslations or {}
    local position = 1
    for _, code in ipairs(options) do
        local label = showChinese and (translations[code] or code) or code
        combo:AddItem(label)
        if defaultValue and defaultValue ~= "" and defaultValue ~= "Default" then
            if defaultValue == code or (showChinese and translations[code] == defaultValue) then
                currentIndex = position
                selectedValue = code
            end
        end
        position = position + 1
    end
    if currentIndex == 0 and defaultValue and defaultValue ~= "" and defaultValue ~= "Default" then
        for idx, code in ipairs(options) do
            if code == defaultValue then
                currentIndex = idx
                selectedValue = code
                break
            end
        end
    end
    combo.CurrentIndex = currentIndex
    combo.Enabled = (#options > 0)
    if currentIndex == 0 then
        App.State.azure.multilingual = "Default"
        App.State.azure.multilingualIndex = 0
    else
        App.State.azure.multilingual = selectedValue
        App.State.azure.multilingualIndex = currentIndex
    end
end

function App.UI.populateAzureVoices(languageId, voiceType, defaultIndex)
    local combo = App.UI.items.azureVoiceCombo
    combo:Clear()
    local lang = App.Config.Azure.languages[languageId]
    if not lang then
        combo.CurrentIndex = 0
        App.State.azure.voiceId = nil
        App.State.azure.voiceIndex = 0
        return nil, 0
    end
    local filtered = {}
    for _, voice in ipairs(lang.voices or {}) do
        if not voiceType or voice.type == voiceType then
            table.insert(filtered, voice)
        end
    end
    if #filtered == 0 then
        filtered = lang.voices or {}
    end
    local selectedVoice, selectedIndex = App.UI.populateCombo(
        combo,
        filtered,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        defaultIndex
    )
    local fallbackVoice = getFirstEntry(filtered)
    App.State.azure.voiceId = selectedVoice and selectedVoice.id or (fallbackVoice and fallbackVoice.id)
    App.State.azure.voiceIndex = selectedIndex or 0
    App.State.azure.voiceList = filtered
    return selectedVoice, selectedIndex
end

function App.UI.populateAzureCombos()
    local cfg = App.Config.Azure
    local languages = {}
    for _, locale in ipairs(cfg.languageOrder or {}) do
        local langEntry = cfg.languages[locale]
        if langEntry then
            table.insert(languages, { id = locale, labels = langEntry.labels })
        end
    end
    if #languages == 0 then
        languages = {
            { id = "default", labels = buildLabelPair("默认", "Default") },
        }
    end
    local selectedLanguage, languageIndex = App.UI.populateCombo(
        App.UI.items.azureLanguageCombo,
        languages,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.languageIndex
    )
    App.State.azure.language = selectedLanguage and selectedLanguage.id or languages[1].id
    App.State.azure.languageIndex = languageIndex or 0

    local voiceTypes = {}
    for _, typeId in ipairs(cfg.voiceTypeOrder or {}) do
        local typeEntry = cfg.voiceTypes[typeId]
        if typeEntry then
            table.insert(voiceTypes, { id = typeId, labels = typeEntry.labels })
        end
    end
    if #voiceTypes == 0 then
        voiceTypes = {
            { id = "Neutral", labels = mapGenderLabel("Neutral") },
        }
    end
    local selectedType, typeIndex = App.UI.populateCombo(
        App.UI.items.azureVoiceTypeCombo,
        voiceTypes,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.voiceTypeIndex
    )
    App.State.azure.voiceType = selectedType and selectedType.id or voiceTypes[1].id
    App.State.azure.voiceTypeIndex = typeIndex or 0

    local selectedVoice, voiceIndex = App.UI.populateAzureVoices(
        App.State.azure.language,
        App.State.azure.voiceType,
        cfg.defaults.voiceIndex
    )

    App.UI.populateAzureStyles(
        App.State.azure.language,
        App.State.azure.voiceId,
        (function()
            if not selectedVoice then
                return nil
            end
            local styles = selectedVoice.styles or {}
            if #styles == 0 then
                return nil
            end
            local idx = clampIndex(cfg.defaults.styleIndex or 0, #styles)
            return styles[idx + 1]
        end)()
    )

    App.UI.populateAzureMultilingual(
        App.State.azure.language,
        App.State.azure.voiceId,
        (function()
            if not selectedVoice then
                return nil
            end
            local list = {}
            if type(selectedVoice.multilingual) == "table" and #selectedVoice.multilingual > 0 then
                list = selectedVoice.multilingual
            else
                local mapped = App.Config.Azure.voiceMultilingualMap and App.Config.Azure.voiceMultilingualMap[selectedVoice.id]
                if mapped then
                    list = mapped
                end
            end
            if type(list) == "table" and #list > 0 then
                local idx = clampIndex(cfg.defaults.multilingualIndex or 0, #list)
                return list[idx + 1]
            end
            return nil
        end)()
    )

    local selectedFormat, formatIndex = App.UI.populateCombo(
        App.UI.items.outputFormatCombo,
        cfg.outputFormats,
        nil,
        function(entry)
            return entry.label or entry.id
        end,
        function(entry)
            return entry.label or entry.id
        end,
        Config.Settings.defaults.outputFormatIndex
    )
    App.State.azure.outputFormat = selectedFormat and (selectedFormat.azureId or selectedFormat.id) or (cfg.outputFormats[1] and cfg.outputFormats[1].id)
    App.State.azure.outputFormatIndex = formatIndex or 0
end

function App.UI.refreshAzureVoices(options)
    options = options or {}
    if App.State.azure.isUpdating then
        return
    end
    App.State.azure.isUpdating = true
    local function run()
        local languages = {}
        for _, locale in ipairs(App.Config.Azure.languageOrder or {}) do
            local langEntry = App.Config.Azure.languages[locale]
            if langEntry then
                table.insert(languages, { id = locale, labels = langEntry.labels })
            end
        end
        if not App.State.azure.language then
            local firstLanguage = languages[1]
            App.State.azure.language = firstLanguage and firstLanguage.id or nil
            App.State.azure.languageIndex = 0
        end
        if App.State.azure.language and not App.Config.Azure.languages[App.State.azure.language] then
            local firstLanguage = languages[1]
            if firstLanguage then
                App.State.azure.language = firstLanguage.id
                App.State.azure.languageIndex = 0
                if items.azureLanguageCombo then
                    items.azureLanguageCombo.CurrentIndex = 0
                end
            end
        end
        local voiceTypes = App.Config.Azure.voiceTypesList or {}
        if not App.State.azure.voiceType then
            local firstType = voiceTypes[1]
            App.State.azure.voiceType = firstType and firstType.id or "Neutral"
            App.State.azure.voiceTypeIndex = 0
        end
        if App.State.azure.voiceType and not App.Config.Azure.voiceTypes[App.State.azure.voiceType] then
            local firstType = voiceTypes[1]
            if firstType then
                App.State.azure.voiceType = firstType.id
                App.State.azure.voiceTypeIndex = 0
                if items.azureVoiceTypeCombo then
                    items.azureVoiceTypeCombo.CurrentIndex = 0
                end
            end
        end

        local voiceIndex = options.voiceIndex
        if voiceIndex == nil then
            voiceIndex = App.State.azure.voiceIndex or 0
        end
        if options.resetVoice then
            voiceIndex = 0
        end

        local selectedVoice, actualIndex = App.UI.populateAzureVoices(
            App.State.azure.language,
            App.State.azure.voiceType,
            voiceIndex
        )
        App.State.azure.voiceIndex = actualIndex or 0

        local stylePreference
        if not options.resetStyle then
            stylePreference = App.State.azure.style
        end
        App.UI.populateAzureStyles(
            App.State.azure.language,
            App.State.azure.voiceId,
            stylePreference
        )

        if options.resetMultilingual then
            App.State.azure.multilingual = "Default"
            App.State.azure.multilingualIndex = 0
        end
        local multilingualPreference
        if not options.resetMultilingual and App.State.azure.multilingual and App.State.azure.multilingual ~= "Default" then
            multilingualPreference = App.State.azure.multilingual
        end
        App.UI.populateAzureMultilingual(
            App.State.azure.language,
            App.State.azure.voiceId,
            multilingualPreference
        )
    end
    local ok, err = pcall(run)
    App.State.azure.isUpdating = false
    if not ok then
        print("[DaVinci TTS] refreshAzureVoices failed: " .. tostring(err))
    end
end

function App.UI.populateMiniMaxCombos()
    local cfg = App.Config.MiniMax
    local selectedModel, modelIndex = App.UI.populateCombo(
        App.UI.items.minimaxModelCombo,
        cfg.models,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.modelIndex
    )
    local fallbackModel = cfg.models[1] or { id = "speech-01-turbo" }
    App.State.minimax.model = selectedModel and selectedModel.id or fallbackModel.id
    App.State.minimax.modelIndex = modelIndex or 0

    local selectedLanguage, languageIndex = App.UI.populateCombo(
        App.UI.items.minimaxLanguageCombo,
        cfg.languages,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.languageIndex
    )
    local fallbackLanguage = cfg.languages[1] or { id = "中文（普通话）" }
    App.State.minimax.language = selectedLanguage and selectedLanguage.id or fallbackLanguage.id
    App.State.minimax.languageIndex = languageIndex or 0

    local voices = cfg.voices[App.State.minimax.language] or {}
    App.State.minimax.voiceList = voices
    local selectedVoice, voiceIndex = App.UI.populateCombo(
        App.UI.items.minimaxVoiceCombo,
        voices,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.voiceIndex
    )
    local fallbackVoice = voices[1]
    App.State.minimax.voice = selectedVoice and selectedVoice.id or (fallbackVoice and fallbackVoice.id)
    App.State.minimax.voiceIndex = voiceIndex or 0

    local selectedEmotion, emotionIndex = App.UI.populateCombo(
        App.UI.items.minimaxEmotionCombo,
        cfg.emotions,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.emotionIndex
    )
    local fallbackEmotion = cfg.emotions[1] or { id = "default" }
    App.State.minimax.emotion = selectedEmotion and selectedEmotion.id or fallbackEmotion.id
    App.State.minimax.emotionIndex = emotionIndex or 0

    -- 音效只在音色效果器窗口使用
    if App.UI.minimaxVoiceModifyItems and App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo then
        local _, effectIndex2 = App.UI.populateCombo(
            App.UI.minimaxVoiceModifyItems.minimaxSoundEffectCombo,
            cfg.soundEffects,
            nil,
            function(entry)
                return entry.id
            end,
            function(entry)
                return App.UI.localizeLabel(entry.labels)
            end,
            cfg.defaults.soundEffectIndex or 0
        )
        App.State.minimax.voiceEffectIndex = effectIndex2 or cfg.defaults.soundEffectIndex or 0
        local fallbackEffect = cfg.soundEffects[(App.State.minimax.voiceEffectIndex or 0) + 1] or cfg.soundEffects[1] or { id = "default" }
        App.State.minimax.soundEffect = fallbackEffect.id
    end
end

function App.UI.refreshMiniMaxVoices(options)
    options = options or {}
    if App.State.minimax.isUpdating then
        return
    end
    App.State.minimax.isUpdating = true
    local function run()
        local languages = App.Config.MiniMax.languages or {}
        if not App.State.minimax.language then
            local firstLanguage = languages[1]
            App.State.minimax.language = firstLanguage and firstLanguage.id or nil
            App.State.minimax.languageIndex = 0
        end
        if App.State.minimax.language and not App.Config.MiniMax.voices[App.State.minimax.language] then
            local firstLanguage = languages[1]
            if firstLanguage then
                App.State.minimax.language = firstLanguage.id
                App.State.minimax.languageIndex = 0
                if items.minimaxLanguageCombo then
                    items.minimaxLanguageCombo.CurrentIndex = 0
                end
            end
        end

        local voices = App.Config.MiniMax.voices[App.State.minimax.language] or {}
        App.State.minimax.voiceList = voices

        local voiceIndex = options.voiceIndex
        local selectVoiceId = options.selectVoiceId
        if voiceIndex == nil then
            voiceIndex = App.State.minimax.voiceIndex or 0
        end
        if options.resetVoice then
            voiceIndex = 0
        end
        if selectVoiceId and #voices > 0 then
            for idx, entry in ipairs(voices) do
                if entry.id == selectVoiceId then
                    voiceIndex = idx - 1
                    break
                end
            end
        end

        local selectedVoice, actualIndex = App.UI.populateCombo(
            App.UI.items.minimaxVoiceCombo,
            voices,
            nil,
            function(entry)
                return entry.id
            end,
            function(entry)
                return App.UI.localizeLabel(entry.labels)
            end,
            voiceIndex
        )
        local fallbackVoice = voices[1]
        App.State.minimax.voice = selectedVoice and selectedVoice.id or (fallbackVoice and fallbackVoice.id)
        App.State.minimax.voiceIndex = actualIndex or 0
    end
    local ok, err = pcall(run)
    App.State.minimax.isUpdating = false
    if not ok then
        print("[DaVinci TTS] refreshMiniMaxVoices failed: " .. tostring(err))
    end
end

function App.UI.populateOpenAICombos()
    local cfg = App.Config.OpenAI
    local selectedModel, modelIndex = App.UI.populateCombo(
        App.UI.items.OpenAIModelCombo,
        cfg.models,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.modelIndex
    )
    local fallbackModel = cfg.models[1] or { id = "gpt-4o-mini-tts" }
    App.State.openai.model = selectedModel and selectedModel.id or fallbackModel.id
    App.State.openai.modelIndex = modelIndex or 0

    local selectedVoice, voiceIndex = App.UI.populateCombo(
        App.UI.items.OpenAIVoiceCombo,
        cfg.voices,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.voiceIndex
    )
    local fallbackVoice = cfg.voices[1] or { id = "alloy" }
    App.State.openai.voice = selectedVoice and selectedVoice.id or fallbackVoice.id
    App.State.openai.voiceIndex = voiceIndex or 0

    local selectedPreset, presetIndex = App.UI.populateCombo(
        App.UI.items.OpenAIPresetCombo,
        cfg.presets,
        nil,
        function(entry)
            return entry.id
        end,
        function(entry)
            return App.UI.localizeLabel(entry.labels)
        end,
        cfg.defaults.presetIndex
    )
    local fallbackPreset = cfg.presets[1] or { id = "Custom" }
    App.State.openai.preset = selectedPreset and selectedPreset.id or fallbackPreset.id
    App.State.openai.presetIndex = presetIndex or 0

end

function App.UI.writeCombos()
    App.UI.populateAzureCombos()
    App.UI.populateMiniMaxCombos()
    App.UI.populateOpenAICombos()
end

function App.UI.updateAzureApiInputs(useApiEnabled)
    local azureItems = App.UI.azureItems or {}
    local enabled = useApiEnabled ~= false
    setEnabledSafe(azureItems.ApiKey, enabled)
    setEnabledSafe(azureItems.Region, enabled)
end

function App.UI.bindDefaults()
    local items = App.UI.items
    local azureItems = App.UI.azureItems
    local minimaxItems = App.UI.minimaxItems
    local openaiItems = App.UI.openaiItems
    local cloneItems = App.UI.minimaxCloneItems
    local loadingItems = App.UI.loadingItems

    local settingsDefaults = App.Config.Settings.defaults
    local azureDefaults = App.Config.Azure.defaults
    local minimaxDefaults = App.Config.MiniMax.defaults
    local minimaxCloneDefaults = App.Config.MiniMax.cloneDefaults
    local openaiDefaults = App.Config.OpenAI.defaults
    local azureUseApi = azureDefaults.useApi ~= false
    azureUseApiProgrammatic = true
    setCheckedSafe(azureItems.UseAPICheckBox, azureUseApi)
    azureUseApiProgrammatic = false
    setTextSafe(azureItems.ApiKey, azureDefaults.apiKey)
    setTextSafe(azureItems.Region, azureDefaults.region)
    App.State.azure.useApi = azureUseApi
    App.UI.updateAzureApiInputs(azureUseApi)

    setValueSafe(items.azureBreakSpinBox, azureDefaults.breakMs)
    setValueSafe(items.azureStyleDegreeSpinBox, azureDefaults.styleDegree)
    setValueSafe(items.azureStyleDegreeSlider, scaledValue(azureDefaults.styleDegree, 100))
    setValueSafe(items.azureRateSpinBox, azureDefaults.rate)
    setValueSafe(items.azureRateSlider, scaledValue(azureDefaults.rate, 100))
    setValueSafe(items.azurePitchSpinBox, azureDefaults.pitch)
    setValueSafe(items.azurePitchSlider, scaledValue(azureDefaults.pitch, 100))
    setValueSafe(items.azureVolumeSpinBox, azureDefaults.volume)
    setValueSafe(items.azureVolumeSlider, scaledValue(azureDefaults.volume, 100))
    setTextSafe(items.azureText, "")

    App.State.azure.breakMs = azureDefaults.breakMs
    App.State.azure.styleDegree = azureDefaults.styleDegree
    App.State.azure.rate = azureDefaults.rate
    App.State.azure.pitch = azureDefaults.pitch
    App.State.azure.volume = azureDefaults.volume

    setTextSafe(minimaxItems.minimaxApiKey, minimaxDefaults.apiKey)
    setTextSafe(minimaxItems.minimaxGroupID, minimaxDefaults.groupId)
    setCheckedSafe(minimaxItems.intlCheckBox, minimaxDefaults.intl)

    setValueSafe(items.minimaxBreakSpinBox, minimaxDefaults.breakMs)
    setValueSafe(items.minimaxRateSpinBox, minimaxDefaults.rate)
    setValueSafe(items.minimaxRateSlider, scaledValue(minimaxDefaults.rate, 100))
    setValueSafe(items.minimaxVolumeSpinBox, minimaxDefaults.volume)
    setValueSafe(items.minimaxVolumeSlider, scaledValue(minimaxDefaults.volume, 100))
    setValueSafe(items.minimaxPitchSpinBox, minimaxDefaults.pitch)
    setValueSafe(items.minimaxPitchSlider, scaledValue(minimaxDefaults.pitch, 100))
    setCheckedSafe(items.minimaxSubtitleCheckBox, minimaxDefaults.subtitle)
    setTextSafe(items.minimaxText, "")

    App.State.minimax.breakMs = minimaxDefaults.breakMs
    App.State.minimax.rate = minimaxDefaults.rate
    App.State.minimax.volume = minimaxDefaults.volume
    App.State.minimax.pitch = minimaxDefaults.pitch
    App.State.minimax.subtitle = minimaxDefaults.subtitle
    App.State.minimax.voiceTimbre = minimaxDefaults.voiceTimbre or 0
    App.State.minimax.voiceIntensity = minimaxDefaults.voiceIntensity or 0
    App.State.minimax.voicePitch = minimaxDefaults.voicePitch or 0
    App.State.minimax.voiceEffectIndex = minimaxDefaults.soundEffectIndex or 0
    local vmItems = App.UI.minimaxVoiceModifyItems
    if vmItems then
        local function setModifyWidgets(prefix, value)
            value = tonumber(value) or 0
            setValueSafe(vmItems[prefix .. "Slider"], value)
            setValueSafe(vmItems[prefix .. "SpinBoxLeft"], value < 0 and value or 0)
            setValueSafe(vmItems[prefix .. "SpinBoxRight"], value > 0 and value or 0)
        end
        setModifyWidgets("minimaxTimbre", App.State.minimax.voiceTimbre)
        setModifyWidgets("minimaxIntensity", App.State.minimax.voiceIntensity)
        setModifyWidgets("minimaxModifyPitch", App.State.minimax.voicePitch)
        if vmItems.minimaxSoundEffectCombo then
            vmItems.minimaxSoundEffectCombo.CurrentIndex = App.State.minimax.voiceEffectIndex or 0
        end
    end

    if cloneItems then
        setCheckedSafe(cloneItems.minimaxOnlyAddID, minimaxCloneDefaults.onlyAddId)
        setCheckedSafe(cloneItems.minimaxNeedNoiseReduction, minimaxCloneDefaults.needNoiseReduction)
        setCheckedSafe(cloneItems.minimaxNeedVolumeNormalization, minimaxCloneDefaults.needVolumeNormalization)
        setTextSafe(cloneItems.minimaxClonePreviewText, minimaxCloneDefaults.previewText)
        local cloneInfoText = App.Config.Settings.cloneInfo[App.State.locale] or minimaxCloneDefaults.displayInfo
        setTextSafe(cloneItems.minimaxcloneinfoTxt, cloneInfoText)
        setTextSafe(cloneItems.minimaxCloneVoiceName, "")
        setTextSafe(cloneItems.minimaxCloneVoiceID, "")
        setTextSafe(cloneItems.minimaxCloneFileID, "")
        setTextSafe(cloneItems.minimaxCloneStatus, "")
    end

    setTextSafe(openaiItems.OpenAIApiKey, openaiDefaults.apiKey)
    setTextSafe(openaiItems.OpenAIBaseURL, openaiDefaults.baseUrl)
    setTextSafe(items.OpenAIInstructionText, openaiDefaults.instruction)
    setValueSafe(items.OpenAIRateSpinBox, openaiDefaults.rate)
    setValueSafe(items.OpenAIRateSlider, scaledValue(openaiDefaults.rate, 100))
    setTextSafe(items.OpenAIText, "")

    App.State.openai.rate = openaiDefaults.rate
    App.State.openai.instruction = openaiDefaults.instruction

    setTextSafe(items.Path, settingsDefaults.outputPath)
    local infoText = App.Config.Settings.info[App.State.locale] or App.Config.Settings.info.cn or ""
    setTextSafe(items.infoTxt, infoText)
    setTextSafe(items.CopyrightButton, settingsDefaults.copyright)

    local isChinese = (App.State.locale == "cn")
    setCheckedSafe(items.LangCnCheckBox, isChinese)
    setCheckedSafe(items.LangEnCheckBox, not isChinese)

    if loadingItems then
        setTextSafe(loadingItems.UpdateLabel, "")
        setVisibleSafe(loadingItems.UpdateLabel, false)
        setTextSafe(loadingItems.LoadLabel, "Loading...")
        setVisibleSafe(loadingItems.ConfirmButton, false)
        setEnabledSafe(loadingItems.ConfirmButton, false)
    end

    if App.UI.msgboxItems then
        setTextSafe(App.UI.msgboxItems.InfoLabel, "")
    end
    if msgbox and msgbox.Hide then
        msgbox:Hide()
    end

    local presetEntry = App.Config.OpenAI.presets[(App.State.openai.presetIndex or 0) + 1]
    if (openaiDefaults.instruction or "") == "" and presetEntry and presetEntry.description and presetEntry.description ~= "" then
        setTextSafe(items.OpenAIInstructionText, presetEntry.description)
        App.State.openai.instruction = presetEntry.description
    end
end

local loadingUpdatePending = false

local function onLoadingConfirm(ev)
    if not loadingUpdatePending then
        return
    end
    local loadingItems = App.UI.loadingItems
    if loadingItems then
        setEnabledSafe(loadingItems.ConfirmButton, false)
        setVisibleSafe(loadingItems.ConfirmButton, false)
        setVisibleSafe(loadingItems.UpdateLabel, false)
        setVisibleSafe(loadingItems.LoadLabel, true)
        setTextSafe(loadingItems.LoadLabel, "Loading...")
    end
    loadingUpdatePending = false
    if dispatcher and dispatcher.ExitLoop then
        dispatcher:ExitLoop()
    end
end

function App.checkForUpdates()
    local loadingItems = App.UI.loadingItems
    local ok, result = pcall(Services.supabaseCheckUpdate, SCRIPT_NAME)
    if not ok then
        print(string.format("[Update] Check failed: %s", tostring(result)))
        return
    end
    if type(result) ~= "table" then
        return
    end
    local latest = trim(tostring(result.latest or ""))
    if latest == "" then
        return
    end
    local current = trim(tostring(SCRIPT_VERSION or ""))
    if latest == current then
        return
    end

    local lang = (App.State.locale == "cn") and "cn" or "en"
    local fallback = (lang == "cn") and "en" or "cn"
    local primary = trim(tostring(result[lang] or ""))
    local secondary = trim(tostring(result[fallback] or ""))
    local lines = {}
    if primary ~= "" then
        table.insert(lines, primary)
    elseif secondary ~= "" then
        table.insert(lines, secondary)
    end
    local readableCurrent = current ~= "" and current or ((lang == "cn") and "未知" or "unknown")
    local versionLine
    if lang == "cn" then
        versionLine = string.format("发现新版本：%s → %s，请前往购买页下载最新版本。", readableCurrent, latest)
    else
        versionLine = string.format("Update: %s → %s, Download on your purchase page.", readableCurrent, latest)
    end
    table.insert(lines, versionLine)
    local notice = table.concat(lines, "\n")

    if loadingItems then
        setTextSafe(loadingItems.UpdateLabel, notice)
        setVisibleSafe(loadingItems.UpdateLabel, true)
        setVisibleSafe(loadingItems.LoadLabel, false)
        setVisibleSafe(loadingItems.ConfirmButton, true)
        setEnabledSafe(loadingItems.ConfirmButton, true)
        if loadingItems.UpdateLabel then
            loadingItems.UpdateLabel.StyleSheet = "color:#ff5555; font-size:20px;"
        end
    end

    loadingUpdatePending = true
    print(string.format("[Update] Latest version %s available (current %s).", latest, readableCurrent))
    if dispatcher and dispatcher.RunLoop and loadingItems then
        dispatcher:RunLoop()
    end
    loadingUpdatePending = false

    if loadingItems then
        setVisibleSafe(loadingItems.UpdateLabel, false)
        setVisibleSafe(loadingItems.ConfirmButton, false)
        setEnabledSafe(loadingItems.ConfirmButton, false)
        setVisibleSafe(loadingItems.LoadLabel, true)
        setTextSafe(loadingItems.LoadLabel, "Loading...")
    end
end

if loadingWin and loadingWin.On then
    function loadingWin.On.ConfirmButton.Clicked(ev)
        onLoadingConfirm(ev)
    end
end

local function resetAzureTabToDefaults()
    local items = App.UI.items or {}
    local defaults = App.Config.Azure.defaults
    if not defaults or not items then
        return
    end
    local state = App.State.azure or {}
    local styleDegree = defaults.styleDegree or 1.0
    local rate = defaults.rate or 1.0
    local pitch = defaults.pitch or 1.0
    local volume = defaults.volume or 1.0
    setValueSafe(items.azureStyleDegreeSpinBox, styleDegree)
    setValueSafe(items.azureStyleDegreeSlider, scaledValue(styleDegree, 100))
    setValueSafe(items.azureRateSpinBox, rate)
    setValueSafe(items.azureRateSlider, scaledValue(rate, 100))
    setValueSafe(items.azurePitchSpinBox, pitch)
    setValueSafe(items.azurePitchSlider, scaledValue(pitch, 100))
    setValueSafe(items.azureVolumeSpinBox, volume)
    setValueSafe(items.azureVolumeSlider, scaledValue(volume, 100))
    state.styleDegree = defaults.styleDegree or 1.0
    state.rate = defaults.rate or 1.0
    state.pitch = defaults.pitch or 1.0
    state.volume = defaults.volume or 1.0
end

local function resetMiniMaxTabToDefaults()
    local items = App.UI.items or {}
    local defaults = App.Config.MiniMax.defaults
    if not defaults or not items then
        return
    end
    local state = App.State.minimax or {}
    local rate = defaults.rate or 1.0
    local volume = defaults.volume or 1.0
    local pitch = defaults.pitch or 0
    setValueSafe(items.minimaxRateSpinBox, rate)
    setValueSafe(items.minimaxRateSlider, scaledValue(rate, 100))
    setValueSafe(items.minimaxVolumeSpinBox, volume)
    setValueSafe(items.minimaxVolumeSlider, scaledValue(volume, 100))
    setValueSafe(items.minimaxPitchSpinBox, pitch)
    setValueSafe(items.minimaxPitchSlider, scaledValue(pitch, 100))
    state.rate = rate
    state.volume = volume
    state.pitch = pitch
    local vmItems = App.UI.minimaxVoiceModifyItems
    if vmItems then
        setVoiceModifyValue("timbre", defaults.voiceTimbre or 0)
        setVoiceModifyValue("intensity", defaults.voiceIntensity or 0)
        setVoiceModifyValue("pitch", defaults.voicePitch or 0)
        if vmItems.minimaxSoundEffectCombo then
            vmItems.minimaxSoundEffectCombo.CurrentIndex = defaults.soundEffectIndex or 0
        end
        state.voiceTimbre = defaults.voiceTimbre or 0
        state.voiceIntensity = defaults.voiceIntensity or 0
        state.voicePitch = defaults.voicePitch or 0
        state.voiceEffectIndex = defaults.soundEffectIndex or 0
    end
end

local function resetOpenAITabToDefaults()
    local items = App.UI.items or {}
    local defaults = App.Config.OpenAI.defaults
    if not defaults or not items then
        return
    end
    local state = App.State.openai or {}
    local rate = defaults.rate or 1.0
    setValueSafe(items.OpenAIRateSpinBox, rate)
    setValueSafe(items.OpenAIRateSlider, scaledValue(rate, 100))
    state.rate = rate
end

local languageProgrammatic = false
local azureUseApiProgrammatic = false

function App.UI.buildTranslations()
    local info = App.Config.Settings.info or {}
    local cloneInfo = App.Config.Settings.cloneInfo or {}
    local infoCn = info.cn or ""
    local infoEn = info.en or ""
    local cloneInfoCn = cloneInfo.cn or ""
    local cloneInfoEn = cloneInfo.en or ""
    local copyrightCn = string.format("关注公众号：游艺所\n\n☕用一杯咖啡为创意充电☕\n\n© 2025, Copyright by %s.", SCRIPT_AUTHOR)
    local copyrightEn = string.format("☕ Fuel creativity with a coffee ☕\n\n© 2025, Copyright by %s.", SCRIPT_AUTHOR)

    return {
        cn = {
            Tabs = { "微软语音", "MiniMax 语音", "OpenAI 语音", "设置" },
            azureGetSubButton = "从时间线获取字幕",
            minimaxGetSubButton = "从时间线获取字幕",
            OpenAIGetSubButton = "从时间线获取字幕",
            azureBreakLabel = "ms",
            minimaxBreakLabel = "ms",
            azureBreakButton = "停顿",
            minimaxBreakButton = "停顿",
            minimaxModelLabel = "模型",
            OpenAIModelLabel = "模型",
            minimaxLanguageLabel = "语言",
            minimaxVoiceLabel = "音色",
            OpenAIVoiceLabel = "音色",
            OpenAIPresetLabel = "预设",
            OpenAIPreviewButton = "试听",
            OpenAIInstructionLabel = "指令",
            minimaxPreviewButton = "试听",
            openGuideButton = "使用教程",
            azureLanguageLabel = "语言",
            azureVoiceTypeLabel = "类型",
            azureVoiceLabel = "名称",
            azureMultilingualLabel = "语言技能",
            azureStyleLabel = "风格",
            minimaxEmotionLabel = "情绪",
            minimaxSoundEffectLabel = "音效",
            azureStyleDegreeLabel = "风格强度",
            azureRateLabel = "语速",
            minimaxRateLabel = "语速",
            OpenAIRateLabel = "语速",
            azurePitchLabel = "音调",
            minimaxPitchLabel = "音调",
            azureVolumeLabel = "音量",
            minimaxVolumeLabel = "音量",
            outputFormatLabel = "格式",
            azurePlayButton = "试听",
            azureFromSubButton = "朗读当前字幕",
            minimaxFromSubButton = "朗读当前字幕",
            OpenAIFromSubButton = "朗读当前字幕",
            azureFromTxtButton = "朗读文本框",
            minimaxFromTxtButton = "朗读文本框",
            OpenAIFromTxtButton = "朗读文本框",
            azureResetButton = "重置",
            minimaxResetButton = "重置",
            OpenAIResetButton = "重置",
            PathLabel = "保存路径",
            Browse = "浏览",
            ShowAzure = "配置",
            ShowMiniMax = "配置",
            ShowOpenAI = "配置",
            ShowMiniMaxClone = "克隆",
            minimaxVoiceEffectButton = "音色效果调节",
            minimaxDeleteVoice = "删除",
            CopyrightButton = copyrightCn,
            infoTxt = infoCn,
            AzureLabel = "填写Azure API信息",
            RegionLabel = "区域",
            ApiKeyLabel = "密钥",
            UseAPICheckBox = "使用 API",
            minimaxSubtitleCheckBox = "生成srt字幕",
            AzureConfirm = "确定",
            AzureRegisterButton = "注册",
            minimaxLabel = "填写MiniMax API信息",
            minimaxCloneLabel = "添加 MiniMaxAI 克隆音色",
            minimaxCloneVoiceNameLabel = "音色名字",
            minimaxCloneVoiceIDLabel = "音色 ID",
            minimaxOnlyAddID = "已有克隆音色ID（在下方填入添加即可）",
            minimaxCloneFileIDLabel = "音频 ID",
            minimaxNeedNoiseReduction = "开启降噪",
            minimaxNeedVolumeNormalization = "音量统一",
            minimaxClonePreviewLabel = "输入试听文本(限制300字以内)：",
            minimaxcloneinfoTxt = cloneInfoCn,
            minimaxApiKeyLabel = "密钥",
            intlCheckBox = "海外",
            MiniMaxConfirm = "确定",
            MiniMaxCloneConfirm = "添加",
            MiniMaxCloneCancel = "取消",
            minimaxRegisterButton = "注册",
            OpenAILabel = "填写OpenAI API信息",
            OpenAIBaseURLLabel = "Base URL",
            OpenAIApiKeyLabel = "密钥",
            OpenAIConfirm = "确定",
            OpenAIRegisterButton = "注册",
        },
        en = {
            Tabs = { "Azure TTS", "MiniMax TTS", "OpenAI TTS", "Settings" },
            azureGetSubButton = "Timeline Subs",
            minimaxGetSubButton = "Timeline Subs",
            OpenAIGetSubButton = "Timeline Subs",
            azureBreakLabel = "ms",
            minimaxBreakLabel = "ms",
            azureBreakButton = "Break",
            minimaxBreakButton = "Break",
            minimaxModelLabel = "Model",
            OpenAIModelLabel = "Model",
            minimaxLanguageLabel = "Language",
            minimaxVoiceLabel = "Voice",
            OpenAIVoiceLabel = "Voice",
            OpenAIPresetLabel = "Preset",
            OpenAIPreviewButton = "Preview",
            OpenAIInstructionLabel = "Instruction",
            minimaxPreviewButton = "Preview",
            openGuideButton = "Usage Tutorial",
            azureLanguageLabel = "Language",
            azureVoiceTypeLabel = "Type",
            azureVoiceLabel = "Name",
            azureMultilingualLabel = "Multilingual",
            azureStyleLabel = "Style",
            minimaxEmotionLabel = "Emotion",
            minimaxSoundEffectLabel = "Effect",
            azureStyleDegreeLabel = "Style Degree",
            azureRateLabel = "Rate",
            minimaxRateLabel = "Rate",
            OpenAIRateLabel = "Rate",
            azurePitchLabel = "Pitch",
            minimaxPitchLabel = "Pitch",
            azureVolumeLabel = "Volume",
            minimaxVolumeLabel = "Volume",
            outputFormatLabel = "Format",
            azurePlayButton = "Preview",
            azureFromSubButton = "Read Subs",
            minimaxFromSubButton = "Read Subs",
            OpenAIFromSubButton = "Read Subs",
            azureFromTxtButton = "Read Textbox",
            minimaxFromTxtButton = "Read Textbox",
            OpenAIFromTxtButton = "Read Textbox",
            azureResetButton = "Reset",
            minimaxResetButton = "Reset",
            OpenAIResetButton = "Reset",
            PathLabel = "Path",
            Browse = "Browse",
            ShowAzure = "Config",
            ShowMiniMax = "Config",
            ShowOpenAI = "Config",
            ShowMiniMaxClone = "Clone",
            minimaxVoiceEffectButton = "Voice Effects",
            minimaxDeleteVoice = "Delete",
            CopyrightButton = copyrightEn,
            infoTxt = infoEn,
            AzureLabel = "Azure API",
            RegionLabel = "Region",
            ApiKeyLabel = "Key",
            UseAPICheckBox = "Use API",
            minimaxSubtitleCheckBox = "Subtitle Enable",
            AzureConfirm = "OK",
            AzureRegisterButton = "Register",
            minimaxLabel = "MiniMax API",
            minimaxCloneLabel = "Add MiniMax Clone Voice",
            minimaxCloneVoiceNameLabel = "Voice Name",
            minimaxCloneVoiceIDLabel = "Voice ID",
            minimaxOnlyAddID = "I already have a clone voice.(just fill in below).",
            minimaxCloneFileIDLabel = "File ID",
            minimaxNeedNoiseReduction = "Noise Reduction",
            minimaxNeedVolumeNormalization = "Volume Normalization",
            minimaxClonePreviewLabel = "Input text for cloned voice preview:\n(Limited to 2000 characters.)",
            minimaxcloneinfoTxt = cloneInfoEn,
            minimaxApiKeyLabel = "Key",
            intlCheckBox = "intl",
            MiniMaxConfirm = "OK",
            MiniMaxCloneConfirm = "Add",
            MiniMaxCloneCancel = "Cancel",
            minimaxRegisterButton = "Register",
            OpenAILabel = "OpenAI API",
            OpenAIBaseURLLabel = "Base URL",
            OpenAIApiKeyLabel = "Key",
            OpenAIConfirm = "OK",
            OpenAIRegisterButton = "Register",
        },
    }
end

local function applyTextToControls(key, value)
    local targets = {
        App.UI.items,
        App.UI.azureItems,
        App.UI.minimaxItems,
        App.UI.openaiItems,
        App.UI.minimaxCloneItems,
    }
    for _, tbl in ipairs(targets) do
        if tbl and tbl[key] then
            setTextSafe(tbl[key], value)
            return true
        end
    end
    return false
end

function App.UI.applyLocale(locale)
    if locale ~= "cn" then
        locale = "en"
    end

    App.State.locale = locale
    Config.Settings.locale = locale
    if Config.Settings.saved then
        Config.Settings.saved.CN = (locale == "cn")
        Config.Settings.saved.EN = (locale == "en")
    end

    App.UI.translations = App.UI.buildTranslations()
    local texts = App.UI.translations[locale] or {}

    languageProgrammatic = true
    setCheckedSafe(App.UI.items.LangCnCheckBox, locale == "cn")
    setCheckedSafe(App.UI.items.LangEnCheckBox, locale == "en")
    languageProgrammatic = false

    local tabWidget = App.UI.items.MyTabs
    if tabWidget and tabWidget.SetTabText and texts.Tabs then
        for index, title in ipairs(texts.Tabs) do
            tabWidget:SetTabText(index - 1, title)
        end
    end

    for key, value in pairs(texts) do
        if key ~= "Tabs" then
            applyTextToControls(key, value)
        end
    end

    local azureDefaults = App.Config.Azure.defaults or {}
    local azureState = App.State.azure or {}
    azureDefaults.languageIndex = azureState.languageIndex or azureDefaults.languageIndex or 0
    azureDefaults.voiceTypeIndex = azureState.voiceTypeIndex or azureDefaults.voiceTypeIndex or 0
    azureDefaults.voiceIndex = azureState.voiceIndex or azureDefaults.voiceIndex or 0
    azureDefaults.styleIndex = azureState.styleIndex or azureDefaults.styleIndex or 0
    azureDefaults.multilingualIndex = azureState.multilingualIndex or azureDefaults.multilingualIndex or 0
    azureDefaults.outputFormatIndex = azureState.outputFormatIndex or azureDefaults.outputFormatIndex or 0

    azureState.isUpdating = true
    local ok, err = pcall(App.UI.populateAzureCombos)
    if not ok then
        print("[DaVinci TTS] populateAzureCombos failed during locale switch: " .. tostring(err))
    end
    azureState.isUpdating = false

    if azureState.style then
        App.UI.populateAzureStyles(azureState.language, azureState.voiceId, azureState.style)
    end
    if azureState.multilingual then
        App.UI.populateAzureMultilingual(azureState.language, azureState.voiceId, azureState.multilingual)
    end

    local minimaxDefaults = App.Config.MiniMax.defaults or {}
    local minimaxState = App.State.minimax or {}
    minimaxDefaults.modelIndex = minimaxState.modelIndex or minimaxDefaults.modelIndex or 0
    minimaxDefaults.languageIndex = minimaxState.languageIndex or minimaxDefaults.languageIndex or 0
    minimaxDefaults.voiceIndex = minimaxState.voiceIndex or minimaxDefaults.voiceIndex or 0
    minimaxDefaults.emotionIndex = minimaxState.emotionIndex or minimaxDefaults.emotionIndex or 0
    minimaxDefaults.soundEffectIndex = minimaxState.soundEffectIndex or minimaxDefaults.soundEffectIndex or 0

    minimaxState.isUpdating = true
    ok, err = pcall(App.UI.populateMiniMaxCombos)
    if not ok then
        print("[DaVinci TTS] populateMiniMaxCombos failed during locale switch: " .. tostring(err))
    end
    minimaxState.isUpdating = false

    local openaiDefaults = App.Config.OpenAI.defaults or {}
    local openaiState = App.State.openai or {}
    openaiDefaults.modelIndex = openaiState.modelIndex or openaiDefaults.modelIndex or 0
    openaiDefaults.voiceIndex = openaiState.voiceIndex or openaiDefaults.voiceIndex or 0
    openaiDefaults.presetIndex = openaiState.presetIndex or openaiDefaults.presetIndex or 0

    App.UI.populateOpenAICombos()

    if openaiState.instruction and openaiState.instruction ~= "" then
        setTextSafe(App.UI.items.OpenAIInstructionText, openaiState.instruction)
    end
end

function App.UI.initialize()
    if not App.State.locale then
        App.State.locale = App.Config.Settings.locale or "en"
    end
    App.UI.writeCombos()
    App.UI.bindDefaults()
    App.UI.applyLocale(App.State.locale)
end

App.UI.initialize()
App.Controller.onProviderChanged(App.UI.items.MyTabs and (App.UI.items.MyTabs.CurrentIndex or 0) or 0)

local function getAzureLanguageEntry(index)
    local entries = App.Config.Azure.languagesList or {}
    return entries[index + 1]
end

local function getAzureVoiceTypeEntry(index)
    local entries = App.Config.Azure.voiceTypesList or {}
    return entries[index + 1]
end

local styleDegreeSliderHandler = buildSliderSyncHandler("AzureStyleDegree", "azureStyleDegreeSpinBox", 0.01, 2)
local styleDegreeSpinHandler = buildSliderSyncHandler("AzureStyleDegree", "azureStyleDegreeSlider", 100, 0)
local azureRateSliderHandler = buildSliderSyncHandler("AzureRate", "azureRateSpinBox", 0.01, 2)
local azureRateSpinHandler = buildSliderSyncHandler("AzureRate", "azureRateSlider", 100, 0)
local azurePitchSliderHandler = buildSliderSyncHandler("AzurePitch", "azurePitchSpinBox", 0.01, 2)
local azurePitchSpinHandler = buildSliderSyncHandler("AzurePitch", "azurePitchSlider", 100, 0)
local azureVolumeSliderHandler = buildSliderSyncHandler("AzureVolume", "azureVolumeSpinBox", 0.01, 2)
local azureVolumeSpinHandler = buildSliderSyncHandler("AzureVolume", "azureVolumeSlider", 100, 0)

local minimaxRateSliderHandler = buildSliderSyncHandler("MiniMaxRate", "minimaxRateSpinBox", 0.01, 2)
local minimaxRateSpinHandler = buildSliderSyncHandler("MiniMaxRate", "minimaxRateSlider", 100, 0)
local minimaxVolumeSliderHandler = buildSliderSyncHandler("MiniMaxVolume", "minimaxVolumeSpinBox", 0.01, 2)
local minimaxVolumeSpinHandler = buildSliderSyncHandler("MiniMaxVolume", "minimaxVolumeSlider", 100, 0)
local minimaxPitchSliderHandler = buildSliderSyncHandler("MiniMaxPitch", "minimaxPitchSpinBox", 0.01, 2)
local minimaxPitchSpinHandler = buildSliderSyncHandler("MiniMaxPitch", "minimaxPitchSlider", 100, 0)

local openaiRateSliderHandler = buildSliderSyncHandler("OpenAIRate", "OpenAIRateSpinBox", 0.01, 2)
local openaiRateSpinHandler = buildSliderSyncHandler("OpenAIRate", "OpenAIRateSlider", 100, 0)

local function notifyUser(message)
    if not message or message == "" then
        return
    end
    controllerSetStatus(App.Controller.activeProvider or "azure", message)
end

function win.On.azureStyleDegreeSlider.ValueChanged(ev)
    styleDegreeSliderHandler(ev)
end

function win.On.azureStyleDegreeSpinBox.ValueChanged(ev)
    styleDegreeSpinHandler(ev)
end

function win.On.azureRateSlider.ValueChanged(ev)
    azureRateSliderHandler(ev)
end

function win.On.azureRateSpinBox.ValueChanged(ev)
    azureRateSpinHandler(ev)
end

function win.On.azurePitchSlider.ValueChanged(ev)
    azurePitchSliderHandler(ev)
end

function win.On.azurePitchSpinBox.ValueChanged(ev)
    azurePitchSpinHandler(ev)
end

function win.On.azureVolumeSlider.ValueChanged(ev)
    azureVolumeSliderHandler(ev)
end

function win.On.azureVolumeSpinBox.ValueChanged(ev)
    azureVolumeSpinHandler(ev)
end

function win.On.minimaxRateSlider.ValueChanged(ev)
    minimaxRateSliderHandler(ev)
end

function win.On.minimaxRateSpinBox.ValueChanged(ev)
    minimaxRateSpinHandler(ev)
end

function win.On.minimaxVolumeSlider.ValueChanged(ev)
    minimaxVolumeSliderHandler(ev)
end

function win.On.minimaxVolumeSpinBox.ValueChanged(ev)
    minimaxVolumeSpinHandler(ev)
end

function win.On.minimaxPitchSlider.ValueChanged(ev)
    minimaxPitchSliderHandler(ev)
end

function win.On.minimaxPitchSpinBox.ValueChanged(ev)
    minimaxPitchSpinHandler(ev)
end

function minimaxVoiceModifyWin.On.minimaxTimbreSlider.ValueChanged(ev)
    syncVoiceModifyFromControl("timbre", "minimaxTimbreSlider", eventNumericValue(ev))
end

function minimaxVoiceModifyWin.On.minimaxTimbreSpinBoxLeft.ValueChanged(ev)
    local value = -(math.abs(eventNumericValue(ev) or 0))
    syncVoiceModifyFromControl("timbre", "minimaxTimbreSpinBoxLeft", value)
end

function minimaxVoiceModifyWin.On.minimaxTimbreSpinBoxRight.ValueChanged(ev)
    local value = math.abs(eventNumericValue(ev) or 0)
    syncVoiceModifyFromControl("timbre", "minimaxTimbreSpinBoxRight", value)
end

function minimaxVoiceModifyWin.On.minimaxIntensitySlider.ValueChanged(ev)
    syncVoiceModifyFromControl("intensity", "minimaxIntensitySlider", eventNumericValue(ev))
end

function minimaxVoiceModifyWin.On.minimaxIntensitySpinBoxLeft.ValueChanged(ev)
    local value = -(math.abs(eventNumericValue(ev) or 0))
    syncVoiceModifyFromControl("intensity", "minimaxIntensitySpinBoxLeft", value)
end

function minimaxVoiceModifyWin.On.minimaxIntensitySpinBoxRight.ValueChanged(ev)
    local value = math.abs(eventNumericValue(ev) or 0)
    syncVoiceModifyFromControl("intensity", "minimaxIntensitySpinBoxRight", value)
end

function minimaxVoiceModifyWin.On.minimaxModifyPitchSlider.ValueChanged(ev)
    syncVoiceModifyFromControl("pitch", "minimaxModifyPitchSlider", eventNumericValue(ev))
end

function minimaxVoiceModifyWin.On.minimaxModifyPitchSpinBoxLeft.ValueChanged(ev)
    local value = -(math.abs(eventNumericValue(ev) or 0))
    syncVoiceModifyFromControl("pitch", "minimaxModifyPitchSpinBoxLeft", value)
end

function minimaxVoiceModifyWin.On.minimaxModifyPitchSpinBoxRight.ValueChanged(ev)
    local value = math.abs(eventNumericValue(ev) or 0)
    syncVoiceModifyFromControl("pitch", "minimaxModifyPitchSpinBoxRight", value)
end

function minimaxVoiceModifyWin.On.minimaxSoundEffectCombo.CurrentIndexChanged(ev)
    handleVoiceModifyEffectChange(ev)
end

function win.On.OpenAIRateSlider.ValueChanged(ev)
    openaiRateSliderHandler(ev)
end

function win.On.OpenAIRateSpinBox.ValueChanged(ev)
    openaiRateSpinHandler(ev)
end

function win.On.azureLanguageCombo.CurrentIndexChanged(ev)
    if App.State.azure.isUpdating then
        return
    end
    local index = items.azureLanguageCombo.CurrentIndex or 0
    index = clampIndex(index, #(App.Config.Azure.languagesList or {}))
    App.State.azure.languageIndex = index
    local entry = getAzureLanguageEntry(index)
    if entry then
        App.State.azure.language = entry.id
    end
    App.UI.refreshAzureVoices({
        resetVoice = true,
        resetStyle = true,
        resetMultilingual = true,
    })
end

function win.On.azureVoiceTypeCombo.CurrentIndexChanged(ev)
    if App.State.azure.isUpdating then
        return
    end
    local index = items.azureVoiceTypeCombo.CurrentIndex or 0
    index = clampIndex(index, #(App.Config.Azure.voiceTypesList or {}))
    App.State.azure.voiceTypeIndex = index
    local entry = getAzureVoiceTypeEntry(index)
    if entry then
        App.State.azure.voiceType = entry.id
    end
    App.UI.refreshAzureVoices({
        resetVoice = true,
        resetStyle = true,
        resetMultilingual = true,
    })
end

function win.On.azureVoiceCombo.CurrentIndexChanged(ev)
    if App.State.azure.isUpdating then
        return
    end
    local voiceList = App.State.azure.voiceList or {}
    local index = items.azureVoiceCombo.CurrentIndex or 0
    index = clampIndex(index, #voiceList)
    App.State.azure.voiceIndex = index
    local voice = voiceList[index + 1]
    if voice then
        App.State.azure.voiceId = voice.id
    end
    App.State.azure.isUpdating = true
    local ok, err = pcall(function()
        App.UI.populateAzureStyles(
            App.State.azure.language,
            App.State.azure.voiceId,
            nil
        )
        App.UI.populateAzureMultilingual(
            App.State.azure.language,
            App.State.azure.voiceId,
            nil
        )
    end)
    App.State.azure.isUpdating = false
    if not ok then
        print("[DaVinci TTS] azureVoiceCombo handler error: " .. tostring(err))
    end
end

function minimaxCloneWin.On.minimaxOnlyAddID.Clicked(ev)
    local items = App.UI.minimaxCloneItems
    if not items then
        return
    end
    App.MiniMaxClone.toggleMode(items.minimaxOnlyAddID and items.minimaxOnlyAddID.Checked)
end

function win.On.azureStyleCombo.CurrentIndexChanged(ev)
    if App.State.azure.isUpdating then
        return
    end
    local index = items.azureStyleCombo and items.azureStyleCombo.CurrentIndex or 0
    local options = App.State.azure.styleOptions or { "default" }
    index = clampIndex(index or 0, #options)
    App.State.azure.styleIndex = index
    local value = options[index + 1] or "default"
    if not value or value == "" then
        value = "default"
    end
    App.State.azure.style = value
end

function win.On.azureMultilingualCombo.CurrentIndexChanged(ev)
    if App.State.azure.isUpdating then
        return
    end
    local currentIndex = items.azureMultilingualCombo and items.azureMultilingualCombo.CurrentIndex or 0
    local options = App.State.azure.multilingualOptions or {}
    currentIndex = clampIndex(currentIndex or 0, #options + 1)
    App.State.azure.multilingualIndex = currentIndex
    if currentIndex == 0 or #options == 0 then
        App.State.azure.multilingual = "Default"
        return
    end
    local value = options[currentIndex]
    if not value or value == "" then
        App.State.azure.multilingual = "Default"
        App.State.azure.multilingualIndex = 0
    else
        App.State.azure.multilingual = value
    end
end

function win.On.LangCnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    App.UI.applyLocale("cn")
end

function win.On.LangEnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    App.UI.applyLocale("en")
end

function win.On.minimaxLanguageCombo.CurrentIndexChanged(ev)
    if App.State.minimax.isUpdating then
        return
    end
    local languageEntries = App.Config.MiniMax.languages or {}
    local index = items.minimaxLanguageCombo.CurrentIndex or 0
    index = clampIndex(index, #languageEntries)
    App.State.minimax.languageIndex = index
    local entry = languageEntries[index + 1]
    if entry then
        App.State.minimax.language = entry.id
    end
    App.UI.refreshMiniMaxVoices({
        resetVoice = true,
    })
end

function win.On.minimaxVoiceCombo.CurrentIndexChanged(ev)
    if App.State.minimax.isUpdating then
        return
    end
    local voiceList = App.State.minimax.voiceList or {}
    local index = items.minimaxVoiceCombo.CurrentIndex or 0
    index = clampIndex(index, #voiceList)
    App.State.minimax.voiceIndex = index
    local entry = voiceList[index + 1]
    if entry then
        App.State.minimax.voice = entry.id
    end
end

function win.On.minimaxDeleteVoice.Clicked(ev)
    local items = App.UI.items or {}
    local voiceList = App.State.minimax.voiceList or {}
    local index = items.minimaxVoiceCombo and (items.minimaxVoiceCombo.CurrentIndex or 0) or 0
    local entry = voiceList[index + 1]
    if not entry then
        return
    end
    local ok, err = App.MiniMaxClone.deleteCloneVoice(entry)
    if ok then
        App.MiniMaxClone.refreshVoices()
        App.MiniMaxClone.showStatus("delete_clone_succeed")
    else
        App.MiniMaxClone.showStatus(nil, err)
    end
end

local function getInitialTabTitles()
    local locale = (Config.Settings.locale == "cn") and "cn" or "en"
    if App.UI.buildTranslations then
        local translations = App.UI.buildTranslations()
        local texts = translations and translations[locale]
        if texts and texts.Tabs then
            return texts.Tabs
        end
    end
    if locale == "cn" then
        return { "微软语音", "MiniMax 语音", "OpenAI 语音", "设置" }
    end
    return { "Azure TTS", "MiniMax TTS", "OpenAI TTS", "Settings" }
end

local tabNames = getInitialTabTitles()
for _, name in ipairs(tabNames) do
    items.MyTabs:AddTab(name)
end
items.MyTabs.CurrentIndex = 0
items.MyStack.CurrentIndex = 0

App.checkForUpdates()

msgbox:Hide()
azureConfigWin:Hide()
openaiConfigWin:Hide()
minimaxConfigWin:Hide()
minimaxCloneWin:Hide()
loadingWin:Hide()

function msgbox.On.OkButton.Clicked(ev)
    msgbox:Hide()
end

function win.On.MyTabs.CurrentChanged(ev)
    local index = ev.Index or 0
    items.MyStack.CurrentIndex = index
    App.Controller.onProviderChanged(index)
end

function win.On.MainWin.Close(ev)
    local savedOk, savedErr = App.Settings.save()
    if not savedOk then
        logInfo(string.format("Settings save on close failed: %s", tostring(savedErr)))
    end
    Utils.removeDir(Paths.tempDir)
    local cloneDir = App.MiniMaxClone and App.MiniMaxClone.tempDir
    if cloneDir then
        Utils.removeDir(cloneDir)
    end
    win:Hide()
    minimaxCloneWin:Hide()
    minimaxConfigWin:Hide()
    openaiConfigWin:Hide()
    azureConfigWin:Hide()
    msgbox:Hide()
    dispatcher:ExitLoop()
end

function win.On.ShowAzure.Clicked(ev)
    azureConfigWin:Show()
end

function win.On.ShowMiniMax.Clicked(ev)
    minimaxConfigWin:Show()
end

function win.On.ShowOpenAI.Clicked(ev)
    openaiConfigWin:Show()
end

function win.On.ShowMiniMaxClone.Clicked(ev)
    App.MiniMaxClone.onShowWindow()
end

function win.On.minimaxVoiceEffectButton.Clicked(ev)
    onShowVoiceModifyWindow()
end

function azureConfigWin.On.UseAPICheckBox.Clicked(ev)
    if azureUseApiProgrammatic then
        return
    end
    local azureItems = App.UI.azureItems or {}
    local checked = readChecked(azureItems.UseAPICheckBox, App.State.azure.useApi ~= false)
    App.State.azure.useApi = checked
    App.UI.updateAzureApiInputs(checked)
end

function azureConfigWin.On.AzureConfirm.Clicked(ev)
    logInfo("Azure API configuration confirmed")
    azureConfigWin:Hide()
end

function azureConfigWin.On.AzureRegisterButton.Clicked(ev)
    openUrl(App.URLS.AzureRegister)
end

function azureConfigWin.On.AzureConfigWin.Close(ev)
    azureConfigWin:Hide()
end

function minimaxVoiceModifyWin.On.MiniMaxVoiceModifyConfirm.Clicked(ev)
    onVoiceModifyConfirm()
end

function minimaxVoiceModifyWin.On.MiniMaxVoiceModifyCancel.Clicked(ev)
    onVoiceModifyCancel()
end

function minimaxVoiceModifyWin.On.MiniMaxVoiceModifyWin.Close(ev)
    onVoiceModifyCancel()
end

local function handleTimelineSubtitleFetch(providerId)
    App.Controller.onFetchTimelineSubtitles(providerId)
end

function win.On.azureGetSubButton.Clicked(ev)
    handleTimelineSubtitleFetch("azure")
end

function win.On.minimaxGetSubButton.Clicked(ev)
    handleTimelineSubtitleFetch("minimax")
end

function win.On.OpenAIGetSubButton.Clicked(ev)
    handleTimelineSubtitleFetch("openai")
end

function win.On.azureFromTxtButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("azure", "text")
end

function win.On.azureFromSubButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("azure", "subtitle")
end

function win.On.azureResetButton.Clicked(ev)
    resetAzureTabToDefaults()
end

function win.On.minimaxFromTxtButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("minimax", "text")
end

function win.On.minimaxFromSubButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("minimax", "subtitle")
end

function win.On.minimaxResetButton.Clicked(ev)
    resetMiniMaxTabToDefaults()
end

function win.On.OpenAIFromTxtButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("openai", "text")
end

function win.On.OpenAIFromSubButton.Clicked(ev)
    App.Controller.onSynthesizeClicked("openai", "subtitle")
end

function win.On.OpenAIResetButton.Clicked(ev)
    resetOpenAITabToDefaults()
end

function win.On.OpenAIPreviewButton.Clicked(ev)
    if not openUrl(OPENAI_FM_URL) then
        notifyUser(localizedText("无法打开 OpenAI FM 链接。", "Unable to open the OpenAI FM page."))
    end
end

function win.On.OpenAIPresetCombo.CurrentIndexChanged(ev)
    local combo = App.UI.items and App.UI.items.OpenAIPresetCombo
    if not combo then
        return
    end
    local presets = App.Config.OpenAI.presets or {}
    local index = clampIndex(combo.CurrentIndex or 0, #presets)
    App.State.openai.presetIndex = index
    local entry = presets[index + 1]
    if entry then
        local description = entry.description or ""
        setTextSafe(App.UI.items.OpenAIInstructionText, description)
        App.State.openai.instruction = description
    end
end

function win.On.azureBreakButton.Clicked(ev)
    local items = App.UI.items or {}
    local breakControl = items.azureBreakSpinBox
    local value = breakControl and breakControl.Value or App.State.azure.breakMs or 0
    local breakMs = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
    local snippet = string.format('<break time="%dms" />', breakMs)
    insertPlainTextSafe(items.azureText, snippet)
end

function win.On.azurePlayButton.Clicked(ev)
    local params = App.Controller.collectAzureParams("preview")
    params.text = trim(params.text or "")
    if params.text == "" then
        notifyUser(localizedText("请输入要合成的文本。", "Please enter text to preview."))
        return
    end
    local extension = App.Azure.getOutputExtension(params.outputFormat) or ".wav"
    local previewPath, err = Utils.makeTempPath(extension)
    if not previewPath then
        notifyUser(localizedText("无法创建临时试听文件。", "Unable to create a temporary preview file.") .. "\n" .. tostring(err or ""))
        return
    end
    params.outputPath = previewPath
    params.outputDir = previewPath:match("^(.*)[/\\]") or Paths.tempDir
    params.source = "preview"
    local ok, result = App.Providers.Azure.speak(params)
    if not ok then
        notifyUser(localizedText("试听失败：", "Preview failed: ") .. tostring(result or "unknown"))
        os.remove(previewPath)
        return
    end
    local responsePath = previewPath
    if type(result) == "table" and result.path and result.path ~= "" then
        responsePath = result.path
    end
    if not Utils.fileExists(responsePath) then
        notifyUser(localizedText("试听音频生成失败。", "Preview audio was not created."))
        return
    end
    if openUrl(responsePath) then
        notifyUser(localizedText("已生成试听音频。", "Preview audio generated."))
    else
        notifyUser(localizedText("试听音频已生成，请手动打开：", "Preview audio generated. Please open it manually:") .. "\n" .. responsePath)
    end
end

function win.On.minimaxBreakButton.Clicked(ev)
    local items = App.UI.items or {}
    local breakControl = items.minimaxBreakSpinBox
    local value = breakControl and breakControl.Value or App.State.minimax.breakMs or 0
    local breakSeconds = math.max(0, tonumber(value) or 0) / 1000
    local snippet = string.format("<#%s#>", formatBreakSeconds(breakSeconds))
    insertPlainTextSafe(items.minimaxText, snippet)
end

function win.On.minimaxPreviewButton.Clicked(ev)
    local miniItems = App.UI.minimaxItems or {}
    local url = App.MiniMaxClone.previewUrls.cn
    if miniItems.intlCheckBox and miniItems.intlCheckBox.Checked then
        url = App.MiniMaxClone.previewUrls.intl
    end
    openUrl(url)
end

function win.On.Browse.Clicked(ev)
    local fusionInstance = fusion or (resolve and resolve:Fusion())
    if not (fusionInstance and fusionInstance.RequestDir) then
        notifyUser(localizedText("当前环境不支持选择路径。", "Directory picker is not available in this context."))
        return
    end
    local uiItems = App.UI.items or {}
    local startDir = trim((uiItems.Path and uiItems.Path.Text) or Config.Settings.outputPath or "")
    if startDir == "" and fusionInstance.MapPath then
        local ok, mapped = pcall(function()
            return fusionInstance:MapPath("UserData:/")
        end)
        if ok and mapped and mapped ~= "" then
            startDir = mapped
        end
    end
    local selected = fusionInstance:RequestDir((startDir ~= "" and startDir) or nil)
    if not selected or selected == "" then
        return
    end
    if not Utils.ensureDir(selected) then
        notifyUser(localizedText("无法访问所选目录。", "Selected directory is not accessible."))
        return
    end
    local _, project = App.ResolveCtx.get()
    local projectName = (project and project.GetName and project:GetName()) or "DaVinci"
    local safeName = Utils.sanitizeFileName(projectName, 48)
    if safeName == "" then
        safeName = "DaVinci"
    end
    local folderName = safeName
    if not safeName:lower():match("_tts$") then
        folderName = safeName .. "_TTS"
    end
    local targetDir = Utils.joinPath(selected, folderName)
    if not Utils.ensureDir(targetDir) then
        notifyUser(localizedText("无法创建保存路径。", "Unable to create the save directory."))
        return
    end
    if uiItems.Path then
        setTextSafe(uiItems.Path, targetDir)
    end
    Config.Settings.outputPath = targetDir
    if Config.Settings.saved then
        Config.Settings.saved.Path = targetDir
    end
    if App.Config and App.Config.Settings and App.Config.Settings.defaults then
        App.Config.Settings.defaults.outputPath = targetDir
    end
    notifyUser(localizedText("保存路径已更新。", "Save path updated."))
    logInfo("Output path updated to " .. targetDir)
end

function win.On.openGuideButton.Clicked(ev)
    local guidePath = Utils.joinPath(Paths.scriptDir, "Installation-Usage-Guide.html")
    if not Utils.fileExists(guidePath) then
        notifyUser(localizedText("找不到教程文件：", "Guide file not found:") .. "\n" .. guidePath)
        return
    end
    if not openUrl(guidePath) then
        notifyUser(localizedText("无法打开教程文件。", "Unable to open the guide file."))
    end
end

function win.On.CopyrightButton.Clicked(ev)
    local uiItems = App.UI.items or {}
    local useEnglish = false
    if uiItems.LangEnCheckBox and uiItems.LangEnCheckBox.Checked then
        useEnglish = true
    elseif uiItems.LangCnCheckBox and uiItems.LangCnCheckBox.Checked then
        useEnglish = false
    else
        useEnglish = (App.State.locale ~= "cn")
    end
    local url = useEnglish and SCRIPT_KOFI_URL or SCRIPT_TAOBAO_URL
    if not openUrl(url) then
        notifyUser(localizedText("无法打开链接：", "Unable to open link:") .. "\n" .. url)
    end
end

function openaiConfigWin.On.OpenAIConfirm.Clicked(ev)
    logInfo("OpenAI API configuration confirmed")
    openaiConfigWin:Hide()
end

function openaiConfigWin.On.OpenAIConfigWin.Close(ev)
    openaiConfigWin:Hide()
end

function openaiConfigWin.On.OpenAIRegisterButton.Clicked(ev)
    openUrl(App.URLS.OpenAIRegister)
end

function minimaxConfigWin.On.MiniMaxConfirm.Clicked(ev)
    logInfo("MiniMax API configuration confirmed")
    minimaxConfigWin:Hide()
end

function minimaxConfigWin.On.minimaxRegisterButton.Clicked(ev)
    local miniItems = App.UI.minimaxItems or {}
    local url = App.URLS.MiniMaxRegisterCn
    if miniItems.intlCheckBox and miniItems.intlCheckBox.Checked then
        url = App.URLS.MiniMaxRegisterIntl
    end
    openUrl(url)
end

function minimaxConfigWin.On.MiniMaxConfigWin.Close(ev)
    minimaxConfigWin:Hide()
end

function minimaxCloneWin.On.MiniMaxCloneConfirm.Clicked(ev)
    App.MiniMaxClone.handleConfirm()
end

function minimaxCloneWin.On.MiniMaxCloneWin.Close(ev)
    App.MiniMaxClone.onCloseWindow()
end

function minimaxCloneWin.On.MiniMaxCloneCancel.Clicked(ev)
    App.MiniMaxClone.onCloseWindow()
end

win:Show()
dispatcher:RunLoop()
win:Hide()
