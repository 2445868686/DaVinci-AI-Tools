
local SCRIPT_NAME = "DaVinci Sub Editor"
local SCRIPT_VERSION = "1.0.5"
local SCRIPT_AUTHOR = "HEIBA"
print(string.format("%s | %s | %s", SCRIPT_NAME, SCRIPT_VERSION, SCRIPT_AUTHOR))
local SCRIPT_KOFI_URL = "https://ko-fi.com/heiba"
local SCRIPT_BILIBILI_URL = "https://space.bilibili.com/385619394"
local SCRIPT_PAYPAL_URL ="https://paypal.me/heibashop"

local App = {
    Utils = {},
    Storage = {},
    Services = {
        Azure = {},
        OpenAIFormat = {},
        GLM = {},
        Parallel = {},
    },
    Subtitle = {},
    Translate = {},
    UI = {
        Events = {},
        Windows = {},
    },
    Cache = {},
}

local Utils = App.Utils
local Storage = App.Storage
local Services = App.Services
local Subtitle = App.Subtitle
local Translate = App.Translate
local UI = App.UI
local Azure = Services.Azure
local OpenAIService = Services.OpenAIFormat
local GLMService = Services.GLM
local ParallelServices = Services.Parallel
local SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
local WINDOW_WIDTH, WINDOW_HEIGHT = 550, 600
local X_CENTER = math.floor((SCREEN_WIDTH - WINDOW_WIDTH ) / 2)
local Y_CENTER = math.floor((SCREEN_HEIGHT - WINDOW_HEIGHT) / 2)
local LOADING_WINDOW_WIDTH, LOADING_WINDOW_HEIGHT = 220, 120
local LOADING_X = math.floor((SCREEN_WIDTH - LOADING_WINDOW_WIDTH) / 2)
local LOADING_Y = math.floor((SCREEN_HEIGHT - LOADING_WINDOW_HEIGHT) / 2)
local DONATION_QR_BASE64 = [[
111
]]

local resolve = resolve or Resolve()
if not resolve then
    print("Resolve API 不可用")
    return
end

local fusion = resolve:Fusion()
if not fusion then
    print("Fusion 对象不可用")
    return
end

function Utils.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

local ui = fusion.UIManager
local disp = bmd.UIDispatcher(ui)
local json = require('dkjson')

local TRANSLATE_PROVIDER_AZURE_LABEL = "Microsoft"
local TRANSLATE_PROVIDER_GL_LABEL = "GLM-4-Flash       ( Free AI  )"
local TRANSLATE_PROVIDER_OPENAI_LABEL = "OpenAI Format  ( API Key )"
local TRANSLATE_PROVIDER_LIST = {
    TRANSLATE_PROVIDER_AZURE_LABEL,
    TRANSLATE_PROVIDER_GL_LABEL,
    TRANSLATE_PROVIDER_OPENAI_LABEL,
}
function Translate.isSupportedProvider(label)
    for _, value in ipairs(TRANSLATE_PROVIDER_LIST) do
        if value == label then
            return true
        end
    end
    return false
end
local DEFAULT_TRANSLATE_CONCURRENCY = 5
local TRANSLATE_CONCURRENCY_OPTIONS = {
    { labelKey = "concurrency_option_low", value = 1 },
    { labelKey = "concurrency_option_standard", value = 5 },
    { labelKey = "concurrency_option_high", value = 15 },
}
local TRANSLATE_CONTEXT_WINDOW = 1
local AZURE_DEFAULT_BASE_URL = "https://api.cognitive.microsofttranslator.com"
local AZURE_DEFAULT_REGION = ""
local AZURE_FALLBACK_REGION = "eastus"
local AZURE_TIMEOUT = 15
local AZURE_REGISTER_URL = "https://azure.microsoft.com/"
local GLM_API_URL = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
local GLM_MODEL = "GLM-4-Flash"
local GLM_MAX_RETRY = 3
local GLM_TIMEOUT = 30
local AZURE_SUPABASE_PROVIDER = "AZURE"
local GLM_SUPABASE_PROVIDER = "BIGMODEL"
local OPENAI_FORMAT_DEFAULT_BASE_URL = "https://api.openai.com"
local OPENAI_FORMAT_DEFAULT_TEMPERATURE = 0.3
local OPENAI_FORMAT_TIMEOUT = 30
local DEFAULT_OPENAI_MODELS = {}

local TRANSLATE_PREFIX_PROMPT = [[
You are a professional {target_lang} subtitle translation engine.
Task: Translate ONLY the sentence shown after the tag <<< Sentence >>> into {target_lang}.
---
]]

local TRANSLATE_SYSTEM_PROMPT = [[Strict rules you MUST follow:

1. Keep every proper noun, personal name, brand, product name, code snippet, file path, URL, and any other non-translatable element EXACTLY as it appears. Do NOT transliterate or translate these.

2. Follow subtitle style: short, concise, natural, and easy to read.

3. Output ONLY the translated sentence. No tags, no explanations, no extra spaces.
]]

local TRANSLATE_SUFFIX_PROMPT = [[
---
Note:
- The messages with role=assistant are only CONTEXT; do NOT translate them or include them in your output.
- Translate ONLY the line after <<< Sentence >>>
]]

local OPENAI_DEFAULT_SYSTEM_PROMPT = TRANSLATE_SYSTEM_PROMPT

local LANG_CODE_MAP = {
    ["中文（普通话）"] = "zh-Hans",
    ["中文（粤语）"] = "yue",
    ["English"] = "en",
    ["Japanese"] = "ja",
    ["Korean"] = "ko",
    ["Spanish"] = "es",
    ["Portuguese"] = "pt",
    ["French"] = "fr",
    ["Indonesian"] = "id",
    ["German"] = "de",
    ["Russian"] = "ru",
    ["Italian"] = "it",
    ["Arabic"] = "ar",
    ["Turkish"] = "tr",
    ["Ukrainian"] = "uk",
    ["Vietnamese"] = "vi",
    ["Uzbek"] = "uz",
    ["Dutch"] = "nl",
}

local LANG_LABELS = {
    "中文（普通话）",
    "中文（粤语）",
    "English",
    "Japanese",
    "Korean",
    "Spanish",
    "Portuguese",
    "French",
    "Indonesian",
    "German",
    "Russian",
    "Italian",
    "Arabic",
    "Turkish",
    "Ukrainian",
    "Vietnamese",
    "Uzbek",
    "Dutch",
}

Translate.secretCache = {}


App.State = {
    entries = {},
    fps = 24.0,
    startFrame = 0,
    timeline = nil,
    resolve = resolve,
    selectedIndex = nil,
    activeTrackIndex = nil,
    language = "en",
    lastStatusKey = nil,
    lastStatusArgs = nil,
    findQuery = "",
    findMatches = nil,
    findIndex = nil,
    currentMatchPos = nil,
    suppressTreeSelection = false,
    currentMatchHighlight = nil,
    stickyHighlights = {},
    highlightedRows = {},
    updateInfo = nil,
    translate = {
        entries = {},
        populated = false,
        busy = false,
        selectedIndex = nil,
        provider = TRANSLATE_PROVIDER_AZURE_LABEL,
        targetLabel = nil,
        concurrency = DEFAULT_TRANSLATE_CONCURRENCY,
        totalTokens = 0,
        lastStatusKey = "idle",
        lastStatusArgs = nil,
    },
}

local state = App.State

state.openaiFormat = {
    baseUrl = OPENAI_FORMAT_DEFAULT_BASE_URL,
    apiKey = "",
    temperature = OPENAI_FORMAT_DEFAULT_TEMPERATURE,
    models = Utils.deepCopy(DEFAULT_OPENAI_MODELS),
    customModels = {},
    selectedIndex = 1,
    systemPrompt = OPENAI_DEFAULT_SYSTEM_PROMPT,
}
state.azure = {
    apiKey = "",
    region = AZURE_DEFAULT_REGION,
    baseUrl = AZURE_DEFAULT_BASE_URL,
}
math.randomseed(os.time() + tonumber(tostring({}):sub(8), 16))
state.sessionCode = string.format("%04X", math.random(0, 0xFFFF))

local findHighlightColor = { R = 0.40, G = 0.40, B = 0.40, A = 0.60 } -- 查找命中 / 替换后标记
local transparentColor = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 } -- 透明，真正清空
local editorProgrammatic = false
local translateEditorProgrammatic = false
local languageProgrammatic = false
local unpack = table.unpack or unpack
local configDir
local settingsFile

local uiText = {
    cn = {
        find_next_button = "下一个",
        find_previous_button = "上一个",
        all_replace_button = "全部替换",
        single_replace_button = "替换",
        refresh_button = "加载时间线字幕",
        update_button = "更新时间线字幕",
        find_placeholder = "查找文本",
        replace_placeholder = "替换文本",
        editor_placeholder = "在此编辑选中的字幕",
        tree_headers = { "#", "开始/结束", "字幕" },
        translate_tree_headers = { "#", "开始/结束", "字幕", "翻译" },
        lang_cn = "简体中文",
        lang_en = "EN",
        tabs = { "编辑", "翻译", "设置" },
        donation = "☕用一杯咖啡为创意充电☕",
        copyright = " © 2025, 版权所有 " .. SCRIPT_AUTHOR,
        translate_provider_label = "服务商",
        translate_target_label = "目标语言",
        translate_provider_placeholder = "选择服务商",
        translate_target_placeholder = "选择目标语言",
        translate_trans_button = "开始翻译",
        translate_update_button = "译文导入时间线",
        translate_selected_button = "翻译选中行",
        translate_editor_placeholder = "在此编辑译文内容",
        openai_config_label = "OpenAI Format",
        openai_config_button = "配置",
        azure_config_label = "Azure API",
        azure_config_button = "配置",
        azure_config_window_title = "Azure API",
        azure_config_header = "填写 Azure API 信息",
        azure_region_label = "区域",
        azure_api_key_label = "密钥",
        azure_confirm_button = "确定",
        azure_register_button = "注册",
        concurrency_label = "模式",
        concurrency_option_low = "低速",
        concurrency_option_standard = "标准",
        concurrency_option_high = "高速",
        openai_config_window_title = "OpenAI Format API",
        openai_config_header = "填写 API 信息",
        openai_model_label = "模型",
        openai_model_name_label = "模型名称",
        openai_base_url_label = "* Base URL",
        openai_api_key_label = "* API Key",
        openai_temperature_label = "温度",
        system_prompt_label = "* 系统提示词",
        openai_verify_button = "验证",
        openai_add_button = "新增模型",
        openai_delete_button = "删除模型",
        openai_close_button = "关闭",
        openai_new_model_display_label = "* 显示名称",
        openai_new_model_name_label = "* 模型 ID",
        openai_add_model_title = "添加 OpenAI 兼容模型",
        openai_status_ready = "",
        openai_delete_builtin_warning = "系统默认模型不可删除",
        openai_verify_success = "模型验证成功",
        openai_verify_failed = "模型验证失败：%s",
        openai_add_success = "模型已添加",
        openai_add_duplicate = "模型已存在",
        openai_missing_fields = "请填写全部必填项",
        openai_delete_success = "模型已删除",
    },
    en = {
        find_next_button = "Next",
        find_previous_button = "Previous",
        all_replace_button = "All Replace",
        single_replace_button = "Replace",
        refresh_button = "Load Timeline Subtitles",
        update_button = "Update Timeline Subtitles",
        find_placeholder = "Find text",
        replace_placeholder = "Replace with",
        editor_placeholder = "Edit selected subtitle here",
        tree_headers = { "#", "Start/End", "Subtitle" },
        translate_tree_headers = { "#", "Start/End", "Original", "Translation" },
        lang_cn = "简体中文",
        lang_en = "EN",
        tabs = { "Edit", "Translate", "Settings" },
        donation = "☕ Fuel creativity with a coffee ☕",
        copyright = " © 2025, copyright by " .. SCRIPT_AUTHOR,
        translate_provider_label = "Provider",
        translate_target_label = "To",
        translate_provider_placeholder = "Select provider",
        translate_target_placeholder = "Select target language",
        translate_trans_button = "Translate",
        translate_update_button = "Import Translation to Timeline",
        translate_selected_button = "Translate Selected",
        translate_editor_placeholder = "Edit translation here",
        openai_config_label = "OpenAI Format",
        openai_config_button = "Config",
        azure_config_label = "Azure API",
        azure_config_button = "Config",
        azure_config_window_title = "Azure API",
        azure_config_header = "Azure API",
        azure_region_label = "Region",
        azure_api_key_label = "Key",
        azure_confirm_button = "OK",
        azure_register_button = "Register",
        concurrency_label = "Mode",
        concurrency_option_low = "Low",
        concurrency_option_standard = "Medium",
        concurrency_option_high = "High",
        openai_config_window_title = "OpenAI Format API",
        openai_config_header = "Fill API Info",
        openai_model_label = "Model",
        openai_model_name_label = "Model ID",
        openai_base_url_label = "* Base URL",
        openai_api_key_label = "* API Key",
        openai_temperature_label = "* Temperature",
        system_prompt_label = "* System Prompt",
        openai_verify_button = "Verify",
        openai_add_button = "Add Model",
        openai_delete_button = "Delete Model",
        openai_close_button = "Close",
        openai_new_model_display_label = "* Display Name",
        openai_new_model_name_label = "* Model Name",
        openai_add_model_title = "Add OpenAI Format Model",
        openai_status_ready = "",
        openai_delete_builtin_warning = "Built-in models cannot be removed",
        openai_verify_success = "Model verified successfully",
        openai_verify_failed = "Model verification failed: %s",
        openai_add_success = "Model added",
        openai_add_duplicate = "Model already exists",
        openai_missing_fields = "Fill in all required fields",
        openai_delete_success = "Model removed",
    }
}

local messages = {
    current_total = { cn = "当前字幕数量：%d", en = "Total subtitles: %d" },
    loaded_count = { cn = "已加载 %d 条字幕", en = "Loaded %d subtitles" },
    enter_find_text = { cn = "请输入查找文本", en = "Enter text to find" },
    no_find_results = { cn = "未找到匹配字幕", en = "No matching subtitles" },
    find_match_count = { cn = "匹配 %d 条字幕", en = "%d subtitles matched" },
    replace_no_find = { cn = "请先填写查找文本", en = "Enter text to replace" },
    no_replace = { cn = "未替换任何字幕", en = "No replacements made" },
    replace_done = { cn = "完成替换，共 %d 处", en = "Replaced %d occurrence(s)" },
    no_entries_update = { cn = "没有字幕可更新", en = "No subtitles to update" },
    write_failed = { cn = "写入 SRT 失败", en = "Failed to write SRT" },
    import_failed = { cn = "导入 SRT 失败", en = "Failed to import SRT" },
    updated_success = { cn = "字幕已更新至时间线", en = "Timeline subtitles updated" },
    jump_failed = { cn = "无法跳转到指定时间码", en = "Unable to jump to timecode" },
    jump_success = { cn = "跳转至 %s", en = "Jumped to %s" },
    no_timeline = { cn = "未找到活动项目/时间线", en = "No active project or timeline" },
    cannot_read_subtitles = { cn = "无法读取字幕", en = "Unable to read subtitles" },
    create_srt_folder_failed = { cn = "无法创建 srt 媒体池文件夹", en = "Unable to create 'srt' media pool folder" },
    append_failed = { cn = "无法将字幕追加至时间线", en = "Failed to append subtitles to timeline" },
    match_progress = { cn = "匹配项：第 %d 个结果，共 %d 个结果", en = "Match: result %d of %d" },
    matches_rows_occ = { cn = "包含条目：%d 条；出现次数：%d 处", en = "Rows: %d; Occurrences: %d" },

}

local translateStatusTemplates = {
    idle = { cn = "等待翻译任务", en = "Ready to translate" },
    copying = { cn = "正在复制字幕...", en = "Copying subtitles..." },
    no_entries = { cn = "没有可翻译的字幕", en = "No subtitles to translate" },
    fetching_key = { cn = "正在获取翻译密钥...", en = "Fetching translator credential..." },
    progress = { cn = "翻译中 %d/%d  令牌:%d", en = "Translating %d/%d  Tokens:%d" },
    success = { cn = "翻译完成，共 %d 条字幕。令牌:%d", en = "Translation finished: %d lines. Tokens:%d" },
    failed = { cn = "翻译失败：%s", en = "Translation failed: %s" },
    updating = { cn = "正在生成并导入 SRT...", en = "Generating and importing SRT..." },
    updated = { cn = "译文已导入时间线", en = "Translated subtitles imported" },
}

local translateErrorMessages = {
    missing_key = { cn = "无法获取服务密钥，请稍后重试", en = "Unable to fetch service credential. Please try again later." },
    request_failed = { cn = "网络请求失败，请检查网络", en = "Network request failed. Please check your connection." },
    decode_failed = { cn = "服务响应解析失败", en = "Failed to decode service response." },
    translation_failed = { cn = "翻译失败，请稍后重试", en = "Translation failed. Please try again." },
    empty_translation = { cn = "服务返回空结果", en = "The service returned an empty result." },
    provider_not_supported = { cn = "当前服务商暂不支持", en = "The selected provider is not supported yet." },
    no_timeline = { cn = "未找到有效的时间线", en = "No active timeline available." },
    invalid_response = { cn = "服务响应内容无效", en = "Service returned an invalid payload." },
    no_selection = { cn = "请先在列表中选择需要翻译的行", en = "Select a row to translate first." },
    openai_missing_key = { cn = "请在设置中填写 OpenAI API Key", en = "Enter the OpenAI API key in settings." },
    openai_missing_base = { cn = "请在设置中填写 OpenAI Base URL", en = "Enter the OpenAI Base URL in settings." },
    openai_missing_model = { cn = "请选择有效的 OpenAI 模型", en = "Select a valid OpenAI model." },
    openai_parallel_failed = { cn = "并发请求失败，已退回串行模式", en = "Parallel requests failed; falling back to sequential mode." },
}




local SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
local SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"
local SUPABASE_TIMEOUT = 5

function Utils.trim(s)
    if type(s) ~= "string" then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utils.urlEncode(str)
    if not str then
        return ""
    end
    return tostring(str):gsub("([^%w%-_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

Services.HttpClient = Services.HttpClient or {}
local httpClient = Services.HttpClient

function Storage.sanitizeOpenAIModelEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local name = Utils.trim(entry.name or entry.model or "")
    if name == "" then
        return nil
    end
    local display = Utils.trim(entry.display or entry.title or entry.label or name)
    local cleaned = {
        name = name,
        display = display ~= "" and display or name,
        builtin = entry.builtin == true,
    }
    return cleaned
end

function Storage.sortModelList(list)
    table.sort(list, function(a, b)
        local ad = a.display or a.name or ""
        local bd = b.display or b.name or ""
        if (a.builtin and not b.builtin) then
            return true
        end
        if (b.builtin and not a.builtin) then
            return false
        end
        if ad == bd then
            return (a.name or "") < (b.name or "")
        end
        return ad < bd
    end)
end

function Storage.ensureOpenAIModelList(config)
    if type(config) ~= "table" then
        return
    end
    local models = {}
    local indexByName = {}

    local function append(entry, builtinFlag)
        local sanitized = Storage.sanitizeOpenAIModelEntry(entry)
        if not sanitized then
            return
        end
        if indexByName[sanitized.name] then
            return
        end
        sanitized.builtin = builtinFlag or sanitized.builtin == true
        table.insert(models, sanitized)
        indexByName[sanitized.name] = sanitized
    end

    for _, entry in ipairs(DEFAULT_OPENAI_MODELS or {}) do
        append(entry, true)
    end
    if type(config.customModels) == "table" then
        for _, entry in ipairs(config.customModels) do
            append(entry, false)
        end
    end
    if type(config.models) == "table" then
        for _, entry in ipairs(config.models) do
            append(entry, entry.builtin)
        end
    end

    Storage.sortModelList(models)
    config.models = models
    if type(config.selectedIndex) ~= "number" or config.selectedIndex < 1 or config.selectedIndex > #models then
        config.selectedIndex = (#models > 0) and 1 or nil
    end
end

function Storage.getOpenAISelectedModel(config)
    if type(config) ~= "table" then
        return nil
    end
    Storage.ensureOpenAIModelList(config)
    if type(config.selectedIndex) ~= "number" then
        return nil
    end
    return config.models and config.models[config.selectedIndex]
end

function Storage.serializeOpenAIConfig(config)
    if type(config) ~= "table" then
        return nil
    end
    Storage.ensureOpenAIModelList(config)
    local payload = {
        baseUrl = Utils.trim(config.baseUrl or ""),
        apiKey = config.apiKey or "",
        temperature = tonumber(config.temperature) or OPENAI_FORMAT_DEFAULT_TEMPERATURE,
        selectedIndex = config.selectedIndex or 1,
        systemPrompt = config.systemPrompt or OPENAI_DEFAULT_SYSTEM_PROMPT,
        models = {},
    }
    if type(config.models) == "table" then
        for _, entry in ipairs(config.models) do
            table.insert(payload.models, {
                name = entry.name,
                display = entry.display,
                builtin = entry.builtin == true,
            })
        end
    end
    if type(config.customModels) == "table" then
        payload.customModels = {}
        for _, entry in ipairs(config.customModels) do
            table.insert(payload.customModels, {
                name = entry.name,
                display = entry.display,
            })
        end
    end
    return payload
end

Storage.ensureOpenAIModelList(state.openaiFormat)


function UI.runWithLoading(action)
    if type(action) ~= "function" then
        return
    end
    if not (disp and ui) then
        return action()
    end

    local loadingWin = disp:AddWindow({
        ID = "LoadingWindow",
        WindowTitle = string.format("%s Loading", SCRIPT_NAME),
        Geometry = { LOADING_X, LOADING_Y, LOADING_WINDOW_WIDTH, LOADING_WINDOW_HEIGHT },
    }, ui:VGroup{
        ID = "LoadingRoot",
        Weight = 1,
        ui:Label{
            ID = "LoadingLabel",
            Weight = 1,
            Alignment = { AlignHCenter = true, AlignVCenter = true },
            WordWrap = true,
            Text = " loading...",
        },
    })

    if not loadingWin then
        return action()
    end

    local items = loadingWin:GetItems()
    local label = items and items.LoadingLabel

    if label then
        label.Text = " loading..."
    end

    loadingWin:Show()

    local ok, result = pcall(action)

    loadingWin:Hide()


    if loadingWin.DeleteLater then
        loadingWin:DeleteLater()
    end

    if not ok then
        error(result)
    end
    return result
end
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

function Services.httpGet(url, headers, timeout)
    if httpClient.https then
        local body, code = httpClient.https.get(url, headers, timeout)
        if body then
            return body, code
        end
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
        local tmpPath = os.tmpname()
        if not tmpPath then
            return nil, "tmpname_failed"
        end
        if tmpPath:sub(1, 1) == "\\" then
            local tempDir = os.getenv("TEMP") or os.getenv("TMP") or "."
            local needsSep = tempDir:match('[\\/]$') and "" or "\\"
            tmpPath = tempDir .. needsSep .. tmpPath:sub(2)
        end
        tmpPath = tmpPath:gsub('/', '\\')

        local redirected = string.format('%s > "%s" 2>nul', curlCommand, tmpPath)
        local ok = runShellCommand and runShellCommand(redirected)

        local file = io.open(tmpPath, "rb")
        local body = file and file:read("*a") or ""
        if file then
            file:close()
        end
        os.remove(tmpPath)

        if not ok then
            return nil, "curl_hidden_failed"
        end
        if body == "" then
            return nil, "empty_response"
        end
        return body, nil
    end

    if sep == "\\" then
        curlCommand = curlCommand .. " 2>nul"
    else
        curlCommand = curlCommand .. " 2>/dev/null"
    end
    local pipe = io.popen(curlCommand, "r")
    if not pipe then
        return nil, "curl_popen_failed"
    end
    local body = pipe:read("*a") or ""
    pipe:close()
    if body == "" then
        return nil, "empty_response"
    end
    return body, nil
end

function Services.httpPostJson(url, payload, headers, timeout)
    local bodyStr = payload or ""
    if httpClient.https and httpClient.https.postJson then
        local body, code = httpClient.https.postJson(url, bodyStr, headers, timeout)
        if body then
            return body, code
        end
    end

    local headerParts = {}
    local hasContentType = false
    if headers then
        for k, v in pairs(headers) do
            local cleanValue = tostring(v):gsub('"', '\\"')
            table.insert(headerParts, string.format('-H "%s: %s"', k, cleanValue))
            if not hasContentType and type(k) == "string" and k:lower() == "content-type" then
                hasContentType = true
            end
        end
    end
    if not hasContentType then
        table.insert(headerParts, '-H "Content-Type: application/json"')
    end

    local maxTime = timeout or SUPABASE_TIMEOUT
    local sep = package.config:sub(1, 1)

    local tempPayload = os.tmpname()
    if not tempPayload then
        return nil, "tmpname_failed"
    end
    if sep == "\\" and tempPayload:sub(1, 1) == "\\" then
        local tempDir = os.getenv("TEMP") or os.getenv("TMP") or "."
        local needsSep = tempDir:match('[\\/]$') and "" or "\\"
        tempPayload = tempDir .. needsSep .. tempPayload:sub(2)
    end

    local payloadFile, err = io.open(tempPayload, "wb")
    if not payloadFile then
        return nil, "payload_tmp_open_failed: " .. tostring(err)
    end
    payloadFile:write(bodyStr)
    payloadFile:close()

    if sep == "\\" then
        tempPayload = tempPayload:gsub('/', '\\')
        local outputPath = os.tmpname()
        if outputPath:sub(1, 1) == "\\" then
            local tempDir = os.getenv("TEMP") or os.getenv("TMP") or "."
            local needsSep = tempDir:match('[\\/]$') and "" or "\\"
            outputPath = tempDir .. needsSep .. outputPath:sub(2)
        end
        outputPath = outputPath:gsub('/', '\\')

        local curlCommand = string.format(
            'curl -sS -m %d -X POST %s --data-binary "@%s" "%s"',
            maxTime,
            table.concat(headerParts, " "),
            tempPayload,
            url
        )
        local redirected = string.format('%s > "%s" 2>nul', curlCommand, outputPath)
        local ok = runShellCommand and runShellCommand(redirected)

        local outputFile = io.open(outputPath, "rb")
        local body = outputFile and outputFile:read("*a") or ""
        if outputFile then
            outputFile:close()
        end
        os.remove(outputPath)
        os.remove(tempPayload)

        if not ok then
            return nil, "curl_hidden_failed"
        end
        if body == "" then
            return nil, "empty_response"
        end
        return body, nil
    else
        local curlCommand = string.format(
            'curl -sS -m %d -X POST %s --data-binary @%q "%s" 2>/dev/null',
            maxTime,
            table.concat(headerParts, " "),
            tempPayload,
            url
        )
        local pipe = io.popen(curlCommand, "r")
        if not pipe then
            os.remove(tempPayload)
            return nil, "curl_popen_failed"
        end
        local body = pipe:read("*a") or ""
        pipe:close()
        os.remove(tempPayload)
        if body == "" then
            return nil, "empty_response"
        end
        return body, nil
    end
end

-- Services.Parallel: shared curl-based parallel executor
function ParallelServices.runCurlParallel(tasks, options)
    if not tasks or #tasks == 0 then
        return {}, nil
    end
    local tempDir = Utils.getTempDir()
    if not Utils.ensureDir(tempDir) then
        return nil, "temp_dir_failed"
    end
    options = options or {}
    local apiUrl = options.apiUrl or GLM_API_URL
    if not apiUrl or apiUrl == "" then
        return nil, "invalid_api_url"
    end
    local timeout = options.timeout or GLM_TIMEOUT
    local limit = math.max(1, math.min(options.parallelLimit or #tasks, #tasks))
    local payloadPrefix = options.payloadPrefix or "chat_payload"
    local outputPrefix = options.outputPrefix or "chat_output"
    local headers = {}
    if type(options.headers) == "table" then
        for _, header in ipairs(options.headers) do
            if type(header) == "string" and Utils.trim(header) ~= "" then
                table.insert(headers, header)
            end
        end
    end
    local parser = options.parseResponse
    if type(parser) ~= "function" then
        parser = GLMService.parseResponseBody
    end
    local commandParts = { "curl", "-sS", "--show-error", "--parallel", "--parallel-immediate", string.format("--parallel-max %d", limit), string.format("-m %d", timeout) }
    local artifacts = {}
    local createdCount = 0
    local function cleanupArtifacts()
        for _, art in ipairs(artifacts) do
            if art.output then os.remove(art.output) end
            if art.payload then os.remove(art.payload) end
        end
    end
    for idx, task in ipairs(tasks) do
        local payloadName = string.format("%s_%s_%d_%d.json", payloadPrefix, state.sessionCode or "sess", os.time(), idx + createdCount)
        local outputName = string.format("%s_%s_%d_%d.json", outputPrefix, state.sessionCode or "sess", os.time(), idx + createdCount)
        createdCount = createdCount + 1
        local payloadPath = Utils.joinPath(tempDir, payloadName)
        local outputPath = Utils.joinPath(tempDir, outputName)
        local payloadFile, err = io.open(payloadPath, "wb")
        if not payloadFile then cleanupArtifacts(); return nil, string.format("payload_tmp_open_failed: %s", tostring(err)) end
        payloadFile:write(task.payload or "")
        payloadFile:close()
        table.insert(artifacts, { index = task.index, payload = payloadPath, output = outputPath })
        table.insert(commandParts, "-X")
        table.insert(commandParts, "POST")
        for _, header in ipairs(headers) do
            table.insert(commandParts, "-H")
            table.insert(commandParts, string.format("%q", header))
        end
        table.insert(commandParts, "--data-binary")
        table.insert(commandParts, string.format("@%q", payloadPath))
        table.insert(commandParts, "-o")
        table.insert(commandParts, string.format("%q", outputPath))
        table.insert(commandParts, string.format("%q", task.url or apiUrl))
        if idx < #tasks then table.insert(commandParts, "--next") end
    end
    local command = table.concat(commandParts, " ")
    local ok = runShellCommand(command)
    if not ok then cleanupArtifacts(); return nil, "parallel_execution_failed" end
    local results = {}
    local anyOutput = false
    for _, art in ipairs(artifacts) do
        local body; local file = io.open(art.output, "rb")
        if file then body = file:read("*a") or ""; file:close() end
        if body and body ~= "" then
            anyOutput = true
            local translation, extra, errMsg = parser(body)
            if translation then
                results[art.index] = { success = true, translation = translation, tokens = extra or 0, meta = extra }
            else
                results[art.index] = { success = false, err = errMsg or "translation_failed" }
            end
        else
            results[art.index] = { success = false, err = "empty_response" }
        end
        if art.output then os.remove(art.output) end
        if art.payload then os.remove(art.payload) end
    end
    if not anyOutput then return nil, "parallel_execution_failed" end
    return results, nil
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

function Utils.scriptDir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    local pattern = "(.*" .. SEP .. ")"
    if SEP == "\\" then
        pattern = "(.*[\\/])" -- 兼容模式，同时匹配两种斜杠，更安全
    end
    return source:match(pattern) or ""
end

function Utils.joinPath(a, b)
    if a == "" then
        return b
    end
    if a:sub(-1) == SEP then
        return a .. b
    end
    return a .. SEP .. b
end

function Utils.getTempDir()
    return Utils.joinPath(Utils.scriptDir(), "temp")
end

-- 将时间线名称转为文件名安全格式
function Utils.sanitizeFilename(name)
    name = tostring(name or "timeline")
    name = name:gsub("[%c%z]", "")
    name = name:gsub("[/\\:%*%?%\"]", "_")
    name = name:gsub("[<>|]", "_")
    name = name:gsub("%s+", "_")
    name = name:gsub("^_+", ""):gsub("_+$", "")
    if name == "" then name = "timeline" end
    return name
end

-- 简易目录列举（跨平台）
function Utils.listFiles(dir)
    local sep = package.config:sub(1,1)
    local cmd
    if sep == "\\" then
        cmd = string.format('dir /b "%s"', dir)
    else
        cmd = string.format('ls -1 "%s"', dir:gsub('"','\\"'))
    end
    local p = io.popen(cmd)
    if not p then return {} end
    local t = {}
    for line in p:lines() do
        table.insert(t, line)
    end
    p:close()
    return t
end


function Utils.escapePattern(s)
    return (s:gsub("(%W)","%%%1"))
end

function Utils.ensureDir(path)
    if path == "" then
        return true
    end
    if bmd and bmd.fileexists and bmd.fileexists(path) then
        return true
    end
    if IS_WINDOWS then
        if not runShellCommand(string.format('if not exist "%s" mkdir "%s"', path, path)) then
            print("Failed to create directory: " .. path)
            return false
        end
    else
        local escaped = path:gsub("'", "'\\''")
        if not runShellCommand("mkdir -p '" .. escaped .. "'") then
            print("Failed to create directory: " .. path)
            return false
        end
    end
    return true
end

configDir = Utils.joinPath(Utils.scriptDir(), "config")
Utils.ensureDir(configDir)
settingsFile = Utils.joinPath(configDir, "subedit_settings.json")
local storedSettings
local modelsFile = Utils.joinPath(configDir, "models.json")
local openAIModelStore = { builtin = {}, custom = {} }
Storage.settingsKeyOrder = {
    "TranslateProviderCombo",
    "TranslateTargetCombo",
    "TranslateConcurrencyCombo",
    "AzureRegion",
    "AzureApiKey",
    "OpenAIFormatModelCombo",
    "OpenAIFormatBaseURL",
    "OpenAIFormatApiKey",
    "OpenAIFormatTemperatureSpinBox",
    "SystemPromptTxt",
    "LangCnCheckBox",
    "LangEnCheckBox",
}

function Utils.fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end



function Storage.refreshDefaultModelsFromStore()
    DEFAULT_OPENAI_MODELS = {}
    if type(openAIModelStore.builtin) ~= "table" then
        openAIModelStore.builtin = {}
    end
    for display, info in pairs(openAIModelStore.builtin) do
        table.insert(DEFAULT_OPENAI_MODELS, {
            display = display,
            name = (info and info.model) or display,
            builtin = true,
        })
    end
    Storage.sortModelList(DEFAULT_OPENAI_MODELS)
end

function Storage.rebuildCustomModelListFromStore()
    state.openaiFormat.customModels = {}
    for display, info in pairs(openAIModelStore.custom or {}) do
        table.insert(state.openaiFormat.customModels, {
            display = display,
            name = (info and info.model) or display,
            builtin = false,
        })
    end
    Storage.sortModelList(state.openaiFormat.customModels)
end

function Storage.saveSettings(path, values, keyorder)
    if not values then
        return
    end
    Utils.ensureDir(configDir)
    local file, err = io.open(path, "w")
    if not file then
        print(string.format("无法写入设置文件 %s: %s", tostring(path), tostring(err)))
        return
    end
    
    -- 使用 JSON 编码函数将表转换为字符串
    local content
    if type(keyorder) == "table" then
        content = json.encode(values, { keyorder = keyorder })
    else
        content = json.encode(values)
    end

    file:write(content)
    file:close()
end

function Storage.saveOpenAIModelStore()
    Storage.saveSettings(modelsFile, {
        models = openAIModelStore.builtin or {},
        custom_models = openAIModelStore.custom or {},
    })
end

function Storage.loadSettings(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return nil
    end
    
    -- 使用 pcall 安全地调用 JSON 解码函数
    local ok, settings_table = pcall(json.decode, content)
    
    -- 如果解码失败或返回的不是一个表，则认为配置无效
    if not ok or type(settings_table) ~= "table" then
        print("JSON settings decode failed. Using default.")
        return nil
    end

    return settings_table
end

function Storage.loadOpenAIModelStore()
    Utils.ensureDir(configDir)
    if not Utils.fileExists(modelsFile) then
        Storage.saveSettings(modelsFile, { models = {}, custom_models = {} })
    end
    local config = Storage.loadSettings(modelsFile)
    if type(config) ~= "table" then
        config = {}
    end
    openAIModelStore.builtin = config.models or openAIModelStore.builtin or {}
    openAIModelStore.custom = config.custom_models or openAIModelStore.custom or {}
    Storage.refreshDefaultModelsFromStore()
    Storage.rebuildCustomModelListFromStore()
    state.openaiFormat.models = Utils.deepCopy(DEFAULT_OPENAI_MODELS)
    Storage.ensureOpenAIModelList(state.openaiFormat)
end

Storage.loadOpenAIModelStore()

function Subtitle.nextSrtPathForTimeline(timeline)
    local tempDir = Utils.getTempDir()
    Utils.ensureDir(tempDir)

    local tlName = "timeline"
    if timeline and timeline.GetName then
        tlName = timeline:GetName() or tlName
    end
    local safeName = Utils.sanitizeFilename(tlName)
    local rand = state.sessionCode or "0000"

    local prefix = string.format("%s_subtitle_update_%s_", safeName, rand)
    local files = Utils.listFiles(tempDir)

    -- 在 tempDir 中寻找相同前缀且后缀为数字的 .srt，取最大值
    local maxN = 0
    local pat = "^" .. Utils.escapePattern(prefix) .. "(%d+)%.srt$"
    for _, f in ipairs(files) do
        local n = f:match(pat)
        if n then
            n = tonumber(n) or 0
            if n > maxN then maxN = n end
        end
    end

    local nextIdx = maxN + 1
    local filename = string.format("%s%03d.srt", prefix, nextIdx)
    return Utils.joinPath(tempDir, filename)
end

function Utils.removeDir(path)
    if not path or path == "" then
        return
    end
    if IS_WINDOWS then
        if not runShellCommand(string.format('rmdir /S /Q "%s"', path)) then
            print("Failed to remove directory: " .. path)
        end
    else
        local escaped = path:gsub("'", "'\\''")
        if not runShellCommand("rm -rf '" .. escaped .. "'") then
            print("Failed to remove directory: " .. path)
        end
    end
end

-- ================= 新增功能函数区 开始 =================

-- 纯 Lua Base64 解码函数
function Utils.base64Decode(data)
    data = data:gsub("[^%w%+%/%=]", "")
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local t = {}
    local pad = 0
    if data:sub(-2) == "==" then pad = 2
    elseif data:sub(-1) == "=" then pad = 1 end
    for i=1, #data, 4 do
        local n = 0
        for j=0,3 do
            local c = data:sub(i+j, i+j)
            if c ~= "=" and c ~= "" then
                n = n * 64 + (b:find(c,1,true) - 1)
            else
                n = n * 64
            end
        end
        local bytes = string.char(math.floor(n/65536)%256, math.floor(n/256)%256, n%256)
        t[#t+1] = bytes
    end
    local out = table.concat(t)
    if pad > 0 then out = out:sub(1, #out - pad) end
    return out
end

-- 将 Base64 解码并写入临时文件
function Utils.createImageFromBase64(base64Data, destinationPath)
    local ok, bytes = pcall(Utils.base64Decode, base64Data)
    if not ok or not bytes then
        print("Base64 解码失败: " .. tostring(bytes))
        return false
    end

    local file, err = io.open(destinationPath, "wb")
    if not file then
        print("写入临时图片文件失败: " .. tostring(err))
        return false
    end

    file:write(bytes)
    file:close()
    return true
end

-- 创建并显示赞赏窗口
function UI.showDonationWindow()
    local tempDir = Utils.getTempDir()
    Utils.ensureDir(tempDir)
    local tempImagePath = Utils.joinPath(tempDir, "donation_qr_" .. state.sessionCode .. ".png")

    local success = Utils.createImageFromBase64(DONATION_QR_BASE64, tempImagePath)
    if not success then
        print("无法创建赞赏码图片，流程中止。")
        return
    end

    local IMG_WIDTH, IMG_HEIGHT = 280, 280 -- 设置图片显示尺寸
    local WIN_W, WIN_H = IMG_WIDTH + 40, IMG_HEIGHT + 40 -- 窗口尺寸
    local DONATION_X_CENTER = math.floor((SCREEN_WIDTH - WIN_W) / 2)
    local DONATION_Y_CENTER = math.floor((SCREEN_HEIGHT - WIN_H) / 2)

    local donationWin = disp:AddWindow({
        ID = "DonationWindow",
        WindowTitle = "Donation",
        Geometry = { DONATION_X_CENTER, DONATION_Y_CENTER, WIN_W, WIN_H },
    }, ui:VGroup{
        Weight = 1,
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        ui:Button{
            ID = "DonationImageButton",
            Icon = ui:Icon({ File = tempImagePath }),
            IconSize = { IMG_WIDTH, IMG_HEIGHT },
            MinimumSize = { IMG_WIDTH, IMG_HEIGHT },
            StyleSheet = "border:0px dashed #444; border-radius:0px; background:transparent;",
            Flat = true,
        }
    })
    function donationWin.On.DonationWindow.Close(ev)
        os.remove(tempImagePath)
        donationWin:Hide()
    end
    donationWin:Show()
end

function UI.currentLanguage()
    if state.language == "en" then
        return "en"
    end
    return "cn"
end

function UI.uiString(key)
    local lang = UI.currentLanguage()
    local pack = uiText[lang]
    if pack and pack[key] ~= nil then
        return pack[key]
    end
    pack = uiText.cn
    if pack and pack[key] ~= nil then
        return pack[key]
    end
    return ""
end

function UI.messageString(key)
    local bucket = messages[key]
    if not bucket then
        return nil
    end
    local lang = UI.currentLanguage()
    return bucket[lang] or bucket.cn
end

function Utils.openExternalUrl(url)
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
    local ok = runShellCommand("open '" .. escaped .. "'")
    if not ok then
        runShellCommand("xdg-open '" .. escaped .. "'")
    end
end

function UI.currentHeaders()
    local lang = UI.currentLanguage()
   local pack = uiText[lang]
   return (pack and pack.tree_headers) or uiText.cn.tree_headers
end

function UI.currentTranslateHeaders()
    local lang = UI.currentLanguage()
    local pack = uiText[lang]
    return (pack and pack.translate_tree_headers) or uiText.cn.translate_tree_headers
end

function Translate.getGoogleLangLabels()
    local copy = {}
    for idx, label in ipairs(LANG_LABELS) do
        copy[idx] = label
    end
    return copy
end




    storedSettings = Storage.loadSettings(settingsFile)
if storedSettings then
    if storedSettings.LangEnCheckBox == true  then
        state.language = "en"
    elseif storedSettings.LangCnCheckBox == true  then
        state.language = "cn"
    end

    local provider = storedSettings.TranslateProviderCombo 
    if type(provider) == "string" and Translate.isSupportedProvider(provider) then
        state.translate.provider = provider
    end

    local targetLabel = storedSettings.TranslateTargetCombo 
    if type(targetLabel) == "string" and targetLabel ~= "" then
        state.translate.targetLabel = targetLabel
    end

    local concurrencyValue = tonumber(storedSettings.TranslateConcurrencyCombo)
    if concurrencyValue and concurrencyValue >= 1 then
        state.translate.concurrency = math.floor(concurrencyValue)
    end

    local azureKey = storedSettings.AzureApiKey
    if type(azureKey) == "string" and Utils.trim(azureKey) ~= "" then
        state.azure.apiKey = Utils.trim(azureKey)
    end

    local azureRegion = storedSettings.AzureRegion 
    if type(azureRegion) == "string" and Utils.trim(azureRegion) ~= "" then
        state.azure.region = Utils.trim(azureRegion)
    end

    local baseUrl = storedSettings.OpenAIFormatBaseURL
    if type(baseUrl) == "string" then
        baseUrl = Utils.trim(baseUrl)
        if baseUrl ~= "" then
            state.openaiFormat.baseUrl = baseUrl
        end
    end

    local apiKey = storedSettings.OpenAIFormatApiKey
    if type(apiKey) == "string" and apiKey ~= "" then
        state.openaiFormat.apiKey = apiKey
    end

    local temperatureValue = tonumber(storedSettings.OpenAIFormatTemperatureSpinBox)
    if temperatureValue then
        state.openaiFormat.temperature = temperatureValue
    end

    local systemPrompt = storedSettings.SystemPromptTxt
    if type(systemPrompt) == "string" and Utils.trim(systemPrompt) ~= "" then
        state.openaiFormat.systemPrompt = systemPrompt 
    end

    local selectedDisplay = storedSettings.OpenAIFormatModelCombo
    if type(selectedDisplay) == "string" and selectedDisplay ~= "" then
        Storage.ensureOpenAIModelList(state.openaiFormat)
        local models = state.openaiFormat.models or {}
        for idx, entry in ipairs(models) do
            if entry.display == selectedDisplay or entry.name == selectedDisplay then
                state.openaiFormat.selectedIndex = idx
                break
            end
        end
    end

    local openaiStored = storedSettings.openai_format or storedSettings.openaiFormat
    if type(openaiStored) == "table" then
        if openaiStored.baseUrl or openaiStored.base_url then
            local legacyBase = Utils.trim(openaiStored.baseUrl or openaiStored.base_url or "")
            if legacyBase ~= "" then
                state.openaiFormat.baseUrl = legacyBase
            end
        end
        if openaiStored.apiKey or openaiStored.api_key then
            local legacyKey = openaiStored.apiKey or openaiStored.api_key
            if type(legacyKey) == "string" and legacyKey ~= "" then
                state.openaiFormat.apiKey = legacyKey
            end
        end
        if openaiStored.temperature or openaiStored.temp then
            local legacyTemp = tonumber(openaiStored.temperature or openaiStored.temp)
            if legacyTemp then
                state.openaiFormat.temperature = legacyTemp
            end
        end
        if openaiStored.systemPrompt and type(openaiStored.systemPrompt) == "string" and Utils.trim(openaiStored.systemPrompt) ~= "" then
            state.openaiFormat.systemPrompt = openaiStored.systemPrompt
        end
        if openaiStored.selectedIndex or openaiStored.selected_index then
            local legacyIndex = tonumber(openaiStored.selectedIndex or openaiStored.selected_index)
            if legacyIndex then
                state.openaiFormat.selectedIndex = legacyIndex
            end
        end
    end

    Storage.ensureOpenAIModelList(state.openaiFormat)
    Storage.saveOpenAIModelStore()
end
if not Translate.isSupportedProvider(state.translate.provider) then
    state.translate.provider = TRANSLATE_PROVIDER_AZURE_LABEL
end
Storage.ensureOpenAIModelList(state.openaiFormat)

function Subtitle.parseFps(raw)
    if not raw then
        return 24.0
    end
    if type(raw) == "number" then
        return raw
    end
    if type(raw) == "string" then
        raw = raw:match("^%s*(.-)%s*$")
        if raw == "" then
            return 24.0
        end
        local num, denom = raw:match("^(%-?%d+)%s*/%s*(%-?%d+)$")
        if num and denom then
            denom = tonumber(denom)
            if denom ~= 0 then
                return tonumber(num) / denom
            end
        end
        return tonumber(raw) or 24.0
    end
    return 24.0
end

function Subtitle.framesToTimecode(frames, fps)
    frames = math.floor(frames + 0.5)
    if fps <= 0 then
        fps = 24.0
    end
    local totalSeconds = math.floor(frames / fps)
    local remainFrames = frames - math.floor(totalSeconds * fps)
    if remainFrames < 0 then
        remainFrames = 0
    end
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d:%02d", hours, minutes, seconds, remainFrames)
end

function Subtitle.framesToSrtTimestamp(frames, fps)
    if fps <= 0 then
        fps = 24.0
    end
    if frames < 0 then
        frames = 0
    end
    local totalSeconds = frames / fps
    local hours = math.floor(totalSeconds / 3600)
    totalSeconds = totalSeconds - hours * 3600
    local minutes = math.floor(totalSeconds / 60)
    totalSeconds = totalSeconds - minutes * 60
    local seconds = math.floor(totalSeconds)
    local milliseconds = math.floor((totalSeconds - seconds) * 1000 + 0.5)
    if milliseconds >= 1000 then
        milliseconds = milliseconds - 1000
        seconds = seconds + 1
        if seconds >= 60 then
            seconds = seconds - 60
            minutes = minutes + 1
            if minutes >= 60 then
                minutes = minutes - 60
                hours = hours + 1
            end
        end
    end
    return string.format("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
end

function Subtitle.getTimelineContext()
    local pm = resolve:GetProjectManager()
    if not pm then
        return nil
    end
    local project = pm:GetCurrentProject()
    if not project then
        return nil
    end
    local timeline = project:GetCurrentTimeline()
    if not timeline then
        return nil
    end
    local mediaPool = project:GetMediaPool()
    if not mediaPool then
        return nil
    end
    local rootFolder = mediaPool:GetRootFolder()
    return {
        project = project,
        timeline = timeline,
        mediaPool = mediaPool,
        rootFolder = rootFolder,
    }
end

function Subtitle.sortEntries(entries)
    table.sort(entries, function(a, b)
        if a.startFrame == b.startFrame then
            return a.endFrame < b.endFrame
        end
        return a.startFrame < b.startFrame
    end)
end

function Subtitle.collectSubtitles()
    local ctx = Subtitle.getTimelineContext()
    if not ctx then
        return false, "no_timeline"
    end
    local timeline = ctx.timeline
    state.timeline = timeline
    local fpsSetting = timeline:GetSetting("timelineFrameRate")
    if not fpsSetting then
        fpsSetting = ctx.project:GetSetting("timelineFrameRate")
    end
    state.fps = Subtitle.parseFps(fpsSetting)
    local startFrame = timeline:GetStartFrame()
    state.startFrame = startFrame or 0

    local trackCount = timeline:GetTrackCount("subtitle") or 0
    local entries = {}
    state.activeTrackIndex = nil

    for track = 1, trackCount do
        local enabled = timeline:GetIsTrackEnabled("subtitle", track)
        if enabled ~= false then
            local itemList = timeline:GetItemListInTrack("subtitle", track)
                if itemList and #itemList > 0 then
                    state.activeTrackIndex = track
                    for _, item in ipairs(itemList) do
                        local startValue = item:GetStart() or 0
                        local endValue = item:GetEnd() or startValue
                        local name = item:GetName() or ""
                        local startFrame = math.floor(startValue + 0.5)
                        local endFrame = math.floor(endValue + 0.5)
                        table.insert(entries, {
                            startFrame = startFrame,
                            endFrame = endFrame,
                            startText = Subtitle.framesToTimecode(startFrame, state.fps),
                            endText = Subtitle.framesToTimecode(endFrame, state.fps),
                            text = name,
                        })
                    end
                    break
                end
            end
        end

    Subtitle.sortEntries(entries)
    state.entries = entries
    return true
end



function Subtitle.cleanupTempDir()
    local tempDir = Utils.getTempDir()
    if tempDir == "" then
        return
    end
    Utils.removeDir(tempDir)
end

function Subtitle.writeSrt(entries, path, startFrame, fps)
    if not entries or #entries == 0 then
        return false, "no_entries_update"
    end
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if dir and dir ~= "" then
        Utils.ensureDir(dir)
    end
    local fh, err = io.open(path, "w")
    if not fh then
        if err then
            print("writeSrt error: " .. tostring(err))
        end
        return false, "write_failed"
    end
    for idx, entry in ipairs(entries) do
        local s = math.max(0, (entry.startFrame or 0) - startFrame)
        local e = math.max(0, (entry.endFrame or 0) - startFrame)
        if e <= s then
            e = s + 1
        end
        local sText = Subtitle.framesToSrtTimestamp(s, fps)
        local eText = Subtitle.framesToSrtTimestamp(e, fps)
        fh:write(string.format("%d\n", idx))
        fh:write(string.format("%s --> %s\n", sText, eText))
        fh:write((entry.text or "") .. "\n\n")
    end
    fh:close()
    return true
end

function Subtitle.findClipByName(clips, name)
    if not clips then
        return nil
    end
    for _, clip in ipairs(clips) do
        if clip:GetName() == name then
            return clip
        end
    end
    return nil
end

function Subtitle.importSrtToTimeline(path)
    local ctx = Subtitle.getTimelineContext()
    if not ctx then
        return false, "no_timeline"
    end
    local timeline = ctx.timeline
    local mediaPool = ctx.mediaPool
    local root = ctx.rootFolder

    local trackCount = timeline:GetTrackCount("subtitle") or 0
    local targetIndex = nil

    for i = 1, trackCount do
        local enabled = timeline:GetIsTrackEnabled("subtitle", i)
        timeline:SetTrackEnable("subtitle", i, false)

        if not targetIndex then
            local items = timeline:GetItemListInTrack("subtitle", i)
            if not items or #items == 0 then
                targetIndex = i
            end
        end
    end

    if not targetIndex then
        timeline:AddTrack("subtitle")
        local newCount = timeline:GetTrackCount("subtitle")
        if newCount and newCount > trackCount then
            trackCount = newCount
            targetIndex = trackCount
        else
            targetIndex = trackCount > 0 and trackCount or 1
        end
    end

    timeline:SetTrackEnable("subtitle", targetIndex, true)
    state.activeTrackIndex = targetIndex

    local srtFolder = nil
    local subFolders = root and root:GetSubFolderList() or {}
    for _, folder in ipairs(subFolders) do
        if folder:GetName() == "srt" then
            srtFolder = folder
            break
        end
    end
    if not srtFolder then
        srtFolder = mediaPool:AddSubFolder(root, "srt")
    end
    if not srtFolder then
        return false, "create_srt_folder_failed"
    end
    mediaPool:SetCurrentFolder(srtFolder)

    local imported = mediaPool:ImportMedia({ path })
    local mediaItem = nil
    if type(imported) == "table" and #imported > 0 then
        mediaItem = imported[#imported]
    end
    if not mediaItem then
        local baseName = path:match("[^/\\]+$")
        local clips = srtFolder:GetClipList()
        mediaItem = Subtitle.findClipByName(clips, baseName)
    end
    if not mediaItem then
        return false, "import_failed"
    end

    timeline:SetCurrentTimecode(timeline:GetStartTimecode())
    local appendOk = mediaPool:AppendToTimeline({ mediaItem })

    local finalCount = timeline:GetTrackCount("subtitle") or trackCount
    for i = 1, finalCount do
        if i ~= targetIndex then
            timeline:SetTrackEnable("subtitle", i, false)
        end
    end
    timeline:SetTrackEnable("subtitle", targetIndex, true)

    if appendOk == false or appendOk == nil then
        return false, "append_failed"
    end
    return true
end

function Utils.escapePlainPattern(text)
    return text:gsub("([^%w])", "%%%1")
end

--[[
  SubtitleUtilityWin UI
]]

-- ==============================================================
-- UI Layout: Main Window and Tabs (Edit / Translate / Config)
-- ==============================================================
local win = disp:AddWindow(
  {
    ID          = "SubtitleUtilityWin",
    WindowTitle = string.format("%s %s", SCRIPT_NAME, SCRIPT_VERSION),
    Geometry    = { X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT },
    StyleSheet  = "*{font-size:14px;}",
  },
  ui:VGroup{
    ID     = "root",
    Weight = 1,
    ui:TabBar{
      ID     = "MainTabs",
      Weight = 0,
    },
    ui:Stack{
      ID     = "MainStack",
      Weight = 1,

      ------------------------------------------------------------------
      -- Edit Tab
      ------------------------------------------------------------------
      ui:VGroup{
        ID     = "EditTab",
        Weight = 1,

        ui:VGap(10),

        ui:HGroup{
          Weight = 0,
          ui:LineEdit{
            ID              = "FindInput",
            PlaceholderText = UI.uiString("find_placeholder"),
            Weight          = 1,
            Events          = { TextChanged = true, EditingFinished = true },
          },
          ui:Button{ ID = "FindPreviousButton", Text = UI.uiString("find_previous_button"), Weight = 0 },
          ui:Button{ ID = "FindNextButton",     Text = UI.uiString("find_next_button"),     Weight = 0 },
          ui:LineEdit{
            ID              = "ReplaceInput",
            PlaceholderText = UI.uiString("replace_placeholder"),
            Weight          = 1,
          },
          ui:Button{ ID = "AllReplaceButton",    Text = UI.uiString("all_replace_button"),    Weight = 0 },
          ui:Button{ ID = "SingleReplaceButton", Text = UI.uiString("single_replace_button"), Weight = 0 },
        },

        ui:Tree{
          ID                   = "SubtitleTree",
          AlternatingRowColors = true,
          WordWrap             = true,
          UniformRowHeights    = false,
          HorizontalScrollMode = true,
          FrameStyle           = 1,
          ColumnCount          = 3,
          SelectionMode        = "SingleSelection",
          Weight               = 1,
        },

        ui:TextEdit{
          ID              = "SubtitleEditor",
          Weight          = 0,
          PlaceholderText = UI.uiString("editor_placeholder"),
          WordWrap        = true,
        },

        ui:HGroup{
          Weight = 0,
          ui:Label{
            ID        = "StatusLabel",
            Text      = "",
            Weight    = 1,
            Alignment = { AlignHCenter = true, AlignVCenter = true },
          },
        },

        ui:HGroup{
          Weight = 0,
          ui:Label{
            ID          = "UpdateLabel",
            Text        = "",
            Weight      = 1,
            Alignment   = { AlignHCenter = true, AlignVCenter = true },
            WordWrap    = true,
            Visible     = false,
            StyleSheet  = "color:#d9534f; font-weight:bold;",
          },
        },

        ui:HGroup{
          Weight = 0.1,
          ui:Button{ ID = "RefreshButton",            Text = UI.uiString("refresh_button"),  Weight = 1 },
          ui:Button{ ID = "UpdateSubtitleButton",     Text = UI.uiString("update_button"),   Weight = 1 },
        },

        ui:VGap(5),

        ui:Button{
          ID               = "DonationButton",
          Text             = UI.uiString("donation"),
          Alignment        = { AlignHCenter = true, AlignVCenter = true },
          Font             = ui.Font({ PixelSize = 12, StyleName = "Bold" }),
          Flat             = true,
          TextColor        = { 1, 1, 1, 1 },
          BackgroundColor  = { 1, 1, 1, 0 },
          Weight           = 0,
        },
      },

      ------------------------------------------------------------------
      -- Translate Tab
      ------------------------------------------------------------------
      ui:VGroup{
        ID     = "TranslateTab",
        Weight = 1,

        ui:VGap(10),

        ui:HGroup{
          Weight = 0,

          ui:Label{   ID = "TranslateProviderLabel", Text = UI.uiString("translate_provider_label"), Weight = 0, Alignment = { AlignVCenter = true } },
          ui:ComboBox{ ID = "TranslateProviderCombo", Weight = 1, Editable = false },
          ui:Label{   ID = "TranslateTargetLabel",   Text = UI.uiString("translate_target_label"),   Weight = 0, Alignment = { AlignVCenter = true } },
          ui:ComboBox{ ID = "TranslateTargetCombo",   Weight = 1, Editable = false },
          ui:HGroup{
            Weight = 0,
            ui:Label{
              ID        = "TranslateConcurrencyLabel",
              Text      = UI.uiString("concurrency_label"),
              Alignment = { AlignVCenter = true },
              Weight    = 1,
            },
            ui:ComboBox{
              ID      = "TranslateConcurrencyCombo",
              Weight  = 0,
              Editable = false,
              Events  = { CurrentIndexChanged = true },
            },
          },
        },

        ui:Tree{
          ID                   = "TranslateSubtitleTree",
          AlternatingRowColors = true,
          WordWrap             = true,
          UniformRowHeights    = false,
          HorizontalScrollMode = true,
          FrameStyle           = 1,
          ColumnCount          = 4,
          SelectionMode        = "SingleSelection",
          Weight               = 1,
        },

        ui:TextEdit{
          ID              = "TranslateSubtitleEditor",
          Weight          = 0,
          PlaceholderText = UI.uiString("translate_editor_placeholder"),
          WordWrap        = true,
        },

        ui:HGroup{
          Weight = 0,
          ui:Label{
            ID        = "TranslateStatusLabel",
            Text      = "",
            Weight    = 1,
            Alignment = { AlignHCenter = true, AlignVCenter = true },
            WordWrap  = true,
          },
        },

        ui:HGroup{
          Weight = 0.1,
          ui:Button{ ID = "TranslateTransButton",     Text = UI.uiString("translate_trans_button"),     Weight = 1 },
          ui:Button{ ID = "TranslateSelectedButton",  Text = UI.uiString("translate_selected_button"),  Weight = 1 },
        },

        ui:HGroup{
          Weight = 0.1,
          ui:Button{ ID = "TranslateUpdateSubtitleButton", Text = UI.uiString("translate_update_button"), Weight = 1 },
        },

        ui:VGap(5),
      },

      ------------------------------------------------------------------
      -- Config Tab
      ------------------------------------------------------------------
      ui:VGroup{
        ID     = "ConfigTab",
        Weight = 1,

        ui:VGap(20),

        ui:HGroup{
          Weight = 0,
          ui:Label{
            ID        = "AzureConfigLabel",
            Text      = UI.uiString("azure_config_label"),
            Alignment = { AlignVCenter = true },
            Weight    = 1,
          },
          ui:Button{
            ID     = "AzureConfigButton",
            Text   = UI.uiString("azure_config_button"),
            Weight = 0,
          },
        },

        ui:HGroup{
          Weight = 0,
          ui:Label{
            ID        = "OpenAIFormatConfigLabel",
            Text      = UI.uiString("openai_config_label"),
            Alignment = { AlignVCenter = true },
            Weight    = 1,
          },
          ui:Button{
            ID     = "OpenAIFormatConfigButton",
            Text   = UI.uiString("openai_config_button"),
            Weight = 0,
          },
        },

        ui:HGroup{
          Weight = 0,
          ui:CheckBox{ ID = "LangCnCheckBox", Text = UI.uiString("lang_cn"), Checked = false, Weight = 0 },
          ui:CheckBox{ ID = "LangEnCheckBox", Text = UI.uiString("lang_en"), Checked = true,  Weight = 0 },
        },

        ui:Button{
          ID              = "CopyrightButton",
          Text            = UI.uiString("copyright"),
          Alignment       = { AlignHCenter = true, AlignVCenter = true },
          Font            = ui.Font({ PixelSize = 12, StyleName = "Bold" }),
          Flat            = true,
          TextColor       = { 0.1, 0.3, 0.9, 1 },
          BackgroundColor = { 1, 1, 1, 0 },
          Weight          = 0,
        },
      },
    },
  }
)


local it = win:GetItems()
local controls = {
    tree = it.SubtitleTree,
    editor = it.SubtitleEditor,
    langCn = it.LangCnCheckBox,
    langEn = it.LangEnCheckBox,
    mainTabs = it.MainTabs,
    mainStack = it.MainStack,
    updateLabel = it.UpdateLabel,
    translateTree = it.TranslateSubtitleTree,
    translateEditor = it.TranslateSubtitleEditor,
    translateStatusLabel = it.TranslateStatusLabel,
    translateProviderCombo = it.TranslateProviderCombo,
    translateTargetCombo = it.TranslateTargetCombo,
    translateTransButton = it.TranslateTransButton,
    translateSelectedButton = it.TranslateSelectedButton,
    translateUpdateButton = it.TranslateUpdateSubtitleButton,
    translateProviderLabel = it.TranslateProviderLabel,
    translateTargetLabel = it.TranslateTargetLabel,
    translateConcurrencyLabel = it.TranslateConcurrencyLabel,
    translateConcurrencyCombo = it.TranslateConcurrencyCombo,
    azureConfigLabel = it.AzureConfigLabel,
    azureConfigButton = it.AzureConfigButton,
    openAIConfigLabel = it.OpenAIFormatConfigLabel,
    openAIConfigButton = it.OpenAIFormatConfigButton,
    donationButton = it.DonationButton,
    findInput = it.FindInput,
    replaceInput = it.ReplaceInput,
    statusLabel = it.StatusLabel,
    refreshButton = it.RefreshButton,
    updateButton = it.UpdateSubtitleButton,
}


local function findConcurrencyOptionIndexByValue(value)
    local numeric = tonumber(value) or DEFAULT_TRANSLATE_CONCURRENCY
    local bestIndex = 1
    local bestDiff = math.huge
    for idx, option in ipairs(TRANSLATE_CONCURRENCY_OPTIONS) do
        if option.value == numeric then
            return idx, option.value
        end
        local diff = math.abs(option.value - numeric)
        if diff < bestDiff then
            bestDiff = diff
            bestIndex = idx
        end
    end
    local matched = TRANSLATE_CONCURRENCY_OPTIONS[bestIndex] and TRANSLATE_CONCURRENCY_OPTIONS[bestIndex].value or DEFAULT_TRANSLATE_CONCURRENCY
    return bestIndex, matched
end

local function setConcurrencyComboSelection(value)
    if not controls.translateConcurrencyCombo then
        return
    end
    local idx, matchedValue = findConcurrencyOptionIndexByValue(value)
    controls.translateConcurrencyCombo.CurrentIndex = (idx or 1) - 1
    if matchedValue and state.translate.concurrency ~= matchedValue then
        state.translate.concurrency = matchedValue
    end
end

local function populateConcurrencyCombo(value)
    if not controls.translateConcurrencyCombo then
        return
    end
    local combo = controls.translateConcurrencyCombo
    combo:Clear()
    for _, option in ipairs(TRANSLATE_CONCURRENCY_OPTIONS) do
        combo:AddItem(UI.uiString(option.labelKey))
    end
    setConcurrencyComboSelection(value)
end

populateConcurrencyCombo(state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)


local azureConfigWin = disp:AddWindow({
    ID = "AzureConfigWin",
    WindowTitle = UI.uiString("azure_config_window_title"),
    Geometry = { X_CENTER + 30, Y_CENTER + 30, 300, 150 },
    Hidden = true,
    StyleSheet = "*{font-size:14px;}",
}, ui:VGroup{
    ui:Label{
        ID = "AzureLabel",
        Text = UI.uiString("azure_config_header"),
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        Weight = 0,
    },
    ui:HGroup{
        Weight = 0,
        ui:Label{
            ID = "AzureRegionLabel",
            Text = UI.uiString("azure_region_label"),
            Alignment = { AlignVCenter = true },
            Weight = 0.3,
        },
        ui:LineEdit{
            ID = "AzureRegion",
            Text = state.azure.region or "",
            Weight = 0.7,
        },
    },
    ui:HGroup{
        Weight = 0,
        ui:Label{
            ID = "AzureApiKeyLabel",
            Text = UI.uiString("azure_api_key_label"),
            Alignment = { AlignVCenter = true },
            Weight = 0.3,
        },
        ui:LineEdit{
            ID = "AzureApiKey",
            Text = state.azure.apiKey or "",
            EchoMode = "Password",
            Weight = 0.7,
        },
    },
    ui:HGroup{
        Weight = 0,
        ui:Button{
            ID = "AzureConfirm",
            Text = UI.uiString("azure_confirm_button"),
            Weight = 1,
        },
        ui:Button{
            ID = "AzureRegisterButton",
            Text = UI.uiString("azure_register_button"),
            Weight = 1,
        },
    },
})
local azureConfigItems = azureConfigWin and azureConfigWin:GetItems() or {}

function Azure.refreshConfigTexts()
    if not azureConfigItems then
        return
    end
    if azureConfigWin then
        azureConfigWin.WindowTitle = UI.uiString("azure_config_window_title")
    end
    local textMap = {
        AzureLabel = "azure_config_header",
        AzureRegionLabel = "azure_region_label",
        AzureApiKeyLabel = "azure_api_key_label",
        AzureConfirm = "azure_confirm_button",
        AzureRegisterButton = "azure_register_button",
    }
    for id, key in pairs(textMap) do
        local widget = azureConfigItems[id]
        if widget and widget.Text ~= nil then
            widget.Text = UI.uiString(key)
        end
    end
    if controls.azureConfigLabel then
        controls.azureConfigLabel.Text = UI.uiString("azure_config_label")
    end
    if controls.azureConfigButton then
        controls.azureConfigButton.Text = UI.uiString("azure_config_button")
    end
end

function Azure.syncConfigControls()
    if not azureConfigItems then
        return
    end
    if azureConfigItems.AzureRegion then
        azureConfigItems.AzureRegion.Text = state.azure.region or ""
    end
    if azureConfigItems.AzureApiKey then
        azureConfigItems.AzureApiKey.Text = state.azure.apiKey or ""
    end
end

function Azure.applyConfigFromControls()
    if not azureConfigItems then
        return
    end
    if azureConfigItems.AzureRegion then
        state.azure.region = Utils.trim(azureConfigItems.AzureRegion.Text or "")
    end
    if azureConfigItems.AzureApiKey then
        state.azure.apiKey = Utils.trim(azureConfigItems.AzureApiKey.Text or "")
    end
end

function Azure.openConfigWindow()
    if not azureConfigWin then
        return
    end
    Azure.refreshConfigTexts()
    Azure.syncConfigControls()
    azureConfigWin:Show()
end

function Azure.closeConfigWindow()
    if not azureConfigWin then
        return
    end
    Azure.applyConfigFromControls()
    azureConfigWin:Hide()
end


local openAIConfigWin = disp:AddWindow({
    ID = "OpenAIFormatConfigWin",
    WindowTitle = UI.uiString("openai_config_window_title"),
    Geometry = { X_CENTER + 40, Y_CENTER + 40, 350, 450 },
    --WindowFlags = { Window = true },
    Hidden = true,
    StyleSheet = "*{font-size:14px;}",
}, ui:VGroup{
    ui:Label{
        ID = "OpenAIFormatLabel",
        Text = UI.uiString("openai_config_header"),
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        Weight = 0,
    },
    ui:Label{
        ID = "OpenAIFormatModelLabel",
        Text = UI.uiString("openai_model_label"),
        Weight = 0,
    },
    ui:HGroup{
        Weight = 0,
        ui:ComboBox{
            ID = "OpenAIFormatModelCombo",
            Weight = 0.6,
            Editable = false,
            Events = { CurrentIndexChanged = true },
        },
        ui:LineEdit{
            ID = "OpenAIFormatModelName",
            ReadOnly = true,
            Weight = 0.4,
        },
    },
    ui:Label{
        ID = "OpenAIFormatBaseURLLabel",
        Text = UI.uiString("openai_base_url_label"),
        Weight = 0,
    },
    ui:LineEdit{
        ID = "OpenAIFormatBaseURL",
        Text = "",
        PlaceholderText = OPENAI_FORMAT_DEFAULT_BASE_URL,
        Weight = 0,
    },
    ui:Label{
        ID = "OpenAIFormatApiKeyLabel",
        Text = UI.uiString("openai_api_key_label"),
        Weight = 0,
    },
    ui:LineEdit{
        ID = "OpenAIFormatApiKey",
        Text = state.openaiFormat.apiKey or "",
        EchoMode = "Password",
        Weight = 0,
    },
    ui:HGroup{
        Weight = 0,
        ui:Label{
            ID = "OpenAIFormatTemperatureLabel",
            Text = UI.uiString("openai_temperature_label"),
            Weight = 1,
        },
        ui:DoubleSpinBox{
            ID = "OpenAIFormatTemperatureSpinBox",
            Minimum = 0.0,
            Maximum = 1.0,
            SingleStep = 0.01,
            Value = state.openaiFormat.temperature or OPENAI_FORMAT_DEFAULT_TEMPERATURE,
            Weight = 0,
        },
    },
    ui:Label{
        ID = "SystemPromptLabel",
        Text = UI.uiString("system_prompt_label"),
        Weight = 0,
    },
    ui:TextEdit{
        ID = "SystemPromptTxt",
        Text = state.openaiFormat.systemPrompt or OPENAI_DEFAULT_SYSTEM_PROMPT,
        Weight = 1,
    },
    ui:HGroup{
        Weight = 0,
        ui:Button{
            ID = "VerifyModel",
            Text = UI.uiString("openai_verify_button"),
            Weight = 1,
        },
        ui:Button{
            ID = "ShowAddModel",
            Text = UI.uiString("openai_add_button"),
            Weight = 1,
        },
        ui:Button{
            ID = "DeleteModel",
            Text = UI.uiString("openai_delete_button"),
            Weight = 1,
        },
    },
})
local openAIConfigItems = openAIConfigWin and openAIConfigWin:GetItems() or {}

local addModelWin = disp:AddWindow({
    ID = "AddModelWin",
    WindowTitle = "Add OpenAI Format Model",
    Geometry = { X_CENTER + 60, Y_CENTER + 60, 300, 200 },
    --WindowFlags = { Window = true },
    Hidden = true,
    StyleSheet = "*{font-size:14px;}",
}, ui:VGroup{
    ui:Label{
        ID = "AddModelTitle",
        Text = "Add OpenAI Format Model",
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        Weight = 0,
    },
    ui:Label{
        ID = "NewModelDisplayLabel",
        Text = "Display name",
        Weight = 0,
    },
    ui:LineEdit{
        ID = "addOpenAIFormatModelDisplay",
        Weight = 0,
    },
    ui:Label{
        ID = "OpenAIFormatModelNameLabel",
        Text = "Model name",
        Weight = 0,
    },
    ui:LineEdit{
        ID = "addOpenAIFormatModelName",
        Weight = 0,
    },
    ui:HGroup{
        Weight = 0,
        ui:Button{
            ID = "AddModelBtn",
            Text = "Add",
            Weight = 1,
        },
    },
})
local addModelItems = addModelWin and addModelWin:GetItems() or {}

local messageWin = disp:AddWindow({
    ID = "MessageBoxWin",
    WindowTitle = "Info",
    Geometry = { X_CENTER + 60, Y_CENTER + 80, 360, 160 },
    Hidden = true,
    StyleSheet = "*{font-size:14px;}",
}, ui:VGroup{
    ID = "MessageBoxLayout",
    Weight = 1,
    ui:Label{
        ID = "MessageLabel",
        Weight = 1,
        WordWrap = true,
        Alignment = { AlignHCenter = true, AlignVCenter = true },
        Text = "",
    },
    ui:HGroup{
        Weight = 0,
        ui:Button{
            ID = "MessageBoxOk",
            Text = "OK",
            Weight = 1,
            MinimumSize = { 80, 28 },
        },
    },
})

local messageItems = messageWin and messageWin:GetItems() or {}

local function hide_dynamic_message()
    if not messageWin then
        return
    end
    messageWin:Hide()
end

local function show_dynamic_message(en_text, zh_text)
    if not messageWin or not messageItems then
        return
    end
    local lang = UI.currentLanguage()
    local display = en_text or ""
    if lang == "cn" then
        display = zh_text or en_text or ""
    end
    if display == "" then
        display = en_text or zh_text or ""
    end
    if messageItems.MessageLabel then
        messageItems.MessageLabel.Text = display or ""
    end
    if messageItems.MessageBoxOk then
        messageItems.MessageBoxOk.Text = UI.uiString("azure_confirm_button")
    end
    messageWin:Show()
end

if messageWin then
    function messageWin.On.MessageBoxWin.Close(ev)
        hide_dynamic_message()
    end
    function messageWin.On.MessageBoxOk.Clicked(ev)
        hide_dynamic_message()
    end
end

function UI.withUpdatesSuspended(widget, fn)
    if not widget or type(fn) ~= "function" then
        return
    end
    local canSuspend = type(widget.SetUpdatesEnabled) == "function"
    if not canSuspend then
        fn()
        return
    end
    widget:SetUpdatesEnabled(false)
    local ok, err = pcall(fn)
    widget:SetUpdatesEnabled(true)
    if not ok then
        error(err)
    end
end

-- Programmatic update guards for editor/translate text widgets
function UI.withEditorProgrammatic(fn)
    if type(fn) ~= "function" then return end
    editorProgrammatic = true
    local ok, err = pcall(fn)
    editorProgrammatic = false
    if not ok then error(err) end
end

function UI.withTranslateProgrammatic(fn)
    if type(fn) ~= "function" then return end
    translateEditorProgrammatic = true
    local ok, err = pcall(fn)
    translateEditorProgrammatic = false
    if not ok then error(err) end
end


function OpenAIService.refreshConfigTexts()
    if not openAIConfigItems then
        return
    end
    if openAIConfigWin then
        openAIConfigWin.WindowTitle = UI.uiString("openai_config_window_title")
    end
    local textMap = {
        OpenAIFormatLabel = "openai_config_header",
        OpenAIFormatModelLabel = "openai_model_label",
        OpenAIFormatBaseURLLabel = "openai_base_url_label",
        OpenAIFormatApiKeyLabel = "openai_api_key_label",
        OpenAIFormatTemperatureLabel = "openai_temperature_label",
        SystemPromptLabel = "system_prompt_label",
        VerifyModel = "openai_verify_button",
        ShowAddModel = "openai_add_button",
        DeleteModel = "openai_delete_button",
    }
    for id, key in pairs(textMap) do
        local widget = openAIConfigItems[id]
        if widget and widget.Text ~= nil then
            widget.Text = UI.uiString(key)
        end
    end
    if addModelItems then
        local addTextMap = {
            AddModelTitle = "openai_add_model_title",
            NewModelDisplayLabel = "openai_new_model_display_label",
            OpenAIFormatModelNameLabel = "openai_new_model_name_label",
            AddModelBtn = "openai_add_button",
        }
        for id, key in pairs(addTextMap) do
            local widget = addModelItems[id]
            if widget and widget.Text ~= nil then
                widget.Text = UI.uiString(key)
            end
        end
    end
    if controls.openAIConfigLabel then
        controls.openAIConfigLabel.Text = UI.uiString("openai_config_label")
    end
    if controls.openAIConfigButton then
        controls.openAIConfigButton.Text = UI.uiString("openai_config_button")
    end
    if controls.translateConcurrencyLabel then
        controls.translateConcurrencyLabel.Text = UI.uiString("concurrency_label")
    end
    populateConcurrencyCombo(state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)
    if openAIConfigItems.OpenAIFormatBaseURL then
        openAIConfigItems.OpenAIFormatBaseURL.PlaceholderText = OPENAI_FORMAT_DEFAULT_BASE_URL
    end
end

function OpenAIService.populateOpenAIModelCombo()
    if not openAIConfigItems or not openAIConfigItems.OpenAIFormatModelCombo then
        return
    end
    Storage.ensureOpenAIModelList(state.openaiFormat)
    local combo = openAIConfigItems.OpenAIFormatModelCombo
    combo:Clear()
    local models = state.openaiFormat.models or {}
    for _, entry in ipairs(models) do
        combo:AddItem(entry.display or entry.name or "")
    end
    if #models > 0 then
        local idx = state.openaiFormat.selectedIndex or 1
        idx = math.max(1, math.min(idx, #models))
        state.openaiFormat.selectedIndex = idx
        combo.CurrentIndex = idx - 1
        if openAIConfigItems.OpenAIFormatModelName then
            openAIConfigItems.OpenAIFormatModelName.Text = models[idx].name or ""
        end
    else
        combo.CurrentIndex = -1
        if openAIConfigItems.OpenAIFormatModelName then
            openAIConfigItems.OpenAIFormatModelName.Text = ""
        end
    end
end

function OpenAIService.applyConfigFromControls()
    if not openAIConfigItems then
        return
    end
    if openAIConfigItems.OpenAIFormatBaseURL then
        local baseUrl = Utils.trim(openAIConfigItems.OpenAIFormatBaseURL.Text or "")

        state.openaiFormat.baseUrl = baseUrl
    end
    if openAIConfigItems.OpenAIFormatApiKey then
        state.openaiFormat.apiKey = Utils.trim(openAIConfigItems.OpenAIFormatApiKey.Text or "")
    end
    if openAIConfigItems.OpenAIFormatTemperatureSpinBox then
        local value = tonumber(openAIConfigItems.OpenAIFormatTemperatureSpinBox.Value)
        if value then
            if value < 0 then value = 0 end
            if value > 1 then value = 1 end
            state.openaiFormat.temperature = value
        end
    end
    if openAIConfigItems.SystemPromptTxt then
        local promptText = openAIConfigItems.SystemPromptTxt.PlainText or openAIConfigItems.SystemPromptTxt.Text or ""
        promptText = Utils.trim(promptText)
        if promptText == "" then
            promptText = OPENAI_DEFAULT_SYSTEM_PROMPT
        end
        state.openaiFormat.systemPrompt = promptText
    end
    if openAIConfigItems.OpenAIFormatModelCombo then
        local idx = openAIConfigItems.OpenAIFormatModelCombo.CurrentIndex
        if type(idx) == "number" and idx >= 0 then
            state.openaiFormat.selectedIndex = idx + 1
        end
    end
    Storage.ensureOpenAIModelList(state.openaiFormat)
end

function OpenAIService.syncOpenAIConfigControls()
    Storage.ensureOpenAIModelList(state.openaiFormat)
    if openAIConfigItems.OpenAIFormatBaseURL then
        local currentBase = Utils.trim(state.openaiFormat.baseUrl or "")
        if currentBase ~= "" and currentBase ~= OPENAI_FORMAT_DEFAULT_BASE_URL then
            openAIConfigItems.OpenAIFormatBaseURL.Text = currentBase
        else
            openAIConfigItems.OpenAIFormatBaseURL.Text = ""
        end
    end
    if openAIConfigItems.OpenAIFormatApiKey then
        openAIConfigItems.OpenAIFormatApiKey.Text = state.openaiFormat.apiKey or ""
    end
    if openAIConfigItems.OpenAIFormatTemperatureSpinBox then
        openAIConfigItems.OpenAIFormatTemperatureSpinBox.Value = state.openaiFormat.temperature or OPENAI_FORMAT_DEFAULT_TEMPERATURE
    end
    if openAIConfigItems.SystemPromptTxt then
        local prompt = state.openaiFormat.systemPrompt or OPENAI_DEFAULT_SYSTEM_PROMPT
        openAIConfigItems.SystemPromptTxt.PlainText = prompt
        openAIConfigItems.SystemPromptTxt.Text = prompt
    end
    OpenAIService.populateOpenAIModelCombo()
end

function OpenAIService.openConfigWindow()
    if not openAIConfigWin then
        return
    end
    OpenAIService.refreshConfigTexts()
    OpenAIService.syncOpenAIConfigControls()
    if addModelItems.addOpenAIFormatModelDisplay then
        addModelItems.addOpenAIFormatModelDisplay.Text = ""
    end
    if addModelItems.addOpenAIFormatModelName then
        addModelItems.addOpenAIFormatModelName.Text = ""
    end
    if addModelWin then
        addModelWin:Hide()
    end
    openAIConfigWin:Show()
end

function OpenAIService.closeConfigWindow()
    if not openAIConfigWin then
        return
    end
    OpenAIService.applyConfigFromControls()
    openAIConfigWin:Hide()
    if addModelWin then
        addModelWin:Hide()
    end
end

function OpenAIService.verifyModel(baseUrl, apiKey, model)
    local cleanBase = Utils.trim(baseUrl or "")
    if cleanBase == "" then
        cleanBase = OPENAI_FORMAT_DEFAULT_BASE_URL
    end
    local normalizedBase = cleanBase:gsub("/*$", "")
    local url = normalizedBase .. "/v1/chat/completions"
    local payload = json.encode({
        model = model,
        messages = {
            { role = "system", content = "You are a health check assistant." },
            { role = "user", content = "Reply with OK." },
        },
        temperature = 0,
        max_tokens = 5,
    })
    local headers = {
        Authorization = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
    }
    local body, status = Services.httpPostJson(url, payload, headers, OPENAI_FORMAT_TIMEOUT)
    if not body then
        return false, status or "request_failed"
    end

    local code = tonumber(status)
    local ok, decoded = pcall(json.decode, body)
    if ok and type(decoded) == "table" then
        if decoded.error and decoded.error.message then
            return false, decoded.error.message
        end
        local choices = decoded.choices
        if choices and type(choices) == "table" and choices[1] and choices[1].message then
            return true, tostring(code or "200")
        end
    end

    if code and code >= 200 and code < 300 then
        return true, tostring(code)
    end
    return false, tostring(status or "error")
end

-- ==============================================================
-- Translate Tab: Controller & Helpers
-- ==============================================================
local translate = Translate

    local function formatTranslateStatusForLang(key, args, lang)
        local template = translateStatusTemplates[key]
        if not template then
            return ""
        end
        local text = template[lang] or template.cn or ""
        if text == "" then
            return text
        end
        if args and #args > 0 then
            local ok, formatted = pcall(string.format, text, table.unpack(args))
            if ok then
                return formatted
            end
        end
        return text
    end

    local function formatTranslateStatus(key, args)
        return formatTranslateStatusForLang(key, args, UI.currentLanguage())
    end

    local function notifyTranslateStatus(key, argsEn, argsCn)
        argsEn = argsEn or {}
        argsCn = argsCn or argsEn
        local enText = formatTranslateStatusForLang(key, argsEn, "en")
        local cnText = formatTranslateStatusForLang(key, argsCn, "cn")
        if enText == "" and cnText == "" then
            return
        end
        local finalEn = enText ~= "" and enText or cnText
        local finalCn = cnText ~= "" and cnText or enText
        show_dynamic_message(finalEn, finalCn)
    end

    local function applyTranslateStatusInternal(key, args)
        if controls.translateStatusLabel then
            controls.translateStatusLabel.Text = formatTranslateStatus(key, args)
        end
    end

    local function setTranslateStatus(key, ...)
        local args = { ... }
        local tState = state.translate
        if tState then
            tState.lastStatusKey = key
            tState.lastStatusArgs = args
        end
        applyTranslateStatusInternal(key, args)
    end

    local function resolveTranslateErrorForLang(code, lang)
        if code == nil or code == "" then
            return ""
        end
        local bucket = translateErrorMessages[code]
        if bucket then
            if lang == "en" then
                return bucket.en or bucket.cn or tostring(code)
            end
            return bucket.cn or bucket.en or tostring(code)
        end
        if type(code) == "string" then
            return code
        end
        return tostring(code)
    end

    local function resolveTranslateError(code)
        return resolveTranslateErrorForLang(code, UI.currentLanguage())
    end

    local function resolveTranslateErrorPair(code)
        local enText = resolveTranslateErrorForLang(code, "en")
        local cnText = resolveTranslateErrorForLang(code, "cn")
        return enText, cnText
    end

    local function notifyTranslateFailure(reason)
        if reason == nil then
            notifyTranslateStatus("failed", { "" }, { "" })
            return
        end
        if type(reason) == "table" then
            local enReason = reason.en or reason[1] or ""
            local cnReason = reason.cn or reason[2] or enReason
            notifyTranslateStatus("failed", { enReason }, { cnReason })
            return
        end
        local enReason, cnReason = resolveTranslateErrorPair(reason)
        notifyTranslateStatus("failed", { enReason }, { cnReason })
    end

    local function handleOpenAIVerify()
        if not openAIConfigItems then
            return
        end
        OpenAIService.applyConfigFromControls()
        Storage.ensureOpenAIModelList(state.openaiFormat)
        local selected = Storage.getOpenAISelectedModel(state.openaiFormat)
        if not selected then
            setTranslateStatus("failed", resolveTranslateError("openai_missing_model"))
            local enText, cnText = resolveTranslateErrorPair("openai_missing_model")
            show_dynamic_message(enText, cnText)
            return
        end
        local baseUrl = Utils.trim(state.openaiFormat.baseUrl or "")
        if baseUrl == "" then
            baseUrl = OPENAI_FORMAT_DEFAULT_BASE_URL
        end
        local apiKey = Utils.trim(state.openaiFormat.apiKey or "")
        if apiKey == "" then
            setTranslateStatus("failed", resolveTranslateError("openai_missing_key"))
            local enText, cnText = resolveTranslateErrorPair("openai_missing_key")
            show_dynamic_message(enText, cnText)
            return
        end
        local ok, message = OpenAIService.verifyModel(baseUrl, apiKey, selected.name)
        if ok then
            local enMsg = uiText.en.openai_verify_success or "Model verified successfully"
            local cnMsg = uiText.cn.openai_verify_success or enMsg
            show_dynamic_message(enMsg, cnMsg)
            print(string.format("[OpenAI] Verify success: %s (%s)", selected.name, tostring(message or "")))
        else
            local templateEn = uiText.en.openai_verify_failed or "Model verification failed: %s"
            local templateCn = uiText.cn.openai_verify_failed or templateEn
            local errMsgEn = string.format(templateEn, tostring(message or ""))
            local errMsgCn = string.format(templateCn, tostring(message or ""))
            local statusText = UI.currentLanguage() == "cn" and errMsgCn or errMsgEn
            setTranslateStatus("failed", statusText)
            show_dynamic_message(errMsgEn, errMsgCn)
            print(string.format("[OpenAI] Verify failed: %s", errMsgEn))
        end
    end

    local function handleOpenAIAddModel()
        if not addModelItems then
            return
        end
        local displayInput = Utils.trim((addModelItems.addOpenAIFormatModelDisplay and addModelItems.addOpenAIFormatModelDisplay.Text) or "")
        local modelInput = Utils.trim((addModelItems.addOpenAIFormatModelName and addModelItems.addOpenAIFormatModelName.Text) or "")
        if modelInput == "" then
            setTranslateStatus("failed", UI.uiString("openai_missing_fields"))
            return
        end
        if displayInput == "" then
            displayInput = modelInput
        end
        if openAIModelStore.builtin and openAIModelStore.builtin[displayInput] then
            setTranslateStatus("failed", UI.uiString("openai_add_duplicate"))
            return
        end
        Storage.ensureOpenAIModelList(state.openaiFormat)
        for _, entry in ipairs(state.openaiFormat.models or {}) do
            if entry.name == modelInput and entry.builtin then
                setTranslateStatus("failed", UI.uiString("openai_add_duplicate"))
                return
            end
        end
        for disp, info in pairs(openAIModelStore.custom or {}) do
            if info and info.model == modelInput then
                openAIModelStore.custom[disp] = nil
            end
        end
        openAIModelStore.custom = openAIModelStore.custom or {}
        openAIModelStore.custom[displayInput] = { model = modelInput }
        Storage.rebuildCustomModelListFromStore()
        state.openaiFormat.models = Utils.deepCopy(DEFAULT_OPENAI_MODELS)
        Storage.ensureOpenAIModelList(state.openaiFormat)
        state.openaiFormat.selectedIndex = nil
        for idx, entry in ipairs(state.openaiFormat.models or {}) do
            if entry.name == modelInput then
                state.openaiFormat.selectedIndex = idx
                break
            end
        end
        if not state.openaiFormat.selectedIndex then
            state.openaiFormat.selectedIndex = (#state.openaiFormat.models > 0) and 1 or nil
        end
        Storage.saveOpenAIModelStore()
        OpenAIService.populateOpenAIModelCombo()
        if addModelItems.addOpenAIFormatModelDisplay then
            addModelItems.addOpenAIFormatModelDisplay.Text = ""
        end
        if addModelItems.addOpenAIFormatModelName then
            addModelItems.addOpenAIFormatModelName.Text = ""
        end
        if addModelWin then
            addModelWin:Hide()
        end
        if openAIConfigWin then
            openAIConfigWin:Show()
        end
        OpenAIService.syncOpenAIConfigControls()
        print(string.format("[OpenAI] Model added: %s (%s)", displayInput, modelInput))
    end

    local function handleOpenAIDeleteModel()
        OpenAIService.applyConfigFromControls()
        Storage.ensureOpenAIModelList(state.openaiFormat)
        local models = state.openaiFormat.models or {}
        if #models == 0 then
            local en = (uiText.en.openai_missing_model or "Select a valid OpenAI model.")
            local cn = (uiText.cn.openai_missing_model or "请选择有效的 OpenAI 模型")
            show_dynamic_message(en, cn)
            return
        end
        local idx = state.openaiFormat.selectedIndex or 1
        idx = math.max(1, math.min(idx, #models))
        local target = models[idx]
        if target.builtin then
            local en = (uiText.en.openai_delete_builtin_warning or "Built-in models cannot be removed")
            local cn = (uiText.cn.openai_delete_builtin_warning or "系统默认模型不可删除")
            show_dynamic_message(en, cn)
            return
        end
        local displayKey = target.display or target.name
        if openAIModelStore.custom then
            openAIModelStore.custom[displayKey] = nil
        end
        Storage.rebuildCustomModelListFromStore()
        state.openaiFormat.models = Utils.deepCopy(DEFAULT_OPENAI_MODELS)
        Storage.ensureOpenAIModelList(state.openaiFormat)
        if state.openaiFormat.selectedIndex and state.openaiFormat.selectedIndex > (#state.openaiFormat.models or 0) then
            state.openaiFormat.selectedIndex = (#state.openaiFormat.models > 0) and #state.openaiFormat.models or nil
        end
        Storage.saveOpenAIModelStore()
        OpenAIService.populateOpenAIModelCombo()
        OpenAIService.syncOpenAIConfigControls()
        local en = (uiText.en.openai_delete_success or "Model deleted")
        local cn = (uiText.cn.openai_delete_success or "模型已删除")
        show_dynamic_message(en, cn)
        print(string.format("[OpenAI] Model removed: %s", displayKey))
    end

    local translateTabInitialized = false





    local function refreshTranslateStatus()
        local tState = state.translate
        if not tState then
            return
        end
        applyTranslateStatusInternal(tState.lastStatusKey or "idle", tState.lastStatusArgs or {})
    end

    local function setTranslateControlsEnabled(enabled)
        local flag = enabled and true or false
        if controls.translateProviderCombo then
            controls.translateProviderCombo.Enabled = flag
        end
        if controls.translateTargetCombo then
            controls.translateTargetCombo.Enabled = flag
        end
        if controls.translateTransButton then
            controls.translateTransButton.Enabled = flag
        end
        if controls.translateSelectedButton then
            controls.translateSelectedButton.Enabled = flag and (state.translate.selectedIndex ~= nil)
        end
        if controls.translateUpdateButton then
            controls.translateUpdateButton.Enabled = flag
        end
        if controls.translateEditor then
            controls.translateEditor.Enabled = flag
        end
        if controls.translateConcurrencyCombo then
            controls.translateConcurrencyCombo.Enabled = flag
        end
    end

    local function normalizeTranslateTree()
        if not controls.translateTree then
            return
        end
        UI.withUpdatesSuspended(controls.translateTree, function()
            controls.translateTree:SetHeaderLabels(UI.currentTranslateHeaders())
            controls.translateTree.ColumnWidth[0] = 50
            controls.translateTree.ColumnWidth[1] = 110
            controls.translateTree.ColumnWidth[2] = 100
            controls.translateTree.ColumnWidth[3] = 260
        end)
    end

    local function resetTranslateState()
        local tState = state.translate
        if not tState then
            return
        end
        tState.entries = {}
        tState.populated = false
        tState.selectedIndex = nil
        tState.totalTokens = 0
        tState.busy = false
        tState.lastStatusKey = "idle"
        tState.lastStatusArgs = nil
        if controls.translateTree then
            UI.withUpdatesSuspended(controls.translateTree, function()
                controls.translateTree:Clear()
            end)
        end
        normalizeTranslateTree()
        if controls.translateEditor then
            UI.withTranslateProgrammatic(function()
                controls.translateEditor.Text = ""
            end)
        end
        if controls.translateSelectedButton then
            controls.translateSelectedButton.Enabled = false
        end
        setTranslateStatus("idle")
    end

    local function cloneEditEntriesForTranslate()
        local cloned = {}
        for index, entry in ipairs(state.entries or {}) do
            cloned[index] = {
                index = index,
                startFrame = entry.startFrame,
                endFrame = entry.endFrame,
                startText = entry.startText or "",
                endText = entry.endText or "",
                original = entry.text or "",
                translation = "",
            }
        end
        return cloned
    end

    local function populateTranslateTree()
        normalizeTranslateTree()
        if not controls.translateTree then
            return
        end
        local entries = state.translate.entries or {}
        UI.withUpdatesSuspended(controls.translateTree, function()
            controls.translateTree:Clear()
            for index, entry in ipairs(entries) do
                local item = controls.translateTree:NewItem()
                item.Text[0] = tostring(index)
                local startDisplay = entry.startText or Subtitle.framesToTimecode(entry.startFrame or 0, state.fps or 24.0)
                local endDisplay = entry.endText or Subtitle.framesToTimecode(entry.endFrame or 0, state.fps or 24.0)
                item.Text[1] = string.format("▸ %s\n◂ %s", startDisplay or "", endDisplay or "")
                item.Text[2] = entry.original or ""
                item.Text[3] = entry.translation or ""
                controls.translateTree:AddTopLevelItem(item)
            end
        end)
    end

    local function updateTranslateTreeRow(index, text)
        if not controls.translateTree then
            return
        end
        UI.withUpdatesSuspended(controls.translateTree, function()
            local item = controls.translateTree:TopLevelItem(index - 1)
            if item then
                item.Text[3] = text or ""
            end
        end)
    end

    local function updateTranslateOriginalRow(index, text)
        if not controls.translateTree then
            return
        end
        UI.withUpdatesSuspended(controls.translateTree, function()
            local item = controls.translateTree:TopLevelItem(index - 1)
            if item then
                item.Text[2] = text or ""
            end
        end)
    end

    local function selectTranslateRow(index)
        state.translate.selectedIndex = index
        local entry = state.translate.entries and state.translate.entries[index]
        if controls.translateTree then
            local item = controls.translateTree:TopLevelItem(index - 1)
            if item and controls.translateTree:CurrentItem() ~= item then
                controls.translateTree:SetCurrentItem(item)
            end
        end
        if controls.translateEditor then
            UI.withTranslateProgrammatic(function()
                controls.translateEditor.Text = entry and (entry.translation or "") or ""
            end)
        end
        if controls.translateSelectedButton then
            controls.translateSelectedButton.Enabled = not (state.translate.busy) and true
        end
    end

    local function ensureTranslateEntries(force)
        local tState = state.translate
        if not tState then
            return
        end
        if not force and tState.populated and #tState.entries > 0 then
            populateTranslateTree()
            refreshTranslateStatus()
            return
        end
        setTranslateStatus("copying")
        tState.entries = cloneEditEntriesForTranslate()
        tState.populated = true
        tState.selectedIndex = nil
        tState.totalTokens = 0
        populateTranslateTree()
        if controls.translateEditor then
            UI.withTranslateProgrammatic(function()
                controls.translateEditor.Text = ""
            end)
        end
        if controls.translateSelectedButton then
            controls.translateSelectedButton.Enabled = false
        end
        setTranslateStatus("idle")
    end

    local function initTranslateTab()
        if translateTabInitialized then
            normalizeTranslateTree()
            refreshTranslateStatus()
            return
        end
        translateTabInitialized = true
        if controls.translateProviderLabel then
            controls.translateProviderLabel.Text = UI.uiString("translate_provider_label")
        end
        if controls.translateTargetLabel then
            controls.translateTargetLabel.Text = UI.uiString("translate_target_label")
        end
        if controls.translateProviderCombo then
            controls.translateProviderCombo:Clear()
            controls.translateProviderCombo.PlaceholderText = UI.uiString("translate_provider_placeholder")
            local selectedIndex = 0
            for idx, label in ipairs(TRANSLATE_PROVIDER_LIST) do
                controls.translateProviderCombo:AddItem(label)
                if state.translate.provider == label then
                    selectedIndex = idx - 1
                end
            end
            controls.translateProviderCombo.CurrentIndex = selectedIndex
            state.translate.provider = controls.translateProviderCombo.CurrentText or TRANSLATE_PROVIDER_AZURE_LABEL
        end
        if controls.translateTargetCombo then
            controls.translateTargetCombo:Clear()
            controls.translateTargetCombo.PlaceholderText = UI.uiString("translate_target_placeholder")
            local labels = Translate.getGoogleLangLabels()
            local stored = state.translate.targetLabel
            local selectedIndex = 0
            for idx, label in ipairs(labels) do
                controls.translateTargetCombo:AddItem(label)
                if stored and stored == label then
                    selectedIndex = idx - 1
                end
            end
            controls.translateTargetCombo.CurrentIndex = selectedIndex
            state.translate.targetLabel = controls.translateTargetCombo.CurrentText
        end
        if controls.translateTransButton then
            controls.translateTransButton.Text = UI.uiString("translate_trans_button")
        end
        if controls.translateSelectedButton then
            controls.translateSelectedButton.Text = UI.uiString("translate_selected_button")
            controls.translateSelectedButton.Enabled = state.translate.selectedIndex ~= nil and not state.translate.busy
        end
        if controls.translateUpdateButton then
            controls.translateUpdateButton.Text = UI.uiString("translate_update_button")
        end
        if controls.translateEditor then
            controls.translateEditor.PlaceholderText = UI.uiString("translate_editor_placeholder")
        end
        normalizeTranslateTree()
        setTranslateStatus("idle")
    end

    local function getTargetLangCode(label)
        if label and label ~= "" then
            return LANG_CODE_MAP[label] or LANG_CODE_MAP["English"] or "en"
        end
        return LANG_CODE_MAP["English"] or "en"
    end

    local function composeTranslatePrompt(targetLabel)
        local target = targetLabel and Utils.trim(targetLabel) ~= "" and targetLabel or "English"
        local prefix = TRANSLATE_PREFIX_PROMPT:gsub("{target_lang}", target)
        local corePrompt = OPENAI_DEFAULT_SYSTEM_PROMPT
        if state and state.openaiFormat and type(state.openaiFormat.systemPrompt) == "string" then
            local trimmed = Utils.trim(state.openaiFormat.systemPrompt)
            if trimmed ~= "" then
                corePrompt = trimmed
            end
        end
        return table.concat({ prefix, corePrompt, TRANSLATE_SUFFIX_PROMPT }, "\n")
    end

    local function fetch_provider_secret(provider)
        local cleanProvider = Utils.trim(provider or "")
        if cleanProvider == "" then
            return nil, "missing_provider"
        end
        local cached = Translate.secretCache[cleanProvider]
        if cached and cached ~= "" then
            return cached
        end
        local url = string.format("%s/functions/v1/getApiKey?provider=%s", SUPABASE_URL, Utils.urlEncode(cleanProvider))
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
        local apiKey = decoded.api_key or decoded.apiKey or decoded.key
        if not apiKey or apiKey == "" then
            return nil, "missing_key"
        end
        Translate.secretCache[cleanProvider] = apiKey
        return apiKey
    end

    local function buildTranslateContext(entries, index)
        local beforeParts, afterParts = {}, {}
        if TRANSLATE_CONTEXT_WINDOW > 0 then
            for offset = 1, TRANSLATE_CONTEXT_WINDOW do
                local prev = entries[index - offset]
                if not prev then break end
                if prev.original and prev.original ~= "" then
                    table.insert(beforeParts, 1, prev.original)
                end
            end
            for offset = 1, TRANSLATE_CONTEXT_WINDOW do
                local nxt = entries[index + offset]
                if not nxt then break end
                if nxt.original and nxt.original ~= "" then
                    table.insert(afterParts, nxt.original)
                end
            end
        end
        return table.concat(beforeParts, "\n"), table.concat(afterParts, "\n")
    end

    function GLMService.buildRequestPayload(sentence, prefixText, suffixText, targetLabel)
        local prompt = composeTranslatePrompt(targetLabel)
        local messages = {
            { role = "system", content = prompt },
        }
        local ctxParts = {}
        if prefixText and Utils.trim(prefixText) ~= "" then
            table.insert(ctxParts, prefixText)
        end
        if suffixText and Utils.trim(suffixText) ~= "" then
            table.insert(ctxParts, suffixText)
        end
        if #ctxParts > 0 then
            table.insert(messages, { role = "assistant", content = table.concat(ctxParts, "\nCONTEXT (do not translate)\n") })
        end
        table.insert(messages, { role = "user", content = string.format("<<< Sentence >>>\n%s", sentence or "") })

        local payloadTable = {
            model = GLM_MODEL,
            messages = messages,
            temperature = GLM_TEMPERATURE,
            thinking = { type = "disabled" },
        }
        return json.encode(payloadTable)
    end

    function GLMService.parseResponseBody(body)
        if type(body) ~= "string" or body == "" then
            return nil, 0, "empty_response"
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" then
            return nil, 0, "decode_failed"
        end

        local choices = decoded.choices
        if type(choices) ~= "table" or not choices[1] or not choices[1].message then
            return nil, 0, "invalid_response"
        end

        local content = Utils.trim(choices[1].message.content or "")
        if content == "" then
            return nil, 0, "empty_translation"
        end

        local usage = decoded.usage
        local tokens = 0
        if type(usage) == "table" then
            tokens = tonumber(usage.total_tokens or usage.totalTokens or 0) or 0
        end
        return content, tokens, nil
    end

    function GLMService.requestTranslation(sentence, prefixText, suffixText, targetLabel, apiKey)
        local payload = GLMService.buildRequestPayload(sentence, prefixText, suffixText, targetLabel)
        local headers = {
            Authorization = "Bearer " .. apiKey,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
        }

        local body, status = Services.httpPostJson(GLM_API_URL, payload, headers, GLM_TIMEOUT)
        if not body then
            return nil, 0, status or "request_failed"
        end

        return GLMService.parseResponseBody(body)
    end

    function Azure.resolveCredential()
        local key = Utils.trim(state.azure and state.azure.apiKey or "")
        local region = Utils.trim(state.azure and state.azure.region or "")
        if key ~= "" and region ~= "" then
            return key, region
        end
        local apiKey, err = fetch_provider_secret(AZURE_SUPABASE_PROVIDER)
        if not apiKey then
            return nil, nil, err
        end
        return apiKey, AZURE_FALLBACK_REGION
    end

    function Azure.parseResponseBody(body)
        local ok, decoded = pcall(json.decode, body or "")
        if not ok or type(decoded) ~= "table" then
            return nil, 0, "decode_failed"
        end
        local first = decoded[1]
        if type(first) ~= "table" then
            return nil, 0, "invalid_response"
        end
        local translations = first.translations
        if type(translations) ~= "table" or type(translations[1]) ~= "table" then
            return nil, 0, "translation_failed"
        end
        local translated = translations[1].text
        if not translated or Utils.trim(translated) == "" then
            return nil, 0, "empty_translation"
        end
        return translated, 0, nil
    end

    function Azure.requestTranslation(text, targetCode, baseUrl, apiKey, region)
        local cleanBase = Utils.trim(baseUrl or "")
        if cleanBase == "" then
            cleanBase = AZURE_DEFAULT_BASE_URL
        end
        cleanBase = cleanBase:gsub("/+$", "")
        local query = string.format("?api-version=3.0&to=%s", Utils.urlEncode(targetCode or "en"))
        local url = cleanBase .. "/translate" .. query
        local payload = json.encode({
            { text = text or "" },
        })
        local headers = {
            ["Ocp-Apim-Subscription-Key"] = apiKey,
            ["Ocp-Apim-Subscription-Region"] = region,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
        }
        local body, status = Services.httpPostJson(url, payload, headers, AZURE_TIMEOUT)
        if not body then
            return nil, 0, status or "request_failed"
        end
        return Azure.parseResponseBody(body)
    end

function OpenAIService.buildRequestPayload(sentence, prefixText, suffixText, targetLabel, model, temperature)
        local prompt = composeTranslatePrompt(targetLabel)
        local messages = {
            { role = "system", content = prompt },
        }
        local ctxParts = {}
        if prefixText and Utils.trim(prefixText) ~= "" then
            table.insert(ctxParts, prefixText)
        end
        if suffixText and Utils.trim(suffixText) ~= "" then
            table.insert(ctxParts, suffixText)
        end
        if #ctxParts > 0 then
            table.insert(messages, { role = "assistant", content = table.concat(ctxParts, "\nCONTEXT (do not translate)\n") })
        end
        table.insert(messages, { role = "user", content = string.format("<<< Sentence >>>\n%s", sentence or "") })

        local payloadTable = {
            model = model,
            messages = messages,
            temperature = temperature or OPENAI_FORMAT_DEFAULT_TEMPERATURE,
        }
        return json.encode(payloadTable)
end

function OpenAIService.parseResponseBody(body)
    return GLMService.parseResponseBody(body)
end

function OpenAIService.requestTranslation(sentence, prefixText, suffixText, targetLabel, config)
        local model = config and config.model
        if not model or Utils.trim(model) == "" then
            return nil, 0, "openai_missing_model"
        end
        local baseUrl = Utils.trim(config.baseUrl or "")
        if baseUrl == "" then
            baseUrl = OPENAI_FORMAT_DEFAULT_BASE_URL
        end
        local apiKey = Utils.trim(config.apiKey or "")
        if apiKey == "" then
            return nil, 0, "openai_missing_key"
        end
        local temperature = tonumber(config.temperature) or OPENAI_FORMAT_DEFAULT_TEMPERATURE
        if temperature < 0 then
            temperature = 0
        elseif temperature > 1 then
            temperature = 1
        end

        local payload = OpenAIService.buildRequestPayload(sentence, prefixText, suffixText, targetLabel, model, temperature)
        local headers = {
            Authorization = "Bearer " .. apiKey,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = string.format("%s/%s", SCRIPT_NAME, SCRIPT_VERSION),
        }
        local apiUrl = baseUrl:gsub("/+$", "") .. "/v1/chat/completions"
        local body, status = Services.httpPostJson(apiUrl, payload, headers, OPENAI_FORMAT_TIMEOUT)
        if not body then
            return nil, 0, status or "request_failed"
        end
    local translation, tokens, err = OpenAIService.parseResponseBody(body)
        if not translation then
            local ok, decoded = pcall(json.decode, body)
            if ok and type(decoded) == "table" and decoded.error and decoded.error.message then
                return nil, 0, decoded.error.message
            end
        end
        return translation, tokens, err
    end

    function GLMService.translateEntries(entries, targetLabel)
        if not entries or #entries == 0 then
            return nil, "no_entries"
        end

        --setTranslateStatus("fetching_key")
        local apiKey, fetchErr = fetch_provider_secret(GLM_SUPABASE_PROVIDER)
        if not apiKey then
            return nil, fetchErr or "missing_key"
        end

        local totalTokens = 0
        local total = #entries
        local concurrency = math.max(1, state.translate and state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)
        local processed = 0

        setTranslateStatus("progress", processed, total, totalTokens)

        local useParallel = concurrency > 1

        if useParallel then
            local startIndex = 1
            while startIndex <= total do
                local batchEnd = math.min(total, startIndex + concurrency - 1)
                local batchIndices = {}
                for idx = startIndex, batchEnd do
                    table.insert(batchIndices, idx)
                end

                local attempts = {}
                for _, idx in ipairs(batchIndices) do
                    attempts[idx] = 0
                end

                local pending = {}
                for _, idx in ipairs(batchIndices) do
                    table.insert(pending, idx)
                end

                while #pending > 0 do
                    local tasks = {}
                    for _, idx in ipairs(pending) do
                        local entry = entries[idx]
                        local prefixText, suffixText = buildTranslateContext(entries, idx)
                        table.insert(tasks, {
                            index = idx,
                            payload = GLMService.buildRequestPayload(entry.original or "", prefixText, suffixText, targetLabel),
                        })
                    end

                    local results, batchErr = ParallelServices.runCurlParallel(tasks, {
                        apiUrl = GLM_API_URL,
                        timeout = GLM_TIMEOUT,
                        parallelLimit = concurrency,
                        headers = {
                            string.format("Authorization: Bearer %s", apiKey),
                            "Content-Type: application/json",
                            string.format("User-Agent: %s/%s", SCRIPT_NAME, SCRIPT_VERSION),
                        },
                        payloadPrefix = "glm_payload",
                        outputPrefix = "glm_output",
                    })
                    if not results then
                        if processed == 0 then
                            useParallel = false
                            break
                        end
                        local failIdx = pending[1]
                        local errMsg = batchErr or "parallel_execution_failed"
                        if failIdx then
                            processed = processed + 1
                            local fallback = string.format("[Error: %s]", tostring(errMsg))
                            entries[failIdx].translation = fallback
                            updateTranslateTreeRow(failIdx, fallback)
                            setTranslateStatus("progress", processed, total, totalTokens)
                        end
                        return nil, errMsg, totalTokens
                    end

                    local nextPending = {}

                    for _, task in ipairs(tasks) do
                        local result = results[task.index]
                        if result and result.success then
                            local entry = entries[task.index]
                            entry.translation = result.translation
                            updateTranslateTreeRow(task.index, result.translation)
                            totalTokens = totalTokens + (result.tokens or 0)
                            processed = processed + 1
                            setTranslateStatus("progress", processed, total, totalTokens)
                        else
                            local errMsg = (result and result.err) or batchErr or "translation_failed"
                                                            if errMsg == "parallel_execution_failed" then
                                                                errMsg = "openai_parallel_failed"
                                                            end
                                                            attempts[task.index] = (attempts[task.index] or 0) + 1
                                                            if attempts[task.index] < GLM_MAX_RETRY then
                                                                table.insert(nextPending, task.index)
                                                            else
                                                                processed = processed + 1
                                                                local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
                                                                entries[task.index].translation = fallback
                                                                updateTranslateTreeRow(task.index, fallback)
                                                                setTranslateStatus("progress", processed, total, totalTokens)
                                                            end                        end
                    end

                    if #nextPending == 0 then
                        pending = {}
                    else
                        pending = nextPending
                    end
                end

                if not useParallel then
                    break
                end

                startIndex = batchEnd + 1
            end
        end

        if not useParallel then
            totalTokens = 0
            processed = 0
            setTranslateStatus("progress", processed, total, totalTokens)

            for startIndex = 1, total, concurrency do
                local batchEnd = math.min(total, startIndex + concurrency - 1)
                for index = startIndex, batchEnd do
                    local entry = entries[index]
                    local prefixText, suffixText = buildTranslateContext(entries, index)
                    local success = false
                    local lastError = nil

                    for attempt = 1, GLM_MAX_RETRY do
                        local translation, tokens, errMsg = GLMService.requestTranslation(entry.original or "", prefixText, suffixText, targetLabel, apiKey)
                        if translation then
                            entry.translation = translation
                            updateTranslateTreeRow(index, translation)
                            totalTokens = totalTokens + (tokens or 0)
                            success = true
                            break
                        else
                            lastError = errMsg
                        end
                    end

                    processed = processed + 1
                    setTranslateStatus("progress", processed, total, totalTokens)

                    if not success then
                        local fallback = string.format("[Error: %s]", tostring(lastError or "failed"))
                        entry.translation = fallback
                        updateTranslateTreeRow(index, fallback)
                    end
                end
            end
        end

        return totalTokens, nil
    end

    function Azure.translateEntries(entries, targetLabel)
        if not entries or #entries == 0 then
            return nil, "no_entries"
        end

        local targetCode = getTargetLangCode(targetLabel)
        if not targetCode or targetCode == "" then
            targetCode = "en"
        end

        local userKey = Utils.trim(state.azure and state.azure.apiKey or "")
        local userRegion = Utils.trim(state.azure and state.azure.region or "")
        if userKey == "" or userRegion == "" then
            --setTranslateStatus("fetching_key")
        end
        local apiKey, region, fetchErr = Azure.resolveCredential()
        if not apiKey then
            return nil, fetchErr or "missing_key"
        end
        if not region or region == "" then
            region = AZURE_FALLBACK_REGION
        end
        local baseUrl = state.azure and state.azure.baseUrl or AZURE_DEFAULT_BASE_URL

        local totalTokens = 0
        local total = #entries
        local processed = 0
        local concurrency = math.max(1, state.translate and state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)
        local useParallel = concurrency > 1

        local cleanBase = Utils.trim(baseUrl or "")
        if cleanBase == "" then
            cleanBase = AZURE_DEFAULT_BASE_URL
        end
        cleanBase = cleanBase:gsub("/+$", "")
        baseUrl = cleanBase
        local translateUrl = cleanBase .. "/translate" .. string.format("?api-version=3.0&to=%s", Utils.urlEncode(targetCode or "en"))
        local headers = {
            string.format("Ocp-Apim-Subscription-Key: %s", apiKey),
            string.format("Ocp-Apim-Subscription-Region: %s", region),
            "Content-Type: application/json",
            string.format("User-Agent: %s/%s", SCRIPT_NAME, SCRIPT_VERSION),
        }

        setTranslateStatus("progress", processed, total, totalTokens)

        if useParallel then
            local startIndex = 1
            while startIndex <= total do
                local batchEnd = math.min(total, startIndex + concurrency - 1)
                local tasks = {}
                for idx = startIndex, batchEnd do
                    local entry = entries[idx]
                    table.insert(tasks, {
                        index = idx,
                        payload = json.encode({
                            { text = entry.original or "" },
                        }),
                        url = translateUrl,
                    })
                end

                local results, batchErr = ParallelServices.runCurlParallel(tasks, {
                    timeout = AZURE_TIMEOUT,
                    parallelLimit = concurrency,
                    headers = headers,
                    payloadPrefix = "azure_payload",
                    outputPrefix = "azure_output",
                    parseResponse = Azure.parseResponseBody,
                })
                if not results then
                    if processed == 0 then
                        useParallel = false
                        break
                    end
                    local failIdx = tasks[1] and tasks[1].index or startIndex
                    local errMsg = batchErr or "parallel_execution_failed"
                    local fallback = string.format("[Error: %s]", tostring(errMsg))
                    if failIdx and entries[failIdx] then
                        entries[failIdx].translation = fallback
                        updateTranslateTreeRow(failIdx, fallback)
                        processed = processed + 1
                        setTranslateStatus("progress", processed, total, totalTokens)
                    end
                    return nil, errMsg, totalTokens
                end

                for _, task in ipairs(tasks) do
                    local result = results[task.index]
                    if result and result.success then
                        local translation = result.translation
                        entries[task.index].translation = translation
                        updateTranslateTreeRow(task.index, translation)
                        processed = processed + 1
                        setTranslateStatus("progress", processed, total, totalTokens)
                    else
                        local errMsg = (result and result.err) or batchErr or "translation_failed"
                        local fallback = string.format("[Error: %s]", tostring(errMsg))
                        entries[task.index].translation = fallback
                        updateTranslateTreeRow(task.index, fallback)
                        processed = processed + 1
                        setTranslateStatus("progress", processed, total, totalTokens)
                    end
                end

                startIndex = batchEnd + 1
            end
        end

        if (not useParallel) or (processed < total) then
            processed = 0
            setTranslateStatus("progress", processed, total, totalTokens)
            for index, entry in ipairs(entries) do
                local translation, _, errMsg = Azure.requestTranslation(entry.original or "", targetCode, baseUrl, apiKey, region)
                if translation then
                    entry.translation = translation
                    updateTranslateTreeRow(index, translation)
                else
                    local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
                    entry.translation = fallback
                    updateTranslateTreeRow(index, fallback)
                end
                processed = processed + 1
                setTranslateStatus("progress", processed, total, totalTokens)
            end
        end

        return totalTokens, nil
    end

    function OpenAIService.translateEntries(entries, targetLabel)
        if not entries or #entries == 0 then
            return nil, "no_entries"
        end

        OpenAIService.applyConfigFromControls()
        Storage.ensureOpenAIModelList(state.openaiFormat)
        local selected = Storage.getOpenAISelectedModel(state.openaiFormat)
        if not selected then
            return nil, "openai_missing_model"
        end
        local apiKey = Utils.trim(state.openaiFormat.apiKey or "")
        if apiKey == "" then
            return nil, "openai_missing_key"
        end
        local baseUrl = Utils.trim(state.openaiFormat.baseUrl or "")
        if baseUrl == "" then
            baseUrl = OPENAI_FORMAT_DEFAULT_BASE_URL
        end
        local temperature = tonumber(state.openaiFormat.temperature) or OPENAI_FORMAT_DEFAULT_TEMPERATURE
        if temperature < 0 then
            temperature = 0
        elseif temperature > 1 then
            temperature = 1
        end

        local totalTokens = 0
        local total = #entries
        local concurrency = math.max(1, state.translate and state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)
        local processed = 0

        setTranslateStatus("progress", processed, total, totalTokens)

        local useParallel = concurrency > 1
        local apiUrl = baseUrl:gsub("/*$", "") .. "/v1/chat/completions"

        if useParallel then
            local startIndex = 1
            while startIndex <= total do
                local batchEnd = math.min(total, startIndex + concurrency - 1)
                local batchIndices = {}
                for idx = startIndex, batchEnd do
                    table.insert(batchIndices, idx)
                end

                local attempts = {}
                for _, idx in ipairs(batchIndices) do
                    attempts[idx] = 0
                end

                local pending = {}
                for _, idx in ipairs(batchIndices) do
                    table.insert(pending, idx)
                end

                while #pending > 0 do
                    local tasks = {}
                    for _, idx in ipairs(pending) do
                        local entry = entries[idx]
                        local prefixText, suffixText = buildTranslateContext(entries, idx)
                        table.insert(tasks, {
                            index = idx,
                            payload = OpenAIService.buildRequestPayload(entry.original or "", prefixText, suffixText, targetLabel, selected.name, temperature),
                        })
                    end

                    local results, batchErr = ParallelServices.runCurlParallel(tasks, {
                        apiUrl = apiUrl,
                        timeout = OPENAI_FORMAT_TIMEOUT,
                        parallelLimit = concurrency,
                        headers = {
                            string.format("Authorization: Bearer %s", apiKey),
                            "Content-Type: application/json",
                            string.format("User-Agent: %s/%s", SCRIPT_NAME, SCRIPT_VERSION),
                        },
                        payloadPrefix = "openai_payload",
                        outputPrefix = "openai_output",
                        parseResponse = OpenAIService.parseResponseBody,
                    })
                    if not results then
                        if processed == 0 then
                            useParallel = false
                            break
                        end
                        local failIdx = pending[1]
                        local errMsg = batchErr or "parallel_execution_failed"
                        if errMsg == "parallel_execution_failed" then
                            errMsg = "openai_parallel_failed"
                        end
                        if failIdx then
                            processed = processed + 1
                            local fallback = string.format("[Error: %s]", tostring(errMsg))
                            entries[failIdx].translation = fallback
                            updateTranslateTreeRow(failIdx, fallback)
                            setTranslateStatus("progress", processed, total, totalTokens)
                        end
                        return nil, errMsg, totalTokens
                    end

                    local nextPending = {}

                    for _, task in ipairs(tasks) do
                        local result = results[task.index]
                        if result and result.success then
                            local entry = entries[task.index]
                            entry.translation = result.translation
                            updateTranslateTreeRow(task.index, result.translation)
                            totalTokens = totalTokens + (result.tokens or 0)
                            processed = processed + 1
                            setTranslateStatus("progress", processed, total, totalTokens)
                        else
                            local errMsg = (result and result.err) or batchErr or "translation_failed"
                            attempts[task.index] = (attempts[task.index] or 0) + 1
                            if attempts[task.index] < GLM_MAX_RETRY then
                                table.insert(nextPending, task.index)
                            else
                                processed = processed + 1
                                local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
                                entries[task.index].translation = fallback
                                updateTranslateTreeRow(task.index, fallback)
                                setTranslateStatus("progress", processed, total, totalTokens)
                            end
                        end
                    end

                    if #nextPending == 0 then
                        pending = {}
                    else
                        pending = nextPending
                    end
                end

                if not useParallel then
                    break
                end

                startIndex = batchEnd + 1
            end
        end

        if not useParallel then
            totalTokens = 0
            processed = 0
            setTranslateStatus("progress", processed, total, totalTokens)

            local requestConfig = {
                baseUrl = baseUrl,
                apiKey = apiKey,
                model = selected.name,
                temperature = temperature,
            }

            for startIndex = 1, total, concurrency do
                local batchEnd = math.min(total, startIndex + concurrency - 1)
                for index = startIndex, batchEnd do
                    local entry = entries[index]
                    local prefixText, suffixText = buildTranslateContext(entries, index)
                    local success = false
                    local lastError = nil

                    for attempt = 1, GLM_MAX_RETRY do
                        local translation, tokens, errMsg = OpenAIService.requestTranslation(entry.original or "", prefixText, suffixText, targetLabel, requestConfig)
                        if translation then
                            entry.translation = translation
                            updateTranslateTreeRow(index, translation)
                            totalTokens = totalTokens + (tokens or 0)
                            success = true
                            break
                        else
                            lastError = errMsg
                        end
                    end

                    processed = processed + 1
                    setTranslateStatus("progress", processed, total, totalTokens)

                    if not success then
                        local fallback = string.format("[Error: %s]", tostring(lastError or "failed"))
                        entry.translation = fallback
                        updateTranslateTreeRow(index, fallback)
                    end
                end
            end
        end

        return totalTokens, nil
    end

    local function performTranslateWorkflow()
        if state.translate.busy then
            return false
        end

        OpenAIService.applyConfigFromControls()

        ensureTranslateEntries(false)
        local entries = state.translate.entries or {}
        if #entries == 0 then
            setTranslateStatus("no_entries")
            return false
        end

        local provider = controls.translateProviderCombo and controls.translateProviderCombo.CurrentText or state.translate.provider
        if not provider or Utils.trim(provider) == "" then
            provider = TRANSLATE_PROVIDER_AZURE_LABEL
        end
        state.translate.provider = provider
        local translateFunc
        if provider == TRANSLATE_PROVIDER_AZURE_LABEL then
            translateFunc = Azure.translateEntries
        elseif provider == TRANSLATE_PROVIDER_GL_LABEL then
            translateFunc = GLMService.translateEntries
        elseif provider == TRANSLATE_PROVIDER_OPENAI_LABEL then
            translateFunc = OpenAIService.translateEntries
        else
            local en, cn = resolveTranslateErrorPair("provider_not_supported")
            show_dynamic_message(en, cn)
            setTranslateStatus("failed", resolveTranslateError("provider_not_supported"))
            return false
        end

        local targetLabel = controls.translateTargetCombo and controls.translateTargetCombo.CurrentText or state.translate.targetLabel or "English"
        state.translate.targetLabel = targetLabel

        state.translate.busy = true
        setTranslateControlsEnabled(false)

        local ok, totalTokens, err = pcall(translateFunc, entries, targetLabel)

        state.translate.busy = false
        setTranslateControlsEnabled(true)

        if not ok then
            state.translate.totalTokens = 0
            local en, cn = resolveTranslateErrorPair(totalTokens or "translation_failed")
            show_dynamic_message(en, cn)
            setTranslateStatus("failed", resolveTranslateError(totalTokens) or tostring(totalTokens))
            return false
        end

        if not totalTokens then
            state.translate.totalTokens = 0
            local en, cn = resolveTranslateErrorPair(err or "translation_failed")
            show_dynamic_message(en, cn)
            setTranslateStatus("failed", resolveTranslateError(err or "translation_failed"))
            return false
        end

        state.translate.totalTokens = totalTokens
        setTranslateStatus("success", #entries, totalTokens)
        notifyTranslateStatus("success", { #entries, totalTokens }, { #entries, totalTokens })
        return true
    end

    local function translateSingleEntry(index, targetLabel)
        OpenAIService.applyConfigFromControls()
        local entries = state.translate.entries or {}
        local entry = entries[index]
        if not entry then
            setTranslateStatus("failed", resolveTranslateError("no_selection"))
            return false
        end
        local provider = state.translate.provider or TRANSLATE_PROVIDER_AZURE_LABEL
        if provider == TRANSLATE_PROVIDER_AZURE_LABEL then
            local targetCode = getTargetLangCode(targetLabel)
            if not targetCode or targetCode == "" then
                targetCode = "en"
            end
            local userKey = Utils.trim(state.azure and state.azure.apiKey or "")
            local userRegion = Utils.trim(state.azure and state.azure.region or "")
            if userKey == "" or userRegion == "" then
                --setTranslateStatus("fetching_key")
            end
            local apiKey, region, fetchErr = Azure.resolveCredential()
            if not apiKey then
                setTranslateStatus("failed", resolveTranslateError(fetchErr or "missing_key"))
                return false
            end
            if not region or region == "" then
                region = AZURE_FALLBACK_REGION
            end
            local baseUrl = state.azure and state.azure.baseUrl or AZURE_DEFAULT_BASE_URL
            setTranslateStatus("progress", 0, 1, state.translate.totalTokens or 0)
            local translation, _, errMsg = Azure.requestTranslation(entry.original or "", targetCode, baseUrl, apiKey, region)
            if translation then
                entry.translation = translation
                updateTranslateTreeRow(index, translation)
                state.translate.totalTokens = state.translate.totalTokens or 0
                setTranslateStatus("success", 1, state.translate.totalTokens)
                return true
            end
            local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
            entry.translation = fallback
            updateTranslateTreeRow(index, fallback)
            setTranslateStatus("success", 1, state.translate.totalTokens)
            return true
        elseif provider == TRANSLATE_PROVIDER_GL_LABEL then
            --setTranslateStatus("fetching_key")
            local apiKey, fetchErr = fetch_provider_secret(GLM_SUPABASE_PROVIDER)
            if not apiKey then
                setTranslateStatus("failed", resolveTranslateError(fetchErr or "missing_key"))
                return false
            end

            local beforeCtx, afterCtx = buildTranslateContext(entries, index)
            setTranslateStatus("progress", 0, 1, state.translate.totalTokens or 0)

            local translation, tokens, errMsg = GLMService.requestTranslation(entry.original or "", beforeCtx, afterCtx, targetLabel, apiKey)
            if translation then
                entry.translation = translation
                updateTranslateTreeRow(index, translation)
                state.translate.totalTokens = (state.translate.totalTokens or 0) + (tokens or 0)
                setTranslateStatus("success", 1, state.translate.totalTokens)
                return true
            end

            local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
            entry.translation = fallback
            updateTranslateTreeRow(index, fallback)
            setTranslateStatus("success", 1, state.translate.totalTokens)
            return true
        elseif provider == TRANSLATE_PROVIDER_OPENAI_LABEL then
            OpenAIService.applyConfigFromControls()
            Storage.ensureOpenAIModelList(state.openaiFormat)
            local selected = Storage.getOpenAISelectedModel(state.openaiFormat)
            if not selected then
                setTranslateStatus("failed", resolveTranslateError("openai_missing_model"))
                return false
            end
            local apiKey = Utils.trim(state.openaiFormat.apiKey or "")
            if apiKey == "" then
                setTranslateStatus("failed", resolveTranslateError("openai_missing_key"))
                return false
            end
            local baseUrl = Utils.trim(state.openaiFormat.baseUrl or "")
            if baseUrl == "" then
                baseUrl = OPENAI_FORMAT_DEFAULT_BASE_URL
            end
            local temperature = tonumber(state.openaiFormat.temperature) or OPENAI_FORMAT_DEFAULT_TEMPERATURE
            if temperature < 0 then
                temperature = 0
            elseif temperature > 1 then
                temperature = 1
            end

            local beforeCtx, afterCtx = buildTranslateContext(entries, index)
            setTranslateStatus("progress", 0, 1, state.translate.totalTokens or 0)

            local translation, tokens, errMsg = OpenAIService.requestTranslation(entry.original or "", beforeCtx, afterCtx, targetLabel, {
                baseUrl = baseUrl,
                apiKey = apiKey,
                model = selected.name,
                temperature = temperature,
            })
            if translation then
                entry.translation = translation
                updateTranslateTreeRow(index, translation)
                state.translate.totalTokens = (state.translate.totalTokens or 0) + (tokens or 0)
                setTranslateStatus("success", 1, state.translate.totalTokens)
                return true
            end

            local fallback = string.format("[Error: %s]", tostring(errMsg or "failed"))
            entry.translation = fallback
            updateTranslateTreeRow(index, fallback)
            setTranslateStatus("success", 1, state.translate.totalTokens)
            return true
        end

        setTranslateStatus("failed", resolveTranslateError("provider_not_supported"))
        return false
    end


translate.setStatus = setTranslateStatus
translate.resolveError = resolveTranslateError
translate.handleVerify = handleOpenAIVerify
translate.handleAddModel = handleOpenAIAddModel
translate.handleDeleteModel = handleOpenAIDeleteModel
translate.refreshStatus = refreshTranslateStatus
translate.setControlsEnabled = setTranslateControlsEnabled
translate.normalizeTree = normalizeTranslateTree
translate.resetState = resetTranslateState
translate.ensureEntries = ensureTranslateEntries
translate.initTab = initTranslateTab
translate.performWorkflow = performTranslateWorkflow
translate.translateSingleEntry = translateSingleEntry
translate.updateTreeRow = updateTranslateTreeRow
translate.updateOriginalRow = updateTranslateOriginalRow
translate.selectRow = selectTranslateRow
-- Translate Tab: (moved) Export Translated Subtitles
function Subtitle.exportTranslatedSubtitles()
    local entries = state.translate.entries or {}
    if #entries == 0 then
        translate.setStatus("no_entries")
        return false
    end
    if not state.timeline then
        translate.setStatus("failed", translate.resolveError("no_timeline"))
        UI.updateStatus("no_timeline")
        return false
    end

    translate.setStatus("updating")
    local exportEntries = {}
    for idx, entry in ipairs(entries) do
        local translation = Utils.trim(entry.translation or "")
        if translation == "" then
            translation = entry.original or ""
        end
        exportEntries[idx] = {
            startFrame = entry.startFrame,
            endFrame = entry.endFrame,
            text = translation,
        }
    end

    local tempPath = Subtitle.nextSrtPathForTimeline(state.timeline)
    local ok, err = Subtitle.writeSrt(exportEntries, tempPath, state.startFrame or 0, state.fps or 24.0)
    if not ok then
        local message = UI.messageString(err or "write_failed") or translate.resolveError(err or "translation_failed")
        translate.setStatus("failed", message)
        UI.updateStatus(err or "write_failed")
        return false
    end

    local success, importErr = Subtitle.importSrtToTimeline(tempPath)
    if not success then
        local message = UI.messageString(importErr or "import_failed") or translate.resolveError(importErr or "translation_failed")
        translate.setStatus("failed", message)
        UI.updateStatus(importErr or "import_failed")
        return false
    end

    translate.setStatus("updated")
    return true
end

-- Subtitle Domain: Timeline IO / SRT / Jump
-- ==============================================================
function Subtitle.refreshFromTimeline()
    local ok, err = Subtitle.collectSubtitles()
    if not ok then
        UI.updateStatus(err or "cannot_read_subtitles")
        state.entries = {}
        if controls.tree then
            UI.withUpdatesSuspended(controls.tree, function()
                controls.tree:Clear()
            end)
        end
        state.highlightedRows = {}
        state.stickyHighlights = {}
        state.findMatches = nil
        state.findIndex = nil
        state.currentMatchPos = nil
        state.currentMatchHighlight = nil
        UI.setEditorText("")
        translate.resetState()
        return false
    end
    translate.resetState()
    UI.populateTree()
    UI.updateStatus("loaded_count", #state.entries)
    return true
end

function UI.setRowHighlight(rowIndex, color)
    if not controls.tree then
        return
    end
    local item = controls.tree:TopLevelItem(rowIndex - 1)
    if not item then
        return
    end
    local targetColor = color or transparentColor
    item.BackgroundColor[2] = targetColor
    if color then
        state.highlightedRows[rowIndex] = true
    else
        state.highlightedRows[rowIndex] = nil
    end
end

if controls.mainTabs then
    local initialTabs = uiText.cn.tabs or { "字幕编辑", "翻译", "设置" }
    for _, title in ipairs(initialTabs) do
        controls.mainTabs:AddTab(title)
    end
    if controls.mainStack then
        controls.mainTabs.CurrentIndex = 0
        controls.mainStack.CurrentIndex = 0
    end
end

translate.initTab()

function UI.refreshUpdateNotice()
    if not controls.updateLabel then
        return
    end
    local info = state.updateInfo
    if type(info) ~= "table" then
        controls.updateLabel.Text = ""
        controls.updateLabel.Visible = false
        return
    end
    local lang = UI.currentLanguage()
    local text
    if lang == "en" then
        text = info.en or info.cn
    else
        text = info.cn or info.en
    end
    text = Utils.trim(text or "")
    if text ~= "" then
        controls.updateLabel.Text = text
        controls.updateLabel.Visible = true
        return
    end
    controls.updateLabel.Text = ""
    controls.updateLabel.Visible = false
end

function UI.buildUpdateMessage(payload, lang, latest, current)
    local messageKey = lang == "cn" and "cn" or "en"
    local baseText = nil
    if type(payload) == "table" then
        baseText = payload[messageKey] or payload[lang == "cn" and "zh" or nil]
    end
    local parts = {}
    baseText = Utils.trim(baseText or "")
    if baseText ~= "" then
        table.insert(parts, baseText)
    end
    local readableCurrent = Utils.trim(current or "")
    if readableCurrent == "" then
        readableCurrent = (lang == "cn") and "未知" or "unknown"
    end
    local line
    if lang == "cn" then
        line = string.format("发现新版本：%s → %s，请前往购买页下载最新版本。", readableCurrent,latest)
    else
        line = string.format("Update: %s → %s, Download on your purchase page.", readableCurrent,latest)
    end
    table.insert(parts, line)
    return table.concat(parts, "\n")
end

function App.checkForUpdates()
    local ok, result = pcall(Services.supabaseCheckUpdate, SCRIPT_NAME)
    if not ok then
        print(string.format("[Update] Check failed: %s", tostring(result)))
        return
    end
    if type(result) ~= "table" then
        return
    end
    local latest = Utils.trim(tostring(result.latest or ""))
    if latest == "" then
        return
    end
    local current = Utils.trim(tostring(SCRIPT_VERSION or ""))
    if latest == current then
        return
    end
    local info = {
        latest = latest,
        current = current,
        cn = UI.buildUpdateMessage(result, "cn", latest, current),
        en = UI.buildUpdateMessage(result, "en", latest, current),
    }
    state.updateInfo = info
    UI.refreshUpdateNotice()
    local readableCurrent = current ~= "" and current or "unknown"
    print(string.format("[Update] Latest version %s available (current %s).", latest, readableCurrent))
end

function UI.updateStatus(key, ...)
    state.lastStatusKey = key
    state.lastStatusArgs = { ... }

    if not key then
        it.StatusLabel.Text = ""
        return
    end

    local template = UI.messageString(key)
    if template then
        it.StatusLabel.Text = string.format(template, ...)
        return
    end

    local text = tostring(key)
    if select('#', ...) > 0 then
        text = string.format(text, ...)
    end
    it.StatusLabel.Text = text
end

-- ==============================================================
-- Editor Tab: Controller & Helpers (find/replace/jump/update)
-- ==============================================================
function UI.setEditorText(text)
    UI.withEditorProgrammatic(function()
        controls.editor.Text = text or ""
    end)
end

function UI.clearFindHighlights(preserveIfStillMatch)
    local current = state.currentMatchHighlight
    if not current then return end
    state.currentMatchHighlight = nil

    local preserve = false
    if preserveIfStillMatch and state.findQuery and state.findQuery ~= "" then
        local entry = state.entries[current]
        local text = entry and entry.text or ""
        preserve = text:find(state.findQuery, 1, true) ~= nil
    end

    if preserve or state.stickyHighlights[current] then
        UI.setRowHighlight(current, findHighlightColor)
    else
        UI.setRowHighlight(current, nil)
    end
end

-- ✅ 新增：每次开始新查询前，清掉“所有行”的查找高亮
--（替换后的条目也使用 findHighlightColor，这里通过颜色判断来识别并清理）
function UI.clearAllFindHighlights()
    local toClear = {}
    for index in pairs(state.highlightedRows or {}) do
        if not state.stickyHighlights[index] then
            table.insert(toClear, index)
        end
    end
    if controls.tree then
        UI.withUpdatesSuspended(controls.tree, function()
            for _, index in ipairs(toClear) do
                UI.setRowHighlight(index, nil)
            end
        end)
    else
        for _, index in ipairs(toClear) do
            UI.setRowHighlight(index, nil)
        end
    end
    state.currentMatchHighlight = nil
    state.currentMatchPos = nil
end


function Subtitle.performTimelineJump(entry)
    if not state.timeline then
        return
    end
    local resolve = state.resolve
    if not resolve then
        return
    end
    local currentPage = resolve:GetCurrentPage()
    if currentPage ~= "cut" and currentPage ~= "edit" and currentPage ~= "color" and currentPage ~= "fairlight" and currentPage ~= "deliver" then
        resolve:OpenPage("edit")
    end
    local timecode = Subtitle.framesToTimecode(entry.startFrame, state.fps or 24.0)
    local ok = state.timeline:SetCurrentTimecode(timecode)
    if not ok then
        UI.updateStatus("jump_failed")
    else
        --UI.updateStatus("jump_success", timecode)
    end
end

-- 新增：清空 Tree 现有选择
function UI.clearTreeSelection()
    if not controls.tree then return end
    local selected = controls.tree:SelectedItems()
    if selected and type(selected) == "table" then
        for _, it in ipairs(selected) do
            it.Selected = false
        end
    end
end

-- 修改：仅选中当前命中的条目
function UI.jumpToEntry(index, doTimeline)
    local entry = state.entries[index]
    if not entry then return end
    local item = controls.tree:TopLevelItem(index - 1)
    if not item then return end

    state.suppressTreeSelection = true

    -- 关键：先清空旧选择，再选中当前
    UI.clearTreeSelection()
    item.Selected = true
    controls.tree:ScrollToItem(item)

    state.suppressTreeSelection = false

    state.selectedIndex = index
    UI.setEditorText(entry.text or "")

    if doTimeline ~= false then
        Subtitle.performTimelineJump(entry)
    end
end

function UI.countOccurrences(s, q)
    if not s or not q or q == "" then return 0 end
    local i, c = 1, 0
    while true do
        local a, b = string.find(s, q, i, true) -- 明确使用纯文本匹配
        if not a then break end
        c, i = c + 1, b + 1
    end
    return c
end

function UI.refreshFindMatches()
    local query = it.FindInput.Text or ""
    state.findQuery = query

    UI.clearAllFindHighlights()
    state.findMatches, state.findIndex = nil, nil
    state.currentMatchPos = nil

    if query == "" then
        UI.updateStatus("enter_find_text")
        return false
    end

    local matches = {}
    local rowsMatched, occTotal = 0, 0
    for index, entry in ipairs(state.entries) do
        local text = entry.text or ""
        local c = UI.countOccurrences(text, query)
        if c > 0 then
            rowsMatched = rowsMatched + 1
            occTotal = occTotal + c
            matches[#matches + 1] = index
        elseif not state.stickyHighlights[index] and state.highlightedRows[index] then
            UI.setRowHighlight(index, nil)
        end
    end

    if rowsMatched == 0 then
        UI.updateStatus("no_find_results")
        state.findMatches = {}
        state.findRows, state.findOcc = 0, 0
        state.currentMatchPos = nil
        return false
    end

    if controls.tree then
        UI.withUpdatesSuspended(controls.tree, function()
            for _, index in ipairs(matches) do
                UI.setRowHighlight(index, findHighlightColor)
            end
        end)
    else
        for _, index in ipairs(matches) do
            UI.setRowHighlight(index, findHighlightColor)
        end
    end

    state.findMatches = matches
    state.findRows, state.findOcc = rowsMatched, occTotal
    state.currentMatchPos = nil
    UI.updateStatus("matches_rows_occ", rowsMatched, occTotal)
    return true
end


function UI.ensureFindMatches()
    local query = it.FindInput.Text or ""
    if query == "" then
        UI.updateStatus("enter_find_text")
        return false
    end
    if query ~= state.findQuery or not state.findMatches then
        return UI.refreshFindMatches()
    end
    if state.findMatches and #state.findMatches > 0 then
        return true
    end
    return UI.refreshFindMatches()
end

function UI.gotoNextMatch()
    if not UI.ensureFindMatches() then return nil end
    local matches = state.findMatches or {}
    local count = #matches
    if count == 0 then
        UI.updateStatus("no_find_results")
        return nil
    end
    local idx = (state.currentMatchPos or 0) + 1
    if idx > count then idx = 1 end
    state.currentMatchPos = idx
    local entryIndex = matches[idx]

    UI.clearFindHighlights(true)
    UI.jumpToEntry(entryIndex, true)

    UI.setRowHighlight(entryIndex, findHighlightColor)
    state.currentMatchHighlight = entryIndex
    UI.updateStatus("match_progress", idx, count)
    return entryIndex
end

function UI.gotoPreviousMatch()
    if not UI.ensureFindMatches() then return nil end
    local matches = state.findMatches or {}
    local count = #matches
    if count == 0 then
        UI.updateStatus("no_find_results")
        return nil
    end
    local idx = (state.currentMatchPos or 1) - 1
    if idx < 1 then idx = count end
    state.currentMatchPos = idx
    local entryIndex = matches[idx]

    UI.clearFindHighlights(true)
    UI.jumpToEntry(entryIndex, true)

    UI.setRowHighlight(entryIndex, findHighlightColor)
    state.currentMatchHighlight = entryIndex
    UI.updateStatus("match_progress", idx, count)
    return entryIndex
end

function UI.updateTabBarTexts()
    if not controls.mainTabs then
        return
    end
    local lang = UI.currentLanguage()
    local pack = uiText[lang]
    local titles = (pack and pack.tabs) or uiText.cn.tabs
    if type(titles) ~= "table" then
        return
    end
    for index, title in ipairs(titles) do
        controls.mainTabs:SetTabText(index - 1, title)
    end
end

function UI.applyLanguage(lang)
    if lang ~= "en" then
        lang = "cn"
    end
    state.language = lang

    languageProgrammatic = true
    if controls.langCn then
        controls.langCn.Checked = (lang == "cn")
        controls.langCn.Text = UI.uiString("lang_cn")
    end
    if controls.langEn then
        controls.langEn.Checked = (lang == "en")
        controls.langEn.Text = UI.uiString("lang_en")
    end
    languageProgrammatic = false

    UI.updateTabBarTexts()

    if it.FindNextButton then
        it.FindNextButton.Text = UI.uiString("find_next_button")
    end
    if it.FindPreviousButton then
        it.FindPreviousButton.Text = UI.uiString("find_previous_button")
    end
    if it.AllReplaceButton then
        it.AllReplaceButton.Text = UI.uiString("all_replace_button")
    end
    if it.SingleReplaceButton then
        it.SingleReplaceButton.Text = UI.uiString("single_replace_button")
    end
    if it.RefreshButton then
        it.RefreshButton.Text = UI.uiString("refresh_button")
    end
    if it.UpdateSubtitleButton then
        it.UpdateSubtitleButton.Text = UI.uiString("update_button")
    end
    if it.FindInput then
        it.FindInput.PlaceholderText = UI.uiString("find_placeholder")
    end
    if it.ReplaceInput then
        it.ReplaceInput.PlaceholderText = UI.uiString("replace_placeholder")
    end
    if controls.editor then
        controls.editor.PlaceholderText = UI.uiString("editor_placeholder")
    end
    if it.CopyrightButton then
        it.CopyrightButton.Text = UI.uiString("copyright")
    end
    if controls.donationButton then
        controls.donationButton.Text = UI.uiString("donation")
    end
    if controls.translateConcurrencyLabel then
        controls.translateConcurrencyLabel.Text = UI.uiString("concurrency_label")
    end
    populateConcurrencyCombo(state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY)
    if controls.openAIConfigLabel then
        controls.openAIConfigLabel.Text = UI.uiString("openai_config_label")
    end
    if controls.openAIConfigButton then
        controls.openAIConfigButton.Text = UI.uiString("openai_config_button")
    end

    if controls.translateProviderLabel then
        controls.translateProviderLabel.Text = UI.uiString("translate_provider_label")
    end
    if controls.translateTargetLabel then
        controls.translateTargetLabel.Text = UI.uiString("translate_target_label")
    end
    if controls.translateProviderCombo then
        controls.translateProviderCombo.PlaceholderText = UI.uiString("translate_provider_placeholder")
    end
    if controls.translateTargetCombo then
        controls.translateTargetCombo.PlaceholderText = UI.uiString("translate_target_placeholder")
    end
    if controls.translateTransButton then
        controls.translateTransButton.Text = UI.uiString("translate_trans_button")
    end
    if controls.translateSelectedButton then
        controls.translateSelectedButton.Text = UI.uiString("translate_selected_button")
        controls.translateSelectedButton.Enabled = state.translate.selectedIndex ~= nil and not state.translate.busy
    end
    if controls.translateUpdateButton then
        controls.translateUpdateButton.Text = UI.uiString("translate_update_button")
    end
    if controls.translateEditor then
        controls.translateEditor.PlaceholderText = UI.uiString("translate_editor_placeholder")
    end
    translate.normalizeTree()
    translate.refreshStatus()

    UI.refreshUpdateNotice()

    Azure.refreshConfigTexts()
    OpenAIService.refreshConfigTexts()

    if controls.tree then
        controls.tree:SetHeaderLabels(UI.currentHeaders())
        controls.tree.ColumnWidth[0] = 50
        controls.tree.ColumnWidth[1] = 110
        controls.tree.ColumnWidth[2] = 360
    end

    local args = state.lastStatusArgs or {}
    UI.updateStatus(state.lastStatusKey, unpack(args))
end

function UI.setLanguage(lang)
    UI.applyLanguage(lang)
end

function UI.clearHighlights()
    if controls.tree then
        local toClear = {}
        for index in pairs(state.highlightedRows or {}) do
            table.insert(toClear, index)
        end
        UI.withUpdatesSuspended(controls.tree, function()
            for _, index in ipairs(toClear) do
                UI.setRowHighlight(index, nil)
            end
        end)
    else
        for index in pairs(state.highlightedRows or {}) do
            UI.setRowHighlight(index, nil)
        end
    end
    state.currentMatchHighlight = nil
    state.stickyHighlights = {}   -- ✅ 新增：完全清屏时重置粘性集合
    state.highlightedRows = {}
    state.currentMatchPos = nil
end

function UI.populateTree(suppressStatus)
    state.selectedIndex = nil
    state.findMatches = nil
    state.findIndex = nil
    state.currentMatchPos = nil
    state.currentMatchHighlight = nil
    state.stickyHighlights = {}
    state.highlightedRows = {}
    UI.setEditorText("")

    if controls.tree then
        UI.withUpdatesSuspended(controls.tree, function()
            controls.tree:Clear()
            controls.tree:SetHeaderLabels(UI.currentHeaders())
            controls.tree.ColumnWidth[0] = 50
            controls.tree.ColumnWidth[1] = 110
            controls.tree.ColumnWidth[2] = 360
            for index, entry in ipairs(state.entries) do
                local item = controls.tree:NewItem()
                item.Text[0] = tostring(index)
                local startDisplay = entry.startText or Subtitle.framesToTimecode(entry.startFrame, state.fps) or ""
                local endDisplay = entry.endText or Subtitle.framesToTimecode(entry.endFrame, state.fps) or ""
                item.Text[1] = string.format("▸ %s\n◂ %s", startDisplay, endDisplay)
                item.Text[2] = entry.text or ""
                controls.tree:AddTopLevelItem(item)
            end
        end)
    end

    if not suppressStatus then
        UI.updateStatus("current_total", #state.entries)
    end
end

-- ==============================================================
-- Editor Tab: (moved) Replace/Export helpers
function Subtitle.applyReplace()
    --UI.clearHighlights()
    UI.clearFindHighlights()
    local findText = it.FindInput.Text or ""
    local replaceText = it.ReplaceInput.Text or ""
    if findText == "" then
        UI.updateStatus("replace_no_find")
        return
    end
    local pattern = Utils.escapePlainPattern(findText)
    local replaced = 0
    for index, entry in ipairs(state.entries) do
        local newText, changes = (entry.text or ""):gsub(pattern, replaceText)
        if changes > 0 then
            entry.text = newText
            replaced = replaced + changes
            local item = controls.tree:TopLevelItem(index - 1)
            if item then
                item.Text[2] = newText
            end
            if state.translate and state.translate.entries and state.translate.entries[index] then
                local tEntry = state.translate.entries[index]
                tEntry.original = newText
                translate.updateOriginalRow(index, newText)
            end
            UI.setRowHighlight(index, findHighlightColor)
            if state.selectedIndex == index then
                UI.setEditorText(newText)
            end
        end
    end
    if replaced == 0 then
        UI.updateStatus("no_replace")
    else
        UI.updateStatus("replace_done", replaced)
    end
    state.findMatches = nil
    state.findIndex = nil
    state.currentMatchPos = nil
end
function Subtitle.replaceSingle()
    local findText = it.FindInput.Text or ""
    if findText == "" then
        UI.updateStatus("replace_no_find")
        return
    end
    if not UI.ensureFindMatches() then return end

    -- 若当前选中不含匹配，则先跳到下一命中
    local function currentContains()
        local idx = state.selectedIndex
        if not idx then return false end
        local entry = state.entries[idx]
        return entry and entry.text and entry.text:find(findText, 1, true) ~= nil
    end
    local attempts = 0
    while not currentContains() and attempts < (state.findMatches and #state.findMatches or 0) do
        local jumped = UI.gotoNextMatch()
        attempts = attempts + 1
        if not jumped then break end
    end
    if not currentContains() then
        UI.updateStatus("no_replace")
        return
    end

    -- ✅ 执行单条替换
    local replaceText = it.ReplaceInput.Text or ""
    local pattern = Utils.escapePlainPattern(findText)
    local index = state.selectedIndex
    local entry = state.entries[index]
    local newText, count = (entry.text or ""):gsub(pattern, replaceText)
    if count == 0 then
        UI.updateStatus("no_replace")
        return
    end

    entry.text = newText
    local item = controls.tree and controls.tree:TopLevelItem(index - 1)
    if item then
        item.Text[2] = newText
    end
    if state.translate and state.translate.entries and state.translate.entries[index] then
        local tEntry = state.translate.entries[index]
        tEntry.original = newText
        translate.updateOriginalRow(index, newText)
    end
    UI.setRowHighlight(index, findHighlightColor)
    UI.setEditorText(newText)

    -- ✅ 标记该行“粘性高亮”，后续 UI.refreshFindMatches() 的全表清理将跳过它
    state.stickyHighlights[index] = true

    -- 刷新匹配并跳到下一条（保持用户原工作流）
    state.currentMatchHighlight = nil
    UI.refreshFindMatches()
    local updatedMatches = state.findMatches or {}
    if #updatedMatches == 0 then
        UI.updateStatus("match_progress", 0, 0)
        return
    end
    local nextIdx = 1
    for i, matchIndex in ipairs(updatedMatches) do
        if matchIndex > index then
            nextIdx = i
            break
        end
        if i == #updatedMatches then nextIdx = 1 end
    end
    state.currentMatchPos = nextIdx - 1
end
function Subtitle.exportAndImport()
    if not state.entries or #state.entries == 0 then
        UI.updateStatus("no_entries_update")
        return
    end
    local tempDir = Utils.getTempDir()
    Utils.ensureDir(tempDir)
    local tempPath = Subtitle.nextSrtPathForTimeline(state.timeline)
    local ok, err = Subtitle.writeSrt(state.entries, tempPath, state.startFrame or 0, state.fps or 24.0)
    if not ok then
        UI.updateStatus(err or "write_failed")
        return
    end
    local success, importErr = Subtitle.importSrtToTimeline(tempPath)
    if not success then
        UI.updateStatus(importErr or "import_failed")
        return
    end
    Subtitle.refreshFromTimeline()
    UI.updateStatus("updated_success")
end

function win.On.LangCnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    UI.setLanguage("cn")
end

function win.On.LangEnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    UI.setLanguage("en")
end

function win.On.MainTabs.CurrentChanged(ev)
    if not controls.mainStack then
        return
    end
    local index = (ev and ev.Index) or 0
    controls.mainStack.CurrentIndex = index
    if index == 1 then
        translate.initTab()
        translate.ensureEntries(false)
    end
end

-- ==============================================================
-- Events: Editor Tab
-- ==============================================================
function win.On.FindInput.TextChanged(ev)
    UI.clearAllFindHighlights()      -- ← 改成清全表
    state.findMatches = nil
    state.findIndex = nil
    state.currentMatchPos = nil
    state.stickyHighlights = {} 
    state.findQuery = it.FindInput.Text or ""
end

function win.On.FindInput.EditingFinished(ev)
    if UI.refreshFindMatches() then
        UI.updateStatus("matches_rows_occ", state.findRows or 0, state.findOcc or 0)
    end
end


function win.On.FindNextButton.Clicked(ev)
    UI.gotoNextMatch()
end

function win.On.FindPreviousButton.Clicked(ev)
    UI.gotoPreviousMatch()
end

function win.On.AllReplaceButton.Clicked(ev)
    Subtitle.applyReplace()
end

function win.On.SingleReplaceButton.Clicked(ev)
    Subtitle.replaceSingle()
end

function win.On.RefreshButton.Clicked(ev)
    UI.clearHighlights()
    state.findMatches = nil
    state.findIndex = nil
    state.currentMatchPos = nil
    Subtitle.refreshFromTimeline()
end

function win.On.UpdateSubtitleButton.Clicked(ev)
    Subtitle.exportAndImport()
end

function win.On.DonationButton.Clicked(ev)
    if UI.currentLanguage() == "cn" then
        UI.showDonationWindow()
    else
        Utils.openExternalUrl(SCRIPT_KOFI_URL)
    end
end

function win.On.SubtitleEditor.TextChanged(ev)
    if editorProgrammatic then
        return
    end
    local index = state.selectedIndex
    if not index then
        return
    end
    local entry = state.entries[index]
    if not entry then
        return
    end
    local newText = controls.editor.PlainText or controls.editor.Text or ""
    entry.text = newText
    local item = controls.tree and controls.tree:TopLevelItem(index - 1)
    if item then
        item.Text[2] = newText
    end
    if state.translate and state.translate.entries and state.translate.entries[index] then
        local tEntry = state.translate.entries[index]
        tEntry.original = newText
        translate.updateOriginalRow(index, newText)
    end
end

function win.On.SubtitleTree.ItemClicked(ev)
    if state.suppressTreeSelection then
        return
    end
    local item = controls.tree and controls.tree:CurrentItem()
    if not item then
        return
    end
    local index = tonumber(item.Text[0] or "")
    if not index then
        return
    end
    UI.jumpToEntry(index, true)
end


-- ==============================================================
-- Events: Config Tab
-- ==============================================================
function win.On.CopyrightButton.Clicked(ev)
    local preferEnglish = false
    if controls.langEn and controls.langEn.Checked then
        preferEnglish = true
    elseif state.language == "en" then
        preferEnglish = true
    end
    local targetUrl = preferEnglish and SCRIPT_KOFI_URL or SCRIPT_BILIBILI_URL
    Utils.openExternalUrl(targetUrl)
end

function win.On.AzureConfigButton.Clicked(ev)
    Azure.openConfigWindow()
end

function win.On.OpenAIFormatConfigButton.Clicked(ev)
    OpenAIService.openConfigWindow()
end

Azure.refreshConfigTexts()
Azure.syncConfigControls()
OpenAIService.refreshConfigTexts()
OpenAIService.syncOpenAIConfigControls()

if azureConfigWin then
    function azureConfigWin.On.AzureConfirm.Clicked(ev)
        Azure.closeConfigWindow()
    end
    function azureConfigWin.On.AzureConfigWin.Close(ev)
        Azure.closeConfigWindow()
    end
    function azureConfigWin.On.AzureRegisterButton.Clicked(ev)
        Utils.openExternalUrl(AZURE_REGISTER_URL)
    end
end

if openAIConfigWin then
    function openAIConfigWin.On.OpenAIFormatConfigWin.Close(ev)
        OpenAIService.closeConfigWindow()
    end

    function openAIConfigWin.On.OpenAIFormatModelCombo.CurrentIndexChanged(ev)
        local combo = openAIConfigItems.OpenAIFormatModelCombo
        local index = ev and ev.Index
        if (not index) and combo then
            index = combo.CurrentIndex
        end
        if type(index) == "number" and index >= 0 then
            state.openaiFormat.selectedIndex = index + 1
            Storage.ensureOpenAIModelList(state.openaiFormat)
            if openAIConfigItems.OpenAIFormatModelName then
                local models = state.openaiFormat.models or {}
                openAIConfigItems.OpenAIFormatModelName.Text = (models[state.openaiFormat.selectedIndex] and models[state.openaiFormat.selectedIndex].name) or ""
            end
        end
    end

    function openAIConfigWin.On.VerifyModel.Clicked(ev)
        translate.handleVerify()
    end

    function openAIConfigWin.On.ShowAddModel.Clicked(ev)
        OpenAIService.applyConfigFromControls()
        if addModelItems.addOpenAIFormatModelDisplay then
            addModelItems.addOpenAIFormatModelDisplay.Text = ""
        end
        if addModelItems.addOpenAIFormatModelName then
            addModelItems.addOpenAIFormatModelName.Text = ""
        end
        if addModelWin then
            addModelWin:Show()
        end
        openAIConfigWin:Hide()
    end

    function openAIConfigWin.On.DeleteModel.Clicked(ev)
        translate.handleDeleteModel()
    end
end

if addModelWin then
    function addModelWin.On.AddModelBtn.Clicked(ev)
        translate.handleAddModel()
    end

    function addModelWin.On.AddModelWin.Close(ev)
        if openAIConfigWin then
            OpenAIService.syncOpenAIConfigControls()
            addModelWin:Hide()
            openAIConfigWin:Show()
        end
    end
end


-- ==============================================================
-- Events: Translate Tab
-- ==============================================================
function win.On.TranslateSubtitleTree.ItemClicked(ev)
    if not controls.translateTree then
        return
    end
    local item = controls.translateTree:CurrentItem()
    if not item then
        return
    end
    local index = tonumber(item.Text[0] or "")
    if not index then
        return
    end
    translate.selectRow(index)
end

function win.On.TranslateSubtitleEditor.TextChanged(ev)
    if translateEditorProgrammatic then
        return
    end
    local idx = state.translate.selectedIndex
    if not idx then
        return
    end
    local entry = state.translate.entries and state.translate.entries[idx]
    if not entry then
        return
    end
    local text = (controls.translateEditor and (controls.translateEditor.PlainText or controls.translateEditor.Text)) or ""
    entry.translation = text
    translate.updateTreeRow(idx, text)
end

function win.On.TranslateProviderCombo.CurrentIndexChanged(ev)
    if controls.translateProviderCombo then
        state.translate.provider = controls.translateProviderCombo.CurrentText or state.translate.provider
    end
end

function win.On.TranslateConcurrencyCombo.CurrentIndexChanged(ev)
    if not controls.translateConcurrencyCombo then
        return
    end
    local index = controls.translateConcurrencyCombo.CurrentIndex
    if not index or index < 0 then
        state.translate.concurrency = DEFAULT_TRANSLATE_CONCURRENCY
        setConcurrencyComboSelection(state.translate.concurrency)
        return
    end
    local option = TRANSLATE_CONCURRENCY_OPTIONS[index + 1]
    local value = option and option.value or DEFAULT_TRANSLATE_CONCURRENCY
    state.translate.concurrency = value
    if not option then
        setConcurrencyComboSelection(state.translate.concurrency)
    end
end

function win.On.TranslateTargetCombo.CurrentIndexChanged(ev)
    if controls.translateTargetCombo then
        state.translate.targetLabel = controls.translateTargetCombo.CurrentText or state.translate.targetLabel
    end
end
function win.On.TranslateTransButton.Clicked(ev)
    translate.performWorkflow()
end

function win.On.TranslateSelectedButton.Clicked(ev)
    if state.translate.busy then
        return
    end
    translate.ensureEntries(false)
    local idx = state.translate.selectedIndex
    if not idx then
        translate.setStatus("failed", translate.resolveError("no_selection"))
        return
    end

    local provider = controls.translateProviderCombo and controls.translateProviderCombo.CurrentText or state.translate.provider
    if not provider or Utils.trim(provider) == "" then
        provider = TRANSLATE_PROVIDER_AZURE_LABEL
    end
    if not Translate.isSupportedProvider(provider) then
        translate.setStatus("failed", translate.resolveError("provider_not_supported"))
        return
    end
    state.translate.provider = provider

    local targetLabel = controls.translateTargetCombo and controls.translateTargetCombo.CurrentText or state.translate.targetLabel or "English"
    state.translate.targetLabel = targetLabel

    state.translate.busy = true
    translate.setControlsEnabled(false)

    local ok, err = pcall(translate.translateSingleEntry, idx, targetLabel)

    state.translate.busy = false
    translate.setControlsEnabled(true)

    if not ok then
        translate.setStatus("failed", translate.resolveError(err or "translation_failed"))
    end
end

function win.On.TranslateUpdateSubtitleButton.Clicked(ev)
    if state.translate.busy then
        return
    end
    if Subtitle.exportTranslatedSubtitles and Subtitle.exportTranslatedSubtitles() then
        if Subtitle.refreshFromTimeline() then
            translate.setStatus("updated")
        end
    end
end

function win.On.SubtitleUtilityWin.Close(ev)
    OpenAIService.applyConfigFromControls()
    Azure.applyConfigFromControls()
    Storage.ensureOpenAIModelList(state.openaiFormat)
    local selectedModel = Storage.getOpenAISelectedModel(state.openaiFormat)
    local settingsPayload = {
        TranslateProviderCombo = state.translate and state.translate.provider or "",
        TranslateTargetCombo = state.translate and state.translate.targetLabel or "",
        TranslateConcurrencyCombo = state.translate and state.translate.concurrency or DEFAULT_TRANSLATE_CONCURRENCY,
        AzureRegion = state.azure and state.azure.region or "",
        AzureApiKey = state.azure and state.azure.apiKey or "",
        OpenAIFormatModelCombo = selectedModel and (selectedModel.display or selectedModel.name) or "",
        OpenAIFormatBaseURL = state.openaiFormat and state.openaiFormat.baseUrl or OPENAI_FORMAT_DEFAULT_BASE_URL,
        OpenAIFormatApiKey = state.openaiFormat and state.openaiFormat.apiKey or "",
        OpenAIFormatTemperatureSpinBox = state.openaiFormat and state.openaiFormat.temperature or OPENAI_FORMAT_DEFAULT_TEMPERATURE,
        SystemPromptTxt = state.openaiFormat and state.openaiFormat.systemPrompt or OPENAI_DEFAULT_SYSTEM_PROMPT,
        LangCnCheckBox = controls.langCn and controls.langCn.Checked or false,
        LangEnCheckBox = controls.langEn and controls.langEn.Checked or false,
    }
    Storage.saveSettings(settingsFile, settingsPayload, Storage.settingsKeyOrder)
    Storage.saveOpenAIModelStore()
    Subtitle.cleanupTempDir()
    disp:ExitLoop()
end

UI.applyLanguage(state.language)
function App.performInitialLoad()
    Subtitle.refreshFromTimeline()
    App.checkForUpdates()
end
UI.runWithLoading(App.performInitialLoad)
win:Show()
disp:RunLoop()
win:Hide()
