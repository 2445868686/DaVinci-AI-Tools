# ================= 用户配置 =================
SCRIPT_NAME    = "Sub AI Translator"
SCRIPT_VERSION = " 1.8"
SCRIPT_AUTHOR  = "HEIBA"
print(f"{SCRIPT_NAME} | {SCRIPT_VERSION.strip()} | {SCRIPT_AUTHOR}")
SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
WINDOW_WIDTH, WINDOW_HEIGHT = 880, 620
X_CENTER = (SCREEN_WIDTH  - WINDOW_WIDTH ) // 2
Y_CENTER = (SCREEN_HEIGHT - WINDOW_HEIGHT) // 2

SCRIPT_KOFI_URL      = "https://ko-fi.com/heiba"
SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"

CONCURRENCY = 10
MAX_RETRY   = 3
TIMEOUT     = 30

OPENAI_FORMAT_API_KEY   = ""
OPENAI_FORMAT_BASE_URL   = "https://api.openai.com"
OPENAI_FORMAT_MODEL = "gpt-4o-mini"
OPENAI_DEFAULT_TEMPERATURE = 0.3

GLM_BASE_URL = "https://open.bigmodel.cn/api/paas"

GOOGLE_PROVIDER         = "Google"
AZURE_PROVIDER          = "Microsoft                     "
GLM_PROVIDER            = "GLM-4-Flash               ( Free AI  )"
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
# --------------------------------------------
# 语言映射
# --------------------------------------------
AZURE_LANG_CODE_MAP = {  # Microsoft
    "中文（普通话）": "zh-Hans",  "中文（粤语）": "yue",
    "English": "en", "Japanese": "ja", "Korean": "ko", "Spanish": "es",
    "Portuguese": "pt", "French": "fr", "Indonesian": "id", "German": "de",
    "Russian": "ru", "Italian": "it", "Arabic": "ar", "Turkish": "tr",
    "Ukrainian": "uk", "Vietnamese": "vi", "Uzbek": "uz", "Dutch": "nl",
}
GOOGLE_LANG_CODE_MAP = {   # Google
    "中文（普通话）": "zh-CN", "中文（粤语）": "zh-TW",
    "English": "en", "Japanese": "ja", "Korean": "ko", "Spanish": "es",
    "Portuguese": "pt", "French": "fr", "Indonesian": "id", "German": "de",
    "Russian": "ru", "Italian": "it", "Arabic": "ar", "Turkish": "tr",
    "Ukrainian": "uk", "Vietnamese": "vi", "Uzbek": "uz", "Dutch": "nl",
}
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
    "CN":False,
    "EN":True,
    "TRANSLATE_MODE": 1,
}
# ===========================================
import base64
import concurrent.futures
import json
import logging
import os
import platform
import random
import re
import string
import sys
import threading
import time
import uuid
import webbrowser
from abc import ABC, abstractmethod
from fractions import Fraction
from typing import Any, Dict, Optional, Sequence, Tuple
from urllib.parse import quote_plus
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
    from deep_translator import DeeplTranslator
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
        from deep_translator import DeeplTranslator
        print(lib_dir)
    except ImportError as e:
        print("Dependency import failed—please make sure all dependencies are bundled into the Lib directory:", lib_dir, "\nError message:", e)


config_dir        = os.path.join(SCRIPT_PATH, "config")
settings_file     = os.path.join(config_dir, "translator_settings.json")
custom_models_file = os.path.join(config_dir, "models.json")
status_file = os.path.join(config_dir, 'status.json')

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

    def translate(self, text, target_lang):
        for attempt in range(1, self.cfg.get("max_retry", 3) + 1):
            try:
                translator = DeeplTranslator(
                    source='auto',
                    target=target_lang,
                    api_key=self.cfg.get("api_key", "")
                )
                return translator.translate(text)
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
            "timeout": 10
        },
        AZURE_PROVIDER: {
            "class":  "AzureProvider",
            "base_url": AZURE_DEFAULT_URL,
            "api_key":  AZURE_DEFAULT_KEY,
            "region":   AZURE_DEFAULT_REGION,
            "max_retry": MAX_RETRY,
            "timeout":  15
        },
        GLM_PROVIDER: {
            "class": "GLMProvider",
            "base_url": GLM_BASE_URL,
            # 默认使用最新可用的 4.5 Flash 型号，兼容 z.ai 与 bigmodel 域名
            "model":    "glm-4-flash",
            "temperature": OPENAI_DEFAULT_TEMPERATURE,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT,
        },
        OPENAI_FORMAT_PROVIDER: {
            "class": "OpenAIFormatProvider",
            "base_url": OPENAI_FORMAT_BASE_URL,
            "api_key":  OPENAI_FORMAT_API_KEY,
            "model":    OPENAI_FORMAT_MODEL,
            "temperature":OPENAI_DEFAULT_TEMPERATURE,
            "max_retry": MAX_RETRY,
            "timeout":  TIMEOUT
        },
        DEEPL_PROVIDER: {
            "class":   "DeepLProvider",
            "api_key": "",          
            "max_retry": MAX_RETRY,
            "timeout":  15,
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
                            ui.ComboBox({"ID": "TranslateModeCombo", "Weight": 0, "MinimumSize": [140, 0]}),
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


target_language = [
    "中文（普通话）", "中文（粤语）", "English", "Japanese", "Korean",
    "Spanish", "Portuguese", "French", "Indonesian", "German", "Russian",
    "Italian", "Arabic", "Turkish", "Ukrainian", "Vietnamese","Uzbek", "Dutch"
]

for lang in target_language:
    items["TargetLangCombo"].AddItem(lang)



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


def _map_target_code(provider_name, target_label):
    if provider_name == AZURE_PROVIDER:
        return AZURE_LANG_CODE_MAP.get(target_label, target_label)
    if provider_name == GOOGLE_PROVIDER:
        return GOOGLE_LANG_CODE_MAP.get(target_label, target_label)
    if provider_name == DEEPL_PROVIDER:
        return GOOGLE_LANG_CODE_MAP.get(target_label, target_label)
    return target_label


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


def on_lang_checkbox_clicked(ev):
    is_en_checked = ev['sender'].ID == "LangEnCheckBox"
    items["LangCnCheckBox"].Checked = not is_en_checked
    items["LangEnCheckBox"].Checked = is_en_checked
    switch_language("en" if is_en_checked else "cn")

translator_win.On.LangCnCheckBox.Clicked = on_lang_checkbox_clicked
translator_win.On.LangEnCheckBox.Clicked = on_lang_checkbox_clicked


if saved_settings:

    items["TargetLangCombo"].CurrentIndex = saved_settings.get("TARGET_LANG", DEFAULT_SETTINGS["TARGET_LANG"])
    items["LangCnCheckBox"].Checked = saved_settings.get("CN", DEFAULT_SETTINGS["CN"])
    items["LangEnCheckBox"].Checked = saved_settings.get("EN", DEFAULT_SETTINGS["EN"])
    items["ProviderCombo"].CurrentIndex = saved_settings.get("PROVIDER", DEFAULT_SETTINGS["PROVIDER"])
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


def _translate_single_row(
    row_index: int,
    provider: "BaseProvider",
    target_code: str,
    prompt_content: str,
) -> Tuple[str, int]:
    """Translate a single subtitle row and return the result with token usage.

    Args:
        row_index (int): Zero-based index of the row to translate.
        provider (BaseProvider): Active translation provider.
        target_code (str): Translation target language code.
        prompt_content (str): Additional prompt text for providers支持上下文翻译.

    Returns:
        Tuple[str, int]: Pair of translated text and消耗的令牌数.

    Raises:
        ValueError: If the provider does not return a textual translation.

    Examples:
        >>> text, tokens = _translate_single_row(0, provider, "en", "")
        >>> isinstance(text, str)
        True
    """
    rows = translation_state.get("rows") or []
    row = rows[row_index]
    source_text = row.get("source") or ""
    provider_name = getattr(provider, "name", provider.__class__.__name__)
    logger.debug(
        "Translating row",
        extra={
            "component": "translation",
            "row_index": row.get("idx", row_index),
            "provider": provider_name,
        },
    )
    if isinstance(provider, (OpenAIFormatProvider, GLMProvider)):
        prefix, suffix = "", ""
        if CONTEXT_WINDOW > 0:
            start = max(0, row_index - CONTEXT_WINDOW)
            prefix = "\n".join(rows[i]["source"] for i in range(start, row_index))
            suffix = "\n".join(
                rows[i]["source"]
                for i in range(row_index + 1, min(len(rows), row_index + 1 + CONTEXT_WINDOW))
            )
        if prefix or suffix:
            result = provider.translate(source_text, target_code, prefix, suffix, prompt_content)
        else:
            result = provider.translate(source_text, target_code, prompt_content=prompt_content)
    else:
        result = provider.translate(source_text, target_code)

    if isinstance(result, tuple):
        translated_text, usage = result
        tokens = usage.get("total_tokens", 0) if isinstance(usage, dict) else 0
    else:
        translated_text, tokens = result, 0
    if not isinstance(translated_text, str):
        raise ValueError("翻译结果无效，未返回字符串")
    logger.debug(
        "Row translated",
        extra={
            "component": "translation",
            "row_index": row.get("idx", row_index),
            "provider": provider_name,
            "tokens": tokens,
        },
    )
    return translated_text, tokens


def _translate_rows(
    row_indices: Sequence[int],
    provider: "BaseProvider",
    target_code: str,
    prompt_content: str,
    progress_key: str,
) -> Tuple[int, int, int]:
    """Translate multiple rows concurrently and collect statistics.

    Args:
        row_indices (Sequence[int]): Row indexes to translate.
        provider (BaseProvider): Provider handling translation requests.
        target_code (str): Target language code.
        prompt_content (str): Additional prompt content.
        progress_key (str): Key identifying progress label set.

    Returns:
        Tuple[int, int, int]: Success count, failure count, total tokens.

    Raises:
        None.

    Examples:
        >>> _translate_rows([0], provider, "en", "", "all")  # doctest: +SKIP
    """
    rows = translation_state.get("rows") or []
    if not row_indices:
        return 0, 0, 0

    concurrency = max(1, min(_get_selected_speed_value(), len(row_indices)))
    labels = TRANSLATE_PROGRESS_LABELS.get(progress_key, TRANSLATE_PROGRESS_LABELS["all"])
    success_count = 0
    failed_count = 0
    total_tokens = 0

    futures: Dict[concurrent.futures.Future, int] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
        for idx in row_indices:
            row = rows[idx]
            row["status"] = "translating"
            row["error"] = ""
            update_translation_tree_row(idx)
            futures[pool.submit(
                _translate_single_row,
                idx,
                provider,
                target_code,
                prompt_content,
            )] = idx

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
        total = len(futures)
        for done, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            idx = futures[future]
            try:
                translated_text, tokens = future.result()
                rows[idx]["target"] = translated_text
                rows[idx]["status"] = "success"
                rows[idx].pop("error", None)
                success_count += 1
                total_tokens += tokens
                clear_translation_failure(idx)
            except requests.exceptions.HTTPError as http_err:
                failed_count += 1
                rows[idx]["status"] = "failed"
                rows[idx]["error"] = str(http_err)
                code = http_err.response.status_code if http_err.response is not None else None
                mapped = code_map.get(code)
                if mapped:
                    show_warning_message(mapped)
                logger.warning(
                    "HTTP error during translation",
                    extra={
                        "component": "translation",
                        "row_index": rows[idx].get("idx", idx),
                        "status_code": code,
                        "error": str(http_err),
                    },
                )
                mark_translation_failure(idx, rows[idx].get("error"))
            except Exception as exc:  # noqa: BLE001
                failed_count += 1
                rows[idx]["status"] = "failed"
                rows[idx]["error"] = str(exc)
                logger.error(
                    "Translation failed",
                    extra={
                        "component": "translation",
                        "row_index": rows[idx].get("idx", idx),
                        "error": str(exc),
                    },
                )
                mark_translation_failure(idx, rows[idx].get("error"))
            update_translation_tree_row(idx)
            progress_en = f"{labels['en']}... {done}/{total}  Tokens: {total_tokens}"
            progress_zh = f"{labels['cn']}... {done}/{total}  令牌: {total_tokens}"
            set_translate_status(progress_en, progress_zh)

    translation_state["last_tokens"] = total_tokens
    _update_editor_from_selection()
    refresh_translation_controls()
    return success_count, failed_count, total_tokens


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
        success, failed, tokens = _translate_rows(row_indices, provider, target_code, system_prompt, progress_key)
    finally:
        translation_state["busy"] = False
        refresh_translation_controls()

    total = len(row_indices)
    summary_en = f"Completed: {success}/{total} succeeded, {failed} failed. Tokens: {tokens}"
    summary_zh = f"完成：成功 {success}/{total} 条，失败 {failed} 条。令牌：{tokens}"
    set_translate_status(summary_en, summary_zh)
    if failed:
        logger.warning(
            "Rows failed during translation",
            extra={
                "component": "translation",
                "failed": failed,
                "total": total,
                "provider": getattr(provider, "name", provider.__class__.__name__),
            },
        )
    else:
        logger.info(
            "Translation batch completed",
            extra={
                "component": "translation",
                "success": success,
                "total": total,
                "tokens": tokens,
                "provider": getattr(provider, "name", provider.__class__.__name__),
            },
        )


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

    if provider_name == AZURE_PROVIDER:
        #if not azure_items["AzureApiKey"].Text.strip():
        #    show_warning_message(STATUS_MESSAGES.enter_api_key)
        prov_manager.update_cfg(
            AZURE_PROVIDER,
            api_key = azure_items["AzureApiKey"].Text.strip(),
            region  = azure_items["AzureRegion"].Text.strip() or AZURE_DEFAULT_REGION
        )
        return prov_manager.get(AZURE_PROVIDER), AZURE_LANG_CODE_MAP[target_name]

    if provider_name == GLM_PROVIDER:
        # GLM 使用聊天补全，目标语言直接传入提示词
        return prov_manager.get(GLM_PROVIDER), target_name

    if provider_name == GOOGLE_PROVIDER:
        return prov_manager.get(GOOGLE_PROVIDER), GOOGLE_LANG_CODE_MAP[target_name]

    if provider_name == DEEPL_PROVIDER:
        # DeepL 缺少 Key 时阻断翻译
        if not deepL_items["DeepLApiKey"].Text.strip():
            show_warning_message(STATUS_MESSAGES.enter_api_key)
            raise ValueError("DeepL missing api key")
        prov_manager.update_cfg(
            DEEPL_PROVIDER,
            api_key = deepL_items["DeepLApiKey"].Text.strip()
        )
        return prov_manager.get(DEEPL_PROVIDER), GOOGLE_LANG_CODE_MAP[target_name]


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
    rows[idx]["target"] = text
    rows[idx]["error"] = ""
    if rows[idx].get("status") not in ("translating",):
        rows[idx]["status"] = "success" if text.strip() else "pending"
    update_translation_tree_row(idx)
    clear_translation_failure(idx)
    refresh_translation_controls()
translator_win.On.TranslateSubtitleEditor.TextChanged = _on_translate_editor_text_changed


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
    import shutil
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
