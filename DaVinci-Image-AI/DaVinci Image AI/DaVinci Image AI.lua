--[[
    Script: DaVinci Image Edit
    Version: 2.0.0
    Author: HEIBA
    Description: Image editing utility
]]

math.randomseed(os.time())

-- 唯一的全局命名空间
local App = {}

---
--- 1. 配置模块 (App.Config)
---
do
    local Config = {}

    Config.SCRIPT_NAME    = "DaVinci Image AI"
    Config.SCRIPT_VERSION = "1.0.1"
    Config.SCRIPT_AUTHOR  = "HEIBA"
    print(string.format("%s | %s | %s", Config.SCRIPT_NAME, Config.SCRIPT_VERSION, Config.SCRIPT_AUTHOR))

    -- 窗口几何
    Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT = 1920, 1080
    Config.WINDOW_WIDTH, Config.WINDOW_HEIGHT = 600, 625
    Config.X_CENTER = math.floor((Config.SCREEN_WIDTH - Config.WINDOW_WIDTH) / 2)
    Config.Y_CENTER = math.floor((Config.SCREEN_HEIGHT - Config.WINDOW_HEIGHT) / 2)
    Config.LOADING_WINDOW_WIDTH, Config.LOADING_WINDOW_HEIGHT = 260, 140
    Config.LOADING_X_CENTER = math.floor((Config.SCREEN_WIDTH - Config.LOADING_WINDOW_WIDTH) / 2)
    Config.LOADING_Y_CENTER = math.floor((Config.SCREEN_HEIGHT - Config.LOADING_WINDOW_HEIGHT) / 2)

    -- 更新检测
    Config.SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
    Config.SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"
    Config.SUPABASE_TIMEOUT = 5

    Config.GOOGLE_DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"
    Config.GOOGLE_DEFAULT_MODEL = "gemini-2.5-flash-image"
    Config.GOOGLE_PRO_DEFAULT_MODEL = "gemini-3-pro-image-preview"
    Config.GOOGLE_ENDPOINT = "/v1beta/models"

    Config.SEED_DEFAULT_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/images/generations"
    Config.SEED_DEFAULT_MODEL = "doubao-seededit-3-0-i2i-250628"

    -- 默认配置
    Config.DEFAULT_CONFIG = {
        savePath = "",
        currentLang = "en",
        provider_choice = "google",
        generator_provider_choice = "google",
        google = {
            base_url = "",
            api_key = "",
            model = Config.GOOGLE_DEFAULT_MODEL,
            aspect_ratio = "1:1",
            resolution = "1K"
        },
        -- 文生图（生成页）专用配置，避免与编辑页互相覆盖
        google_gen = {
            base_url = "",
            api_key = "",
            model = Config.GOOGLE_DEFAULT_MODEL,
            aspect_ratio = "1:1",
            resolution = "1K"
        },
        seeddream = {
            base_url = "",
            api_key = "",
            model = Config.SEED_DEFAULT_MODEL,
            aspect_ratio = "1:1"
        }
    }

    -- 支持的图片格式
    Config.SUPPORTED_FORMATS = {"PNG", "JPEG", "WEBP"}

    -- 日志配置
    Config.LOG_HTTP_RESPONSE = true   -- 避免打印巨大 base64 响应导致界面卡顿

    App.Config = Config
end

---
--- 2. 核心 API 模块 (App.Core)
---
do
    local Core = {}
    Core.resolve = resolve or Resolve()
    Core.fusion = Core.resolve and Core.resolve:Fusion()
    Core.ui = Core.fusion and Core.fusion.UIManager
    Core.dispatcher = Core.ui and bmd.UIDispatcher(Core.ui)

    if not Core.dispatcher then
        print(string.format("%s: 无法初始化 Fusion UI. (Resolve/Fusion API 不可用)", App.Config.SCRIPT_NAME or "Script"))
        return
    end

    App.Core = Core
end

---
--- 3. 工具模块 (App.Utils)
---
do
    local Utils = {}
    local Config = App.Config

    -- 加载json模块
    local json = require("dkjson")

    Utils.SEP = package.config:sub(1,1)
    Utils.IS_WINDOWS = (Utils.SEP == "\\")

    -- OS Shell 命令
    local runHiddenWindowsCommand
    local runShellCommand
    do
        if Utils.IS_WINDOWS then
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
                    if required == 0 then return nil end
                    local buffer = ffi.new("wchar_t[?]", required)
                    if kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buffer, required) == 0 then return nil end
                    return buffer
                end

                runHiddenWindowsCommand = function(command)
                    local comspec = os.getenv("COMSPEC") or "C:\\Windows\\System32\\cmd.exe"
                    local fullCommand = string.format('"%s" /c %s', comspec, command)
                    local cmdBuffer = utf8ToWideBuffer(fullCommand)
                    if not cmdBuffer then return false, "command_encoding_failed" end

                    local startupInfo = ffi.new("STARTUPINFOW")
                    startupInfo.cb = ffi.sizeof(startupInfo)
                    startupInfo.dwFlags = STARTF_USESHOWWINDOW
                    startupInfo.wShowWindow = 0

                    local processInfo = ffi.new("PROCESS_INFORMATION")
                    local created = kernel32.CreateProcessW(
                        nil, cmdBuffer, nil, nil, false,
                        CREATE_NO_WINDOW, nil, nil,
                        startupInfo, processInfo
                    )

                    if created == 0 then return false, kernel32.GetLastError() end

                    kernel32.WaitForSingleObject(processInfo.hProcess, INFINITE)
                    local exitCodeArr = ffi.new("DWORD[1]", 0)
                    kernel32.GetExitCodeProcess(processInfo.hProcess, exitCodeArr)
                    kernel32.CloseHandle(processInfo.hProcess)
                    kernel32.CloseHandle(processInfo.hThread)

                    return exitCodeArr[0] == 0, exitCodeArr[0]
                end
            end
        end

        runShellCommand = function(command)
            if Utils.IS_WINDOWS and type(runHiddenWindowsCommand) == "function" then
                local ok, code = runHiddenWindowsCommand(command)
                if not ok then
                    print(string.format("Command failed (exit=%s)", tostring(code)))
                end
                -- 保持第1返回值是布尔；新增第2返回值为退出码
                return ok == true, tonumber(code) or 0
            end

            -- *nix：os.execute 在不同 Lua 版本返回形式不同，这里做了全覆盖
            local res, how, code = os.execute(command)
            if type(res) == "number" then
                return res == 0, res
            end
            if res == true then
                if how == "exit" then return (code or 0) == 0, (code or 0) end
                return true, 0
            end
            return false, (type(code) == "number" and code or 1)
        end

    end
    Utils.runShellCommand = runShellCommand

    -- 字符串工具
    function Utils.trim(s)
        if type(s) ~= "string" then return "" end
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function Utils.urlEncode(str)
        if not str then return "" end
        return tostring(str):gsub("([^%w%-_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end

    -- 路径工具
    function Utils.scriptDir()
        local source = debug.getinfo(1, "S").source
        if source:sub(1, 1) == "@" then
            source = source:sub(2)
        end
        local pattern = "(.*" .. Utils.SEP .. ")"
        if Utils.IS_WINDOWS then
            pattern = "(.*[\\/])"
        end
        return source:match(pattern) or ""
    end

    function Utils.joinPath(a, b)
        if a == "" then return b end
        if a:sub(-1) == Utils.SEP then return a .. b end
        return a .. Utils.SEP .. b
    end

    function Utils.getConfigDir()
        return Utils.joinPath(Utils.scriptDir(), "config")
    end

    function Utils.getTempDir()
        return Utils.joinPath(Utils.scriptDir(), "temp")
    end

    function Utils.fileExists(path)
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end

    function Utils.getFileSize(path)
        local f = io.open(path, "rb")
        if not f then
            return 0
        end
        local size = f:seek("end")
        f:close()
        return size or 0
    end

    function Utils.ensureDir(path)
        if path == "" then return true end
        if bmd and bmd.fileexists and bmd.fileexists(path) then return true end
        if Utils.IS_WINDOWS then
            if not Utils.runShellCommand(string.format('if not exist "%s" mkdir "%s"', path, path)) then
                print("Failed to create directory: " .. path)
                return false
            end
        else
            local escaped = path:gsub("'", "'\\''")
            if not Utils.runShellCommand("mkdir -p '" .. escaped .. "'") then
                print("Failed to create directory: " .. path)
                return false
            end
        end
        return true
    end

    -- 调试文件清理（允许传入 table 或字符串）
    function Utils.cleanupDebugPaths(paths)
        if not paths then return end
        if type(paths) == "string" then
            if paths ~= "" and Utils.fileExists(paths) then
                os.remove(paths)
            end
            return
        end
        if type(paths) ~= "table" then return end
        for _, p in pairs(paths) do
            if type(p) == "string" then
                if p ~= "" and Utils.fileExists(p) then
                    os.remove(p)
                end
            elseif type(p) == "table" then
                Utils.cleanupDebugPaths(p)
            end
        end
    end

    function Utils.makeTempPath(ext)
        local dir = Utils.getTempDir()
        Utils.ensureDir(dir)
        local ts  = tostring(os.time())
        local rnd = string.format("%06d", math.random(0, 999999))
        local base = string.format("tmp_%s_%s", ts, rnd)
        if ext and ext ~= "" then
            if not ext:match("^%.") then ext = "." .. ext end
        else
            ext = ""
        end
        local path = Utils.joinPath(dir, base .. ext)
        local i = 0
        while Utils.fileExists(path) do
            i = i + 1
            path = Utils.joinPath(dir, base .. "_" .. i .. ext)
            if i > 1000 then return nil, "temp_name_exhausted" end
        end
        return path
    end

    function Utils.sanitizeFilename(name)
        name = tostring(name or "image")
        name = name:gsub("[%c%z]", ""):gsub("[/\\:%*%?%\"]", "_"):gsub("[<>|]", "_")
        name = name:gsub("%s+", "_"):gsub("^_+", ""):gsub("_+$", "")
        if name == "" then name = "image" end
        return name
    end

    function Utils.maskToken(token)
        token = tostring(token or "")
        if token == "" then return "未设置" end
        local len = #token
        if len <= 4 then
            return string.rep("*", len)
        end
        local masked = string.rep("*", len - 4) .. token:sub(-4)
        return masked
    end

    function Utils.maskHeaderValue(name, value)
        local lower = tostring(name or ""):lower()
        local str = tostring(value or "")
        if lower == "authorization" then
            local prefix, token = str:match("^(%S+)%s+(.+)$")
            if prefix and token then
                return string.format("%s %s", prefix, Utils.maskToken(token))
            end
            return Utils.maskToken(str)
        end
        return str
    end

    function Utils.truncate(str, limit)
        str = tostring(str or "")
        limit = limit or 200
        if #str <= limit then
            return str
        end
        return str:sub(1, limit) .. "...(truncated)"
    end

    function Utils.debugSection(title)
        print(string.format("\n========== [Image Edit] %s ==========", title or "DEBUG"))
    end

    function Utils.debugSectionEnd()
        print("================================================\n")
    end

    function Utils.debugKV(key, value)
        print(string.format("%-18s: %s", tostring(key or "Field"), tostring(value or "")))
    end

    function Utils.openExternalUrl(url)
        if not url or url == "" then return end
        if bmd and bmd.openurl then
            pcall(bmd.openurl, url)
            return
        end
        local escaped = url:gsub("'", "'\\''"):gsub('"', '\\"')
        if Utils.IS_WINDOWS then
            Utils.runShellCommand(string.format('start "" "%s"', url))
        elseif pcall(os.execute, "open '" .. escaped .. "'") then
            -- macOS
        else
            -- Linux
            Utils.runShellCommand("xdg-open '" .. escaped .. "'")
        end
    end

    function Utils.normalizeBaseUrl(url)
        if type(url) ~= "string" then return "" end
        url = Utils.trim(url)
        if url == "" then return "" end
        return (url:gsub("/+$", ""))
    end

    function Utils.buildGoogleEndpoint(baseUrl, modelName)
        local normalized = Utils.normalizeBaseUrl(baseUrl)
        if normalized == "" then
            return ""
        end

        normalized = normalized:gsub("/v1/chat/completions$", "")
        normalized = normalized:gsub("/chat/completions$", "")
        normalized = normalized:gsub("/v1$", "")

        local model = Utils.trim(modelName or "")
        if model == "" then
            model = App.Config.GOOGLE_DEFAULT_MODEL
        end

        if normalized:find(":generateContent", 1, true) then
            return normalized
        end

        if normalized:find("/v1beta/models/", 1, true) then
            if normalized:sub(-#model) == model then
                return normalized .. ":generateContent"
            end
            return normalized .. ":generateContent"
        end

        local baseWithModels = normalized
        if normalized:find("/v1beta$", 1, false) then
            baseWithModels = normalized .. "/models"
        elseif not normalized:find("/v1beta/models", 1, true) then
            baseWithModels = normalized .. App.Config.GOOGLE_ENDPOINT
        end

        return string.format("%s/%s:generateContent", baseWithModels, model)
    end

    -- 配置管理
    local function deep_copy(tbl)
        if type(tbl) ~= "table" then
            return tbl
        end
        local copy = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                copy[k] = deep_copy(v)
            else
                copy[k] = v
            end
        end
        return copy
    end

    local function merge_provider_defaults(config)
        local defaults = App.Config.DEFAULT_CONFIG
        local function ensure_subtable(key, defaultTbl)
            config[key] = config[key] or {}
            for dk, dv in pairs(defaultTbl) do
                if config[key][dk] == nil then
                    config[key][dk] = dv
                end
            end
        end

        ensure_subtable("google", defaults.google)
        ensure_subtable("google_gen", defaults.google_gen or defaults.google)
        ensure_subtable("seeddream", defaults.seeddream)

        if type(config.google_pro) == "table" then
            for dk, dv in pairs(config.google_pro) do
                if dk ~= "model" and (config.google[dk] == nil or config.google[dk] == "" or config.google[dk] == defaults.google[dk]) then
                    config.google[dk] = dv
                end
            end
            config.google_pro = nil
        end

        if config.openai_base_url and (config.google.base_url == "" or config.google.base_url == defaults.google.base_url) then
            config.google.base_url = config.openai_base_url
        end
        if config.openai_api_key and (config.google.api_key == "" or config.google.api_key == nil) then
            config.google.api_key = config.openai_api_key
        end

        -- 将已有 google 配置同步到 google_gen（仅填空位，避免覆盖用户已分开的配置）
        if config.google and config.google_gen then
            local function copy_if_empty(key)
                local defv = (defaults.google_gen or defaults.google or {})[key]
                local gv = config.google_gen[key]
                local src = config.google[key]
                if (gv == nil or gv == "" or gv == defv) and src ~= nil and src ~= "" then
                    config.google_gen[key] = src
                end
            end
            copy_if_empty("base_url")
            copy_if_empty("api_key")
            copy_if_empty("model")
            copy_if_empty("aspect_ratio")
            copy_if_empty("resolution")
        end
        if config.openai_model and config.google.model == defaults.google.model then
            config.google.model = config.openai_model
        end

        config.openai_base_url = nil
        config.openai_api_key = nil
        config.openai_model = nil
    end

    function Utils.loadConfig()
        local configDir = Utils.getConfigDir()
        Utils.ensureDir(configDir)
        local configPath = Utils.joinPath(configDir, "settings.json")

        if not Utils.fileExists(configPath) then
            local fresh = deep_copy(App.Config.DEFAULT_CONFIG)
            merge_provider_defaults(fresh)
            return fresh
        end

        local file = io.open(configPath, "r")
        if not file then
            local fresh = deep_copy(App.Config.DEFAULT_CONFIG)
            merge_provider_defaults(fresh)
            return fresh
        end

        local content = file:read("*a")
        file:close()

        local ok, config = pcall(json.decode, content)
        if ok and type(config) == "table" then
            local defaults = App.Config.DEFAULT_CONFIG
            for k, v in pairs(defaults) do
                if config[k] == nil then
                    if type(v) == "table" then
                        config[k] = deep_copy(v)
                    else
                        config[k] = v
                    end
                end
            end
            if not config.provider_choice or config.provider_choice == "" then
                config.provider_choice = defaults.provider_choice
            end
            merge_provider_defaults(config)
            return config
        end

        local fallback = deep_copy(App.Config.DEFAULT_CONFIG)
        merge_provider_defaults(fallback)
        return fallback
    end

    function Utils.saveConfig(config)
        local configDir = Utils.getConfigDir()
        Utils.ensureDir(configDir)
        local configPath = Utils.joinPath(configDir, "settings.json")

        local prepared = deep_copy(config)
        prepared.google_pro = nil

        local ok, jsonStr = pcall(json.encode, prepared)
        if not ok then
            print("Failed to encode config: " .. tostring(jsonStr))
            return false
        end

        local file = io.open(configPath, "w")
        if not file then
            return false
        end

        file:write(jsonStr)
        file:close()
        return true
    end

    local function strip_data_url(s)
        return (tostring(s or ""):gsub("^data:[^;]+;base64,", ""))
    end

    function Utils.stripDataUrlPayload(dataUrl)
        return strip_data_url(dataUrl or "")
    end

    function Utils.getMimeFromDataUrl(dataUrl, fallback)
        local mime = tostring(dataUrl or ""):match("^data:([^;]+);base64,")
        if mime and mime ~= "" then
            return mime
        end
        return fallback or "image/png"
    end

    local function estimate_decoded_size(payload)
        local padding = 0
        if payload:sub(-2) == "==" then
            padding = 2
        elseif payload:sub(-1) == "=" then
            padding = 1
        end
        local blocks = math.floor(#payload / 4)
        return math.max(0, blocks * 3 - padding)
    end

    local function system_base64_encode_string(data)
        if type(data) ~= "string" or data == "" then
            return ""
        end
        local tempIn, errIn = Utils.makeTempPath("bin")
        if not tempIn then return nil, errIn end
        local bin = io.open(tempIn, "wb")
        if not bin then
            return nil, "temp_input_failed"
        end
        bin:write(data)
        bin:close()

        local tempOut, errOut = Utils.makeTempPath("b64")
        if not tempOut then
            os.remove(tempIn)
            return nil, errOut
        end

        local commands = {}
        if Utils.IS_WINDOWS then
            local function ps_quote(path)
                return "'" .. tostring(path or ""):gsub("'", "''") .. "'"
            end
            table.insert(commands, string.format('powershell -NoLogo -NoProfile -Command "Try { $bytes=[IO.File]::ReadAllBytes(%s); $b64=[Convert]::ToBase64String($bytes); [IO.File]::WriteAllText(%s,$b64); exit 0 } Catch { exit 1 }"', ps_quote(tempIn), ps_quote(tempOut)))
        else
            table.insert(commands, string.format('openssl base64 -A -in %q -out %q 2>/dev/null', tempIn, tempOut))
            table.insert(commands, string.format('( base64 %q | tr -d "\\n" ) > %q 2>/dev/null', tempIn, tempOut))
        end

        local result
        for _, cmd in ipairs(commands) do
            if Utils.fileExists(tempOut) then
                os.remove(tempOut)
            end
            if Utils.runShellCommand(cmd) and Utils.fileExists(tempOut) then
                local f = io.open(tempOut, "rb")
                if f then
                    local content = f:read("*a") or ""
                    f:close()
                    content = content:gsub("%s+", "")
                    if content ~= "" then
                        result = content
                        break
                    end
                end
            end
        end

        os.remove(tempIn)
        os.remove(tempOut)
        if result then
            return result
        end
        return nil, "system_encode_failed"
    end

    function Utils.base64Encode(bytes)
        bytes = bytes or ""
        if bytes == "" then
            return ""
        end
        local encoded = select(1, system_base64_encode_string(bytes))
        if encoded and encoded ~= "" then
            return encoded
        end
        return ""
    end

    function Utils.findDataUrlInText(text)
        if type(text) ~= "string" then return nil end
        local startIdx = text:find("data:image/")
        if not startIdx then return nil end
        local snippet = text:sub(startIdx)
        local pattern = "(data:image/[%w%-%+]+;base64,[%w%+/%=%-_,]+)"
        local dataUrl = snippet:match(pattern)
        if dataUrl then
            return dataUrl
        end
        local loose = snippet:match("(data:image/[%w%-%+]+;base64,[%w%+/%=%-_,\n\r]+)")
        if loose then
            return (loose:gsub("%s+", ""))
        end
        return nil
    end

    function Utils.findHttpImageInText(text)
        if type(text) ~= "string" then return nil end
        local function sanitize(u)
            if not u then return nil end
            return (u:gsub("['\"%s>%]%)}]+$", ""))
        end
        -- Prefer markdown image links if present to avoid trailing ")"
        local mdUrl = text:match("!%[[^%]]*%]%((https?://[^%s)]+)%)")
        if mdUrl then
            local clean = sanitize(mdUrl)
            if clean:match("^https?://") then
                return clean
            end
        end
        local url = text:match("(https?://%S+)")
        url = sanitize(url)
        if url and url:match("^https?://") then
            return url
        end
        return nil
    end

    local function copy_file(src, dest)
        local infile = io.open(src, "rb")
        if not infile then
            return false, "read_failed"
        end
        local outfile, err = io.open(dest, "wb")
        if not outfile then
            infile:close()
            return false, "write_failed:" .. tostring(err)
        end
        while true do
            local chunk = infile:read(1024 * 128)
            if not chunk then break end
            outfile:write(chunk)
        end
        infile:close()
        outfile:close()
        return true
    end

    function Utils.copyToTemp(srcPath)
        local ext = (tostring(srcPath):lower():match("%.([^%.]+)$") or "png")
        local tempPath, err = Utils.makeTempPath(ext)
        if not tempPath then
            return nil, err
        end
        local ok, copyErr = copy_file(srcPath, tempPath)
        if not ok then
            os.remove(tempPath)
            return nil, copyErr
        end
        return tempPath
    end

    function Utils.processImageWithSips(srcPath)
        if Utils.IS_WINDOWS then
            return srcPath
        end
        local destPath, err = Utils.makeTempPath("jpg")
        if not destPath then
            return nil, err
        end
        local cmd = string.format('sips -s format jpeg -s formatOptions 70 -Z 1920 %q --out %q', srcPath, destPath)
        if Utils.runShellCommand(cmd) and Utils.fileExists(destPath) and Utils.getFileSize(destPath) > 0 then
            return destPath
        end
        os.remove(destPath)
        return nil, "sips_failed"
    end

    function Utils.preparePreviewImage(srcPath, opts)
        opts = opts or {}
        local working = srcPath
        if opts.copy_to_temp then
            local copyPath, err = Utils.copyToTemp(srcPath)
            if not copyPath then
                return nil, err
            end
            working = copyPath
        end
        if Utils.IS_WINDOWS then
            return working
        end
        local processed, err = Utils.processImageWithSips(working)
        if processed then
            if opts.cleanup_source and processed ~= working then
                if working and working:find(Utils.getTempDir(), 1, true) then
                    os.remove(working)
                end
            end
            return processed
        end
        return working, err
    end

    function Utils.httpGet(url, headers, timeout)
        if not url or url == "" then
            return false, "missing_url"
        end
        local headerParts = {}
        local hasAccept = false
        local hasExpect = false
        if headers then
            for k, v in pairs(headers) do
                local name = tostring(k or "")
                local cleanValue = tostring(v or ""):gsub('"', '\\"')
                table.insert(headerParts, string.format('-H "%s: %s"', name, cleanValue))
                local lower = name:lower()
                if lower == "accept" then hasAccept = true end
                if lower == "expect" then hasExpect = true end
            end
        end
        if not hasAccept then
            table.insert(headerParts, '-H "Accept: application/json"')
        end
        --table.insert(headerParts, '-H "Connection: close"')

        local maxTime = tonumber(timeout) or 120
        Utils.debugSection("HTTP GET START")
        Utils.debugKV("URL", url)
        Utils.debugKV("Timeout", string.format("%ss", maxTime))
        if headers then
            print("Headers:")
            for k, v in pairs(headers) do
                print(string.format("  - %s: %s", tostring(k), Utils.maskHeaderValue(k, v)))
            end
        end
        Utils.debugSectionEnd()

        local bodyPath, errOut = Utils.makeTempPath("out")
        if not bodyPath then
            return false, "tmp_output_failed:" .. tostring(errOut)
        end
        local statusPath, errStatus = Utils.makeTempPath("status")
        if not statusPath then
            os.remove(bodyPath)
            return false, "tmp_status_failed:" .. tostring(errStatus)
        end
        local errPath, errErr = Utils.makeTempPath("err")
        if not errPath then
            os.remove(bodyPath)
            os.remove(statusPath)
            return false, "tmp_err_failed:" .. tostring(errErr)
        end

        local debugPaths = {out = bodyPath, status = statusPath, err = errPath}

        local sep = Utils.SEP
        local headerStr = table.concat(headerParts, " ")
        local commonFlags = '--http1.1 --no-keepalive -sS -L'
        local curlCommand
        if sep == "\\" then
            curlCommand = string.format(
                'curl %s -m %d %s -o "%s" -w "%%%%{http_code}" "%s"',
                commonFlags,
                maxTime,
                headerStr,
                bodyPath,
                url
            )
        else
            curlCommand = string.format(
                'curl %s -m %d %s -o %q -w "%%%%{http_code}" %q',
                commonFlags,
                maxTime,
                headerStr,
                bodyPath,
                url
            )
        end

        local redirected
        if sep == "\\" then
            redirected = string.format('%s > "%s" 2>"%s"', curlCommand, statusPath, errPath)
        else
            redirected = string.format('( %s ) > %q 2>%q', curlCommand, statusPath, errPath)
        end

        local ok, exitCode = Utils.runShellCommand(redirected)

        local statusCode
        local sf = io.open(statusPath, "rb")
        if sf then
            local statusData = sf:read("*a") or ""
            sf:close()
            statusCode = tonumber((statusData or ""):match("(%d%d%d)"))
        end

        local of = io.open(bodyPath, "rb")
        local body = of and of:read("*a") or ""
        if of then of:close() end

        local errText = ""
        local ef = io.open(errPath, "rb")
        if ef then errText = ef:read("*a") or ""; ef:close() end

        if not ok then
            if Config and Config.LOG_HTTP_RESPONSE then
                print(string.format("[cURL] exit=%s", tostring(exitCode)))
                if errText ~= "" then
                    print("[cURL stderr]")
                    print(Utils.truncate(errText, 800))
                end
            end
            return false, "curl_failed", statusCode, debugPaths
        end
        if not body or body == "" then
            return false, "empty_response", statusCode, debugPaths
        end
        if statusCode and (statusCode < 200 or statusCode >= 300) then
            return false, body, statusCode, debugPaths
        end
        if Config and Config.LOG_HTTP_RESPONSE then
            Utils.debugSection("HTTP RESPONSE START")
            Utils.debugKV("Response Bytes", tostring(#body))
            Utils.debugKV("Preview", Utils.truncate(body, 200))
            Utils.debugSectionEnd()
        end
        return true, body, statusCode or 200, debugPaths
    end

    function Utils.httpPostJson(url, payload, headers, timeout)
        if not url or url == "" then
            return false, "missing_url"
        end
        local bodyStr
        if type(payload) == "table" then
            local ok, encoded = pcall(json.encode, payload)
            if not ok then
                return false, "json_encode_failed"
            end
            bodyStr = encoded
        elseif type(payload) == "string" then
            bodyStr = payload
        else
            bodyStr = tostring(payload or "")
        end

        local headerParts = {}
        local hasContentType = false
        local hasAccept = false
        
        -- User-Agent 伪装
        local userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        if headers then
            for k, v in pairs(headers) do
                local name = tostring(k or "")
                local cleanValue = tostring(v or ""):gsub('"', '\\"')
                table.insert(headerParts, string.format('-H "%s: %s"', name, cleanValue))
                local lower = name:lower()
                if lower == "content-type" then hasContentType = true end
                if lower == "accept" then hasAccept = true end
            end
        end
        if not hasContentType then
            table.insert(headerParts, '-H "Content-Type: application/json"')
        end
        if not hasAccept then
            table.insert(headerParts, '-H "Accept: application/json"')
        end
        -- 移除 Expect 头，防止大 payload 发送时卡顿
        table.insert(headerParts, '-H "Expect:"')
   
        -- Mac/Linux 默认不再强制 close，减少长链路被 RST 的概率
   
        local maxTime = tonumber(timeout) or 120
        Utils.debugSection("HTTP REQUEST START")
        Utils.debugKV("URL", url)
        
        local tempPayload, err1 = Utils.makeTempPath("json")
        if not tempPayload then return false, "tmp_payload_failed" end
        
        local pf = io.open(tempPayload, "wb")
        if not pf then return false, "payload_write_failed" end
        pf:write(bodyStr)
        pf:close()

        local sep = Utils.SEP
        local headerStr = table.concat(headerParts, " ")
        local bodyPath, err2 = Utils.makeTempPath("out")
        local statusPath, err3 = Utils.makeTempPath("status")
        local errPath, err4 = Utils.makeTempPath("err")
        local debugPaths = {
            payload = tempPayload,
            out = bodyPath,
            status = statusPath,
            err = errPath
        }

        -- === Windows 配置 (保持稳定版) ===
        -- Windows 需要 -N 来防止假死，且 cmd 处理重定向较好
        local winFlags = string.format('--http1.1 --no-keepalive -sS -L -N -4 -A "%s"', userAgent)
        
        -- === Mac/Linux 最终修正版 ===
        -- 1. --http1.1 : 强制 HTTP/1.1 保证大文件流式传输稳定
        -- 2. --keepalive-time 5 : 必须的高频心跳，防止路由器切断
        -- 3. -N : 禁用缓冲，防止数据积压
        -- 4. -H "Connection: close" : (通过 headerStr 添加) 告诉服务器发完就挂断，不要 reset
        local macFlags = string.format(
        '--http1.1 -sS -L -g ' ..
        '--connect-timeout 20 ' ..
        '--keepalive-time 5 ' ..    -- 保持心跳
        --'-N ' ..                    -- 保持无缓冲
        '-4 ' ..
        '--no-sessionid ' ..
        '--compressed ' ..
        '-A "%s"', userAgent
        )


        local curlCommand
        local redirected

        if sep == "\\" then
            -- [Windows 逻辑]
            curlCommand = string.format(
                'curl %s -m %d -X POST %s --data-binary "@%s" -o "%s" -w "%%%%{http_code}" "%s"',
                winFlags, maxTime, headerStr, tempPayload, bodyPath, url
            )
            redirected = string.format('%s > "%s" 2>"%s"', curlCommand, statusPath, errPath)
        else
            -- [Mac/Linux 逻辑 - 关键修改]
            -- 1. URL 用单引号
            -- 2. 错误日志直接由 curl 写入 (--stderr %q)
            -- 3. 只有状态码 (-w) 输出到 stdout 并重定向到 statusPath
            local safeUrl = url:gsub("'", "'\\''") 
            curlCommand = string.format(
                'curl %s -m %d -X POST %s --data-binary @%q -o %q --stderr %q -w "%%{http_code} start=%%{time_starttransfer} total=%%{time_total} size=%%{size_download}\n" \'%s\'',
                macFlags,
                maxTime,
                headerStr,
                tempPayload,
                bodyPath,
                errPath, -- curl 直接写错误日志
                safeUrl
            )
            -- 这里的重定向只负责极小的状态码，不会阻塞
            redirected = string.format('%s > %q', curlCommand, statusPath)
        end

        -- 执行命令
        local ok, exitCode = Utils.runShellCommand(redirected)

        -- 读取状态码
        local statusCode
        local sf = io.open(statusPath, "rb")
        if sf then
            local statusData = sf:read("*a") or ""
            sf:close()
            if Config and Config.LOG_HTTP_RESPONSE then
                print("[cURL stats] " .. (statusData:gsub("%s+$","")))
            end
            statusCode = tonumber((statusData or ""):match("(%d%d%d)"))
        end

        -- 读取结果
        local of = io.open(bodyPath, "rb")
        local body = of and of:read("*a") or ""
        if of then of:close() end

        -- 读取错误日志
        local errText = ""
        local ef = io.open(errPath, "rb")
        if ef then errText = ef:read("*a") or ""; ef:close() end

        if not ok then
            print(string.format("[cURL] exit=%s", tostring(exitCode)))
            if errText ~= "" then print("[cURL stderr] " .. Utils.truncate(errText, 800)) end
            
            -- 抢救逻辑：如果 curl 报错但 body 有数据
            if body and #body > 100 then
                 print("[WARNING] curl reported error but data received. Continuing.")
                 return true, body, statusCode or 200, debugPaths
            end
            return false, "curl_failed", statusCode, debugPaths
        end

        if not body or body == "" then
            -- 状态码 200 但无内容，说明写入磁盘失败
            if statusCode == 200 then
                 -- 尝试读取 stderr 看看有没有 Write error
                 if errText:find("Failed to write") or errText:find("write error") then
                     return false, "disk_write_failed", statusCode, debugPaths
                 end
                 return false, "empty_response_write_failed", statusCode, debugPaths
            end
            return false, "empty_response", statusCode, debugPaths
        end
        return true, body, statusCode or 200, debugPaths
    end

    local function system_decode_base64(payload, dest_path, expected_bytes)
        if type(payload) ~= "string" or payload == "" then
            return false
        end
        local tempB64, err = Utils.makeTempPath("b64")
        if not tempB64 then
            return false, err
        end
        local writer, werr = io.open(tempB64, "wb")
        if not writer then
            return false, "temp_write_failed:" .. tostring(werr)
        end
        if Utils.IS_WINDOWS then
            local idx, len = 1, #payload
            while idx <= len do
                local chunk = payload:sub(idx, idx + 63)
                writer:write(chunk, "\n")
                idx = idx + 64
            end
        else
            writer:write(payload)
            if payload:sub(-1) ~= "\n" then
                writer:write("\n")
            end
        end
        writer:close()

        local commands = {}
        if Utils.IS_WINDOWS then
            local function win_quote(path)
                return '"' .. tostring(path or ""):gsub('"', '""') .. '"'
            end
            local function ps_quote(path)
                return "'" .. tostring(path or ""):gsub("'", "''") .. "'"
            end
            table.insert(commands, string.format('certutil -f -decode %s %s >nul 2>nul', win_quote(tempB64), win_quote(dest_path)))
            table.insert(commands, string.format('powershell -NoLogo -NoProfile -Command "Try { $b=[IO.File]::ReadAllText(%s); [IO.File]::WriteAllBytes(%s,[Convert]::FromBase64String($b)); exit 0 } Catch { exit 1 }"', ps_quote(tempB64), ps_quote(dest_path)))
        else
            table.insert(commands, string.format('base64 -D -i %q -o %q 2>/dev/null', tempB64, dest_path))
            table.insert(commands, string.format('base64 -d %q > %q 2>/dev/null', tempB64, dest_path))
            table.insert(commands, string.format('openssl base64 -d -A -in %q -out %q 2>/dev/null', tempB64, dest_path))
        end

        local expected_min = nil
        if expected_bytes and expected_bytes > 0 then
            local min_ratio = 0.85
            if expected_bytes < 2048 then
                min_ratio = 0.6
            end
            expected_min = math.max(128, math.floor(expected_bytes * min_ratio))
        end

        local success = false
        local out_size = 0
        for _, cmd in ipairs(commands) do
            if Utils.fileExists(dest_path) then
                os.remove(dest_path)
            end
            if Utils.runShellCommand(cmd) and Utils.fileExists(dest_path) then
                local sz = Utils.getFileSize(dest_path)
                if sz > 0 then
                    if not expected_min or sz >= expected_min then
                        success = true
                        out_size = sz
                        break
                    end
                end
            end
        end
        os.remove(tempB64)
        if not success and Utils.fileExists(dest_path) then
            os.remove(dest_path)
        end
        return success, out_size
    end

    local function system_base64_decode_string(payload)
        if type(payload) ~= "string" or payload == "" then
            return ""
        end
        local tempOut, errOut = Utils.makeTempPath("bin")
        if not tempOut then
            return nil, errOut
        end
        local expected = estimate_decoded_size(payload)
        local ok, _ = system_decode_base64(payload, tempOut, expected)
        if ok then
            local f = io.open(tempOut, "rb")
            local bytes = f and f:read("*a") or ""
            if f then f:close() end
            os.remove(tempOut)
            return bytes
        end
        os.remove(tempOut)
        return nil, "system_decode_failed"
    end

    function Utils.base64Decode(b64)
        local payload = strip_data_url(b64 or "")
        payload = payload:gsub("[^%w%+/%=]", "")
        if payload == "" then
            return ""
        end
        local decoded = select(1, system_base64_decode_string(payload))
        if decoded then
            return decoded
        end
        return ""
    end

    function Utils.decodeBase64ToFile(dataUrl, dest_path)
        if type(dest_path) ~= "string" or dest_path == "" then
            return false, "invalid_dest"
        end
        local payload = strip_data_url(dataUrl or "")
        payload = payload:gsub("[^%w%+/%=]", "")
        if payload == "" then
            return false, "invalid_data_url"
        end
        local expected = estimate_decoded_size(payload)
        local sys_ok, sys_size = system_decode_base64(payload, dest_path, expected)
        if sys_ok then
            return true, sys_size
        end

        return false, "system_decode_failed"
    end

    -- 把图片文件编码为 data:URL（兼容 jpg/png）
    function Utils.encodeImageToBase64(imgPath)
        local f = io.open(imgPath, "rb"); if not f then return nil end
        local blob = f:read("*a"); f:close()
        local ext  = (tostring(imgPath):lower():match("%.([^%.]+)$") or "png")
        local mime = (ext == "jpg" or ext == "jpeg") and "jpeg" or "png"
        return ("data:image/%s;base64,%s"):format(mime, Utils.base64Encode(blob))
    end

    function Utils.saveDataUrlImage(dataUrl, saveDir, prefix)
        if type(dataUrl) ~= "string" or dataUrl == "" then
            return nil, "invalid_data_url"
        end
        saveDir = Utils.trim(saveDir or "")
        if saveDir == "" then
            saveDir = Utils.getTempDir()
        end
        if not Utils.ensureDir(saveDir) then
            return nil, "save_dir_unavailable"
        end

        local mimeType = dataUrl:match("^data:image/([%w%-%+%.]+)")
        local ext = "png"
        if mimeType then
            local lowerMime = mimeType:lower()
            if lowerMime == "jpeg" or lowerMime == "jpg" then
                ext = "jpg"
            elseif lowerMime == "webp" then
                ext = "webp"
            elseif lowerMime == "gif" then
                ext = "gif"
            else
                ext = lowerMime:gsub("[^%w]", "")
                if ext == "" then ext = "png" end
            end
        end

        local prefixValue = Utils.sanitizeFilename(prefix or "image_edit_")
        if prefixValue == "" then
            prefixValue = "image_edit_"
        end
        local uniqueName = string.format("%s%d_%04d", prefixValue, os.time(), math.random(0, 9999))
        local filename = uniqueName .. "." .. ext
        local destPath = Utils.joinPath(saveDir, filename)
        local decode_ok, size_or_err = Utils.decodeBase64ToFile(dataUrl, destPath)
        if not decode_ok then
            os.remove(destPath)
            return nil, size_or_err or "decode_failed"
        end

        return destPath, size_or_err
    end

    function Utils.saveImageFromUrl(imageUrl, saveDir, prefix)
        if type(imageUrl) ~= "string" or imageUrl == "" then
            return nil, "invalid_url"
        end
        saveDir = Utils.trim(saveDir or "")
        if saveDir == "" then
            saveDir = Utils.getTempDir()
        end
        if not Utils.ensureDir(saveDir) then
            return nil, "save_dir_unavailable"
        end

        local ext = imageUrl:match("%.([%w%d]+)(%?.*)?$")
        if ext then
            ext = ext:lower()
            if ext == "jpeg" then ext = "jpg" end
            if ext == "" then ext = nil end
        end
        if not ext or #ext > 6 then
            ext = "png"
        end

        local prefixValue = Utils.sanitizeFilename(prefix or "image_edit_")
        if prefixValue == "" then
            prefixValue = "image_edit_"
        end
        local filename = string.format("%s%d_%04d.%s", prefixValue, os.time(), math.random(0, 9999), ext)
        local destPath = Utils.joinPath(saveDir, filename)

        local cmd
        if Utils.IS_WINDOWS then
            cmd = string.format('curl -sS -L -f --max-time 300 -o "%s" "%s"', destPath, imageUrl:gsub('"', '\\"'))
        else
            cmd = string.format('curl -sS -L -f --max-time 300 -o %q %q', destPath, imageUrl)
        end

        if not Utils.runShellCommand(cmd) or not Utils.fileExists(destPath) then
            os.remove(destPath)
            return nil, "download_failed"
        end

        local size = Utils.getFileSize(destPath)
        if not size or size <= 0 then
            os.remove(destPath)
            return nil, "download_empty"
        end

        return destPath, size
    end

    App.Utils = Utils
end

---
--- 4. 更新检测模块 (App.Update)
---
do
    local Update = {}
    local Utils = App.Utils
    local Config = App.Config
    local json = require("dkjson")

    function Update:_fetch()
        local url = string.format(
            "%s/functions/v1/check_update?pid=%s",
            Config.SUPABASE_URL,
            Utils.urlEncode(Config.SCRIPT_NAME)
        )
        local headers = {
            Authorization = "Bearer " .. Config.SUPABASE_ANON_KEY,
            apikey = Config.SUPABASE_ANON_KEY,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = string.format("%s/%s", Config.SCRIPT_NAME, Config.SCRIPT_VERSION),
        }
        local ok, body, status = Utils.httpGet(url, headers, Config.SUPABASE_TIMEOUT)
        if not ok then
            return nil
        end
        if status and status ~= 200 and status ~= 0 then
            return nil
        end
        local decoded, pos, err = json.decode(body)
        if type(decoded) ~= "table" then
            print(string.format("[Update] Invalid response: %s (pos=%s, err=%s)", tostring(body), tostring(pos), tostring(err)))
            return nil
        end
        return decoded
    end

    function Update:_build_message(payload, lang, latest, current)
        local key = lang == "zh" and "cn" or "en"
        local info = ""
        if type(payload) == "table" then
            info = Utils.trim(payload[key] or payload[lang])
        end
        local readableCurrent = Utils.trim(current or "")
        if readableCurrent == "" then
            readableCurrent = (lang == "zh") and "未知" or "unknown"
        end
        local line
        if lang == "zh" then
            line = string.format("发现新版本：%s → %s，请前往购买页下载。", readableCurrent, latest)
        else
            line = string.format("Update available: %s → %s. Download it from your purchase page.", readableCurrent, latest)
        end
        if info ~= "" then
            return info .. "\n" .. line
        end
        return line
    end

    function Update:check_for_updates()
        local ok, payload = pcall(function()
            return self:_fetch()
        end)
        if not ok or type(payload) ~= "table" then
            return nil, "fetch_failed"
        end
        local latest = Utils.trim(tostring(payload.latest or ""))
        local current = Utils.trim(tostring(Config.SCRIPT_VERSION or ""))
        if latest == "" or latest == current then
            return nil, "no_update"
        end
        local info = {
            latest = latest,
            current = current,
            en = self:_build_message(payload, "en", latest, current),
            cn = self:_build_message(payload, "zh", latest, current),
        }
        return info, nil
    end

    App.Update = Update
end

---
--- 5. Resolve 交互模块 (App.Resolve)
---
do
    local R = {}
    local Core = App.Core
    local Utils = App.Utils

    R.project = Core.resolve:GetProjectManager():GetCurrentProject()
    R.timeline = R.project and R.project:GetCurrentTimeline()
    R.mediaPool = R.project and R.project:GetMediaPool()
    R.rootFolder = R.mediaPool and R.mediaPool:GetRootFolder()
    R.fps = (R.project and tonumber(R.project:GetSetting("timelineFrameRate"))) or 24.0

    if not R.timeline then
        print(string.format("%s: 无法获取当前项目或时间线.", App.Config.SCRIPT_NAME))
    end

    -- 动态获取当前时间线
    function R.get_current_timeline()
        if not App.Core or not App.Core.resolve then
            return nil
        end
        local project = App.Core.resolve:GetProjectManager():GetCurrentProject()
        if not project then
            return nil
        end
        local timeline = project:GetCurrentTimeline()
        return timeline
    end

    function R.get_first_empty_track(timeline, start_frame, end_frame, media_type)
        local idx = 1
        while true do
            local items = timeline:GetItemListInTrack(media_type, idx)
            if not items or #items == 0 then return idx end
            local is_empty = true
            for _, itm in ipairs(items) do
                local s, e = itm:GetStart(), itm:GetEnd()
                if s <= end_frame and start_frame <= e then
                    is_empty = false
                    break
                end
            end
            if is_empty then return idx end
            idx = idx + 1
        end
    end

    function R.export_current_frame(prefix)
        -- 动态获取当前项目
        if not App.Core or not App.Core.resolve then
            return nil, "Resolve API not available"
        end

        local project = App.Core.resolve:GetProjectManager():GetCurrentProject()
        if not project then
            return nil, "No current project"
        end

        local tempDir = Utils.getTempDir()
        if not Utils.ensureDir(tempDir) then
            return nil, "temp directory unavailable"
        end

        local filename = string.format("%s_%s.png", prefix, tostring(os.time()))
        local abs_path = Utils.joinPath(tempDir, filename)

        local ok, export_err = pcall(function()
            return project:ExportCurrentFrameAsStill(abs_path)
        end)

        if not ok or not export_err then
            os.remove(abs_path)
            return nil, "ExportCurrentFrameAsStill failed: " .. tostring(export_err)
        end
        if not Utils.fileExists(abs_path) then
             return nil, "still not created"
        end
        return abs_path
    end

    -- options:
    --   duration_frames -> limit appended range (per AppendToTimeline spec)
    --   track_index     -> force append onto specific video track
    function R.append_to_timeline(start_frame, end_frame, filename, provider_tag, options)
        -- 动态获取当前项目和媒体池
        if not App.Core or not App.Core.resolve then
            return false, "Resolve API not available"
        end
        local opts = options or {}

        local project = App.Core.resolve:GetProjectManager():GetCurrentProject()
        if not project then
            return false, "No current project"
        end

        local mediaPool = project:GetMediaPool()
        if not mediaPool then
            return false, "media pool unavailable"
        end

        local timeline = project:GetCurrentTimeline()
        if not timeline then
            return false, "timeline unavailable"
        end

        local rootFolder = mediaPool:GetRootFolder()
        if not rootFolder then
            return false, "root folder unavailable"
        end

        local folder = nil
        for _, f in ipairs(rootFolder:GetSubFolderList() or {}) do
            if f:GetName() == (provider_tag or "ImageEdit") then
                folder = f
                break
            end
        end
        if not folder then
            folder = mediaPool:AddSubFolder(rootFolder, (provider_tag or "ImageEdit"))
        end
        if not folder then return false, "failed to create folder" end

        mediaPool:SetCurrentFolder(folder)
        local imported = mediaPool:ImportMedia({filename})
        if not imported or not imported[1] then
            return false, "import failed"
        end

        local clip = imported[1]
        local duration_tc = clip:GetClipProperty("Duration")
        local duration_frames = (tonumber(duration_tc:match("(%d+)$")) or 1)

        local desired_track = tonumber(opts.track_index or 0)
        local track_index
        if desired_track and desired_track >= 1 then
            local ensured = true
            local existing = timeline:GetTrackCount("video") or 0
            while existing < desired_track do
                if not timeline:AddTrack("video") then
                    ensured = false
                    break
                end
                existing = timeline:GetTrackCount("video") or existing + 1
            end
            if ensured then
                track_index = desired_track
            end
        end
        if not track_index then
            track_index = R.get_first_empty_track(timeline, start_frame, end_frame, "video")
        end

        local duration_override = nil
        if opts.duration_frames then
            local val = math.floor(tonumber(opts.duration_frames) or 0)
            if val >= 1 then
                duration_override = val
            end
        end

        local clip_info = {
            mediaPoolItem = clip,
            startFrame = 0,
            endFrame = duration_frames - 1,
            mediaType = 1,
            trackIndex = track_index or 1,
            recordFrame = math.max(0, tonumber(start_frame) or 0),
            stereoEye = "both"
        }
        if duration_override then
            local clip_len = math.min(duration_frames, duration_override)
            clip_info.endFrame = clip_info.startFrame + clip_len - 1
        end
        local ok_append = mediaPool:AppendToTimeline({clip_info})
        local success = false
        if type(ok_append) == "table" then
            success = #ok_append > 0
        else
            success = ok_append and ok_append ~= 0
        end
        if success then
            local finalTrack = track_index or 1
            print(string.format("Appended clip %s to timeline at %d (track %d)", clip:GetName(), start_frame, finalTrack))
            return true, ok_append
        end
        return false, "append failed"
    end

    function R.import_to_media_pool(filename, folder_name)
        if not App.Core or not App.Core.resolve then
            return false, "Resolve API not available"
        end
        local project = App.Core.resolve:GetProjectManager():GetCurrentProject()
        if not project then
            return false, "No current project"
        end
        local mediaPool = project:GetMediaPool()
        if not mediaPool then
            return false, "media pool unavailable"
        end
        local rootFolder = mediaPool:GetRootFolder()
        if not rootFolder then
            return false, "root folder unavailable"
        end
        local targetName = folder_name or "ImageGenerate"
        local folder = nil
        for _, f in ipairs(rootFolder:GetSubFolderList() or {}) do
            if f:GetName() == targetName then
                folder = f
                break
            end
        end
        if not folder then
            folder = mediaPool:AddSubFolder(rootFolder, targetName)
        end
        if not folder then
            return false, "failed to create folder"
        end
        mediaPool:SetCurrentFolder(folder)
        local imported = mediaPool:ImportMedia({filename})
        if not imported or not imported[1] then
            return false, "import failed"
        end
        return true, imported[1]
    end

    App.Resolve = R
end

---
--- 6. UI 模块 (App.UI)
---
do
    local UI = {}
    local Core = App.Core
    local Config = App.Config
    local Utils = App.Utils
    local json = require("dkjson")
    local ui = Core.ui

    UI.translations = {
        cn = {
            Tabs = {"图片生成", "图片编辑", "设置"},
            OriginalImage = "原始图片",
            EditedImage = "编辑结果",
            GeneratedResult = "生成结果",
            UploadImage = "选择图片",
            FromTimeline = "提取当前帧",
            ContinueEdit = "继续编辑",
            ApplyToTimeline = "放到时间线开头",
            AddToPool = "添加到媒体池",
            PromptPlaceholder = "用一句话描述你想要的效果",
            Generate = "开始生成",
            Progress = "进度",
            SavePath = "保存到",
            SavePathPlaceholder = "/选择保存文件夹",
            Browse = "浏览",
            OutputSettings = "输出设置",
            GoogleConfigLabel = "Google",
            GoogleConfigBtn = "配置",
            GoogleConfigTitle = "Google",
            GoogleBaseURL = "Base URL",
            GoogleApiKey = "密钥",
            ConfigConfirm = "保存",
            ConfigRegister = "注册",
            SeedConfigLabel = "Seed Dream",
            SeedConfigBtn = "配置",
            SeedConfigTitle = "Seed Dream",
            SeedBaseURL = "Base URL",
            SeedApiKey = "密钥",
            Donation = "☕ 探索更多功能 ☕",
            ProviderLabel = "选择服务",
            AspectRatioLabel = "画幅比例",
            GoogleAspectRatioLabel = "Google 宽高比",
            ResolutionLabel = "清晰度",
            Ready = "就绪",
            Uploading = "上传中...",
            Processing = "处理中...",
            Success = "成功",
            Error = "错误"
        },
        en = {
            Tabs = {"Image Generate", "Image Edit", "Settings"},
            OriginalImage = "Original",
            EditedImage = "Result",
            GeneratedResult = "Generated Result",
            UploadImage = "Pick Image",
            FromTimeline = "Grab Current Frame",
            ContinueEdit = "Continue Editing",
            ApplyToTimeline = "Add to Timeline Start",
            AddToPool = "Add to Media Pool",
            PromptPlaceholder = "In one line, describe the change you want",
            Generate = "Generate",
            Reset = "Clear",
            Progress = "Progress",
            SavePath = "Save to",
            SavePathPlaceholder = "/choose a folder",
            Browse = "Browse",
            OutputSettings = "Output Settings",
            GoogleConfigLabel = "Google",
            GoogleConfigBtn = "Configure",
            GoogleConfigTitle = "Google",
            GoogleBaseURL = "Base URL",
            GoogleApiKey = "API Key",
            ConfigConfirm = "Save",
            ConfigRegister = "Sign up",
            SeedConfigLabel = "Seed Dream",
            SeedConfigBtn = "Configure",
            SeedConfigTitle = "Seed Dream",
            SeedBaseURL = "Base URL",
            SeedApiKey = "API Key",
            Donation = "☕ Explore More Features ☕",
            ProviderLabel = "Service",
            AspectRatioLabel = "Aspect Ratio",
            GoogleAspectRatioLabel = "Google Aspect Ratio",
            ResolutionLabel = "Quality",
            Ready = "Ready",
            Uploading = "Uploading...",
            Processing = "Processing...",
            Success = "Success",
            Error = "Error"
        }
    }

    local function tr(key, lang)
        local langKey = (lang == "en") and "en" or (lang == "cn" and "cn") or (UI.currentLang or "cn")
        local data = UI.translations[langKey] or UI.translations.cn
        return (data and data[key]) or ""
    end
    UI.tr = tr

    UI.messages = {
        status = {
            ready = {cn = "准备就绪", en = "Ready"},
            validating = {cn = "正在检查输入...", en = "Checking your input..."},
            needPrompt = {cn = "请输入提示词", en = "Please describe the change you want"},
            needImage = {cn = "请先选择一张图片", en = "Please pick an image first"},
            needSavePath = {cn = "请先选择保存路径", en = "Please choose a save folder first"},
            savePathInvalid = {cn = "保存位置不可用，请重新选择", en = "Save location unavailable, please choose another"},
            preparingImage = {cn = "正在准备图片...", en = "Preparing the image..."},
            readImageFail = {cn = "图片读取失败，请重新选择", en = "Couldn't read the image, please choose again"},
            generating = {cn = "正在生成中，预计 3～5 分钟，请稍候...", en = "Generating (about 3–5 minutes), please wait..."},
            downloadInterrupted = {cn = "下载中断，请重试", en = "Download interrupted, please retry"},
            parsing = {cn = "正在整理结果...", en = "Putting the results together..."},
            saving = {cn = "正在保存图片...", en = "Saving the image..."},
            saveFailed = {cn = "保存失败，请检查路径或空间", en = "Save failed, check the path or disk space"},
            success = {cn = "完成", en = "Done"},
            requestFailed = {cn = "请求没有成功，请稍后再试", en = "The request didn't succeed, please try again later"},
            addedToPool = {cn = "已加入媒体池", en = "Added to media pool"}
        },
        error = {
            needGoogleConfig = {cn = "请先在设置里填好 Google 服务信息", en = "Please complete the Google settings first"},
            needSeedConfig = {cn = "请先在设置里填好 Seed Dream 信息", en = "Please complete the Seed Dream settings first"},
            invalidBaseUrl = {cn = "地址好像不对，请检查后重试", en = "The service address looks incorrect, please check and try again"},
            encodeFailed = {cn = "图片处理失败，请重试", en = "Image processing failed, please try again"},
            requestFailed = {cn = "请求没有成功，请稍后再试", en = "The request didn't succeed, please try again later"},
            responseParseFailed = {cn = "结果读取失败，请稍后再试", en = "Couldn't read the result, please try again later"},
            responseNoImage = {cn = "没有收到图片，请重试", en = "No image was received, please try again"}
        }
    }

    -- 当前语言
    UI.currentLang = "cn"

    -- 初始化配置
    UI.config = Utils.loadConfig() or Config.DEFAULT_CONFIG
    -- 确保配置表存在且有所有必要字段
    if not UI.config or type(UI.config) ~= "table" then
        UI.config = Config.DEFAULT_CONFIG
    end
    local function ensure_provider_table(target, key, defaults)
        target[key] = target[key] or {}
        for dk, dv in pairs(defaults) do
            if target[key][dk] == nil then
                target[key][dk] = dv
            end
        end
    end
    ensure_provider_table(UI.config, "google", Config.DEFAULT_CONFIG.google)
    ensure_provider_table(UI.config, "google_gen", Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google)
    ensure_provider_table(UI.config, "seeddream", Config.DEFAULT_CONFIG.seeddream)
    UI.config.google_pro = nil
    if not UI.config.provider_choice or UI.config.provider_choice == "" then
        UI.config.provider_choice = Config.DEFAULT_CONFIG.provider_choice
    end
    if not UI.config.generator_provider_choice or UI.config.generator_provider_choice == "" then
        UI.config.generator_provider_choice = "google"
    end
    if not UI.config.google.aspect_ratio or UI.config.google.aspect_ratio == "" then
        UI.config.google.aspect_ratio = Config.DEFAULT_CONFIG.google.aspect_ratio
    end
    if not UI.config.google.resolution or UI.config.google.resolution == "" then
        UI.config.google.resolution = Config.DEFAULT_CONFIG.google.resolution
    end
    if not UI.config.google_gen.aspect_ratio or UI.config.google_gen.aspect_ratio == "" then
        UI.config.google_gen.aspect_ratio = (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).aspect_ratio
    end
    if not UI.config.google_gen.resolution or UI.config.google_gen.resolution == "" then
        UI.config.google_gen.resolution = (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).resolution
    end
    if not UI.config.seeddream.aspect_ratio or UI.config.seeddream.aspect_ratio == "" then
        UI.config.seeddream.aspect_ratio = Config.DEFAULT_CONFIG.seeddream.aspect_ratio
    end

    UI.providerOptions = {
        {id = "google", label = "Nano Banana 🍌"},
        {id = "google_pro", label = "Nano Banana Pro 🍌"},
        {id = "seeddream", label = "Seed Dream 4.0"}
    }

    local function provider_index_by_id(pid)
        for idx, opt in ipairs(UI.providerOptions) do
            if opt.id == pid then
                return idx
            end
        end
        return 1
    end
    UI._provider_index_by_id = provider_index_by_id

    local function provider_label_by_id(pid)
        local idx = provider_index_by_id(pid)
        local opt = UI.providerOptions[idx]
        return opt and opt.label or UI.providerOptions[1].label
    end
    UI._provider_label_by_id = provider_label_by_id

    local function provider_id_by_index(idx)
        local opt = UI.providerOptions[idx]
        return opt and opt.id or UI.providerOptions[1].id
    end
    UI._provider_id_by_index = provider_id_by_index

    local function is_google_provider(pid)
        return pid == "google" or pid == "google_pro"
    end

    local function is_google_pro(pid)
        return pid == "google_pro"
    end
    UI.is_google_provider = is_google_provider
    UI.is_google_pro = is_google_pro

    UI.aspectRatioOptions = {
        {id = "1:1",   label = "1:1", size = "2048x2048"},
        {id = "4:3",   label = "4:3", size = "2304x1728"},
        {id = "3:4",   label = "3:4", size = "1728x2304"},
        {id = "16:9",  label = "16:9", size = "2560x1440"},
        {id = "9:16",  label = "9:16", size = "1440x2560"},
        {id = "3:2",   label = "3:2", size = "2496x1664"},
        {id = "2:3",   label = "2:3", size = "1664x2496"},
        {id = "21:9",  label = "21:9", size = "3024x1296"}
    }

    UI.resolutionOptionsFlash = {
        {id = "1K", label = "1K"}
    }

    UI.resolutionOptionsPro = {
        {id = "1K", label = "1K"},
        {id = "2K", label = "2K"},
        {id = "4K", label = "4K"}
    }

    local function resolution_options_by_provider(pid)
        if is_google_pro(pid) then
            return UI.resolutionOptionsPro
        end
        if pid == "google" then
            return UI.resolutionOptionsFlash
        end
        return UI.resolutionOptionsPro
    end
    UI.resolution_options_by_provider = resolution_options_by_provider

    local function resolution_index_by_id(providerId, rid)
        rid = rid or ""
        local opts = resolution_options_by_provider(providerId)
        for idx, opt in ipairs(opts) do
            if opt.id == rid then
                return idx
            end
        end
        return 1
    end
    UI.resolution_index_by_id = resolution_index_by_id

    local function aspect_ratio_index_by_id(rid)
        rid = rid or ""
        for idx, opt in ipairs(UI.aspectRatioOptions) do
            if opt.id == rid then
                return idx
            end
        end
        return 1
    end
    UI._aspect_ratio_index_by_id = aspect_ratio_index_by_id

    local function aspect_ratio_data_by_id(rid)
        return UI.aspectRatioOptions[aspect_ratio_index_by_id(rid)]
    end
    UI._aspect_ratio_data_by_id = aspect_ratio_data_by_id

    local function get_provider_aspect_id(pid)
        if pid == "seeddream" then
            return (UI.config.seeddream and UI.config.seeddream.aspect_ratio) or Config.DEFAULT_CONFIG.seeddream.aspect_ratio
        else
            return (UI.config.google and UI.config.google.aspect_ratio) or Config.DEFAULT_CONFIG.google.aspect_ratio
        end
    end
    UI.get_provider_aspect_id = get_provider_aspect_id

    -- 生成页专用：使用独立的 google_gen 配置，避免与编辑页互相影响
    local function get_generator_aspect_id(pid)
        if pid == "google" or pid == "google_pro" then
            return (UI.config.google_gen and UI.config.google_gen.aspect_ratio) or (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).aspect_ratio
        end
        -- 生成页目前只支持 Google，其他返回默认
        return (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).aspect_ratio
    end
    UI.get_generator_aspect_id = get_generator_aspect_id

    local function set_provider_aspect_id(pid, rid)
        if pid == "seeddream" then
            UI.config.seeddream = UI.config.seeddream or {}
            UI.config.seeddream.aspect_ratio = rid
        else
            UI.config.google = UI.config.google or {}
            UI.config.google.aspect_ratio = rid
        end
    end
    UI.set_provider_aspect_id = set_provider_aspect_id

    local function set_generator_aspect_id(pid, rid)
        if pid == "google" or pid == "google_pro" then
            UI.config.google_gen = UI.config.google_gen or {}
            UI.config.google_gen.aspect_ratio = rid
        end
    end
    UI.set_generator_aspect_id = set_generator_aspect_id

    local function get_provider_resolution_id(pid)
        if pid == "google_pro" or pid == "google" then
            return (UI.config.google and UI.config.google.resolution) or Config.DEFAULT_CONFIG.google.resolution
        end
        return Config.DEFAULT_CONFIG.google.resolution
    end
    UI.get_provider_resolution_id = get_provider_resolution_id

    local function get_generator_resolution_id(pid)
        if pid == "google_pro" or pid == "google" then
            return (UI.config.google_gen and UI.config.google_gen.resolution) or (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).resolution
        end
        return (Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google).resolution
    end
    UI.get_generator_resolution_id = get_generator_resolution_id

    local function set_provider_resolution_id(pid, rid)
        if pid == "google_pro" or pid == "google" then
            UI.config.google = UI.config.google or {}
            UI.config.google.resolution = rid
        end
    end
    UI.set_provider_resolution_id = set_provider_resolution_id

    local function set_generator_resolution_id(pid, rid)
        if pid == "google_pro" or pid == "google" then
            UI.config.google_gen = UI.config.google_gen or {}
            UI.config.google_gen.resolution = rid
        end
    end
    UI.set_generator_resolution_id = set_generator_resolution_id

    -- 安全函数：获取配置值
    UI.getConfigValue = function(key)
        return UI.config and UI.config[key] or Config.DEFAULT_CONFIG[key]
    end

    -- Image Editor Tab UI
    function UI.build_image_editor_tab()
        return ui.VGroup{
            Spacing = 10,
            Weight = 1,
            ui.HGroup{
                Spacing = 15,
                Weight = 1,
                -- 左侧：原始图片
                ui.VGroup{
                    Spacing = 8,
                    Weight = 1,
                    ui.Label{
                        ID = "OriginalImageLabel",
                        Text = tr("OriginalImage"),
                        Alignment = {AlignHCenter = true},
                        Font = ui.Font{PixelSize = 14, StyleName = "Bold"},
                        Weight = 0
                    },
                    ui.Button{
                        ID = "OriginalImagePreview",
                        Flat = true,
                        IconSize = {256, 256},
                        MinimumSize = {256, 256},
                        StyleSheet = "border:2px dashed #555; border-radius:4px; background:transparent;",
                        Weight = 1
                    },
                    ui.HGroup{
                        Spacing = 8,
                        Weight = 0,
                        ui.Button{
                            ID = "UploadImageBtn",
                            Text = tr("UploadImage"),
                            Weight = 1
                        },
                        ui.Button{
                            ID = "FromTimelineBtn",
                            Text = tr("FromTimeline"),
                            Weight = 1
                        }
                    }
                },
                -- 右侧：编辑后图片
                ui.VGroup{
                    Spacing = 8,
                    Weight = 1,
                    ui.Label{
                        ID = "EditedImageLabel",
                        Text = tr("EditedImage"),
                        Alignment = {AlignHCenter = true},
                        Font = ui.Font{PixelSize = 14, StyleName = "Bold"},
                        Weight = 0
                    },
                    ui.Button{
                        ID = "EditedImagePreview",
                        Flat = true,
                        IconSize = {256, 256},
                        MinimumSize = {256, 256},
                        StyleSheet = "border:2px dashed #555; border-radius:4px; background:transparent;",
                        Weight = 1
                    },
                    ui.HGroup{
                        Spacing = 8,
                        Weight = 0,
                        ui.Button{
                            ID = "ContinueEditBtn",
                            Text = tr("ContinueEdit"),
                            Weight = 1
                        },
                        ui.Button{
                            ID = "EditAddToPoolBtn",
                            Text = tr("AddToPool"),
                            Weight = 1
                        }
                    }
                }
            },
            -- Prompt 输入
            ui.VGroup{
                Spacing = 5,
                Weight = 0.5,
                ui.TextEdit{
                    ID = "PromptTextEdit",
                    PlaceholderText = tr("PromptPlaceholder"),
                    Weight = 1
                },
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "ProviderLabel",
                        Text = tr("ProviderLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "ProviderCombo",
                        Editable = false,
                        Weight = 1,
                        Events = {CurrentIndexChanged = true}
                    }
                },
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "AspectRatioLabel",
                        Text = tr("AspectRatioLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "AspectRatioCombo",
                        Editable = false,
                        Weight = 1,
                        Events = {CurrentIndexChanged = true}
                    },
                    ui.Label{
                        ID = "ResolutionLabel",
                        Text = tr("ResolutionLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "ResolutionCombo",
                        Editable = false,
                        Weight = 1,
                        Enabled = is_google_provider(UI.config.provider_choice),
                        Events = {CurrentIndexChanged = true}
                    }
                }
            },
            -- 控制按钮和进度
            ui.HGroup{
                Spacing = 10,
                Weight = 0,
                ui.Button{
                    ID = "GenerateBtn",
                    Text = tr("Generate"),
                    Font = ui.Font{PixelSize = 14, StyleName = "Bold"},
                    Weight = 1
                },
            },
            ui.HGroup{
                Spacing = 8,
                Weight = 0,
                ui.Label{
                    ID = "StatusLabel",
                    Text = (UI.messages.status.ready and UI.messages.status.ready[(UI.currentLang == "en") and "en" or "cn"]) or UI.translations[UI.currentLang].Ready,
                    Alignment = {AlignHCenter = true},
                    StyleSheet = "color:#d9534f; font-weight:bold;",
                    Weight = 1
                }
            },
            ui.Button{
                ID = "DonationButtonEdit",
                Text = tr("Donation"),
                Alignment = {AlignHCenter = true, AlignVCenter = true},
                Font = ui.Font{PixelSize = 12, StyleName = "Bold"},
                Flat = true,
                TextColor = {1, 1, 1, 1},
                BackgroundColor = {1, 1, 1, 0},
                Weight = 0
            }
        }
    end

    function UI.build_image_generate_tab()
        return ui.VGroup{
            Spacing = 10,
            Weight = 1,
            ui.Button{
                ID = "GenImagePreview",
                Flat = true,
                IconSize = {256, 256},
                MinimumSize = {256, 256},
                StyleSheet = "border:2px dashed #555; border-radius:4px; background:transparent;",
                Weight = 1
            },
            ui.HGroup{
                Spacing = 8,
                Weight = 0,
                ui.Button{
                    ID = "GenAddToPoolBtn",
                    Text = tr("AddToPool"),
                    Weight = 1
                }
            },
            ui.VGroup{
                Spacing = 5,
                Weight = 0.5,
                ui.TextEdit{
                    ID = "GenPromptTextEdit",
                    PlaceholderText = tr("PromptPlaceholder"),
                    Weight = 1
                },
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "GenProviderLabel",
                        Text = tr("ProviderLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "GenProviderCombo",
                        Editable = false,
                        Weight = 1,
                        Events = {CurrentIndexChanged = true}
                    }
                },
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "GenAspectRatioLabel",
                        Text = tr("AspectRatioLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "GenAspectRatioCombo",
                        Editable = false,
                        Weight = 1,
                        Events = {CurrentIndexChanged = true}
                    },
                    ui.Label{
                        ID = "GenResolutionLabel",
                        Text = tr("ResolutionLabel"),
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.ComboBox{
                        ID = "GenResolutionCombo",
                        Editable = false,
                        Weight = 1,
                        Events = {CurrentIndexChanged = true}
                    }
                },
            },
           
            ui.HGroup{
                Spacing = 10,
                Weight = 0,
                ui.Button{
                    ID = "GenGenerateBtn",
                    Text = tr("Generate"),
                    Font = ui.Font{PixelSize = 14, StyleName = "Bold"},
                    Weight = 1
                }
            },
            ui.Label{
                ID = "GenStatusLabel",
                Text = (UI.messages.status.ready and UI.messages.status.ready[(UI.currentLang == "en") and "en" or "cn"]) or tr("Ready"),
                Alignment = {AlignHCenter = true},
                StyleSheet = "color:#d9534f; font-weight:bold;",
                Weight = 0
            },
            ui.Button{
                ID = "DonationButtonGen",
                Text = tr("Donation"),
                Alignment = {AlignHCenter = true, AlignVCenter = true},
                Font = ui.Font{PixelSize = 12, StyleName = "Bold"},
                Flat = true,
                TextColor = {1, 1, 1, 1},
                BackgroundColor = {1, 1, 1, 0},
                Weight = 0
            }
        }
    end

    -- Settings Tab UI
    function UI.build_settings_tab()
        return ui.VGroup{
            Spacing = 15,
            Weight = 1,
            -- 输出设置
            ui.VGroup{
                Spacing = 10,
                Weight = 0,
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "SavePathLabel",
                        Text = tr("SavePath"),
                        --Alignment = {AlignRight = true},
                        MinimumSize = {100, -1},
                        Weight = 0
                    },
                    ui.LineEdit{
                        ID = "SavePathEdit",
                        Text = UI.config.savePath or "",
                        PlaceholderText = tr("SavePathPlaceholder"),
                        Weight = 1
                    },
                    ui.Button{
                        ID = "BrowseBtn",
                        Text = tr("Browse"),
                        Weight = 0
                    }
                }
            },
            -- 服务商配置
            ui.VGroup{
                Spacing = 10,
                Weight = 0,
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "GoogleConfigLabel",
                        Text = tr("GoogleConfigLabel"),
                        Alignment = {AlignLeft = true},
                        Weight = 0.7
                    },
                    ui.Button{
                        ID = "GoogleConfigBtn",
                        Text = tr("GoogleConfigBtn"),
                        Weight = 0.3
                    }
                },
                ui.HGroup{
                    Spacing = 8,
                    Weight = 0,
                    ui.Label{
                        ID = "SeedConfigLabel",
                        Text = tr("SeedConfigLabel"),
                        Alignment = {AlignLeft = true},
                        Weight = 0.7
                    },
                    ui.Button{
                        ID = "SeedConfigBtn",
                        Text = tr("SeedConfigBtn"),
                        Weight = 0.3
                    }
                }
            },
            -- 语言设置
            ui.VGroup{
                Spacing = 10,
                Weight = 0,
                ui.HGroup{
                    Spacing = 10,
                    Weight = 0,
                    ui.CheckBox{
                        ID = "LangCnCheckBox",
                        Text = "简体中文",
                        Checked = (UI.config.currentLang == "cn"),
                        Weight = 0
                    },
                    ui.CheckBox{
                        ID = "LangEnCheckBox",
                        Text = "English",
                        Checked = (UI.config.currentLang == "en"),
                        Weight = 0
                    }
                }
            },
            ui.Button{
                ID = "DonationButtonSettings",
                Text = tr("Donation"),
                Alignment = {AlignHCenter = true, AlignVCenter = true},
                Font = ui.Font{PixelSize = 12, StyleName = "Bold"},
                Flat = true,
                TextColor = {1, 1, 1, 1},
                BackgroundColor = {1, 1, 1, 0},
                Weight = 0
            }
        }
    end

    -- Google 配置窗口
    function UI.create_google_config_window(Core, Config)
        local title = tr("GoogleConfigTitle")
        local x = math.floor((Config.SCREEN_WIDTH - 350) / 2)
        local y = math.floor((Config.SCREEN_HEIGHT - 150) / 2)
        local win = Core.dispatcher:AddWindow({
            ID = "GoogleConfigWin",
            WindowTitle = title,
            Geometry = {x, y, 350, 150},
            StyleSheet = "* { font-size: 14px; }",
            Hidden = true
        }, ui.VGroup{
            ui.Label{
                ID = "GoogleConfigTitleLabel",
                Text = title,
                Alignment = {AlignHCenter = true, AlignVCenter = true}
            },
            ui.HGroup{
                Weight = 1,
                ui.Label{
                    ID = "GoogleBaseURLLabel",
                    Text = tr("GoogleBaseURL"),
                    Alignment = {AlignRight = true},
                    Weight = 0.2
                },
                ui.LineEdit{
                    ID = "GoogleBaseURL",
                    Text = Utils.trim(UI.config.google.base_url or ""),
                    PlaceholderText = Config.GOOGLE_DEFAULT_BASE_URL,
                    Weight = 0.8
                }
            },
            ui.HGroup{
                Weight = 1,
                ui.Label{
                    ID = "GoogleApiKeyLabel",
                    Text = tr("GoogleApiKey"),
                    Alignment = {AlignRight = true},
                    Weight = 0.2
                },
                ui.LineEdit{
                    ID = "GoogleApiKey",
                    Text = UI.config.google.api_key or "",
                    PlaceholderText = "",
                    PasswordMode = true,
                    EchoMode = "Password",
                    Weight = 0.8
                }
            },
            ui.HGroup{
                Weight = 1,
                ui.Button{
                    ID = "GoogleConfigConfirm",
                    Text = tr("ConfigConfirm"),
                    Weight = 0.5
                },
                ui.Button{
                    ID = "GoogleConfigRegister",
                    Text = tr("ConfigRegister"),
                    Weight = 0.5
                }
            }
        })

        win.On.GoogleConfigWin.Close = function()
            win:Hide()
        end

        win.On.GoogleConfigConfirm.Clicked = function()
            local cfgItems = win:GetItems()
            if not cfgItems then return end
            local base = cfgItems.GoogleBaseURL and Utils.trim(cfgItems.GoogleBaseURL.Text or "") or ""
            local apiKey = cfgItems.GoogleApiKey and Utils.trim(cfgItems.GoogleApiKey.Text or "") or ""
            UI.config.google.base_url = base
            UI.config.google.api_key = apiKey
            -- 同步到生成页配置，避免两页用不同表导致缺少 API Key
            UI.config.google_gen = UI.config.google_gen or {}
            UI.config.google_gen.base_url = base
            UI.config.google_gen.api_key = apiKey
            Utils.saveConfig(UI.config)
            print("[Google] 配置已更新")
            win:Hide()
        end

        return win
    end

    -- Seed Dream 配置窗口
    function UI.create_seed_config_window(Core, Config)
        local title = tr("SeedConfigTitle")
        local x = math.floor((Config.SCREEN_WIDTH - 350) / 2)
        local y = math.floor((Config.SCREEN_HEIGHT - 150) / 2) + 40
        local win = Core.dispatcher:AddWindow({
            ID = "SeedConfigWin",
            WindowTitle = title,
            Geometry = {x, y, 350, 150},
            StyleSheet = "* { font-size: 14px; }",
            Hidden = true
        }, ui.VGroup{
            ui.Label{
                ID = "SeedConfigTitleLabel",
                Text = title,
                Alignment = {AlignHCenter = true, AlignVCenter = true}
            },
            ui.HGroup{
                Weight = 1,
                ui.Label{
                    ID = "SeedBaseURLLabel",
                    Text = tr("SeedBaseURL"),
                    Alignment = {AlignRight = true},
                    Weight = 0.2
                },
                ui.LineEdit{
                    ID = "SeedBaseURL",
                    Text = Utils.trim(UI.config.seeddream.base_url or ""),
                    PlaceholderText = Config.SEED_DEFAULT_BASE_URL,
                    Weight = 0.8
                }
            },
            ui.HGroup{
                Weight = 1,
                ui.Label{
                    ID = "SeedApiKeyLabel",
                    Text = tr("SeedApiKey"),
                    Alignment = {AlignRight = true},
                    Weight = 0.2
                },
                ui.LineEdit{
                    ID = "SeedApiKey",
                    Text = UI.config.seeddream.api_key or "",
                    PlaceholderText = "",
                    PasswordMode = true,
                    EchoMode = "Password",
                    Weight = 0.8
                }
            },
            ui.HGroup{
                Weight = 1,
                    ui.Button{
                        ID = "SeedConfigConfirm",
                        Text = tr("ConfigConfirm"),
                        Weight = 1
                    }
                }
            })

        win.On.SeedConfigWin.Close = function()
            win:Hide()
        end

        win.On.SeedConfigConfirm.Clicked = function()
            local cfgItems = win:GetItems()
            if not cfgItems then return end
            local base = cfgItems.SeedBaseURL and Utils.trim(cfgItems.SeedBaseURL.Text or "") or ""
            local apiKey = cfgItems.SeedApiKey and Utils.trim(cfgItems.SeedApiKey.Text or "") or ""
            UI.config.seeddream.base_url = base
            UI.config.seeddream.api_key = apiKey
            Utils.saveConfig(UI.config)
            print("[Seed Dream] 配置已更新")
            win:Hide()
        end

        return win
    end

    local text_map_main = {
        OriginalImageLabel = "OriginalImage",
        EditedImageLabel = "EditedImage",
        UploadImageBtn = "UploadImage",
        FromTimelineBtn = "FromTimeline",
        ContinueEditBtn = "ContinueEdit",
        EditAddToPoolBtn = "AddToPool",
        GenProviderLabel = "ProviderLabel",
        GenAspectRatioLabel = "AspectRatioLabel",
        GenResolutionLabel = "ResolutionLabel",
        GenAddToPoolBtn = "AddToPool",
        GenGenerateBtn = "Generate",
        ProviderLabel = "ProviderLabel",
        AspectRatioLabel = "AspectRatioLabel",
        ResolutionLabel = "ResolutionLabel",
        GenerateBtn = "Generate",
        SavePathLabel = "SavePath",
        BrowseBtn = "Browse",
        GoogleConfigLabel = "GoogleConfigLabel",
        GoogleConfigBtn = "GoogleConfigBtn",
        SeedConfigLabel = "SeedConfigLabel",
        SeedConfigBtn = "SeedConfigBtn",
        DonationButtonGen = "Donation",
        DonationButtonEdit = "Donation",
        DonationButtonSettings = "Donation"
    }

    local placeholder_map_main = {
        PromptTextEdit = "PromptPlaceholder",
        GenPromptTextEdit = "PromptPlaceholder",
        SavePathEdit = "SavePathPlaceholder"
    }

    local text_map_google = {
        GoogleConfigTitleLabel = "GoogleConfigTitle",
        GoogleBaseURLLabel = "GoogleBaseURL",
        GoogleApiKeyLabel = "GoogleApiKey",
        GoogleConfigConfirm = "ConfigConfirm",
        GoogleConfigRegister = "ConfigRegister"
    }

    local text_map_seed = {
        SeedConfigTitleLabel = "SeedConfigTitle",
        SeedBaseURLLabel = "SeedBaseURL",
        SeedApiKeyLabel = "SeedApiKey",
        SeedConfigConfirm = "ConfigConfirm"
    }

    local function apply_text_map(items, map, lang)
        if not items then return end
        for id, key in pairs(map) do
            if items[id] then
                items[id].Text = tr(key, lang)
            end
        end
    end

    local function apply_placeholder_map(items, map, lang)
        if not items then return end
        for id, key in pairs(map) do
            if items[id] and items[id].PlaceholderText ~= nil then
                items[id].PlaceholderText = tr(key, lang)
            end
        end
    end

    local function apply_tab_texts(items, lang)
        if not items or not items.MainTabs then return end
        local tabs = UI.translations[lang] and UI.translations[lang].Tabs
        if not tabs then return end
        for i, tab_name in ipairs(tabs) do
            items.MainTabs:SetTabText(i - 1, tab_name)
        end
    end

    -- 简单的加载提示窗口，用于更新检测
    function UI.run_with_loading(action)
        if type(action) ~= "function" then
            return
        end
        local dispatcher = Core.dispatcher
        local ui = Core.ui
        if not (dispatcher and ui) then
            return action()
        end
        local title = (UI.currentLang == "en") and "Checking update..." or "正在检查更新..."
        local win = dispatcher:AddWindow({
            ID = "ImageEditLoadingWin",
            WindowTitle = title,
            Geometry = {Config.LOADING_X_CENTER, Config.LOADING_Y_CENTER, Config.LOADING_WINDOW_WIDTH, Config.LOADING_WINDOW_HEIGHT},
            Hidden = true
        }, ui.VGroup{
            Weight = 1,
            Alignment = {AlignHCenter = true, AlignVCenter = true},
            ui.Label{
                ID = "LoadingLabel",
                Text = title,
                Alignment = {AlignHCenter = true, AlignVCenter = true},
                WordWrap = true,
                Weight = 1
            }
        })
        if not win then
            return action()
        end
        local items = win:GetItems()
        if items and items.LoadingLabel then
            items.LoadingLabel.Text = title
        end
        win:Show()
        local ok, result = pcall(action)
        if items and items.LoadingLabel then
            items.LoadingLabel.Text = (UI.currentLang == "en") and "Done" or "完成"
        end
        win:Hide()
        if win.DeleteLater then
            win:DeleteLater()
        end
        if not ok then
            error(result)
        end
        return result
    end

    function UI.switch_language(lang, win)
        local langKey = (lang == "en") and "en" or "cn"
        UI.currentLang = langKey

        local targetWin = win or UI.MainWin
        local items = targetWin and targetWin.GetItems and targetWin:GetItems() or UI.Items
        if items then
            apply_tab_texts(items, langKey)
            apply_text_map(items, text_map_main, langKey)
            apply_placeholder_map(items, placeholder_map_main, langKey)
            if items.StatusLabel and UI.messages and UI.messages.status and UI.messages.status.ready then
                local readyMsg = UI.messages.status.ready
                items.StatusLabel.Text = readyMsg[langKey] or readyMsg.cn or readyMsg.en or tr("Ready", langKey)
            end
            if items.GenStatusLabel and UI.messages and UI.messages.status and UI.messages.status.ready then
                local readyMsg = UI.messages.status.ready
                items.GenStatusLabel.Text = readyMsg[langKey] or readyMsg.cn or readyMsg.en or tr("Ready", langKey)
            end
        end

        if UI.google_config_win and UI.google_config_win.GetItems then
            local gitems = UI.google_config_win:GetItems()
            if gitems then
                UI.google_config_win.WindowTitle = tr("GoogleConfigTitle", langKey)
                apply_text_map(gitems, text_map_google, langKey)
            end
        end

        if UI.seed_config_win and UI.seed_config_win.GetItems then
            local sitems = UI.seed_config_win:GetItems()
            if sitems then
                UI.seed_config_win.WindowTitle = tr("SeedConfigTitle", langKey)
                apply_text_map(sitems, text_map_seed, langKey)
            end
        end

    end

    function UI.apply_language_ui(win, use_en)
        UI.switch_language(use_en and "en" or "cn", win)
    end

    -- 构建主窗口
    function UI.build_main_window()
        return Core.dispatcher:AddWindow({
            ID = "ImageEditWin",
            WindowTitle = string.format("%s %s", Config.SCRIPT_NAME, Config.SCRIPT_VERSION),
            Geometry = {Config.X_CENTER, Config.Y_CENTER, Config.WINDOW_WIDTH, Config.WINDOW_HEIGHT},
            Spacing = 10,
            StyleSheet = "*{font-size:14px;}"
        }, ui.VGroup{
            Spacing = 10,
            Weight = 1,
            ui.TabBar{ID = "MainTabs", Weight = 0},
            ui.Stack{ID = "MainStack", Weight = 1,
                UI.build_image_generate_tab(),
                UI.build_image_editor_tab(),
                UI.build_settings_tab()
            }
        })
    end

    App.UI = UI
end

---
--- 7. 主执行函数 (App:Run)
---
function App:Run()
    local Core = self.Core
    local UI = self.UI
    local Config = self.Config
    local Utils = self.Utils
    local json = require("dkjson")
    local Services = self.Services
    local Resolve = self.Resolve
    local is_google_provider = UI.is_google_provider
    local is_google_pro = UI.is_google_pro
    local get_provider_aspect_id = UI.get_provider_aspect_id
    local set_provider_aspect_id = UI.set_provider_aspect_id
    local get_provider_resolution_id = UI.get_provider_resolution_id
    local set_provider_resolution_id = UI.set_provider_resolution_id
    local resolution_options_by_provider = UI.resolution_options_by_provider
    local resolution_index_by_id = UI.resolution_index_by_id
    local function resolve_google_model(pid, cfg)
        local model = cfg and cfg.model
        if is_google_pro(pid) and (not model or model == "" or model == Config.GOOGLE_DEFAULT_MODEL) then
            model = Config.GOOGLE_PRO_DEFAULT_MODEL
        end
        if not model or model == "" then
            model = Config.GOOGLE_DEFAULT_MODEL
        end
        return model
    end

    local ProviderBase = {}
    ProviderBase.__index = ProviderBase
    function ProviderBase:new(def)
        def = def or {}
        setmetatable(def, self)
        return def
    end

    local Providers = {list = {}, by_id = {}}
    local function register_provider(p)
        table.insert(Providers.list, p)
        Providers.by_id[p.id] = p
    end

    local function make_google_provider(id, label, isPro)
        local provider = ProviderBase:new{
            id = id,
            label = label,
            is_pro = isPro,
            kind = "google"
        }
        function provider:get_config()
            return UI.config.google_gen or UI.config.google or {}
        end
        function provider:get_defaults()
            return Config.DEFAULT_CONFIG.google_gen or Config.DEFAULT_CONFIG.google
        end
        function provider:resolution_options()
            return isPro and UI.resolutionOptionsPro or UI.resolutionOptionsFlash
        end
        function provider:aspect_options()
            return UI.aspectRatioOptions
        end
        function provider:build_generation_request(promptText)
            local cfg = self:get_config()
            local baseUrl = Utils.trim((cfg and cfg.base_url) or "")
            if baseUrl == "" then
                baseUrl = Config.GOOGLE_DEFAULT_BASE_URL
            end
            local apiKey = Utils.trim((cfg and cfg.api_key) or "")
            if baseUrl == "" or apiKey == "" then
                if UI.google_config_win then UI.google_config_win:Show() end
                return nil, "needGoogleConfig"
            end
            local modelName = resolve_google_model(self.id, cfg)
            local requestUrl = Utils.buildGoogleEndpoint(baseUrl, modelName)
            if requestUrl == "" then
                return nil, "invalidBaseUrl"
            end
            local defaults = self:get_defaults()
            local aspectId = (cfg and cfg.aspect_ratio) or defaults.aspect_ratio
            local resId = (cfg and cfg.resolution) or defaults.resolution
            local imageConfig = {}
            if aspectId and aspectId ~= "" then
                imageConfig.aspectRatio = aspectId
            end
            if self.is_pro and resId and resId ~= "" then
                imageConfig.imageSize = resId
            end
            local generationConfig = {responseModalities = {"TEXT", "IMAGE"}}
            if next(imageConfig) then
                generationConfig.imageConfig = imageConfig
            end
            local headers = {
                ["x-goog-api-key"] = apiKey,
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json"
            }
            local payload = {
                model = modelName,
                contents = {{
                    role = "user",
                    parts = {
                        {text = promptText}
                    }
                }},
                generationConfig = generationConfig
            }
            return {
                url = requestUrl,
                headers = headers,
                payload = payload,
                aspectId = aspectId,
                resId = resId,
                model = modelName,
                baseUrl = baseUrl
            }
        end
        return provider
    end

    register_provider(make_google_provider("google", "Nano Banana 🍌", false))
    register_provider(make_google_provider("google_pro", "Nano Banana Pro 🍌", true))

    UI.generateProviderOptions = {}
    for _, p in ipairs(Providers.list) do
        if p.id == "google" or p.id == "google_pro" then
            table.insert(UI.generateProviderOptions, {id = p.id, label = p.label})
        end
    end

    local function gen_provider_index_by_id(pid)
        for idx, opt in ipairs(UI.generateProviderOptions) do
            if opt.id == pid then
                return idx
            end
        end
        return 1
    end

    local function gen_provider_label_by_id(pid)
        local idx = gen_provider_index_by_id(pid)
        local opt = UI.generateProviderOptions[idx]
        return opt and opt.label or UI.generateProviderOptions[1].label
    end

    local TAB_INDEX_GENERATE = 0
    local TAB_INDEX_EDIT = 1
    local TAB_INDEX_SETTINGS = 2

    -- 构建主窗口
    UI.MainWin = UI.build_main_window()
    if not UI.MainWin then
        print(string.format("%s: 无法创建主窗口.", Config.SCRIPT_NAME))
        return
    end

    -- 获取 UI 元素
    local items = UI.MainWin:GetItems()
    UI.Items = items

    -- 创建服务商配置窗口
    UI.google_config_win = UI.create_google_config_window(Core, Config)
    UI.seed_config_win = UI.create_seed_config_window(Core, Config)

    local function current_google_config(_)
        return UI.config.google or {}
    end

    local function get_current_aspect_id(pid)
        return (UI.get_provider_aspect_id or get_provider_aspect_id)(pid or (UI.config.provider_choice or "google"))
    end

    local function get_current_resolution_id(pid)
        return (UI.get_provider_resolution_id or get_provider_resolution_id)(pid or (UI.config.provider_choice or "google"))
    end

    local function refresh_provider_combo()
        if not items.ProviderCombo then
            return
        end
        if items.ProviderCombo.Clear then
            items.ProviderCombo:Clear()
        end
        for _, opt in ipairs(UI.providerOptions) do
            if items.ProviderCombo.AddItem then
                items.ProviderCombo:AddItem(opt.label)
            end
        end
        local idx = (UI._provider_index_by_id or provider_index_by_id)(UI.config.provider_choice or "google")
        if items.ProviderCombo.CurrentIndex ~= nil then
            items.ProviderCombo.CurrentIndex = idx - 1
        end
    end
    local function refresh_aspect_ratio_combo(providerId)
        if not items.AspectRatioCombo then
            return
        end
        if items.AspectRatioCombo.Clear then
            items.AspectRatioCombo:Clear()
        end
        for _, opt in ipairs(UI.aspectRatioOptions) do
            if items.AspectRatioCombo.AddItem then
                items.AspectRatioCombo:AddItem(opt.label)
            end
        end
        local pid = providerId or (UI.config.provider_choice or "google")
        local currentId = get_current_aspect_id(pid) or UI.aspectRatioOptions[1].id
        local idx = (UI._aspect_ratio_index_by_id or aspect_ratio_index_by_id)(currentId)
        if items.AspectRatioCombo.CurrentIndex ~= nil then
            items.AspectRatioCombo.CurrentIndex = idx - 1
        end
    end

    local function refresh_resolution_combo(providerId)
        if not items.ResolutionCombo then
            return
        end
        local pid = providerId or (UI.config.provider_choice or "google")
        local opts = (UI.resolution_options_by_provider or resolution_options_by_provider)(pid)
        if items.ResolutionCombo.Clear then
            items.ResolutionCombo:Clear()
        end
        for _, opt in ipairs(opts) do
            if items.ResolutionCombo.AddItem then
                items.ResolutionCombo:AddItem(opt.label)
            end
        end
        local resId = get_current_resolution_id(pid)
        local idx = (UI.resolution_index_by_id or resolution_index_by_id)(pid, resId)
        if items.ResolutionCombo.CurrentIndex ~= nil then
            items.ResolutionCombo.CurrentIndex = idx - 1
        end
        local enabled = is_google_provider(pid)
        items.ResolutionCombo.Enabled = enabled
        if items.ResolutionLabel then
            items.ResolutionLabel.Enabled = enabled
        end
    end

    local function refresh_gen_provider_combo()
        if not items.GenProviderCombo then
            return
        end
        local optsList = UI.generateProviderOptions or {}
        if #optsList == 0 then
            return
        end
        if items.GenProviderCombo.Clear then
            items.GenProviderCombo:Clear()
        end
        for _, opt in ipairs(optsList) do
            if items.GenProviderCombo.AddItem then
                items.GenProviderCombo:AddItem(opt.label)
            end
        end
        local idx = gen_provider_index_by_id(UI.config.generator_provider_choice or "google")
        if idx > #optsList then
            idx = 1
            UI.config.generator_provider_choice = optsList[1].id
            Utils.saveConfig(UI.config)
        end
        if items.GenProviderCombo.CurrentIndex ~= nil then
            items.GenProviderCombo.CurrentIndex = idx - 1
        end
    end

    local function refresh_gen_aspect_ratio_combo(providerId)
        if not items.GenAspectRatioCombo then
            return
        end
        if items.GenAspectRatioCombo.Clear then
            items.GenAspectRatioCombo:Clear()
        end
        for _, opt in ipairs(UI.aspectRatioOptions) do
            if items.GenAspectRatioCombo.AddItem then
                items.GenAspectRatioCombo:AddItem(opt.label)
            end
        end
        local pid = providerId or (UI.config.generator_provider_choice or "google")
        local currentId = (UI.get_generator_aspect_id or get_provider_aspect_id)(pid) or UI.aspectRatioOptions[1].id
        local idx = (UI._aspect_ratio_index_by_id or aspect_ratio_index_by_id)(currentId)
        if items.GenAspectRatioCombo.CurrentIndex ~= nil then
            items.GenAspectRatioCombo.CurrentIndex = idx - 1
        end
    end

    local function refresh_gen_resolution_combo(providerId)
        if not items.GenResolutionCombo then
            return
        end
        local pid = providerId or (UI.config.generator_provider_choice or "google")
        local opts = (UI.resolution_options_by_provider or resolution_options_by_provider)(pid)
        if items.GenResolutionCombo.Clear then
            items.GenResolutionCombo:Clear()
        end
        for _, opt in ipairs(opts) do
            if items.GenResolutionCombo.AddItem then
                items.GenResolutionCombo:AddItem(opt.label)
            end
        end
        local resId = (UI.get_generator_resolution_id or get_provider_resolution_id)(pid)
        local idx = (UI.resolution_index_by_id or resolution_index_by_id)(pid, resId)
        if items.GenResolutionCombo.CurrentIndex ~= nil then
            items.GenResolutionCombo.CurrentIndex = idx - 1
        end
        local enabled = is_google_provider(pid)
        items.GenResolutionCombo.Enabled = enabled
        if items.GenResolutionLabel then
            items.GenResolutionLabel.Enabled = enabled
        end
    end

    refresh_provider_combo()
    refresh_aspect_ratio_combo(UI.config.provider_choice)
    refresh_resolution_combo(UI.config.provider_choice)
    refresh_gen_provider_combo()
    refresh_gen_aspect_ratio_combo(UI.config.generator_provider_choice)
    refresh_gen_resolution_combo(UI.config.generator_provider_choice)

    -- 填充 Tab
    for _, tab_name in ipairs(UI.translations[UI.currentLang].Tabs) do
        items.MainTabs:AddTab(tab_name)
    end

    if items.MainStack then
        items.MainTabs.CurrentIndex = 0
        items.MainStack.CurrentIndex = 0
    end

    -- 设置事件处理程序
    if UI.MainWin and UI.MainWin.On then
        -- Tab 切换
        UI.MainWin.On.MainTabs.CurrentChanged = function(ev)
            local idx = (ev and (ev.Index or ev.index)) or 0
            if items.MainStack then
                items.MainStack.CurrentIndex = idx
            end
            if idx == TAB_INDEX_EDIT then
                if UI.generatedImagePath and UI.generatedImagePath ~= "" then
                    UI.currentImagePath = UI.generatedImagePath
                    if items.OriginalImagePreview then
                        items.OriginalImagePreview.Icon = Core.ui.Icon{File = UI.generatedImagePath}
                        items.OriginalImagePreview.IconSize = {256, 256}
                    end
                end
            end
        end

        local function get_message(section, key)
            local bucket = UI.messages and UI.messages[section]
            if bucket then
                return bucket[key]
            end
            return nil
        end

        local function localizedText(textOrMap)
            if type(textOrMap) == "table" then
                local lang = (UI.currentLang == "en") and "en" or "cn"
                return textOrMap[lang] or textOrMap.cn or textOrMap.en or ""
            end
            return tostring(textOrMap or "")
        end

        local function updateStatus(message)
            local final = localizedText(message)
            if items.StatusLabel then
                items.StatusLabel.Text = final
            end
            if items.GenStatusLabel then
                items.GenStatusLabel.Text = final
            end
            print("[STATUS] " .. final)
        end
        UI.updateStatus = updateStatus

        local function show_update_dialog(text)
            local title = (UI.currentLang == "en") and "Update" or "更新提示"
            local win = Core.dispatcher:AddWindow({
                ID = "UpdateNoticeWin",
                WindowTitle = title,
                Geometry = {Config.LOADING_X_CENTER, Config.LOADING_Y_CENTER, Config.LOADING_WINDOW_WIDTH, Config.LOADING_WINDOW_HEIGHT},
                StyleSheet = "* { font-size: 14px; }",
                Hidden = false
            }, ui.VGroup{
                Spacing = 8,
                ui.Label{
                    ID = "UpdateNoticeTitle",
                    Text = title,
                    Alignment = {AlignHCenter = true},
                    Weight = 0
                },
                ui.TextEdit{
                    ID = "UpdateNoticeText",
                    Text = text or "",
                    ReadOnly = true,
                    Weight = 1
                },
                ui.Button{
                    ID = "UpdateNoticeClose",
                    Text = (UI.currentLang == "en") and "Close" or "关闭",
                    Weight = 0
                }
            })
            if win and win.On then
                win.On.UpdateNoticeClose.Clicked = function()
                    win:Hide()
                end
            end
            if win then win:Show() end
        end

        local function run_update_check_on_start()
            local info, reason
            local ok, res = pcall(function()
                return UI.run_with_loading(function()
                    local payload, why = App.Update and App.Update:check_for_updates()
                    return {info = payload, reason = why}
                end)
            end)
            if ok and type(res) == "table" then
                info = res.info
                reason = res.reason
            else
                info = nil
                reason = "failed"
            end
            if not info then
                return
            end
            local msg = {cn = info.cn or info.en, en = info.en or info.cn}
            if UI.updateStatus then
                UI.updateStatus(msg)
            end
            show_update_dialog(localizedText(msg))
        end
        UI.run_update_check_on_start = run_update_check_on_start


        local function provider_error(key)
            return get_message("error", key) or get_message("status", "requestFailed")
        end

        -- 公共：在长响应中定位 base64 片段并用系统命令直接解码到文件
        local function locate_b64_segment(responseBody)
            if type(responseBody) ~= "string" or #responseBody < 100 then
                return nil, "too_short"
            end
            local b64Start, b64End = nil, nil
            local ext = "png"
            local _, keyEnd = responseBody:find('"data"%s*:%s*"')
            if not keyEnd then _, keyEnd = responseBody:find('"bytes"%s*:%s*"') end
            if not keyEnd then _, keyEnd = responseBody:find('"b64_json"%s*:%s*"') end
            if keyEnd then
                local valStart = keyEnd + 1
                local valEnd = responseBody:find('"', valStart)
                if not valEnd then
                    return nil, "truncated"
                end
                b64Start, b64End = valStart, valEnd - 1
                local contextStr = responseBody:sub(math.max(1, keyEnd - 300), keyEnd)
                if contextStr:find("image/jpeg") then ext = "jpg" end
                if contextStr:find("image/webp") then ext = "webp" end
            else
                return nil, "not_found"
            end
            return {start_idx = b64Start, end_idx = b64End, ext = ext}
        end

        local function decode_b64_segment_to_file(responseBody, segment, saveDir, prefix)
            if not segment or not segment.start_idx or not segment.end_idx then
                return nil, "invalid_segment"
            end
            local filename = string.format("%s%d_%04d.%s", prefix or "image_", os.time(), math.random(0, 9999), segment.ext or "png")
            local destPath = Utils.joinPath(saveDir, filename)

            local tempB64Path, tmperr = Utils.makeTempPath("b64")
            if not tempB64Path then
                return nil, "tmp_b64_failed:" .. tostring(tmperr)
            end
            local f = io.open(tempB64Path, "wb")
            if not f then
                return nil, "tmp_b64_open_failed"
            end
            f:write(responseBody:sub(segment.start_idx, segment.end_idx))
            f:close()

            local decodeCmd
            if Utils.IS_WINDOWS then
                decodeCmd = string.format('certutil -f -decode "%s" "%s" >nul 2>nul', tempB64Path, destPath)
            else
                decodeCmd = string.format('base64 -d -i "%s" -o "%s"', tempB64Path, destPath)
            end

            local runOk = Utils.runShellCommand(decodeCmd)
            os.remove(tempB64Path)

            if not runOk or not Utils.fileExists(destPath) or Utils.getFileSize(destPath) < 100 then
                if Utils.fileExists(destPath) then os.remove(destPath) end
                return nil, "decode_failed"
            end
            return destPath, Utils.getFileSize(destPath)
        end

        local function try_zero_copy_save(responseBody, saveDir, prefix)
            local segment, reason = locate_b64_segment(responseBody)
            if not segment then
                return nil, reason
            end
            local destPath, res = decode_b64_segment_to_file(responseBody, segment, saveDir, prefix)
            if not destPath then
                return nil, res
            end
            return destPath, res
        end

        local function resolve_save_dir()
            local saveDir = ""
            if items.SavePathEdit then
                saveDir = Utils.trim(items.SavePathEdit.Text or "")
            end
            if saveDir == "" then
                saveDir = Utils.trim(UI.config.savePath or "")
            end
            if saveDir == "" then
                return nil, get_message("status", "needSavePath")
            end
            if not Utils.ensureDir(saveDir) then
                return nil, get_message("status", "savePathInvalid")
            end
            if saveDir ~= (UI.config.savePath or "") then
                UI.config.savePath = saveDir
                Utils.saveConfig(UI.config)
            end
            if items.SavePathEdit and Utils.trim(items.SavePathEdit.Text or "") ~= saveDir then
                items.SavePathEdit.Text = saveDir
            end
            return saveDir
        end

        UI.MainWin.On.ProviderCombo.CurrentIndexChanged = function(ev)
            if not items.ProviderCombo then return end
            local idx = (ev and (ev.Index or ev.index)) or items.ProviderCombo.CurrentIndex or 0
            local opt = UI.providerOptions[idx + 1]
            if not opt then return end
            if UI.config.provider_choice ~= opt.id then
                UI.config.provider_choice = opt.id
                Utils.saveConfig(UI.config)
            end
            refresh_aspect_ratio_combo(opt.id)
            refresh_resolution_combo(opt.id)
        end

        UI.MainWin.On.AspectRatioCombo.CurrentIndexChanged = function(ev)
            if not items.AspectRatioCombo then return end
            local idx = (ev and (ev.Index or ev.index)) or items.AspectRatioCombo.CurrentIndex or 0
            local opt = UI.aspectRatioOptions[idx + 1]
            if not opt then return end
            local providerChoice = UI.config.provider_choice or "google"
            local currentId = get_provider_aspect_id(providerChoice)
            if currentId ~= opt.id then
                set_provider_aspect_id(providerChoice, opt.id)
                Utils.saveConfig(UI.config)
            end
        end

        UI.MainWin.On.ResolutionCombo.CurrentIndexChanged = function(ev)
            if not items.ResolutionCombo then return end
            local providerChoice = UI.config.provider_choice or "google"
            if not is_google_provider(providerChoice) then return end
            local idx = (ev and (ev.Index or ev.index)) or items.ResolutionCombo.CurrentIndex or 0
            local opts = resolution_options_by_provider(providerChoice)
            local opt = opts[idx + 1]
            if not opt then return end
            local currentId = get_provider_resolution_id(providerChoice)
            if currentId ~= opt.id then
                set_provider_resolution_id(providerChoice, opt.id)
                Utils.saveConfig(UI.config)
            end
        end

        UI.MainWin.On.GenProviderCombo.CurrentIndexChanged = function(ev)
            if not items.GenProviderCombo then return end
            local idx = (ev and (ev.Index or ev.index)) or items.GenProviderCombo.CurrentIndex or 0
            local opt = UI.generateProviderOptions[idx + 1]
            if not opt then return end
            if UI.config.generator_provider_choice ~= opt.id then
                UI.config.generator_provider_choice = opt.id
                Utils.saveConfig(UI.config)
            end
            refresh_gen_aspect_ratio_combo(opt.id)
            refresh_gen_resolution_combo(opt.id)
        end

        UI.MainWin.On.GenAspectRatioCombo.CurrentIndexChanged = function(ev)
            if not items.GenAspectRatioCombo then return end
            local idx = (ev and (ev.Index or ev.index)) or items.GenAspectRatioCombo.CurrentIndex or 0
            local opt = UI.aspectRatioOptions[idx + 1]
            if not opt then return end
            local providerChoice = UI.config.generator_provider_choice or "google"
            local currentId = (UI.get_generator_aspect_id or get_provider_aspect_id)(providerChoice)
            if currentId ~= opt.id then
                (UI.set_generator_aspect_id or set_provider_aspect_id)(providerChoice, opt.id)
                Utils.saveConfig(UI.config)
            end
        end

        UI.MainWin.On.GenResolutionCombo.CurrentIndexChanged = function(ev)
            if not items.GenResolutionCombo then return end
            local providerChoice = UI.config.generator_provider_choice or "google"
            if not is_google_provider(providerChoice) then return end
            local idx = (ev and (ev.Index or ev.index)) or items.GenResolutionCombo.CurrentIndex or 0
            local opts = resolution_options_by_provider(providerChoice)
            local opt = opts[idx + 1]
            if not opt then return end
            local currentId = (UI.get_generator_resolution_id or get_provider_resolution_id)(providerChoice)
            if currentId ~= opt.id then
                (UI.set_generator_resolution_id or set_provider_resolution_id)(providerChoice, opt.id)
                Utils.saveConfig(UI.config)
            end
        end

        local function extractImageSource(content)
            local function accept_candidate(candidate)
                if type(candidate) ~= "string" then return nil end
                if candidate:find("^data:image/") then
                    return candidate
                end
                if candidate:match("^https?://") then
                    return candidate
                end
                return nil
            end
            if not content then return nil end
            if type(content) == "string" then
                local data = Utils.findDataUrlInText(content)
                if data then return data end
                return Utils.findHttpImageInText(content)
            elseif type(content) == "table" then
                local inlineData = content.inline_data or content.inlineData
                if inlineData and type(inlineData.data) == "string" and inlineData.data ~= "" then
                    local mime = inlineData.mime_type or inlineData.mimeType or content.mime_type or content.mimeType or "image/png"
                    return string.format("data:%s;base64,%s", mime, inlineData.data)
                end
                if content.data and type(content.data) == "string" and (content.mime_type or content.mimeType) then
                    local mime = content.mime_type or content.mimeType or "image/png"
                    return string.format("data:%s;base64,%s", mime, content.data)
                end
                if content.image_url then
                    local candidate = content.image_url.url or content.image_url
                    local picked = accept_candidate(candidate)
                    if picked then return picked end
                end
                if content.url and type(content.url) == "string" and content.url:find("data:image/") then
                    return content.url
                end
                if content.type == "text" and content.text then
                    local found = Utils.findDataUrlInText(content.text)
                    if found then return found end
                    local http = Utils.findHttpImageInText(content.text)
                    if http then return http end
                end
                if content.type == "image_url" and content.image_url then
                    local candidate = content.image_url.url or content.image_url
                    local picked = accept_candidate(candidate)
                    if picked then return picked end
                end
                if content.content then
                    local nested = extractImageSource(content.content)
                    if nested then return nested end
                end
                for _, part in ipairs(content) do
                    local nested = extractImageSource(part)
                    if nested then return nested end
                end
            end
            return nil
        end

        -- ============================================================
        -- [优化版] 图片提取函数
        -- 功能：支持从原始字符串直接提取大文件，避免 JSON 解析崩溃
        -- ============================================================
        local function pick_google_image(parsed, rawBody, opts)
            local skip_raw_scan = opts and opts.skip_raw_scan

            -----------------------------------------------------------
            -- 1. 快速通道：字符串正则提取 (针对大文件优化)
            -----------------------------------------------------------
            if not skip_raw_scan and type(rawBody) == "string" and #rawBody > 1024 then
                -- A. 尝试提取 Base64 (Google 格式: "data": "...")
                -- 使用非贪婪匹配查找 "data" 字段后的内容
                local b64 = rawBody:match('"data"%s*:%s*"([^"]+)"')
                
                -- 如果没找到，尝试找 "b64_json" (某些 OpenAI 兼容接口)
                if not b64 then
                    b64 = rawBody:match('"b64_json"%s*:%s*"([^"]+)"')
                end

                if b64 then
                    -- 简单的有效性检查：Base64 图片通常很长
                    if #b64 > 2000 then
                        -- 尝试从文本中顺便提取 mime_type，如果找不到默认为 png
                        local mime = rawBody:match('"mime_?type"%s*:%s*"([^"]+)"') or "image/png"
                        -- 直接返回拼接好的 Data URL，跳过繁琐的 Table 解析
                        return string.format("data:%s;base64,%s", mime, b64), nil
                    end
                end

                -- B. 尝试提取 URL (SeedDream/Midjourney 格式: "url": "http...")
                local url = rawBody:match('"url"%s*:%s*"([^"]+)"')
                if url then
                    -- 简单的清理和校验
                    url = url:gsub("\\/", "/") -- 处理转义斜杠
                    if url:match("^http") then
                        return url, nil
                    end
                end
            end

            -----------------------------------------------------------
            -- 2. 标准通道：Table 结构遍历 (保持原有的兼容性逻辑)
            -----------------------------------------------------------
            
            -- 定义内部递归提取函数
            local function extractImageSource(content)
                local function accept_candidate(candidate)
                    if type(candidate) ~= "string" then return nil end
                    if candidate:find("^data:image/") then return candidate end
                    if candidate:match("^https?://") then return candidate end
                    return nil
                end

                if not content then return nil end

                if type(content) == "string" then
                    -- 尝试从文本中找 Data URL
                    local data = Utils.findDataUrlInText(content)
                    if data then return data end
                    -- 尝试从文本中找 HTTP URL
                    return Utils.findHttpImageInText(content)
                elseif type(content) == "table" then
                    -- 检查 inline_data (Google Gemini 原生格式)
                    local inlineData = content.inline_data or content.inlineData
                    if inlineData and type(inlineData.data) == "string" and inlineData.data ~= "" then
                        local mime = inlineData.mime_type or inlineData.mimeType or content.mime_type or content.mimeType or "image/png"
                        return string.format("data:%s;base64,%s", mime, inlineData.data)
                    end
                    
                    -- 检查直接的 data 字段
                    if content.data and type(content.data) == "string" and (content.mime_type or content.mimeType) then
                        local mime = content.mime_type or content.mimeType or "image/png"
                        return string.format("data:%s;base64,%s", mime, content.data)
                    end

                    -- 检查 image_url (OpenAI 格式)
                    if content.image_url then
                        local candidate = content.image_url.url or content.image_url
                        local picked = accept_candidate(candidate)
                        if picked then return picked end
                    end
                    
                    -- 递归查找 parts 或 content 数组
                    if content.parts then
                        for _, part in ipairs(content.parts) do
                            local nested = extractImageSource(part)
                            if nested then return nested end
                        end
                    end
                    if content.content then -- 某些情况下 content 也是数组或对象
                         local nested = extractImageSource(content.content)
                         if nested then return nested end
                    end
                end
                return nil
            end

            -- 如果 parsed 为空（可能因为 JSON 解析失败），则直接返回 nil
            if type(parsed) ~= "table" then
                return nil, nil
            end

            -- 提取第一条消息作为 fallback 提示信息
            local firstMessage = nil
            if type(parsed.choices) == "table" and parsed.choices[1] then
                firstMessage = parsed.choices[1].message
            elseif type(parsed.candidates) == "table" and parsed.candidates[1] then
                firstMessage = parsed.candidates[1].content or parsed.candidates[1].message
            end

            -- 遍历 Candidates (Google 风格)
            if type(parsed.candidates) == "table" then
                for _, cand in ipairs(parsed.candidates) do
                    local msg = cand.content or cand.message
                    if msg then
                        local img = extractImageSource(msg)
                        if img then return img, msg end
                    end
                end
            end

            -- 遍历 Choices (OpenAI 风格)
            if type(parsed.choices) == "table" then
                for _, choice in ipairs(parsed.choices) do
                    local msg = choice.message
                    if msg then
                        local img = extractImageSource(msg.content or msg)
                        if img then return img, msg end
                    end
                    -- 有些接口把 content 直接放在 choice 根目录下
                    if choice.content then
                        local img = extractImageSource(choice.content)
                        if img then return img, msg or firstMessage end
                    end
                end
            end

            -- 遍历 Data 数组 (SeedDream/Midjourney 风格)
            if type(parsed.data) == "table" then
                for _, item in ipairs(parsed.data) do
                    local img = extractImageSource(item)
                    if img then return img, firstMessage end
                    if item and item.url then
                        local alt = extractImageSource(item.url)
                        if alt then return alt, firstMessage end
                    end
                    -- 这里的 b64_json 是为了防止上面正则没匹配到的漏网之鱼
                    if item and item.b64_json then
                         return "data:image/png;base64," .. item.b64_json, firstMessage
                    end
                end
            end

            -- 最后尝试：如果 rawBody 很短没走快速通道，但里面可能有隐藏的 url
            if type(rawBody) == "string" then
                local inline = extractImageSource(rawBody)
                if inline then return inline, firstMessage end
            end

            return nil, firstMessage
        end

        -- Google 配置按钮
        UI.MainWin.On.GoogleConfigBtn.Clicked = function()
            if not UI.google_config_win then return end
            UI.switch_language(UI.currentLang)
            local cfgItems = UI.google_config_win:GetItems()
            if cfgItems then
                local function fill(field, val)
                    if not field then return end
                    field.Text = Utils.trim(val or "")
                end
                fill(cfgItems.GoogleBaseURL, UI.config.google.base_url)
                fill(cfgItems.GoogleApiKey, UI.config.google.api_key)
            end
            UI.google_config_win:Show()
        end

        -- Seed Dream 配置按钮
        UI.MainWin.On.SeedConfigBtn.Clicked = function()
            if not UI.seed_config_win then return end
            UI.switch_language(UI.currentLang)
            local cfgItems = UI.seed_config_win:GetItems()
            if cfgItems then
                local function fill(field, val)
                    if not field then return end
                    field.Text = Utils.trim(val or "")
                end
                fill(cfgItems.SeedBaseURL, UI.config.seeddream.base_url)
                fill(cfgItems.SeedApiKey, UI.config.seeddream.api_key)
            end
            UI.seed_config_win:Show()
        end


        -- 赞赏按钮
        if UI.MainWin.On.DonationButtonEdit then
            UI.MainWin.On.DonationButtonEdit.Clicked = function()
                local SCRIPT_KOFI_URL = "https://ko-fi.com/heiba"
                local SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"
                if UI.currentLang == "cn" then
                    Utils.openExternalUrl(SCRIPT_TAOBAO_URL)
                else
                    Utils.openExternalUrl(SCRIPT_KOFI_URL)
                end
            end
        end
        if UI.MainWin.On.DonationButtonGen then
            UI.MainWin.On.DonationButtonGen.Clicked = UI.MainWin.On.DonationButtonEdit.Clicked
        end
        if UI.MainWin.On.DonationButtonSettings then
            UI.MainWin.On.DonationButtonSettings.Clicked = UI.MainWin.On.DonationButtonEdit.Clicked
        end

        -- 浏览按钮 - 选择保存路径
        UI.MainWin.On.BrowseBtn.Clicked = function()
            pcall(function()
                local current_path = items.SavePathEdit.Text or ""
                -- 使用 DaVinci API 选择目录
                local selected_path = Core.fusion:RequestDir(current_path ~= "" and current_path or nil)
                if selected_path and selected_path ~= "" then
                    items.SavePathEdit.Text = selected_path
                    UI.config.savePath = selected_path
                    Utils.saveConfig(UI.config)
                end
            end)
        end

        -- 语言切换 - 简体中文
        if items.LangCnCheckBox then
            UI.MainWin.On.LangCnCheckBox.Clicked = function()
                if items.LangEnCheckBox then
                    items.LangEnCheckBox.Checked = false
                end
                UI.config.currentLang = "cn"
                Utils.saveConfig(UI.config)
                UI.apply_language_ui(UI.MainWin, false)
                if UI.updateStatus then
                    UI.updateStatus(UI.messages.status.ready)
                end
            end
        end

        -- 语言切换 - English
        if items.LangEnCheckBox then
            UI.MainWin.On.LangEnCheckBox.Clicked = function()
                if items.LangCnCheckBox then
                    items.LangCnCheckBox.Checked = false
                end
                UI.config.currentLang = "en"
                Utils.saveConfig(UI.config)
                UI.apply_language_ui(UI.MainWin, true)
                if UI.updateStatus then
                    UI.updateStatus(UI.messages.status.ready)
                end
            end
        end

        -- 存储当前图片路径
        UI.currentImagePath = nil
        UI.editedImagePath = nil
        UI.generatedImagePath = nil

        -- 图片上传
        UI.MainWin.On.UploadImageBtn.Clicked = function()
            local filePath = Core.fusion:RequestFile()
            if not filePath or filePath == "" then
                print("未选择文件")
                return
            end

            -- 验证文件
            local ext = filePath:lower():match("%.([^%.]+)$")
            if not ext or (ext ~= "png" and ext ~= "jpg" and ext ~= "jpeg") then
                print("仅支持 PNG/JPG 格式")
                return
            end

            local preparedPath, prepErr = Utils.preparePreviewImage(filePath, {copy_to_temp = not Utils.IS_WINDOWS})
            if not preparedPath then
                print("Failed to prepare image: " .. tostring(prepErr))
                return
            end

            UI.currentImagePath = preparedPath
            if items.OriginalImagePreview then
                items.OriginalImagePreview.Icon = Core.ui.Icon{File = preparedPath}
                items.OriginalImagePreview.IconSize = {256, 256}
            end
            print("Image loaded: " .. preparedPath)
        end

        -- 从时间线提取
        UI.MainWin.On.FromTimelineBtn.Clicked = function()
            -- 参考 I2V .lua 中的 capture_current_frame 实现
            local tempPath, err = Resolve.export_current_frame("from_timeline")
            if not tempPath then
                print("Failed to export frame: " .. tostring(err))
                return
            end
            local processed, prepErr = Utils.preparePreviewImage(tempPath, {copy_to_temp = true, cleanup_source = true})
            if not processed then
                print("Failed to prepare image: " .. tostring(prepErr))
                UI.currentImagePath = tempPath
            else
                UI.currentImagePath = processed
            end
            if items.OriginalImagePreview then
                items.OriginalImagePreview.Icon = Core.ui.Icon{File = UI.currentImagePath}
                items.OriginalImagePreview.IconSize = {256, 256}
            end
            print("Frame extracted from timeline")
        end

        -- 文生图生成 (GenGenerateBtn) - 零拷贝直写版 (解决大文件截断)
        UI.MainWin.On.GenGenerateBtn.Clicked = function()
            -- 1. 准备保存路径
            local saveDir, saveErr = resolve_save_dir()
            if not saveDir then
                updateStatus(saveErr or get_message("status", "savePathInvalid"))
                return
            end

            updateStatus(get_message("status", "validating"))
            local providerChoice = UI.config.generator_provider_choice or "google"
            local provider = Providers.by_id[providerChoice] or Providers.by_id["google"]

            -- 2. 检查 API Key
            local function ensure_generator_api_key_available()
                local cfg = provider and provider.get_config and provider:get_config() or (UI.config.google or {})
                local apiKey = Utils.trim(cfg.api_key or "")
                if apiKey == "" then
                    if UI.google_config_win then UI.google_config_win:Show() end
                    updateStatus(provider_error("needGoogleConfig"))
                    return false
                end
                return true
            end

            if not ensure_generator_api_key_available() then
                return
            end

            -- 3. 获取提示词
            local promptField = items.GenPromptTextEdit
            local prompt = ""
            if promptField then
                prompt = Utils.trim(promptField.PlainText or promptField.Text or "")
            end
            if prompt == "" then
                updateStatus(get_message("status", "needPrompt"))
                return
            end

            -- 4. 构建请求
            local request, errMsg = provider:build_generation_request(prompt)
            if not request then
                updateStatus(errMsg and provider_error(errMsg) or get_message("status", "requestFailed"))
                return
            end

            Utils.debugSection("TEXT2IMAGE PARAMS")
            Utils.debugKV("Prompt", Utils.truncate(prompt, 160))
            Utils.debugKV("Model", request.model)
            Utils.debugSectionEnd()

            updateStatus(get_message("status", "generating"))
            
            -- 5. 发起网络请求
            -- 注意：对于超大文件，我们尽量让 httpPostJson 只要下载了东西就返回 true
            local ok, responseBody, statusCode, debugPaths = Utils.httpPostJson(request.url, request.payload, request.headers, 600)
            
            -- [容错] 只要 body 有长度就尝试处理
            if (not responseBody or #responseBody < 100) then
                local errHint = statusCode and string.format("status=%s", tostring(statusCode)) or string.format("reason=%s", tostring(responseBody or "unknown"))
                print(string.format("[ERROR] [Google] HTTP 下载严重失败 (%s)", errHint))
                updateStatus(get_message("status", "requestFailed"))
                return
            end
            if statusCode and (statusCode < 200 or statusCode >= 300) then
                print(string.format("[ERROR] [Google] HTTP 状态异常 status=%s", tostring(statusCode)))
                updateStatus(get_message("status", "requestFailed"))
                return
            end

            -- 6. 核心提取逻辑 (零拷贝系统解码)
            local directPath, directRes = try_zero_copy_save(responseBody, saveDir, "image_gen_")
            if not directPath then
                if directRes == "truncated" then
                    print("[ERROR] Data Truncated! Found start of image but NO ending quote.")
                updateStatus(get_message("status", "downloadInterrupted"))
                    return
                end

                print("[Info] No large image data found, trying to parse error message...")
                local decodeOk, parsed = pcall(json.decode, responseBody)
                if decodeOk and type(parsed) == "table" and parsed.error then
                     local errMsg = parsed.error.message or "unknown"
                     print("[ERROR] Google API Error: " .. tostring(errMsg))
                end
                updateStatus(provider_error("responseNoImage"))
                return
            end

            updateStatus(get_message("status", "saving"))
            local savedPath = directPath
            local savedSize = tonumber(directRes) or Utils.getFileSize(savedPath)

            -- 请求成功且已落盘，清理调试文件
            Utils.cleanupDebugPaths(debugPaths)

            UI.generatedImagePath = savedPath
            if items.GenImagePreview then
                items.GenImagePreview.Icon = Core.ui.Icon{File = savedPath}
                items.GenImagePreview.IconSize = {256, 256}
            end

            Utils.debugSection("GEN IMAGE SAVE RESULT")
            Utils.debugKV("Saved Path", savedPath)
            Utils.debugKV("Size (bytes)", tostring(savedSize or 0))
            Utils.debugSectionEnd()

            updateStatus(get_message("status", "success"))
            print("[SUCCESS] 图片已保存: " .. savedPath)
        end

        UI.MainWin.On.GenAddToPoolBtn.Clicked = function()
            if not UI.generatedImagePath or UI.generatedImagePath == "" then
                updateStatus(get_message("status", "needImage"))
                return
            end
            local ok, err = Resolve.import_to_media_pool(UI.generatedImagePath, "ImageGenerate")
            if ok then
                updateStatus(get_message("status", "addedToPool"))
            else
                print("Failed to import to media pool: " .. tostring(err))
                updateStatus(get_message("status", "requestFailed"))
            end
        end

        -- 生成图片
        UI.MainWin.On.GenerateBtn.Clicked = function()
            updateStatus(get_message("status", "validating"))
            local saveDir, saveErr = resolve_save_dir()
            if not saveDir then
                updateStatus(saveErr or get_message("status", "savePathInvalid"))
                return
            end

            local googleCfg = UI.config.google or {}
            local seedCfg = UI.config.seeddream or {}
            local providerChoice = UI.config.provider_choice or "google"
            local selectedGoogleCfg = current_google_config(providerChoice)
            local providerLabel = (UI._provider_label_by_id or provider_label_by_id)(providerChoice)

            local function ensure_api_key_available()
                if providerChoice == "seeddream" then
                    local apiKey = Utils.trim(seedCfg.api_key or "")
                    if apiKey == "" then
                        if UI.seed_config_win then UI.seed_config_win:Show() end
                        updateStatus(provider_error("needSeedConfig"))
                        return false
                    end
                    return true
                end

                local apiKey = Utils.trim((selectedGoogleCfg and selectedGoogleCfg.api_key) or googleCfg.api_key or "")
                if apiKey == "" then
                    if UI.google_config_win then UI.google_config_win:Show() end
                    updateStatus(provider_error("needGoogleConfig"))
                    return false
                end
                return true
            end

            if not ensure_api_key_available() then
                return
            end

            if not UI.currentImagePath or UI.currentImagePath == "" then
                updateStatus(get_message("status", "needImage"))
                return
            end

            local promptField = items.PromptTextEdit
            local prompt = ""
            if promptField then
                prompt = Utils.trim(promptField.PlainText or promptField.Text or "")
            end
            if prompt == "" then
                updateStatus(get_message("status", "needPrompt"))
                return
            end

            local googleBaseUrl = Utils.trim((selectedGoogleCfg and selectedGoogleCfg.base_url) or googleCfg.base_url or "")
            local seedBaseUrl = Utils.trim(seedCfg.base_url or "")
            local googleModel = resolve_google_model(providerChoice, selectedGoogleCfg)
            local seedModel = seedCfg.model or Config.SEED_DEFAULT_MODEL
            local googleDefaults = Config.DEFAULT_CONFIG.google
            local googleAspectId = (selectedGoogleCfg and selectedGoogleCfg.aspect_ratio) or googleDefaults.aspect_ratio
            local googleResolutionId = (selectedGoogleCfg and selectedGoogleCfg.resolution) or googleDefaults.resolution

            local function get_seed_aspect_data()
                local ratioId = (UI.config.seeddream and UI.config.seeddream.aspect_ratio) or Config.DEFAULT_CONFIG.seeddream.aspect_ratio
                return (UI._aspect_ratio_data_by_id or aspect_ratio_data_by_id)(ratioId)
            end
            local seedAspectData = get_seed_aspect_data()

            Utils.debugSection("GENERATE PARAMS")
            Utils.debugKV("Prompt", Utils.truncate(prompt, 160))
            Utils.debugKV("Image Path", UI.currentImagePath or "未设置")
            Utils.debugKV("Save Dir", saveDir)
            Utils.debugKV("Provider", providerLabel)
            if providerChoice == "seeddream" then
                Utils.debugKV("Base URL", seedBaseUrl)
                Utils.debugKV("Model", seedModel)
                Utils.debugKV("API Key", Utils.maskToken(seedCfg.api_key or ""))
                if seedAspectData then
                    Utils.debugKV("Aspect Ratio", string.format("%s (%s)", seedAspectData.id, seedAspectData.size))
                end
            else
                Utils.debugKV("Base URL", googleBaseUrl)
                Utils.debugKV("Request URL", Utils.buildGoogleEndpoint(googleBaseUrl, googleModel))
                Utils.debugKV("Model", googleModel)
                Utils.debugKV("API Key", Utils.maskToken((selectedGoogleCfg and selectedGoogleCfg.api_key) or googleCfg.api_key or ""))
                Utils.debugKV("Aspect Ratio", googleAspectId or "-")
                Utils.debugKV("Resolution", googleResolutionId or "-")
            end
            Utils.debugSectionEnd()

            updateStatus(get_message("status", "preparingImage"))
            local imageDataUrl = Utils.encodeImageToBase64(UI.currentImagePath)
            if not imageDataUrl then
                updateStatus(get_message("status", "readImageFail"))
                return
            end
            Utils.debugSection("IMAGE ENCODED")
            Utils.debugKV("Data URL Length", tostring(#imageDataUrl))
            Utils.debugKV("Preview", Utils.truncate(imageDataUrl, 120))
            Utils.debugSectionEnd()

            local function call_google_provider(promptText, dataUrl, providerId, saveDir)
                local pid = providerId or (UI.config.provider_choice or "google")
                local cfg = current_google_config(pid)
                local baseUrl = Utils.trim((cfg and cfg.base_url) or "")
                if baseUrl == "" then
                    baseUrl = Config.GOOGLE_DEFAULT_BASE_URL
                end
                local apiKey = Utils.trim((cfg and cfg.api_key) or "")
                if baseUrl == "" or apiKey == "" then
                    if UI.google_config_win then UI.google_config_win:Show() end
                    return nil, provider_error("needGoogleConfig")
                end
                local modelName = resolve_google_model(pid, cfg)
                local requestUrl = Utils.buildGoogleEndpoint(baseUrl, modelName)
                if requestUrl == "" then
                    return nil, provider_error("invalidBaseUrl")
                end
                local payloadData = Utils.stripDataUrlPayload(dataUrl)
                if payloadData == "" then
                    return nil, provider_error("encodeFailed")
                end
                
                -- 构建请求参数
                local defaults = Config.DEFAULT_CONFIG.google
                local aspectId = (cfg and cfg.aspect_ratio) or defaults.aspect_ratio
                local resId = (cfg and cfg.resolution) or defaults.resolution
                local imageConfig = {}
                if aspectId and aspectId ~= "" then
                    imageConfig.aspectRatio = aspectId
                end
                if is_google_pro(pid) and resId and resId ~= "" then
                    imageConfig.imageSize = resId
                end
                local generationConfig = {
                    responseModalities = {"TEXT", "IMAGE"}
                }
                if next(imageConfig) then
                    generationConfig.imageConfig = imageConfig
                end
                local headers = {
                    ["x-goog-api-key"] = apiKey,
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json"
                }
                -- [新增] 显式关闭连接，配合 macFlags 防止服务器 RST
                --table.insert(headers, "-H 'Connection: close'") 
                
                local payload = {
                    model = modelName,
                    contents = {{
                        role = "user",
                        parts = {
                            {text = promptText},
                            {inline_data = {mime_type = Utils.getMimeFromDataUrl(dataUrl, "image/png"), data = payloadData}}
                        }
                    }},
                    generationConfig = generationConfig
                }
                
                -- 发起请求
                local success, responseBody, statusCode, debugPaths = Utils.httpPostJson(requestUrl, payload, headers, 600)
                
                -- [关键修复 1] 容忍网络重置错误 (Exit 56)
                -- 只要 responseBody 有足够的内容，就认为是成功的，忽略 curl 的报错
                if not success and (not responseBody or #responseBody < 100) then
                    local errHint = statusCode and string.format("status=%s", tostring(statusCode)) or string.format("reason=%s", tostring(responseBody or "unknown"))
                    print(string.format("[ERROR] [Google] HTTP 调用失败 (%s)", errHint))
                    return nil, provider_error("requestFailed")
                end
                if statusCode and (statusCode < 200 or statusCode >= 300) then
                    print(string.format("[ERROR] [Google] HTTP 状态异常 status=%s", tostring(statusCode)))
                    return nil, provider_error("requestFailed")
                end

                -- 优先尝试零拷贝解码，避免巨大 base64 解析/占内存
                local directPath, directRes = try_zero_copy_save(responseBody, saveDir, "image_edit_")
                if directPath then
                    Utils.cleanupDebugPaths(debugPaths)
                    return directPath, {type = "google", saved_path = directPath, saved_size = tonumber(directRes) or Utils.getFileSize(directPath)}
                elseif directRes == "truncated" then
                    return nil, {cn = "下载中断，请重试", en = "Download interrupted, please retry", debugPaths = debugPaths}
                end

                -- [常规流程] 如果零拷贝失败，才尝试 JSON 解析
                local decodeOk, parsed = pcall(json.decode, responseBody)
                if not decodeOk or type(parsed) ~= "table" then
                    print("[ERROR] JSON 解析失败 (且零拷贝未能解码): " .. tostring(parsed))
                    return nil, provider_error("responseParseFailed"), debugPaths
                end

                if type(parsed.error) == "table" or parsed.error ~= nil then
                    local errMsg = parsed.error
                    if type(errMsg) == "table" then
                        errMsg = errMsg.message or errMsg.code or "unknown_error"
                    end
                    print("[ERROR] Google 响应包含错误字段: " .. tostring(errMsg))
                    return nil, provider_error("requestFailed"), debugPaths
                end

                -- 正常解析 JSON 提取图片
                -- 已经尝试过零拷贝，此处跳过再次扫描原始字符串，直接从解析结构中找
                local imageSource, pickedMessage = pick_google_image(parsed, responseBody, {skip_raw_scan = true})
                if not imageSource then
                    Utils.debugSection("GOOGLE RAW RESPONSE (NO IMAGE)")
                    if type(parsed) == "table" then
                        print(json.encode(parsed, {indent = true}) or "")
                    else
                        print(responseBody or "")
                    end
                    Utils.debugSectionEnd()
                    return nil, provider_error("responseNoImage"), debugPaths
                end
                
                return imageSource, {type = "google", message = pickedMessage, debugPaths = debugPaths}
            end

            local function call_seed_provider(promptText, dataUrl, aspectData)
                local baseUrl = Utils.trim((UI.config.seeddream and UI.config.seeddream.base_url) or "")
                if baseUrl == "" then
                    baseUrl = Config.SEED_DEFAULT_BASE_URL
                end
                local apiKey = Utils.trim((UI.config.seeddream and UI.config.seeddream.api_key) or "")
                if baseUrl == "" or apiKey == "" then
                    if UI.seed_config_win then UI.seed_config_win:Show() end
                    return nil, provider_error("needSeedConfig")
                end
                local imagePayload = Utils.stripDataUrlPayload(dataUrl)
                if imagePayload == "" then
                    return nil, provider_error("encodeFailed")
                end
                local aspectInfo = aspectData or get_seed_aspect_data()
                local sizeText = (aspectInfo and aspectInfo.size) or "2048x2048"
                local payload = {
                    model = (UI.config.seeddream and UI.config.seeddream.model) or Config.SEED_DEFAULT_MODEL,
                    prompt = promptText,
                    image = imagePayload,
                    size = sizeText,
                    sequential_image_generation = "disabled",
                    stream = false,
                    response_format = "url",
                    watermark = true
                }
                local headers = {
                    ["Authorization"] = "Bearer " .. apiKey,
                    ["Content-Type"] = "application/json"
                }
                local success, responseBody, statusCode, debugPaths = Utils.httpPostJson(baseUrl, payload, headers, 600)
                if not success then
                    local errHint = statusCode and string.format("status=%s", tostring(statusCode)) or string.format("reason=%s", tostring(responseBody or "unknown"))
                    print(string.format("[ERROR] [Seed Dream] HTTP 调用失败 (%s)", errHint))
                    return nil, provider_error("requestFailed"), debugPaths
                end
                local decodeOk, parsed = pcall(json.decode, responseBody)
                if not decodeOk or type(parsed) ~= "table" then
                    print("[ERROR] JSON 解析失败: " .. tostring(parsed))
                    return nil, provider_error("responseParseFailed"), debugPaths
                end
                if type(parsed.error) == "table" or parsed.error ~= nil then
                    local errMsg = parsed.error
                    if type(errMsg) == "table" then
                        errMsg = errMsg.message or errMsg.code or "unknown_error"
                    end
                    print("[ERROR] Seed Dream 响应包含错误字段: " .. tostring(errMsg))
                    return nil, provider_error("requestFailed"), debugPaths
                end
                local dataArr = parsed.data
                if type(dataArr) ~= "table" or not dataArr[1] or type(dataArr[1].url) ~= "string" then
                    return nil, provider_error("responseNoImage"), debugPaths
                end
                return dataArr[1].url, {type = "seeddream", data = dataArr[1], count = #dataArr, debugPaths = debugPaths}
            end

            updateStatus(get_message("status", "generating"))
            local imageSource, providerMeta
            if providerChoice == "seeddream" then
                imageSource, providerMeta = call_seed_provider(prompt, imageDataUrl, seedAspectData)
            else
                imageSource, providerMeta = call_google_provider(prompt, imageDataUrl, providerChoice, saveDir)
            end
            if not imageSource then
                updateStatus(providerMeta or get_message("status", "requestFailed"))
                return
            end

            updateStatus(get_message("status", "parsing"))
            Utils.debugSection("API RESPONSE SUMMARY")
            if providerMeta and providerMeta.type == "google" then
                local message = providerMeta.message
                Utils.debugKV("Choice Role", (message and message.role) or "assistant")
                Utils.debugKV("Content Items", type(message and message.content) == "table" and #message.content or 1)
                local function extract_first_text(node)
                    if type(node) == "string" then
                        return node
                    elseif type(node) == "table" then
                        if node.text then
                            return tostring(node.text)
                        end
                        if node.type == "text" and node.text then
                            return tostring(node.text)
                        end
                        if node.parts then
                            for _, part in ipairs(node.parts) do
                                local txt = extract_first_text(part)
                                if txt then return txt end
                            end
                        end
                        if node.content then
                            for _, part in ipairs(node.content) do
                                local txt = extract_first_text(part)
                                if txt then return txt end
                            end
                        end
                        for _, part in ipairs(node) do
                            local txt = extract_first_text(part)
                            if txt then return txt end
                        end
                    end
                    return nil
                end
                local txt = extract_first_text((message and (message.parts or message.content or message)) or nil)
                if txt and txt ~= "" then
                    Utils.debugKV("Text", Utils.truncate(txt, 200))
                end
            elseif providerMeta and providerMeta.type == "seeddream" then
                local info = providerMeta.data or {}
                Utils.debugKV("Image Size", info.size or "-")
                Utils.debugKV("Data Items", tostring(providerMeta.count or 1))
            end
            Utils.debugKV("Image Source Length", tostring(#imageSource))
            Utils.debugKV("Image Source Preview", Utils.truncate(imageSource, 160))
            Utils.debugSectionEnd()

            -- 如果零拷贝已直接落盘，则跳过再次解码
            if providerMeta and providerMeta.saved_path then
                UI.editedImagePath = providerMeta.saved_path
                local savedSize = providerMeta.saved_size or Utils.getFileSize(providerMeta.saved_path)
                if items.EditedImagePreview then
                    items.EditedImagePreview.Icon = Core.ui.Icon{File = providerMeta.saved_path}
                    items.EditedImagePreview.IconSize = {256, 256}
                end
                Utils.debugSection("IMAGE SAVE RESULT")
                Utils.debugKV("Saved Path", providerMeta.saved_path)
                Utils.debugKV("Size (bytes)", tostring(savedSize or 0))
                Utils.debugSectionEnd()
                Utils.cleanupDebugPaths(providerMeta.debugPaths)
                updateStatus(get_message("status", "success"))
                print("[SUCCESS] 图片已保存: " .. providerMeta.saved_path)
                return
            end

            updateStatus(get_message("status", "saving"))
            local savedPath, savedSize
            if imageSource:find("^data:image/") then
                savedPath, savedSize = Utils.saveDataUrlImage(imageSource, saveDir, "image_edit_")
            elseif imageSource:match("^https?://") then
                savedPath, savedSize = Utils.saveImageFromUrl(imageSource, saveDir, "image_edit_")
            else
                savedPath, savedSize = Utils.saveDataUrlImage(imageSource, saveDir, "image_edit_")
            end
            if not savedPath then
                print("[ERROR] 无法保存图片: " .. tostring(savedSize))
                updateStatus(get_message("status", "saveFailed"))
                return
            end
            if providerMeta and providerMeta.debugPaths then
                Utils.cleanupDebugPaths(providerMeta.debugPaths)
            end

            UI.editedImagePath = savedPath
            if items.EditedImagePreview then
                items.EditedImagePreview.Icon = Core.ui.Icon{File = savedPath}
                items.EditedImagePreview.IconSize = {256, 256}
            end

            Utils.debugSection("IMAGE SAVE RESULT")
            Utils.debugKV("Saved Path", savedPath)
            Utils.debugKV("Size (bytes)", tostring(savedSize or 0))
            Utils.debugSectionEnd()

            updateStatus(get_message("status", "success"))
            print("[SUCCESS] 图片已保存: " .. savedPath)
        end

        -- 添加到媒体池（编辑结果）
        UI.MainWin.On.EditAddToPoolBtn.Clicked = function()
            if not UI.editedImagePath or UI.editedImagePath == "" then
                updateStatus(get_message("status", "needImage"))
                return
            end
            local ok, err = Resolve.import_to_media_pool(UI.editedImagePath, "ImageEdit")
            if ok then
                updateStatus(get_message("status", "addedToPool"))
            else
                print("Failed to import to media pool: " .. tostring(err))
                updateStatus(get_message("status", "requestFailed"))
            end
        end

        -- 继续编辑：把编辑结果作为新的原图
        UI.MainWin.On.ContinueEditBtn.Clicked = function()
            if not UI.editedImagePath or UI.editedImagePath == "" then
                updateStatus(get_message("status", "needImage"))
                return
            end
            UI.currentImagePath = UI.editedImagePath
            if items.OriginalImagePreview then
                items.OriginalImagePreview.Icon = Core.ui.Icon{File = UI.currentImagePath}
                items.OriginalImagePreview.IconSize = {256, 256}
            end
            UI.editedImagePath = nil
            if items.EditedImagePreview then
                items.EditedImagePreview.Icon = Core.ui.Icon{}
            end
        end

        -- 主窗口关闭
        UI.MainWin.On.ImageEditWin.Close = function(ev)
            -- 清理临时文件
            if UI.currentImagePath and UI.currentImagePath:find(Utils.getTempDir()) then
                os.remove(UI.currentImagePath)
            end
            if UI.editedImagePath and UI.editedImagePath:find(Utils.getTempDir()) then
                os.remove(UI.editedImagePath)
            end
            local tempRoot = Utils.getTempDir()
            if tempRoot and tempRoot ~= "" then
                local function rmTempDir()
                    if Utils.IS_WINDOWS then
                        Utils.runShellCommand(string.format('rmdir /s /q "%s"', tempRoot))
                    else
                        local escaped = tempRoot:gsub("'", "'\\''")
                        Utils.runShellCommand(string.format("rm -rf '%s'", escaped))
                    end
                end
                pcall(rmTempDir)
            end

            Core.dispatcher:ExitLoop()
        end
    end

    -- 初始化设置值到UI
    if items.SavePathEdit then
        items.SavePathEdit.Text = UI.config.savePath or ""
    end

    -- 初始化语言设置
    if UI.config.currentLang == "en" then
        UI.apply_language_ui(UI.MainWin, true)
        if items.LangEnCheckBox then items.LangEnCheckBox.Checked = true end
        if items.LangCnCheckBox then items.LangCnCheckBox.Checked = false end
    else
        UI.apply_language_ui(UI.MainWin, false)
        if items.LangEnCheckBox then items.LangEnCheckBox.Checked = false end
        if items.LangCnCheckBox then items.LangCnCheckBox.Checked = true end
    end

    if UI.updateStatus and UI.messages and UI.messages.status then
        UI.updateStatus(UI.messages.status.ready)
    end

    -- 启动时检查更新并弹出结果
    if UI.run_update_check_on_start then
        pcall(UI.run_update_check_on_start)
    end

    -- 启动应用
    UI.MainWin:Show()
    Core.dispatcher:RunLoop()
    UI.MainWin:Hide()
end

---
--- 8. 运行
---
App:Run()
