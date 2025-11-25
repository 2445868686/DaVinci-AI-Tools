math.randomseed(os.time())

local json = require("dkjson")
local SEP = package.config:sub(1, 1)
local IS_WINDOWS = (SEP == "\\")
local SCRIPT_KOFI_URL = "https://ko-fi.com/s/5e9dcdeae5"
local SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"
local FREE_VERION = false
local function join_path(base, rel)
    if base == "" then
        return rel
    end
    if base:sub(-1) == SEP then
        return base .. rel
    end
    return base .. SEP .. rel
end

local function detect_script_dir()
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    local pattern = SEP == "\\" and "(.*[\\/])" or "(.*" .. SEP .. ")"
    return source:match(pattern) or "."
end

local SCRIPT_DIR = detect_script_dir()

local App = {}
local httpClient = {}

--
-- 1. 配置模块 (App.Config)
--
do
    local Config = {}

    Config.SCRIPT_NAME    = "DaVinci Batch Render"
    Config.SCRIPT_VERSION = "1.1.1"
    Config.SCRIPT_AUTHOR  = "HEIBA"
    Config.SCRIPT_DIR     = SCRIPT_DIR

    Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT = 1920, 1080
    Config.WINDOW_WIDTH, Config.WINDOW_HEIGHT = 650, 500
    Config.X_CENTER = math.floor((Config.SCREEN_WIDTH - Config.WINDOW_WIDTH) / 2)
    Config.Y_CENTER = math.floor((Config.SCREEN_HEIGHT - Config.WINDOW_HEIGHT) / 2)
    Config.LOADING_WINDOW_WIDTH, Config.LOADING_WINDOW_HEIGHT = 260, 140
    Config.LOADING_X_CENTER = math.floor((Config.SCREEN_WIDTH - Config.LOADING_WINDOW_WIDTH) / 2)
    Config.LOADING_Y_CENTER = math.floor((Config.SCREEN_HEIGHT - Config.LOADING_WINDOW_HEIGHT) / 2)

    Config.MARK_COLOR = "Cyan"
    Config.MARK_TAG = "DaVinciBatchRender"
    Config.DEFAULT_INTERVAL_SECONDS = 30
    Config.DEFAULT_MARK_COUNT = 5
    Config.LOG_MAX_LINES = 400
    Config.CONFIG_DIR = join_path(Config.SCRIPT_DIR, "config")
    Config.SETTINGS_FILE = join_path(Config.CONFIG_DIR, "setting.json")
    Config.TEMP_DIR = join_path(Config.SCRIPT_DIR, "temp")
    Config.SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
    Config.SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"
    Config.SUPABASE_TIMEOUT = 5

    App.Config = Config
end

local SUPABASE_TIMEOUT = App.Config.SUPABASE_TIMEOUT

------------------------------------------------------------------
-- runShellCommand
------------------------------------------------------------------

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

do
    if IS_WINDOWS then
        local ok, ffi = pcall(require, "ffi")
        if ok and ffi then
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


--
-- 1.a 语言模块 (App.Locale)
--
do
    local Locale = {
        current = "en",
        strings = {
            en = {
                app_title = App.Config.SCRIPT_NAME,
                add_mark = "Add",
                interval_label = "Interval (s)",
                count_label = "Count",
                base_name_label = "Filename Prefix",
                get_queue = "Load Queue",
                start_render = "Start Render",
                clear_marks = "Remove",
                target_placeholder = "Select output directory",
                browse = "Browse",
                tree_header_index = "Index",
                tree_header_start = "Start",
                tree_header_end = "End",
                tree_header_name = "Name",
                tree_header_status = "Status",
                language_checkbox = "简体中文",
                lang_cn_label = "简体中文",
                lang_en_label = "English",
                donation_button = "☕ Explore More Features ☕",
                loading_updates = "Checking updates...",
                loading_complete = "Ready.",
                status_pending = "Not queued",
                status_queued = "Queued",
                status_waiting = "Waiting",
                status_rendering = "Rendering",
                status_done = "Completed",
                status_failed = "Failed",
                status_unknown = "Unknown",
                log_active_timeline_missing = "Active timeline not found.",
                log_interval_invalid = "Interval must be greater than 0.",
                log_count_invalid = "Count must be at least 2.",
                log_marker_add_failed = "Failed to add marker at frame %d.",
                log_marker_add_success = "Added %d markers with a %d-frame interval.",
                log_need_duration_marker = "Add at least one marker with duration before building segments.",
                log_marker_duration_missing = "Marker %s at %s has no duration; skipped.",
                log_marker_duration_too_short = "Marker %s at %s has duration 1 frame; Alt-drag the marker to stretch the interval.",
                log_segment_skipped = "Segment %s - %s contains no video and was skipped.",
                log_no_valid_segments = "No valid segments detected. Check marker spacing.",
                log_segments_generated = "Generated %d render segments.",
                log_markers_removed = "Removed %d markers created by the script.",
                log_mark_range_failed = "Failed to set in/out range for %s.",
                log_row_status_pattern = "%s: %s",
                log_render_sequence_finished = "Render sequence finished.",
                log_render_env_failed = "Render environment initialization failed: %s",
                log_render_settings_failed = "Failed to configure render settings for %s.",
                log_add_job_failed = "Failed to add render job: %s.",
                log_job_added = "Added render job %s.",
                log_start_job_failed = "Failed to start job %s.",
                log_attempts = "Attempts: %s",
                log_job_started = "Started rendering job %s.",
                log_project_missing = "Active project not found.",
                log_target_dir_required = "Set an output directory before rendering.",
                log_base_name_required = "Set a filename prefix before rendering.",
                log_no_jobs_available = "No render jobs available.",
                log_jobs_prepared = "Prepared %d render jobs.",
                log_render_in_progress = "Rendering already in progress.",
                log_starting_sequential = "Starting sequential render for %d segments.",
                log_sequential_started = "Sequential render started.",
                log_start_render_failed = "Failed to start rendering.",
                log_job_failed_cancel_rest = "Job %s failed; cancelling remaining tasks.",
                log_render_interrupted_stop = "Rendering interrupted; stopping tasks.",
                log_detected_failure_stop = "Detected render failure; stopped all tasks.",
                log_render_interrupted = "Rendering interrupted.",
                log_window_closed = "Window closed.",
                log_dir_picker_unavailable = "Directory picker is not available in this environment.",
                log_dir_selected = "Selected output directory: %s",
                log_queue_required = "Load the render queue first."
            },
            zh = {
                app_title = "DaVinci 批量渲染",
                add_mark = "添加",
                interval_label = "间隔(秒)",
                count_label = "数量",
                base_name_label = "文件名前缀",
                get_queue = "获取渲染队列",
                start_render = "开始渲染",
                clear_marks = "删除",
                target_placeholder = "请选择输出目录",
                browse = "浏览",
                tree_header_index = "序号",
                tree_header_start = "开始",
                tree_header_end = "结束",
                tree_header_name = "名称",
                tree_header_status = "状态",
                language_checkbox = "简体中文",
                lang_cn_label = "简体中文",
                lang_en_label = "English",
                donation_button = "☕ 探索更多功能 ☕",
                loading_updates = "正在检查更新...",
                loading_complete = "准备就绪",
                status_pending = "等待队列",
                status_queued = "已添加到队列",
                status_waiting = "等待渲染",
                status_rendering = "正在渲染",
                status_done = "渲染完成",
                status_failed = "渲染失败",
                status_unknown = "未知状态",
                log_active_timeline_missing = "未找到当前时间线。",
                log_interval_invalid = "间隔必须大于 0。",
                log_count_invalid = "数量至少为 2。",
                log_marker_add_failed = "在帧 %d 处添加 Mark 失败。",
                log_marker_add_success = "已添加 %d 个 Mark，间隔 %d 帧。",
                log_need_duration_marker = "请至少添加一个带持续时间的 Mark。",
                log_marker_duration_missing = "标记 %s（%s）缺少持续时间，已跳过。",
                log_marker_duration_too_short = "标记 %s（%s）的持续时间只有 1 帧，请按住 Alt 拖动 Mark 调整长度。",
                log_segment_skipped = "区间 %s - %s 内无视频片段，已跳过。",
                log_no_valid_segments = "未生成有效区间，请检查 Mark 间距。",
                log_segments_generated = "已生成 %d 个渲染区间。",
                log_markers_removed = "已移除脚本创建的 %d 个 Mark。",
                log_mark_range_failed = "为 %s 设置 I/O 范围失败。",
                log_row_status_pattern = "%s：%s",
                log_render_sequence_finished = "渲染序列已完成。",
                log_render_env_failed = "渲染环境初始化失败：%s",
                log_render_settings_failed = "为 %s 配置渲染设置失败。",
                log_add_job_failed = "添加渲染任务失败：%s。",
                log_job_added = "已添加渲染任务 %s。",
                log_start_job_failed = "启动任务 %s 失败。",
                log_attempts = "尝试记录：%s",
                log_job_started = "已开始渲染任务 %s。",
                log_project_missing = "未找到当前项目。",
                log_target_dir_required = "渲染前请先设置输出目录。",
                log_base_name_required = "渲染前请先设置文件名前缀。",
                log_no_jobs_available = "没有可渲染的任务。",
                log_jobs_prepared = "已准备 %d 个渲染任务。",
                log_render_in_progress = "渲染已在进行中。",
                log_starting_sequential = "正在启动 %d 个区间的顺序渲染。",
                log_sequential_started = "顺序渲染已启动。",
                log_start_render_failed = "启动渲染失败。",
                log_job_failed_cancel_rest = "任务 %s 失败；正在取消剩余任务。",
                log_render_interrupted_stop = "渲染被中断，正在停止任务。",
                log_detected_failure_stop = "检测到渲染失败，已停止所有任务。",
                log_render_interrupted = "渲染被中断。",
                log_window_closed = "窗口已关闭。",
                log_dir_picker_unavailable = "此环境下无法打开目录选择器。",
                log_dir_selected = "已选择输出目录：%s",
                log_queue_required = "请先加载渲染队列。"
            }
        }
    }

    function Locale:t(key)
        local langTable = self.strings[self.current] or {}
        return langTable[key] or (self.strings.en and self.strings.en[key]) or key
    end

    function Locale:format(key, ...)
        local text = self:t(key)
        if select("#", ...) > 0 then
            local ok, formatted = pcall(string.format, text, ...)
            if ok then
                return formatted
            end
        end
        return text
    end

    function Locale:set_language(lang)
        if self.strings[lang] then
            self.current = lang
        end
    end

    App.Locale = Locale
end

--
-- 2. 核心模块 (App.Core)
--
do
    local Core = {
        initialized = false,
        resolve = nil,
        fusion = nil,
        ui = nil,
        dispatcher = nil,
        projectManager = nil,
        project = nil,
        timeline = nil
    }

    local function init()
        Core.resolve = resolve
        if not Core.resolve and Resolve then
            local ok, res = pcall(Resolve)
            if ok then
                Core.resolve = res
            end
        end

        if not Core.resolve then
            print("[DaVinci Batch Render] 无法获取 Resolve 对象")
            return
        end

        local okFusion, fusionObj = pcall(function()
            return Core.resolve:Fusion()
        end)
        if okFusion then
            Core.fusion = fusionObj
        end
        if not Core.fusion then
            print("[DaVinci Batch Render] 无法获取 Fusion 对象")
            return
        end

        Core.ui = Core.fusion.UIManager
        if not Core.ui then
            print("[DaVinci Batch Render] 无法获取 UIManager")
            return
        end

        if bmd and bmd.UIDispatcher then
            Core.dispatcher = bmd.UIDispatcher(Core.ui)
        end
        if not Core.dispatcher then
            print("[DaVinci Batch Render] 无法创建 UIDispatcher")
            return
        end

        Core.initialized = true
        print(string.format("[%s] 初始化成功", App.Config.SCRIPT_NAME))
    end

    function Core:getProjectManager()
        if not self.projectManager and self.resolve and self.resolve.GetProjectManager then
            self.projectManager = self.resolve:GetProjectManager()
        end
        return self.projectManager
    end

    function Core:getProject()
        local pm = self:getProjectManager()
        if pm then
            self.project = pm:GetCurrentProject()
        end
        return self.project
    end

    function Core:getTimeline()
        local project = self:getProject()
        if project then
            self.timeline = project:GetCurrentTimeline()
        end
        return self.timeline
    end

    init()
    App.Core = Core
end

--
-- 3. 工具模块 (App.Helpers)
--
do
    local Helpers = {}

    local fpsAliases = {
        ["23.976"] = { num = 24000, den = 1001 },
        ["29.97"]  = { num = 30000, den = 1001 },
        ["59.94"]  = { num = 60000, den = 1001 },
        ["47.952"] = { num = 48000, den = 1001 },
        ["119.88"] = { num = 120000, den = 1001 },
    }

    function Helpers:deep_copy(tbl)
        if type(tbl) ~= "table" then return tbl end
        local res = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                res[k] = self:deep_copy(v)
            else
                res[k] = v
            end
        end
        return res
    end

    function Helpers:merge_tables(a, b)
        local res = self:deep_copy(a)
        for k, v in pairs(b or {}) do
            res[k] = v
        end
        return res
    end

    function Helpers:trim(str)
        if type(str) ~= "string" then
            return ""
        end
        return (str:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function Helpers:url_encode(str)
        if not str then
            return ""
        end
        return tostring(str):gsub("([^%w%-_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end

    function Helpers:script_dir()
        return App.Config.SCRIPT_DIR or "."
    end

    function Helpers:join_path(a, b)
        return join_path(a or "", b or "")
    end

    function Helpers:file_exists(path)
        if not path or path == "" then
            return false
        end
        local ok = os.rename(path, path)
        return ok ~= nil
    end

    function Helpers:ensure_dir(path)
        path = self:trim(path or "")
        if path == "" then
            return false
        end
        if self:file_exists(path) then
            return true
        end
        local cmd
        if IS_WINDOWS then
            cmd = string.format('if not exist "%s" mkdir "%s"', path, path)
        else
            cmd = string.format('mkdir -p "%s"', path)
        end
        return runShellCommand(cmd)
    end

    function Helpers:remove_dir(path)
        path = self:trim(path or "")
        if path == "" then
            return
        end
        if IS_WINDOWS then
            runShellCommand(string.format('rmdir /S /Q "%s"', path))
            return
        end
        local escaped = path:gsub("'", "'\\''")
        runShellCommand("rm -rf '" .. escaped .. "'")
    end

    function Helpers:openExternalUrl(url)
        if not url or url == "" then
            return
        end
        if bmd and bmd.openurl then
            local ok, err = pcall(bmd.openurl, url)
            if not ok then
                print("openurl failed: " .. tostring(err))
            end
            return
        end
        if IS_WINDOWS then
            runShellCommand(string.format('start "" "%s"', url))
            return
        end
        local escaped = url:gsub("'", "'\\''")
        if not runShellCommand("open '" .. escaped .. "'") then
            runShellCommand("xdg-open '" .. escaped .. "'")
        end
    end

    function Helpers:read_file(path)
        local file = io.open(path, "rb")
        if not file then
            return nil
        end
        local content = file:read("*a")
        file:close()
        return content
    end

    function Helpers:write_file(path, content)
        local dir = path and path:match("^(.*)[/\\][^/\\]+$")
        if dir then
            self:ensure_dir(dir)
        end
        local file, err = io.open(path, "wb")
        if not file then
            return false, err
        end
        file:write(content or "")
        file:close()
        return true
    end

    function Helpers:read_json(path)
        local data = self:read_file(path)
        if not data or data == "" then
            return nil
        end
        local ok, decoded = pcall(json.decode, data)
        if ok then
            return decoded
        end
        return nil
    end

    function Helpers:write_json(path, tbl)
        local ok, encoded = pcall(json.encode, tbl or {})
        if not ok then
            return false
        end
        return self:write_file(path, encoded)
    end

    function Helpers:split_path(path)
        if type(path) ~= "string" or path == "" then
            return "", ""
        end
        local dir, file = path:match("^(.*[\\/])([^\\/]+)$")
        if not dir then
            return "", path
        end
        return dir, file
    end

    function Helpers:strip_extension(filename)
        if type(filename) ~= "string" then
            return ""
        end
        return filename:gsub("%.[^%.]+$", "")
    end

    function Helpers:get_temp_dir()
        local dir = App.Config.TEMP_DIR or self:join_path(self:script_dir(), "temp")
        self:ensure_dir(dir)
        return dir
    end

    function Helpers:make_temp_path(ext)
        local dir = self:get_temp_dir()
        local suffix = self:trim(ext or "")
        if suffix ~= "" and not suffix:match("^%.") then
            suffix = "." .. suffix
        end
        local seed = tostring(os.time())
        for i = 1, 1000 do
            local candidate = self:join_path(dir, string.format("tmp_%s_%06d%s", seed, i, suffix))
            if not self:file_exists(candidate) then
                return candidate
            end
        end
        return self:join_path(dir, string.format("tmp_%s_%d%s", seed, math.random(999999), suffix))
    end

    function Helpers:safe_number(value)
        local num = tonumber(value)
        if num then return num end
        if type(value) == "string" then
            num = tonumber(value:match("[0-9%.]+"))
        end
        return tonumber(num)
    end

    function Helpers:base64_decode(data)
        data = tostring(data or ""):gsub("[^%w%+/%=]", "")
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local output = {}
        local padding = 0
        if data:sub(-2) == "==" then
            padding = 2
        elseif data:sub(-1) == "=" then
            padding = 1
        end
        for i = 1, #data, 4 do
            local n = 0
            for j = 0, 3 do
                local c = data:sub(i + j, i + j)
                if c ~= "" and c ~= "=" then
                    local idx = alphabet:find(c, 1, true)
                    if not idx then
                        error("invalid base64 character")
                    end
                    n = n * 64 + (idx - 1)
                else
                    n = n * 64
                end
            end
            local bytes = string.char(
                math.floor(n / 65536) % 256,
                math.floor(n / 256) % 256,
                n % 256
            )
            table.insert(output, bytes)
        end
        local result = table.concat(output)
        if padding > 0 then
            result = result:sub(1, #result - padding)
        end
        return result
    end

    function Helpers:create_image_from_base64(base64Data, destinationPath)
        local ok, bytes = pcall(function()
            return self:base64_decode(base64Data)
        end)
        if not ok or not bytes then
            return false
        end
        local file, err = io.open(destinationPath, "wb")
        if not file then
            return false, err
        end
        file:write(bytes)
        file:close()
        return true
    end

    function Helpers:httpGet(url, headers, timeout)
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
            local outPath, err = self:make_temp_path("out")
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

    function Helpers:httpPostJson(url, payload, headers, timeout)
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

        local tempPayload, err1 = self:make_temp_path("json")
        if not tempPayload then return nil, "tmpname_failed:" .. tostring(err1) end
        local f, err2 = io.open(tempPayload, "wb")
        if not f then
            os.remove(tempPayload)
            return nil, "payload_tmp_open_failed:" .. tostring(err2)
        end
        f:write(bodyStr)
        f:close()

        if sep == "\\" then
            local outputPath, err3 = self:make_temp_path("out")
            if not outputPath then
                os.remove(tempPayload)
                return nil, "tmpname_failed:" .. tostring(err3)
            end

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
            if not pipe then
                os.remove(tempPayload)
                return nil, "curl_popen_failed"
            end
            local body = pipe:read("*a") or ""
            pipe:close()
            os.remove(tempPayload)
            if body == "" then return nil, "empty_response" end
            return body, nil
        end
    end

    local function gcd(a, b)
        a, b = math.abs(a), math.abs(b)
        while b ~= 0 do
            a, b = b, a % b
        end
        return a
    end

    local function normalize_fraction(num, den)
        if den == 0 then
            return 0, 1
        end
        if den < 0 then
            num, den = -num, -den
        end
        local g = gcd(num, den)
        return math.floor(num / g), math.floor(den / g)
    end

    function Helpers:fps_to_fraction(value)
        if type(value) == "table" and value.num and value.den then
            local num, den = normalize_fraction(value.num, value.den)
            return { num = num, den = den }
        end
        if value == nil then
            return { num = 24, den = 1 }
        end
        if type(value) == "number" then
            for str, frac in pairs(fpsAliases) do
                if math.abs(value - (frac.num / frac.den)) < 1e-3 then
                    return { num = frac.num, den = frac.den }
                end
            end
            if value > 0 then
                return { num = math.floor(value + 0.5), den = 1 }
            end
            return { num = 24, den = 1 }
        end
        local s = tostring(value)
        local alias = fpsAliases[s]
        if alias then
            return { num = alias.num, den = alias.den }
        end
        if s:find("/") then
            local num, den = s:match("^(%d+)%s*/%s*(%d+)$")
            num, den = tonumber(num), tonumber(den)
            if num and den and den ~= 0 then
                local n, d = normalize_fraction(num, den)
                return { num = n, den = d }
            end
        end
        local asNumber = tonumber(s)
        if asNumber then
            return self:fps_to_fraction(asNumber)
        end
        return { num = 24, den = 1 }
    end

    function Helpers:fps_as_float(fpsSpec)
        local frac = self:fps_to_fraction(fpsSpec)
        return frac.num / frac.den
    end

    function Helpers:fps_timebase(fpsSpec)
        local value = self:fps_as_float(fpsSpec)
        return math.max(1, math.floor(value + 0.5))
    end

    function Helpers:frames_to_timecode(frames, fpsSpec)
        return self:frames_to_timecode_precise(frames, fpsSpec)
    end

    function Helpers:frames_to_timecode_precise(frames, fpsSpec)
        local frac = self:fps_to_fraction(fpsSpec or { num = 24, den = 1 })
        local base = self:fps_timebase(frac)
        local totalFrames = math.max(0, math.floor((frames or 0) + 0.5))
        local framesPerHour = base * 3600
        local framesPerMinute = base * 60
        local hh = math.floor(totalFrames / framesPerHour)
        totalFrames = totalFrames - hh * framesPerHour
        local mm = math.floor(totalFrames / framesPerMinute)
        totalFrames = totalFrames - mm * framesPerMinute
        local ss = math.floor(totalFrames / base)
        local ff = totalFrames - ss * base
        return string.format("%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    end

    function Helpers:timecode_to_frames(timecode, fpsSpec)
        if not timecode or timecode == "" then
            return nil
        end
        local hh, mm, ss, ff = timecode:match("^(%d+):(%d+):(%d+):(%d+)$")
        if not hh then
            return nil
        end
        hh, mm, ss, ff = tonumber(hh), tonumber(mm), tonumber(ss), tonumber(ff)
        if not (hh and mm and ss and ff) then
            return nil
        end
        local frac = self:fps_to_fraction(fpsSpec or { num = 24, den = 1 })
        local base = self:fps_timebase(frac)
        local totalFrames = ((hh * 3600) + (mm * 60) + ss) * base + ff
        return math.floor(totalFrames * frac.den / base + 0.5)
    end

    function Helpers:get_timeline_fps_fraction(timeline)
        if not timeline or not timeline.GetSetting then
            return { num = 24, den = 1 }
        end
        local keys = { "timelineFrameRate", "timelinePlaybackFrameRate", "timelineProxyFrameRate" }
        for _, key in ipairs(keys) do
            local ok, value = pcall(function()
                return timeline:GetSetting(key)
            end)
            if ok and value then
                return self:fps_to_fraction(value)
            end
        end
        return { num = 24, den = 1 }
    end

    function Helpers:get_timeline_fps(timeline)
        local frac = self:get_timeline_fps_fraction(timeline)
        return frac.num / frac.den
    end

    function Helpers:sort_markers(markerDict)
        local list = {}
        for frame, meta in pairs(markerDict or {}) do
            local f = tonumber(frame)
            if f then
                table.insert(list, { frame = f, meta = meta })
            end
        end
        table.sort(list, function(a, b) return a.frame < b.frame end)
        return list
    end

    function Helpers:http_get(url, headers, timeout)
        return self:httpGet(url, headers, timeout)
    end

    App.Helpers = Helpers
end

App.Helpers:ensure_dir(App.Config.CONFIG_DIR)
App.Helpers:ensure_dir(App.Config.TEMP_DIR)

--
-- 4. 状态模块 (App.State)
--
do
    local State = {
        interval_seconds = App.Config.DEFAULT_INTERVAL_SECONDS,
        mark_count = App.Config.DEFAULT_MARK_COUNT,
        target_dir = "",
        base_name = "",
        language = App.Locale and App.Locale.current or "en",
        tree_rows = {},
        job_ids = {},
        job_rows = {},
        logs = {},
        created_markers = {},
        timeline_fps = 24,
        timeline_fps_fraction = { num = 24, den = 1 },
        timeline_start_frame = 0,
        update_info = nil,
    }

    function State:reset_job_tracking()
        self.job_ids = {}
        self.job_rows = {}
    end

    function State:set_tree_rows(rows)
        self.tree_rows = rows or {}
        self:reset_job_tracking()
        for _, row in ipairs(self.tree_rows) do
            if row then
                row.jobId = nil
                row.statusKey = "pending"
                row.statusExtra = nil
                row.lastLoggedStatus = nil
            end
        end
        self:apply_base_name_to_rows()
    end

    function State:get_tree_rows()
        return self.tree_rows or {}
    end

    function State:get_row_by_index(index)
        if not index then
            return nil
        end
        index = tonumber(index)
        if not index then
            return nil
        end
        for _, row in ipairs(self.tree_rows or {}) do
            if row and row.index == index then
                return row
            end
        end
        return nil
    end

    function State:set_job_ids(jobIds)
        self.job_ids = jobIds or {}
    end

    function State:register_job_row(jobId, row)
        if not jobId or not row then
            return
        end
        self.job_rows[jobId] = row
    end

    function State:get_row_by_job(jobId)
        if not jobId then
            return nil
        end
        return self.job_rows[jobId]
    end

    function State:set_row_status(row, statusKey, statusExtra)
        if not row then
            return false, false
        end
        local changed = false
        local keyChanged = false
        if row.statusKey ~= statusKey then
            row.statusKey = statusKey
            changed = true
            keyChanged = true
        end
        if row.statusExtra ~= statusExtra then
            row.statusExtra = statusExtra
            changed = true
        end
        return changed, keyChanged
    end

    function State:set_target_dir(path)
        self.target_dir = App.Helpers:trim(path or "")
    end

    function State:apply_base_name_to_rows()
        local prefix = App.Helpers:trim(self.base_name or "")
        if prefix == "" then
            return
        end
        for _, row in ipairs(self.tree_rows or {}) do
            if row.index then
                row.name = string.format("%s_%03d", prefix, row.index)
            end
        end
    end

    function State:set_base_name(name)
        local sanitized = App.Helpers:strip_extension(App.Helpers:trim(name or ""))
        if sanitized == "" then
            sanitized = "Batch"
        end
        self.base_name = sanitized
        self:apply_base_name_to_rows()
    end

    function State:remember_marker(frame)
        if type(frame) ~= "number" then
            return
        end
        self.created_markers[math.floor(frame + 0.5)] = true
    end

    function State:reset_created_markers()
        self.created_markers = {}
    end

    function State:init_defaults()
        local timeline = App.Core:getTimeline()
        if timeline and timeline.GetName then
            self:set_base_name(timeline:GetName() or "Batch")
        else
            self:set_base_name("Batch")
        end
        self.target_dir = self.target_dir or ""
        self.language = self.language or (App.Locale and App.Locale.current) or "en"
        self.timeline_fps_fraction = self.timeline_fps_fraction or { num = 24, den = 1 }
        self.timeline_fps = self.timeline_fps or 24
        self.timeline_start_frame = self.timeline_start_frame or 0
    end

    function State:set_timeline_fps(fpsFraction)
        if type(fpsFraction) == "table" and fpsFraction.num and fpsFraction.den then
            self.timeline_fps_fraction = { num = fpsFraction.num, den = fpsFraction.den }
            self.timeline_fps = fpsFraction.num / fpsFraction.den
        end
    end

    function State:get_timeline_fps_fraction()
        return self.timeline_fps_fraction or { num = 24, den = 1 }
    end

    function State:set_timeline_start_frame(frame)
        local value = tonumber(frame) or 0
        self.timeline_start_frame = math.floor(value + 0.5)
    end

    function State:get_timeline_start_frame()
        return self.timeline_start_frame or 0
    end

    State:init_defaults()
    if App.Locale then
        App.Locale:set_language(State.language)
    end
    App.State = State
end

--
-- 5. 设置模块 (App.Settings)
--
do
    local Settings = { data = {} }
    local Helpers = App.Helpers

    function Settings:load()
        Helpers:ensure_dir(App.Config.CONFIG_DIR)
        local stored = Helpers:read_json(App.Config.SETTINGS_FILE)
        if type(stored) ~= "table" then
            stored = {}
        end
        self.data = stored
        local lang = stored.language
        if lang == "en" or lang == "zh" then
            App.State.language = lang
            if App.Locale then
                App.Locale:set_language(lang)
            end
        else
            stored.language = App.State.language
        end
    end

    function Settings:save()
        if not self.data then
            self.data = {}
        end
        self.data.language = App.State.language
        App.Helpers:write_json(App.Config.SETTINGS_FILE, self.data)
    end

    App.Settings = Settings
    App.Settings:load()
end

--
-- 6. 更新检测模块 (App.Update)
--
do
    local Update = {}
    local Helpers = App.Helpers

    function Update:_fetch()
        local url = string.format(
            "%s/functions/v1/check_update?pid=%s",
            App.Config.SUPABASE_URL,
            Helpers:url_encode(App.Config.SCRIPT_NAME)
        )
        local headers = {
            Authorization = "Bearer " .. App.Config.SUPABASE_ANON_KEY,
            apikey = App.Config.SUPABASE_ANON_KEY,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = string.format("%s/%s", App.Config.SCRIPT_NAME, App.Config.SCRIPT_VERSION),
        }
        local body, status = Helpers:httpGet(url, headers, App.Config.SUPABASE_TIMEOUT)
        if not body then
            return nil
        end
        if status and status ~= 200 and status ~= 0 then
            return nil
        end
        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" then
            return nil
        end
        return decoded
    end

    function Update:_build_message(payload, lang, latest, current)
        local key = lang == "zh" and "cn" or "en"
        local info = ""
        if type(payload) == "table" then
            info = Helpers:trim(payload[key] or payload[lang])
        end
        local readableCurrent = Helpers:trim(current or "")
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
            return
        end
        local latest = Helpers:trim(tostring(payload.latest or ""))
        local current = Helpers:trim(tostring(App.Config.SCRIPT_VERSION or ""))
        if latest == "" or latest == current then
            return
        end
        local info = {
            latest = latest,
            current = current,
            en = self:_build_message(payload, "en", latest, current),
            zh = self:_build_message(payload, "zh", latest, current),
        }
        App.State.update_info = info
        if App.UI and App.UI.update_update_status_label then
            App.UI:update_update_status_label()
        end
    end

    App.Update = Update
end
--
-- 7. 日志模块 (App.Logger)
--
do
    local Logger = {
        lines = {},
        entries = {}
    }
    local unpack_list = (table and table.unpack) or unpack

    local function clone_args(args)
        if not args or #args == 0 then
            return {}
        end
        local copy = {}
        for i = 1, #args do
            copy[i] = args[i]
        end
        return copy
    end

    function Logger:_format_entry(entry)
        if not entry then
            return ""
        end
        local content = entry.message or ""
        if entry.key and App.Locale and App.Locale.format then
            local ok, formatted = pcall(function()
                return App.Locale:format(entry.key, unpack_list(entry.args or {}))
            end)
            if ok and formatted then
                content = formatted
            end
        end
        return string.format("[%s] %s", entry.timestamp or os.date("%H:%M:%S"), content)
    end

    function Logger:_trim()
        local maxLines = App.Config.LOG_MAX_LINES or 200
        local trimmed = false
        while #self.entries > maxLines do
            table.remove(self.entries, 1)
            trimmed = true
            if #self.lines > maxLines then
                table.remove(self.lines, 1)
            end
        end
        while #self.lines > maxLines do
            table.remove(self.lines, 1)
            trimmed = true
        end
        return trimmed
    end

    local function get_log_view()
        local items = App.UI and App.UI.items
        return items and items.LogView or nil
    end

    local function append_line(view, line)
        if not view or not line then
            return
        end
        if view.Append then
            pcall(function()
                view:Append(line)
            end)
            return
        end
        local existing = view.Text or ""
        if existing ~= "" then
            view.Text = existing .. "\n" .. line
        else
            view.Text = line
        end
    end

    function Logger:_update_view(refreshAll)
        local view = get_log_view()
        if not view then
            return
        end
        if refreshAll then
            if view.Clear then
                pcall(function()
                    view:Clear()
                end)
            end
            if view.Append then
                for _, line in ipairs(self.lines) do
                    append_line(view, line)
                end
            else
                view.Text = table.concat(self.lines, "\n")
            end
            return
        end
        append_line(view, self.lines[#self.lines])
    end

    function Logger:_append_entry(entry)
        if not entry then
            return
        end
        table.insert(self.entries, entry)
        local line = self:_format_entry(entry)
        table.insert(self.lines, line)
        local trimmed = self:_trim()
        print(line)
        self:_update_view(trimmed)
    end

    function Logger:append(message)
        if message == nil then
            return
        end
        local entry = {
            message = tostring(message),
            timestamp = os.date("%H:%M:%S")
        }
        self:_append_entry(entry)
    end

    function Logger:append_localized(key, ...)
        if not key then
            return
        end
        local args = { ... }
        local message
        if App.Locale and App.Locale.format then
            local ok, formatted = pcall(function()
                return App.Locale:format(key, unpack_list(args))
            end)
            message = ok and formatted or nil
        end
        if not message then
            if #args > 0 then
                local ok, formatted = pcall(string.format, key, unpack_list(args))
                message = ok and formatted or key
            else
                message = key
            end
        end
        local entry = {
            key = key,
            args = clone_args(args),
            message = message,
            timestamp = os.date("%H:%M:%S")
        }
        self:_append_entry(entry)
    end

    function Logger:refresh_language()
        local rebuilt = {}
        for _, entry in ipairs(self.entries) do
            table.insert(rebuilt, self:_format_entry(entry))
        end
        self.lines = rebuilt
        self:_trim()
        self:_update_view(true)
    end

    App.Logger = Logger
end

--
-- 6. 时间线模块 (App.Timeline)
--
do
    local Timeline = {}

    function Timeline:add_markers(interval_seconds, count)
        local timeline = App.Core:getTimeline()
        if not timeline then
            App.Logger:append_localized("log_active_timeline_missing")
            return false
        end

        interval_seconds = tonumber(interval_seconds)
        count = tonumber(count)
        if not interval_seconds or interval_seconds <= 0 then
            App.Logger:append_localized("log_interval_invalid")
            return false
        end
        if not count or count < 2 then
            App.Logger:append_localized("log_count_invalid")
            return false
        end

        local fpsFraction = App.Helpers:get_timeline_fps_fraction(timeline)
        local fpsBase = App.Helpers:fps_timebase(fpsFraction)
        local interval_frames = math.max(1, math.floor(interval_seconds * fpsBase + 0.5))
        local start_frame = 0

        for i = 0, count - 1 do
            local frame = start_frame + i * interval_frames
            local name = string.format("Batch_%03d", i + 1)
            local ok = timeline:AddMarker(frame, App.Config.MARK_COLOR, name, App.Config.MARK_TAG, interval_frames, App.Config.MARK_TAG)
            if not ok then
                App.Logger:append_localized("log_marker_add_failed", frame)
                return false
            else
                App.State:remember_marker(frame)
            end
        end

        App.Logger:append_localized("log_marker_add_success", count, interval_frames)
        return true
    end

    local function collect_track_items(timeline)
        local collections = {
            video = {},
            audio = {}
        }
        if not (timeline and timeline.GetTrackCount and timeline.GetItemListInTrack) then
            return collections
        end

        local function push_tracks(trackType)
            local count = timeline:GetTrackCount(trackType) or 0
            local target = collections[trackType]
            if target then
                for idx = 1, count do
                    table.insert(target, timeline:GetItemListInTrack(trackType, idx) or {})
                end
            end
        end

        push_tracks("video")
        push_tracks("audio")
        return collections
    end

    local function resolve_clip_frame(item, primaryGetter, fallbackGetter, offset)
        if not item then
            return nil
        end
        local getter = primaryGetter and item[primaryGetter]
        if type(getter) == "function" then
            local ok, value = pcall(getter, item)
            if ok then
                local num = tonumber(value)
                if num then
                    return math.floor(num + 0.5)
                end
            end
        end
        getter = fallbackGetter and item[fallbackGetter]
        if type(getter) == "function" then
            local ok, value = pcall(getter, item)
            if ok then
                local num = tonumber(value)
                if num then
                    if offset and offset ~= 0 then
                        num = num - offset
                    end
                    return math.floor(num + 0.5)
                end
            end
        end
        return nil
    end

    local function has_media_between(trackCollections, startFrame, endFrame, timelineStartFrame)
        if not startFrame or not endFrame or endFrame <= startFrame then
            return false
        end
        local offset = tonumber(timelineStartFrame) or 0
        for _, items in ipairs(trackCollections or {}) do
            for _, item in ipairs(items) do
                local clipStart = resolve_clip_frame(item, "GetStartFrame", "GetStart", offset)
                local clipEnd = resolve_clip_frame(item, "GetEndFrame", "GetEnd", offset)
                if clipStart and clipEnd and clipEnd > startFrame and clipStart < endFrame then
                    return true
                end
            end
        end
        return false
    end

    local function extract_marker_duration(meta)
        if type(meta) ~= "table" then
            return nil
        end
        local candidates = { "duration", "Duration", "length", "Length" }
        for _, key in ipairs(candidates) do
            local value = meta[key]
            if value ~= nil then
                local num = tonumber(value)
                if num and num > 0 then
                    return math.floor(num + 0.5)
                end
            end
        end
        return nil
    end

    local function marker_display_name(meta, fallback)
        if type(meta) == "table" then
            return meta.name or meta.Name or meta.text or meta.Text or fallback
        end
        return fallback
    end

    function Timeline:build_segments()
        local timeline = App.Core:getTimeline()
        if not timeline then
            App.Logger:append_localized("log_active_timeline_missing")
            return nil
        end
        local markerDict = timeline:GetMarkers() or {}
        local sorted = App.Helpers:sort_markers(markerDict)
        local targetMarkers = {}
        for _, entry in ipairs(sorted) do
            if entry.meta then
                table.insert(targetMarkers, entry)
            end
        end
        if #targetMarkers == 0 then
            App.Logger:append_localized("log_need_duration_marker")
            return nil
        end
        local fpsFraction = App.Helpers:get_timeline_fps_fraction(timeline)
        local fps = App.Helpers:get_timeline_fps(timeline)
        App.State:set_timeline_fps(fpsFraction)
        local timelineStartFrame = 0
        if timeline.GetStartFrame then
            local ok, value = pcall(function()
                return timeline:GetStartFrame()
            end)
            if ok then
                timelineStartFrame = tonumber(value) or 0
            end
        end
        App.State:set_timeline_start_frame(timelineStartFrame)
        local trackCollections = collect_track_items(timeline)
        local timelineName = timeline:GetName() or "Timeline"
        local basePrefix = App.Helpers:trim(App.State.base_name or "") ~= "" and App.State.base_name or timelineName
        local segments = {}
        local segmentIndex = 0
        for idx, marker in ipairs(targetMarkers) do
            local startFrame = math.floor(marker.frame + 0.5)
            local nextMarker = targetMarkers[idx + 1]
            local fallbackDuration = nil
            if nextMarker then
                fallbackDuration = math.floor(nextMarker.frame + 0.5) - startFrame
                if fallbackDuration <= 0 then
                    fallbackDuration = nil
                end
            end
            local durationFrames = extract_marker_duration(marker.meta)
            if (not durationFrames or durationFrames <= 0) and fallbackDuration then
                durationFrames = fallbackDuration
            end
            local displayStartFrame = startFrame + timelineStartFrame
            local startTc = App.Helpers:frames_to_timecode_precise(displayStartFrame, fpsFraction)
            if not durationFrames or durationFrames <= 0 then
                App.Logger:append_localized(
                    "log_marker_duration_missing",
                    marker_display_name(marker.meta, string.format("#%03d", idx)),
                    startTc
                )
            elseif durationFrames == 1 then
                App.Logger:append_localized(
                    "log_marker_duration_too_short",
                    marker_display_name(marker.meta, string.format("#%03d", idx)),
                    startTc
                )
            else
                local endFrame = startFrame + durationFrames
                local inclusiveEndFrame = math.max(startFrame, endFrame - 1)
                local displayEndFrame = inclusiveEndFrame + timelineStartFrame
                local endTc = App.Helpers:frames_to_timecode_precise(displayEndFrame, fpsFraction)
                if not has_media_between(trackCollections.video, startFrame, endFrame, timelineStartFrame) then
                    App.Logger:append_localized("log_segment_skipped", startTc, endTc)
                else
                    segmentIndex = segmentIndex + 1
                    local row = {
                        index = segmentIndex,
                        startFrame = startFrame,
                        endFrame = endFrame,
                        startTimecode = startTc,
                        endTimecode = endTc,
                        name = string.format("%s_%03d", basePrefix, segmentIndex),
                        statusKey = "pending",
                        statusExtra = nil
                    }
                    table.insert(segments, row)
                end
            end
        end
        if #segments == 0 then
            App.Logger:append_localized("log_no_valid_segments")
            return nil
        end
        App.Logger:append_localized("log_segments_generated", #segments)
        return segments
    end

    function Timeline:cleanup_script_markers()
        local timeline = App.Core:getTimeline()
        if not timeline then
            return
        end
        local markers = timeline:GetMarkers() or {}
        local removed = 0
        for frame, meta in pairs(markers) do
            if meta and meta.customData == App.Config.MARK_TAG then
                timeline:DeleteMarkerAtFrame(frame)
                removed = removed + 1
            end
        end
        if removed > 0 then
            App.Logger:append_localized("log_markers_removed", removed)
        end
        App.State:reset_created_markers()
    end

    function Timeline:clear_mark_range()
        local timeline = App.Core:getTimeline()
        if not (timeline and timeline.ClearMarkInOut) then
            return false
        end
        local ok, res = pcall(function()
            return timeline:ClearMarkInOut("all")
        end)
        return ok and res ~= false
    end

    function Timeline:apply_mark_range(row)
        if not row or not row.startFrame or not row.endFrame or row.endFrame <= row.startFrame then
            return false
        end
        local timeline = App.Core:getTimeline()
        if not (timeline and timeline.SetMarkInOut) then
            return false
        end
        local markOut = math.max(row.startFrame, row.endFrame - 1)
        local ok, result = pcall(function()
            return timeline:SetMarkInOut(row.startFrame, markOut, "all")
        end)
        if ok and result == true then
            return true
        end
        if App.Logger and App.Logger.append_localized then
            App.Logger:append_localized("log_mark_range_failed", row.name or row.startTimecode or tostring(row.index or "?"))
        end
        return false
    end

    function Timeline:jump_to_frame(frame)
        if not frame then
            return false
        end
        local timeline = App.Core:getTimeline()
        if not timeline then
            return false
        end
        local resolve = App.Core.resolve
        if resolve and resolve.GetCurrentPage then
            local currentPage = resolve:GetCurrentPage()
            local allowed = {
                cut = true,
                edit = true,
                color = true,
                fairlight = true,
                deliver = true,
            }
            if not allowed[currentPage] and resolve.OpenPage then
                resolve:OpenPage("edit")
            end
        end
        local fpsFrac = App.State:get_timeline_fps_fraction()
        local startOffset = App.State:get_timeline_start_frame() or 0
        local displayFrame = (tonumber(frame) or 0) + startOffset
        local timecode = App.Helpers:frames_to_timecode_precise(displayFrame, fpsFrac)
        local ok = timeline.SetCurrentTimecode and timeline:SetCurrentTimecode(timecode)
        if not ok and timeline.SetCurrentFrame then
            ok = timeline:SetCurrentFrame(frame)
        end
        return ok == true
    end

    function Timeline:jump_to_row(row)
        if not row then
            return false
        end
        local jumped = self:jump_to_frame(row.startFrame)
        if jumped then
            self:apply_mark_range(row)
        end
        return jumped
    end

    App.Timeline = Timeline
end

--
-- 7. 渲染模块 (App.Render)
--
do
    local Render = {
        monitor = nil,
        _statusDirty = false,
        sequence = nil
    }
    local unpack_list = (table and table.unpack) or unpack

    local statusLocaleKeys = {
        pending = "status_pending",
        queued = "status_queued",
        waiting = "status_waiting",
        rendering = "status_rendering",
        done = "status_done",
        failed = "status_failed"
    }

    local function localized_text(key, ...)
        local args = { ... }
        if not key then
            return ""
        end
        if App.Locale and App.Locale.format then
            local ok, text = pcall(function()
                return App.Locale:format(key, unpack_list(args))
            end)
            if ok and text then
                return text
            end
        end
        if #args > 0 then
            local ok, text = pcall(string.format, key, unpack_list(args))
            if ok and text then
                return text
            end
        end
        return key
    end

    -- 仅保留：切到 Deliver 页 + 目录校验
    local function ensure_render_env(project, targetDir)
        if not project then return false, "log_project_missing" end

        local resolver = App.Core and App.Core.resolve
        if resolver and resolver.OpenPage then
            pcall(function() resolver:OpenPage("deliver") end) -- 切到 Deliver 页（官方支持）【:contentReference[oaicite:14]{index=14}】
        end

        -- 不再调用：SetCurrentRenderMode / SetCurrentRenderFormatAndCodec
        if type(targetDir) ~= "string" or targetDir == "" then
            return false, "log_target_dir_required"
        end
        return true
    end


    local function to_display_frame(frame)
        local base = tonumber(frame) or 0
        local offset = 0
        if App.State and App.State.get_timeline_start_frame then
            offset = App.State:get_timeline_start_frame() or 0
        end
        return math.floor(base + offset + 0.5)
    end

    local function build_settings(row, targetDir, baseName)
        local prefix = App.Helpers:trim(baseName or "")
        if prefix == "" then prefix = "Render" end
        local customName = string.format("%s_%03d", prefix, row.index or 0)
        row.name = customName
        local markIn = to_display_frame(row.startFrame)
        local markOut = to_display_frame(math.max(row.startFrame, row.endFrame - 1))

        -- 仅设置范围、目录、文件名；其余参数沿用 Deliver 页当前设置
        return {
            SelectAllFrames = false,   -- 使用 MarkIn/Out
            MarkIn = markIn,
            MarkOut = markOut,
            TargetDir = targetDir,
            CustomName = customName,
            -- 不再设置 ExportVideo/ExportAudio/Format/Codec/Quality...
        } -- 这些键均为官方支持【:contentReference[oaicite:15]{index=15}】
    end


    local function update_row_status(row, statusKey, statusExtra)
        local changed, keyChanged = App.State:set_row_status(row, statusKey, statusExtra)
        if changed then
            Render._statusDirty = true
        end
        return changed, keyChanged
    end

    local function log_row_status(row, statusKey)
        if not row or not statusKey then
            return
        end
        if row.lastLoggedStatus == statusKey then
            return
        end
        local labelKey = statusLocaleKeys[statusKey]
        if not labelKey then
            return
        end
        row.lastLoggedStatus = statusKey
        local rowName = row.name or string.format("Segment %s", tostring(row.index or "?"))
        local labelText = App.Locale and App.Locale:format(labelKey) or labelKey
        App.Logger:append_localized("log_row_status_pattern", rowName, labelText)
    end

    local function ensure_ui_refresh()
        if Render._statusDirty and App.UI then
            App.UI:refresh_tree()
            Render._statusDirty = false
        end
    end

    local function normalize_job_status(info)
        if type(info) ~= "table" then
            return "unknown", nil
        end
        local rawStatus = info.JobStatus or info.Status or info["Job Status"] or info.State
        local normalized = "queued"
        if rawStatus and rawStatus ~= "" then
            local lower = string.lower(tostring(rawStatus))
            if lower:find("render") or lower:find("process") or lower:find("run") then
                normalized = "rendering"
            elseif lower:find("wait") or lower:find("queue") or lower:find("hold") then
                normalized = "waiting"
            elseif lower:find("fail") or lower:find("error") or lower:find("cancel") or lower:find("abort") or lower:find("stop") then
                normalized = "failed"
            elseif lower:find("complete") or lower:find("finish") or lower:find("success") or lower:find("done") then
                normalized = "done"
            else
                normalized = "queued"
            end
        end
        local progressText = nil
        local progress = info.CompletionPercentage or info.PercentComplete or info.Percentage or info.Progress
        if normalized == "rendering" and progress ~= nil then
            local numeric = tonumber(progress)
            if numeric then
                numeric = math.max(0, math.min(100, numeric))
                progressText = string.format("%d%%", math.floor(numeric + 0.5))
            elseif type(progress) == "string" and progress ~= "" then
                progressText = progress
            end
        end
        return normalized, progressText
    end

    local function finalize_rows_as(statusKey)
        local updated = false
        for _, row in ipairs(App.State:get_tree_rows() or {}) do
            if row and row.statusKey ~= "done" and row.statusKey ~= "failed" then
                local _, keyChanged = update_row_status(row, statusKey, nil)
                if keyChanged then
                    log_row_status(row, statusKey)
                end
                updated = updated or keyChanged
            end
        end
        return updated
    end

    local function delete_render_job(project, jobId)
        if not (project and jobId) then
            return
        end
        if project.DeleteRenderJob then
            pcall(function()
                project:DeleteRenderJob(jobId)
            end)
        end
    end

    local function delete_job_list(project, jobIds)
        if not jobIds or not project then
            return
        end
        for _, jobId in ipairs(jobIds) do
            delete_render_job(project, jobId)
        end
    end

    local function clear_pending_jobs(project)
        local pending = App.State and App.State.job_ids or {}
        delete_job_list(project, pending)
        if App.State and App.State.set_job_ids then
            App.State:set_job_ids({})
        end
    end

    local function complete_sequence()
        if Render.sequence then
            Render.sequence.active = false
            Render.sequence = nil
        end
        if Render.stop_monitor then
            Render:stop_monitor()
        end
        if App.State and App.State.set_job_ids then
            App.State:set_job_ids({})
        end
        if App.State and App.State.reset_job_tracking then
            App.State:reset_job_tracking()
        end
        App.Logger:append_localized("log_render_sequence_finished")
        ensure_ui_refresh()
    end

    local function abort_sequence(message, ...)
        finalize_rows_as("failed")
        if Render.sequence then
            Render.sequence.active = false
            Render.sequence = nil
        end
        if Render.stop_monitor then
            Render:stop_monitor()
        end
        local project = App.Core:getProject()
        if project then
            clear_pending_jobs(project)
        else
            if App.State and App.State.set_job_ids then
                App.State:set_job_ids({})
            end
        end
        if App.State and App.State.reset_job_tracking then
            App.State:reset_job_tracking()
        end
        if message and message ~= "" then
            if type(message) == "string" and message:match("^log_[%w_]+$") then
                App.Logger:append_localized(message, ...)
            else
                App.Logger:append(message)
            end
        end
        ensure_ui_refresh()
    end

    function Render:prepare_jobs()
        if not (self.sequence and self.sequence.rows and #self.sequence.rows > 0) then
            return nil
        end
        local project = App.Core:getProject()
        if not project then
            App.Logger:append_localized("log_project_missing")
            return nil
        end
        local seq = self.sequence
        local targetDir = seq.targetDir
        local baseName = seq.baseName
        local okEnv, envReason = ensure_render_env(project, targetDir)
        if not okEnv then
            local reasonText = localized_text(envReason or "log_start_render_failed")
            App.Logger:append_localized("log_render_env_failed", reasonText ~= "" and reasonText or "-")
            return nil
        end
        App.State:reset_job_tracking()
        local createdJobIds = {}
        for _, row in ipairs(seq.rows) do
            row.jobId = nil
            row.statusExtra = nil
            local _, waitingChanged = update_row_status(row, "waiting", nil)
            if waitingChanged then
                log_row_status(row, "waiting")
            end

            local settings = build_settings(row, targetDir, baseName)
            local okSettings = project:SetRenderSettings(settings)
            if not okSettings then
                App.Logger:append_localized("log_render_settings_failed", row.name or row.index or "?")
                update_row_status(row, "failed", nil)
                log_row_status(row, "failed")
                delete_job_list(project, createdJobIds)
                App.State:set_job_ids({})
                App.State:reset_job_tracking()
                return nil
            end

            local jobId = project:AddRenderJob()
            if not jobId then
                App.Logger:append_localized("log_add_job_failed", row.name or row.index or "?")
                update_row_status(row, "failed", nil)
                log_row_status(row, "failed")
                delete_job_list(project, createdJobIds)
                App.State:set_job_ids({})
                App.State:reset_job_tracking()
                return nil
            end

            row.jobId = jobId
            App.State:register_job_row(jobId, row)
            table.insert(createdJobIds, jobId)
            App.Logger:append_localized("log_job_added", row.name or jobId)
            local _, queuedChanged = update_row_status(row, "queued", nil)
            if queuedChanged then
                log_row_status(row, "queued")
            end
        end
        App.State:set_job_ids(createdJobIds)
        return createdJobIds
    end

    function Render:enqueue_rows(rows)
        local project = App.Core:getProject()
        if not project then
            App.Logger:append_localized("log_project_missing")
            return false
        end
        local targetDir = App.Helpers:trim(App.State.target_dir or "")
        if targetDir == "" then
            App.Logger:append_localized("log_target_dir_required")
            return false
        end
        local baseName = App.Helpers:trim(App.State.base_name or "")
        if baseName == "" then
            App.Logger:append_localized("log_base_name_required")
            return false
        end
        if not rows or #rows == 0 then
            App.Logger:append_localized("log_no_jobs_available")
            return false
        end

        App.State:reset_job_tracking()
        App.State:set_job_ids({})
        for _, row in ipairs(rows) do
            row.jobId = nil
            row.statusExtra = nil
            local _, keyChanged = update_row_status(row, "pending", nil)
            if keyChanged then
                log_row_status(row, "pending")
            end
        end

        self.sequence = {
            rows = rows,
            targetDir = targetDir,
            baseName = baseName,
            currentIndex = 0,
            active = false
        }
        App.Logger:append_localized("log_jobs_prepared", #rows)
        ensure_ui_refresh()
        return true
    end

    function Render:start()
        if not (self.sequence and self.sequence.rows and #self.sequence.rows > 0) then
            App.Logger:append_localized("log_no_jobs_available")
            return false
        end
        if self.sequence.active then
            App.Logger:append_localized("log_render_in_progress")
            return false
        end
        self.sequence.active = true
        App.Logger:append_localized("log_starting_sequential", #self.sequence.rows)
        local jobIds = self:prepare_jobs()
        if not jobIds or #jobIds == 0 then
            self.sequence.active = false
            App.Logger:append_localized("log_start_render_failed")
            finalize_rows_as("failed")
            ensure_ui_refresh()
            return false
        end
        local project = App.Core:getProject()
        local ok, started = pcall(function()
            return project:StartRendering(jobIds, true)
        end)
        if not ok then
            started = false
        end
        if not started then
            App.Logger:append_localized("log_start_render_failed")
            delete_job_list(project, jobIds)
            App.State:set_job_ids({})
            App.State:reset_job_tracking()
            finalize_rows_as("failed")
            ensure_ui_refresh()
            self.sequence.active = false
            return false
        end
        self:stop_monitor()
        self:start_monitor()
        App.Logger:append_localized("log_sequential_started")
        return true
    end

    function Render:start_monitor()
        self.monitor = self.monitor or {}
        self.monitor.active = true
        if App.UI and App.UI.start_status_timer then
            App.UI:start_status_timer()
        end
        return true
    end

    function Render:stop_monitor()
        if self.monitor then
            self.monitor.active = false
            self.monitor = nil
        end
        if App.UI and App.UI.stop_status_timer then
            App.UI:stop_status_timer()
        end
    end

    function Render:poll_job_status()
        if not self.monitor or not self.monitor.active then
            if App.UI and App.UI.stop_status_timer then
                App.UI:stop_status_timer()
            end
            return
        end

        local project = App.Core:getProject()
        if not project then
            abort_sequence("log_project_missing")
            return
        end

        local jobIds = (App.State and App.State.job_ids) or {}
        if not jobIds or #jobIds == 0 then
            if not project:IsRenderingInProgress() then
                complete_sequence()
            end
            return
        end

        local remaining = {}
        for _, jobId in ipairs(jobIds) do
            local row = App.State:get_row_by_job(jobId)
            local statusInfo
            local ok, result = pcall(function()
                return project:GetRenderJobStatus(jobId)
            end)
            if ok then
                statusInfo = result
            end
            local statusKey, progressText = normalize_job_status(statusInfo)
            if row then
                local _, keyChanged = update_row_status(row, statusKey, progressText)
                if keyChanged then
                    log_row_status(row, statusKey)
                end
            end

            if statusKey == "done" then
                delete_render_job(project, jobId)
                if row then
                    row.jobId = nil
                end
            elseif statusKey == "failed" then
                delete_render_job(project, jobId)
                App.Logger:append_localized("log_job_failed_cancel_rest", row and row.name or tostring(jobId))
                abort_sequence("log_detected_failure_stop")
                return
            else
                table.insert(remaining, jobId)
            end
        end

        App.State:set_job_ids(remaining)
        ensure_ui_refresh()

        if #remaining == 0 then
            complete_sequence()
            return
        end

        if not project:IsRenderingInProgress() then
            App.Logger:append_localized("log_render_interrupted_stop")
            abort_sequence("log_render_interrupted")
        end
    end

    App.Render = Render
end

--
-- 8. UI 模块 (App.UI)
--
do
    local UI = {
        win = nil,
        items = nil,
        statusTimer = nil,
        _timeoutHooked = false,
        _previousTimeoutHandler = nil,
        statusLocaleKeys = {
            pending = "status_pending",
            queued = "status_queued",
            waiting = "status_waiting",
            rendering = "status_rendering",
            done = "status_done",
            failed = "status_failed",
            unknown = "status_unknown"
        }
    }

    local function tr(key)
        return App.Locale and App.Locale:t(key) or key
    end

    function UI:run_with_loading(action)
        if type(action) ~= "function" then
            return
        end
        local dispatcher = App.Core.dispatcher
        local ui = App.Core.ui
        if not (dispatcher and ui) then
            return action()
        end
        local win = dispatcher:AddWindow({
            ID = "LoadingWindow",
            WindowTitle = string.format("%s - Loading", App.Config.SCRIPT_NAME),
            Geometry = {
                App.Config.LOADING_X_CENTER,
                App.Config.LOADING_Y_CENTER,
                App.Config.LOADING_WINDOW_WIDTH,
                App.Config.LOADING_WINDOW_HEIGHT
            },
        }, ui:VGroup{
            Weight = 1,
            Alignment = { AlignHCenter = true, AlignVCenter = true },
            ui:Label{
                ID = "LoadingLabel",
                Text = tr("loading_updates"),
                Alignment = { AlignHCenter = true, AlignVCenter = true },
                WordWrap = true,
            }
        })
        if not win then
            return action()
        end
        local items = win:GetItems()
        if items and items.LoadingLabel then
            items.LoadingLabel.Text = tr("loading_updates")
        end
        win:Show()
        local ok, result = pcall(action)
        if items and items.LoadingLabel then
            items.LoadingLabel.Text = tr("loading_complete")
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

    function UI:ensure_status_timer()
        local ui = App.Core.ui
        if not ui then
            return nil
        end
        if not self.statusTimer then
            local ok, timer = pcall(function()
                return ui:Timer{
                    ID = "RenderStatusTimer",
                    Interval = 1000,
                    SingleShot = false,
                    TimerType = "CoarseTimer"
                }
            end)
            if ok then
                self.statusTimer = timer
            end
        end
        if (not self._timeoutHooked) and App.Core.dispatcher then
            local dispatcher = App.Core.dispatcher
            local previousHandler = dispatcher.On.Timeout
            dispatcher.On.Timeout = function(ev)
                local handled
                if previousHandler then
                    handled = previousHandler(ev)
                end
                local who = ev and (ev.who or ev.ID or ev.Name or ev.TimerID or ev.TimerId)
                if who == "RenderStatusTimer" then
                    if App.Render and App.Render.poll_job_status then
                        App.Render:poll_job_status()
                    end
                    return true
                end
                return handled
            end
            self._timeoutHooked = true
            self._previousTimeoutHandler = previousHandler
        end
        return self.statusTimer
    end

    function UI:start_status_timer()
        local timer = self:ensure_status_timer()
        if timer and timer.Start then
            pcall(function() timer:Start() end)
        end
    end

    function UI:stop_status_timer()
        if self.statusTimer and self.statusTimer.Stop then
            pcall(function() self.statusTimer:Stop() end)
        end
    end

    function UI:get_row_status_text(row)
        local statusKey = row and row.statusKey or "pending"
        if not self.statusLocaleKeys[statusKey] then
            statusKey = "unknown"
        end
        local text = tr(self.statusLocaleKeys[statusKey])
        if row and row.statusExtra and row.statusExtra ~= "" then
            text = string.format("%s (%s)", text, row.statusExtra)
        end
        return text
    end

    function UI:build_window_content()
        local ui = App.Core.ui
        return ui.VGroup{
            Weight = 1,
            ui.HGroup{
                Weight = 0,
                ui.VGroup{
                    ui.Label{ Text = "Marks", Alignment = { AlignHCenter = true, AlignVCenter = true },},
                    ui.HGroup{
                        ui.Button{ ID = "AddMarkBtn", Text = tr("add_mark"),  },
                        ui.Button{
                            ID = "ClearMarksBtn",
                            Text = tr("clear_marks"),
                            Weight = 0,
                        },
                    },  
                },
                ui.VGroup{
                    ui.Label{ ID = "IntervalLabel", Text = tr("interval_label"),Alignment = { AlignHCenter = true, AlignVCenter = true },  },
                    ui.LineEdit{ ID = "IntervalInput", Text = tostring(App.State.interval_seconds), }
                },
                ui.VGroup{
                    ui.Label{ ID = "CountLabel", Text = tr("count_label"), Alignment = { AlignHCenter = true, AlignVCenter = true },},
                    ui.SpinBox{ ID = "CountInput", Minimum = 2, Maximum = 200, Value = App.State.mark_count }
                },
                ui.VGroup{
                    ui.Label{ ID = "BaseNameLabel", Text = tr("base_name_label"), Alignment = { AlignHCenter = true, AlignVCenter = true }, },
                    ui.LineEdit{
                        ID = "BaseNameInput",
                        Text = App.State.base_name or "Batch",
                        Events = { EditingFinished = true },
                        Weight = 1,
                    }
                    
                },
            },
            ui.HGroup{
                Weight = 0.65,
                ui.Tree{
                    ID = "RenderTree",
                    Weight = 1,
                    ColumnCount = 5,
                    AlternatingRowColors = true,
                    RootIsDecorated = false,
                    HeaderHidden = false,
                }
            },
            ui.HGroup{
                Weight = 0,
                ui.LineEdit{ ID = "TargetDirInput", ReadOnly = true, PlaceholderText = tr("target_placeholder"), Weight = 1 },
                ui.Button{ ID = "ChoosePathBtn", Text = tr("browse"), Weight = 0 },
            },
            ui.HGroup{
                Weight = 0,
                ui.Button{ ID = "GetQueueBtn", Text = tr("get_queue") },
                ui.Button{ ID = "StartRenderBtn", Text = tr("start_render"),  },
            },
            ui.VGroup{
                Weight = 0.35,
                ui.TextEdit{ ID = "LogView", ReadOnly = true, },
            },
            ui.Label{
                ID = "UpdateStatusLabel",
                Text = "",
                Weight = 0,
                WordWrap = true,
                Alignment = { AlignHCenter = true, AlignVCenter = true },
                Visible = false,
                StyleSheet = "color:#d9534f; font-weight:bold;",
            },
            ui.Button{
                ID = "DonationButton",
                Text = tr("donation_button"),
                Flat = true,
                Font = ui.Font({ PixelSize = 12, StyleName = "Bold" }),
                Alignment = { AlignHCenter = true, AlignVCenter = true },
                TextColor = { 1, 1, 1, 1 },
                BackgroundColor = { 1, 1, 1, 0 },
                Weight = 0,
            },
            ui.HGroup{
                Weight = 0,
                ui.CheckBox{ ID = "LangEnCheckBox", Text = tr("lang_en_label"), Checked = (App.State.language ~= "zh"), Weight = 0 },
                ui.CheckBox{ ID = "LangCnCheckBox", Text = tr("lang_cn_label"), Checked = (App.State.language == "zh"), Weight = 0 },
            },
        }
    end

    function UI:create_main_window()
        if not App.Core.initialized then
            return nil
        end
        local win = App.Core.dispatcher:AddWindow({
            ID = "BatchRenderWin",
            WindowTitle = string.format("%s %s", tr("app_title"), App.Config.SCRIPT_VERSION),
            Geometry = {App.Config.X_CENTER, App.Config.Y_CENTER, App.Config.WINDOW_WIDTH, App.Config.WINDOW_HEIGHT},
            Spacing = 6,
            Margin = 8,
            StyleSheet = "*{font-size:14px;}"
        }, self:build_window_content())
        self.win = win
        if win then
            self.items = win:GetItems()
            self:sync_inputs()
            self:update_language_texts()
        end
        return win
    end

    function UI:sync_inputs()
        if not self.items then return end
        if self.items.TargetDirInput then
            self.items.TargetDirInput.Text = App.State.target_dir or ""
        end
        if self.items.BaseNameInput then
            self.items.BaseNameInput.Text = App.State.base_name or ""
        end
        if self.items.LangEnCheckBox then
            self.items.LangEnCheckBox.Checked = (App.State.language ~= "zh")
        end
        if self.items.LangCnCheckBox then
            self.items.LangCnCheckBox.Checked = (App.State.language == "zh")
        end
    end

    function UI:update_language_texts()
        if not self.items then return end
        local items = self.items

        if items.IntervalLabel then items.IntervalLabel.Text = tr("interval_label") end
        if items.CountLabel then items.CountLabel.Text = tr("count_label") end
        if items.BaseNameLabel then items.BaseNameLabel.Text = tr("base_name_label") end

        if items.AddMarkBtn then items.AddMarkBtn.Text = tr("add_mark") end
        if items.GetQueueBtn then items.GetQueueBtn.Text = tr("get_queue") end
        if items.StartRenderBtn then items.StartRenderBtn.Text = tr("start_render") end
        if items.ClearMarksBtn then items.ClearMarksBtn.Text = tr("clear_marks") end
        if items.ChoosePathBtn then items.ChoosePathBtn.Text = tr("browse") end
        if items.TargetDirInput then
            items.TargetDirInput.PlaceholderText = tr("target_placeholder")
        end

        if items.LangEnCheckBox then
            items.LangEnCheckBox.Text = tr("lang_en_label")
            items.LangEnCheckBox.Checked = (App.State.language ~= "zh")
        end
        if items.LangCnCheckBox then
            items.LangCnCheckBox.Text = tr("lang_cn_label")
            items.LangCnCheckBox.Checked = (App.State.language == "zh")
        end
        if items.DonationButton then
            items.DonationButton.Text = tr("donation_button")
        end

        if items.RenderTree and items.RenderTree.SetHeaderLabels then
            items.RenderTree:SetHeaderLabels({
                tr("tree_header_index"),
                tr("tree_header_start"),
                tr("tree_header_end"),
                tr("tree_header_name"),
                tr("tree_header_status")
            })
        end

        if items.RenderTree and items.RenderTree.SetColumnWidth then
            items.RenderTree:SetColumnWidth(0, 50)   -- 序号
            items.RenderTree:SetColumnWidth(1, 100)  -- 开始时间
            items.RenderTree:SetColumnWidth(2, 100)  -- 结束时间
            items.RenderTree:SetColumnWidth(3, 250)  -- 名称
            items.RenderTree:SetColumnWidth(4, 100)  -- 状态
        end
        if self.win then
            local title = string.format("%s %s", tr("app_title"), App.Config.SCRIPT_VERSION)
            if self.win.SetWindowTitle then
                self.win:SetWindowTitle(title)
            else
                self.win.WindowTitle = title
            end
        end
        self:refresh_tree()
        self:update_update_status_label()
    end

    function UI:update_update_status_label()
        if not self.items or not self.items.UpdateStatusLabel then
            return
        end
        local label = self.items.UpdateStatusLabel
        local info = App.State.update_info
        if type(info) ~= "table" then
            label.Text = ""
            label.Visible = false
            return
        end
        local langKey = (App.State.language == "zh") and "zh" or "en"
        local text = info[langKey] or info.en or info.zh or ""
        text = App.Helpers and App.Helpers:trim(text) or (text or "")
        if text == "" then
            label.Text = ""
            label.Visible = false
            return
        end
        label.Text = text
        label.Visible = true
    end

    function UI:refresh_tree()
        if not self.items or not self.items.RenderTree then return end
        local tree = self.items.RenderTree
        if tree.Clear then tree:Clear() end
        for _, row in ipairs(App.State:get_tree_rows()) do
            local item = tree.NewItem and tree:NewItem() or (App.Core.ui.TreeItem and App.Core.ui.TreeItem({})) or nil
            if item then
                item.Text[0] = tostring(row.index)
                item.Text[1] = row.startTimecode or ""
                item.Text[2] = row.endTimecode or ""
                item.Text[3] = row.name or ""
                item.Text[4] = self:get_row_status_text(row)
                if tree.AddTopLevelItem then
                    tree:AddTopLevelItem(item)
                end
            end
        end
    end

    function UI:jump_to_row_index(index)
        local row = App.State:get_row_by_index(index)
        if not row then
            return
        end
        App.Timeline:jump_to_row(row)
    end

    function UI:bind_events()
        if not self.win or not self.items then return end
        local win = self.win
        local items = self.items

        win.On.BatchRenderWin.Close = function()
            App.Timeline:cleanup_script_markers()
            App.Timeline:clear_mark_range()
            if App.Render and App.Render.stop_monitor then
                App.Render:stop_monitor()
            end
            UI:stop_status_timer()
            if App.Settings and App.Settings.save then
                App.Settings:save()
            end
            if App.Helpers and App.Helpers.remove_dir and App.Config and App.Config.TEMP_DIR then
                App.Helpers:remove_dir(App.Config.TEMP_DIR)
            end
            App.Logger:append_localized("log_window_closed")
            App.Core.dispatcher:ExitLoop()
        end

        win.On.AddMarkBtn.Clicked = function()
            local interval = tonumber(items.IntervalInput.Text)
            local count = items.CountInput.Value
            App.State.interval_seconds = interval or App.Config.DEFAULT_INTERVAL_SECONDS
            App.State.mark_count = count or App.Config.DEFAULT_MARK_COUNT
            App.Timeline:add_markers(App.State.interval_seconds, App.State.mark_count)
        end

        if win.On.ClearMarksBtn then
            win.On.ClearMarksBtn.Clicked = function()
                App.Timeline:cleanup_script_markers()
            end
        end

        win.On.CountInput.ValueChanged = function()
            App.State.mark_count = items.CountInput.Value
        end

        if win.On.IntervalInput then
            win.On.IntervalInput.EditingFinished = function()
                App.State.interval_seconds = tonumber(items.IntervalInput.Text) or App.Config.DEFAULT_INTERVAL_SECONDS
            end
        end

        win.On.ChoosePathBtn.Clicked = function()
            local fusion = App.Core.fusion
            if not (fusion and fusion.RequestDir) then
                App.Logger:append_localized("log_dir_picker_unavailable")
                return
            end
            local startDir = App.State.target_dir
            if (not startDir or startDir == "") and fusion.MapPath then
                startDir = fusion:MapPath("UserData:/")
            end
            local selected = fusion:RequestDir((startDir ~= "" and startDir or nil))
            if selected and selected ~= "" then
                App.State:set_target_dir(selected)
                UI:sync_inputs()
                App.Logger:append_localized("log_dir_selected", selected)
            end
        end

        if win.On.BaseNameInput then
            win.On.BaseNameInput.EditingFinished = function()
                App.State:set_base_name(items.BaseNameInput.Text or "")
                UI:sync_inputs()
                UI:refresh_tree()
            end
        end

        win.On.GetQueueBtn.Clicked = function()
            local segments = App.Timeline:build_segments()
            if segments then
                App.State:set_tree_rows(segments)
                UI:refresh_tree()
            end
        end

        win.On.StartRenderBtn.Clicked = function()
            local rows = App.State:get_tree_rows()
            if not rows or #rows == 0 then
                App.Logger:append_localized("log_queue_required")
                return
            end
            local ready = App.Render:enqueue_rows(rows)
            UI:refresh_tree()
            if ready then
                App.Render:start()
            end
        end

        if win.On.RenderTree then
            win.On.RenderTree.ItemClicked = function()
                local tree = items.RenderTree
                local current = tree and tree:CurrentItem()
                if not current then
                    return
                end
                local idx = tonumber(current.Text[0])
                if idx then
                    UI:jump_to_row_index(idx)
                end
            end
        end

        local function apply_language(lang)
            if lang ~= "zh" then
                lang = "en"
            end
            if App.State.language ~= lang then
                App.State.language = lang
                App.Locale:set_language(lang)
                UI:sync_inputs()
                UI:update_language_texts()
                if App.Logger and App.Logger.refresh_language then
                    App.Logger:refresh_language()
                end
                if App.Settings and App.Settings.save then
                    App.Settings:save()
                end
            else
                UI:sync_inputs()
            end
        end

        if win.On.LangEnCheckBox then
            win.On.LangEnCheckBox.Clicked = function()
                if items.LangEnCheckBox then
                    items.LangEnCheckBox.Checked = true
                end
                if items.LangCnCheckBox then
                    items.LangCnCheckBox.Checked = false
                end
                apply_language("en")
            end
        end

        if win.On.LangCnCheckBox then
            win.On.LangCnCheckBox.Clicked = function()
                if items.LangCnCheckBox then
                    items.LangCnCheckBox.Checked = true
                end
                if items.LangEnCheckBox then
                    items.LangEnCheckBox.Checked = false
                end
                apply_language("zh")
            end
        end

        if win.On.DonationButton then
            win.On.DonationButton.Clicked = function()
                if items.LangCnCheckBox and items.LangCnCheckBox.Checked then
                    if App.Helpers and App.Helpers.openExternalUrl then
                        App.Helpers:openExternalUrl(SCRIPT_TAOBAO_URL)
                    end
                    return
                end
                App.Helpers:openExternalUrl(SCRIPT_KOFI_URL)
            end
        end

    end

    App.UI = UI
end

--
-- 9. 主流程
--
local function main()

    if App.Update then
        App.UI:run_with_loading(function()
            App.Update:check_for_updates()
        end)
    end

    if not App.Core.initialized then
        print("DaVinci Batch Render 初始化失败")
        return
    end

    local win = App.UI:create_main_window()
    if not win then
        print("无法创建主窗口")
        return
    end

    App.UI:refresh_tree()
    App.UI:bind_events()

    win:Show()
    App.Core.dispatcher:RunLoop()
end

main()
