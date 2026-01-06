# ================= 用户配置 =================
SCRIPT_NAME    = "Sub AI Translator"
SCRIPT_VERSION = " 2.0.1"
SCRIPT_AUTHOR  = "HEIBA"
print(f"{SCRIPT_NAME} | {SCRIPT_VERSION.strip()} | {SCRIPT_AUTHOR}")
SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
WINDOW_WIDTH, WINDOW_HEIGHT = 880, 620
X_CENTER = (SCREEN_WIDTH  - WINDOW_WIDTH ) // 2
Y_CENTER = (SCREEN_HEIGHT - WINDOW_HEIGHT) // 2

SCRIPT_KOFI_URL      = "https://ko-fi.com/heiba"
SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"

MAX_RETRY   = 1
TIMEOUT_SINGLE = 10   # 非合并模式（单条翻译）
TIMEOUT_MERGE  = 120   # 合并模式（多条合并翻译）
TRANSLATE_POLL_INTERVAL = 200  # ms

OPENAI_FORMAT_API_KEY   = ""
OPENAI_FORMAT_BASE_URL   = "https://api.openai.com"
OPENAI_FORMAT_MODEL = "gpt-4o-mini"
OPENAI_DEFAULT_TEMPERATURE = 0.3

GLM_BASE_URL = "https://open.bigmodel.cn/api/paas"

GOOGLE_PROVIDER         = "Google"
AZURE_PROVIDER          = "Microsoft                     "
GLM_PROVIDER            = "GLM-4-Flash               ( Free AI  )"
SILICONFLOW_PROVIDER    = "SiliconFlow                 ( Free AI  )"
OPENAI_FORMAT_PROVIDER  = "Open AI Format         ( API Key )"
DEEPL_PROVIDER          = "DeepL                          ( API Key )"

AZURE_DEFAULT_KEY    = ""
AZURE_DEFAULT_REGION = ""
AZURE_DEFAULT_URL    = "https://api.cognitive.microsofttranslator.com"
AZURE_REGISTER_URL   = "https://azure.microsoft.com/" 
PROVIDER             = 0
DEEPL_DEFAULT_KEY    = ""
DEEPL_REGISTER_URL   = "https://www.deepl.com/account/summary"
CONTEXT_WINDOW = 1
PREFIX_PROMPT="""
You are a professional {target_lang} subtitle translation engine.
Task: Translate ONLY the sentence shown after the tag <<< Sentence >>> into {target_lang}.
---
"""
SYSTEM_PROMPT = """Strict rules you MUST follow:

1. Keep every proper noun, personal name, brand, product name, code snippet, file path, URL, and any other non-translatable element EXACTLY as it appears. Do NOT transliterate or translate these.

2. Follow subtitle style: short, concise, natural, and easy to read.

3. Output ONLY the translated sentence. No tags, no explanations, no extra spaces.
"""
SUFFIX_PROMPT="""
---
Note:
- The messages with role=assistant are only CONTEXT; do NOT translate them or include them in your output.
- Translate ONLY the line after <<< Sentence >>>
"""
DEFAULT_SETTINGS = {
    "AZURE_DEFAULT_KEY":"",
    "AZURE_DEFAULT_REGION":"",
    "DEEPL_DEFAULT_KEY":"",
    "PROVIDER":0,
    "OPENAI_FORMAT_BASE_URL": "",
    "OPENAI_FORMAT_API_KEY": "",
    "OPENAI_FORMAT_MODEL": 0,
    "OPENAI_FORMAT_TEMPERATURE":0.3,
    "SYSTEM_PROMPT":SYSTEM_PROMPT,
    "TARGET_LANG":0,
    "TARGET_LANG_CODE":"",
    "CN":False,
    "EN":True,
    "TRANSLATE_MODE": 1,
}
# ================= 智能合并翻译配置 =================
MAX_MERGE_CHUNKS = 5
SENTENCE_END_PUNCT = r'[.!?。！？；;，,]$'
LLM_STRUCTURED_PROVIDERS = {"OpenAI Format", "GLM", "SiliconFlow",
                            OPENAI_FORMAT_PROVIDER, GLM_PROVIDER, SILICONFLOW_PROVIDER}

SMART_MERGE_PREFIX_PROMPT = """You are a subtitle translation + segmentation engine.

INPUT:
A JSON object: {{"segments":[...]}}.
These segments are consecutive subtitle fragments in the SAME sentence/utterance.

GOAL:
1) Mentally join all segments into ONE complete sentence.
2) Translate the FULL meaning into natural {target_lang}.
3) Cut this SINGLE translated sentence into exactly {chunk_count} parts.

TRANSLATE RULES:
{translate_rules}

CRITICAL OUTPUT RULES:
- Output ONLY raw JSON. No Markdown.
- JSON schema: {{"translations":[string, ...], "ratios":[number, ...]}} with EXACTLY {chunk_count} items.
- The concatenation of all "translations" parts MUST equal the ONE fluent sentence.
- NO repetition across parts.
- NO extra content/interpretation (e.g. Do NOT add "We have no choice").

RATIO-ALIGNED SEGMENTATION (IMPORTANT):
A) Calculate input ratios based on segment length.
B) Split the translated sentence to match these ratios.
   - Example Input: ["我们不", "得不找个地方..."] (Short + Long)
   - Translation: "We have to find a place..."
   - CORRECT Split: ["We have to", "find a place..."] (Short + Long)
   - WRONG Split: ["We have to find a place...", "We have no choice"] (Hallucination)

SEGMENTATION RULES:
1) Each line must be a usable subtitle line (min 2 words for EN, 3 chars for CN).
2) NEVER output a line that is only punctuation or whitespace.
3) Attach orphaned function words (because, but, so) to the next line.
4) Punctuation must stick to a neighboring line.
5) Also output "ratios": [r1, r2, ...] where sum is 1.0.

Return JSON only:
{{"translations":[...], "ratios":[...]}}
"""

# ===========================================
import base64
import json
import logging
import os
import platform
import random
import re
import shutil
import string
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
from abc import ABC, abstractmethod
from fractions import Fraction
from typing import Any, Dict, Optional, Sequence, Tuple
from urllib.parse import quote_plus, urlencode
SCRIPT_PATH = os.path.dirname(os.path.abspath(sys.argv[0]))
TEMP_DIR         = os.path.join(SCRIPT_PATH, "temp")
RAND_CODE = "".join(random.choices(string.digits, k=2))
logger = logging.getLogger(__name__)

FPS_FALLBACK = Fraction(24, 1)
_FPS_STRING_ALIASES = {
    "23.976": Fraction(24000, 1001),
    "23.9760": Fraction(24000, 1001),
    "23.98": Fraction(24000, 1001),
    "23.980": Fraction(24000, 1001),
    "24000/1001": Fraction(24000, 1001),
    "29.97": Fraction(30000, 1001),
    "29.970": Fraction(30000, 1001),
    "30000/1001": Fraction(30000, 1001),
    "59.94": Fraction(60000, 1001),
    "59.940": Fraction(60000, 1001),
    "60000/1001": Fraction(60000, 1001),
    "47.952": Fraction(48000, 1001),
    "47.9520": Fraction(48000, 1001),
    "48000/1001": Fraction(48000, 1001),
    "119.88": Fraction(120000, 1001),
    "119.880": Fraction(120000, 1001),
    "120000/1001": Fraction(120000, 1001),
}
_FPS_FLOAT_ALIASES = {
    23.976: Fraction(24000, 1001),
    29.97: Fraction(30000, 1001),
    59.94: Fraction(60000, 1001),
    47.952: Fraction(48000, 1001),
    119.88: Fraction(120000, 1001),
}
_FPS_STD_FRACTIONS = tuple({
    Fraction(24, 1),
    Fraction(25, 1),
    Fraction(30, 1),
    Fraction(50, 1),
    Fraction(60, 1),
    *(_FPS_STRING_ALIASES.values()),
})

TRANSLATION_TREE_HEADERS = {
    "en": ["#", "Start", "End", "Source", "Target"],
    "cn": ["#", "开始", "结束", "原文", "译文"],
}

TRANSLATE_PROGRESS_LABELS = {
    "all": {"en": "Translating", "cn": "正在翻译"},
    "retry": {"en": "Retrying failed rows", "cn": "重试失败行"},
    "selected": {"en": "Translating selection", "cn": "翻译选中行"},
}

TRANSLATION_BUTTON_IDS = (
    "LoadSubsButton",
    "StartTranslateButton",
    "RetryFailedButton",
    "TranslateSelectedButton",
    "ApplyToTimelineButton",
)

TRANSLATE_SPEED_OPTIONS = [
    {"key": "slow", "labels": {"cn": "低速 (5)", "en": "Low (5)"}, "value": 5},
    {"key": "standard", "labels": {"cn": "标准 (20)", "en": "Standard (20)"}, "value": 20},
    {"key": "fast", "labels": {"cn": "高速 (100)", "en": "High (100)"}, "value": 100},
]

TRANSLATION_ROW_COLORS = {
    "failed": {"R": 0.90, "G": 0.25, "B": 0.25, "A": 0.35},
}

TRANSLATION_ROW_TRANSPARENT = {"R": 0.0, "G": 0.0, "B": 0.0, "A": 0.0}

TRANSLATE_EDITOR_PLACEHOLDER = {
    "en": "Edit translation here...",
    "cn": "在此修改译文...",
}

UPDATE_VERSION_LINE = {
    "version": {
        "cn": "发现新版本：{current} → {latest}\n请前往购买页面下载最新版本。",
        "en": "Update: {current} → {latest}\nDownload on your purchase page.",
    },
    "loading": {
        "cn": "正在加载 {count} 条字幕...",
        "en": "Loading {count} subtitles...",
    },
    "waiting": {
        "cn": "请稍等... {elapsed} 秒",
        "en": "Please wait... {elapsed}s",
    },
    "loaded": {
        "cn": "已从轨道 #{track} 加载 {count} 条字幕。",
        "en": "Loaded {count} subtitles from track #{track}.",
    },
}

def configure_logging() -> logging.Logger:
    """Configure and return the module logger.

    Args:
        None.

    Returns:
        logging.Logger: Logger configured for this module.

    Raises:
        None.

    Examples:
        >>> configure_logging().name == __name__
        True
    """
    if logger.handlers:
        return logger
    handler = logging.StreamHandler()
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(name)s - %(message)s")
    )
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


def _normalize_fraction(frac: Fraction) -> Fraction:
    for std_frac in _FPS_STD_FRACTIONS:
        if abs(float(frac) - float(std_frac)) < 1e-6:
            return std_frac
    return frac


def _fps_to_fraction(value, default=FPS_FALLBACK) -> Fraction:
    def _fail():
        if default is None:
            raise ValueError("Invalid fps value")
        return default

    if isinstance(value, Fraction):
        return _normalize_fraction(value) if value > 0 else _fail()
    if value is None:
        return _fail()
    if isinstance(value, int):
        if value <= 0:
            return _fail()
        return Fraction(value, 1)
    numeric = None
    if isinstance(value, float):
        numeric = float(value)
    else:
        s = str(value).strip()
        if not s:
            return _fail()
        alias = _FPS_STRING_ALIASES.get(s)
        if alias:
            return alias
        if "." in s:
            alias = _FPS_STRING_ALIASES.get(s.rstrip("0").rstrip("."))
            if alias:
                return alias
        if "/" in s:
            try:
                frac = Fraction(s)
                if frac > 0:
                    return _normalize_fraction(frac)
            except (ValueError, ZeroDivisionError):
                pass
        try:
            numeric = float(s)
        except ValueError:
            return _fail()
    if numeric is None:
        return _fail()
    for approx, frac in _FPS_FLOAT_ALIASES.items():
        if abs(numeric - approx) < 1e-3:
            return frac
    if numeric <= 0:
        return _fail()
    if abs(numeric - round(numeric)) < 1e-6:
        return Fraction(int(round(numeric)), 1)
    frac = Fraction.from_float(numeric).limit_denominator(1000000)
    return _normalize_fraction(frac) if frac > 0 else _fail()


def _get_timeline_fps(timeline, project=None) -> Fraction:
    candidates = []
    timeline_keys = (
        "timelineFrameRate",
        "timelinePlaybackFrameRate",
        "timelineProxyFrameRate",
        "timelineOutputFrameRate",
    )
    if timeline:
        for key in timeline_keys:
            try:
                candidates.append(timeline.GetSetting(key))
            except Exception:
                continue
    if project:
        for key in ("timelineFrameRate", "timelinePlaybackFrameRate"):
            try:
                candidates.append(project.GetSetting(key))
            except Exception:
                continue
    for candidate in candidates:
        try:
            return _fps_to_fraction(candidate, default=None)
        except Exception:
            continue
    return FPS_FALLBACK


def _fps_as_float(fps_value) -> float:
    return float(_fps_to_fraction(fps_value))


def _fps_timebase(fps_value) -> int:
    return max(1, int(round(_fps_as_float(fps_value))))

fusion     = resolve.Fusion()  
ui       = fusion.UIManager
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
                        "ID": "UpdateLabel",
                        "Text": "",
                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                        "WordWrap": True,
                        "Visible": False,
                        "StyleSheet": "color:#bbb; font-size:20px;",
                    }
                ),
                ui.Label(                          
                    {
                        "ID": "LoadLabel", 
                        "Text": "Loading...",
                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                    }
                ),
                ui.HGroup(
                    [
                        ui.Button(
                            {
                                "ID": "ConfirmButton",
                                "Text": "OK",
                                "Visible": False,
                                "Enabled": False,
                                "MinimumSize": [80, 28],
                            }
                        )
                    ],
                    {
                        "Weight": 0,
                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                    }
                ),
            ]
        )
    ]
)
_loading_items = {}
_loading_start_ts = 0.0
_loading_timer_stop = False
_loading_confirmation_pending = False
_loading_notice_text = ""
_loading_progress_message = ""
_loading_total_subtitles = None
_loading_stage = "update"  # "update" during version check, "load" when loading subtitles
_loading_progress_lock = threading.Lock()
_loading_thread_started = False


def _get_update_lang() -> str:
    """
    返回更新提示的语言，优先使用已保存的 UI 语言偏好。
    """
    try:
        settings_path = os.path.join(SCRIPT_PATH, "config", "translator_settings.json")
        with open(settings_path, "r", encoding="utf-8") as f:
            data = json.load(f) or {}
            if data.get("EN"):
                return "en"
            if data.get("CN"):
                return "cn"
    except Exception:
        pass
    return "en" if DEFAULT_SETTINGS.get("EN") else "cn"


def _compose_loading_text(elapsed=None):
    notice = _loading_notice_text.strip()
    with _loading_progress_lock:
        progress = (_loading_progress_message or "").strip()
        subtitle_total = _loading_total_subtitles
        stage = _loading_stage
    lang_key = _get_update_lang()

    if stage == "done":
        base_text = progress or notice or ""
        return base_text.strip()

    if stage == "update":
        tpl = UPDATE_VERSION_LINE.get("waiting", {})
        template = tpl.get(lang_key) or tpl.get("en", "")
        try:
            base_text = template.format(elapsed=int(elapsed) if elapsed is not None else 0)
        except Exception:
            base_text = template or "Please wait..."
    else:
        loading_tpl = UPDATE_VERSION_LINE.get("loading", {})
        template = ""
        if isinstance(loading_tpl, dict):
            template = loading_tpl.get(lang_key) or loading_tpl.get("en", "")
        count_display = subtitle_total if subtitle_total is not None else "..."
        try:
            if template:
                base_text = template.format(count=count_display)
            else:
                base_text = "Loading subtitles..." if lang_key == "en" else "正在加载字幕..."
        except Exception:
            base_text = template or ("Loading subtitles..." if lang_key == "en" else "正在加载字幕...")
    if progress:
        base_text = f"{base_text}\n{progress}"
    if notice:
        base_text = f"{notice}\n\n{base_text}"
    return base_text


def _set_loading_message(message, *, count=None):
    global _loading_progress_message, _loading_total_subtitles
    with _loading_progress_lock:
        _loading_progress_message = message or ""
        if count is not None:
            try:
                _loading_total_subtitles = max(0, int(count))
            except Exception:
                _loading_total_subtitles = count
    try:
        _loading_items["LoadLabel"].Text = _compose_loading_text()
    except Exception:
        pass


def _set_loading_stage(stage: str, *, count=None):
    """Switch loading window stage (update / load) and refresh UI."""
    global _loading_stage, _loading_start_ts, _loading_progress_message, _loading_total_subtitles
    _loading_stage = stage or "update"
    _loading_start_ts = time.time()
    if stage == "load":
        _loading_progress_message = ""
        _loading_total_subtitles = None
        try:
            _loading_items["UpdateLabel"].Visible = False
            _loading_items["LoadLabel"].Visible = True
        except Exception:
            pass
    elif stage == "done":
        _loading_total_subtitles = None
    _set_loading_message(_loading_progress_message, count=count)


def _format_loaded_message(count, track):
    tpl = UPDATE_VERSION_LINE.get("loaded", {})
    lang = _get_update_lang()
    en_tpl = tpl.get("en", "") if isinstance(tpl, dict) else ""
    cn_tpl = tpl.get("cn", "") if isinstance(tpl, dict) else ""
    en_msg = (en_tpl or "Loaded {count} subtitles from track #{track}.").format(
        count=count, track=track
    )
    cn_msg = (cn_tpl or "已从轨道 #{track} 加载 {count} 条字幕。").format(
        count=count, track=track
    )
    display = en_msg if lang == "en" else cn_msg
    return display, en_msg, cn_msg


def _on_loading_confirm(ev):
    global _loading_confirmation_pending
    if not _loading_confirmation_pending:
        return
    _loading_confirmation_pending = False
    try:
        _loading_items["ConfirmButton"].Enabled = False
        _loading_items["ConfirmButton"].Visible = False
        _loading_items["UpdateLabel"].Visible = False
        _loading_items["LoadLabel"].Visible = True
    except Exception:
        pass
    _set_loading_stage("load")
    dispatcher.ExitLoop()

def _loading_timer_worker():
    while not _loading_timer_stop:
        try:
            elapsed = int(time.time() - _loading_start_ts)
            _loading_items["LoadLabel"].Text = _compose_loading_text(elapsed)
        except Exception:
            pass
        time.sleep(1.0)


def initialize_application() -> None:
    """Initialize loading UI elements and background timers.

    Args:
        None.

    Returns:
        None.

    Raises:
        None.

    Examples:
        >>> initialize_application()
    """
    global _loading_items
    global _loading_start_ts
    global _loading_timer_stop
    global _loading_confirmation_pending
    global _loading_notice_text
    global _loading_progress_message
    global _loading_thread_started
    global _loading_total_subtitles

    configure_logging()

    if _loading_thread_started:
        _set_loading_stage("update")
        return

    loading_win.Show()
    _loading_items = loading_win.GetItems()
    _loading_start_ts = time.time()
    _loading_timer_stop = False
    _loading_confirmation_pending = False
    _loading_notice_text = ""
    _loading_progress_message = ""
    _loading_total_subtitles = 0
    _loading_stage = "update"
    loading_win.On.ConfirmButton.Clicked = _on_loading_confirm

    thread = threading.Thread(target=_loading_timer_worker, daemon=True)
    thread.start()
    _loading_thread_started = True
    _set_loading_stage("update")
    logger.info(
        "Loading window initialized",
        extra={"component": "loading_ui", "event": "initialized"},
    )


initialize_application()

# ---------- Resolve/Fusion 连接,外部环境使用（先保存起来） ----------
"""
try:
    import DaVinciResolveScript as dvr_script
    from python_get_resolve import GetResolve
    print("DaVinciResolveScript from Python")
except ImportError:
    # mac / windows 常规路径补全
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
"""
# ---------- 常用工具/封装（不改变外部行为） ----------
def connect_resolve():
    pm  = resolve.GetProjectManager()
    prj = pm.GetCurrentProject()
    mp  = prj.GetMediaPool()
    root= mp.GetRootFolder()
    tl  = prj.GetCurrentTimeline()
    fps_frac = _get_timeline_fps(tl, prj)
    return resolve, prj, mp, root, tl, fps_frac

def frames_to_srt_tc(frames, fps_frac):
    ms = round(frames * 1000 * fps_frac.denominator / fps_frac.numerator)
    if ms < 0: ms = 0
    h, rem = divmod(ms, 3600000)
    m, rem = divmod(rem, 60000)
    s, ms  = divmod(rem, 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"
try:
    import requests
    from deep_translator import GoogleTranslator
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
        from deep_translator import GoogleTranslator
        print(lib_dir)
    except ImportError as e:
        print("Dependency import failed—please make sure all dependencies are bundled into the Lib directory:", lib_dir, "\nError message:", e)


config_dir        = os.path.join(SCRIPT_PATH, "config")
settings_file     = os.path.join(config_dir, "translator_settings.json")
custom_models_file = os.path.join(config_dir, "models.json")
status_file = os.path.join(config_dir, 'status.json')
lang_code_map_file = os.path.join(config_dir, "lang_code_map.json")

def load_lang_code_maps(path: str) -> Dict[str, Any]:
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Language code map file missing: {path}")
    with open(path, "r", encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise ValueError("Language code map must be a JSON object.")
    required_keys = ("popular", "providers", "labels")
    missing = [key for key in required_keys if key not in data]
    if missing:
        raise ValueError(f"Language code map missing keys: {', '.join(missing)}")
    providers = data["providers"]
    labels = data["labels"]
    popular = data["popular"]
    if not isinstance(providers, dict):
        raise ValueError("Language code map 'providers' must be an object.")
    if not isinstance(labels, dict):
        raise ValueError("Language code map 'labels' must be an object.")
    if not isinstance(popular, dict):
        raise ValueError("Language code map 'popular' must be an object.")
    for key in ("azure", "google", "deepl"):
        values = providers.get(key)
        if not isinstance(values, list):
            raise ValueError(f"Language code map 'providers.{key}' must be a list.")
    for key in ("azure", "google", "deepl"):
        values = popular.get(key)
        if not isinstance(values, list):
            raise ValueError(f"Language code map 'popular.{key}' must be a list.")
    for lang_key in ("en", "cn"):
        lang_labels = labels.get(lang_key)
        if not isinstance(lang_labels, dict):
            raise ValueError(f"Language code map 'labels.{lang_key}' must be an object.")
        for key in ("azure", "google", "deepl"):
            values = lang_labels.get(key)
            if not isinstance(values, dict):
                raise ValueError(f"Language code map 'labels.{lang_key}.{key}' must be an object.")
    return data

LANG_CODE_MAPS = load_lang_code_maps(lang_code_map_file)
PROVIDER_LANG_MAP_KEYS = {
    AZURE_PROVIDER: "azure",
    GOOGLE_PROVIDER: "google",
    DEEPL_PROVIDER: "deepl",
    OPENAI_FORMAT_PROVIDER: "google",
    GLM_PROVIDER: "google",
    SILICONFLOW_PROVIDER: "google",
}
CODED_PROVIDERS = {AZURE_PROVIDER, GOOGLE_PROVIDER, DEEPL_PROVIDER}

# ================== Supabase 客户端 ==================
SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"


class SupabaseClient:
    def __init__(self, *, base_url: str, anon_key: str, default_timeout: int = 5):
        self.base_url = base_url.rstrip("/")
        self.anon_key = anon_key
        self.default_timeout = default_timeout

    @property
    def _functions_base(self) -> str:
        return f"{self.base_url}/functions/v1"

    def fetch_provider_secret(
        self,
        provider: str,
        *,
        user_id: str,
        timeout: Optional[int] = None,
        max_retry: int = 3,
    ) -> str:
        headers = {
            "Authorization": f"Bearer {self.anon_key}",
            "Content-Type": "application/json",
        }
        function_url = f"{self._functions_base}/getApiKey?provider={provider}"
        request_timeout = timeout or self.default_timeout

        for attempt in range(max_retry):
            try:
                resp = requests.get(function_url, headers=headers, timeout=request_timeout)
                if resp.status_code == 200:
                    api_key = resp.json().get("api_key")
                    if api_key:
                        return api_key
                    raise ValueError("API key not found in the response.")
                if resp.status_code == 429:
                    retry_after = resp.headers.get("Retry-After")
                    wait = float(retry_after) if retry_after else min(2 ** attempt, 30)
                    print(f"[{attempt+1}/{max_retry}] 429 rate limited, sleeping {wait}s")
                    time.sleep(wait)
                    continue
                if 500 <= resp.status_code < 600:
                    wait = min(2 ** attempt, 30)
                    print(f"[{attempt+1}/{max_retry}] server {resp.status_code}, sleeping {wait}s")
                    time.sleep(wait)
                    continue
                try:
                    err = resp.json()
                except Exception:
                    err = {"error": resp.text[:200]}
                raise RuntimeError(f"HTTP {resp.status_code}: {err}")

            except requests.exceptions.RequestException as e:
                jitter = random.random()
                wait = min(2 ** attempt + jitter, 30)
                print(f"[{attempt+1}/{max_retry}] network error: {e}; sleeping {wait:.2f}s")
                time.sleep(wait)

        raise RuntimeError("Failed to fetch API key after multiple attempts.")

    def check_update(
        self,
        plugin_id: str,
        *,
        timeout: Optional[int] = None,
    ) -> Optional[Dict[str, Any]]:
        if not plugin_id:
            raise ValueError("plugin_id is required")

        request_timeout = timeout or self.default_timeout
        function_url = f"{self._functions_base}/check_update?pid={quote_plus(plugin_id)}"
        headers = {
            "Authorization": f"Bearer {self.anon_key}",
            "Content-Type": "application/json",
        }

        try:
            resp = requests.get(function_url, headers=headers, timeout=request_timeout)
        except requests.exceptions.RequestException as exc:
            print(f"Failed to contact Supabase update endpoint: {exc}")
            return None

        if resp.status_code == 200:
            try:
                payload = resp.json()
            except ValueError as exc:
                print(f"Invalid update response: {exc}")
                return None
            if isinstance(payload, dict):
                return payload
            print(f"Unexpected update payload type: {type(payload)}")
            return None

        if resp.status_code in {400, 404}:
            return None

        print(f"Unexpected status from update endpoint: {resp.status_code} -> {resp.text[:200]}")
        return None


supabase_client = SupabaseClient(base_url=SUPABASE_URL, anon_key=SUPABASE_ANON_KEY)

class STATUS_MESSAGES:
    pass
with open(status_file, "r", encoding="utf-8") as file:
    status_data = json.load(file)
for key, (en, zh) in status_data.items():
    setattr(STATUS_MESSAGES, key, (en, zh))

def _check_for_updates():
    global _loading_confirmation_pending, _loading_notice_text
    _set_loading_stage("update")
    current_version = (SCRIPT_VERSION or "").strip()
    result = supabase_client.check_update(SCRIPT_NAME)
    if not result:
        return

    latest_version = (result.get("latest") or "").strip()
    if not latest_version or latest_version == current_version:
        return

    ui_lang = _get_update_lang()
    fallback_lang = "en" if ui_lang == "cn" else "cn"

    messages = []
    primary = (result.get(ui_lang) or "").strip()
    fallback = (result.get(fallback_lang) or "").strip()
    if primary:
        messages.append(primary)
    elif fallback:
        messages.append(fallback)

    readable_current = current_version or "未知"
    version_tpl = UPDATE_VERSION_LINE.get("version", {})
    template = version_tpl.get(ui_lang) or version_tpl.get("en", "")
    version_line = template.format(current=readable_current, latest=latest_version)
    messages.append(version_line)
    notice_text = "\n".join(messages).strip()

    try:
        _loading_items["UpdateLabel"].Text = notice_text
        _loading_items["UpdateLabel"].Visible = True
        _loading_items["LoadLabel"].Visible = False
        _loading_items["UpdateLabel"].StyleSheet = "color:#ff5555; font-size:20px;"
    except Exception:
        pass

    _loading_notice_text = ""
    try:
        _loading_items["ConfirmButton"].Visible = True
        _loading_items["ConfirmButton"].Enabled = True
    except Exception:
        pass

    print(f"[Update] Latest version {latest_version} available (current {readable_current}).")
    _loading_confirmation_pending = True
    try:
        dispatcher.RunLoop()
    finally:
        _loading_confirmation_pending = False


try:
    _check_for_updates()
except Exception as exc:
    print(f"Version check encountered an unexpected error: {exc}")


# =============== Provider 抽象层 ===============
class BaseProvider(ABC):
    name: str = "base"
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.initialized = False

    def initialize(self, text: str, target_lang: str):
        """Perform a test translation to ensure the provider works"""
        if not self.initialized:
            result = self.translate(text, target_lang)
            self.initialized = True
            return result
        return None
    @abstractmethod
    def translate(self, text: str, target_lang: str, *args, **kwargs) -> str: ...

def _compose_prompt_content(target_lang: str, ui_prompt_text: str = "") -> str:
    base_prompt = (ui_prompt_text or "").strip() or (SYSTEM_PROMPT or "").strip()
    parts = []
    pre = (PREFIX_PROMPT or "").strip()
    suf = (SUFFIX_PROMPT or "").strip()
    if pre:
        parts.append(pre)
    if base_prompt:
        parts.append(base_prompt)
    if suf:
        parts.append(suf)
    system_prompt = "\n".join(parts)
    lang = (target_lang or "").strip()
    system_prompt = system_prompt.replace("{target_lang}", lang).strip()
    return system_prompt
    
# -- Google -------------------------------
class GoogleProvider(BaseProvider):
    name = GOOGLE_PROVIDER

    def __init__(self, cfg):
        super().__init__(cfg)
        # deep_translator 不需要预先实例化 translator

    def translate(self, text, target_lang):
        """
        target_lang: deep_translator 接受的语言代码，例如 'zh-cn' 或 'en'
        """
        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                # 每次调用时根据目标语言新建一个 GoogleTranslator 实例
                translator = GoogleTranslator(source='auto', target=target_lang)
                return translator.translate(text)
            except Exception as e:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

def get_machine_id():
        import hashlib
        import subprocess
        import uuid
        system = platform.system()
        # 1. Linux: /etc/machine-id 或 /var/lib/dbus/machine-id
        if system == "Linux":
            for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
                if os.path.exists(path):
                    try:
                        return open(path, "r", encoding="utf-8").read().strip()
                    except Exception:
                        pass
        # 2. Windows: 注册表 MachineGuid
        elif system == "Windows":
            try:
                import winreg
                key = winreg.OpenKey(
                    winreg.HKEY_LOCAL_MACHINE,
                    r"SOFTWARE\Microsoft\Cryptography"
                )
                value, _ = winreg.QueryValueEx(key, "MachineGuid")
                return value
            except Exception:
                pass
        # 3. macOS: IOPlatformUUID
        elif system == "Darwin":
            try:
                output = subprocess.check_output(
                    ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                    stderr=subprocess.DEVNULL
                ).decode()
                import re
                m = re.search(r'"IOPlatformUUID" = "([^"]+)"', output)
                if m:
                    return m.group(1)
            except Exception:
                pass

        # 4. 回退：MAC 地址做 SHA256 哈希
        mac = uuid.getnode()
        # uuid.getnode() 不一定保证唯一（虚拟机可能一样），但一般可用
        return hashlib.sha256(str(mac).encode("utf-8")).hexdigest()
global USERID 
USERID = get_machine_id()
# -- Microsoft ----------------------------
class AzureProvider(BaseProvider):
    name = AZURE_PROVIDER
    _session = requests.Session()
    _key_cache = None
    _key_lock = threading.Lock()

    @classmethod
    def _ensure_key(cls):
        # 并发安全：仅首次向 Dify 拉取一次 Azure Key
        if cls._key_cache:
            return cls._key_cache
        with cls._key_lock:
            if not cls._key_cache:
                cls._key_cache = supabase_client.fetch_provider_secret("AZURE", user_id=USERID)
        return cls._key_cache

    def translate(self, text, target_lang):
        # -------- 1. 优先使用用户配置 --------
        user_key = (self.cfg.get("api_key") or "").strip()
        user_region = (self.cfg.get("region") or "").strip()

        if user_key and user_region:
            api_key = user_key
            region = user_region
        else:
            # -------- 2. 无用户完整配置时，使用 Dify 获取 Azure Key，region 固定 eastus --------
            api_key = self._ensure_key()
            region = "eastus"

        params = {"api-version": "3.0", "to": target_lang}
        headers = {
            "Ocp-Apim-Subscription-Key": api_key,
            "Ocp-Apim-Subscription-Region": region,
            "Content-Type": "application/json",
        }
        url = (self.cfg.get("base_url") or AZURE_DEFAULT_URL).rstrip("/") + "/translate"
        body = [{"text": text}]

        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, params=params, headers=headers,
                                       json=body, timeout=self.cfg.get("timeout", 15))
                r.raise_for_status()
                return r.json()[0]["translations"][0]["text"]
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)


# -- DeepL ------------------------                
class DeepLProvider(BaseProvider):
    name = DEEPL_PROVIDER
    _session = requests.Session()

    @staticmethod
    def _get_api_base(api_key: str) -> str:
        # DeepL free keys end with ":fx" and require the api-free host.
        if api_key.endswith(":fx"):
            return "https://api-free.deepl.com/v2"
        return "https://api.deepl.com/v2"

    def translate(self, text, target_lang):
        api_key = (self.cfg.get("api_key") or "").strip()
        if not api_key:
            raise ValueError("DeepL missing api key")
        base_url = (self.cfg.get("base_url") or "").strip() or self._get_api_base(api_key)
        url = base_url.rstrip("/") + "/translate"
        payload = {
            "auth_key": api_key,
            "text": text,
            "target_lang": target_lang,
        }

        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, data=payload, timeout=self.cfg.get("timeout", 15))
                r.raise_for_status()
                data = r.json()
                translations = data.get("translations") if isinstance(data, dict) else None
                if not translations:
                    raise ValueError(f"DeepL empty response: {data}")
                translated = translations[0].get("text")
                if not isinstance(translated, str):
                    raise ValueError("DeepL response missing translation text")
                return translated
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)
                
# -- AI Translator ------------------------
class OpenAIFormatProvider(BaseProvider):
    _session = requests.Session()
    name = OPENAI_FORMAT_PROVIDER

    def translate(self, text, target_lang, prefix: str = "", suffix: str = "", prompt_content: str = None):
        """
        返回: (翻译文本, usage dict)
        usage 包含 'prompt_tokens', 'completion_tokens', 'total_tokens'
        """
        prompt_content = prompt_content or _compose_prompt_content(target_lang)

        messages = [{"role": "system", "content": prompt_content}]
        # 上下文
        ctx = "\nCONTEXT (do not translate)\n".join(filter(None, [prefix, suffix]))
        if ctx:
            messages.append({"role": "assistant", "content": ctx})
        messages.append({"role": "user", "content": f"<<< Sentence >>>\n{text}"})
        
        payload = {
            "model":       self.cfg["model"],
            "messages":    messages,
            "temperature": self.cfg["temperature"],
        }
        headers = {
            "Authorization": f"Bearer {self.cfg['api_key']}",
            "Content-Type":  "application/json",
        }
        url = self.cfg["base_url"].rstrip("/") + "/v1/chat/completions"

        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload,
                                       timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                text_out = resp["choices"][0]["message"]["content"].strip()
                usage    = resp.get("usage", {})
                return text_out, usage
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

    def translate_batch(self, text: str, target_lang: str, prompt_content: str, response_format: dict = None):
        """批量翻译接口，支持结构化 JSON 输出。"""
        messages = [{"role": "system", "content": prompt_content}, {"role": "user", "content": text}]
        payload = {"model": self.cfg["model"], "messages": messages, "temperature": self.cfg["temperature"]}
        if response_format:
            payload["response_format"] = response_format
        headers = {"Authorization": f"Bearer {self.cfg['api_key']}", "Content-Type": "application/json"}
        url = self.cfg["base_url"].rstrip("/") + "/v1/chat/completions"
        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload, timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                return resp["choices"][0]["message"]["content"].strip(), resp.get("usage", {})
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

# -- GLM (via Dify secret) ------------------------
class GLMProvider(BaseProvider):
    _session = requests.Session()
    name = GLM_PROVIDER

    def __init__(self, cfg):
        super().__init__(cfg)
        # 缓存不同环境的密钥：{'zai': key, 'bigmodel': key}
        self._api_keys = {}
        self._key_lock = threading.Lock()

    def _is_en_checked(self) -> bool:
        # UI 可能尚未初始化，稳妥处理
        try:
            return bool(items["LangEnCheckBox"].Checked)
        except Exception:
            return False

    def _ensure_api_key(self):
        # 根据语言复选框选择不同的 Dify provider 名称
        use_en = self._is_en_checked()
        env_key = "zai" if use_en else "bigmodel"
        provider_name = "BIGMODEL" if use_en else "BIGMODEL"

        with self._key_lock:
            if env_key not in self._api_keys:
                self._api_keys[env_key] = supabase_client.fetch_provider_secret(provider_name, user_id=USERID)
            return self._api_keys[env_key]

    def translate(self, text, target_lang, prefix: str = "", suffix: str = "", prompt_content: str = None):
        prompt_content = prompt_content or _compose_prompt_content(target_lang)

        messages = [{"role": "system", "content": prompt_content}]
        ctx = "\nCONTEXT (do not translate)\n".join(filter(None, [prefix, suffix]))
        if ctx:
            messages.append({"role": "assistant", "content": ctx})
        messages.append({"role": "user", "content": f"<<< Sentence >>>\n{text}"})

        # 统一使用 4.5 flash 型号（z.ai 要求），仍然允许外部配置覆盖
        payload = {
            "model":       self.cfg.get("model", "glm-4-flash"),
            "messages":    messages,
            "temperature": self.cfg.get("temperature", OPENAI_DEFAULT_TEMPERATURE),
            "thinking":    {"type": "disabled"}  
        }
        api_key = self._ensure_api_key()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type":  "application/json",
        }

        use_en = self._is_en_checked()
        if use_en:
            #base = "https://api.z.ai/api/paas"
            #headers["Accept-Language"] = "en-US,en"
            base = "https://open.bigmodel.cn/api/paas"
        else:
            base = "https://open.bigmodel.cn/api/paas"
        base = base.rstrip("/")
        url = base + "/v4/chat/completions"

        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload,
                                       timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                text_out = resp["choices"][0]["message"]["content"].strip()
                usage    = resp.get("usage", {})
                return text_out, usage
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

    def translate_batch(self, text: str, target_lang: str, prompt_content: str, response_format: dict = None):
        """批量翻译接口，支持结构化 JSON 输出。"""
        messages = [{"role": "system", "content": prompt_content}, {"role": "user", "content": text}]
        payload = {"model": self.cfg.get("model", "glm-4-flash"), "messages": messages,
                   "temperature": self.cfg.get("temperature", OPENAI_DEFAULT_TEMPERATURE), "thinking": {"type": "disabled"}}
        if response_format:
            payload["response_format"] = response_format
        api_key = self._ensure_api_key()
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        url = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload, timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                return resp["choices"][0]["message"]["content"].strip(), resp.get("usage", {})
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

# -- SiliconFlow (via Supabase secret) ------------------------
class SiliconFlowProvider(BaseProvider):
    _session = requests.Session()
    name = SILICONFLOW_PROVIDER
    
    def __init__(self, cfg):
        super().__init__(cfg)
        self._api_key = None
        self._key_lock = threading.Lock()

    def _ensure_api_key(self):
        with self._key_lock:
            if not self._api_key:
                # 这里的 "SILICONFLOUW" 需与 Lua 处一致 (SILICONFLOUW_SUPABASE_PROVIDER)
                # 或与 Supabase 数据库里的 provider name 一致
                self._api_key = supabase_client.fetch_provider_secret("SILICONFLOUW", user_id=USERID)
            return self._api_key

    def translate(self, text, target_lang, prefix: str = "", suffix: str = "", prompt_content: str = None):
        prompt_content = prompt_content or _compose_prompt_content(target_lang)

        messages = [{"role": "system", "content": prompt_content}]
        ctx = "\nCONTEXT (do not translate)\n".join(filter(None, [prefix, suffix]))
        if ctx:
            messages.append({"role": "assistant", "content": ctx})
        messages.append({"role": "user", "content": f"<<< Sentence >>>\n{text}"})

        payload = {
            "model":       self.cfg.get("model", "THUDM/GLM-4-9B-0414"),
            "messages":    messages,
            "temperature": self.cfg.get("temperature", OPENAI_DEFAULT_TEMPERATURE),
            "stream":      False
        }
        
        api_key = self._ensure_api_key()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type":  "application/json",
        }
        
        url = self.cfg.get("base_url", "https://api.siliconflow.cn/v1/chat/completions")

        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload,
                                       timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                text_out = resp["choices"][0]["message"]["content"].strip()
                usage    = resp.get("usage", {})
                return text_out, usage
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

    def translate_batch(self, text: str, target_lang: str, prompt_content: str, response_format: dict = None):
        """批量翻译接口，支持结构化 JSON 输出。"""
        messages = [{"role": "system", "content": prompt_content}, {"role": "user", "content": text}]
        payload = {"model": self.cfg.get("model", "THUDM/GLM-4-9B-0414"), "messages": messages,
                   "temperature": self.cfg.get("temperature", OPENAI_DEFAULT_TEMPERATURE), "stream": False}
        if response_format:
            payload["response_format"] = response_format
        api_key = self._ensure_api_key()
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        url = self.cfg.get("base_url", "https://api.siliconflow.cn/v1/chat/completions")
        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                r = self._session.post(url, headers=headers, json=payload, timeout=self.cfg.get("timeout", 30))
                r.raise_for_status()
                resp = r.json()
                return resp["choices"][0]["message"]["content"].strip(), resp.get("usage", {})
            except Exception:
                if attempt == self.cfg.get("max_retry", 3):
                    raise
                time.sleep(2 ** attempt)

# =============== Provider 管理器 ===============
class ProviderManager:
    def __init__(self, cfg: dict):
        self._providers = {}
        self.default = cfg.get("default")
        for name, p_cfg in cfg["providers"].items():
            cls = globals()[p_cfg["class"]]      # 直接从当前模块拿类
            self._providers[name] = cls(p_cfg)
    def list(self):            # 返回支持的服务商列表
        return list(self._providers.keys())
    def get(self, name=None):  # 获取指定服务商实例
        return self._providers[name or self.default]
    
    def update_cfg(self, name: str, **new_cfg):
        if name not in self._providers:
            raise ValueError("Provider 不存在，无法更新配置")
        # 重建实例以应用最新配置
        cls = self._providers[name].__class__
        cfg = {**self._providers[name].cfg, **new_cfg}
        self._providers[name] = cls(cfg)

# --------- 3  服务商配置（可在 GUI 动态修改后写回） ---------
PROVIDERS_CFG = {
    "default": GOOGLE_PROVIDER,
    "providers": {
        GOOGLE_PROVIDER: {               # ← 新增
            "class": "GoogleProvider",
            "service_urls": [
                "translate.google.com",
                "translate.google.com.hk",
                "translate.google.com.tw"],  # 可多填备用域名
            "max_retry": MAX_RETRY,
            "timeout": TIMEOUT_SINGLE
        },
        AZURE_PROVIDER: {
            "class":  "AzureProvider",
            "base_url": AZURE_DEFAULT_URL,
            "api_key":  AZURE_DEFAULT_KEY,
            "region":   AZURE_DEFAULT_REGION,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT_SINGLE
        },
        GLM_PROVIDER: {

            "class": "GLMProvider",
            "base_url": GLM_BASE_URL,
            # 默认使用最新可用的 4.5 Flash 型号，兼容 z.ai 与 bigmodel 域名
            "model":    "glm-4-flash",
            "temperature": OPENAI_DEFAULT_TEMPERATURE,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT_SINGLE,
        },
        SILICONFLOW_PROVIDER: {
            "class": "SiliconFlowProvider",
            "base_url": "https://api.siliconflow.cn/v1/chat/completions",
            "model":    "THUDM/GLM-4-9B-0414",
            "temperature": OPENAI_DEFAULT_TEMPERATURE,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT_SINGLE,
        },
        OPENAI_FORMAT_PROVIDER: {
            "class": "OpenAIFormatProvider",
            "base_url": OPENAI_FORMAT_BASE_URL,
            "api_key":  OPENAI_FORMAT_API_KEY,
            "model":    OPENAI_FORMAT_MODEL,
            "temperature":OPENAI_DEFAULT_TEMPERATURE,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT_SINGLE
        },
        DEEPL_PROVIDER: {
            "class":   "DeepLProvider",
            "api_key": "",          
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT_SINGLE,
        },

    }
}

prov_manager = ProviderManager(PROVIDERS_CFG)   # 实例化

# -------------------- 4  GUI 搭建 --------------------
translator_win = dispatcher.AddWindow(
    {
        "ID": 'TranslatorWin',
        "WindowTitle": SCRIPT_NAME + SCRIPT_VERSION,
        "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],
        "Spacing": 10,
        "StyleSheet": "*{font-size:14px;}"
    },
    [
        ui.VGroup([
            ui.TabBar({"ID":"MyTabs","Weight":0.0}),
            ui.Stack({"ID":"MyStack","Weight":1.0},[
                # ===== 4.1 翻译页 =====
                ui.VGroup({"Weight":1},[
                    ui.VGap(6),
                    ui.HGroup(
                        {
                            "Weight": 0,
                            "Spacing": 8,
                        },
                        [
                            ui.Label(
                                {
                                    "ID": "ProviderLabel",
                                    "Text": "服务商",
                                    
                                    "Alignment": {"AlignVCenter": True},
                                    "Weight": 0,
                                }
                            ),
                            ui.ComboBox({"ID": "ProviderCombo", "Weight": 1}),
                            ui.Label(
                                {
                                    "ID": "TargetLangLabel",
                                    "Text": "翻译为",
                                 
                                    "Alignment": {"AlignVCenter": True},
                                    "Weight": 0,
                                }
                            ),
                            ui.ComboBox({"ID": "TargetLangCombo", "Weight": 1}),
                            ui.Label(
                                {
                                    "ID": "TranslateModeLabel",
                                    "Text": "模式",
                                   
                                    "Alignment": {"AlignVCenter": True},
                                    "Weight": 0,
                                }
                            ),
                            ui.ComboBox({"ID": "TranslateModeCombo", "Weight": 0}),
                            ui.CheckBox({"ID": "SmartMergeCheck", "Text": "语义增强", "Checked": False, "Weight": 0}),
                        ],
                    ),
                    ui.Tree(
                        {
                            "ID": "TranslateTree",
                            "AlternatingRowColors": True,
                            "WordWrap": True,
                            "UniformRowHeights": False,
                            "HorizontalScrollMode": True,
                            "FrameStyle": 1,
                            "ColumnCount": 5,
                            "SelectionMode": "SingleSelection",
                            "SortingEnabled": False,
                            "Weight": 1,
                        }
                    ),
                    ui.TextEdit(
                        {
                            "ID": "TranslateSubtitleEditor",
                            "Weight": 0,
                            "PlaceholderText": "在此修改译文...",
                            "WordWrap": True,
                        }
                    ),
                    ui.Label(
                        {
                            "ID": "TranslateStatusLabel",
                            "Text": "",
                            "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                            "WordWrap": True,
                            "Weight": 0,
                        }
                    ),
                    ui.HGroup(
                        {
                            "Weight": 0,
                            "Spacing": 8,
                        },
                        [
                            ui.Button({"ID": "LoadSubsButton", "Text": "加载时间线字幕", "Weight": 1}),
                            ui.Button({"ID": "StartTranslateButton", "Text": "开始翻译", "Weight": 1}),
                            ui.Button({"ID": "RetryFailedButton", "Text": "重试失败", "Weight": 1}),
                            ui.Button({"ID": "TranslateSelectedButton", "Text": "翻译选中", "Weight": 1}),
                            ui.Button({"ID": "ApplyToTimelineButton", "Text": "导入译文到时间线", "Weight": 1}),
                        ],
                    ),
                    ui.VGap(6),
                ]),
                # ===== 4.2 配置页 =====
                ui.VGroup({"Weight":1},[
                    ui.HGroup({"Weight": 0.1}, [
                        ui.Label({"ID":"MicrosoftConfigLabel","Text": "Microsoft", "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                        ui.Button({"ID": "ShowAzure", "Text": "配置","Weight": 0.1,}),
                    ]),
                    ui.HGroup({"Weight":0.1}, [
                        ui.Label({"ID":"DeepLConfigLabel","Text":"DeepL","Weight":0.1}),
                        ui.Button({"ID":"ShowDeepL","Text":"配置","Weight":0.1}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.Label({"ID":"OpenAIFormatConfigLabel","Text":"OpenAI Format","Weight":0.1}),
                        ui.Button({"ID":"ShowOpenAIFormat","Text":"配置","Weight":0.1}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.VGap(10),
                        ui.CheckBox({"ID":"LangEnCheckBox","Text":"EN","Checked":True,"Weight":0}),
                        ui.CheckBox({"ID":"LangCnCheckBox","Text":"简体中文","Checked":False,"Weight":0}),
                    ]),
                    #ui.TextEdit({"ID":"infoTxt","Text":"","ReadOnly":True,"Weight":1}),
                    #ui.Label({"ID":"CopyrightLabel","Text":f"© 2025, Copyright by {SCRIPT_AUTHOR}","Weight":0.1,"Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                    ui.Button({
                            "ID": "DonationButton", 
                            "Text": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
                            "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                            "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                            "Flat": True,
                            "TextColor": [0.1, 0.3, 0.9, 1],
                            "BackgroundColor": [1, 1, 1, 0],
                            "Weight": 1
                    })
                ])
            ])
        ])
    ]
)

# --- OpenAI 单独配置窗口（维持原有） ---
# openai配置窗口
openai_format_config_window = dispatcher.AddWindow(
    {
        "ID": "AITranslatorConfigWin",
        "WindowTitle": "AI Translator API",
        "Geometry": [750, 400, 350, 450],
        "Hidden": True,
        "StyleSheet": """
        * {
            font-size: 14px; /* 全局字体大小 */
        }
    """
    },
    [
        ui.VGroup(
            [
                ui.Label({"ID": "OpenAIFormatLabel","Text": "填写AI Translator 信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True},"Weight": 0.1}),
                ui.Label({"ID":"OpenAIFormatModelLabel","Text":"模型","Weight":0.1}),
                ui.HGroup({"Weight": 0.1}, [
                    ui.ComboBox({"ID":"OpenAIFormatModelCombo","Weight":0.2}),  
                    ui.LineEdit({"ID": "OpenAIFormatModelName", "ReadOnly":True, "Text": "","Weight": 0.1}),
                ]),
                ui.Label({"ID": "OpenAIFormatBaseURLLabel", "Text": "* Base URL","Weight": 0.1}),
                ui.LineEdit({"ID": "OpenAIFormatBaseURL",  "Text": "","PlaceholderText":OPENAI_FORMAT_BASE_URL,"Weight": 0.1}),
                ui.Label({"ID": "OpenAIFormatApiKeyLabel", "Text": "* API Key","Weight": 0.1}),
                ui.LineEdit({"ID": "OpenAIFormatApiKey", "Text": "",  "EchoMode": "Password","Weight": 0.1}),
                ui.HGroup({"Weight": 0.1}, [
                    ui.Label({"ID": "OpenAIFormatTemperatureLabel", "Text": "* Temperature"}),
                ui.DoubleSpinBox({"ID": "OpenAIFormatTemperatureSpinBox", "Value": 0.3, "Minimum": 0.0, "Maximum": 1.0, "SingleStep": 0.01, "Weight": 1})
                ]),
                ui.Label({"ID": "SystemPromptLabel", "Text": "* System Prompt","Weight": 0.1}),
                ui.TextEdit({"ID": "SystemPromptTxt", "Text": SYSTEM_PROMPT,"PlaceholderText": "", "Weight": 0.9, }),
                ui.HGroup({"Weight": 0.1}, [
                    ui.Button({"ID": "VerifyModel", "Text": "验证","Weight": 1}),
                    ui.Button({"ID": "ShowAddModel", "Text": "新增模型","Weight": 1}),
                    ui.Button({"ID": "DeleteModel", "Text": "删除模型","Weight": 1}),
                ]),
                #ui.Label({"ID": "VerifyStatus", "Text": "", "Alignment": {"AlignHCenter": True}}),
                
            ]
        )
    ]
)

# azure配置窗口
azure_config_window = dispatcher.AddWindow(
    {
        "ID": "AzureConfigWin",
        "WindowTitle": "Microsoft API",
        "Geometry": [750, 400, 300, 150],
        "Hidden": True,
        "StyleSheet": """
        * {
            font-size: 14px; /* 全局字体大小 */
        }
    """
    },
    [
        ui.VGroup(
            [
                ui.Label({"ID": "AzureLabel","Text": "Azure API", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "AzureRegionLabel", "Text": "区域", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "AzureRegion", "Text": "", "Weight": 0.8}),
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "AzureApiKeyLabel", "Text": "密钥", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "AzureApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
                    
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Button({"ID": "AzureConfirm", "Text": "确定","Weight": 1}),
                    ui.Button({"ID": "AzureRegisterButton", "Text": "注册","Weight": 1}),
                ]),
                
            ]
        )
    ]
)
deepL_config_window = dispatcher.AddWindow(
    {
        "ID": "DeepLConfigWin",
        "WindowTitle": "DeepL API",
        "Geometry": [780, 420, 300, 100],
        "Hidden": True,
        "StyleSheet": "*{font-size:14px;}"
    },
    [
        ui.VGroup([
            ui.Label({"ID":"DeepLLabel","Text":"DeepL API Key","Alignment":{"AlignHCenter":True}}),
            ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "DeepLApiKeyLabel", "Text": "密钥", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID":"DeepLApiKey","Text":"","EchoMode":"Password","Weight":0.8}),
                    
                ]),
            
            ui.HGroup([
                ui.Button({"ID":"DeepLConfirm","Text":"确定","Weight":1}),
                ui.Button({"ID":"DeepLRegister","Text":"注册","Weight":1}),
            ])
        ])
    ]
)
add_model_window = dispatcher.AddWindow(
    {
        "ID": "AddModelWin",
        "WindowTitle": "Add Model",
        "Geometry": [750, 400, 300, 200],
        "Hidden": True,
        "StyleSheet": "*{font-size:14px;}"
    },
    [
        ui.VGroup([
            ui.Label({"ID": "AddModelTitle", "Text": "添加 OpenAI 兼容模型", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
            ui.Label({"ID": "NewModelDisplayLabel", "Text": "Display name"}),
            ui.LineEdit({"ID": "addOpenAIFormatModelDisplay", "Text": ""}),
            ui.Label({"ID": "OpenAIFormatModelNameLabel", "Text": "* Model name"}),
            ui.LineEdit({"ID": "addOpenAIFormatModelName", "Text": ""}),
            ui.HGroup([
                ui.Button({"ID": "AddModelBtn", "Text": "Add Model"}),
            ])
        ])
    ]
)
msgbox = dispatcher.AddWindow(
        {
            "ID": 'msg',
            "WindowTitle": 'Warning',
            "Geometry": [750, 400, 350, 100],
            "Spacing": 10,
        },
        [
            ui.VGroup(
                [
                    ui.Label({"ID": 'WarningLabel', "Text": "",'Alignment': { 'AlignCenter' : True },'WordWrap': True}),
                    ui.HGroup(
                        {
                            "Weight": 0,
                        },
                        [
                            ui.Button({"ID": 'OkButton', "Text": 'OK'}),
                        ]
                    ),
                ]
            ),
        ]
    )

def show_warning_message(status_tuple):
    use_english = items["LangEnCheckBox"].Checked
    # 元组索引 0 为英文，1 为中文
    message = status_tuple[0] if use_english else status_tuple[1]
    msgbox.Show()
    msg_items["WarningLabel"].Text = message

def show_dynamic_message(en_text, zh_text):
    """直接弹窗显示任意中英文文本的动态消息"""
    use_en = items["LangEnCheckBox"].Checked
    msg = en_text if use_en else zh_text
    msgbox.Show()
    msg_items["WarningLabel"].Text = msg

def on_msg_close(ev):
    msgbox.Hide()
msgbox.On.OkButton.Clicked = on_msg_close
msgbox.On.msg.Close = on_msg_close

def show_donation_window(qr_base64: str, *,size=280):
    try:
        os.makedirs(TEMP_DIR, exist_ok=True)
    except Exception:
        print("[Donation] TEMP_DIR 不可用：", TEMP_DIR)
        return

    head, sep, body = qr_base64.partition(",")
    b64data = body if ("base64" in head.lower()) else qr_base64

    try:
        img_bytes = base64.b64decode(b64data, validate=False)
    except Exception as e:
        print("[Donation] Base64 解码失败：", e)
        return

    png_path = os.path.join(
        TEMP_DIR,
        f"donation_qr_{int(time.time())}_{uuid.uuid4().hex[:8]}.png",
    )
    try:
        with open(png_path, "wb") as f:
            f.write(img_bytes)
    except Exception as e:
        print("[Donation] 写入临时图片失败：", e)
        return

    win_w, win_h = size + 40, size + 40
    x = int((SCREEN_WIDTH  - win_w) / 2)
    y = int((SCREEN_HEIGHT - win_h) / 2)

    donation_win = dispatcher.AddWindow(
        {
            "ID": "DonationWin",
            "WindowTitle": "Donation",
            "Geometry": [x, y, win_w, win_h],
            "StyleSheet": "*{font-size:14px;}",
        },
        [
            ui.VGroup(
                {
                    "Weight": 1,
                    "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                },
                [
                    ui.Button(
                        {
                            "ID": "DonationImageButton",
                            "Icon": ui.Icon({"File": png_path}),
                            "IconSize": [size, size],
                            "MinimumSize": [size, size],
                            "StyleSheet": "border:0px dashed #444; border-radius:0px; background:transparent;",
                            "Flat": True,
                        }
                    )
                ],
            )
        ],
    )

    def _close(ev=None):
        try:
            donation_win.Hide()
        except Exception:
            pass
        try:
            os.remove(png_path)
        except Exception:
            pass
        try:
            os.rmdir(TEMP_DIR)
        except Exception:
            pass

    donation_win.On.DonationWin.Close = _close
    donation_win.On.DonationImageButton.Clicked = lambda ev: _close()

    donation_win.Show()

translations = {
    "cn": {
        "Tabs": ["翻译","设置"],
        "OpenAIFormatModelLabel":"选择模型：",
        "TargetLangLabel":"翻译为",
        "MicrosoftConfigLabel":"Microsoft",
        "ShowAzure":"配置",
        "OpenAIFormatConfigLabel":"Open AI 格式",
        "ShowOpenAIFormat": "配置",
        "ProviderLabel":"服务商",
        "DeepLConfigLabel":"DeepL",
        "ShowDeepL":"配置",
        "TranslateModeLabel": "模式",
        "SmartMergeCheck": "语义增强",
        "DeepLLabel":"DeepL API",
        "DeepLApiKeyLabel":"密钥",
        "DeepLConfirm":"确定",
        "DeepLRegister":"注册",
        "AzureRegionLabel":"区域",
        "AzureApiKeyLabel":"密钥",
        "AzureConfirm":"确定",
        "AzureRegisterButton":"注册",
        "AzureLabel":"填写 Azure API 信息",
        "OpenAIFormatLabel":"填写 OpenAI Format API 信息",
        "SystemPromptLabel":"* 系统提示词",
        "VerifyModel":"验证",
        "ShowAddModel":"新增模型",
        "DeleteModel":"删除模型",
        "AddModelTitle":"添加 OpenAI 兼容模型",
        "OpenAIFormatModelNameLabel":"* 模型",
        "NewModelDisplayLabel":"显示名称",
        "AddModelBtn":"添加",
        "DonationButton":  f"关注公众号：游艺所\n\n☕ 点击探索更多功能 ☕\n\n© 2025, Copyright by {SCRIPT_AUTHOR}.",
        "LoadSubsButton": "加载时间线字幕",
        "StartTranslateButton": "开始翻译",
        "RetryFailedButton": "重试失败",
        "TranslateSelectedButton": "翻译选中",
        "ApplyToTimelineButton": "导入译文到时间线",
    },

    "en": {
        "Tabs": ["Translate","Settings"],
        "OpenAIFormatModelLabel":"Select Model:",
        "TargetLangLabel":"To",
        "MicrosoftConfigLabel":"Microsoft",
        "ShowAzure":"Config",
        "OpenAIFormatConfigLabel":"Open AI Format",
        "ShowOpenAIFormat": "Config",
        "ProviderLabel":"Provider",
        "DeepLConfigLabel":"DeepL",
        "ShowDeepL":"Config",
        "TranslateModeLabel": "Mode",
        "SmartMergeCheck": "Semantic Boost",
        "DeepLLabel":"DeepL API",
        "DeepLApiKeyLabel":"Key",
        "DeepLConfirm":"OK",
        "DeepLRegister":"Register",
        "AzureRegionLabel":"Region",
        "AzureApiKeyLabel":"Key",
        "AzureConfirm":"OK",
        "AzureRegisterButton":"Register",
        "AzureLabel":"Azure API",
        "OpenAIFormatLabel":"OpenAI Format API",
        "SystemPromptLabel":"* System Prompt",
        "VerifyModel":"Verify",
        "ShowAddModel":"Add Model",
        "DeleteModel":"Delete Model",
        "AddModelTitle":"Add OpenAI Format Model",
        "OpenAIFormatModelNameLabel":"* Model name",
        "NewModelDisplayLabel":"Display name",
        "AddModelBtn":"Add",
        "DonationButton" :f"☕ Explore More Features ☕\n\n© 2025, Copyright by {SCRIPT_AUTHOR}.",
        "LoadSubsButton": "Load Timeline Subtitles",
        "StartTranslateButton": "Translate All",
        "RetryFailedButton": "Retry Failed",
        "TranslateSelectedButton": "Translate Selected",
        "ApplyToTimelineButton": "Apply To Timeline",
    }
}    

items       = translator_win.GetItems()
openai_items = openai_format_config_window.GetItems()
azure_items = azure_config_window.GetItems()
deepL_items = deepL_config_window.GetItems()
add_model_items = add_model_window.GetItems()
msg_items = msgbox.GetItems()
items["MyStack"].CurrentIndex = 0

# --- 4.3 初始化下拉内容 ---
for tab_name in translations["cn"]["Tabs"]:
    items["MyTabs"].AddTab(tab_name)


def _populate_target_languages(
    provider_name: str,
    *,
    preferred_code: Optional[str] = None,
    preferred_label: Optional[str] = None,
    preferred_index: Optional[int] = None,
) -> None:
    combo = items.get("TargetLangCombo")
    if not combo:
        return
    combo.Clear()
    codes = _build_ordered_target_codes(provider_name)
    label_map = _get_label_map(provider_name, _current_language_key())
    translation_state["target_codes"] = codes
    for code in codes:
        combo.AddItem(label_map[code])
    if not codes:
        return
    if preferred_code and preferred_code in codes:
        idx = codes.index(preferred_code)
    elif preferred_label and preferred_label in label_map.values():
        idx = list(label_map.values()).index(preferred_label)
    elif preferred_index is not None and 0 <= preferred_index < len(codes):
        idx = preferred_index
    else:
        idx = 0
    combo.CurrentIndex = idx



translation_state = {
    "rows": [],
    "project": None,
    "timeline": None,
    "fps_frac": FPS_FALLBACK,
    "start_frame": 0,
    "busy": False,
    "last_tokens": 0,
    "active_track_index": None,
    "last_target_code": None,
    "last_target_label": None,
    "last_provider": None,
    "selected_indices": [],
    "speed_key": "standard",
    "failed_rows": {},
    "target_codes": [],
}


_translate_editor_programmatic = False


def _current_language_key():
    try:
        return "en" if items["LangEnCheckBox"].Checked else "cn"
    except Exception:
        return "en"




def set_translate_status(en_text: str = "", zh_text: str = "") -> None:
    """Update the status label according to the current language.

    Args:
        en_text (str): Message rendered when界面处于英文.
        zh_text (str): Message rendered when界面处于中文.

    Returns:
        None.

    Raises:
        None.

    Examples:
        >>> set_translate_status("Loading", "加载中")
    """
    lang = _current_language_key()
    text = en_text if lang == "en" else zh_text
    widget = items.get("TranslateStatusLabel")
    if widget is not None:
        widget.Text = text or ""


def _translate_editor_placeholder_for_lang(lang=None):
    if lang is None:
        lang = _current_language_key()
    return TRANSLATE_EDITOR_PLACEHOLDER.get(lang, TRANSLATE_EDITOR_PLACEHOLDER["en"])


def _apply_translate_editor_placeholder(lang=None):
    editor = items.get("TranslateSubtitleEditor")
    if not editor:
        return
    placeholder = _translate_editor_placeholder_for_lang(lang)
    try:
        editor.PlaceholderText = placeholder
    except Exception:
        pass


def _set_translate_editor_text(text):
    editor = items.get("TranslateSubtitleEditor")
    if not editor:
        return
    global _translate_editor_programmatic
    _translate_editor_programmatic = True
    try:
        try:
            editor.Text = text or ""
        except Exception:
            try:
                editor.PlainText = text or ""
            except Exception:
                pass
    finally:
        _translate_editor_programmatic = False


def _format_tc(frame_value: int) -> str:
    fps_frac = translation_state.get("fps_frac") or FPS_FALLBACK
    start_frame = translation_state.get("start_frame") or 0
    relative = max(0, frame_value - start_frame)
    return frames_to_srt_tc(relative, fps_frac)


def _ensure_translation_tree_headers():
    tree = items.get("TranslateTree")
    if not tree:
        return
    headers = TRANSLATION_TREE_HEADERS.get(_current_language_key(), TRANSLATION_TREE_HEADERS["en"])
    try:
        tree.SetHeaderLabels(headers)
    except Exception:
        pass
    column_widths = [60, 80, 80, 280, 320]
    for idx, width in enumerate(column_widths):
        try:
            tree.ColumnWidth[idx] = width
        except Exception:
            continue


def _apply_translation_row_style(item, row_index):
    tree = items.get("TranslateTree")
    if not tree or not item:
        return
    failed_map = translation_state.get("failed_rows") or {}
    row_identifier = _get_row_identifier(row_index)
    color = TRANSLATION_ROW_COLORS.get("failed") if failed_map.get(row_identifier) else TRANSLATION_ROW_TRANSPARENT
    target_column = 4  # Target text column
    try:
        item.BackgroundColor[target_column] = color
    except Exception:
        try:
            item.BackgroundColor[target_column] = color
        except Exception:
            pass


def _get_translate_tree_item(row_index):
    tree = items.get("TranslateTree")
    if not tree:
        return None
    try:
        return tree.TopLevelItem(row_index)
    except Exception:
        return None


def _get_row_identifier(row_index):
    try:
        row = translation_state.get("rows", [])[row_index]
        value = row.get("idx") if isinstance(row, dict) else None
        if value is not None:
            return int(value)
    except Exception:
        pass
    return (row_index or 0) + 1


def mark_translation_failure(row_index, reason=None):
    failed_map = translation_state.setdefault("failed_rows", {})
    identifier = _get_row_identifier(row_index)
    failed_map[identifier] = reason or True
    failed_map[row_index + 1] = reason or True
    item = _get_translate_tree_item(row_index)
    if item:
        _apply_translation_row_style(item, row_index)


def clear_translation_failure(row_index):
    failed_map = translation_state.get("failed_rows")
    if failed_map:
        identifier = _get_row_identifier(row_index)
        removed = False
        if failed_map.pop(identifier, None) is not None:
            removed = True
        if failed_map.pop(row_index + 1, None) is not None:
            removed = True
        if removed:
            item = _get_translate_tree_item(row_index)
            if item:
                _apply_translation_row_style(item, row_index)


def refresh_translation_tree(select_index=None):
    tree = items.get("TranslateTree")
    if not tree:
        _set_translate_editor_text("")
        translation_state["selected_indices"] = []
        return
    rows = translation_state.get("rows") or []
    try:
        tree.SetUpdatesEnabled(False)
    except Exception:
        pass
    tree.Clear()
    _ensure_translation_tree_headers()
    for zero_index, row in enumerate(rows):
        item = tree.NewItem()
        item.Text[0] = str(row.get("idx", 0))
        item.Text[1] = _format_tc(row.get("start", 0))
        item.Text[2] = _format_tc(row.get("end", 0))
        item.Text[3] = (row.get("source") or "").replace("\n", " ")
        item.Text[4] = (row.get("target") or "").replace("\n", " ")
        _apply_translation_row_style(item, zero_index)
        tree.AddTopLevelItem(item)
    if select_index is not None and 0 <= select_index < len(rows):
        try:
            current = tree.TopLevelItem(select_index)
            if current:
                tree.SetCurrentItem(current)
                try:
                    current.Selected = True
                except Exception:
                    pass
                tree.ScrollToItem(current)
        except Exception:
            pass
        translation_state["selected_indices"] = [select_index]
    else:
        translation_state["selected_indices"] = []
    _update_editor_from_selection()
    try:
        tree.SetUpdatesEnabled(True)
    except Exception:
        pass


def update_translation_tree_row(index):
    tree = items.get("TranslateTree")
    if not tree:
        return
    row = None
    try:
        row = translation_state["rows"][index]
    except (KeyError, IndexError):
        return
    item = tree.TopLevelItem(index)
    if not item:
        return
    item.Text[4] = (row.get("target") or "").replace("\n", " ")
    _apply_translation_row_style(item, index)


def _selected_row_indices():
    tree = items.get("TranslateTree")
    if not tree:
        return []
    selected = []
    try:
        items_list = tree.SelectedItems() or []
    except Exception:
        items_list = []
    for itm in items_list:
        try:
            idx = int(itm.Text[0]) - 1
        except (AttributeError, TypeError, ValueError):
            continue
        rows = translation_state.get("rows") or []
        if 0 <= idx < len(rows):
            selected.append(idx)
    if not selected:
        try:
            current = tree.CurrentItem()
        except Exception:
            current = None
        if current:
            try:
                idx = int(current.Text[0]) - 1
            except (TypeError, ValueError):
                idx = None
            rows = translation_state.get("rows") or []
            if idx is not None and 0 <= idx < len(rows):
                selected.append(idx)
    return sorted(set(selected))


def _update_editor_from_selection():
    rows = translation_state.get("rows") or []
    indices = translation_state.get("selected_indices") or []
    if not indices:
        _set_translate_editor_text("")
        return
    idx = indices[-1]
    if 0 <= idx < len(rows):
        _set_translate_editor_text(rows[idx].get("target") or "")
    else:
        _set_translate_editor_text("")


def _current_speed_option():
    key = translation_state.get("speed_key") or "standard"
    for opt in TRANSLATE_SPEED_OPTIONS:
        if opt["key"] == key:
            return opt
    return TRANSLATE_SPEED_OPTIONS[1]


def _populate_translate_mode_combo(lang=None):
    combo = items.get("TranslateModeCombo")
    if not combo:
        return
    if lang is None:
        lang = _current_language_key()
    current_key = translation_state.get("speed_key") or "standard"
    selected_index = 0
    try:
        combo.SetUpdatesEnabled(False)
    except Exception:
        pass
    try:
        combo.Clear()
    except Exception:
        pass
    for idx, opt in enumerate(TRANSLATE_SPEED_OPTIONS):
        label = opt["labels"].get(lang, opt["labels"]["en"])
        try:
            combo.AddItem(label)
        except Exception:
            pass
        if opt["key"] == current_key:
            selected_index = idx
    try:
        combo.CurrentIndex = selected_index
    except Exception:
        pass
    try:
        combo.SetUpdatesEnabled(True)
    except Exception:
        pass


def _get_selected_speed_value():
    combo = items.get("TranslateModeCombo")
    idx = None
    if combo:
        try:
            idx = combo.CurrentIndex
        except Exception:
            idx = None
    if idx is None or idx < 0 or idx >= len(TRANSLATE_SPEED_OPTIONS):
        return _current_speed_option()["value"]
    translation_state["speed_key"] = TRANSLATE_SPEED_OPTIONS[idx]["key"]
    return TRANSLATE_SPEED_OPTIONS[idx]["value"]


def _get_lang_map_key(provider_name: str) -> str:
    try:
        return PROVIDER_LANG_MAP_KEYS[provider_name]
    except KeyError as exc:
        raise ValueError(f"Unsupported provider for language map: {provider_name}") from exc


def _get_provider_codes(provider_name: str) -> Sequence[str]:
    key = _get_lang_map_key(provider_name)
    try:
        return LANG_CODE_MAPS["providers"][key]
    except KeyError as exc:
        raise ValueError(f"Missing provider codes for: {key}") from exc


def _get_popular_codes(provider_name: str) -> Sequence[str]:
    key = _get_lang_map_key(provider_name)
    try:
        return LANG_CODE_MAPS["popular"][key]
    except KeyError as exc:
        raise ValueError(f"Missing popular codes for: {key}") from exc


def _get_label_map(provider_name: str, lang_key: str) -> Dict[str, str]:
    key = _get_lang_map_key(provider_name)
    try:
        return LANG_CODE_MAPS["labels"][lang_key][key]
    except KeyError as exc:
        raise ValueError(f"Missing labels for {lang_key}.{key}") from exc


def _build_ordered_target_codes(provider_name: str) -> Sequence[str]:
    provider_codes = _get_provider_codes(provider_name)
    popular_codes = _get_popular_codes(provider_name)
    ordered = []
    seen = set()
    for code in popular_codes:
        if code in provider_codes and code not in seen:
            ordered.append(code)
            seen.add(code)
    for code in provider_codes:
        if code not in seen:
            ordered.append(code)
            seen.add(code)
    return ordered


def _get_target_code_from_index(provider_name: str, index: int) -> str:
    codes = translation_state.get("target_codes") or _build_ordered_target_codes(provider_name)
    if not isinstance(index, int) or index < 0 or index >= len(codes):
        raise ValueError("Invalid target language selection index.")
    return codes[index]


def _map_target_code(provider_name, target_label):
    if provider_name in CODED_PROVIDERS:
        combo = items.get("TargetLangCombo")
        idx = None
        if combo:
            try:
                idx = combo.CurrentIndex
            except Exception:
                idx = None
        if idx is None:
            raise ValueError("Target language selection is unavailable.")
        return _get_target_code_from_index(provider_name, idx)
    if provider_name in PROVIDER_LANG_MAP_KEYS:
        return target_label
    raise ValueError(f"Unsupported provider for target code: {provider_name}")


def _current_target_code():
    provider_widget = items.get("ProviderCombo")
    target_widget = items.get("TargetLangCombo")
    provider_name = ""
    target_label = ""
    if provider_widget is not None:
        try:
            provider_name = provider_widget.CurrentText
        except Exception:
            provider_name = ""
    if target_widget is not None:
        try:
            target_label = target_widget.CurrentText
        except Exception:
            target_label = ""
    if translation_state.get("last_target_code"):
        return translation_state["last_target_code"]
    return _map_target_code(provider_name, target_label)


def refresh_translation_controls():
    busy = bool(translation_state.get("busy"))
    rows = translation_state.get("rows") or []
    has_rows = bool(rows)
    has_failed = any(row.get("status") == "failed" for row in rows)
    has_translated = any((row.get("target") or "").strip() for row in rows)
    for btn_id in TRANSLATION_BUTTON_IDS:
        widget = items.get(btn_id)
        if not widget:
            continue
        if btn_id == "LoadSubsButton":
            widget.Enabled = not busy
        elif btn_id == "RetryFailedButton":
            widget.Enabled = (not busy) and has_failed
        elif btn_id == "ApplyToTimelineButton":
            widget.Enabled = (not busy) and has_translated
        else:
            widget.Enabled = (not busy) and has_rows
    editor = items.get("TranslateSubtitleEditor")
    if editor:
        editor.Enabled = (not busy) and has_rows


refresh_translation_controls()
    
def check_or_create_file(file_path):
    if os.path.exists(file_path):
        pass
    else:
        try:
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, 'w') as file:
                json.dump({}, file)
        except IOError:
            raise Exception(f"Cannot create file: {file_path}")
        
def save_settings(settings, settings_file):
    with open(settings_file, 'w') as file:
        content = json.dumps(settings, indent=4)
        file.write(content)
        
def load_settings(settings_file):
    if os.path.exists(settings_file):
        with open(settings_file, 'r') as file:
            content = file.read()
            if content:
                try:
                    settings = json.loads(content)
                    return settings
                except json.JSONDecodeError as err:
                    print('Error decoding settings:', err)
                    return None
    return None



check_or_create_file(settings_file)
check_or_create_file(custom_models_file)
saved_settings = load_settings(settings_file) 
custom_models = load_settings(custom_models_file)    # {"models": {disp: {...}}}


for p in prov_manager.list():
    items["ProviderCombo"].AddItem(p)
def update_openai_format_model_combo():
    openai_items["OpenAIFormatModelCombo"].Clear()
                # 预装官方模型
    for disp ,info in custom_models.get("models", {}).items():
        openai_items["OpenAIFormatModelCombo"].AddItem(disp)


    # 加载用户自定义
    for disp ,info in custom_models.get("custom_models", {}).items():
        openai_items["OpenAIFormatModelCombo"].AddItem(disp)

update_openai_format_model_combo()

saved_provider_index = DEFAULT_SETTINGS["PROVIDER"]
saved_target_index = DEFAULT_SETTINGS["TARGET_LANG"]
saved_target_code = None
if saved_settings:
    saved_provider_index = saved_settings.get("PROVIDER", DEFAULT_SETTINGS["PROVIDER"])
    saved_target_index = saved_settings.get("TARGET_LANG", DEFAULT_SETTINGS["TARGET_LANG"])
    saved_target_code = saved_settings.get("TARGET_LANG_CODE")
try:
    items["ProviderCombo"].CurrentIndex = saved_provider_index
except Exception:
    pass
_populate_target_languages(
    items["ProviderCombo"].CurrentText,
    preferred_code=saved_target_code,
    preferred_index=saved_target_index,
)

def switch_language(lang):
    """
    根据 lang (可取 'cn' 或 'en') 切换所有控件的文本
    """
    if "MyTabs" in items:
        for index, new_name in enumerate(translations[lang]["Tabs"]):
            items["MyTabs"].SetTabText(index, new_name)

    for item_id, text_value in translations[lang].items():
        # 确保 items[item_id] 存在，否则会报 KeyError
        if item_id == "Tabs":
            continue
        if item_id in items:
            items[item_id].Text = text_value
        elif item_id in azure_items:    
            azure_items[item_id].Text = text_value
        elif item_id in openai_items:    
            openai_items[item_id].Text = text_value
        elif item_id in deepL_items:    
            deepL_items[item_id].Text = text_value
        elif item_id in add_model_items:    
            add_model_items[item_id].Text = text_value
        else:
            print(f"[Warning] No control with ID {item_id} exists in items, so the text cannot be set!")
    # 刷新 Tree 头与状态语言
    _populate_translate_mode_combo(lang)
    _ensure_translation_tree_headers()
    rows = translation_state.get("rows") or []
    for idx in range(len(rows)):
        update_translation_tree_row(idx)
    _apply_translate_editor_placeholder(lang)
    try:
        provider_name = items["ProviderCombo"].CurrentText
    except Exception:
        provider_name = ""
    current_code = None
    try:
        idx = items["TargetLangCombo"].CurrentIndex
    except Exception:
        idx = None
    codes = translation_state.get("target_codes") or []
    if idx is not None and 0 <= idx < len(codes):
        current_code = codes[idx]
    if provider_name:
        _populate_target_languages(provider_name, preferred_code=current_code)


def on_lang_checkbox_clicked(ev):
    is_en_checked = ev['sender'].ID == "LangEnCheckBox"
    items["LangCnCheckBox"].Checked = not is_en_checked
    items["LangEnCheckBox"].Checked = is_en_checked
    switch_language("en" if is_en_checked else "cn")

translator_win.On.LangCnCheckBox.Clicked = on_lang_checkbox_clicked
translator_win.On.LangEnCheckBox.Clicked = on_lang_checkbox_clicked


if saved_settings:
    items["LangCnCheckBox"].Checked = saved_settings.get("CN", DEFAULT_SETTINGS["CN"])
    items["LangEnCheckBox"].Checked = saved_settings.get("EN", DEFAULT_SETTINGS["EN"])
    azure_items["AzureApiKey"].Text = saved_settings.get("AZURE_DEFAULT_KEY", DEFAULT_SETTINGS["AZURE_DEFAULT_KEY"])
    azure_items["AzureRegion"].Text = saved_settings.get("AZURE_DEFAULT_REGION", DEFAULT_SETTINGS["AZURE_DEFAULT_REGION"])
    deepL_items["DeepLApiKey"].Text = saved_settings.get("DEEPL_DEFAULT_KEY",DEFAULT_SETTINGS["DEEPL_DEFAULT_KEY"])
    openai_items["OpenAIFormatModelCombo"].CurrentIndex = saved_settings.get("OPENAI_FORMAT_MODEL", DEFAULT_SETTINGS["OPENAI_FORMAT_MODEL"])
    openai_items["OpenAIFormatBaseURL"].Text = saved_settings.get("OPENAI_FORMAT_BASE_URL", DEFAULT_SETTINGS["OPENAI_FORMAT_BASE_URL"])
    openai_items["OpenAIFormatApiKey"].Text = saved_settings.get("OPENAI_FORMAT_API_KEY", DEFAULT_SETTINGS["OPENAI_FORMAT_API_KEY"])
    openai_items["OpenAIFormatTemperatureSpinBox"].Value = saved_settings.get("OPENAI_FORMAT_TEMPERATURE", DEFAULT_SETTINGS["OPENAI_FORMAT_TEMPERATURE"])
    openai_items["SystemPromptTxt"].Text = saved_settings.get("SYSTEM_PROMPT", DEFAULT_SETTINGS["SYSTEM_PROMPT"])
    mode_index = saved_settings.get("TRANSLATE_MODE", DEFAULT_SETTINGS.get("TRANSLATE_MODE", 1))
    if not isinstance(mode_index, int) or not (0 <= mode_index < len(TRANSLATE_SPEED_OPTIONS)):
        mode_index = DEFAULT_SETTINGS.get("TRANSLATE_MODE", 1)
    translation_state["speed_key"] = TRANSLATE_SPEED_OPTIONS[mode_index]["key"]
else:
    translation_state["speed_key"] = TRANSLATE_SPEED_OPTIONS[1]["key"]

_populate_translate_mode_combo()
try:
    items["TranslateModeCombo"].CurrentIndex = next(
        (idx for idx, opt in enumerate(TRANSLATE_SPEED_OPTIONS) if opt["key"] == translation_state.get("speed_key")),
        DEFAULT_SETTINGS.get("TRANSLATE_MODE", 1),
    )
except Exception:
    pass

if items["LangEnCheckBox"].Checked:
    switch_language("en")
else:
    switch_language("cn")

def close_and_save(settings_file):
    mode_combo = items["TranslateModeCombo"] if "TranslateModeCombo" in items else None
    try:
        mode_index = mode_combo.CurrentIndex if mode_combo is not None else DEFAULT_SETTINGS.get("TRANSLATE_MODE", 1)
    except Exception:
        mode_index = DEFAULT_SETTINGS.get("TRANSLATE_MODE", 1)
    settings = {

        "CN":items["LangCnCheckBox"].Checked,
        "EN":items["LangEnCheckBox"].Checked,
        "PROVIDER":items["ProviderCombo"].CurrentIndex,
        "AZURE_DEFAULT_KEY":azure_items["AzureApiKey"].Text,
        "AZURE_DEFAULT_REGION":azure_items["AzureRegion"].Text,
        "DEEPL_DEFAULT_KEY":deepL_items["DeepLApiKey"].Text,
        "OPENAI_FORMAT_MODEL": openai_items["OpenAIFormatModelCombo"].CurrentIndex,
        "OPENAI_FORMAT_BASE_URL": openai_items["OpenAIFormatBaseURL"].Text,
        "OPENAI_FORMAT_API_KEY": openai_items["OpenAIFormatApiKey"].Text,
        "OPENAI_FORMAT_TEMPERATURE": openai_items["OpenAIFormatTemperatureSpinBox"].Value,
        "TARGET_LANG":items["TargetLangCombo"].CurrentIndex,
        "TARGET_LANG_CODE":_get_target_code_from_index(
            items["ProviderCombo"].CurrentText,
            items["TargetLangCombo"].CurrentIndex,
        ),
        "SYSTEM_PROMPT":openai_items["SystemPromptTxt"].PlainText,
        "TRANSLATE_MODE": mode_index,

    }

    save_settings(settings, settings_file)
# --- 4.4 Tab 切换 ---
def on_my_tabs_current_changed(ev):
    items["MyStack"].CurrentIndex = ev["Index"]
translator_win.On.MyTabs.CurrentChanged = on_my_tabs_current_changed

# --- 4.5 打开 OpenAI 配置窗 ---
def on_show_openai_format(ev):
    openai_format_config_window.Show()
translator_win.On.ShowOpenAIFormat.Clicked = on_show_openai_format

def on_openai_close(ev):
    print("OpenAI Format API setup is complete.")
    openai_format_config_window.Hide()
openai_format_config_window.On.AITranslatorConfigWin.Close = on_openai_close


# --- 4.6 打开 Azure 配置窗 ---
def on_show_azure(ev):
    azure_config_window.Show()
translator_win.On.ShowAzure.Clicked = on_show_azure

def on_azure_close(ev):
    print("Azure API setup is complete.")
    azure_config_window.Hide()
azure_config_window.On.AzureConfirm.Clicked = on_azure_close
azure_config_window.On.AzureConfigWin.Close = on_azure_close

def on_azure_register_link_button_clicked(ev):
    webbrowser.open(AZURE_REGISTER_URL)   # 官网注册页
azure_config_window.On.AzureRegisterButton.Clicked = on_azure_register_link_button_clicked

def on_show_deepl(ev):
    deepL_config_window.Show()
translator_win.On.ShowDeepL.Clicked = on_show_deepl

def on_deepl_close(ev):
    # 关闭窗口 & 写入 ProviderManager
    prov_manager.update_cfg(
        DEEPL_PROVIDER,
        api_key = deepL_items["DeepLApiKey"].Text.strip()
    )
    deepL_config_window.Hide()
deepL_config_window.On.DeepLConfirm.Clicked = on_deepl_close
deepL_config_window.On.DeepLConfigWin.Close = on_deepl_close

def on_deepl_register(ev):
    webbrowser.open(DEEPL_REGISTER_URL )   # 官网注册页
deepL_config_window.On.DeepLRegister.Clicked = on_deepl_register


def on_open_link_button_clicked(ev):
    if items["LangEnCheckBox"].Checked :
        webbrowser.open(SCRIPT_KOFI_URL)
    else :
        webbrowser.open(SCRIPT_TAOBAO_URL)
translator_win.On.DonationButton.Clicked = on_open_link_button_clicked

# --- 新增模型弹窗 ---
def on_show_add_model(ev):

    add_model_items["addOpenAIFormatModelDisplay"].Text = ""
    add_model_items["addOpenAIFormatModelName"].Text    = ""
    openai_format_config_window.Hide()
    add_model_window.Show()
openai_format_config_window.On.ShowAddModel.Clicked = on_show_add_model


def verify_settings(base_url, api_key, model):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "hello"}],
        "temperature": 0
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    url = base_url.rstrip("/") + "/v1/chat/completions"

    try:
        r = requests.post(url, headers=headers, json=payload, timeout=10)
        code = r.status_code            # 直接获取响应码
        r.raise_for_status()            # 如果不是 2xx，会抛出 HTTPError
        return True, "", code           # 成功时返回 True 和状态码
    except requests.exceptions.HTTPError as e:
        # HTTPError 中包含 .response，可以再提取状态码
        return False, str(e), e.response.status_code
    except Exception as e:
        # 其他网络错误（超时、连接失败等）
        # e.response 可能为 None
        code = getattr(e, 'response', None)
        code = code.status_code if code else None
        return False, str(e), code

def on_verify_model(ev):
    base_url = openai_items["OpenAIFormatBaseURL"].Text.strip() or OPENAI_FORMAT_BASE_URL
    model    = openai_items["OpenAIFormatModelName"].PlaceholderText.strip()
    api_key  = openai_items["OpenAIFormatApiKey"].Text.strip()
    ok,msg,code = verify_settings(base_url, api_key, model)
    if ok :
        show_warning_message(STATUS_MESSAGES.verify_success)
    else :
        code_map = {
            400: STATUS_MESSAGES.bad_request,
            401: STATUS_MESSAGES.unauthorized,
            403: STATUS_MESSAGES.forbidden,
            404: STATUS_MESSAGES.not_found,
            429: STATUS_MESSAGES.too_many_requests,
            500: STATUS_MESSAGES.internal_server_error,
            502: STATUS_MESSAGES.bad_gateway,
            503: STATUS_MESSAGES.service_unavailable,
            504: STATUS_MESSAGES.gateway_timeout,
        }
        # 用 dict.get 拿到对应消息，找不到就用 verify_code 兜底
        show_warning_message(code_map.get(code, STATUS_MESSAGES.verify_code))
        print(msg)
openai_format_config_window.On.VerifyModel.Clicked = on_verify_model

def on_delete_model(ev):
    display = openai_items["OpenAIFormatModelCombo"].CurrentText.strip()
    custom_tbl = custom_models.setdefault("custom_models", {})
    if display in custom_tbl:
        del custom_tbl[display]
        update_openai_format_model_combo()
    else:
        show_warning_message(STATUS_MESSAGES.model_deleted_failed)
    save_settings(custom_models, custom_models_file)
openai_format_config_window.On.DeleteModel.Clicked = on_delete_model

def on_add_model(ev):
    # === 0 读取输入 ===
    model   = add_model_items["addOpenAIFormatModelName"].Text.strip()
    display = add_model_items["addOpenAIFormatModelDisplay"].Text.strip() or model

    if not model:
        show_warning_message(STATUS_MESSAGES.parameter_error)
        return

    # === 1 只操作 custom_models["custom_models"] ===
    custom_tbl = custom_models.setdefault("custom_models", {})

    # === 2 查找重复 model ===
    for old_disp, info in list(custom_tbl.items()):
        if info.get("model") == model:
            # 找到相同 model → 更新 display 名
            if old_disp != display:
                # 先搬移到新 key
                custom_tbl[display] = info
                # 再删除旧 key
                del custom_tbl[old_disp]
                # 更新下拉框：先移除旧项，再添加新项
                update_openai_format_model_combo()
            # 已处理完毕，直接保存返回
            save_settings(custom_models, custom_models_file)

            openai_format_config_window.Show()
            add_model_window.Hide()
            return

    # === 3 未找到重复 model → 新增条目 ===
    custom_tbl[display] = {"model": model}
    openai_items["OpenAIFormatModelCombo"].AddItem(display)

    # === 4 持久化并关闭窗口 ===
    save_settings(custom_models, custom_models_file)
    openai_format_config_window.Show()
    add_model_window.Hide()

add_model_window.On.AddModelBtn.Clicked = on_add_model

def on_openai_model_changed(ev):
    """
    当 OpenAIFormatModelCombo 选中项发生变化时，
    实时更新 NewModelName、NewBaseURL、NewApiKey 的显示内容。
    """
    # 1. 获取下拉框当前显示名
    disp = openai_items["OpenAIFormatModelCombo"].CurrentText

    # 2. 从 custom_models 中查询：优先查“自定义”表，否则查“预装”表
    entry = (
        custom_models.get("custom_models", {}).get(disp)
        or custom_models.get("models", {}).get(disp)
    )

    # 3. 如果找到了 dict，就更新对应字段；否则清空或回退
    if isinstance(entry, dict):
        openai_items["OpenAIFormatModelName"].PlaceholderText = entry.get("model", "")
    else:
        # 无配置时可清空，也可回退到默认
        openai_items["OpenAIFormatModelName"].PlaceholderText = ""

# 4. 绑定事件：ComboBox 的 CurrentIndexChanged
openai_format_config_window.On.OpenAIFormatModelCombo.CurrentIndexChanged = on_openai_model_changed
# =============== 5  Resolve 辅助函数 ===============

def get_subtitles(timeline):
    subs = []
    for tidx in range(1, timeline.GetTrackCount("subtitle")+1):
        if not timeline.GetIsTrackEnabled("subtitle", tidx):
            continue
        for item in timeline.GetItemListInTrack("subtitle", tidx):
            subs.append({"start":item.GetStart(),
                         "end":item.GetEnd(),
                         "text":item.GetName()})
    return subs

def frame_to_timecode(frame, fps):
    sec      = frame / fps
    h, rem   = divmod(sec, 3600)
    m, rem   = divmod(rem, 60)
    s, msec  = divmod(rem, 1)
    return f"{int(h):02}:{int(m):02}:{int(s):02},{int(msec*1000):03}"

def write_srt(subs, start_frame, fps_frac, timeline_name, lang_code, output_dir="."):
    """
    按 [时间线名称]_[语言code]_[月日时分]_[4位随机码]_[版本].srt 规则写文件：
      1. 安全化时间线名称和语言code
      2. 获取当前时间戳（月日时分）
      3. 扫描已有文件，计算新版本号
      4. 写入并返回路径
    """
    # 1. 安全化名称
    safe_name = re.sub(r'[\\\/:*?"<>|]', "_", timeline_name)
    safe_lang = re.sub(r'[\\\/:*?"<>|]', "_", lang_code)
    from datetime import datetime
    # 2. 获取当前时间戳（月日时分），格式化为 MMDDHHMM
    timestamp = datetime.now().strftime("%m%d%H%M")

    # 3. 创建目录（若不存在）
    os.makedirs(output_dir, exist_ok=True)

    # 4. 扫描已有版本：匹配形如
    #    safe_name_safe_lang_（任意8位数字）_RAND_CODE_版本.srt
    pattern = re.compile(
        rf"^{re.escape(safe_name)}_{re.escape(safe_lang)}_\d{{8}}_{re.escape(RAND_CODE)}_(\d+)\.srt$"
    )
    versions = []
    for fname in os.listdir(output_dir):
        m = pattern.match(fname)
        if m:
            versions.append(int(m.group(1)))
    version = max(versions) + 1 if versions else 1

    # 5. 构造文件名与路径
    filename = f"{safe_name}_{safe_lang}_{timestamp}_{RAND_CODE}_{version}.srt"
    path = os.path.join(output_dir, filename)

    # 6. 写入 SRT 内容
    subs = sorted(subs, key=lambda x: x["start"])
    with open(path, "w", encoding="utf-8") as f:
        for idx, s in enumerate(subs, 1):
            st = max(0, s["start"] - start_frame)
            ed = max(0, s["end"]   - start_frame)
            if ed <= st: ed = st + 1
            f.write(
                f"{idx}\n"
                f"{frames_to_srt_tc(st, fps_frac)} --> "
                f"{frames_to_srt_tc(ed, fps_frac)}\n"
                f"{s['text']}\n\n"
            )
    return path

def import_srt_to_first_empty(path):
    resolve, current_project, current_media_pool, current_root_folder, current_timeline, fps_frac = connect_resolve()
    if not current_timeline:
        return False

    states = {}
    for i in range(1, current_timeline.GetTrackCount("subtitle") + 1):
        states[i] = current_timeline.GetIsTrackEnabled("subtitle", i)
        if states[i]:
            current_timeline.SetTrackEnable("subtitle", i, False)

    target = next((i for i in range(1, current_timeline.GetTrackCount("subtitle")+1)
                   if not current_timeline.GetItemListInTrack("subtitle", i)), None)
    if target is None:
        current_timeline.AddTrack("subtitle")
        target = current_timeline.GetTrackCount("subtitle")
    current_timeline.SetTrackEnable("subtitle", target, True)

    # 放入 srt 文件夹
    srt_folder = next((f for f in current_root_folder.GetSubFolderList() if f.GetName()=="srt"), None)
    if srt_folder is None:
        srt_folder = current_media_pool.AddSubFolder(current_root_folder, "srt")
    current_media_pool.SetCurrentFolder(srt_folder)

    added = current_media_pool.ImportMedia([path])
    if added and isinstance(added, list):
        mpi = added[-1]
    else:
        name = os.path.basename(path)
        clips = [c for c in srt_folder.GetClipList() if c.GetName()==name]
        if not clips: return False
        mpi = clips[0]

    current_timeline.SetCurrentTimecode(current_timeline.GetStartTimecode())
    current_media_pool.AppendToTimeline([mpi])
    return True


# =============== 翻译 Tree 数据流 ===============
def _get_active_subtitle_track(timeline):
    get_current_track = getattr(timeline, "GetCurrentTrack", None)
    if callable(get_current_track):
        try:
            current = get_current_track("subtitle")
            if isinstance(current, int) and current > 0:
                return current
        except Exception:
            pass
    try:
        track_count = timeline.GetTrackCount("subtitle") or 0
    except Exception:
        track_count = 0
    for track_index in range(1, track_count + 1):
        try:
            items = timeline.GetItemListInTrack("subtitle", track_index) or []
        except Exception:
            items = []
        if items:
            enabled = True
            try:
                enabled = timeline.GetIsTrackEnabled("subtitle", track_index) != False
            except Exception:
                pass
            if enabled:
                return track_index
    return None


def load_timeline_subtitles(show_feedback=True, progress_callback=None):
    if translation_state.get("busy"):
        return False
    try:
        resolve_obj, project, media_pool, root, timeline, fps_frac = connect_resolve()
    except Exception as exc:
        logger.error(
            "Failed to connect Resolve",
            extra={"component": "translation", "error": str(exc)},
        )
        if show_feedback:
            show_warning_message(STATUS_MESSAGES.initialize_fault)
        return False

    if not timeline:
        if show_feedback:
            show_warning_message(STATUS_MESSAGES.nosub)
        translation_state.update(
            {
                "rows": [],
                "project": project,
                "timeline": None,
                "fps_frac": FPS_FALLBACK,
                "start_frame": 0,
                "last_tokens": 0,
            }
        )
        refresh_translation_tree()
        refresh_translation_controls()
        return False

    active_track = _get_active_subtitle_track(timeline)
    rows = []
    total_items = 0
    if active_track is not None:
        try:
            track_items = timeline.GetItemListInTrack("subtitle", active_track) or []
        except Exception:
            track_items = []
        total_items = len(track_items)
        if progress_callback:
            try:
                progress_callback(0, total_items)
            except Exception:
                pass
        for idx, item in enumerate(track_items, start=1):
            source_text = item.GetName() or ""
            try:
                start_frame = int(item.GetStart() or 0)
            except Exception:
                start_frame = 0
            try:
                end_frame = int(item.GetEnd() or start_frame)
            except Exception:
                end_frame = start_frame
            rows.append(
                {
                    "idx": idx,
                    "start": start_frame,
                    "end": end_frame,
                    "source": source_text,
                    "target": "",
                    "status": "pending",
                    "error": "",
                    "timeline_item": item,
                    "track_index": active_track,
                }
            )
            if progress_callback:
                try:
                    progress_callback(idx, total_items)
                except Exception:
                    pass

    translation_state.update(
        {
            "rows": rows,
            "project": project,
            "timeline": timeline,
            "fps_frac": fps_frac,
            "start_frame": timeline.GetStartFrame() or 0,
            "last_tokens": 0,
            "active_track_index": active_track,
            "failed_rows": {},
        }
    )
    refresh_translation_tree(select_index=0 if rows else None)
    refresh_translation_controls()

    if not rows:
        if show_feedback:
            show_warning_message(STATUS_MESSAGES.nosub)
        set_translate_status("Timeline subtitles not found.", "未找到时间线字幕。")
        return False

    track_display = active_track if active_track is not None else "-"
    message_en = f"Loaded {len(rows)} subtitle rows from track #{track_display}."
    message_zh = f"已从轨道 #{track_display} 加载 {len(rows)} 条字幕。"
    set_translate_status(message_en, message_zh)
    logger.info(
        "Timeline subtitles loaded",
        extra={
            "component": "translation",
            "rows": len(rows),
            "track": track_display,
        },
    )
    return True


def ensure_translation_rows() -> bool:
    """Ensure translation rows are available in memory.

    Args:
        None.

    Returns:
        bool: Whether subtitles rows are ready for后续翻译.

    Raises:
        None.

    Examples:
        >>> ensure_translation_rows()
        True
    """
    rows = translation_state.get("rows") or []
    if rows:
        return True
    return load_timeline_subtitles()


# =============== 智能合并翻译辅助函数 ===============

def _get_llm_response_format(provider_name: str, chunk_count: int) -> Optional[Dict[str, Any]]:
    """生成 JSON Schema 结构化输出格式。"""
    if provider_name not in LLM_STRUCTURED_PROVIDERS:
        return None
    schema = {
        "type": "object",
        "properties": {
            "translations": {
                "type": "array",
                "items": {"type": "string"},
                "minItems": chunk_count,
                "maxItems": chunk_count,
            },
            "ratios": {
                "type": "array",
                "items": {"type": "number"},
                "minItems": chunk_count,
                "maxItems": chunk_count,
            }
        },
        "required": ["translations", "ratios"],
        "additionalProperties": False,
    }
    return {
        "type": "json_schema",
        "json_schema": {"name": "subtitle_translations", "strict": True, "schema": schema},
    }


def _merge_subtitle_chunks(rows: list, row_indices: Sequence[int]) -> list:
    """将相邻连续字幕行合并为翻译组。"""
    groups = []
    current = {"row_indices": [], "sources": []}
    last_idx = None
    for idx in sorted(row_indices):
        row = rows[idx]
        source = row.get("source", "").strip()
        if current["row_indices"] and last_idx is not None and idx != last_idx + 1:
            current["chunk_count"] = len(current["row_indices"])
            groups.append(current)
            current = {"row_indices": [], "sources": []}
        current["row_indices"].append(idx)
        current["sources"].append(source)
        last_idx = idx
        if len(current["row_indices"]) >= MAX_MERGE_CHUNKS or re.search(SENTENCE_END_PUNCT, source):
            current["chunk_count"] = len(current["row_indices"])
            groups.append(current)
            current = {"row_indices": [], "sources": []}
            last_idx = None
    if current["row_indices"]:
        current["chunk_count"] = len(current["row_indices"])
        groups.append(current)
    return groups


def _parse_llm_json_response(response: str, chunk_count: int) -> list:
    """解析 LLM JSON 输出，依赖 Schema 约束保证数量。"""
    match = re.search(r'\{[\s\S]*"translations"[\s\S]*\}', response)
    if not match:
        raise ValueError(f"No valid JSON: {response[:200]}")
    data = json.loads(match.group())
    translations = data.get("translations", [])
    if len(translations) != chunk_count:
        logger.debug(f"Translation count mismatch: expected {chunk_count}, got {len(translations)}")
    return translations


def _build_tagged_text(sources: list) -> str:
    """构建带标签的文本供传统 API 翻译。格式：<s0>Text</s0><s1>Text</s1>"""
    tagged = []
    for i, text in enumerate(sources):
        tagged.append(f"<s{i}>{text}</s{i}>")
    return "".join(tagged)


def _parse_tagged_response(response: str, chunk_count: int) -> list:
    """解析带标签的翻译响应。"""
    translations = [""] * chunk_count
    # 匹配 <sN>content</sN>，允许标签内有空格
    pattern = re.compile(r"<\s*s(\d+)\s*>(.*?)<\s*/\s*s\1\s*>", re.DOTALL)
    matches = pattern.findall(response)
    
    found_indices = set()
    for idx_str, content in matches:
        try:
            idx = int(idx_str)
            if 0 <= idx < chunk_count:
                translations[idx] = content.strip()
                found_indices.add(idx)
        except ValueError:
            continue
            
    if len(found_indices) != chunk_count:
        logger.warning(f"[SmartMerge] Tag mismatch: expected {chunk_count}, got {len(found_indices)}")
        
    return translations


def _is_cjk_char(char: str) -> bool:
    """判断字符是否为CJK字符"""
    code = ord(char) if len(char) == 1 else 0
    return (0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF or
            0x3040 <= code <= 0x30FF or 0xAC00 <= code <= 0xD7AF)


def _is_cjk_text(text: str) -> bool:
    """判断文本是否以CJK为主"""
    if not text:
        return False
    cjk = sum(1 for c in text if _is_cjk_char(c))
    return cjk > len(text) * 0.3


def _split_translation_by_ratio(translation: str, sources: list, target_lang: str = "") -> list:
    """
    按原文比例智能拆分译文。
    核心策略：先找自然断点，再均匀分配，确保每段都有实际内容。
    """
    n = len(sources)
    if n == 0:
        return []
    if n == 1:
        return [translation.strip()]
    
    translation = translation.strip()
    if not translation:
        return [""] * n
    
    # 根据文本类型选择拆分单元
    if _is_cjk_text(translation):
        # CJK: 按字符拆分，但要避免拆分英文单词
        units = []
        i = 0
        while i < len(translation):
            if translation[i].isascii() and translation[i].isalpha():
                # 收集连续的英文字符作为一个单元
                j = i
                while j < len(translation) and translation[j].isascii() and (translation[j].isalpha() or translation[j] == "'"):
                    j += 1
                units.append(translation[i:j])
                i = j
            else:
                units.append(translation[i])
                i += 1
    else:
        # 西文: 按单词拆分
        units = translation.split()
    
    if not units:
        return [translation] + [""] * (n - 1)
    
    # 简单均匀分配：确保每段至少有1个单元
    total_units = len(units)
    base_count = max(1, total_units // n)
    
    result = []
    idx = 0
    for i in range(n):
        if i == n - 1:
            # 最后一段取全部剩余
            segment_units = units[idx:]
        else:
            # 分配基础数量，确保不超出
            count = base_count
            end_idx = min(idx + count, total_units)
            if end_idx <= idx:
                end_idx = idx + 1
            segment_units = units[idx:end_idx]
            idx = end_idx
        
        # 组合单元
        if _is_cjk_text(translation):
            segment = "".join(segment_units)
        else:
            segment = " ".join(segment_units)
        result.append(segment.strip())
    
    # 后处理：确保没有空段
    result = _redistribute_empty_segments(result, _is_cjk_text(translation))
    return result


def _redistribute_empty_segments(segments: list, is_cjk: bool) -> list:
    """重新分配，确保每段都有实际内容"""
    if len(segments) <= 1:
        return segments
    
    result = [s.strip() for s in segments]
    
    # 找到所有非空段
    non_empty_indices = [i for i, s in enumerate(result) if s and not _is_punct_only(s)]
    
    if not non_empty_indices:
        # 全是空或标点，合并所有内容到第一段
        combined = "".join(result) if is_cjk else " ".join(result)
        return [combined.strip()] + [""] * (len(result) - 1)
    
    # 从非空段借内容给空段
    for i, seg in enumerate(result):
        if not seg or _is_punct_only(seg):
            # 找最近的非空段借内容
            donor_idx = min(non_empty_indices, key=lambda x: abs(x - i))
            donor = result[donor_idx]
            
            # 拆分donor，分一部分给当前空段
            if is_cjk:
                chars = list(donor)
                if len(chars) > 1:
                    split_pt = max(1, len(chars) // 2)
                    if i < donor_idx:
                        result[i] = "".join(chars[:split_pt])
                        result[donor_idx] = "".join(chars[split_pt:])
                    else:
                        result[i] = "".join(chars[split_pt:])
                        result[donor_idx] = "".join(chars[:split_pt])
            else:
                words = donor.split()
                if len(words) > 1:
                    split_pt = max(1, len(words) // 2)
                    if i < donor_idx:
                        result[i] = " ".join(words[:split_pt])
                        result[donor_idx] = " ".join(words[split_pt:])
                    else:
                        result[i] = " ".join(words[split_pt:])
                        result[donor_idx] = " ".join(words[:split_pt])
    
    return result


def _is_punct_only(text: str) -> bool:
    """判断是否只有标点"""
    if not text:
        return True
    punct = set('.,;:!?，。；：！？、·…—""''\'\"()[]{}')
    return all(c in punct or c.isspace() for c in text)


class AsyncTranslationState:
    """异步翻译状态管理."""
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.active = False
        self.artifacts = []
        self.pending_count = 0
        self.completed_count = 0
        self.on_complete = None
        self.on_progress = None
        self.parser = None
        self.poll_timeout = 0
        self.max_retry = 0
        self.read_retry = 2
        self.timeout = None
        self.headers = []


async_translation_state = AsyncTranslationState()
_translate_polling_timer = None


def ensure_translate_timer():
    """确保翻译轮询 Timer 存在."""
    global _translate_polling_timer
    if _translate_polling_timer:
        return _translate_polling_timer
    _translate_polling_timer = ui.Timer({
        "ID": "TranslatePollingTimer",
        "Interval": TRANSLATE_POLL_INTERVAL,
        "SingleShot": True,
        "TimerType": "CoarseTimer",
    })
    return _translate_polling_timer


def start_polling_timer():
    """启动轮询 Timer."""
    timer = ensure_translate_timer()
    if timer:
        try:
            timer.Start()
        except Exception:
            pass


def stop_polling_timer():
    """停止轮询 Timer."""
    if _translate_polling_timer:
        try:
            _translate_polling_timer.Stop()
        except Exception:
            pass


def _get_timer_event_id(ev):
    for key in ("who", "ID", "id", "Name", "name", "TimerID", "TimerId"):
        try:
            if isinstance(ev, dict) and key in ev:
                value = ev.get(key)
            else:
                value = getattr(ev, key, None)
            if value:
                return value
        except Exception:
            continue
    if isinstance(ev, dict):
        sender = ev.get("sender")
    else:
        sender = getattr(ev, "sender", None)
    if sender is not None:
        for attr in ("ID", "Name"):
            try:
                value = getattr(sender, attr, None)
            except Exception:
                value = None
            if value:
                return value
    return None


def _ensure_temp_dir() -> bool:
    try:
        os.makedirs(TEMP_DIR, exist_ok=True)
        return True
    except Exception:
        return False


def _cleanup_artifacts(artifacts):
    for art in artifacts or []:
        for key in ("output", "payload"):
            path = art.get(key)
            if not path:
                continue
            try:
                os.remove(path)
            except Exception:
                pass


def _spawn_background_command(command_args) -> bool:
    try:
        kwargs = {
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
            "stdin": subprocess.DEVNULL,
            "close_fds": os.name != "nt",
        }
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kwargs["start_new_session"] = True
        subprocess.Popen(command_args, **kwargs)
        return True
    except Exception as exc:
        logger.error("Async command spawn failed", extra={"error": str(exc)})
        return False


def _build_parallel_curl_command(artifacts, headers, timeout, limit):
    parts = [
        "curl",
        "-sS",
        "--show-error",
        "--parallel",
        "--parallel-immediate",
        "--parallel-max",
        str(limit),
        "-m",
        str(timeout),
    ]
    for idx, art in enumerate(artifacts):
        method = art.get("method") or "POST"
        parts.extend(["-X", method])
        for header in headers or []:
            parts.extend(["-H", header])
        payload = art.get("payload")
        if payload:
            parts.extend(["--data-binary", f"@{payload}"])
        parts.extend(["-o", art["output"], art["url"]])
        if idx < len(artifacts) - 1:
            parts.append("--next")
    return parts


def _build_single_curl_command(artifact, headers, timeout):
    parts = [
        "curl",
        "-sS",
        "--show-error",
        "-m",
        str(timeout),
        "-X",
        artifact.get("method") or "POST",
    ]
    for header in headers or []:
        parts.extend(["-H", header])
    payload = artifact.get("payload")
    if payload:
        parts.extend(["--data-binary", f"@{payload}"])
    parts.extend(["-o", artifact["output"], artifact["url"]])
    return parts


def _launch_retry(artifact, headers, timeout) -> bool:
    if artifact.get("output"):
        try:
            os.remove(artifact["output"])
        except Exception:
            pass
    artifact["started_at"] = time.time()
    command = _build_single_curl_command(artifact, headers, timeout)
    return _spawn_background_command(command)


def launch_async_translation(tasks: list, options: dict):
    """启动后台异步翻译."""
    if async_translation_state.active:
        return False, "async_busy"
    if not tasks:
        return False, "no_entries"
    if not shutil.which("curl"):
        return False, "curl_missing"
    if not _ensure_temp_dir():
        return False, "temp_dir_failed"

    headers = options.get("headers") or []
    timeout = options.get("timeout") or TIMEOUT_SINGLE
    limit = max(1, min(options.get("parallel_limit") or len(tasks), len(tasks)))
    payload_prefix = options.get("payload_prefix") or "translate_payload"
    output_prefix = options.get("output_prefix") or "translate_output"
    parser = options.get("parser")
    if not callable(parser):
        return False, "parser_missing"

    artifacts = []
    for idx, task in enumerate(tasks, start=1):
        payload_text = task.get("payload")
        payload_path = None
        if payload_text is not None:
            payload_name = f"{payload_prefix}_{int(time.time())}_{uuid.uuid4().hex[:6]}_{idx}.json"
            payload_path = os.path.join(TEMP_DIR, payload_name)
            try:
                with open(payload_path, "w", encoding="utf-8") as payload_file:
                    payload_file.write(payload_text)
            except Exception as exc:
                _cleanup_artifacts(artifacts)
                return False, f"payload_write_failed: {exc}"

        output_name = f"{output_prefix}_{int(time.time())}_{uuid.uuid4().hex[:6]}_{idx}.json"
        output_path = os.path.join(TEMP_DIR, output_name)
        artifacts.append({
            "task": task.get("task") or {},
            "payload": payload_path,
            "output": output_path,
            "url": task.get("url"),
            "method": task.get("method") or "POST",
            "completed": False,
            "attempts": 0,
            "read_attempts": 0,
            "last_size": None,
            "started_at": time.time(),
        })

    command = _build_parallel_curl_command(artifacts, headers, timeout, limit)
    if not _spawn_background_command(command):
        _cleanup_artifacts(artifacts)
        return False, "parallel_execution_failed"

    s = async_translation_state
    s.active = True
    s.artifacts = artifacts
    s.pending_count = len(artifacts)
    s.completed_count = 0
    s.on_complete = options.get("on_complete")
    s.on_progress = options.get("on_progress")
    s.parser = parser
    s.poll_timeout = options.get("poll_timeout") or max(5, int(timeout) + 5)
    s.max_retry = int(options.get("max_retry") or 0)
    s.read_retry = int(options.get("read_retry") or 2)
    s.timeout = timeout
    s.headers = headers

    start_polling_timer()
    return True, None


def _read_output_file(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except Exception:
        return None, "read_failed"
    if not data:
        return "", None
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError:
        return None, "decode_failed"


def _finish_async_translation():
    s = async_translation_state
    on_complete = s.on_complete
    artifacts = s.artifacts
    stop_polling_timer()
    s.reset()
    _cleanup_artifacts(artifacts)
    if callable(on_complete):
        try:
            on_complete()
        except Exception:
            pass


def poll_translation_outputs():
    """轮询翻译输出文件."""
    s = async_translation_state
    if not s.active:
        return
    now = time.time()
    poll_timeout = float(s.poll_timeout or 0)

    def emit_progress(task, result):
        if not callable(s.on_progress):
            return
        try:
            s.on_progress(task, result)
        except Exception:
            pass

    def mark_timeout(art):
        art["completed"] = True
        s.completed_count += 1
        _cleanup_artifacts([art])
        emit_progress(art.get("task") or {}, {"success": False, "err": "timeout"})

    def handle_parse_result(art, translation, tokens, err_msg):
        if translation is not None:
            art["completed"] = True
            s.completed_count += 1
            _cleanup_artifacts([art])
            emit_progress(art.get("task") or {}, {"success": True, "translation": translation, "tokens": tokens or 0})
            return

        art["read_attempts"] = (art.get("read_attempts") or 0) + 1
        should_wait = err_msg in ("decode_failed", "invalid_response", "empty_response")
        if should_wait and art["read_attempts"] <= s.read_retry:
            return

        art["attempts"] = (art.get("attempts") or 0) + 1
        if s.max_retry > 0 and art["attempts"] < s.max_retry:
            art["read_attempts"] = 0
            art["last_size"] = None
            ok_retry = _launch_retry(art, s.headers, s.timeout)
            if not ok_retry:
                art["completed"] = True
                s.completed_count += 1
                _cleanup_artifacts([art])
                emit_progress(art.get("task") or {}, {"success": False, "err": "parallel_execution_failed"})
        else:
            art["completed"] = True
            s.completed_count += 1
            _cleanup_artifacts([art])
            emit_progress(art.get("task") or {}, {"success": False, "err": err_msg or "translation_failed"})

    for art in s.artifacts or []:
        if art.get("completed"):
            continue
        if poll_timeout > 0 and art.get("started_at") and (now - art["started_at"]) >= poll_timeout:
            mark_timeout(art)
            continue
        output_path = art.get("output")
        if not output_path or not os.path.isfile(output_path):
            continue
        size = os.path.getsize(output_path)
        if size > 0:
            if art.get("last_size") is not None and art["last_size"] == size:
                content, read_err = _read_output_file(output_path)
                if read_err:
                    handle_parse_result(art, None, 0, read_err)
                else:
                    translation, tokens, err_msg = s.parser(content or "", art.get("task") or {})
                    handle_parse_result(art, translation, tokens, err_msg)
            else:
                art["last_size"] = size
                art["read_attempts"] = 0
        else:
            content, read_err = _read_output_file(output_path)
            if read_err:
                handle_parse_result(art, None, 0, read_err)
            elif content:
                translation, tokens, err_msg = s.parser(content, art.get("task") or {})
                handle_parse_result(art, translation, tokens, err_msg)
            else:
                handle_parse_result(art, None, 0, "empty_response")

    if s.completed_count >= s.pending_count:
        _finish_async_translation()


def on_translate_timer_timeout(ev):
    """Timer 超时回调."""
    if not async_translation_state.active:
        stop_polling_timer()
        return True
    try:
        poll_translation_outputs()
    except Exception:
        pass
    if async_translation_state.active:
        start_polling_timer()
    return True


def _build_llm_messages_for_row(rows, row_index, prompt_content):
    messages = [{"role": "system", "content": prompt_content}]
    if CONTEXT_WINDOW > 0:
        start = max(0, row_index - CONTEXT_WINDOW)
        prefix = "\n".join(rows[i]["source"] for i in range(start, row_index))
        suffix = "\n".join(
            rows[i]["source"]
            for i in range(row_index + 1, min(len(rows), row_index + 1 + CONTEXT_WINDOW))
        )
        ctx = "\nCONTEXT (do not translate)\n".join(filter(None, [prefix, suffix]))
        if ctx:
            messages.append({"role": "assistant", "content": ctx})
    source_text = rows[row_index].get("source") or ""
    messages.append({"role": "user", "content": f"<<< Sentence >>>\n{source_text}"})
    return messages


def _build_llm_payload(provider_name, model, temperature, messages, response_format=None):
    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
    }
    if provider_name == GLM_PROVIDER:
        payload["thinking"] = {"type": "disabled"}
    if provider_name == SILICONFLOW_PROVIDER:
        payload["stream"] = False
    if response_format:
        payload["response_format"] = response_format
    return payload


def _get_provider_request_info(provider, target_code):
    provider_name = getattr(provider, "name", "")
    timeout = provider.cfg.get("timeout", TIMEOUT_SINGLE)
    max_retry = provider.cfg.get("max_retry", MAX_RETRY)
    if provider_name in LLM_STRUCTURED_PROVIDERS:
        api_key = ""
        if provider_name == OPENAI_FORMAT_PROVIDER:
            api_key = (provider.cfg.get("api_key") or "").strip()
            base_url = provider.cfg.get("base_url") or OPENAI_FORMAT_BASE_URL
            url = base_url.rstrip("/") + "/v1/chat/completions"
        elif provider_name == GLM_PROVIDER:
            api_key = provider._ensure_api_key()
            base_url = provider.cfg.get("base_url") or GLM_BASE_URL
            url = base_url.rstrip("/") + "/v4/chat/completions"
        else:
            api_key = provider._ensure_api_key()
            base_url = provider.cfg.get("base_url") or "https://api.siliconflow.cn/v1/chat/completions"
            url = base_url.rstrip("/")
        headers = [
            f"Authorization: Bearer {api_key}",
            "Content-Type: application/json",
        ]
        return {
            "provider_name": provider_name,
            "headers": headers,
            "url": url,
            "timeout": timeout,
            "model": provider.cfg.get("model"),
            "temperature": provider.cfg.get("temperature", OPENAI_DEFAULT_TEMPERATURE),
            "max_retry": max_retry,
        }
    if provider_name == AZURE_PROVIDER:
        user_key = (provider.cfg.get("api_key") or "").strip()
        user_region = (provider.cfg.get("region") or "").strip()
        if user_key and user_region:
            api_key = user_key
            region = user_region
        else:
            api_key = provider._ensure_key()
            region = "eastus"
        params = {"api-version": "3.0", "to": target_code}
        base_url = provider.cfg.get("base_url") or AZURE_DEFAULT_URL
        url = base_url.rstrip("/") + "/translate?" + urlencode(params)
        headers = [
            f"Ocp-Apim-Subscription-Key: {api_key}",
            "Content-Type: application/json",
        ]
        if region:
            headers.append(f"Ocp-Apim-Subscription-Region: {region}")
        return {
            "provider_name": provider_name,
            "headers": headers,
            "url": url,
            "timeout": timeout,
            "max_retry": max_retry,
        }
    if provider_name == DEEPL_PROVIDER:
        api_key = (provider.cfg.get("api_key") or "").strip()
        if not api_key:
            raise ValueError("DeepL missing api key")
        base_url = provider.cfg.get("base_url") or provider._get_api_base(api_key)
        url = base_url.rstrip("/") + "/translate"
        headers = ["Content-Type: application/x-www-form-urlencoded"]
        return {
            "provider_name": provider_name,
            "headers": headers,
            "url": url,
            "timeout": timeout,
            "api_key": api_key,
            "max_retry": max_retry,
        }
    if provider_name == GOOGLE_PROVIDER:
        service_urls = provider.cfg.get("service_urls") or []
        host = service_urls[0] if service_urls else "translate.googleapis.com"
        base_url = f"https://{host}/translate_a/single"
        return {
            "provider_name": provider_name,
            "headers": [],
            "base_url": base_url,
            "timeout": timeout,
            "max_retry": max_retry,
        }
    raise ValueError(f"Unsupported provider for async translation: {provider_name}")


def _parse_openai_style_response(content):
    try:
        data = json.loads(content)
    except Exception:
        return None, 0, "decode_failed"
    if isinstance(data, dict) and data.get("error"):
        err = data["error"]
        message = err.get("message") if isinstance(err, dict) else None
        return None, 0, message or "invalid_response"
    choices = data.get("choices") if isinstance(data, dict) else None
    if not isinstance(choices, list) or not choices:
        return None, 0, "invalid_response"
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    text = message.get("content") if isinstance(message, dict) else None
    if not isinstance(text, str):
        return None, 0, "invalid_response"
    usage = data.get("usage") if isinstance(data, dict) else {}
    tokens = usage.get("total_tokens", 0) if isinstance(usage, dict) else 0
    return text.strip(), tokens, None


def _parse_azure_response(content):
    try:
        data = json.loads(content)
    except Exception:
        return None, 0, "decode_failed"
    if isinstance(data, dict) and data.get("error"):
        err = data["error"]
        message = err.get("message") if isinstance(err, dict) else None
        return None, 0, message or "invalid_response"
    if not isinstance(data, list) or not data:
        return None, 0, "invalid_response"
    translations = data[0].get("translations") if isinstance(data[0], dict) else None
    if not translations:
        return None, 0, "invalid_response"
    text = translations[0].get("text") if isinstance(translations[0], dict) else None
    if not isinstance(text, str):
        return None, 0, "invalid_response"
    return text, 0, None


def _parse_deepl_response(content):
    try:
        data = json.loads(content)
    except Exception:
        return None, 0, "decode_failed"
    if isinstance(data, dict) and data.get("message"):
        return None, 0, data.get("message") or "invalid_response"
    if isinstance(data, dict) and data.get("error"):
        err = data["error"]
        message = err.get("message") if isinstance(err, dict) else None
        return None, 0, message or "invalid_response"
    translations = data.get("translations") if isinstance(data, dict) else None
    if not translations:
        return None, 0, "invalid_response"
    text = translations[0].get("text") if isinstance(translations[0], dict) else None
    if not isinstance(text, str):
        return None, 0, "invalid_response"
    return text, 0, None


def _parse_google_response(content):
    try:
        data = json.loads(content)
    except Exception:
        return None, 0, "decode_failed"
    if isinstance(data, dict) and data.get("sentences"):
        sentences = data.get("sentences") or []
        translated = "".join(
            sentence.get("trans") for sentence in sentences
            if isinstance(sentence, dict) and isinstance(sentence.get("trans"), str)
        )
        return translated, 0, None
    if not isinstance(data, list) or not data:
        return None, 0, "invalid_response"
    chunks = data[0]
    if not isinstance(chunks, list):
        return None, 0, "invalid_response"
    translated = "".join(
        chunk[0] for chunk in chunks
        if isinstance(chunk, list) and chunk and isinstance(chunk[0], str)
    )
    return translated, 0, None


def _parse_async_response(content, task):
    provider_name = task.get("provider")
    smart_merge = bool(task.get("smart_merge"))
    target_code = task.get("target_code") or ""
    sources = task.get("sources") or []

    if provider_name in LLM_STRUCTURED_PROVIDERS:
        text, tokens, err = _parse_openai_style_response(content)
        if err:
            return None, tokens, err
        if smart_merge:
            chunk_count = int(task.get("chunk_count") or 1)
            try:
                translations = _parse_llm_json_response(text, chunk_count)
            except Exception:
                return None, tokens, "invalid_response"
            return translations, tokens, None
        return text, tokens, None

    if provider_name == AZURE_PROVIDER:
        text, tokens, err = _parse_azure_response(content)
    elif provider_name == DEEPL_PROVIDER:
        text, tokens, err = _parse_deepl_response(content)
    else:
        text, tokens, err = _parse_google_response(content)

    if err:
        return None, tokens, err
    if smart_merge:
        if not sources:
            return None, tokens, "invalid_task"
        translations = _split_translation_by_ratio(text, sources, target_code)
        return translations, tokens, None
    return text, tokens, None


def _translate_rows(
    row_indices: Sequence[int],
    provider: "BaseProvider",
    target_code: str,
    prompt_content: str,
    progress_key: str,
    use_smart_merge: bool = False,
) -> bool:
    """启动异步翻译任务并返回是否成功启动."""
    rows = translation_state.get("rows") or []
    if not row_indices:
        return False

    labels = TRANSLATE_PROGRESS_LABELS.get(progress_key, TRANSLATE_PROGRESS_LABELS["all"])
    provider_name = getattr(provider, "name", "")
    total_rows = len(row_indices)

    try:
        request_info = _get_provider_request_info(provider, target_code)
    except Exception as exc:
        for idx in row_indices:
            rows[idx]["status"] = "failed"
            rows[idx]["error"] = str(exc)
            mark_translation_failure(idx, rows[idx].get("error"))
            update_translation_tree_row(idx)
        set_translate_status("Translation failed.", "翻译失败。")
        return False

    tasks = []
    pre_failed = 0

    if use_smart_merge:
        groups = _merge_subtitle_chunks(rows, row_indices)
        for group in groups:
            for idx in group["row_indices"]:
                rows[idx]["status"] = "translating"
                rows[idx]["error"] = ""
                update_translation_tree_row(idx)
            sources = group["sources"]
            meta = {
                "row_indices": group["row_indices"],
                "chunk_count": group["chunk_count"],
                "sources": sources,
                "provider": provider_name,
                "smart_merge": True,
                "target_code": target_code,
                "process_count": len(group["row_indices"]),
            }
            try:
                if provider_name in LLM_STRUCTURED_PROVIDERS:
                    translate_rules = prompt_content.strip() if prompt_content else SYSTEM_PROMPT
                    smart_prompt = SMART_MERGE_PREFIX_PROMPT.format(
                        target_lang=target_code,
                        chunk_count=group["chunk_count"],
                        translate_rules=translate_rules,
                    )
                    user_content = json.dumps({"segments": sources}, ensure_ascii=False)
                    response_format = _get_llm_response_format(provider_name, group["chunk_count"])
                    messages = [
                        {"role": "system", "content": smart_prompt},
                        {"role": "user", "content": user_content},
                    ]
                    payload = _build_llm_payload(
                        provider_name,
                        request_info.get("model"),
                        request_info.get("temperature", OPENAI_DEFAULT_TEMPERATURE),
                        messages,
                        response_format,
                    )
                    payload_text = json.dumps(payload, ensure_ascii=False)
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                elif provider_name == AZURE_PROVIDER:
                    merged_source = "".join(sources)
                    payload_text = json.dumps([{"text": merged_source}], ensure_ascii=False)
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                elif provider_name == DEEPL_PROVIDER:
                    merged_source = "".join(sources)
                    payload_text = urlencode(
                        {"auth_key": request_info["api_key"], "text": merged_source, "target_lang": target_code}
                    )
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                else:
                    merged_source = "".join(sources)
                    params = {
                        "client": "gtx",
                        "sl": "auto",
                        "tl": target_code,
                        "dt": "t",
                        "q": merged_source,
                    }
                    url = request_info["base_url"] + "?" + urlencode(params, doseq=True)
                    tasks.append({"payload": None, "url": url, "method": "GET", "task": meta})
            except Exception as exc:
                for idx in group["row_indices"]:
                    rows[idx]["status"] = "failed"
                    rows[idx]["error"] = str(exc)
                    mark_translation_failure(idx, rows[idx].get("error"))
                    update_translation_tree_row(idx)
                pre_failed += len(group["row_indices"])
                logger.error("Merged group translation failed", extra={"error": str(exc)})
    else:
        for idx in row_indices:
            row = rows[idx]
            row["status"] = "translating"
            row["error"] = ""
            update_translation_tree_row(idx)
            meta = {
                "row_indices": [idx],
                "chunk_count": 1,
                "sources": [row.get("source") or ""],
                "provider": provider_name,
                "smart_merge": False,
                "target_code": target_code,
                "process_count": 1,
            }
            try:
                if provider_name in LLM_STRUCTURED_PROVIDERS:
                    messages = _build_llm_messages_for_row(rows, idx, prompt_content)
                    payload = _build_llm_payload(
                        provider_name,
                        request_info.get("model"),
                        request_info.get("temperature", OPENAI_DEFAULT_TEMPERATURE),
                        messages,
                    )
                    payload_text = json.dumps(payload, ensure_ascii=False)
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                elif provider_name == AZURE_PROVIDER:
                    payload_text = json.dumps([{"text": row.get("source") or ""}], ensure_ascii=False)
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                elif provider_name == DEEPL_PROVIDER:
                    payload_text = urlencode(
                        {"auth_key": request_info["api_key"], "text": row.get("source") or "", "target_lang": target_code}
                    )
                    tasks.append({"payload": payload_text, "url": request_info["url"], "method": "POST", "task": meta})
                else:
                    params = {
                        "client": "gtx",
                        "sl": "auto",
                        "tl": target_code,
                        "dt": "t",
                        "q": row.get("source") or "",
                    }
                    url = request_info["base_url"] + "?" + urlencode(params, doseq=True)
                    tasks.append({"payload": None, "url": url, "method": "GET", "task": meta})
            except Exception as exc:
                rows[idx]["status"] = "failed"
                rows[idx]["error"] = str(exc)
                mark_translation_failure(idx, rows[idx].get("error"))
                update_translation_tree_row(idx)
                pre_failed += 1
                logger.error("Translation task build failed", extra={"error": str(exc)})

    if not tasks:
        translation_state["busy"] = False
        refresh_translation_controls()
        summary_en = f"Completed: 0/{total_rows} succeeded, {pre_failed} failed. Tokens: 0"
        summary_zh = f"完成：成功 0/{total_rows} 条，失败 {pre_failed} 条。令牌：0"
        set_translate_status(summary_en, summary_zh)
        return False

    concurrency = max(1, min(_get_selected_speed_value(), len(tasks)))
    timeout = TIMEOUT_MERGE if use_smart_merge else request_info.get("timeout", TIMEOUT_SINGLE)
    progress = {"success": 0, "failed": pre_failed, "tokens": 0, "processed": pre_failed}

    if _ensure_temp_dir():
        prefix_output = f"translate_output_{RAND_CODE}_"
        prefix_payload = f"translate_payload_{RAND_CODE}_"
        for name in os.listdir(TEMP_DIR):
            if name.startswith(prefix_output) or name.startswith(prefix_payload):
                try:
                    os.remove(os.path.join(TEMP_DIR, name))
                except Exception:
                    pass

    def on_progress(task, result):
        if result.get("success"):
            progress["tokens"] += int(result.get("tokens") or 0)
            translations = result.get("translation")
            indices = task.get("row_indices") or []
            if isinstance(translations, list):
                for offset, idx in enumerate(indices):
                    rows[idx]["target"] = translations[offset] if offset < len(translations) else ""
                    rows[idx]["status"] = "success"
                    rows[idx].pop("error", None)
                    clear_translation_failure(idx)
                    update_translation_tree_row(idx)
            else:
                idx = indices[-1] if indices else None
                if idx is not None:
                    rows[idx]["target"] = translations if isinstance(translations, str) else ""
                    rows[idx]["status"] = "success"
                    rows[idx].pop("error", None)
                    clear_translation_failure(idx)
                    update_translation_tree_row(idx)
            progress["success"] += int(task.get("process_count") or 1)
        else:
            err_msg = result.get("err") or "translation_failed"
            for idx in task.get("row_indices") or []:
                rows[idx]["status"] = "failed"
                rows[idx]["error"] = str(err_msg)
                mark_translation_failure(idx, rows[idx].get("error"))
                update_translation_tree_row(idx)
            progress["failed"] += int(task.get("process_count") or 1)
        progress["processed"] += int(task.get("process_count") or 1)
        done = progress["processed"]
        total = total_rows
        progress_en = f"{labels['en']}... {done}/{total}  Tokens: {progress['tokens']}"
        progress_zh = f"{labels['cn']}... {done}/{total}  令牌: {progress['tokens']}"
        set_translate_status(progress_en, progress_zh)

    def finalize():
        translation_state["busy"] = False
        translation_state["last_tokens"] = progress["tokens"]
        _update_editor_from_selection()
        refresh_translation_controls()
        summary_en = f"Completed: {progress['success']}/{total_rows} succeeded, {progress['failed']} failed. Tokens: {progress['tokens']}"
        summary_zh = f"完成：成功 {progress['success']}/{total_rows} 条，失败 {progress['failed']} 条。令牌：{progress['tokens']}"
        set_translate_status(summary_en, summary_zh)
        if progress["failed"]:
            logger.warning(
                "Rows failed during translation",
                extra={
                    "component": "translation",
                    "failed": progress["failed"],
                    "total": total_rows,
                    "provider": provider_name,
                },
            )
        else:
            logger.info(
                "Translation batch completed",
                extra={
                    "component": "translation",
                    "success": progress["success"],
                    "total": total_rows,
                    "tokens": progress["tokens"],
                    "provider": provider_name,
                },
            )

    batches = [tasks[i:i + concurrency] for i in range(0, len(tasks), concurrency)]
    batch_index = 0

    def launch_batch():
        nonlocal batch_index
        if batch_index >= len(batches):
            finalize()
            return
        batch = batches[batch_index]

        def on_batch_complete():
            nonlocal batch_index
            batch_index += 1
            launch_batch()

        started, start_err = launch_async_translation(
            batch,
            {
                "headers": request_info.get("headers") or [],
                "timeout": timeout,
                "parallel_limit": len(batch),
                "payload_prefix": f"translate_payload_{RAND_CODE}",
                "output_prefix": f"translate_output_{RAND_CODE}",
                "parser": _parse_async_response,
                "max_retry": request_info.get("max_retry", MAX_RETRY),
                "on_progress": on_progress,
                "on_complete": on_batch_complete,
            },
        )

        if not started:
            for item in batch:
                on_progress(item.get("task") or {}, {"success": False, "err": start_err or "parallel_execution_failed"})
            batch_index += 1
            launch_batch()

    launch_batch()

    return True


def _start_translation(row_indices: Sequence[int], progress_key: str) -> None:
    """Start translation workflow for指定行.

    Args:
        row_indices (Sequence[int]): Row indexes selected for translation.
        progress_key (str): Progress label key (all/retry/selected).

    Returns:
        None.

    Raises:
        None.

    Examples:
        >>> _start_translation([0, 1], "all")  # doctest: +SKIP
    """
    if translation_state.get("busy"):
        return
    if not row_indices:
        show_warning_message(("Nothing to translate.", "没有可翻译的行。"))
        return
    try:
        provider, target_code = get_provider_and_target()
    except Exception:
        return

    translation_state["last_target_code"] = target_code
    try:
        translation_state["last_provider"] = items["ProviderCombo"].CurrentText
    except Exception:
        translation_state["last_provider"] = None
    try:
        translation_state["last_target_label"] = items["TargetLangCombo"].CurrentText
    except Exception:
        translation_state["last_target_label"] = None

    prompt_text = openai_items["SystemPromptTxt"].PlainText
    system_prompt = _compose_prompt_content(target_code, prompt_text)

    translation_state["busy"] = True
    refresh_translation_controls()
    set_translate_status("Starting translation...", "开始翻译...")
    logger.info(
        "Translation started",
        extra={
            "component": "translation",
            "rows": len(row_indices),
            "progress_key": progress_key,
            "provider": getattr(provider, "name", provider.__class__.__name__),
            "target_code": target_code,
        },
    )

    try:
        use_smart_merge = items.get("SmartMergeCheck") and items["SmartMergeCheck"].Checked
    except Exception:
        use_smart_merge = False

    started = _translate_rows(row_indices, provider, target_code, system_prompt, progress_key, use_smart_merge)
    if not started:
        translation_state["busy"] = False
        refresh_translation_controls()


# =============== 主按钮逻辑（核心差异处 ★★★） ===============
def get_provider_and_target():
    """返回 (provider 实例, target_code)，出错时抛 {'en','zh'} 元组"""
    provider_name = items["ProviderCombo"].CurrentText
    target_name   = items["TargetLangCombo"].CurrentText
    logger.debug(
        "Provider selected",
        extra={"component": "translation", "provider": provider_name},
    )

    if provider_name == OPENAI_FORMAT_PROVIDER:
        # 必填校验：未填写 BaseURL 或 Key 时直接阻断翻译
        if not (openai_items["OpenAIFormatBaseURL"].Text.strip() and openai_items["OpenAIFormatApiKey"].Text.strip()):
            show_warning_message(STATUS_MESSAGES.enter_api_key)
            raise ValueError("OpenAI Format missing base url or api key")
        
        model = openai_items["OpenAIFormatModelName"].PlaceholderText.strip()
        base_url   = openai_items["OpenAIFormatBaseURL"].Text.strip() or OPENAI_FORMAT_BASE_URL
        api_key    = openai_items["OpenAIFormatApiKey"].Text.strip()
        temperature = openai_items["OpenAIFormatTemperatureSpinBox"].Value
        # 更新 Provider 配置
        prov_manager.update_cfg(OPENAI_FORMAT_PROVIDER,
            model   = model,
            base_url= base_url,
            api_key = api_key,
            temperature = temperature
        )
        return prov_manager.get(OPENAI_FORMAT_PROVIDER), target_name

    def _resolve_target_code():
        idx = None
        try:
            idx = items["TargetLangCombo"].CurrentIndex
        except Exception:
            idx = None
        if idx is None:
            raise ValueError("Target language selection is unavailable.")
        try:
            return _get_target_code_from_index(provider_name, idx)
        except ValueError:
            label = provider_name.strip()
            show_dynamic_message(
                f"Unsupported language for {label}: {target_name}",
                f"{label} 不支持该语言：{target_name}",
            )
            raise

    if provider_name == AZURE_PROVIDER:
        #if not azure_items["AzureApiKey"].Text.strip():
        #    show_warning_message(STATUS_MESSAGES.enter_api_key)
        prov_manager.update_cfg(
            AZURE_PROVIDER,
            api_key = azure_items["AzureApiKey"].Text.strip(),
            region  = azure_items["AzureRegion"].Text.strip() or AZURE_DEFAULT_REGION
        )
        return prov_manager.get(AZURE_PROVIDER), _resolve_target_code()

    if provider_name == GLM_PROVIDER:
        # GLM 使用聊天补全，目标语言直接传入提示词
        return prov_manager.get(GLM_PROVIDER), target_name

    if provider_name == SILICONFLOW_PROVIDER:
        # SILICONFLOW_PROVIDER 使用聊天补全，目标语言直接传入提示词
        return prov_manager.get(SILICONFLOW_PROVIDER), target_name

    if provider_name == GOOGLE_PROVIDER:
        return prov_manager.get(GOOGLE_PROVIDER), _resolve_target_code()

    if provider_name == DEEPL_PROVIDER:
        # DeepL 缺少 Key 时阻断翻译
        if not deepL_items["DeepLApiKey"].Text.strip():
            show_warning_message(STATUS_MESSAGES.enter_api_key)
            raise ValueError("DeepL missing api key")
        prov_manager.update_cfg(
            DEEPL_PROVIDER,
            api_key = deepL_items["DeepLApiKey"].Text.strip()
        )
        return prov_manager.get(DEEPL_PROVIDER), _resolve_target_code()


def on_load_subtitles(ev):
    if translation_state.get("busy"):
        return
    def _progress(current, total):
        if total:
            en = f"Loading subtitles... {current}/{total}"
            zh = f"加载字幕... {current}/{total}"
        else:
            en = "Scanning active subtitle track..."
            zh = "正在检测激活的字幕轨道..."
        set_translate_status(en, zh)
    set_translate_status("Preparing to load subtitles...", "正在准备加载字幕...")
    load_timeline_subtitles(show_feedback=False, progress_callback=_progress)


def on_start_translate(ev):
    if translation_state.get("busy"):
        return
    if not ensure_translation_rows():
        return
    rows = translation_state.get("rows") or []
    indices = list(range(len(rows)))
    if not indices:
        show_warning_message(STATUS_MESSAGES.nosub)
        return
    _start_translation(indices, "all")


def on_retry_failed(ev):
    if translation_state.get("busy"):
        return
    rows = translation_state.get("rows") or []
    indices = [idx for idx, row in enumerate(rows) if row.get("status") == "failed"]
    if not indices:
        show_warning_message(("No failed rows to retry.", "没有可重试的失败行。"))
        return
    _start_translation(indices, "retry")


def on_translate_selected(ev):
    if translation_state.get("busy"):
        return
    if not ensure_translation_rows():
        return
    indices = _selected_row_indices()
    if not indices:
        indices = translation_state.get("selected_indices") or []
    translation_state["selected_indices"] = indices
    if not indices:
        show_warning_message(("Please select at least one row.", "请至少选择一行。"))
        return
    _start_translation(indices, "selected")


def apply_translations_to_timeline() -> Tuple[bool, int, Optional[str]]:
    """Export translated rows to SRT and import back to the timeline.

    Args:
        None.

    Returns:
        Tuple[bool, int, Optional[str]]: (success flag, applied row count, SRT path).

    Raises:
        None.

    Examples:
        >>> apply_translations_to_timeline()  # doctest: +SKIP
    """
    rows = translation_state.get("rows") or []
    if not rows:
        return False, 0, None

    translated_rows = [
        row for row in rows if (row.get("target") or "").strip()
    ]
    if not translated_rows:
        return False, 0, None

    try:
        resolve_obj, project, media_pool, root, timeline, fps_frac = connect_resolve()
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "Failed to reconnect Resolve",
            extra={"component": "translation", "error": str(exc)},
        )
        show_warning_message(STATUS_MESSAGES.initialize_fault)
        return False, 0, None

    if not timeline:
        show_warning_message(STATUS_MESSAGES.nosub)
        return False, 0, None

    translation_state["project"] = project
    translation_state["timeline"] = timeline
    translation_state["fps_frac"] = fps_frac
    translation_state["start_frame"] = timeline.GetStartFrame() or 0

    subs = []
    for row in translated_rows:
        start_frame = int(row.get("start") or 0)
        end_frame = int(row.get("end") or start_frame)
        subs.append(
            {
                "start": start_frame,
                "end": end_frame,
                "text": row.get("target") or "",
            }
        )
    subs.sort(key=lambda entry: entry["start"])

    target_code = translation_state.get("last_target_code") or _current_target_code()
    timeline_name = timeline.GetName() if timeline else SCRIPT_NAME
    srt_dir = os.path.join(SCRIPT_PATH, "srt")
    try:
        srt_path = write_srt(
            subs,
            translation_state.get("start_frame") or 0,
            translation_state.get("fps_frac") or FPS_FALLBACK,
            timeline_name,
            target_code,
            output_dir=srt_dir,
        )
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "Failed to write SRT",
            extra={"component": "translation", "error": str(exc)},
        )
        show_warning_message(STATUS_MESSAGES.initialize_fault)
        return False, 0, None
    success = import_srt_to_first_empty(srt_path)

    if success:
        for idx, row in enumerate(rows):
            try:
                target_text = (row.get("target") or "").strip()
            except Exception:
                target_text = ""
            if target_text:
                row["status"] = "applied"
                row.pop("error", None)
                clear_translation_failure(idx)
                update_translation_tree_row(idx)
        logger.info(
            "Translations applied to timeline",
            extra={
                "component": "translation",
                "rows_applied": len(translated_rows),
                "srt_path": srt_path,
            },
        )
    else:
        logger.warning(
            "SRT import failed; keeping exported file",
            extra={
                "component": "translation",
                "rows_exported": len(translated_rows),
                "srt_path": srt_path,
            },
        )
    refresh_translation_controls()
    return success, len(translated_rows), srt_path


def on_apply_translations(ev):
    if translation_state.get("busy"):
        return
    rows = translation_state.get("rows") or []
    if not rows:
        show_warning_message(("Nothing to apply.", "没有可导入的译文。"))
        return
    success, applied_count, srt_path = apply_translations_to_timeline()
    if applied_count == 0:
        show_warning_message(("No translated subtitles to apply.", "没有译文可导入。"))
        return
    srt_name = os.path.basename(srt_path) if srt_path else ""
    if success:
        summary_en = f"Applied {applied_count} rows via {srt_name}."
        summary_zh = f"已通过 {srt_name} 导入 {applied_count} 条字幕。"
    else:
        summary_en = f"SRT import failed. Export kept at {srt_name}."
        summary_zh = f"SRT 导入失败，导出文件保留于 {srt_name}。"
    set_translate_status(summary_en, summary_zh)


translator_win.On.LoadSubsButton.Clicked = on_load_subtitles
translator_win.On.StartTranslateButton.Clicked = on_start_translate
translator_win.On.RetryFailedButton.Clicked = on_retry_failed
translator_win.On.TranslateSelectedButton.Clicked = on_translate_selected
translator_win.On.ApplyToTimelineButton.Clicked = on_apply_translations

def on_smart_merge_clicked(ev):
    smart_merge = items.get("SmartMergeCheck")
    if smart_merge and smart_merge.Checked:
        show_dynamic_message(
            "Merge subtitle fragments into full sentences before translating for better context. Ideal for short vertical-video blocks. Best with sentence-ending punctuation (., !, ?).",
            "将多个字幕片段先合并为完整句再翻译，确保上下文更准确；适用于竖屏视频的短字幕块翻译。句末遇到“。！？”，效果最佳。",
        )
translator_win.On.SmartMergeCheck.Clicked = on_smart_merge_clicked

def _on_provider_changed(ev):
    target_combo = items.get("TargetLangCombo")
    keep_code = None
    if target_combo:
        try:
            idx = target_combo.CurrentIndex
        except Exception:
            idx = None
        codes = translation_state.get("target_codes") or []
        if idx is not None and 0 <= idx < len(codes):
            keep_code = codes[idx]
    provider_name = items["ProviderCombo"].CurrentText if "ProviderCombo" in items else ""
    _populate_target_languages(provider_name, preferred_code=keep_code)
translator_win.On.ProviderCombo.CurrentIndexChanged = _on_provider_changed
def _on_translate_mode_changed(ev):
    combo = items.get("TranslateModeCombo")
    if not combo:
        return
    try:
        idx = combo.CurrentIndex
    except Exception:
        idx = None
    if idx is None or idx < 0 or idx >= len(TRANSLATE_SPEED_OPTIONS):
        return
    translation_state["speed_key"] = TRANSLATE_SPEED_OPTIONS[idx]["key"]
translator_win.On.TranslateModeCombo.CurrentIndexChanged = _on_translate_mode_changed
def _on_translate_tree_item_clicked(ev):
    translation_state["selected_indices"] = _selected_row_indices()
    _update_editor_from_selection()
translator_win.On.TranslateTree.ItemClicked = _on_translate_tree_item_clicked

def _on_translate_editor_text_changed(ev):
    if _translate_editor_programmatic:
        return
    rows = translation_state.get("rows") or []
    indices = translation_state.get("selected_indices") or []
    if not indices:
        return
    idx = indices[-1]
    if idx is None or idx < 0 or idx >= len(rows):
        return
    editor = items.get("TranslateSubtitleEditor")
    if not editor:
        return
    try:
        text = editor.PlainText
    except Exception:
        try:
            text = editor.Text
        except Exception:
            text = ""
    text = text or ""
    
    # 检查文本内容是否真正发生变化
    original_text = rows[idx].get("target") or ""
    text_changed = (text != original_text)
    
    # 只有在文本真正变化时才更新 status 和清除失败标记
    if text_changed:
        rows[idx]["target"] = text
        rows[idx]["error"] = ""
        if rows[idx].get("status") not in ("translating",):
            rows[idx]["status"] = "success" if text.strip() else "pending"
        update_translation_tree_row(idx)
        clear_translation_failure(idx)
        refresh_translation_controls()
    # 如果文本没有变化，什么都不做，保持原状态（包括 "failed" 状态）
translator_win.On.TranslateSubtitleEditor.TextChanged = _on_translate_editor_text_changed

_previous_timeout_handler = None
try:
    candidate = dispatcher["On"]["Timeout"]
    if callable(candidate):
        _previous_timeout_handler = candidate
except Exception:
    _previous_timeout_handler = None


def _dispatcher_timeout(ev):
    handled = None
    if callable(_previous_timeout_handler):
        handled = _previous_timeout_handler(ev)
    who = _get_timer_event_id(ev)
    if who == "TranslatePollingTimer":
        return on_translate_timer_timeout(ev)
    if async_translation_state.active:
        return on_translate_timer_timeout(ev)
    return handled


try:
    dispatcher["On"]["Timeout"] = _dispatcher_timeout
except Exception:
    pass


def _initial_load_translation_rows():
    def _progress(current, total):
        # Keep loading window to a single line; just update count for the template.
        if total:
            _set_loading_message("", count=total)
        else:
            _set_loading_message("", count=None)
        # Show basic context in main UI.
        set_translate_status(
            f"Loading subtitles... {current}/{total}" if total else "Scanning active subtitle track...",
            f"加载字幕... {current}/{total}" if total else "正在检测激活的字幕轨道..."
        )

    _set_loading_stage("load")
    set_translate_status("Preparing to load subtitles...", "正在准备加载字幕...")
    count = 0
    track = "-"
    success = load_timeline_subtitles(show_feedback=False, progress_callback=_progress)
    if success:
        count = len(translation_state.get("rows") or [])
        track = translation_state.get("active_track_index") or "-"
        display_msg, en_msg, cn_msg = _format_loaded_message(count, track)
        msg = display_msg
    else:
        msg = "No subtitles found on active subtitle track.\n未在激活字幕轨道发现字幕。"
        en_msg = "No subtitles found on active subtitle track."
        cn_msg = "未在激活字幕轨道发现字幕。"
    _set_loading_stage("done")
    _set_loading_message(msg, count=None)
    set_translate_status(en_msg, cn_msg)
# =============== 8  关闭窗口保存设置 ===============
def on_close(ev):
    output_dir = os.path.join(SCRIPT_PATH, "srt")
    if os.path.exists(output_dir):
        try:
            shutil.rmtree(output_dir)  # ✅ 删除整个文件夹及其中内容
            logger.info(
                "Temporary directory removed",
                extra={"component": "cleanup", "path": output_dir},
            )
        except Exception as e:
            logger.warning(
                "Failed to delete temporary directory",
                extra={"component": "cleanup", "error": str(e), "path": output_dir},
            )
    stop_polling_timer()
    _cleanup_artifacts(async_translation_state.artifacts)
    async_translation_state.reset()
    if os.path.exists(TEMP_DIR):
        try:
            shutil.rmtree(TEMP_DIR)
            logger.info(
                "Temp directory removed",
                extra={"component": "cleanup", "path": TEMP_DIR},
            )
        except Exception as e:
            logger.warning(
                "Failed to delete temp directory",
                extra={"component": "cleanup", "error": str(e), "path": TEMP_DIR},
            )
    close_and_save(settings_file)
    dispatcher.ExitLoop()

translator_win.On.TranslatorWin.Close = on_close

def on_add_model_close(ev):
    openai_format_config_window.Show()
    add_model_window.Hide(); 
add_model_window.On.AddModelWin.Close = on_add_model_close


def main() -> None:
    """Provide a minimal standalone entry point for手动自检.

    Args:
        None.

    Returns:
        None.

    Raises:
        None.

    Examples:
        >>> main()  # doctest: +SKIP
    """
    configure_logging()
    logger.info(
        "Standalone entry executed",
        extra={"component": "bootstrap", "event": "standalone_entry"},
    )


if __name__ == "__main__":
    main()
# =============== 9  运行 GUI ===============
_initial_load_translation_rows()
time.sleep(0.3)
_loading_timer_stop = True
loading_win.Hide() 
translator_win.Show(); 
dispatcher.RunLoop(); 
translator_win.Hide(); 
openai_format_config_window.Hide()
azure_config_window.Hide()
msgbox.Hide()
