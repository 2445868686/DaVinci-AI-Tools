-- SubtitleFindReplace.lua
-- 获取当前时间线字幕，在界面中支持查找和替换，然后回写到时间线

local SCRIPT_NAME    = "DaVinci Sub Editor"
local SCRIPT_VERSION = "1.0.0"
local SCRIPT_AUTHOR  = "HEIBA"
local SCRIPT_KOFI_URL = "https://ko-fi.com/heiba"
local SCRIPT_BILIBILI_URL = "https://space.bilibili.com/385619394"
local SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
local WINDOW_WIDTH, WINDOW_HEIGHT = 600, 500
local X_CENTER = math.floor((SCREEN_WIDTH  - WINDOW_WIDTH ) / 2)
local Y_CENTER = math.floor((SCREEN_HEIGHT - WINDOW_HEIGHT) / 2)

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

local ui  = fusion.UIManager
local disp = bmd.UIDispatcher(ui)

local state = {
    entries = {},
    fps = 24.0,
    startFrame = 0,
    timeline = nil,
    resolve = resolve,
    selectedIndex = nil,
    activeTrackIndex = nil,
    language = "cn",
    lastStatusKey = nil,
    lastStatusArgs = nil,
    findQuery = "",
    findMatches = nil,
    findIndex = nil,
    suppressTreeSelection = false,
    currentMatchHighlight = nil,
}
math.randomseed(os.time() + tonumber(tostring({}):sub(8), 16))
state.sessionCode = string.format("%04X", math.random(0, 0xFFFF))

local findHighlightColor    = { R = 0.40, G = 0.40, B = 0.40, A = 0.60 } -- 查找命中 / 替换后标记
local transparentColor      = { R = 0.0,  G = 0.0,  B = 0.0,  A = 0.0  } -- 透明，真正清空
local editorProgrammatic = false
local languageProgrammatic = false
local unpack = table.unpack or unpack
local configDir
local settingsFile

local uiText = {
    cn = {
        tree_title = "高级字幕编辑器",
        find_button = "查找",
        all_replace_button = "全部替换",
        single_replace_button = "替换",
        refresh_button = "刷新字幕",
        update_button = "更新字幕",
        find_placeholder = "查找文本",
        replace_placeholder = "替换文本",
        editor_placeholder = "在此编辑选中的字幕",
        tree_headers = { "#", "开始", "结束", "字幕" },
        lang_cn = "简体中文",
        lang_en = "EN",
        tabs = { "字幕编辑", "配置" },
        copyright = "© 2025, 版权所有 " .. SCRIPT_AUTHOR,
    },
    en = {
        tree_title = "Advanced Subtitle Editor",
        find_button = "Find",
        all_replace_button = "All Replace",
        single_replace_button = "Replace",
        refresh_button = "Refresh",
        update_button = "Update Timeline",
        find_placeholder = "Find text",
        replace_placeholder = "Replace with",
        editor_placeholder = "Edit selected subtitle here",
        tree_headers = { "#", "Start", "End", "Subtitle" },
        lang_cn = "简体中文",
        lang_en = "EN",
        tabs = { "Subtitle Editing", "Settings" },
        copyright = "© 2025, Copyright by " .. SCRIPT_AUTHOR,
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

local function scriptDir()
    local info = debug.getinfo(1, "S").source
    local path = info:match("^@(.+/)")
    if path then
        return path
    end
    return ""
end

local function joinPath(a, b)
    if a == "" then
        return b
    end
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

local function getTempDir()
    return joinPath(scriptDir(), "temp")
end
-- 将时间线名称转为文件名安全格式
local function sanitizeFilename(name)
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
local function listFiles(dir)
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


local function escapePattern(s)
    return (s:gsub("(%W)","%%%1"))
end

local function ensureDir(path)
    if path == "" then
        return true
    end
    if bmd and bmd.fileexists and bmd.fileexists(path) then
        return true
    end
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        os.execute(string.format('if not exist "%s" mkdir "%s"', path, path))
    else
        os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "'")
    end
    return true
end

configDir = joinPath(scriptDir(), "config")
ensureDir(configDir)
settingsFile = joinPath(configDir, "subedit_settings.json")
local storedSettings

local function nextSrtPathForTimeline(timeline)
    local tempDir = getTempDir()
    ensureDir(tempDir)

    local tlName = "timeline"
    if timeline and timeline.GetName then
        tlName = timeline:GetName() or tlName
    end
    local safeName = sanitizeFilename(tlName)
    local rand     = state.sessionCode or "0000"

    local prefix   = string.format("%s_subtitle_update_%s_", safeName, rand)
    local files    = listFiles(tempDir)

    -- 在 tempDir 中寻找相同前缀且后缀为数字的 .srt，取最大值
    local maxN = 0
    local pat  = "^" .. escapePattern(prefix) .. "(%d+)%.srt$"
    for _, f in ipairs(files) do
        local n = f:match(pat)
        if n then
            n = tonumber(n) or 0
            if n > maxN then maxN = n end
        end
    end

    local nextIdx  = maxN + 1
    local filename = string.format("%s%03d.srt", prefix, nextIdx)
    return joinPath(tempDir, filename)
end

local function removeDir(path)
    if not path or path == "" then
        return
    end
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        os.execute(string.format('rmdir /S /Q "%s"', path))
    else
        os.execute("rm -rf '" .. path:gsub("'", "'\\''") .. "'")
    end
end

local function currentLanguage()
    if state.language == "en" then
        return "en"
    end
    return "cn"
end

local function uiString(key)
    local lang = currentLanguage()
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

local function messageString(key)
    local bucket = messages[key]
    if not bucket then
        return nil
    end
    local lang = currentLanguage()
    return bucket[lang] or bucket.cn
end

local function openExternalUrl(url)
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
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        os.execute(string.format('start "" "%s"', url))
        return
    end
    local escaped = url:gsub("'", "'\\''")
    local ok = os.execute("open '" .. escaped .. "'")
    if not ok then
        os.execute("xdg-open '" .. escaped .. "'")
    end
end

local function currentHeaders()
    local lang = currentLanguage()
    local pack = uiText[lang]
    return (pack and pack.tree_headers) or uiText.cn.tree_headers
end

local function loadSettings(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return nil
    end
    local langCnValue = content:match('"lang_cn"%s*:%s*(true|false)')
    local langEnValue = content:match('"lang_en"%s*:%s*(true|false)')
    if not langCnValue and not langEnValue then
        return nil
    end
    return {
        lang_cn = langCnValue == "true",
        lang_en = langEnValue == "true",
    }
end

local function saveSettings(path, values)
    if not values then
        return
    end
    ensureDir(configDir)
    local file, err = io.open(path, "w")
    if not file then
        print(string.format("无法写入设置文件 %s: %s", tostring(path), tostring(err)))
        return
    end
    local content = string.format('{"lang_cn": %s, "lang_en": %s}',
        values.lang_cn and "true" or "false",
        values.lang_en and "true" or "false"
    )
    file:write(content)
    file:close()
end

storedSettings = loadSettings(settingsFile)
if storedSettings then
    if storedSettings.lang_en then
        state.language = "en"
    elseif storedSettings.lang_cn then
        state.language = "cn"
    end
end

local function parseFps(raw)
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

local function framesToTimecode(frames, fps)
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

local function framesToSrtTimestamp(frames, fps)
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

local function getTimelineContext()
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

local function sortEntries(entries)
    table.sort(entries, function(a, b)
        if a.startFrame == b.startFrame then
            return a.endFrame < b.endFrame
        end
        return a.startFrame < b.startFrame
    end)
end

local function collectSubtitles()
    local ctx = getTimelineContext()
    if not ctx then
        return false, "no_timeline"
    end
    local timeline = ctx.timeline
    state.timeline = timeline
    local fpsSetting = timeline:GetSetting("timelineFrameRate")
    if not fpsSetting then
        fpsSetting = ctx.project:GetSetting("timelineFrameRate")
    end
    state.fps = parseFps(fpsSetting)
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
                    table.insert(entries, {
                        startFrame = math.floor(startValue + 0.5),
                        endFrame = math.floor(endValue + 0.5),
                        text = name,
                    })
                end
                break
            end
        end
    end

    sortEntries(entries)
    state.entries = entries
    return true
end



local function cleanupTempDir()
    local tempDir = getTempDir()
    if tempDir == "" then
        return
    end
    removeDir(tempDir)
end

local function writeSrt(entries, path, startFrame, fps)
    if not entries or #entries == 0 then
        return false, "no_entries_update"
    end
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if dir and dir ~= "" then
        ensureDir(dir)
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
        local sText = framesToSrtTimestamp(s, fps)
        local eText = framesToSrtTimestamp(e, fps)
        fh:write(string.format("%d\n", idx))
        fh:write(string.format("%s --> %s\n", sText, eText))
        fh:write((entry.text or "") .. "\n\n")
    end
    fh:close()
    return true
end

local function findClipByName(clips, name)
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

local function importSrtToTimeline(path)
    local ctx = getTimelineContext()
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
        mediaItem = findClipByName(clips, baseName)
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

local function escapePlainPattern(text)
    return text:gsub("([^%w])", "%%%1")
end

local win = disp:AddWindow({
    ID = "SubtitleUtilityWin",
    WindowTitle = string.format("%s %s", SCRIPT_NAME, SCRIPT_VERSION),
    Geometry = { X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT },
    StyleSheet = "*{font-size:14px;}"
}, ui:VGroup{
    ID = "root",
    Weight = 1,
    ui:TabBar{
        ID = "MainTabs",
        Weight = 0,
    },
    ui:Stack{
        ID = "MainStack",
        Weight = 1,
        ui:VGroup{
            ID = "EditTab",
            Weight = 1,
            ui:Label{
                ID = "TreeTitleLabel",
                Text = uiString("tree_title"),
                Weight = 0,
                StyleSheet =  " font-size:16px;",
                Alignment = { AlignHCenter = true, AlignVCenter = true },
            },
            ui:VGap(10),
            ui:HGroup{
                Weight = 0.1,
                ui:LineEdit{ ID = "FindInput", PlaceholderText = uiString("find_placeholder"), Weight = 1, Events = { TextChanged = true, EditingFinished = true } },
                ui:Button{ ID = "FindButton", Text = uiString("find_button"), Weight = 0 },
                ui:LineEdit{ ID = "ReplaceInput", PlaceholderText = uiString("replace_placeholder"), Weight = 1 },
                ui:Button{ ID = "AllReplaceButton", Text = uiString("all_replace_button"), Weight = 0 },
                ui:Button{ ID = "SingleReplaceButton", Text = uiString("single_replace_button"), Weight = 0 },
            },
            ui:Tree{
                ID = "SubtitleTree",
                AlternatingRowColors = true,
                WordWrap = true,
                UniformRowHeights = false,
                HorizontalScrollMode = true,
                FrameStyle = 1,
                ColumnCount = 4,
                SelectionMode = "SingleSelection",
                Weight = 0.7,
            },
            ui:TextEdit{
                ID = "SubtitleEditor",
                Weight = 0,
                PlaceholderText = uiString("editor_placeholder"),
                WordWrap = true,
            },
            ui:HGroup{
                Weight = 0.1,
                ui:Button{ ID = "RefreshButton", Text = uiString("refresh_button"), Weight = 1 },
                ui:Button{ ID = "UpdateSubtitleButton", Text = uiString("update_button"), Weight = 1 },
            },
            ui:HGroup{
                Weight = 0.1,
                ui:Label{ ID = "StatusLabel", Text = "", Weight = 1, Alignment = { AlignHCenter = true, AlignVCenter = true } },
            },
            
        },
        ui:VGroup{
            ID = "ConfigTab",
            Weight = 1,
            ui:VGap(20),
            ui:HGroup{
                Weight = 0,
                ui:CheckBox{ ID = "LangCnCheckBox", Text = uiString("lang_cn"), Checked = false, Weight = 0 },
                ui:CheckBox{ ID = "LangEnCheckBox", Text = uiString("lang_en"), Checked = true, Weight = 0 },
            },
            ui:Button{
                ID = "CopyrightButton",
                Text = uiString("copyright"),
                Alignment = { AlignHCenter = true, AlignVCenter = true },
                Font = ui.Font({ PixelSize = 12, StyleName = "Bold" }),
                Flat = true,
                TextColor = { 0.1, 0.3, 0.9, 1 },
                BackgroundColor = { 1, 1, 1, 0 },
                Weight = 0,
            },
        },
    },
})

local it = win:GetItems()
local tree = it.SubtitleTree
local editor = it.SubtitleEditor
local langCn = it.LangCnCheckBox
local langEn = it.LangEnCheckBox
local mainTabs = it.MainTabs
local mainStack = it.MainStack

if mainTabs then
    local initialTabs = uiText.cn.tabs or { "字幕编辑", "配置" }
    for _, title in ipairs(initialTabs) do
        mainTabs:AddTab(title)
    end
    if mainStack then
        mainTabs.CurrentIndex = 0
        mainStack.CurrentIndex = 0
    end
end

local function updateStatus(key, ...)
    state.lastStatusKey = key
    state.lastStatusArgs = { ... }

    if not key then
        it.StatusLabel.Text = ""
        return
    end

    local template = messageString(key)
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

local function setEditorText(text)
    editorProgrammatic = true
    editor.Text = text or ""
    editorProgrammatic = false
end

local function clearFindHighlights(preserveIfStillMatch)
    if not state.currentMatchHighlight then return end
    local row = state.currentMatchHighlight - 1
    local item = tree:TopLevelItem(row)
    state.currentMatchHighlight = nil
    if not item then return end

    -- 用透明色显式清空每一列的背景
    for col = 0, (tree.ColumnCount or 4) - 1 do
        item.BackgroundColor[col] = transparentColor
    end

    if preserveIfStillMatch and state.findQuery and state.findQuery ~= "" then
        local text = item.Text[3] or ""
        if text:find(state.findQuery, 1, true) then
            item.BackgroundColor[3] = findHighlightColor
        end
    end
end

-- ✅ 新增：每次开始新查询前，清掉“所有行”的查找高亮
--（替换后的条目也使用 findHighlightColor，这里通过颜色判断来识别并清理）
local function clearAllFindHighlights()
    local rows = tree:TopLevelItemCount()
    for r = 0, rows - 1 do
        local it = tree:TopLevelItem(r)
        if it then
            -- 仅清除与“查找/替换”高亮对应的颜色，其他自定义背景保持不变
            local bg = it.BackgroundColor[3]
            local isFindColor = bg
                and math.abs((bg.R or 0) - findHighlightColor.R) < 1e-6
                and math.abs((bg.G or 0) - findHighlightColor.G) < 1e-6
                and math.abs((bg.B or 0) - findHighlightColor.B) < 1e-6

            if isFindColor then
                it.BackgroundColor[3] = transparentColor
            end
        end
    end
    state.currentMatchHighlight = nil
end

local function performTimelineJump(entry)
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
    local timecode = framesToTimecode(entry.startFrame, state.fps or 24.0)
    local ok = state.timeline:SetCurrentTimecode(timecode)
    if not ok then
        updateStatus("jump_failed")
    else
        --updateStatus("jump_success", timecode)
    end
end

-- 新增：清空 Tree 现有选择
local function clearTreeSelection()
    if not tree then return end
    local selected = tree:SelectedItems()
    if selected and type(selected) == "table" then
        for _, it in ipairs(selected) do
            it.Selected = false
        end
    end
end

-- 修改：仅选中当前命中的条目
local function jumpToEntry(index, doTimeline)
    local entry = state.entries[index]
    if not entry then return end
    local item = tree:TopLevelItem(index - 1)
    if not item then return end

    state.suppressTreeSelection = true

    -- 关键：先清空旧选择，再选中当前
    clearTreeSelection()
    item.Selected = true
    tree:ScrollToItem(item)

    state.suppressTreeSelection = false

    state.selectedIndex = index
    setEditorText(entry.text or "")

    if doTimeline ~= false then
        performTimelineJump(entry)
    end
end

local function countOccurrences(s, q)
    if not s or not q or q == "" then return 0 end
    local i, c = 1, 0
    while true do
        local a, b = string.find(s, q, i, true) -- 明确使用纯文本匹配
        if not a then break end
        c, i = c + 1, b + 1
    end
    return c
end

local function refreshFindMatches()
    local query = it.FindInput.Text or ""
    state.findQuery = query

    clearAllFindHighlights()
    state.findMatches, state.findIndex = nil, nil

    if query == "" then
        updateStatus("enter_find_text")
        return false
    end

    local matches = {}
    local rowsMatched, occTotal = 0, 0
    local rows = tree:TopLevelItemCount()
    for row = 0, rows - 1 do
        local item = tree:TopLevelItem(row)
        if item then
            local text = item.Text[3] or ""
            local c = countOccurrences(text, query)
            if c > 0 then
                item.BackgroundColor[3] = findHighlightColor
                table.insert(matches, row + 1)  -- 仍按“行”来导航
                rowsMatched = rowsMatched + 1
                occTotal = occTotal + c
            end
        end
    end

    if rowsMatched == 0 then
        updateStatus("no_find_results")
        state.findMatches = {}
        state.findRows, state.findOcc = 0, 0
        return false
    end

    state.findMatches = matches
    state.findRows, state.findOcc = rowsMatched, occTotal
    state.findIndex = 1
    updateStatus("matches_rows_occ", rowsMatched, occTotal)
    return true
end


local function ensureFindMatches()
    local query = it.FindInput.Text or ""
    if query == "" then
        updateStatus("enter_find_text")
        return false
    end
    if query ~= state.findQuery or not state.findMatches then
        return refreshFindMatches()
    end
    if state.findMatches and #state.findMatches > 0 then
        return true
    end
    return refreshFindMatches()
end

local function gotoNextMatch()
    if not ensureFindMatches() then return nil end
    local matches = state.findMatches or {}
    if #matches == 0 then
        updateStatus("no_find_results")
        return nil
    end
    local idx = state.findIndex or 1
    if idx > #matches then idx = 1 end
    local entryIndex = matches[idx]
    state.findIndex = (idx % #matches) + 1

    clearFindHighlights(true)
    jumpToEntry(entryIndex, true)

    local item = tree:TopLevelItem(entryIndex - 1)
    if item then
        item.BackgroundColor[3] = findHighlightColor
        state.currentMatchHighlight = entryIndex
    end
    updateStatus("match_progress", idx, #matches)
    return entryIndex
end

local function updateTabBarTexts()
    if not mainTabs then
        return
    end
    local lang = currentLanguage()
    local pack = uiText[lang]
    local titles = (pack and pack.tabs) or uiText.cn.tabs
    if type(titles) ~= "table" then
        return
    end
    for index, title in ipairs(titles) do
        mainTabs:SetTabText(index - 1, title)
    end
end

local function applyLanguage(lang)
    if lang ~= "en" then
        lang = "cn"
    end
    state.language = lang

    languageProgrammatic = true
    if langCn then
        langCn.Checked = (lang == "cn")
        langCn.Text = uiString("lang_cn")
    end
    if langEn then
        langEn.Checked = (lang == "en")
        langEn.Text = uiString("lang_en")
    end
    languageProgrammatic = false

    updateTabBarTexts()

    if it.TreeTitleLabel then
        it.TreeTitleLabel.Text = uiString("tree_title")
    end
    if it.FindButton then
        it.FindButton.Text = uiString("find_button")
    end
    if it.AllReplaceButton then
        it.AllReplaceButton.Text = uiString("all_replace_button")
    end
    if it.SingleReplaceButton then
        it.SingleReplaceButton.Text = uiString("single_replace_button")
    end
    if it.RefreshButton then
        it.RefreshButton.Text = uiString("refresh_button")
    end
    if it.UpdateSubtitleButton then
        it.UpdateSubtitleButton.Text = uiString("update_button")
    end
    if it.FindInput then
        it.FindInput.PlaceholderText = uiString("find_placeholder")
    end
    if it.ReplaceInput then
        it.ReplaceInput.PlaceholderText = uiString("replace_placeholder")
    end
    if editor then
        editor.PlaceholderText = uiString("editor_placeholder")
    end
    if it.CopyrightButton then
        it.CopyrightButton.Text = uiString("copyright")
    end

    if tree then
        tree:SetHeaderLabels(currentHeaders())
        tree.ColumnWidth[0] = 50
        tree.ColumnWidth[1] = 50
        tree.ColumnWidth[2] = 50
    end

    local args = state.lastStatusArgs or {}
    updateStatus(state.lastStatusKey, unpack(args))
end

local function setLanguage(lang)
    applyLanguage(lang)
end

local function clearHighlights()
    local rows = tree:TopLevelItemCount()
    for row = 0, rows - 1 do
        local item = tree:TopLevelItem(row)
        if item then
            for col = 0, 3 do
                item.BackgroundColor[col] = nil
            end
        end
    end
    state.currentMatchHighlight = nil
end

local function populateTree(suppressStatus)
    tree:Clear()
    state.selectedIndex = nil
    state.findMatches = nil
    state.findIndex = nil
    state.currentMatchHighlight = nil
    setEditorText("")
    tree:SetHeaderLabels(currentHeaders())
    tree.ColumnWidth[0] = 50
    tree.ColumnWidth[1] = 50
    tree.ColumnWidth[2] = 50
    for index, entry in ipairs(state.entries) do
        local item = tree:NewItem()
        item.Text[0] = tostring(index)
        item.Text[1] = framesToTimecode(entry.startFrame, state.fps)
        item.Text[2] = framesToTimecode(entry.endFrame, state.fps)
        item.Text[3] = entry.text or ""
        tree:AddTopLevelItem(item)
    end
    if not suppressStatus then
        updateStatus("current_total", #state.entries)
    end
end

local function refreshFromTimeline()
    local ok, err = collectSubtitles()
    if not ok then
        updateStatus(err or "cannot_read_subtitles")
        state.entries = {}
        populateTree(true)
        return false
    end
    populateTree()
    updateStatus("loaded_count", #state.entries)
    return true
end

local function applyReplace()
    --clearHighlights()
    clearFindHighlights()
    local findText = it.FindInput.Text or ""
    local replaceText = it.ReplaceInput.Text or ""
    if findText == "" then
        updateStatus("replace_no_find")
        return
    end
    local pattern = escapePlainPattern(findText)
    local replaced = 0
    for index, entry in ipairs(state.entries) do
        local newText, changes = (entry.text or ""):gsub(pattern, replaceText)
        if changes > 0 then
            entry.text = newText
            replaced = replaced + changes
            local item = tree:TopLevelItem(index - 1)
            if item then
                item.Text[3] = newText
                item.BackgroundColor[3] = findHighlightColor
            end
            if state.selectedIndex == index then
                setEditorText(newText)
            end
        end
    end
    if replaced == 0 then
        updateStatus("no_replace")
    else
        updateStatus("replace_done", replaced)
    end
    state.findMatches = nil
    state.findIndex = nil
end

local function replaceSingle()
    local findText = it.FindInput.Text or ""
    if findText == "" then
        updateStatus("replace_no_find")
        return
    end

    if not ensureFindMatches() then
        return
    end
    local matches = state.findMatches or {}
    if #matches == 0 then
        updateStatus("no_find_results")
        return
    end

    local function currentContains()
        local idx = state.selectedIndex
        if not idx then
            return false
        end
        local entry = state.entries[idx]
        if not entry or not entry.text then
            return false
        end
        return entry.text:find(findText, 1, true) ~= nil
    end

    local attempts = 0
    while not currentContains() and attempts < #matches do
        local jumped = gotoNextMatch()
        attempts = attempts + 1
        if not jumped then
            break
        end
    end

    if not currentContains() then
        updateStatus("no_replace")
        return
    end

    local replaceText = it.ReplaceInput.Text or ""
    local pattern = escapePlainPattern(findText)
    local index = state.selectedIndex
    local entry = state.entries[index]
    local newText, count = (entry.text or ""):gsub(pattern, replaceText)
    if count == 0 then
        updateStatus("no_replace")
        return
    end

    entry.text = newText
    local item = tree:TopLevelItem(index - 1)
    if item then
        item.Text[3] = newText
        item.BackgroundColor[3] = findHighlightColor
    end
    setEditorText(newText)

    -- refresh matches and move to the next one
    local replacedIndex = index
    state.currentMatchHighlight = nil
    refreshFindMatches()
    local updatedMatches = state.findMatches or {}
    if #updatedMatches == 0 then
        updateStatus("match_progress", 0, 0)
        return
    end

    local nextIdx = 1
    for i, matchIndex in ipairs(updatedMatches) do
        if matchIndex > replacedIndex then
            nextIdx = i
            break
        end
        if i == #updatedMatches then
            nextIdx = 1
        end
    end
    state.findIndex = nextIdx
    gotoNextMatch()
end

local function exportAndImport()
    if not state.entries or #state.entries == 0 then
        updateStatus("no_entries_update")
        return
    end
    local tempDir = getTempDir()
    ensureDir(tempDir)
    local tempPath = nextSrtPathForTimeline(state.timeline)
    local ok, err = writeSrt(state.entries, tempPath, state.startFrame or 0, state.fps or 24.0)
    if not ok then
        updateStatus(err or "write_failed")
        return
    end
    local success, importErr = importSrtToTimeline(tempPath)
    if not success then
        updateStatus(importErr or "import_failed")
        return
    end
    refreshFromTimeline()
    updateStatus("updated_success")
end

function win.On.LangCnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    setLanguage("cn")
end

function win.On.LangEnCheckBox.Clicked(ev)
    if languageProgrammatic then
        return
    end
    setLanguage("en")
end

function win.On.MainTabs.CurrentChanged(ev)
    if not mainStack then
        return
    end
    local index = (ev and ev.Index) or 0
    mainStack.CurrentIndex = index
end

function win.On.FindInput.TextChanged(ev)
    clearAllFindHighlights()     -- ← 改成清全表
    state.findMatches = nil
    state.findIndex   = nil
    state.findQuery   = it.FindInput.Text or ""
end

function win.On.FindInput.EditingFinished(ev)
    if refreshFindMatches() then
        updateStatus("matches_rows_occ", state.findRows or 0, state.findOcc or 0)
    end
end


function win.On.FindButton.Clicked(ev)
    gotoNextMatch()
end

function win.On.AllReplaceButton.Clicked(ev)
    applyReplace()
end

function win.On.SingleReplaceButton.Clicked(ev)
    replaceSingle()
end

function win.On.RefreshButton.Clicked(ev)
    clearHighlights()
    state.findMatches = nil
    state.findIndex = nil
    refreshFromTimeline()
end

function win.On.UpdateSubtitleButton.Clicked(ev)
    exportAndImport()
end

function win.On.CopyrightButton.Clicked(ev)
    local preferEnglish = false
    if langEn and langEn.Checked then
        preferEnglish = true
    elseif state.language == "en" then
        preferEnglish = true
    end
    local targetUrl = preferEnglish and SCRIPT_KOFI_URL or SCRIPT_BILIBILI_URL
    openExternalUrl(targetUrl)
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
    local newText = editor.PlainText or editor.Text or ""
    entry.text = newText
    local item = tree:TopLevelItem(index - 1)
    if item then
        item.Text[3] = newText
    end
end

function win.On.SubtitleTree.ItemClicked(ev)
    if state.suppressTreeSelection then
        return
    end
    local item = tree:CurrentItem()
    if not item then
        return
    end
    local index = tonumber(item.Text[0] or "")
    if not index then
        return
    end
    jumpToEntry(index, true)
end

function win.On.SubtitleUtilityWin.Close(ev)
    saveSettings(settingsFile, {
        lang_cn = langCn and langCn.Checked or false,
        lang_en = langEn and langEn.Checked or false,
    })
    cleanupTempDir()
    disp:ExitLoop()
end

applyLanguage(state.language)
refreshFromTimeline()
win:Show()
disp:RunLoop()
win:Hide()
