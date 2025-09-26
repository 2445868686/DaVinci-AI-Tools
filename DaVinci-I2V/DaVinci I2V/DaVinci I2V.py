# ================= 用户配置 =================
SCRIPT_NAME = "DaVinci I2V"
SCRIPT_VERSION = " 1.0"
SCRIPT_AUTHOR = "HEIBA"

SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
WINDOW_WIDTH,  WINDOW_HEIGHT  = 600, 650
X_CENTER = (SCREEN_WIDTH - WINDOW_WIDTH) // 2
Y_CENTER = (SCREEN_HEIGHT - WINDOW_HEIGHT) // 2

SCRIPT_KOFI_URL="https://ko-fi.com/heiba"
SCRIPT_BILIBILI_URL  = "https://space.bilibili.com/385619394"

MINIMAX_LINK = "https://platform.minimaxi.com/login"
RUNWAY_LINK  = "https://dev.runwayml.com/"

MAX_BYTES  = 10 * 1024 * 1024
ALLOW_SUFF = {".png", ".jpg", ".jpeg"}

MINIMAX_MODEL_LIST = [
    "MiniMax-Hailuo-02",
    "I2V-01-Director",
    "I2V-01-live",
    "I2V-01",
]
MINIMAX_I2V_MODELS = {"I2V-01", "I2V-01-Director", "I2V-01-live"}

RUNWAY_MODEL_LIST = [
    "gen4_turbo",
    "gen3a_turbo",
]

_OP_START_TS   = None
PREVIEW_PATHS  = {}

import os
import sys
import platform
import re
import threading
from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
import time
import json
import base64 
import webbrowser
import shutil

SCRIPT_PATH      = os.path.dirname(os.path.abspath(sys.argv[0]))
TEMP_DIR         = os.path.join(SCRIPT_PATH, "temp")
SETTINGS         = os.path.join(SCRIPT_PATH, "config", "i2v_settings.json")
STATUS_MAP_FILE  = os.path.join(SCRIPT_PATH, "config", "status.json")

DEFAULT_SETTINGS = {

    "MINIMAX_BASE_URL": "",
    "MINIMAX_API_KEY": "",
    "RUNWAY_BASE_URL": "",
    "RUNWAY_API_KEY": "",
    "PATH":"",
    "MODEL": 0,
    "CN":True,
    "EN":False,
}

# ---------- Resolve/Fusion 连接,外部环境使用（先保存起来） ----------
try:
    import DaVinciResolveScript as dvr_script
    from python_get_resolve import GetResolve
    print("DaVinciResolveScript from Python")
except ImportError:
    if platform.system() == "Darwin":
        path1 = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Examples"
        path2 = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    elif platform.system() == "Windows":
        path1 = os.path.join(os.environ['PROGRAMDATA'], "Blackmagic Design", "DaVinci Resolve", "Support", "Developer", "Scripting", "Examples")
        path2 = os.path.join(os.environ['PROGRAMDATA'], "Blackmagic Design", "DaVinci Resolve", "Support", "Developer", "Scripting", "Modules")
    else:
        raise EnvironmentError("Unsupported operating system")
    sys.path += [path1, path2]
    import DaVinciResolveScript as dvr_script
    from python_get_resolve import GetResolve
    print("DaVinciResolveScript from DaVinci")

try:
    import requests
except ImportError:
    system = platform.system()
    if system == "Windows":
        program_data = os.environ.get("PROGRAMDATA", r"C:\ProgramData")
        lib_dir = os.path.join(
            program_data,
            "Blackmagic Design",
            "DaVinci Resolve",
            "Fusion",
            "HB",
            SCRIPT_NAME,
            "Lib"
        )
    elif system == "Darwin":
        lib_dir = os.path.join(
            "/Library",
            "Application Support",
            "Blackmagic Design",
            "DaVinci Resolve",
            "Fusion",
            "HB",
            SCRIPT_NAME,
            "Lib"
        )
    else:
        lib_dir = os.path.normpath(
            os.path.join(SCRIPT_PATH, "..", "..", "..","HB", SCRIPT_NAME,"Lib")
        )

    lib_dir = os.path.normpath(lib_dir)
    if os.path.isdir(lib_dir):
        sys.path.insert(0, lib_dir)
    else:
        print(f"Warning: The TTS/Lib directory doesn’t exist:{lib_dir}", file=sys.stderr)

    try:
        import requests
        print(lib_dir)
    except ImportError as e:
        print("Dependency import failed—please make sure all dependencies are bundled into the Lib directory:", lib_dir, "\nError message:", e)

fusion     = resolve.Fusion()  
ui         = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)

loading_win = dispatcher.AddWindow(
    {
        "ID": "LoadingWin",                            
        "WindowTitle": "Loading",                     
        "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],                  
        "Spacing": 10,                                
        "StyleSheet": "*{font-size:14px;}"            
    },
    [
        ui.VGroup(                                  
            [
                ui.Label(                          
                    {
                        "ID": "LoadLabel", 
                        "Text": "Loading...",
                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                    }
                )
            ]
        )
    ]
)
loading_win.Show()
_loading_items = loading_win.GetItems()
_loading_start_ts = time.time()
_loading_timer_stop = False

def _loading_timer_worker():
    while not _loading_timer_stop:
        try:
            elapsed = int(time.time() - _loading_start_ts)
            _loading_items["LoadLabel"].Text = f"Please wait , loading... \n( {elapsed}s elapsed )"
        except Exception:
            pass
        time.sleep(1.0)

threading.Thread(target=_loading_timer_worker, daemon=True).start()

# ---------- 状态码映射 ----------
def _load_status_map(path: str) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}

_STATUS_MAP = _load_status_map(STATUS_MAP_FILE)

def _status_text_by_code(code: Any) -> Dict[str, str]:
    key1, key2 = f"error_{code}", str(code)
    pair = _STATUS_MAP.get(key1) or _STATUS_MAP.get(key2) or _STATUS_MAP.get("error_1000")
    if not pair:
        return {"en": "Unknown error", "zh": "未知错误"}
    en, zh = (pair + ["Unknown error", "未知错误"])[:2]
    return {"en": en, "zh": zh}

# ---------- UI：主窗体 / 配置窗体 / 消息窗 ----------
def build_provider_tab_ui(id_prefix: str):
    # ---------- UI 复用：通用 Provider 选项卡构建器 ----------
    return ui.VGroup({"Spacing": 10, "Weight": 1}, [
        ui.VGroup({"Spacing": 0, "Weight": 1}, [
            ui.Label({
                "ID": f"{id_prefix}CurrentMode",
                "Text": "图生视频",
                "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                "WordWrap": True,
                "StyleSheet": "color:#bbb; font-size:16px;",
                "Weight": 0
            }),
            ui.VGap(10),
            ui.HGroup({"Spacing": 12, "Weight": 1}, [
                ui.VGroup({"Spacing": 8, "Weight": 1}, [
                    ui.Button({
                        "ID": f"{id_prefix}FirstPreview",
                        "Flat": True,
                        "IconSize": [WINDOW_WIDTH/2.5, WINDOW_HEIGHT/3],
                        "MinimumSize": [WINDOW_WIDTH/2.5, WINDOW_HEIGHT/5],
                        "StyleSheet": "border:2px dashed #444; border-radius:0px; background:transparent;",
                        "Weight": 1
                    }),
                ]),
                ui.Label({"Text": " ", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}, "Weight": 0}),
                ui.VGroup({"Spacing": 8, "Weight": 1}, [
                    ui.Button({
                        "ID": f"{id_prefix}LastPreview",
                        "Flat": True,
                        "IconSize": [WINDOW_WIDTH/2.5, WINDOW_HEIGHT/3],
                        "StyleSheet": "border:2px dashed #444; border-radius:0px; background:transparent;",
                        "MinimumSize": [WINDOW_WIDTH/2.5, WINDOW_HEIGHT/5],
                        "Weight": 1
                    }),
                ]),
            ]),
            ui.VGap(5),
            ui.Label({
                "ID": f"{id_prefix}InfoText",
                "Text": "支持 JPG / PNG，≤10MB，建议尺寸 ≥300px\n",
                "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                "WordWrap": True,
                "StyleSheet": "color:#555; font-size:12px;",
                "Weight": 0
            }),
            ui.VGap(10),
            ui.HGroup({"Spacing": 12, "Weight": 0.2}, [
                ui.VGroup({"Spacing": 8, "Weight": 1}, [
                    ui.HGroup({"Spacing": 8, "Weight": 1}, [
                        ui.Button({
                            "ID": f"{id_prefix}PickFirstCurrentBtn",
                            "Text": "从播放头选择首帧",
                            "StyleSheet": "border:2px dashed #555; border-radius:12px; font-size:14px; padding:4px 10px;",
                            "Weight": 1
                        }),
                        ui.Button({
                            "ID": f"{id_prefix}PickFirstBtn",
                            "Text": "上传首帧",
                            "StyleSheet": "border:0px dashed #555; border-radius:12px; font-size:14px; padding:4px 10px;",
                            "Weight": 0
                        }),
                    ]),
                ]),
                    ui.Button({
                        "ID": f"{id_prefix}SwapBtn",
                        "Text": "⇆",
                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                        "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                        "Flat": True,
                        "TextColor": [0.1, 0.3, 0.9, 1],
                        "BackgroundColor": [1, 1, 1, 0],
                        "Weight": 0
                    }),
                ui.VGroup({"Spacing": 8, "Weight": 1}, [
                    ui.HGroup({"Spacing": 8, "Weight": 1}, [
                        ui.Button({
                            "ID": f"{id_prefix}PickLastCurrentBtn",
                            "Text": "从播放头选择尾帧",
                            "StyleSheet": "border:2px dashed #555; border-radius:12px; font-size:14px; padding:4px 10px;",
                            "Weight": 1
                        }),
                        ui.Button({
                            "ID": f"{id_prefix}PickLastBtn",
                            "Text": "上传尾帧",
                            "StyleSheet": "border:0px dashed #555; border-radius:12px; font-size:14px; padding:4px 10px;",
                            "Weight": 0
                        }),
                    ]),
                ]),
            ]),
        ]),
        ui.TextEdit({"ID": f"{id_prefix}Prompt", "Text": "", "PlaceholderText": "Prompt ...", "Weight": 0.5}),
        ui.HGroup({"Spacing": 8, "Weight": 0.1}, [
            ui.Label({"ID": f"{id_prefix}ModelLabel",      "Text": "Model:",        "Alignment": {"AlignRight": True}, "Weight": 0}),
            ui.ComboBox({"ID": f"{id_prefix}ModelCombo",                          "Weight": 0.33}),
            ui.Label({"ID": f"{id_prefix}DurationLabel",   "Text": "Duration(s):",  "Alignment": {"AlignRight": True}, "Weight": 0}),
            ui.ComboBox({"ID": f"{id_prefix}DurationCombo",                      "Weight": 0.33}),
            ui.Label({"ID": f"{id_prefix}ResolutionLabel", "Text": "Resolution:",   "Alignment": {"AlignRight": True}, "Weight": 0}),
            ui.ComboBox({"ID": f"{id_prefix}ResCombo",                            "Weight": 0.33}),
        ]),
        ui.HGroup({"Weight": 0.1}, [
            ui.Label({"ID": f"{id_prefix}TaskIDLabel", "Text": "Task ID:", "Weight": 0}),
            ui.LineEdit({"ID": f"{id_prefix}TaskID", "Text": "", "PlaceholderText": "", "Weight": 1})
        ]),
        ui.HGroup({"Spacing": 8, "Weight": 0.15}, [
            ui.Button({"ID": f"{id_prefix}PostButton", "Text": "生成", "Weight": 1}),
            ui.Button({"ID": f"{id_prefix}GetButton",  "Text": "下载", "Weight": 1}),
        ]),
        ui.Button({
                                "ID": "CopyrightButton",
                                "Text": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
                                "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                                "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                                "Flat": True,
                                "TextColor": [0.1, 0.3, 0.9, 1],
                                "BackgroundColor": [1, 1, 1, 0],
                                "Weight": 0.1
                            })
    ])

win = dispatcher.AddWindow(
    {
        "ID": "I2VWin",
        "WindowTitle": SCRIPT_NAME + SCRIPT_VERSION,
        "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],
        "Spacing": 10,
        "StyleSheet": "*{font-size:14px;}"
    },
    [
        ui.VGroup({"Spacing": 10, "Weight": 1}, [
            ui.VGroup({"Spacing": 8, "Weight": 1}, [
                ui.TabBar({"ID": "MyTabs", "Weight": 0.0}),
                ui.Stack({"ID": "MyStack", "Weight": 1}, [
                    build_provider_tab_ui("Minimax"),
                    
                    
                    build_provider_tab_ui("Runway"),
                    ui.VGroup({"Weight": 1, "Spacing": 10}, [
                        ui.VGroup({"Weight": 1}, [
                            ui.HGroup({"Weight": 0}, [
                                ui.Label({"ID": "PathLabel", "Text": "保存路径", "Alignment": {"AlignLeft": True}, "Weight": 0.2}),
                                ui.LineEdit({"ID": "Path", "Text": "", "PlaceholderText": "", "ReadOnly": False, "Weight": 0.6}),
                                ui.Button({"ID": "Browse", "Text": "浏览", "Weight": 0.2}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Label({"ID": "MinimaxConfigLabel", "Text": "Minimax", "Weight": 0.1}),
                                ui.Button({"ID": "ShowMinimax", "Text": "配置", "Weight": 0.1}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Label({"ID": "RunwayConfigLabel", "Text": "Runway", "Weight": 0.1}),
                                ui.Button({"ID": "ShowRunway", "Text": "配置", "Weight": 0.1}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.CheckBox({"ID": "LangEnCheckBox", "Text": "EN", "Checked": True,  "Weight": 0}),
                                ui.CheckBox({"ID": "LangCnCheckBox", "Text": "简体中文", "Checked": False, "Weight": 0}),
                            ]),
                            ui.Button({
                                "ID": "CopyrightButton",
                                "Text": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
                                "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                                "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                                "Flat": True,
                                "TextColor": [0.1, 0.3, 0.9, 1],
                                "BackgroundColor": [1, 1, 1, 0],
                                "Weight": 0.1
                            })
                        ]),
                    ]),
                    
                ])
            ])
        ])
    ]
)

minimax_config_win = dispatcher.AddWindow(
    {
        "ID": "MinimaxConfigWin",
        "WindowTitle": "Minimax API",
        "Geometry": [900, 400, 350, 150],
        "Hidden": True,
        "StyleSheet": "* { font-size: 14px; }"
    },
    [
        ui.VGroup([
            ui.Label({"ID": "MinimaxLabel", "Text": "Miniamx API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
            ui.HGroup({"Weight": 1}, [
                ui.Label({"ID": "MinimaxBaseURLLabel", "Text": "Base URL", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                ui.LineEdit({"ID": "MinimaxBaseURL", "Text": "", "PlaceholderText": "https://api.minimaxi.com", "Weight": 0.8}),
            ]),
            ui.HGroup({"Weight": 1}, [
                ui.Label({"ID": "MinimaxApiKeyLabel", "Text": "API Key", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                ui.LineEdit({"ID": "MinimaxApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
            ]),
            ui.HGroup({"Weight": 1}, [
                ui.Button({"ID": "MinimaxConfirm", "Text": "确定", "Weight": 1}),
                ui.Button({"ID": "MinimaxRegisterButton", "Text": "注册", "Weight": 1}),
            ]),
        ])
    ]
)

runway_config_win = dispatcher.AddWindow(
    {
        "ID": "RunwayConfigWin",
        "WindowTitle": "Runway API",
        "Geometry": [900, 600, 350, 150],
        "Hidden": True,
        "StyleSheet": "* { font-size: 14px; }"
    },
    [
        ui.VGroup([
            ui.Label({"ID": "RunwayLabel", "Text": "Runway API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
            ui.HGroup({"Weight": 1}, [
                ui.Label({"ID": "RunwayBaseURLLabel", "Text": "Base URL", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                ui.LineEdit({"ID": "RunwayBaseURL", "Text": "", "PlaceholderText": "https://api.dev.runwayml.com", "Weight": 0.8}),
            ]),
            ui.HGroup({"Weight": 1}, [
                ui.Label({"ID": "RunwayApiKeyLabel", "Text": "API Key", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                ui.LineEdit({"ID": "RunwayApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
            ]),
            ui.HGroup({"Weight": 1}, [
                ui.Button({"ID": "RunwayConfirm", "Text": "确定", "Weight": 1}),
                ui.Button({"ID": "RunwayRegisterButton", "Text": "注册", "Weight": 1}),
            ]),
        ])
    ]
)

msgbox = dispatcher.AddWindow(
    {
        "ID": "msg",
        "WindowTitle": "Warning",
        "Geometry": [750, 400, 350, 100],
        "Spacing": 10,
    },
    [
        ui.VGroup([
            ui.Label({"ID": "WarningLabel", "Text": "", "Alignment": {"AlignCenter": True}, "WordWrap": True}),
            ui.HGroup({"Weight": 0}, [ui.Button({"ID": "OkButton", "Text": "OK"})]),
        ])
    ]
)

# ---------- 多语言 ----------
translations = {
    "cn": {
        "Tabs": ["海螺视频", "Runway", "配置"],
        "PathLabel": "保存路径",
        "Browse": "浏览",
        "MinimaxConfigLabel": "Minimax",
        "RunwayConfigLabel": "Runway",
        "CurrentMode":"当前模式：图生视频",
        "InfoText":"支持 JPG / PNG，≤10MB，建议尺寸 ≥ 300px",
        "ShowMinimax": "配置",
        "ShowRunway": "配置",
        "PickFirstBtn": "📂",
        "PickLastBtn": "📂",
        "PickFirstCurrentBtn": "从播放头选择首帧",
        "PickLastCurrentBtn": "从播放头选择尾帧",
        "MinimaxModelLabel": "模型：",
        "MinimaxDurationLabel": "时长(s)：",
        "TaskIDLabel": "任务ID：",
        "MinimaxResolutionLabel": "分辨率：",
        "MinimaxGetButton": "下载",
        "MinimaxPostButton": "生成",
        "ModelLabel": "模型:",
        "DurationLabel": "时长(s):",
        "ResolutionLabel": "分辨率：",
        "GetButton": "下载",
        "PostButton": "生成",
        "CopyrightButton": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
    },
    "en": {
        "Tabs": ["Hailuo", "Runway", "Configuration"],
        "InfoText":"Support JPG / PNG, ≤10MB, recommended size ≥ 300px",                           
        "PathLabel": "Save Path",
        "CurrentMode":"Current mode: Image to Video",
        "Browse": "Browse",
        "MinimaxConfigLabel": "Minimax",
        "RunwayConfigLabel": "Runway",
        "ShowMinimax": "Config",
        "ShowRunway": "Config",
        "PickFirstBtn": "📂",
        "PickLastBtn": "📂",
        "PickFirstCurrentBtn": "Current First",
        "PickLastCurrentBtn": "Current Last",
        "MinimaxModelLabel": "Model:",
        "MinimaxDurationLabel": "Duration(s):",
        "TaskIDLabel": "Task ID:",
        "MinimaxResolutionLabel": "Resolution:",
        "MinimaxGetButton": "下载",
        "MinimaxPostButton": "Generate",
        "ModelLabel": "Model:",
        "DurationLabel": "Duration(s):",
        "ResolutionLabel": "Resolution:",
        "GetButton": "Download",
        "PostButton": "Generate",
        "CopyrightButton": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
    }
}

# ---------- 常用工具/封装（不改变外部行为） ----------
def connect_resolve():
    pm  = resolve.GetProjectManager()
    prj = pm.GetCurrentProject()
    mp  = prj.GetMediaPool()
    root= mp.GetRootFolder()
    tl  = prj.GetCurrentTimeline()
    fps = float(prj.GetSetting("timelineFrameRate"))
    return resolve, prj, mp, root, tl, fps

def timecode_to_frames(timecode, frame_rate):
    try:
        m = re.match(r"^(\d{2}):(\d{2}):(\d{2})([:;])(\d{2,3})$", timecode)
        if not m:
            raise ValueError(f"Invalid timecode format: {timecode}")
        hh, mm, ss, sep, ff = m.groups()
        hh, mm, ss, ff = int(hh), int(mm), int(ss), int(ff)
        is_drop = (sep == ';')

        if is_drop:
            if frame_rate in [23.976, 29.97, 59.94, 119.88]:
                nominal = round(frame_rate * 1000 / 1001)
                dropf   = int(round(nominal / 15))
            else:
                raise ValueError(f"Unsupported drop frame rate: {frame_rate}")
            total_minutes = hh * 60 + mm
            total_drop    = dropf * (total_minutes - total_minutes // 10)
            frames = ((hh * 3600) + (mm * 60) + ss) * nominal + ff
            frames -= total_drop
        else:
            nominal = round(frame_rate * 1000 / 1001) if frame_rate in [23.976, 29.97, 47.952, 59.94, 95.904, 119.88] else frame_rate
            frames  = ((hh * 3600) + (mm * 60) + ss) * nominal + ff
        return frames
    except ValueError as e:
        print(f"Error converting timecode to frames: {e}")
        return None
    
def get_first_empty_track(timeline, start_frame, end_frame, media_type):
    idx = 1
    while True:
        items = timeline.GetItemListInTrack(media_type, idx)
        if not items:
            return idx
        is_empty = True
        for it in items:
            if it.GetStart() <= end_frame and start_frame <= it.GetEnd():
                is_empty = False
                break
        if is_empty:
            return idx
        idx += 1

def add_to_media_pool_and_timeline(start_frame, end_frame, filename):
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    folder = None
    for f in root.GetSubFolderList():
        if f.GetName() == "I2V":
            folder = f
            break
    if not folder:
        folder = mpool.AddSubFolder(root, "I2V")
    if not folder:
        print("Failed to create or find I2V folder.")
        return False

    mpool.SetCurrentFolder(folder)
    imported = mpool.ImportMedia([filename])
    if not imported:
        print(f"Failed to import media: {filename}")
        return False

    clip = imported[0]
    dur_frames = timecode_to_frames(clip.GetClipProperty("Duration"), fps)
    track_index = get_first_empty_track(tl, start_frame, end_frame, "video")
    clip_info = {
        "mediaPoolItem": clip,
        "startFrame": 0,
        "endFrame": dur_frames - 1,
        "trackIndex": track_index,
        "recordFrame": start_frame,
        "stereoEye": "both"
    }
    tli = mpool.AppendToTimeline([clip_info])
    tag = elapsed_tag(_OP_START_TS)
    if tli:
        print(f"{tag} Appended clip: {clip.GetName()} to timeline at frame {start_frame} on track {track_index}.")
        return True
    print(f"{tag} Failed to append clip to timeline.")
    return False

def encode_image_to_data_uri(img_path: str) -> str:
    ext  = os.path.splitext(img_path)[1].lower()
    mime = "jpeg" if ext in [".jpg", ".jpeg"] else "png"
    with open(img_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    return f"data:image/{mime};base64,{b64}"

def _read_png_size(path: str):
    try:
        with open(path, 'rb') as f:
            sig = f.read(8)
            if sig != b"\x89PNG\r\n\x1a\n":
                return None
            _ = f.read(4)  # length
            if f.read(4) != b'IHDR':
                return None
            w = int.from_bytes(f.read(4), 'big')
            h = int.from_bytes(f.read(4), 'big')
            return (w, h)
    except Exception:
        return None

def _read_jpeg_size(path: str):
    try:
        with open(path, 'rb') as f:
            if f.read(2) != b"\xff\xd8":
                return None
            while True:
                byte = f.read(1)
                if not byte:
                    return None
                if byte != b"\xff":
                    continue
                marker = f.read(1)
                while marker == b"\xff":
                    marker = f.read(1)
                if marker in [b"\xc0", b"\xc1", b"\xc2", b"\xc3", b"\xc5", b"\xc6", b"\xc7", b"\xc9", b"\xca", b"\xcb", b"\xcd", b"\xce", b"\xcf"]:
                    _len = int.from_bytes(f.read(2), 'big')
                    f.read(1)  # precision
                    h = int.from_bytes(f.read(2), 'big')
                    w = int.from_bytes(f.read(2), 'big')
                    return (w, h)
                else:
                    seg_len = int.from_bytes(f.read(2), 'big')
                    f.seek(seg_len - 2, 1)
    except Exception:
        return None

def get_image_size(path: str):
    ext = os.path.splitext(path)[1].lower()
    if ext == '.png':
        return _read_png_size(path)
    if ext in ('.jpg', '.jpeg'):
        return _read_jpeg_size(path)
    return None

def _is_image_ok(path):
    if not path or not os.path.isabs(path) or not os.path.exists(path):
        return False, "路径不存在或不是绝对路径"
    if os.path.splitext(path)[1].lower() not in ALLOW_SUFF:
        return False, "仅支持 PNG/JPG"
    try:
        if os.path.getsize(path) > MAX_BYTES:
            return False, "文件超过 10MB"
    except Exception:
        return False, "无法读取文件大小"
    return True, "OK"

def _set_preview(btn_id, path):
    items[btn_id].Icon = ui.Icon({"File": path})


def _ensure_temp_dir() -> bool:
    try:
        os.makedirs(TEMP_DIR, exist_ok=True)
        return True
    except Exception as exc:
        print(f"Failed to prepare temp directory: {exc}")
        return False


def _export_current_frame_to_temp(prefix: str) -> Optional[str]:
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    if not proj or not tl:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return None
    if not _ensure_temp_dir():
        show_dynamic_message("Cannot prepare temp folder.", "无法创建临时文件夹。")
        return None

    timestamp = int(time.time() * 1000)
    filename = f"{prefix}_{timestamp}.png"
    file_path = os.path.join(TEMP_DIR, filename)

    try:
        ok = proj.ExportCurrentFrameAsStill(file_path)
    except Exception as exc:
        print(f"ExportCurrentFrameAsStill failed: {exc}")
        ok = False

    if ok and os.path.exists(file_path):
        return file_path

    try:
        if os.path.exists(file_path):
            os.remove(file_path)
    except Exception:
        pass
    show_dynamic_message("Export current frame failed.", "导出当前帧失败。")
    return None


def select_current_frame_for(preview_btn_id: str, prefix: str):
    still_path = _export_current_frame_to_temp(prefix)
    if not still_path:
        return
    _set_preview(preview_btn_id, still_path)
    PREVIEW_PATHS[preview_btn_id] = still_path
    try:
        items[preview_btn_id].Update()
    except Exception:
        pass


def cleanup_temp_dir():
    try:
        if os.path.isdir(TEMP_DIR):
            shutil.rmtree(TEMP_DIR)
    except Exception as exc:
        print(f"Failed to clean temp directory: {exc}")

def generate_filename(base_path, prompt, extension):
    if not os.path.exists(base_path):
        os.makedirs(base_path)
    clean = re.sub(r'[<>:"/\\|?*]', '', (prompt or "").replace('\n', ' ').replace('\r', ' '))[:15]
    i = 1
    while True:
        fn = f"{base_path}/{clean or 'untitled'}#{i}{extension}"
        if not os.path.exists(fn):
            return fn
        i += 1

def load_settings(settings_file):
    if os.path.exists(settings_file):
        with open(settings_file, 'r') as f:
            content = f.read()
            if content:
                try:
                    return json.loads(content)
                except json.JSONDecodeError as err:
                    print('Error decoding settings:', err)
    return None
# ---------- 语言与消息（保持原逻辑） ----------
items                 = win.GetItems()
msg_items             = msgbox.GetItems()
minimax_config_items  = minimax_config_win.GetItems()
runway_config_items   = runway_config_win.GetItems()

def show_dynamic_message(en_text, zh_text):
    use_en = items["LangEnCheckBox"].Checked
    msg    = en_text if use_en else zh_text
    msgbox.Show()
    msg_items["WarningLabel"].Text = msg
    # 强制刷新，确保长时间任务轮询时文本能实时更新
    try:
        msg_items["WarningLabel"].Update()
        msgbox.Update()
    except Exception:
        pass


def elapsed_tag(start_ts: Any) -> str:
    """Return a `[+Xs]` tag for console output using a numeric timestamp or dict ref."""
    if isinstance(start_ts, dict):
        start_ts = start_ts.get("ts")
    if isinstance(start_ts, (int, float)) and start_ts > 0:
        return f"[+{int(max(0, time.time() - start_ts))}s]"
    return "[+0s]"

def show_error_by_code(code: Any, fallback_en: str = "", fallback_zh: str = ""):
    pair  = _status_text_by_code(code)
    en_m  = pair["en"] or fallback_en or "Unknown error"
    zh_m  = pair["zh"] or fallback_zh or "未知错误"
    show_dynamic_message(f"✗ {code}: {en_m}", f"✗ {code}：{zh_m}")

def switch_language(lang):
    if "MyTabs" in items:
        for idx, name in enumerate(translations[lang]["Tabs"]):
            items["MyTabs"].SetTabText(idx, name)
    for ctrl_id, val in translations[lang].items():
        if ctrl_id == "Tabs":
            continue
        # 更新原始控件文本
        if ctrl_id in items:
            items[ctrl_id].Text = val
        # 同步更新 Runway 页中前缀化的同名控件（若存在）
        runway_id = f"Runway{ctrl_id}"
        if runway_id in items:
            items[runway_id].Text = val
        # 若提供的是无前缀的通用键，尝试同步 Minimax/Runway 前缀版本
        for pfx in ("Minimax", "Runway"):
            pid = f"{pfx}{ctrl_id}"
            if pid in items:
                items[pid].Text = val

def _allow_last_frame(model: str, resolution: str) -> bool:
    if model in MINIMAX_I2V_MODELS:
        return False
    if model == "MiniMax-Hailuo-02":
        return resolution in ("768P", "1080P")
    return False

_last_tail_enable_state = {"val": None}
def _apply_last_frame_ui_minimax(allow: bool, show_tip: bool = True):
    if allow:
        items["MinimaxPickLastBtn"].Enabled = True
        items["MinimaxPickLastCurrentBtn"].Enabled = True
        if show_tip:
            if items["LangEnCheckBox"].Checked:
                items["MinimaxCurrentMode"].Text = "Current mode: First & Last Frame"
            else:
                items["MinimaxCurrentMode"].Text = "当前模式：首尾帧"

    else:
        if items["LangEnCheckBox"].Checked:
            items["MinimaxCurrentMode"].Text = "Current mode: Image to Video"
        else:
            items["MinimaxCurrentMode"].Text = "当前模式：图生视频"
        items["MinimaxPickLastBtn"].Enabled = False
        items["MinimaxPickLastCurrentBtn"].Enabled = False
        items["MinimaxLastPreview"].Icon = ui.Icon({})
        items["MinimaxLastPreview"].Update()
        PREVIEW_PATHS["MinimaxLastPreview"] = None
        
_runway_last_enable_state = {"val": None}
def _apply_last_frame_ui_runway(allow: bool, show_tip: bool = True):
    if allow:
        items["RunwayPickLastBtn"].Enabled = True
        items["RunwayPickLastCurrentBtn"].Enabled = True
        if show_tip:
            if items["LangEnCheckBox"].Checked:
                items["RunwayCurrentMode"].Text = "Current mode: First & Last Frame"
            else:
                items["RunwayCurrentMode"].Text = "当前模式：首尾帧"
    else:
        if items["LangEnCheckBox"].Checked:
            items["RunwayCurrentMode"].Text = "Current mode: Image to Video"
        else:
            items["RunwayCurrentMode"].Text = "当前模式：图生视频"
        items["RunwayPickLastBtn"].Enabled = False
        items["RunwayPickLastCurrentBtn"].Enabled = False
        items["RunwayLastPreview"].Icon = ui.Icon({})
        items["RunwayLastPreview"].Update()
        PREVIEW_PATHS["RunwayLastPreview"] = None


# 统一选择图片
def select_image_for(target_preview_btn_id, title="选择图片"):
    try:
        sel_path = fusion.RequestFile({"Title": title})
    except Exception:
        sel_path = fusion.RequestFile()
    if not sel_path:
        return
    sel_path = sel_path.strip()
    ok, msg = _is_image_ok(sel_path)
    if ok:
        _set_preview(target_preview_btn_id, sel_path)
        PREVIEW_PATHS[target_preview_btn_id] = sel_path
    else:
        show_dynamic_message(f"✗ Error：{msg}", f"✗ 选择无效：{msg}")

# ---------- Provider 基类 & MiniMax ----------
class VideoGenError(RuntimeError):
    def __init__(self, message: str, code: Optional[Any] = None, info: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.code = code
        self.info = info or {}

class BaseVideoProvider(ABC):
    def __init__(self, api_key: str, base_url: str):
        if not api_key:  raise ValueError("api_key 不能为空")
        if not base_url: raise ValueError("base_url 不能为空")
        self.api_key  = api_key
        self.base_url = base_url.rstrip("/")
        self._op_start_ts = time.time()

    @abstractmethod
    def create_video_task(self, **kwargs) -> str: ...
    @abstractmethod
    def query_video_task(self, task_id: str) -> Dict[str, Any]: ...
    @abstractmethod
    def download_file(self, file_id: str, save_path: str) -> str: ...

    def wait_for_finish(self, task_id: str, poll_interval: int = 8, timeout: int = 600) -> str:
        start_ts = time.time()
        while True:
            info   = self.query_video_task(task_id)
            status = info.get("status")
            if status in ("Success", "Finished"):
                return info.get("file_id")
            if status in ("Fail", "failed"):
                raise VideoGenError(f"[{task_id}] 任务失败：{info}")
            if time.time() - start_ts > timeout:
                raise VideoGenError(f"[{task_id}] 轮询超时 {timeout}s")
            time.sleep(poll_interval)

    def set_operation_origin(self, ts: float):
        if isinstance(ts, (int, float)) and ts > 0:
            self._op_start_ts = ts

class MiniMaxProvider(BaseVideoProvider):
    def __init__(self, api_key: str, base_url: str, on_status=None, debug: bool = False):
        super().__init__(api_key, base_url)
        self.on_status    = on_status
        self.debug        = debug
        self._last_status = None
        self._poll_count  = 0
        # Track operation timing for richer debug prints
        self._op_start_ts   = time.time()
        self._current_stage = None

    def _dbg(self, msg: str):
        if self.debug:
            elapsed = int(max(0, time.time() - (self._op_start_ts or time.time())))
            stage_suffix = f"[{self._current_stage}]" if self._current_stage else ""
            print(f"[MiniMax][{time.strftime('%H:%M:%S')}] {stage_suffix}[{elapsed}s] {msg}")

    def _headers(self) -> Dict[str, str]:
        return {"authorization": f"Bearer {self.api_key}", "content-type": "application/json"}

    def _request(self, method: str, path: str, *, params=None, json_body=None, stream=False, timeout=300) -> requests.Response:
        url = f"{self.base_url.rstrip('/')}/{path.lstrip('/')}"
        if self.debug:
            safe_body = None
            if json_body is not None:
                safe_body = {}
                for k, v in json_body.items():
                    if k in ("model", "duration", "resolution"): safe_body[k] = v
                    elif k == "prompt": safe_body[k] = (v[:120] + "…") if isinstance(v, str) and len(v) > 120 else v
                    elif k in ("first_frame_image", "last_frame_image"): safe_body[k] = "<data-uri>"
                    else: safe_body[k] = v
            self._dbg(f"HTTP {method.upper()} {url} params={params} json={safe_body}")
        try:
            resp = requests.request(method.upper(), url, headers=self._headers(), params=params,
                                    data=json.dumps(json_body) if json_body is not None else None,
                                    stream=stream, timeout=timeout)
            self._dbg(f"HTTP {resp.status_code} {url}")
            try:
                dj = resp.json()
                self._dbg(f"Resp brief={{'status': {dj.get('status')}, 'task_id': {dj.get('task_id')}, 'file_id': {dj.get('file_id')}, 'base_status_code': {(dj.get('base_resp') or {}).get('status_code')}}}")
            except Exception:
                self._dbg("Resp is not JSON (skip brief)")
            resp.raise_for_status()
            return resp
        except requests.RequestException as e:
            raise VideoGenError(f"HTTP 请求失败: {e}") from e

    def create_video_task(self, *, model: str, prompt: str = "", duration: int = 6,
                          resolution: str = "", first_frame_image: Optional[str] = None,
                          last_frame_image: Optional[str] = None, **extra) -> str:
        prev_stage = self._current_stage
        self._current_stage = "create"
        try:
            payload = {"model": model, "prompt": prompt or "", "duration": int(duration)}
            if resolution: payload["resolution"] = resolution
            if first_frame_image: payload["first_frame_image"] = encode_image_to_data_uri(first_frame_image)
            if last_frame_image:  payload["last_frame_image"]  = encode_image_to_data_uri(last_frame_image)
            if extra: payload.update(extra)

            show_dynamic_message("Submitting task to MiniMax…", "正在向 MiniMax 提交任务…")
            data    = self._request("POST", "v1/video_generation", json_body=payload).json()
            if self.debug:
                try:
                    self._dbg("[create] Full JSON response ↓")
                    print(json.dumps(data, ensure_ascii=False, indent=2))
                except Exception as _e:
                    self._dbg(f"[create] JSON dump failed: {_e}")
            task_id = data.get("task_id") or ""
            if not task_id:
                base_resp = data.get("base_resp") or {}
                code = base_resp.get("status_code") or data.get("status_code") or data.get("code") or "1000"
                raise VideoGenError("MiniMax create task failed", code=code, info=data)
            self._dbg(f"Task submitted: task_id={task_id}")
            return task_id
        finally:
            self._current_stage = prev_stage

    def query_video_task(self, task_id: str) -> Dict[str, Any]:
        if not task_id:
            raise ValueError("task_id 不能为空")

        prev_stage = self._current_stage
        self._current_stage = "query"
        try:
            resp = self._request(
                "GET",
                "v1/query/video_generation",
                params={"task_id": task_id},
                json_body=None,
            )
            data = resp.json()
            if self.debug:
                try:
                    self._dbg("[query] Full JSON response ↓")
                    print(json.dumps(data, ensure_ascii=False, indent=2))
                except Exception as _e:
                    self._dbg(f"[query] JSON dump failed: {_e}")

            base_code = (data.get("base_resp") or {}).get("status_code")
            if isinstance(base_code, int) and base_code != 0:
                if callable(self.on_status):
                    try:
                        self.on_status("failed", data)
                    except Exception:
                        pass
                raise VideoGenError("MiniMax query failed", code=base_code, info=data)

            status = data.get("status")
            if status is None:
                raise VideoGenError(f"查询任务返回异常：{data}")

            self._dbg(f"Query task={task_id} status={status}")

            if callable(self.on_status):
                try:
                    self.on_status(status, data)
                except Exception:
                    pass

            return data
        finally:
            self._current_stage = prev_stage

    def download_file(self, file_id: str, save_path: str) -> str:
        if not file_id: raise ValueError("file_id 不能为空")
        meta = self._request("GET", "v1/files/retrieve", params={"file_id": file_id}).json()
        try:
            dl_url = meta["file"]["download_url"]
        except Exception:
            raise VideoGenError(f"无法解析 download_url：{meta}")

        self._dbg(f"Download file_id={file_id} url={dl_url}")
        os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)
        show_dynamic_message("Downloading video…", "正在下载视频…")

        timeout_secs = 300
        chunk_size = 8192
        downloaded = 0
        try:
            start_ts = time.time()
            with requests.get(dl_url, stream=True, timeout=120) as r:
                r.raise_for_status()
                total_size = int(r.headers.get("Content-Length", 0))
                last_pct = -1
                last_time = time.time()
                with open(save_path, "wb") as f:
                    for chunk in r.iter_content(chunk_size):
                        # 超时控制
                        if time.time() - start_ts >= timeout_secs:
                            show_dynamic_message("[MiniMax] Download timeout (300s). Canceled.",
                                                 "[MiniMax] 下载超时（300秒），已取消。")
                            try:
                                f.close()
                            except Exception:
                                pass
                            try:
                                if os.path.exists(save_path):
                                    os.remove(save_path)
                            except Exception:
                                pass
                            raise VideoGenError("MiniMax: 下载超时")

                        if not chunk:
                            continue
                        f.write(chunk)
                        downloaded += len(chunk)

                        # —— 进度汇报 —— #
                        if total_size:
                            pct = int(downloaded * 100 / total_size)
                            if pct != last_pct:
                                show_dynamic_message(f"[MiniMax] Downloading: {pct}%",
                                                     f"[MiniMax] 下载进度: {pct}%")
                                print(f"[MiniMax]{elapsed_tag(self._op_start_ts)} Downloading: {pct}%")
                                last_pct = pct
                        else:
                            if time.time() - last_time >= 0.5:
                                mb = downloaded / (1024 * 1024)
                                show_dynamic_message(f"[MiniMax] Downloaded {mb:.1f} MB",
                                                     f"[MiniMax] 已下载 {mb:.1f} MB")
                                print(f"[MiniMax]{elapsed_tag(self._op_start_ts)} Downloaded {mb:.1f} MB")
                                last_time = time.time()
        except requests.RequestException as e:
            raise VideoGenError(f"下载文件失败：{e}")
        abs_path = os.path.abspath(save_path)
        self._dbg(f"Downloaded {downloaded} bytes -> {abs_path}")
        return abs_path

    def wait_for_finish(
        self,
        task_id: str,
        poll_interval: int = 8,
        timeout: int = 600
    ) -> str:
        """
        轮询直到 Success/Fail/超时；
        成功返回 file_id；失败抛 VideoGenError
        """
        start_ts = time.time()
        self._dbg(f"Polling start: task_id={task_id} interval={poll_interval}s timeout={timeout}s")
        show_dynamic_message(f"Task {task_id} submitted. Waiting…", f"任务 {task_id} 已提交，等待完成…")

        while True:
            self._poll_count += 1
            info = self.query_video_task(task_id)  

            base_code = (info.get("base_resp") or {}).get("status_code")
            if isinstance(base_code, int) and base_code != 0:
                raise VideoGenError(f"[{task_id}] 后端返回错误码：{base_code}", code=base_code, info=info)

            status = (info.get("status") or "").strip()

            if status != self._last_status:
                self._dbg(f"[poll {self._poll_count}] status={status}")
                self._last_status = status

            if status in ("Success", "Finished"):
                fid = info.get("file_id")
                if not fid:
                    raise VideoGenError(f"[{task_id}] 返回 Success 但没有 file_id：{info}")
                self._dbg(f"Task finished: file_id={fid}")
                return fid

            if status in ("Fail", "failed"):
                self._dbg(f"Task failed with info={info}")
                raise VideoGenError(f"[{task_id}] 任务失败：{info}")

            # 若状态为空字符串但没有错误码，视为仍在队列或处理中，继续等
            if time.time() - start_ts > timeout:
                self._dbg(f"Polling timeout after {timeout}s (last status={status})")
                raise VideoGenError(f"[{task_id}] 轮询超时 {timeout}s（最后状态：{status}）")

            time.sleep(poll_interval)

class RunwayProvider(BaseVideoProvider):
    def __init__(self, api_key: str, base_url: str = None, on_status=None, debug: bool = False):
        base_url = (base_url or os.environ.get('RUNWAY_BASE_URL') or 'https://api.dev.runwayml.com').rstrip('/')
        super().__init__(api_key, base_url)
        self.on_status = on_status
        self.debug = debug
        self._last_progress_pct = None

    def _dbg(self, msg: str):
        if self.debug:
            print(f"[Runway][{time.strftime('%H:%M:%S')}] {elapsed_tag(self._op_start_ts)} {msg}")

    def _headers(self) -> Dict[str, str]:
        return {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json',
            'X-Runway-Version': '2024-11-06'
        }

    def _request(self, method: str, path: str, *, params=None, json_body=None, stream=False, timeout=300) -> requests.Response:
        url = f"{self.base_url}{'' if path.startswith('/') else '/'}{path}"
        if self.debug:
            safe_body = None
            if json_body is not None:
                safe_body = {}
                for k, v in json_body.items():
                    if k in ("model", "duration", "ratio", "promptText"): safe_body[k] = v
                    elif k == "promptImage": safe_body[k] = "<data-uri or list>"
                    else: safe_body[k] = v
            self._dbg(f"HTTP {method.upper()} {url} params={params} json={safe_body}")
        try:
            resp = requests.request(method.upper(), url, headers=self._headers(), params=params,
                                    data=json.dumps(json_body) if json_body is not None else None,
                                    stream=stream, timeout=timeout)
            if self.debug:
                self._dbg(f"HTTP {resp.status_code} {url}")
                try:
                    dj = resp.json()
                    self._dbg(f"Resp brief={{'status': {dj.get('status')}, 'id': {dj.get('id')}}}")
                except Exception:
                    self._dbg("Resp is not JSON (skip brief)")
            resp.raise_for_status()
            return resp
        except requests.RequestException as e:
            raise VideoGenError(f"Runway HTTP 请求失败: {e}") from e

    def create_video_task(self, *, model: str, prompt: str = "", duration: int = 10,
                          ratio: str = "1280:720", promptImage=None, **extra) -> str:
        if not promptImage:
            raise VideoGenError("Runway: 缺少首帧图片 promptImage")
        payload = {
            'model': model,
            'promptText': prompt or "",
            'duration': int(duration),
            'ratio': ratio,
            'promptImage': promptImage
        }
        if extra:
            payload.update(extra)

        show_dynamic_message("Submitting task to Runway…", "正在向 Runway 提交任务…")
        data = self._request('POST', '/v1/image_to_video', json_body=payload).json()
        if self.debug:
            try:
                self._dbg("[create] Full JSON response ↓")
                print(json.dumps(data, ensure_ascii=False, indent=2))
            except Exception as _e:
                self._dbg(f"[create] JSON dump failed: {_e}")
        task_id = data.get('id') or data.get('task_id')
        if not task_id:
            raise VideoGenError(f"Runway: 返回异常：{data}")
        self._dbg(f"Task submitted: id={task_id}")
        return task_id

    def query_video_task(self, task_id: str) -> Dict[str, Any]:
        if not task_id:
            raise ValueError("task_id 不能为空")

        def _map_status(s: str) -> str:
            s = (s or "").strip().lower()
            if s in ("succeeded", "success", "finished", "complete", "completed"): return "Success"
            if s in ("failed", "error", "canceled", "cancelled"): return "failed"
            if s in ("pending", "queued", "queueing", "waiting"): return "Queueing"
            if s in ("running", "processing", "in_progress", "generating"): return "Processing"
            return s.capitalize() or "Processing"

        def _extract_video_url(d: Dict[str, Any]) -> Optional[str]:
            # common containers
            for key in ("video", "video_url", "download_url", "url", "uri", "asset_url"):
                v = d.get(key)
                if isinstance(v, str) and v.startswith("http"):
                    return v
            # assets array
            assets = d.get("assets") or d.get("artifacts") or d.get("outputs") or d.get("result") or d.get("output")
            # allow string output directly
            if isinstance(assets, str) and assets.startswith("http"):
                return assets
            if isinstance(assets, dict):
                for key in ("video", "video_url", "url", "uri", "download_url"):
                    v = assets.get(key)
                    if isinstance(v, str) and v.startswith("http"):
                        return v
                # nested array under dict
                for k, v in assets.items():
                    if isinstance(v, list):
                        for it in v:
                            if isinstance(it, dict):
                                for kk in ("url", "uri", "download_url"):
                                    vv = it.get(kk)
                                    if isinstance(vv, str) and vv.startswith("http"):
                                        return vv
            if isinstance(assets, list):
                # list may contain direct URL strings
                for it in assets:
                    if isinstance(it, str) and it.startswith("http"):
                        return it
                # or list of dicts with url fields
                for it in assets:
                    if isinstance(it, dict):
                        for key in ("url", "uri", "download_url"):
                            v = it.get(key)
                            if isinstance(v, str) and v.startswith("http"):
                                return v
            return None
        # try GET /v1/tasks/{id}, fallback to /v1/image_to_video/{id}
        data = None
        resp = self._request("GET", f"/v1/tasks/{task_id}")
        try:
            data = resp.json()
        except Exception:
            data = None
        # fallback if 404 or no status
        if not isinstance(data, dict) or (data.get("status") is None and data.get("state") is None):
            try:
                resp2 = self._request("GET", f"/v1/image_to_video/{task_id}")
                try:
                    data = resp2.json()
                except Exception:
                    # 某些网关返回 200 但无 JSON 内容，视为仍在队列/处理中
                    data = {"status": "pending"}
            except VideoGenError:
                pass

        if not isinstance(data, dict):
            raise VideoGenError(f"Runway: 无法解析任务返回：{data}")
        if self.debug:
            try:
                self._dbg("[query] Effective task JSON ↓")
                print(json.dumps(data, ensure_ascii=False, indent=2))
            except Exception as _e:
                self._dbg(f"[query] Effective JSON dump failed: {_e}")

        raw_status = data.get("status") or data.get("state") or (data.get("task") or {}).get("status")
        status = _map_status(raw_status)
        file_url = None
        if status in ("Success", "Finished"):
            file_url = _extract_video_url(data) or _extract_video_url(data.get("task", {})) or None

        self._dbg(f"Query task={task_id} status={status} url={file_url or '-'}")

        try:
            if status in ("Processing",):
                prog = data.get("progress")
                if prog is None:
                    prog = (data.get("task") or {}).get("progress")
                if prog is not None:
                    try:
                        prog = float(prog)
                        pct = int(prog * 100) if prog <= 1 else int(prog)
                        if pct != self._last_progress_pct:
                            self._last_progress_pct = pct
                            show_dynamic_message(f"[Runway] RUNNING... {pct}%", f"[Runway] 生成中... {pct}%")
                    except Exception:
                        pass
        except Exception:
            pass
        if callable(self.on_status):
            try:
                self.on_status(status, data)
            except Exception:
                pass
        data_out = dict(data)
        if file_url:
            data_out["file_id"] = file_url
        data_out["status"] = status
        return data_out

    def download_file(self, file_id: str, save_path: str) -> str:
        if not (file_id and file_id.startswith('http')):
            raise VideoGenError("Runway: 无效的下载地址")
        os.makedirs(os.path.dirname(save_path) or '.', exist_ok=True)
        show_dynamic_message("Downloading video…", "正在下载视频…")
        timeout_secs = 300
        chunk_size = 8192
        try:
            start_ts = time.time()
            with requests.get(file_id, stream=True, timeout=120) as r:
                r.raise_for_status()
                total_size = int(r.headers.get("Content-Length", 0))
                downloaded = 0
                last_pct = -1
                last_time = time.time()
                with open(save_path, 'wb') as f:
                    for chunk in r.iter_content(chunk_size):
                        if time.time() - start_ts >= timeout_secs:
                            show_dynamic_message("[Runway] Download timeout (300s). Canceled.",
                                                 "[Runway] 下载超时（300秒），已取消。")
                            try:
                                f.close()
                            except Exception:
                                pass
                            try:
                                if os.path.exists(save_path):
                                    os.remove(save_path)
                            except Exception:
                                pass
                            raise VideoGenError("Runway: 下载超时")

                        if not chunk:
                            continue

                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size:
                            pct = int(downloaded * 100 / total_size)
                            if pct != last_pct:
                                show_dynamic_message(f"[Runway] Downloading: {pct}%",
                                                     f"[Runway] 下载进度: {pct}%")
                                print(f"[Runway]{elapsed_tag(self._op_start_ts)} Downloading: {pct}%")
                                last_pct = pct
                        else:
                            if time.time() - last_time >= 0.5:
                                mb = downloaded / (1024 * 1024)
                                show_dynamic_message(f"[Runway] Downloaded {mb:.1f} MB",
                                                     f"[Runway] 已下载 {mb:.1f} MB")
                                print(f"[Runway]{elapsed_tag(self._op_start_ts)} Downloaded {mb:.1f} MB")
                                last_time = time.time()
        except requests.RequestException as e:
            raise VideoGenError(f"Runway: 下载失败 {e}")
        return os.path.abspath(save_path)

# ---------- 统一的状态回调工厂/下载入库封装 ----------
def make_status_cb(op_start_ts_ref):
    state = {"status": None, "last_emit": 0.0}

    def _cb(status: str, info: dict):
        now = time.time()
        elapsed = int(now - op_start_ts_ref["ts"])

        en_map = {
            "Preparing":  f"Preparing… {elapsed}s",
            "Queueing":   f"In queue… {elapsed}s",
            "Processing": f"Generating… {elapsed}s",
            "Success":    f"Success! Downloading… {elapsed}s",
            "Finished":   f"Success! Downloading… {elapsed}s",
            "Fail":       f"Task failed. {elapsed}s",
            "failed":     f"Task failed. {elapsed}s",
        }
        zh_map = {
            "Preparing":  f"…准备中… {elapsed}秒",
            "Queueing":   f"…队列中… {elapsed}秒",
            "Processing": f"…生成中… {elapsed}秒",
            "Success":    f"生成完成，开始下载… {elapsed}秒",
            "Finished":   f"生成完成，开始下载… {elapsed}秒",
            "Fail":       f"任务失败。{elapsed}秒",
            "failed":     f"任务失败。{elapsed}秒",
        }

        norm_status = str(status or "")
        should_emit = (
            norm_status != state["status"] or
            now - state["last_emit"] >= 1.0
        )

        if should_emit:
            state["status"] = norm_status
            state["last_emit"] = now
            show_dynamic_message(en_map.get(norm_status, f"Status: {norm_status} {elapsed}s"),
                                 zh_map.get(norm_status, f"状态：{norm_status} {elapsed}秒"))

    return _cb

def minimax_provider_factory(on_status):
    return MiniMaxProvider(
        api_key = (minimax_config_items["MinimaxApiKey"].Text or "").strip(),
        base_url= (minimax_config_items["MinimaxBaseURL"].Text or minimax_config_items["MinimaxBaseURL"].PlaceholderText.strip()),
        on_status = on_status,
        debug = True
    )
def runway_provider_factory(on_status=None):
    api_key = (runway_config_items["RunwayApiKey"].Text or os.environ.get('RUNWAY_API_KEY', '')).strip()
    base_url = (runway_config_items["RunwayBaseURL"].Text or runway_config_items["RunwayBaseURL"].PlaceholderText.strip())
    return RunwayProvider(api_key=api_key, base_url=base_url, on_status=on_status, debug=True)

def download_and_append_to_timeline(provider: MiniMaxProvider, file_id: str, save_path: str):
    abs_path = provider.download_file(file_id, save_path)
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    current_frame = timecode_to_frames(tl.GetCurrentTimecode(), fps)
    ok = add_to_media_pool_and_timeline(current_frame, tl.GetEndFrame(), abs_path)
    if ok:
        show_dynamic_message("Finish!", "完成！")
        # 成功后清空对应 Provider 的 TaskID，避免 Get 按钮保持可用
        try:
            if isinstance(provider, MiniMaxProvider):
                items["MinimaxTaskID"].Text = ""
            elif isinstance(provider, RunwayProvider):
                items["RunwayTaskID"].Text = ""
        except Exception:
            pass
    else:
        show_dynamic_message("Append to timeline failed.", "添加到时间线失败。")

# ---------- 初始 UI 状态 ----------
items["MyStack"].CurrentIndex = 0
items["MinimaxGetButton"].Enabled    = False
items["RunwayGetButton"].Enabled     = False
for tab_name in translations["cn"]["Tabs"]:
    items["MyTabs"].AddTab(tab_name)

# ---------- 事件绑定 ----------
def on_my_tabs_current_changed(ev):
    items["MyStack"].CurrentIndex = ev["Index"]
win.On["MyTabs"].CurrentChanged = on_my_tabs_current_changed

def _pick_first(ev):
    select_image_for("MinimaxFirstPreview", "选择首帧图片")
win.On["MinimaxPickFirstBtn"].Clicked    = _pick_first

def _pick_first_current(ev):
    select_current_frame_for("MinimaxFirstPreview", "minimax_first")
win.On["MinimaxPickFirstCurrentBtn"].Clicked = _pick_first_current

def _pick_last(ev):
    select_image_for("MinimaxLastPreview", "选择尾帧图片")
win.On["MinimaxPickLastBtn"].Clicked     = _pick_last

def _pick_last_current(ev):
    select_current_frame_for("MinimaxLastPreview", "minimax_last")
win.On["MinimaxPickLastCurrentBtn"].Clicked = _pick_last_current
def on_msg_close(ev):
    msgbox.Hide()
msgbox.On.OkButton.Clicked = on_msg_close
msgbox.On.msg.Close = on_msg_close

def set_combo_items(box, new_items, default_index=0):
    box.Clear()
    for v in new_items:
        box.AddItem(v)
    if new_items:
        box.CurrentIndex = default_index

def minimax_refresh_resolution(ev=None):
    mdl = items["MinimaxModelCombo"].CurrentText
    dur = int(items["MinimaxDurationCombo"].CurrentText or 6)
    if mdl == "MiniMax-Hailuo-02":
        res_choices = ["512P", "768P"] if dur == 10 else ["512P", "768P", "1080P"]
    else:
        res_choices = ["720P"]
    cur = items["MinimaxResCombo"].CurrentText
    set_combo_items(items["MinimaxResCombo"], res_choices, default_index=res_choices.index(cur) if cur in res_choices else 0)
    allow = _allow_last_frame(mdl, items["MinimaxResCombo"].CurrentText)
    if allow != _last_tail_enable_state["val"]:
        _apply_last_frame_ui_minimax(allow, show_tip=allow)
        _last_tail_enable_state["val"] = allow
win.On.MinimaxDurationCombo.CurrentIndexChanged  = lambda ev: minimax_refresh_resolution()

def minimax_refresh_by_model(ev=None):
    mdl = items["MinimaxModelCombo"].CurrentText
    set_combo_items(items["MinimaxDurationCombo"], ["6", "10"] if mdl == "MiniMax-Hailuo-02" else ["6"], default_index=0)
    minimax_refresh_resolution()
win.On.MinimaxModelCombo.CurrentIndexChanged     = minimax_refresh_by_model

def minimax_on_resolution_changed(ev):
    mdl   = items["MinimaxModelCombo"].CurrentText
    res   = items["MinimaxResCombo"].CurrentText
    allow = _allow_last_frame(mdl, res)
    if allow != _last_tail_enable_state["val"]:
        _apply_last_frame_ui_minimax(allow, show_tip=allow)
        _last_tail_enable_state["val"] = allow
win.On.MinimaxResCombo.CurrentIndexChanged = minimax_on_resolution_changed
# ---------- Runway 事件绑定 ----------
def runway_refresh_ratio(ev=None):
    mdl = items["RunwayModelCombo"].CurrentText
    # UI 仅显示分辨率层级（720P 或 768P），方向在提交前根据图片自动判定
    if mdl == "gen4_turbo":
        res_choices = ["720P"]
    else:  
        res_choices = ["768P"]

    cur = items["RunwayResCombo"].CurrentText
    set_combo_items(
        items["RunwayResCombo"],
        res_choices,
        default_index=res_choices.index(cur) if cur in res_choices else 0
    )
    # 仅 gen3a_turbo 支持尾帧（position=last）
    allow = (mdl == "gen3a_turbo")
    if allow != _runway_last_enable_state["val"]:
        _apply_last_frame_ui_runway(allow, show_tip=allow)
        _runway_last_enable_state["val"] = allow
win.On.RunwayDurationCombo.CurrentIndexChanged  = lambda ev: runway_refresh_ratio()

def runway_refresh_by_model(ev):
    set_combo_items(items["RunwayDurationCombo"], ["5", "10"], default_index=0)
    runway_refresh_ratio()
win.On.RunwayModelCombo.CurrentIndexChanged = runway_refresh_by_model

def runway_on_ratio_changed(ev):
    mdl = items["RunwayModelCombo"].CurrentText
    allow = (mdl == "gen3a_turbo")
    if allow != _runway_last_enable_state["val"]:
        _apply_last_frame_ui_runway(allow, show_tip=allow)
        _runway_last_enable_state["val"] = allow
win.On.RunwayResCombo.CurrentIndexChanged = runway_on_ratio_changed

def on_runway_pick_first(ev):
    select_image_for("RunwayFirstPreview", "选择首帧图片")
win.On["RunwayPickFirstBtn"].Clicked = on_runway_pick_first

def on_runway_pick_first_current(ev):
    select_current_frame_for("RunwayFirstPreview", "runway_first")
win.On["RunwayPickFirstCurrentBtn"].Clicked = on_runway_pick_first_current

def on_runway_pick_last(ev):
    select_image_for("RunwayLastPreview", "选择尾帧图片")
win.On["RunwayPickLastBtn"].Clicked = on_runway_pick_last

def on_runway_pick_last_current(ev):
    select_current_frame_for("RunwayLastPreview", "runway_last")
win.On["RunwayPickLastCurrentBtn"].Clicked = on_runway_pick_last_current

def on_runway_swap(ev):
    mdl = items["RunwayModelCombo"].CurrentText
    if mdl != "gen4_turbo":
        fp = PREVIEW_PATHS.get("RunwayFirstPreview")
        lp = PREVIEW_PATHS.get("RunwayLastPreview")
        PREVIEW_PATHS["RunwayFirstPreview"], PREVIEW_PATHS["RunwayLastPreview"] = lp, fp
        if PREVIEW_PATHS.get("RunwayFirstPreview"):
            items["RunwayFirstPreview"].Icon = ui.Icon({"File": PREVIEW_PATHS["RunwayFirstPreview"]})
        else:
            items["RunwayFirstPreview"].Icon = ui.Icon({})
        if PREVIEW_PATHS.get("RunwayLastPreview"):
            items["RunwayLastPreview"].Icon = ui.Icon({"File": PREVIEW_PATHS["RunwayLastPreview"]})
        else:
            items["RunwayLastPreview"].Icon = ui.Icon({})
    else:
        PREVIEW_PATHS["RunwayLastPreview"] = None
        show_dynamic_message("This model does not support last frames!","该模型不支持尾帧！")
        #items["RunwayLastPreview"].Icon = ui.Icon({})
    items["RunwayFirstPreview"].Update(); items["RunwayLastPreview"].Update()
win.On.RunwaySwapBtn.Clicked = on_runway_swap

def on_minimax_swap(ev):
    mdl = items["MinimaxModelCombo"].CurrentText
    res = items["MinimaxResCombo"].CurrentText
    if _allow_last_frame(mdl, res):
        fp = PREVIEW_PATHS.get("MinimaxFirstPreview")
        lp = PREVIEW_PATHS.get("MinimaxLastPreview")
        PREVIEW_PATHS["MinimaxFirstPreview"], PREVIEW_PATHS["MinimaxLastPreview"] = lp, fp
        if PREVIEW_PATHS["MinimaxLastPreview"]:
            items["MinimaxLastPreview"].Icon = ui.Icon({"File": PREVIEW_PATHS["MinimaxLastPreview"]})
        else:
            items["MinimaxLastPreview"].Icon = ui.Icon({})

        if PREVIEW_PATHS["MinimaxFirstPreview"]:
            items["MinimaxFirstPreview"].Icon = ui.Icon({"File": PREVIEW_PATHS["MinimaxFirstPreview"]})
        else:
            items["MinimaxFirstPreview"].Icon = ui.Icon({})
    else:
        show_dynamic_message("This model does not support last frames!","该模型不支持尾帧！")
        PREVIEW_PATHS["MinimaxLastPreview"] = None
        #items["MinimaxLastPreview"].Icon = ui.Icon({})

    items["MinimaxFirstPreview"].Update()
    items["MinimaxLastPreview"].Update()
win.On.MinimaxSwapBtn.Clicked = on_minimax_swap

# 初始模型/分辨率
set_combo_items(items["MinimaxModelCombo"], MINIMAX_MODEL_LIST, default_index=0)
set_combo_items(items["RunwayModelCombo"], RUNWAY_MODEL_LIST, default_index=0)
minimax_refresh_by_model()
runway_refresh_by_model(None)


def on_minimax_post(ev):
    """从 UI 收集参数 → 调用 MiniMax → 保存视频（统一错误映射 + 累计耗时）"""
    global _OP_START_TS
    _OP_START_TS = time.time()  # 开始计时（无多线程）
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    if not tl:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return
    # ---------- 1) 基本校验 ----------
    first_img = PREVIEW_PATHS.get("MinimaxFirstPreview")
    last_img  = PREVIEW_PATHS.get("MinimaxLastPreview")
    prompt    = items["MinimaxPrompt"].PlainText.strip()
    save_dir  = items["Path"].Text.strip()
    base_url  = minimax_config_items["MinimaxBaseURL"].Text or minimax_config_items["MinimaxBaseURL"].PlaceholderText.strip()
    api_key   = minimax_config_items["MinimaxApiKey"].Text.strip()
    
    if items["Path"].Text == '':
        show_dynamic_message("Select a save path in the configuration panel!", "前往配置栏选择保存路径！")
        return
    if not (first_img or last_img):
        show_dynamic_message("Pick at least one frame!", "请至少选择首帧或尾帧！")
        return
    if not api_key:
        show_dynamic_message("Enter API key in the configuration panel!", "前往配置栏填写API密钥！")
        return  

    # ---------- 2) 收集参数 ----------
    model       = items["MinimaxModelCombo"].CurrentText
    duration    = int(items["MinimaxDurationCombo"].CurrentText or 6)
    resolution  = items["MinimaxResCombo"].CurrentText
    
    params = {
        "model"            : model,
        "prompt"           : prompt,
        "duration"         : duration,
        "resolution"       : resolution,
        "first_frame_image": first_img,    
    }
    if _allow_last_frame(model, resolution) and last_img:
        params["last_frame_image"] = last_img    

    save_path    = generate_filename(save_dir, prompt or "untitled", ".mp4")

    # 提前展示等待提示，避免编码参考帧期间 UI 无反馈
    show_dynamic_message("Preparing MiniMax payload…", "正在准备 MiniMax 参数…")

    op_start_ref  = {"ts": _OP_START_TS}
    provider      = minimax_provider_factory(on_status=make_status_cb(op_start_ref))
    provider.set_operation_origin(op_start_ref["ts"])

    try:
        task_id = provider.create_video_task(**params)
        items["MinimaxTaskID"].Text = task_id
        file_id = provider.wait_for_finish(task_id)
        download_and_append_to_timeline(provider, file_id, save_path)
        print(f"{elapsed_tag(op_start_ref)} ✔ Done! Saved to:\n{save_path}")
    except VideoGenError as e:
        if getattr(e, "code", None) is not None:
            show_error_by_code(e.code, "Request failed", "请求失败")
        else:
            show_dynamic_message(f"✗ Failed: {e}", f"✗ 失败：{e}")
win.On.MinimaxPostButton.Clicked     = on_minimax_post

def on_minimax_get(ev):
    global _OP_START_TS
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    if not tl:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return

    prompt    = items["MinimaxPrompt"].PlainText.strip()
    save_dir  = items["Path"].Text.strip() or os.getcwd()
    task_id   = items["MinimaxTaskID"].Text.strip()

    if not task_id:
        show_dynamic_message("Please enter a Task ID!", "请输入任务ID！")
        return

    save_path = generate_filename(save_dir, prompt or "untitled", ".mp4")

    # 立即给出查询提示，避免等待首次轮询前无状态
    show_dynamic_message(f"Preparing to query task {task_id}…", f"正在准备查询任务 {task_id}…")

    op_start_ref = {"ts": time.time()}
    _OP_START_TS = op_start_ref["ts"]
    provider     = minimax_provider_factory(on_status=make_status_cb(op_start_ref))
    provider.set_operation_origin(op_start_ref["ts"])

    try:
        file_id = provider.wait_for_finish(task_id)
        download_and_append_to_timeline(provider, file_id, save_path)
        print(f"{elapsed_tag(op_start_ref)} ✔ Done! Saved to:\n{save_path}")
    except VideoGenError as e:
        if getattr(e, "code", None) is not None:
            show_error_by_code(e.code, "Query failed", "查询失败")
        else:
            show_dynamic_message(f"✗ Failed: {e}", f"✗ 失败：{e}")

win.On.MinimaxGetButton.Clicked = on_minimax_get


def on_runway_post(ev):
    """Runway 一键生成：与 MiniMax 一致的流程（提交→轮询→下载）"""
    global _OP_START_TS
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    if not tl:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return

    first_img = PREVIEW_PATHS.get("RunwayFirstPreview")
    last_img  = PREVIEW_PATHS.get("RunwayLastPreview")
    prompt    = (items.get("RunwayPrompt").PlainText.strip() if items.get("RunwayPrompt") else "")
    save_dir  = items["Path"].Text.strip()
    base_url  = (runway_config_items["RunwayBaseURL"].Text or runway_config_items["RunwayBaseURL"].PlaceholderText.strip())
    api_key   = (runway_config_items["RunwayApiKey"].Text or "").strip()

    if not save_dir:
        show_dynamic_message("Select a save path in the configuration panel!", "前往配置栏选择保存路径！")
        return
    # Gen-3 Alpha 支持首帧或尾帧其一，或者首尾帧一起传输
    model    = items["RunwayModelCombo"].CurrentText if items.get("RunwayModelCombo") else "gen4_turbo"
    if model == "gen3a_turbo":
        if not first_img and not last_img:
            show_dynamic_message("Pick a first or last frame!", "请至少选择首帧或尾帧！")
            return
    else:
        if not first_img:
            show_dynamic_message("Pick a first frame!", "请至少选择首帧！")
            return
    if not api_key:
        show_dynamic_message("Enter API key in the configuration panel!", "前往配置栏填写API密钥！")
        return
    duration = int(items["RunwayDurationCombo"].CurrentText or 5) if items.get("RunwayDurationCombo") else 5
    res_choice = (items["RunwayResCombo"].CurrentText or ("720P" if model == "gen4_turbo" else "768P")).strip()

    # 提前告知正在准备 Runway 请求，涵盖图像读取/编码耗时
    show_dynamic_message("Preparing Runway payload…", "正在准备 Runway 参数…")
    # 检测参考图片方向（优先首帧；若 gen3a_turbo 且仅尾帧，则用尾帧）
    try:
        ref_img = first_img or (last_img if model == "gen3a_turbo" else None)
        size = get_image_size(ref_img) if ref_img else None
        is_landscape = None
        if isinstance(size, tuple) and len(size) == 2 and all(isinstance(x, int) and x > 0 for x in size):
            w, h = size
            is_landscape = (w >= h)
        if res_choice == "768P":
            ratio = "1280:768" if (is_landscape is None or is_landscape) else "768:1280"
        else:  # 720P
            ratio = "1280:720" if (is_landscape is None or is_landscape) else "720:1280"
    except Exception:
        # 回退：按模型默认横屏比例
        ratio = "1280:720" if model == "gen4_turbo" else "1280:768"

    # - 非 gen3a_turbo：仅支持首帧，使用字符串 data-uri
    # - gen3a_turbo：支持首帧、尾帧任意组合
    prompt_image_payload = None
    if model == "gen3a_turbo":
        if first_img and last_img:
            first_uri = encode_image_to_data_uri(first_img)
            last_uri  = encode_image_to_data_uri(last_img)
            prompt_image_payload = [
                {"uri": first_uri, "position": "first"},
                {"uri": last_uri,  "position": "last"},
            ]
        elif first_img:
            prompt_image_payload = encode_image_to_data_uri(first_img)
        else:
            last_uri  = encode_image_to_data_uri(last_img)
            prompt_image_payload = [
                {"uri": last_uri,  "position": "last"},
            ]
    else:
        prompt_image_payload = encode_image_to_data_uri(first_img)

    save_path    = generate_filename(save_dir, prompt or "untitled", ".mp4")
    _OP_START_TS = time.time()
    op_start_ref = {"ts": _OP_START_TS}
    provider     = runway_provider_factory(on_status=make_status_cb(op_start_ref))
    provider.set_operation_origin(op_start_ref["ts"])

    try:
        task_id = provider.create_video_task(model=model, prompt=prompt, duration=duration, ratio=ratio, promptImage=prompt_image_payload)
        if "RunwayTaskID" in items:
            items["RunwayTaskID"].Text = task_id
        # 轮询完成并下载
        file_id = provider.wait_for_finish(task_id)
        download_and_append_to_timeline(provider, file_id, save_path)
        print(f"{elapsed_tag(op_start_ref)} ✔ Done! Saved to:\n{save_path}")
    except VideoGenError as e:
        show_dynamic_message(f"✗ Failed: {e}", f"✗ 失败：{e}")
win.On.RunwayPostButton.Clicked = on_runway_post

def on_runway_get(ev):
    global _OP_START_TS
    """Runway 下载：根据 Task ID 轮询直至完成并下载到时间线。"""
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    if not tl:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return

    prompt   = (items.get("RunwayPrompt").PlainText.strip() if items.get("RunwayPrompt") else "")
    save_dir = items["Path"].Text.strip() or os.getcwd()
    task_id  = (items.get("RunwayTaskID").Text.strip() if items.get("RunwayTaskID") else "")

    if not task_id:
        show_dynamic_message("Please enter a Task ID!", "请输入任务ID！")
        return

    save_path   = generate_filename(save_dir, prompt or "untitled", ".mp4")
    op_start_ref= {"ts": time.time()}
    _OP_START_TS = op_start_ref["ts"]
    provider    = runway_provider_factory(on_status=make_status_cb(op_start_ref))
    provider.set_operation_origin(op_start_ref["ts"])

    try:
        show_dynamic_message(f"Task {task_id} submitted. Waiting…", f"任务 {task_id} 已提交，等待完成…")
        file_id = provider.wait_for_finish(task_id)
        download_and_append_to_timeline(provider, file_id, save_path)
        print(f"{elapsed_tag(op_start_ref)} ✔ Done! Saved to:\n{save_path}")
    except VideoGenError as e:
        show_dynamic_message(f"✗ Failed: {e}", f"✗ 失败：{e}")
win.On.RunwayGetButton.Clicked = on_runway_get

def on_runway_task_id_changed(ev):
    if items["RunwayTaskID"].Text:
        items["RunwayGetButton"].Enabled = True
    else:
        items["RunwayGetButton"].Enabled = False
win.On.RunwayTaskID.TextChanged = on_runway_task_id_changed

def on_browse_button_clicked(ev):
    resolve, proj, mpool, root, tl, fps = connect_resolve()
    current_path = items["Path"].Text
    selected_path = fusion.RequestDir(current_path)
    if selected_path:
        project_subdir = os.path.join(selected_path, f"{proj.GetName()}_I2V")
        try:
            os.makedirs(project_subdir, exist_ok=True)
            items["Path"].Text = str(project_subdir)
            print(f"Directory created: {project_subdir}")
        except Exception as e:
            print(f"Failed to create directory: {e}")
    else:
        print("No directory selected or the request failed.")
win.On.Browse.Clicked = on_browse_button_clicked

def _apply_lang_ui():
    if items["LangEnCheckBox"].Checked: 
        switch_language("en")
    else:                                
        switch_language("cn")

def on_lang_checkbox_clicked(ev):
    is_en_checked = ev['sender'].ID == "LangEnCheckBox"
    items["LangCnCheckBox"].Checked = not is_en_checked
    items["LangEnCheckBox"].Checked = is_en_checked
    _apply_lang_ui()
win.On.LangCnCheckBox.Clicked = on_lang_checkbox_clicked
win.On.LangEnCheckBox.Clicked = on_lang_checkbox_clicked

def on_text_changed(ev):
    if items["MinimaxTaskID"].Text:
        items["MinimaxGetButton"].Enabled = True
    else:
        items["MinimaxGetButton"].Enabled = False
win.On.MinimaxTaskID.TextChanged = on_text_changed

def on_show_minimax(ev):
    minimax_config_win.Show()
win.On.ShowMinimax.Clicked = on_show_minimax

def on_miniamx_close(ev):
    print("API setup is complete.")
    minimax_config_win.Hide()
minimax_config_win.On.MinimaxConfirm.Clicked = on_miniamx_close
minimax_config_win.On.MinimaxConfigWin.Close = on_miniamx_close

# Open registration pages
def on_minimax_register_clicked(ev):
    try:
        webbrowser.open(MINIMAX_LINK)
    except Exception as e:
        show_dynamic_message(f"Open link failed: {e}", f"打开链接失败：{e}")
minimax_config_win.On.MinimaxRegisterButton.Clicked = on_minimax_register_clicked

def on_show_runway(ev):
    runway_config_win.Show()
win.On.ShowRunway.Clicked = on_show_runway

def on_runway_close(ev):
    print("Runway API setup is complete.")
    runway_config_win.Hide()
runway_config_win.On.RunwayConfirm.Clicked = on_runway_close
runway_config_win.On.RunwayConfigWin.Close = on_runway_close

def on_runway_register_clicked(ev):
    try:
        webbrowser.open(RUNWAY_LINK)
    except Exception as e:
        show_dynamic_message(f"Open link failed: {e}", f"打开链接失败：{e}")
runway_config_win.On.RunwayRegisterButton.Clicked = on_runway_register_clicked

def save_file():
    settings = {
        "MINIMAX_BASE_URL": minimax_config_items["MinimaxBaseURL"].Text,
        "MINIMAX_API_KEY": minimax_config_items["MinimaxApiKey"].Text,
        "RUNWAY_BASE_URL": runway_config_items["RunwayBaseURL"].Text,
        "RUNWAY_API_KEY": runway_config_items["RunwayApiKey"].Text,
        "PATH":items["Path"].Text,
        "MODEL": items["MinimaxModelCombo"].CurrentIndex,
        "CN":items["LangCnCheckBox"].Checked,
        "EN":items["LangEnCheckBox"].Checked,
    }
    
    settings_file = os.path.join(SCRIPT_PATH, "config", "i2v_settings.json")
    try:
        os.makedirs(os.path.dirname(settings_file), exist_ok=True)
        
        with open(settings_file, 'w', encoding='utf-8') as f:
            json.dump(settings, f, ensure_ascii=False, indent=4)
        print(f"Settings saved to {settings_file}")
    except OSError as e:
        print(f"Error saving settings to {settings_file}: {e.strerror}")



def on_open_link_button_clicked(ev):
    if items["LangEnCheckBox"].Checked :
        webbrowser.open(SCRIPT_KOFI_URL)
    else :
        webbrowser.open(SCRIPT_BILIBILI_URL)
win.On.CopyrightButton.Clicked = on_open_link_button_clicked

def on_close(ev):
    save_file()
    cleanup_temp_dir()
    dispatcher.ExitLoop()
win.On.I2VWin.Close = on_close

saved_settings = load_settings(SETTINGS)
if saved_settings:
    items["Path"].Text = saved_settings.get("PATH", DEFAULT_SETTINGS["PATH"])
    items["MinimaxModelCombo"].CurrentIndex = saved_settings.get("MODEL", DEFAULT_SETTINGS["MODEL"])
    items["LangCnCheckBox"].Checked = saved_settings.get("CN", DEFAULT_SETTINGS["CN"])
    items["LangEnCheckBox"].Checked = saved_settings.get("EN", DEFAULT_SETTINGS["EN"])
    minimax_config_items["MinimaxBaseURL"].Text = saved_settings.get("MINIMAX_BASE_URL", DEFAULT_SETTINGS["MINIMAX_BASE_URL"])
    minimax_config_items["MinimaxApiKey"].Text = saved_settings.get("MINIMAX_API_KEY", DEFAULT_SETTINGS["MINIMAX_API_KEY"])
    runway_config_items["RunwayBaseURL"].Text = saved_settings.get("RUNWAY_BASE_URL", DEFAULT_SETTINGS["RUNWAY_BASE_URL"])
    runway_config_items["RunwayApiKey"].Text = saved_settings.get("RUNWAY_API_KEY", DEFAULT_SETTINGS["RUNWAY_API_KEY"])
    
_apply_lang_ui()

loading_win.Hide() 
win.Show()
dispatcher.RunLoop()
win.Hide()
