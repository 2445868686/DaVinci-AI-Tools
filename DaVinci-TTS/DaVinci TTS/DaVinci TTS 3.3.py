# ================= 用户配置 =================
SCRIPT_NAME = "DaVinci TTS"
SCRIPT_VERSION = " 4.0.0"
SCRIPT_AUTHOR = "HEIBA"
print(f"{SCRIPT_NAME} | {SCRIPT_VERSION.strip()} | {SCRIPT_AUTHOR}")
SCREEN_WIDTH = 1920
SCREEN_HEIGHT = 1080
WINDOW_WIDTH = 825
WINDOW_HEIGHT = 450
X_CENTER = (SCREEN_WIDTH - WINDOW_WIDTH) // 2
Y_CENTER = (SCREEN_HEIGHT - WINDOW_HEIGHT) // 2

SCRIPT_KOFI_URL="https://ko-fi.com/heiba"
SCRIPT_TAOBAO_URL = "https://shop120058726.taobao.com/"
OPENAI_FM = "https://openai.fm"
MINIMAX_PREW_URL = "https://www.minimax.io/audio/voices"
MINIMAXI_PREW_URL = "https://www.minimaxi.com/audio/voices"

DEFAULT_CHOICE_LABELS = {"cn": "默认", "en": "Default"}

MINIMAX_MODELS = [
    "speech-2.6-hd",
    "speech-2.6-turbo",
    "speech-02-hd",
    "speech-02-turbo",
    "speech-01-hd",
    "speech-01-turbo",
]

MINIMAX_EMOTIONS = [
    ("默认", "Default"),
    ("高兴", "happy"),
    ("悲伤", "sad"),
    ("愤怒", "angry"),
    ("害怕", "fearful"),
    ("厌恶", "disgusted"),
    ("惊讶", "surprised"),
    ("中性", "neutral")
]
MINIMAX_SOUND_EFFECTS = [
    ("默认", "Default"),
    ("空旷回音", "spacious_echo"),
    ("礼堂广播", "auditorium_echo"),
    ("电话失真", "lofi_telephone"),
    ("机械音", "robotic"),
]
MINIMAX_VOICE_MODIFY_RANGE = (-100, 100)

GENDER_LABELS = {
    "Female": {"cn": "女性", "en": "Female"},
    "Male": {"cn": "男性", "en": "Male"},
    "Neutral": {"cn": "中性", "en": "Neutral"},
    "Child": {"cn": "儿童", "en": "Child"},
}

UPDATE_VERSION_LINE = {
    "version": {
        "cn": "发现新版本：{current} → {latest}\n请前往购买页面下载最新版本。",
        "en": "Update: {current} → {latest}\nDownload on your purchase page.",
    },
    "loading": {
        "cn": "加载中...\n（已耗时 {elapsed} 秒）",
        "en": "loading... \n( {elapsed}s elapsed )",
    },
}


OPENAI_MODELS = [
    "gpt-4o-mini-tts",
    "tts-1",
    "tts-1-hd",
]

DEFAULT_SETTINGS = {
    "Path": "",
    "USE_API": False,
    "API_KEY": '',
    "REGION": '',
    "LANGUAGE": 0,
    "TYPE": 0,
    "NAME": 0,
    "RATE": 1.0,
    "PITCH": 1.0,
    "VOLUME": 1.0,
    "STYLE": 0,
    "BREAKTIME":50,
    "STYLEDEGREE": 1.0,
    "OUTPUT_FORMATS": 0,

    "minimax_API_KEY": "",
    "minimax_GROUP_ID": "",
    "minimax_intlCheckBox":False,

    "minimax_Model": 0,
    "minimax_Voice": 0,
    "minimax_Language": 0,
    "minimax_SubtitleCheckBox":False,
    "minimax_Emotion": 0,
    "minimax_Rate": 1.0,
    "minimax_Volume": 1.0,
    "minimax_Pitch": 0,
    "minimax_Break":50,
    "minimaxVoiceTimbre": 0,
    "minimaxVoiceIntensity": 0,
    "minimaxVoicePitch": 0,
    "minimaxVoiceEffect": 0,

    "OpenAI_API_KEY": "",
    "OpenAI_BASE_URL": "",
    "OpenAI_Model": 0,
    "OpenAI_Voice": 0,
    "OpenAI_Rate": 1.0,
    "OpenAI_Instruction":"",
    "OpenAI_Preset":0,
    
    "CN":False,
    "EN":True,
}
import os
import sys
import platform
import re
import time
import json
import threading
import webbrowser
import uuid, base64
import random
from xml.dom import minidom
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Optional
from urllib.parse import quote_plus

def load_json_file(path: str, default):
    try:
        with open(path, "r", encoding="utf-8") as file:
            return json.load(file)
    except (FileNotFoundError, json.JSONDecodeError):
        return default

def extract_minimax_languages(system_voices: List[Dict[str, Any]], clone_voices: List[Dict[str, Any]]) -> List[str]:
    """
    Build a unique language list from MiniMax voice data to avoid hardcoded options.
    """
    languages: List[str] = []
    for voice in system_voices + clone_voices:
        lang_value = voice.get("language")
        if lang_value and lang_value not in languages:
            languages.append(lang_value)
    return languages or ["中文（普通话）"]

def normalize_gender(gender_value: str) -> str:
    if not gender_value:
        return "Neutral"
    return gender_value.split(",")[0].strip()

def build_label_pair(source: Dict[str, str], fallback: str) -> Dict[str, str]:
    if not isinstance(source, dict):
        return {"cn": fallback, "en": fallback}
    cn = source.get("cn") or fallback
    en = source.get("en") or fallback
    return {"cn": cn, "en": en}

def build_azure_voice_source(voice_list: List[Dict[str, Any]], locale_labels: Dict[str, Dict[str, str]], style_labels: Dict[str, Dict[str, str]]):
    language_order: List[str] = []
    language_map: Dict[str, Dict[str, Any]] = {}
    type_order: List[str] = []
    type_map: Dict[str, Dict[str, Any]] = {}
    voice_lookup: Dict[str, Dict[str, Any]] = {}

    for voice_info in voice_list:
        locale = voice_info.get("Locale")
        short_name = voice_info.get("ShortName") or voice_info.get("Name")
        if not locale or not short_name:
            continue
        if locale not in language_map:
            fallback_label = voice_info.get("LocaleName", locale)
            language_map[locale] = {
                "id": locale,
                "labels": build_label_pair(locale_labels.get(locale, {}), fallback_label),
                "voices": []
            }
            language_order.append(locale)
        gender_id = normalize_gender(voice_info.get("Gender"))
        if gender_id not in type_map:
            type_map[gender_id] = {
                "id": gender_id,
                "labels": GENDER_LABELS.get(gender_id, build_label_pair({}, gender_id))
            }
            type_order.append(gender_id)
        voice_entry = {
            "id": short_name,
            "labels": {
                "cn": voice_info.get("LocalName") or voice_info.get("DisplayName") or short_name,
                "en": voice_info.get("DisplayName") or voice_info.get("LocalName") or short_name,
            },
            "type": gender_id,
            "styles": voice_info.get("StyleList", []) or [],
            "multilingual": voice_info.get("SecondaryLocaleList", []) or [],
            "locale": locale,
        }
        language_map[locale]["voices"].append(voice_entry)
        voice_lookup[short_name] = voice_entry

    languages = [language_map[code] for code in language_order]
    voice_types = [type_map[type_id] for type_id in type_order]
    return {
        "languages": languages,
        "language_map": language_map,
        "voice_types": voice_types,
        "voice_lookup": voice_lookup,
        "style_labels": style_labels,
        "locale_labels": locale_labels,
    }

def build_edge_voice_source(edge_voice_data: Dict[str, Any], style_labels: Dict[str, Dict[str, str]], locale_labels: Dict[str, Dict[str, str]]):
    language_entries: List[Dict[str, Any]] = []
    type_order: List[str] = []
    type_map: Dict[str, Dict[str, Any]] = {}
    voice_lookup: Dict[str, Dict[str, Any]] = {}
    language_map: Dict[str, Dict[str, Any]] = {}

    for locale, locale_data in edge_voice_data.items():
        entry = {
            "id": locale,
            "labels": build_label_pair(locale_labels.get(locale, {}), locale_data.get("language", locale)),
            "voices": []
        }
        language_entries.append(entry)
        language_map[locale] = entry
        for voice in locale_data.get("voices", []):
            voice_name, voice_info = list(voice.items())[0]
            gender_id = normalize_gender(voice_info.get("Gender"))
            if gender_id and gender_id not in type_map:
                type_map[gender_id] = {"id": gender_id, "labels": build_label_pair({}, gender_id)}
                type_order.append(gender_id)
            voice_entry = {
                "id": voice_name,
                "labels": {"cn": voice_info.get("Name", voice_name), "en": voice_info.get("Name", voice_name)},
                "type": gender_id,
                "styles": voice_info.get("Styles", []) or [],
                "multilingual": voice_info.get("SecondaryLocaleList", []) or [],
                "locale": locale,
            }
            entry["voices"].append(voice_entry)
            voice_lookup[voice_name] = voice_entry

    voice_types = [type_map[type_id] for type_id in type_order]
    return {
        "languages": language_entries,
        "language_map": language_map,
        "voice_types": voice_types,
        "voice_lookup": voice_lookup,
        "style_labels": style_labels,
        "locale_labels": locale_labels,
    }

SCRIPT_PATH = os.path.dirname(os.path.abspath(sys.argv[0]))
TEMP_DIR         = os.path.join(SCRIPT_PATH, "temp")
AUDIO_TEMP_DIR = os.path.join(SCRIPT_PATH, "audio_temp")

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
loading_win.Show()
_loading_items = loading_win.GetItems()
_loading_start_ts = time.time()
_loading_timer_stop = False
_loading_confirmation_pending = False
# ================== Supabase 客户端 ==================
SUPABASE_URL = "https://tbjlsielfxmkxldzmokc.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamxzaWVsZnhta3hsZHptb2tjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgxMDc3MDIsImV4cCI6MjA3MzY4MzcwMn0.FTgYJJ-GlMcQKOSWu63TufD6Q_5qC_M4cvcd3zpcFJo"
AZURE_SPEECH_PROVIDER = "AZURE_SPEECH"
AZURE_FALLBACK_REGION = "eastus"
AZURE_FALLBACK_OUTPUT_FORMAT = "audio-48khz-96kbitrate-mono-mp3"


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
_azure_speech_key_cache: Optional[str] = None
_azure_speech_key_lock = threading.Lock()


def get_cached_azure_speech_key() -> tuple:
    """
    通过 Supabase 拉取 Azure Speech Key，结果缓存至插件退出。
    返回 (key, error_message)
    """
    global _azure_speech_key_cache
    if _azure_speech_key_cache:
        return _azure_speech_key_cache, None
    with _azure_speech_key_lock:
        if _azure_speech_key_cache:
            return _azure_speech_key_cache, None
        try:
            _azure_speech_key_cache = supabase_client.fetch_provider_secret(AZURE_SPEECH_PROVIDER)
            return _azure_speech_key_cache, None
        except Exception as exc:
            return None, str(exc)

def _on_loading_confirm(ev):
    dispatcher.ExitLoop()

def _get_update_lang() -> str:
    """
    返回更新提示的语言，优先使用已保存的 UI 语言偏好。
    """
    try:
        settings_path = os.path.join(SCRIPT_PATH, "config", "TTS_settings.json")
        with open(settings_path, "r", encoding="utf-8") as f:
            data = json.load(f) or {}
            if data.get("EN"):
                return "en"
            if data.get("CN"):
                return "cn"
    except Exception:
        pass
    # 3) 回退到默认
    return "en" if DEFAULT_SETTINGS.get("EN") else "cn"

def _loading_timer_worker():
    while not _loading_timer_stop:
        try:
            elapsed = int(time.time() - _loading_start_ts)
            lang_key = _get_update_lang()
            loading_tpl = UPDATE_VERSION_LINE.get("loading", {})
            if isinstance(loading_tpl, dict):
                base_text = (loading_tpl.get(lang_key) or loading_tpl.get("en", "")).format(elapsed=elapsed)
            else:
                base_text = f"Please wait , loading... \n( {elapsed}s elapsed )"
            _loading_items["LoadLabel"].Text = base_text
        except Exception:
            pass
        time.sleep(1.0)

loading_win.On.ConfirmButton.Clicked = _on_loading_confirm
threading.Thread(target=_loading_timer_worker, daemon=True).start()


def _check_for_updates():
    global _loading_confirmation_pending
    current_version = (SCRIPT_VERSION or "").strip()
    result = supabase_client.check_update(SCRIPT_NAME)
    if not result:
        return

    latest_version = (result.get("latest") or "").strip()
    if not latest_version or latest_version == current_version:
        return

    ui_lang = _get_update_lang()
    fallback_lang = "en" if ui_lang == "cn" else "cn"

    messages: List[str] = []
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

def _resolve_lib_dir() -> str:
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
            os.path.join(SCRIPT_PATH, "..", "..", "..", "HB", SCRIPT_NAME, "Lib")
        )
    return os.path.normpath(lib_dir)


def _ensure_lib_priority(lib_dir: str) -> bool:
    if os.path.isdir(lib_dir):
        if lib_dir in sys.path:
            sys.path.remove(lib_dir)
        sys.path.insert(0, lib_dir)
        return True
    print(f"Warning: The TTS/Lib directory doesn't exist: {lib_dir}", file=sys.stderr)
    return False


def _clear_cached_modules(mod_names: List[str]) -> None:
    for name in mod_names:
        sys.modules.pop(name, None)


LIB_DIR = _resolve_lib_dir()
_lib_dir_inserted = _ensure_lib_priority(LIB_DIR)
_dependency_modules = [
    "requests",
    "requests.adapters",
    "urllib3",
    "urllib3.util",
    "azure",
    "azure.cognitiveservices",
    "azure.cognitiveservices.speech",
    "edge_tts",
    "pypinyin",
]

try:
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util import Retry
    import azure.cognitiveservices.speech as speechsdk
    import edge_tts
    import pypinyin
except ImportError as lib_err:
    _clear_cached_modules(_dependency_modules)
    if _lib_dir_inserted:
        try:
            sys.path.remove(LIB_DIR)
        except ValueError:
            pass
        sys.path.append(LIB_DIR)

    try:
        import requests
        from requests.adapters import HTTPAdapter
        from urllib3.util import Retry
        import azure.cognitiveservices.speech as speechsdk
        import edge_tts
        import pypinyin
        print(f"Falling back to global dependencies; Lib import failed: {lib_err}", file=sys.stderr)
    except ImportError as e:
        print("Dependency import failed—please make sure all dependencies are bundled into the Lib directory or installed globally:", LIB_DIR, "\nError message:", e)


try:
    _check_for_updates()
except Exception as exc:
    print(f"Version check encountered an unexpected error: {exc}")


# 创建带重试机制的 session（放在模块初始化，整个脚本共享）
session = requests.Session()
retries = Retry(
    total=3,                 # 最多重试3次
    backoff_factor=0.5,       # 每次重试等待时间逐步增加
    status_forcelist=[500, 502, 503, 504],  # 服务器错误才重试
    allowed_methods=["GET", "POST"]         # 限定方法
)
session.mount('http://', HTTPAdapter(max_retries=retries))
session.mount('https://', HTTPAdapter(max_retries=retries))

def check_or_create_file(file_path):
    if os.path.exists(file_path):
        pass
    else:
        try:
            with open(file_path, 'w') as file:
                json.dump({}, file)  
        except IOError:
            raise Exception(f"Cannot create file: {file_path}")
        
def load_resource(file_path: str) -> str:
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"{file_path} missing – check resources folder")
    # 用标准的 open 读取
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read()

class MiniMaxProvider:
    """
    Handles all interactions with the MiniMax TTS and Voice Clone APIs.
    """
    BASE_URL = "https://api.minimax.chat"
    BASE_URL_INTL = "https://api.minimaxi.chat"

    def __init__(self, api_key: str, group_id: str, is_intl: bool = False):
        if not api_key or not group_id:
            raise ValueError("API key and Group ID are required for MiniMaxProvider.")
        
        self.api_key = api_key
        self.group_id = group_id
        self.base_url = self.BASE_URL_INTL if is_intl else self.BASE_URL
        
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
        })

    def _make_url(self, path: str) -> str:
        return f"{self.base_url}{path}?GroupId={self.group_id}"

    def _handle_api_error(self, response_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parses a standard MiniMax error response and returns a structured error dict."""
        base_resp = response_data.get("base_resp", {})
        status_code = base_resp.get("status_code")
        status_msg = base_resp.get("status_msg", "Unknown error")
        error_message = f"API Error {status_code}: {status_msg}"
        print(error_message)
        return {"error_code": status_code, "error_message": error_message}

    def synthesize(self, text: str, model: str, voice_id: str, speed: float, vol: float, pitch: int, file_format: str, subtitle_enable: bool = False, emotion: Optional[str] = None, voice_modify: Optional[Dict[str, Any]] = None, sound_effects: Optional[str] = None) -> Dict[str, Any]:
        """Synthesizes speech and returns audio content and subtitle URL."""
        show_warning_message(STATUS_MESSAGES.synthesizing)
        url = self._make_url("/v1/t2a_v2")
        self.session.headers["Content-Type"] = "application/json"

        payload = {
            "model": model, "text": text, "stream": False, "subtitle_enable": subtitle_enable,
            "voice_setting": {"voice_id": voice_id, "speed": speed, "vol": vol, "pitch": pitch},
            "audio_setting": {"sample_rate": 32000, "bitrate": 128000, "format": file_format, "channel": 2},
            "voice_modify": voice_modify.copy() if voice_modify else {},
        }
        if emotion and emotion not in ["默认", "Default"]:
            payload["voice_setting"]["emotion"] = emotion

        if sound_effects and sound_effects not in ["默认", "Default"] and "sound_effects" not in payload["voice_modify"]:
            payload["voice_modify"]["sound_effects"] = sound_effects
        print(f"Sending payload to MiniMax: {payload}")

        try:
            response = self.session.post(url, json=payload, timeout=(5, 60))
            response.raise_for_status()
            resp_data = response.json()

            if resp_data.get("base_resp", {}).get("status_code") != 0:
                error_info = self._handle_api_error(resp_data)
                show_warning_message(STATUS_MESSAGES.synthesis_failed)
                return {"audio_content": None, "subtitle_url": None, **error_info}

            data = resp_data.get("data", {})
            audio_hex = data.get("audio")
            if not audio_hex:
                show_warning_message(STATUS_MESSAGES.synthesis_failed)
                return {"audio_content": None, "subtitle_url": None, "error_code": -1, "error_message": "No audio data in response."}

            return {"audio_content": bytes.fromhex(audio_hex), "subtitle_url": data.get("subtitle_file"), "error_code": None, "error_message": None}
        except (requests.exceptions.RequestException, json.JSONDecodeError, KeyError) as e:
            error_message = f"Failed during synthesis request: {e}"
            print(error_message)
            show_warning_message(STATUS_MESSAGES.synthesis_failed)
            return {"audio_content": None, "subtitle_url": None, "error_code": -1, "error_message": error_message}

    def upload_file_for_clone(self, file_path: str) -> Dict[str, Any]:
        """Uploads a file for voice cloning."""
        print("Uploading...")
        show_warning_message(STATUS_MESSAGES.file_upload)
        url = self._make_url("/v1/files/upload")
        self.session.headers.pop("Content-Type", None)

        try:
            with open(file_path, 'rb') as f:
                files = {'file': f}
                data = {'purpose': 'voice_clone'}
                response = self.session.post(url, data=data, files=files, timeout=300)
                response.raise_for_status()
                resp_data = response.json()
              

            if resp_data.get("base_resp", {}).get("status_code") != 0:
                error_info = self._handle_api_error(resp_data)
                return {"file_id": None, **error_info}
            
            return {"file_id": resp_data.get("file", {}).get("file_id"), "error_code": None, "error_message": None}
        except (requests.exceptions.RequestException, IOError, json.JSONDecodeError, KeyError) as e:
            error_message = f"Failed during file upload: {e}"
            print(error_message)
            return {"file_id": None, "error_code": -1, "error_message": error_message}

    def submit_clone_job(self, file_id: str, voice_id: str, need_nr: bool, need_vn: bool, text: Optional[str] = None) -> Dict[str, Any]:
        """Submits a voice clone job."""
        url = self._make_url("/v1/voice_clone")
        self.session.headers["Content-Type"] = "application/json"

        payload = {"file_id": file_id, "voice_id": voice_id, "need_noise_reduction": need_nr, "need_volume_normalization": need_vn}
        if text:
            payload.update({"text": text, "model": "speech-2.6-hd"})
        print(payload)
        try:
            response = self.session.post(url, json=payload, timeout=60)
            response.raise_for_status()
            resp_data = response.json()

            if resp_data.get("base_resp", {}).get("status_code") != 0:
                error_info = self._handle_api_error(resp_data)
                return {"demo_url": None, **error_info}
            
            return {"demo_url": resp_data.get("demo_audio"), "error_code": None, "error_message": None}
        except (requests.exceptions.RequestException, json.JSONDecodeError, KeyError) as e:
            error_message = f"Failed during clone submission: {e}"
            print(error_message)
            return {"demo_url": None, "error_code": -1, "error_message": error_message}

    def download_media(self, url: str) -> Optional[bytes]:
        """Downloads content from a given URL (for subtitles or demo audio)."""
        if not url:
            return None
        try:
            # Use a clean session without auth headers for public URLs
            response = requests.get(url, timeout=60)
            response.raise_for_status()
            return response.content
        except requests.exceptions.RequestException as e:
            print(f"Failed to download media from {url}: {e}")
            return None
        
class OpenAIProvider:
    """
    Handles all interactions with the OpenAI TTS API.
    """
    def __init__(self, api_key, base_url=None):
        """
        Initializes the OpenAI provider.

        Args:
            api_key (str): The OpenAI API key.
            base_url (str, optional): The base URL for the API. 
                                      Defaults to "https://api.openai.com/v1".
        
        Raises:
            ValueError: If the API key is not provided.
        """
        if not api_key:
            raise ValueError("API key is required for OpenAIProvider.")
        
        self.api_key = api_key
        self.base_url = (base_url or "https://api.openai.com/").strip().rstrip('/')
        
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        })

    def synthesize(self, text, model, voice, speed, file_format, instructions=None):
        """
        Synthesizes speech using the OpenAI API.

        Args:
            text (str): The text to synthesize.
            model (str): The TTS model to use.
            voice (str): The voice to use.
            speed (float): The speech speed.
            file_format (str): The desired audio format (e.g., 'mp3').
            instructions (str, optional): Instructions for models that support it.

        Returns:
            bytes: The audio content as bytes if successful, otherwise None.
        """
        show_warning_message(STATUS_MESSAGES.synthesizing)
        url = f"{self.base_url}/v1/audio/speech"
        payload = {
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": file_format,
            "speed": speed
        }
        if model not in ["tts-1", "tts-1-hd"] and instructions:
            payload["instructions"] = instructions

        print(f"Sending payload to OpenAI: {payload}")

        try:
            response = self.session.post(url, json=payload, timeout=90)
            response.raise_for_status()  # Raises HTTPError for bad responses (4xx or 5xx)

            # Check if the response content is actually audio
            content_type = response.headers.get('Content-Type', '')
            if 'audio' not in content_type:
                # The API returned a success status but not audio (e.g., a JSON error)
                show_warning_message(STATUS_MESSAGES.synthesis_failed)
                print(f"API Error: Expected audio, but received {content_type}")
                print(f"Response content: {response.text}")
                return None

            return response.content
        except requests.exceptions.RequestException as e:
            
            print(f"OpenAI API request failed: {e}")
            if e.response is not None:
                # Try to print JSON error if possible, otherwise raw text
                try:
                    error_details = e.response.json()
                    show_warning_message(STATUS_MESSAGES.synthesis_failed)
                    print(f"Error details: {error_details}")
                except ValueError:
                    show_warning_message(STATUS_MESSAGES.synthesis_failed)
                    print(f"Error details: {e.response.text}")
            return None

class AzureTTSProvider:
    """
    Handles all interactions with the Azure and EdgeTTS services.
    """
    def __init__(self, api_key, region, use_api):
        self.api_key = api_key
        self.region = region
        self.use_api = use_api
        self.speech_config = None
        if self.use_api:
            if not self.api_key or not self.region:
                raise ValueError("API key and region are required for Azure API.")
            self.speech_config = speechsdk.SpeechConfig(subscription=self.api_key, region=self.region)

    def synthesize(self, text, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format, filename, start_frame, end_frame):
        """
        Synthesizes speech using either Azure API or EdgeTTS.
        """
        if self.use_api:
            return self._synthesize_azure(text, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format, filename, start_frame, end_frame)
        else:
            return self._synthesize_edgetts(text, voice_name, rate, pitch, volume, filename, start_frame, end_frame)

    def _synthesize_azure(self, text, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format, filename, start_frame, end_frame):
        show_warning_message(STATUS_MESSAGES.synthesizing)
        self.speech_config.set_speech_synthesis_output_format(audio_format)
        ssml = create_ssml(lang=lang, voice_name=voice_name, text=text, rate=rate, volume=volume, style=style, styledegree=style_degree, multilingual=multilingual, pitch=pitch)
        print(ssml)
        
        audio_output_config = speechsdk.audio.AudioOutputConfig(filename=filename)
        speech_synthesizer = speechsdk.SpeechSynthesizer(speech_config=self.speech_config, audio_config=audio_output_config)
        result = speech_synthesizer.speak_ssml_async(ssml).get()
        
        if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
            time.sleep(1)
            add_to_media_pool_and_timeline(start_frame, end_frame, filename)
            return True, None
        elif result.reason == speechsdk.ResultReason.Canceled:
            cancellation_details = result.cancellation_details
            error_message = f"Speech synthesis canceled: {cancellation_details.reason}"
            if cancellation_details.reason == speechsdk.CancellationReason.Error:
                error_message += f" - Error details: {cancellation_details.error_details}"
            print(error_message)
            show_warning_message(STATUS_MESSAGES.synthesis_failed)
            return False, error_message
        return False, "Unknown Azure synthesis error."

    def _synthesize_edgetts(self, text, voice_name, rate, pitch, volume, filename, start_frame, end_frame):
        show_warning_message(STATUS_MESSAGES.synthesizing)
        prosody_rate = f"+{int((rate-1)*100)}%" if rate > 1 else f"-{int((1-rate)*100)}%"
        prosody_pitch = f"+{int((pitch-1)*100)}Hz" if pitch > 1 else f"-{int((1-pitch)*100)}Hz"
        prosody_volume = f"+{int((volume-1)*100)}%" if volume > 1 else f"-{int((1-volume)*100)}%"
        
        debug_payload = {
            "voice": voice_name,
            "rate": prosody_rate,
            "pitch": prosody_pitch,
            "volume": prosody_volume,
            "text_len": len(text or ""),
            "text_preview": (text or "")[:200].replace("\n", "\\n"),
            "output": filename,
            "frames": {"start": start_frame, "end": end_frame},
        }
        try:
            print("[EdgeTTS Debug] payload:", json.dumps(debug_payload, ensure_ascii=False))
        except Exception:
            print("[EdgeTTS Debug] payload (fallback):", debug_payload)
        
        try:
            communicate = edge_tts.Communicate(text, voice_name, rate=prosody_rate, volume=prosody_volume, pitch=prosody_pitch)
            communicate.save_sync(filename)
            time.sleep(1)
            add_to_media_pool_and_timeline(start_frame, end_frame, filename)
            return True, None
        except Exception as e:
            error_message = f"EdgeTTS synthesis failed: {e}"
            print(error_message)
            fallback_success, fallback_error = self._synthesize_via_azuretts(
                text=text,
                voice_name=voice_name,
                prosody_rate=prosody_rate,
                prosody_pitch=prosody_pitch,
                prosody_volume=prosody_volume,
                filename=filename,
                start_frame=start_frame,
                end_frame=end_frame,
            )
            if fallback_success:
                return True, None
            show_warning_message(STATUS_MESSAGES.synthesis_failed)
            return False, fallback_error or error_message

    def _build_fallback_ssml(self, text, voice_name, prosody_rate, prosody_pitch, prosody_volume):
        lang_attr = lang if lang else "en-US"
        speak = ET.Element(
            "speak",
            xmlns="http://www.w3.org/2001/10/synthesis",
            attrib={"version": "1.0", "xml:lang": lang_attr},
        )
        voice = ET.SubElement(speak, "voice", name=voice_name)
        prosody_attrs = {}
        if prosody_rate:
            prosody_attrs["rate"] = prosody_rate
        if prosody_pitch:
            prosody_attrs["pitch"] = prosody_pitch
        if prosody_volume:
            prosody_attrs["volume"] = prosody_volume
        prosody_el = ET.SubElement(voice, "prosody", attrib=prosody_attrs)
        prosody_el.text = text or ""
        return format_xml(ET.tostring(speak, encoding="unicode"))

    def _synthesize_via_azuretts(self, text, voice_name, prosody_rate, prosody_pitch, prosody_volume, filename, start_frame, end_frame):
        """
        EdgeTTS 失败时，使用 Azure REST 接口兜底（固定 eastus）。
        """
        print(
            f"[EdgeTTS Fallback] Switching to Azure REST: voice={voice_name}, "
            f"region={AZURE_FALLBACK_REGION}, format={AZURE_FALLBACK_OUTPUT_FORMAT}"
        )
        secret, fetch_err = get_cached_azure_speech_key()
        if not secret:
            return False, f"Failed to fetch Azure speech key: {fetch_err}"

        ssml = self._build_fallback_ssml(text, voice_name, prosody_rate, prosody_pitch, prosody_volume)
        headers = {
            "Content-Type": "application/ssml+xml",
            "X-Microsoft-OutputFormat": AZURE_FALLBACK_OUTPUT_FORMAT,
            "Ocp-Apim-Subscription-Key": secret,
            "User-Agent": f"{SCRIPT_NAME}/{SCRIPT_VERSION.strip()}",
        }
        endpoint = f"https://{AZURE_FALLBACK_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"

        try:
            response = session.post(endpoint, data=ssml.encode("utf-8"), headers=headers, timeout=90)
            response.raise_for_status()
            content_type = response.headers.get("Content-Type", "")
            if "audio" not in content_type:
                return False, f"Azure TTS fallback failed: unexpected content type {content_type}"
            with open(filename, "wb") as f:
                f.write(response.content)
            time.sleep(1)
            add_to_media_pool_and_timeline(start_frame, end_frame, filename)
            return True, None
        except requests.exceptions.RequestException as exc:
            detail = ""
            if exc.response is not None:
                try:
                    detail = exc.response.text[:200]
                except Exception:
                    detail = str(exc)
            return False, f"Azure TTS fallback failed: {exc}; {detail}"

    def preview(self, text, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format):
        if not self.use_api:
            show_warning_message(STATUS_MESSAGES.prev_txt) # Or some other appropriate message for EdgeTTS preview
            return False, "Preview is not supported for EdgeTTS in this implementation."

        show_warning_message(STATUS_MESSAGES.playing)
        self.speech_config.set_speech_synthesis_output_format(audio_format)
        ssml = create_ssml(lang=lang, voice_name=voice_name, text=text, rate=rate, volume=volume, style=style, styledegree=style_degree, multilingual=multilingual, pitch=pitch)
        
        audio_output_config = speechsdk.audio.AudioOutputConfig(use_default_speaker=True)
        speech_synthesizer = speechsdk.SpeechSynthesizer(speech_config=self.speech_config, audio_config=audio_output_config)
        result = speech_synthesizer.speak_ssml_async(ssml).get()
        
        if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
            show_warning_message(STATUS_MESSAGES.reset_status)
            return True, speechsdk.AudioDataStream(result)
        elif result.reason == speechsdk.ResultReason.Canceled:
            cancellation_details = result.cancellation_details
            error_message = f"Preview failed: {cancellation_details.reason}"
            if cancellation_details.reason == speechsdk.CancellationReason.Error:
                error_message += f" - Error details: {cancellation_details.error_details}"
            print(error_message)
            show_warning_message(STATUS_MESSAGES.synthesis_failed)
            return False, error_message
        return False, "Unknown Azure preview error."

config_dir = os.path.join(SCRIPT_PATH, 'config')
voices_dir = os.path.join(SCRIPT_PATH, 'voices')
settings_file = os.path.join(config_dir, 'TTS_settings.json')
STATUS_FILE = os.path.join(config_dir, 'status.json')
SCRIPT_INFO_CN  = load_resource(os.path.join(config_dir, "script_info_cn.html"))
SCRIPT_INFO_EN  = load_resource(os.path.join(config_dir, "script_info_en.html"))
MINIMAX_CLONE_INFO_CN = load_resource(os.path.join(config_dir, "script_clone_info_cn.html"))
MINIMAX_CLONE_INFO_EN = load_resource(os.path.join(config_dir, "script_clone_info_en.html"))

check_or_create_file(settings_file)

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

def save_settings(settings, settings_file):
    with open(settings_file, 'w') as file:
        content = json.dumps(settings, indent=4)
        file.write(content)

saved_settings = load_settings(settings_file) 




class STATUS_MESSAGES:
    pass
with open(STATUS_FILE, "r", encoding="utf-8") as file:
    status_data = json.load(file)
# 把 JSON 中的每一项都设置为 STATUS_MESSAGES 的类属性
for key, (en, zh) in status_data.items():
    setattr(STATUS_MESSAGES, key, (en, zh))

def connect_resolve():
    project_manager = resolve.GetProjectManager()
    project = project_manager.GetCurrentProject()
    timeline      = project.GetCurrentTimeline()
    return resolve, project,timeline

resolve, current_project,current_timeline = connect_resolve()

def get_first_empty_track(timeline, start_frame, end_frame, media_type):
    """获取当前播放头位置的第一个空轨道索引"""
    track_index = 1
    while True:
        items = timeline.GetItemListInTrack(media_type, track_index)
        if not items:
            return track_index
        
        # 检查轨道上是否有片段与给定的start_frame和end_frame重叠
        is_empty = True
        for item in items:
            if item.GetStart() <= end_frame and start_frame <= item.GetEnd():
                is_empty = False
                break
        
        if is_empty:
            return track_index
        
        track_index += 1

def load_audio_only_preset(project, keyword="audio only"):
    presets = project.GetRenderPresetList() or []
    def norm(x): return (x if isinstance(x, str) else x.get("PresetName","")).lower()
    hit = next((p for p in presets if keyword in norm(p)), None)
    if hit:
        name = hit if isinstance(hit, str) else hit.get("PresetName")
        if project.LoadRenderPreset(name): return name
    if project.LoadRenderPreset("Audio Only"): return "Audio Only"
    return None
      
def render_audio_by_marker(output_dir):
    """
    使用当前Project、当前Timeline的第一个Marker，导出相应区段的音频（单一剪辑模式）。
    导出完成后，返回可能的音频文件完整路径（字符串）。
    若没有Marker则返回None。
    """
    resolve, current_project,current_timeline = connect_resolve()
    timeline_start_frame = current_timeline.GetStartFrame()
    current_project.SetCurrentRenderMode(1)
    current_mode = current_project.GetCurrentRenderMode()
    markers = current_timeline.GetMarkers()
    
    if current_mode != 1:
        print("渲染模式切换失败，无法继续。")
        return None
    
    if not markers:
        print("请先使用Mark点标记参考音频范围！")
        show_warning_message(STATUS_MESSAGES.insert_mark)

        return None
        
    first_frame_id = sorted(markers.keys())[0]
    marker_info = markers[first_frame_id]

    local_start = int(first_frame_id)
    local_end   = local_start + int(marker_info["duration"]) - 1

    frame_rate = float(current_project.GetSetting("timelineFrameRate"))
    duration_frames = int(marker_info["duration"])
    duration_seconds = duration_frames / frame_rate
    if duration_seconds < 10 or duration_seconds > 300:
        show_warning_message(STATUS_MESSAGES.duration_seconds)
        return None

    mark_in  = timeline_start_frame + local_start
    mark_out = timeline_start_frame + local_end
    
    filename = f"clone_{current_timeline.GetUniqueId()}"
    #current_project.LoadRenderPreset("Audio Only")
    load_audio_only_preset(current_project)
    os.makedirs(output_dir, exist_ok=True)
    render_settings = {
        "SelectAllFrames": False,
        "MarkIn": mark_in,
        "MarkOut": mark_out,
        "TargetDir": output_dir,
        "CustomName": filename,
        "UniqueFilenameStyle": 1,   
        "ExportVideo": False,
        "ExportAudio": True,
        "AudioCodec": "LinearPCM",
        "AudioBitDepth": 16,        
        "AudioSampleRate": 48000,
    }
    minimax_clone_items["minimaxCloneStatus"].Text = "Start..."
    current_project.SetRenderSettings(render_settings)
    job_id = current_project.AddRenderJob()
    if not current_project.StartRendering([job_id],isInteractiveMode=False): # [cite: 97]
        print("错误: 渲染启动失败")
        return None

    show_warning_message(STATUS_MESSAGES.render_audio)
    while current_project.IsRenderingInProgress(): # 
        print("Rendering...")
        time.sleep(2)  

    print("Render complete!")
    clone_filename = f"{filename}.wav"
    clone_file_path = os.path.join(output_dir, clone_filename)
    current_project.DeleteRenderJob(job_id) # 
    return clone_file_path



def add_to_media_pool_and_timeline(start_frame, end_frame, filename):
    resolve, current_project,current_timeline = connect_resolve()
    media_pool = current_project.GetMediaPool()
    root_folder = media_pool.GetRootFolder()
    tts_folder = None

    # 查找或创建"TTS"文件夹
    folders = root_folder.GetSubFolderList()
    for folder in folders:
        if folder.GetName() == "TTS":
            tts_folder = folder
            break

    if not tts_folder:
        tts_folder = media_pool.AddSubFolder(root_folder, "TTS")

    if tts_folder:
        print(f"TTS folder is available: {tts_folder.GetName()}")
    else:
        print("Failed to create or find TTS folder.")
        return False

    # 加载音频到媒体池
    media_pool.SetCurrentFolder(tts_folder)
    imported_items = media_pool.ImportMedia([filename])
    
    if not imported_items:
        print(f"Failed to import media: {filename}")
        return False

    selected_clip = imported_items[0]
    print(f"Imported clip: {selected_clip.GetName()}")

    # 获取当前时间线
    frame_rate = float(current_timeline.GetSetting("timelineFrameRate"))
    clip_duration_frames = timecode_to_frames(selected_clip.GetClipProperty("Duration"), frame_rate)

    # 查找当前播放头位置的第一个空轨道
    track_index = get_first_empty_track(current_timeline, start_frame, end_frame, "audio")

    # 创建clipInfo字典
    clip_info = {
        "mediaPoolItem": selected_clip,
        "startFrame": 0,
        "endFrame": clip_duration_frames - 1,
        "trackIndex": track_index,
        "recordFrame": start_frame,  
        "stereoEye": "both"  
    }

    # 将剪辑添加到时间线
    timeline_item = media_pool.AppendToTimeline([clip_info])
    if timeline_item:
        print(f"Appended clip: {selected_clip.GetName()} to timeline at frame {start_frame} on track {track_index}.")
        show_warning_message(STATUS_MESSAGES.loaded_to_timeline)
    else:
        print("Failed to append clip to timeline.")

def import_srt_to_timeline(srt_path):
    """
    将指定 .srt 文件导入并追加到当前时间线。
    返回 True 表示成功，False 表示失败。
    """
    # 1. 获取 Resolve、ProjectManager、Project、Timeline
    project_manager = resolve.GetProjectManager()
    current_project = project_manager.GetCurrentProject()
    if current_project is None:
        print("错误：未找到当前项目")
        return False

    timeline = current_project.GetCurrentTimeline()
    if timeline is None:
        print("错误：未找到当前时间线")
        return False

    # 2. 选择目标字幕轨道：若当前字幕轨道已有字幕块，则新增一条字幕轨道
    sub_count = timeline.GetTrackCount("subtitle") or 0
    if sub_count < 1:
        if not timeline.AddTrack("subtitle"):
            print("错误：创建字幕轨道失败")
            return False
        sub_count = 1
        target_track = 1
    else:
        current_items = timeline.GetItemListInTrack("subtitle", sub_count) or []
        if current_items:
            if not timeline.AddTrack("subtitle"):
                print("错误：创建字幕轨道失败")
                return False
            sub_count += 1
            target_track = sub_count
        else:
            target_track = sub_count

    # 3. 导入 .srt 到媒体池
    media_pool = current_project.GetMediaPool()
    root_folder = media_pool.GetRootFolder()
    media_pool.SetCurrentFolder(root_folder)

    # 可选：删除媒体池中同名旧条目，避免重复
    file_name = os.path.basename(srt_path)
    for clip in root_folder.GetClipList():
        if clip.GetName() == file_name:
            media_pool.DeleteClips([clip])
            break

    imported = media_pool.ImportMedia([srt_path])  
    if not imported:
        print(f"错误：字幕文件导入失败 -> {srt_path}")
        return False

    # 4. 将导入的字幕追加到时间线
    new_clip = imported[0]
    track_enabled_states = {}
    for ti in range(1, sub_count + 1):
        track_enabled_states[ti] = timeline.GetIsTrackEnabled("subtitle", ti)
        timeline.SetTrackEnable("subtitle", ti, ti == target_track)
    try:
        success = media_pool.AppendToTimeline([new_clip])
    finally:
        for ti, enabled in track_enabled_states.items():
            timeline.SetTrackEnable("subtitle", ti, enabled)
    if not success:
        print("错误：将字幕添加到时间线失败")
        return False

    print(f"字幕已成功加载到时间线: {file_name}")
    return True

msgbox = dispatcher.AddWindow(
        {
            "ID": "MsgBox",
            "WindowTitle": "Info",
            "Geometry": [750, 400, 350, 100],
            "Spacing": 10,
        },
        [
            ui.VGroup(
                [
                    ui.Label({"ID": "InfoLabel", "Text": "",'Alignment': { 'AlignCenter' : True },'WordWrap': True}),
                    ui.HGroup(
                        {"Weight": 0},
                        [ui.Button({"ID": "OkButton", "Text": "OK"})],
                    ),
                ]
            ),
        ]
    )

win = dispatcher.AddWindow({
    "ID": "MainWin", 
    "WindowTitle": SCRIPT_NAME+SCRIPT_VERSION, 
    "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],
    "Spacing": 10,
    "StyleSheet": """
        * {
            font-size: 14px; /* 全局字体大小 */
        }
    """
    },
    [
        ui.VGroup([
            ui.TabBar({"Weight": 0.0, "ID": "MyTabs"}), 
            ui.Stack({"Weight": 1.0, "ID": "MyStack"}, [
                ui.VGroup({"ID": "Azure TTS", "Weight": 1}, [
                    ui.HGroup({"Weight": 1}, [
                        ui.VGroup({"Weight": 0.7}, [
                            ui.TextEdit({"ID": "AzureTxt", "Text": "","PlaceholderText": "", "Font": ui.Font({"PixelSize": 15}),"Weight": 0.9, }),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "GetSubButton", "Text": "从时间线获取字幕", "Weight": 0.7}),
                                ui.SpinBox({"ID": "BreakSpinBox", "Value": 50, "Minimum": 0, "Maximum": 5000, "SingleStep": 50, "Weight": 0.1}),
                                ui.Label({"ID": "BreakLabel", "Text": "ms", "Weight": 0.1}),
                                ui.Button({"ID": "BreakButton", "Text": "停顿", "Weight": 0.1}),
                                
                            ])
                        ]),
                        ui.VGroup({"Weight": 1}, [
                            ui.HGroup({"Weight": 0,"MinimumSize": [200, 20],}, [
                                ui.Button({"ID": "AlphabetButton", "Text": "发音", "Weight": 1}),
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "LanguageLabel", "Text": "语言", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.ComboBox({"ID": "LanguageCombo", "Text": "", "MinimumSize": [200, 20], "MaximumSize": [300,50],"Weight": 0.8,}),
                                ui.Label({"ID": "NameTypeLabel", "Text": "类型", "Alignment": {"AlignRight": False}, "Weight": 0}),
                                ui.ComboBox({"ID": "NameTypeCombo", "Text": "", "Weight": 0})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "NameLabel", "Text": "名称", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.ComboBox({"ID": "NameCombo", "Text": "", "MinimumSize": [200, 20], "MaximumSize": [400,50], "Weight": 0.8,}),
                                ui.Button({"ID": "PlayButton", "Weight": 0,"Text": "播放预览"}),
                                
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "MultilingualLabel", "Text": "语言技能", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.ComboBox({"ID": "MultilingualCombo", "Text": "", "Weight": 0.8})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "StyleLabel", "Text": "风格", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.ComboBox({"ID": "StyleCombo", "Text": "", "Weight": 0.8})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "StyleDegreeLabel", "Text": "风格强度", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.Slider({"ID": "StyleDegreeSlider", "Value": 100, "Minimum": 0, "Maximum": 200, "Orientation": "Horizontal", "Weight": 0.5}),
                                ui.DoubleSpinBox({"ID": "StyleDegreeSpinBox", "Value": 1.0, "Minimum": 0.0, "Maximum": 2.0, "SingleStep": 0.01, "Weight": 0.3})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "RateLabel", "Text": "语速", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.Slider({"ID": "RateSlider", "Value": 100, "Minimum": 0, "Maximum": 300, "Orientation": "Horizontal", "Weight": 0.5}),
                                ui.DoubleSpinBox({"ID": "RateSpinBox", "Value": 1.0, "Minimum": 0.0, "Maximum": 3.0, "SingleStep": 0.01, "Weight": 0.3})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "PitchLabel", "Text": "音高", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.Slider({"ID": "PitchSlider", "Value": 100, "Minimum": 50, "Maximum": 150, "Orientation": "Horizontal", "Weight": 0.5}),
                                ui.DoubleSpinBox({"ID": "PitchSpinBox", "Value": 1.0, "Minimum": 0.5, "Maximum": 1.5, "SingleStep": 0.01, "Weight": 0.3})
                            ]),
                            ui.HGroup({"Weight": 0.1}, [
                                ui.Label({"ID": "VolumeLabel", "Text": "音量", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                ui.Slider({"ID": "VolumeSlider", "Value": 100, "Minimum": 0, "Maximum": 150, "Orientation": "Horizontal", "Weight": 0.5}),
                                ui.DoubleSpinBox({"ID": "VolumeSpinBox", "Value": 1.0, "Minimum": 0, "Maximum": 1.5, "SingleStep": 0.01, "Weight": 0.3})
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "FromSubButton", "Text": "朗读当前字幕"}),
                                ui.Button({"ID": "FromTxtButton", "Text": "朗读文本框"}),
                                ui.Button({"ID": "ResetButton", "Text": "重置"})
                            ]),
                        ])
                    ])
                ]),
                ui.VGroup({"ID": "Minimax TTS", "Weight": 1}, [
                    ui.HGroup({"Weight": 1}, [
                        ui.VGroup({"Weight": 0.7}, [
                            ui.TextEdit({"ID": "minimaxText", "PlaceholderText": "","Weight": 0.9, }),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "minimaxGetSubButton", "Text": "从时间线获取字幕", "Weight": 0.7}),
                                ui.SpinBox({"ID": "minimaxBreakSpinBox", "Value": 50, "Minimum": 1, "Maximum": 9999, "SingleStep": 50, "Weight": 0.1}),
                                ui.Label({"ID": "minimaxBreakLabel", "Text": "ms", "Weight": 0.1}),
                                ui.Button({"ID": "minimaxBreakButton", "Text": "停顿", "Weight": 0.1})
                            ])
                        ]),
                        ui.VGroup({"Weight": 1}, [
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxModelLabel","Text": "模型:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "minimaxModelCombo", "Text": "选择模型", "Weight": 0.8}),
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxLanguageLabel","Text": "语言:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "minimaxLanguageCombo", "Text": "选择语言", "Weight": 0.8})
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxVoiceLabel","Text": "音色:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "minimaxVoiceCombo", "Text": "选择人声","Weight": 0.8}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "minimaxPreviewButton", "Text": "试听","Weight": 0.1}),
                                ui.Button({"ID": "ShowMiniMaxClone", "Text": "","Weight": 0.1}),
                                ui.Button({"ID": "minimaxDeleteVoice", "Text": "","Weight": 0.1}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "minimaxVoiceEffectButton", "Text": "音色效果调节", "Weight": 1}),
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxEmotionLabel","Text": "情绪:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "minimaxEmotionCombo", "Text": "", "Weight": 0.8}),                   
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxRateLabel","Text": "速度:", "Weight": 0.2}),
                                ui.Slider({"ID": "minimaxRateSlider", "Minimum": 50, "Maximum": 200, "Value": 100, "SingleStep": 1, "Weight": 0.6}),
                                ui.DoubleSpinBox({"ID": "minimaxRateSpinBox", "Minimum": 0.50, "Maximum": 2.00, "Value": 1.00, "SingleStep": 0.01, "Decimals": 2, "Weight": 0.2})
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxVolumeLabel","Text": "音量:", "Weight": 0.2}),
                                ui.Slider({"ID": "minimaxVolumeSlider", "Minimum": 10, "Maximum": 1000, "Value": 100, "SingleStep": 1, "Weight": 0.6}),
                                ui.DoubleSpinBox({"ID": "minimaxVolumeSpinBox", "Minimum": 0.10, "Maximum": 10.00, "Value": 1.00, "SingleStep": 0.01, "Decimals": 2, "Weight": 0.2})
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "minimaxPitchLabel","Text": "音调:", "Weight": 0.2}),
                                ui.Slider({"ID": "minimaxPitchSlider", "Minimum": -1200, "Maximum": 1200, "SingleStep": 1, "Weight": 0.6}),
                                ui.SpinBox({"ID": "minimaxPitchSpinBox", "Minimum": -12, "Maximum": 12, "Value": 0, "SingleStep": 1, "Weight": 0.2})
                            ]),
                            ui.HGroup({}, [
                                ui.CheckBox({"ID": "minimaxSubtitleCheckBox", "Text": "生成字幕", "Checked": False, "Alignment": {"AlignLeft": True}, "Weight": 0.2}),
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "minimaxFromSubButton", "Text": "朗读当前字幕"}),
                                ui.Button({"ID": "minimaxFromTxtButton", "Text": "朗读文本框"}),
                                ui.Button({"ID": "minimaxResetButton", "Text": "重置"})
                            ]),
                        ])
                    ])
                ]),
                ui.VGroup({"ID": "OpenAI TTS", "Weight": 1}, [
                    ui.HGroup({"Weight": 1}, [
                        ui.VGroup({"Weight": 0.7}, [
                            ui.TextEdit({"ID": "OpenAIText", "PlaceholderText": "","Weight": 0.9, }),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "OpenAIGetSubButton", "Text": "从时间线获取字幕", "Weight": 0.7}),
                            ])
                        ]),
                        ui.VGroup({"Weight": 1}, [
                            ui.HGroup({}, [
                                ui.Label({"ID": "OpenAIModelLabel","Text": "模型:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "OpenAIModelCombo", "Text": "选择模型", "Weight": 0.8}),
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "OpenAIVoiceLabel","Text": "音色:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "OpenAIVoiceCombo", "Text": "选择人声", "Weight": 0.6}),
                                ui.Button({"ID": "OpenAIPreviewButton", "Text": "试听", "Weight": 0.2})
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "OpenAIPresetLabel","Text": "预设:", "Weight": 0.2}),
                                ui.ComboBox({"ID": "OpenAIPresetCombo", "Text": "预设", "Weight": 0.8}),
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "OpenAIInstructionLabel","Text": "指令:", "Weight": 0.2}),
                                ui.TextEdit({"ID": "OpenAIInstructionText", "PlaceholderText": "", "Weight": 0.8}),
                            ]),
                            ui.HGroup({}, [
                                ui.Label({"ID": "OpenAIRateLabel","Text": "速度:", "Weight": 0.2}),
                                ui.Slider({"ID": "OpenAIRateSlider", "Minimum": 25, "Maximum": 400, "Value": 100, "SingleStep": 1, "Weight": 0.6}),
                                ui.DoubleSpinBox({"ID": "OpenAIRateSpinBox", "Minimum": 0.25, "Maximum": 4.00, "Value": 1.00, "SingleStep": 0.01, "Decimals": 2, "Weight": 0.2})
                            ]),
                            ui.HGroup({"Weight": 0}, [
                                ui.Button({"ID": "OpenAIFromSubButton", "Text": "朗读当前字幕"}),
                                ui.Button({"ID": "OpenAIFromTxtButton", "Text": "朗读文本框"}),
                                ui.Button({"ID": "OpenAIResetButton", "Text": "重置"})
                            ]),
                        ])
                    ])
                ]), 
                ui.HGroup({"ID": "Config", "Weight": 1}, [
                    ui.VGroup({"Weight": 0.5, "Spacing": 10}, [
                        ui.HGroup({"Weight": 1}, [
                            ui.TextEdit({"ID": "infoTxt", "Text": "", "ReadOnly": True, "Font": ui.Font({"PixelSize": 14})})
                        ])
                    ]),
                    ui.VGroup({"Weight": 0.5, "Spacing": 10,}, [
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"ID": "PathLabel", "Text": "保存路径", "Alignment": {"AlignLeft": True}, "Weight": 0.2}),
                            ui.LineEdit({"ID": "Path", "Text": "", "PlaceholderText": "", "ReadOnly": False, "Weight": 0.6}),
                            ui.Button({"ID": "Browse", "Text": "浏览", "Weight": 0.2}),
                        ]),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"ID": "OutputFormatLabel", "Text": "输出格式", "Alignment": {"AlignLeft": True}, "Weight": 0.2}),
                            ui.ComboBox({"ID": "OutputFormatCombo", "Text": "Output_Format", "Weight": 0.8})
                        ]),
                        
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"Text": "Azure API", "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                            ui.Button({"ID": "ShowAzure", "Text": "配置","Weight": 0.1,}),
                        ]),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"Text": "MiniMax API", "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                            ui.Button({"ID": "ShowMiniMax", "Text": "配置","Weight": 0.1}),
                            
                        ]),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"Text": "OpenAI API", "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                            ui.Button({"ID": "ShowOpenAI", "Text": "配置","Weight": 0.1}),
                            
                        ]),                  
                        ui.HGroup({"Weight": 0.1}, [
                            ui.CheckBox({"ID": "LangEnCheckBox", "Text": "EN", "Checked": True, "Alignment": {"AlignRight": True}, "Weight": 0}),
                            ui.CheckBox({"ID": "LangCnCheckBox", "Text": "简体中文", "Checked": False, "Alignment": {"AlignRight": True}, "Weight": 1}),
                            ui.Button({"ID": "openGuideButton", "Text": "教程","Weight": 0.1}),
                        ]),
                        ui.Button({
                            "ID": "CopyrightButton", 
                            "Text": "关注公众号：游艺所\n\n>>>点击查看更多信息<<<\n\n© 2024, Copyright by HB.",
                            "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                            "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                            "Flat": True,
                            "TextColor": [0.1, 0.3, 0.9, 1],
                            "BackgroundColor": [1, 1, 1, 0],
                            "Weight": 0.8
                        })
                    ])
                ])
            ])
        ])
    ]
)

# azure配置窗口
azure_config_window = dispatcher.AddWindow(
    {
        "ID": "AzureConfigWin",
        "WindowTitle": "Azure API",
        "Geometry": [900, 400, 400, 200],
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
                ui.Label({"ID": "AzureLabel","Text": "填写Azure API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "RegionLabel", "Text": "区域", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "Region", "Text": "", "Weight": 0.8}),
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "ApiKeyLabel", "Text": "密钥", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "ApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
                    
                ]),
                ui.CheckBox({"ID": "UseAPICheckBox", "Text": "使用 API", "Checked": False, "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                ui.HGroup({"Weight": 1}, [
                    ui.Button({"ID": "AzureConfirm", "Text": "确定","Weight": 1}),
                    ui.Button({"ID": "AzureRegisterButton", "Text": "注册","Weight": 1}),
                ]),
                
            ]
        )
    ]
)
# openai配置窗口
openai_config_window = dispatcher.AddWindow(
    {
        "ID": "OpenAIConfigWin",
        "WindowTitle": "OpenAI API",
        "Geometry": [900, 400, 400, 200],
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
                ui.Label({"ID": "OpenAILabel","Text": "填写OpenAI API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "OpenAIBaseURLLabel", "Text": "Base URL", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "OpenAIBaseURL", "Text":"","PlaceholderText": "https://api.openai.com", "Weight": 0.8}),
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "OpenAIApiKeyLabel", "Text": "密钥", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "OpenAIApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
                    
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Button({"ID": "OpenAIConfirm", "Text": "确定","Weight": 1}),
                    ui.Button({"ID": "OpenAIRegisterButton", "Text": "注册","Weight": 1}),
                ]),
                
            ]
        )
    ]
)
# minimax配置窗口
minimax_config_window = dispatcher.AddWindow(
    {
        "ID": "MiniMaxConfigWin",
        "WindowTitle": "MiniMax API",
        "Geometry": [900, 400, 400, 200],
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
                ui.Label({"ID": "minimaxLabel","Text": "填写MiniMax API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"Text": "GroupID", "Weight": 0.2}),
                    ui.LineEdit({"ID": "minimaxGroupID", "Weight": 0.8}),
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "minimaxApiKeyLabel","Text": "密钥", "Weight": 0.2}),
                    ui.LineEdit({"ID": "minimaxApiKey", "EchoMode": "Password", "Weight": 0.8})
                ]),
                ui.CheckBox({"ID": "intlCheckBox", "Text": "海外", "Checked": False, "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                ui.HGroup({"Weight": 1}, [
                    ui.Button({"ID": "MiniMaxConfirm", "Text": "确定","Weight": 1}),
                    ui.Button({"ID": "minimaxRegisterButton", "Text": "注册","Weight": 1}),
                ]),
                
            ]
        )
    ]
)

# minimax配置窗口
minimax_clone_window = dispatcher.AddWindow(
    {
        "ID": "MiniMaxCloneWin",
        "WindowTitle": "MiniMax Clone",
        "Geometry": [X_CENTER, Y_CENTER, 600, 420],
        "Hidden": True,
        "StyleSheet": """
        * {
            font-size: 14px; /* 全局字体大小 */
        }
    """
    },
    ui.VGroup( [
        ui.HGroup({"Weight": 0.1}, [
                        ui.Label({"ID": "minimaxCloneLabel","Text": "MiniMax 克隆音色", "Alignment": {"AlignHCenter": True, "AlignVCenter": True,"Weight": 0.1}}),
                        ]),
                        
        ui.HGroup({ "Weight": 1},
            [
                ui.VGroup({"Weight": 1, "Spacing": 10,},
                    [
                        
                        #ui.TextEdit({"ID": "minimaxCloneGuide", "Text": "", "ReadOnly": True, "Font": ui.Font({"PixelSize": 14})}),
                        
                        ui.CheckBox({"ID": "minimaxOnlyAddID", "Text": "已有克隆音色", "Checked": True, "Alignment": {"AlignRight": True}, "Weight": 0.1}),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"ID": "minimaxCloneVoiceNameLabel","Text": "Name", "Weight": 0.2}),
                            ui.LineEdit({"ID": "minimaxCloneVoiceName", "Weight": 0.8})
                        ]),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"ID": "minimaxCloneVoiceIDLabel","Text": "ID", "Weight": 0.2}),
                            ui.LineEdit({"ID": "minimaxCloneVoiceID", "Weight": 0.8}),
                        ]),
                        ui.HGroup({"Weight": 0.1}, [
                            ui.Label({"ID": "minimaxCloneFileIDLabel","Text": "File ID", "Weight": 0.2}),
                            ui.LineEdit({"ID": "minimaxCloneFileID", "Enabled" : False ,"Weight": 0.8}),
                        ]),
                    
                        ui.HGroup({"Weight": 0.1}, [
                            ui.CheckBox({"ID": "minimaxNeedNoiseReduction", "Text": "是否开启降噪", "Checked": False, "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                            ui.CheckBox({"ID": "minimaxNeedVolumeNormalization", "Text": "音量归一化", "Checked": False, "Alignment": {"AlignLeft": True}, "Weight": 0.1}),
                        ]),
                        ui.Label({"ID": "minimaxClonePreviewLabel","Text": "输入试听文本(限制300字以内)：", "Weight": 0.2}),
                        ui.TextEdit({"ID": "minimaxClonePreviewText", "Text": "", }),
                        
                           
                    ]
                ),
                ui.VGroup( {"Weight": 1, "Spacing": 10},
                    [
                        ui.HGroup({"Weight": 1}, [
                            ui.TextEdit({"ID": "minimaxcloneinfoTxt", "Text": MINIMAX_CLONE_INFO_CN, "ReadOnly": True, "Font": ui.Font({"PixelSize": 14})})
                        ])
                    ]
                ),
            ]
        ),
        ui.HGroup({"Weight": 0.1}, [
                ui.Label({"ID": "minimaxCloneStatus","Text": "", "Weight": 0.2}),
        ]),
        ui.HGroup({"Weight": 0.1}, [
                            ui.Button({"ID": "MiniMaxCloneConfirm", "Text": "添加","Weight": 1}),
                            ui.Button({"ID": "MiniMaxCloneCancel", "Text": "取消","Weight": 1}),
                        ]),  

    ]
    )
)

# minimax 音色效果调节窗口
minimax_voice_modify_window = dispatcher.AddWindow(
    {
        "ID": "MiniMaxVoiceModifyWin",
        "WindowTitle": "MiniMax Effect",
        "Geometry": [X_CENTER, Y_CENTER, 320, 320],
        "Hidden": True,
        "StyleSheet": "* { font-size: 14px; }",
    },
    ui.VGroup(
        [
            ui.Label(
                {
                    "ID": "minimaxVoiceModifyTitle",
                    "Text": "音色效果调节",
                    "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                }
            ),
            ui.VGroup(
                {"Weight": 1, "Spacing": 8},
                [
                    ui.VGroup(
                        {"Weight": 0},
                        [
                            ui.Label({"ID": "minimaxTimbreLabel", "Text": "音色", "Alignment": {"AlignLeft": True}}),
                            ui.HGroup(
                                {},
                                [
                                    ui.SpinBox({"ID": "minimaxTimbreSpinBoxLeft", "Minimum": -100, "Maximum": 0, "Value": 0, "SingleStep": 1, "Weight": 0.2}),
                                    ui.Slider({"ID": "minimaxTimbreSlider", "Minimum": -100, "Maximum": 100, "Value": 0, "SingleStep": 1, "Orientation": "Horizontal", "Weight": 0.4}),
                                    ui.SpinBox({"ID": "minimaxTimbreSpinBoxRight", "Minimum": 0, "Maximum": 100, "Value": 0, "SingleStep": 1, "Weight": 0.2, "Prefix": "+"}),
                                ],
                            ),
                        ],
                    ),
                    ui.VGroup(
                        {"Weight": 0},
                        [
                            ui.Label({"ID": "minimaxIntensityLabel", "Text": "强弱", "Alignment": {"AlignLeft": True}}),
                            ui.HGroup(
                                {},
                                [
                                    ui.SpinBox({"ID": "minimaxIntensitySpinBoxLeft", "Minimum": -100, "Maximum": 0, "Value": 0, "SingleStep": 1, "Weight": 0.2}),
                                    ui.Slider({"ID": "minimaxIntensitySlider", "Minimum": -100, "Maximum": 100, "Value": 0, "SingleStep": 1, "Orientation": "Horizontal", "Weight": 0.4}),
                                    ui.SpinBox({"ID": "minimaxIntensitySpinBoxRight", "Minimum": 0, "Maximum": 100, "Value": 0, "SingleStep": 1, "Weight": 0.2, "Prefix": "+"}),
                                ],
                            ),
                        ],
                    ),
                    ui.VGroup(
                        {"Weight": 0},
                        [
                            ui.Label({"ID": "minimaxModifyPitchLabel", "Text": "音高", "Alignment": {"AlignLeft": True}}),
                            ui.HGroup(
                                {},
                                [
                                    ui.SpinBox({"ID": "minimaxModifyPitchSpinBoxLeft", "Minimum": -100, "Maximum": 0, "Value": 0, "SingleStep": 1, "Weight": 0.2}),
                                    ui.Slider({"ID": "minimaxModifyPitchSlider", "Minimum": -100, "Maximum": 100, "Value": 0, "SingleStep": 1, "Orientation": "Horizontal", "Weight": 0.4}),
                                    ui.SpinBox({"ID": "minimaxModifyPitchSpinBoxRight", "Minimum": 0, "Maximum": 100, "Value": 0, "SingleStep": 1, "Weight": 0.2, "Prefix": "+"}),
                                ],
                            ),
                        ],
                    ),
                    ui.HGroup(
                        {},
                        [
                            ui.Label({"ID": "minimaxSoundEffectLabel", "Text": "音效:", "Weight": 0.2}),
                            ui.ComboBox({"ID": "minimaxSoundEffectCombo", "Text": "", "Weight": 0.8}),
                        ],
                    ),
                ],
            ),
            ui.HGroup(
                {"Weight": 0},
                [
                    ui.Button({"ID": "MiniMaxVoiceModifyConfirm", "Text": "确定", "Weight": 1}),
                    ui.Button({"ID": "MiniMaxVoiceModifyCancel", "Text": "取消", "Weight": 1}),
                ],
            ),
        ]
    ),
)

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
        "Tabs": ["微软语音", "MiniMax 语音", "OpenAI 语音","设置"],
        "GetSubButton": "从时间线获取字幕",
        "minimaxGetSubButton": "从时间线获取字幕",
        "OpenAIGetSubButton": "从时间线获取字幕",
        "BreakLabel": "ms",
        "minimaxBreakLabel": "ms",
        "BreakButton": "停顿",
        "minimaxBreakButton": "停顿",
        "AlphabetButton": "发音",
        "minimaxModelLabel": "模型",
        "OpenAIModelLabel": "模型",
        "minimaxLanguageLabel": "语言",
        "minimaxVoiceLabel": "音色",
        "OpenAIVoiceLabel": "音色",
        "OpenAIPresetLabel": "预设",
        "OpenAIPreviewButton": "试听",
        "OpenAIInstructionLabel": "指令",
        "minimaxPreviewButton":"试听",
        "LanguageLabel": "语言",
        "NameTypeLabel": "类型",
        "NameLabel": "名称",
        "MultilingualLabel": "语言技能",
        "StyleLabel": "风格",
        "minimaxEmotionLabel": "情绪",
        "minimaxSoundEffectLabel":"音效",
        "minimaxVoiceEffectButton":"音色效果调节",
        "minimaxVoiceModifyTitle":"音色效果调节",
        "minimaxTimbreLabel":"低沉 / 明亮",
        "minimaxIntensityLabel":"力量感 / 柔和",
        "minimaxModifyPitchLabel":"磁性 / 清脆",
        "StyleDegreeLabel": "风格强度",
        "RateLabel": "语速",
        "minimaxRateLabel": "语速",
        "OpenAIRateLabel": "语速",
        "PitchLabel": "音调",
        "minimaxPitchLabel": "音调",
        "VolumeLabel": "音量",
        "minimaxVolumeLabel": "音量",
        "OutputFormatLabel": "输出格式",
        "PlayButton": "试听",
        "FromSubButton": "朗读当前字幕",
        "OpenAIFromSubButton": "朗读当前字幕",
        "minimaxFromSubButton": "朗读当前字幕",
        "FromTxtButton": "朗读文本框",
        "minimaxFromTxtButton": "朗读文本框",
        "OpenAIFromTxtButton": "朗读文本框",
        "ResetButton": "重置",
        "minimaxResetButton": "重置",
        "OpenAIResetButton": "重置",
        "PathLabel":"保存路径",
        "Browse":"浏览", 
        "ShowAzure":"配置",
        "ShowMiniMax": "配置",
        "openGuideButton":"使用教程",
        "ShowOpenAI": "配置",
        "ShowMiniMaxClone": "克隆",
        "minimaxDeleteVoice":"删除",
        "CopyrightButton":f"关注公众号：游艺所\n\n☕ 点击探索更多功能 ☕\n\n© 2025, Copyright by {SCRIPT_AUTHOR}.",
        "infoTxt":SCRIPT_INFO_CN,
        "AzureLabel":"填写Azure API信息",
        "RegionLabel":"区域",
        "ApiKeyLabel":"密钥",
        "UseAPICheckBox":"使用 API",
        "minimaxSubtitleCheckBox":"生成srt字幕",
        "AzureConfirm":"确定",
        "AzureRegisterButton":"注册",
        "minimaxLabel":"填写MiniMax API信息",
        "minimaxCloneLabel":"添加 MiniMaxAI 克隆音色",
        #"minimaxCloneGuide":"9.9元/音色。\n\n获得复刻音色时，不会立即收取音色复刻费用。\n\n音色的复刻费用将在首次使用此复刻音色进行语音合成时收取。",
        "minimaxCloneVoiceNameLabel":"音色名字",
        "minimaxCloneVoiceIDLabel":"音色 ID",
        "minimaxOnlyAddID":"已有克隆音色ID（在下方填入添加即可）",
        "minimaxCloneFileIDLabel":"音频 ID",
        "minimaxNeedNoiseReduction":"开启降噪",
        "minimaxNeedVolumeNormalization":"音量统一",
        "minimaxClonePreviewLabel":"输入试听文本(限制300字以内)：",
        "minimaxcloneinfoTxt":MINIMAX_CLONE_INFO_CN,
        "minimaxApiKeyLabel":"密钥",
        "intlCheckBox": "海外",
        "MiniMaxConfirm":"确定",
        "MiniMaxCloneConfirm":"添加",
        "MiniMaxCloneCancel":"取消",
        "MiniMaxVoiceModifyConfirm":"确定",
        "MiniMaxVoiceModifyCancel":"取消",
        "minimaxRegisterButton":"注册",
        "OpenAILabel":"填写OpenAI API信息",
        "OpenAIBaseURLLabel":"Base URL",
        "OpenAIApiKeyLabel":"密钥",
        "OpenAIConfirm":"确定",
        "OpenAIRegisterButton":"注册",

    },

    "en": {
        "Tabs": ["Azure TTS", "MiniMax TTS","OpenAI TTS", "Settings"],
        "GetSubButton": "Timeline Subs",
        "minimaxGetSubButton": "Timeline Subs",
        "OpenAIGetSubButton": "Timeline Subs",
        "BreakLabel": "ms",
        "minimaxBreakLabel": "ms",
        "BreakButton": "Break",
        "minimaxBreakButton": "Break",
        "AlphabetButton": "Pronunciation",
        "minimaxModelLabel": "Model",
        "OpenAIModelLabel": "Model",
        "minimaxLanguageLabel": "Language",
        "minimaxVoiceLabel": "Voice",
        "OpenAIVoiceLabel": "Voice",
        "OpenAIPresetLabel": "Preset",
        "OpenAIPreviewButton": "Preview",
        "OpenAIInstructionLabel": "Instruction",
        "openGuideButton":"Usage Tutorial",
        "minimaxPreviewButton":"Preview",
        "LanguageLabel": "Language",
        "NameTypeLabel": "Type",
        "NameLabel": "Name",
        "MultilingualLabel": "Multilingual",
        "StyleLabel": "Style",
        "minimaxEmotionLabel": "Emotion",
        "minimaxVoiceEffectButton":"Voice Effects",
        "minimaxVoiceModifyTitle":"Voice Effects",
        "StyleDegreeLabel": "Style Degree",
        "RateLabel": "Rate",
        "minimaxRateLabel": "Rate",
        "OpenAIRateLabel": "Rate",
        "PitchLabel": "Pitch",
        "minimaxPitchLabel": "Pitch",
        "minimaxTimbreLabel":"Deepen / Brighten",
        "minimaxIntensityLabel":"Stronger / Softer",
        "minimaxModifyPitchLabel":"Nasal / Crisp",
        "VolumeLabel": "Volume",
        "minimaxVolumeLabel": "Volume",
        "OutputFormatLabel": "Format",
        "PlayButton": "Preview",
        "FromSubButton": "Read Subs",
        "minimaxFromSubButton": "Read Subs",
        "OpenAIFromSubButton": "Read Subs",
        "FromTxtButton": "Read Textbox",
        "minimaxFromTxtButton": "Read Textbox",
        "OpenAIFromTxtButton": "Read Textbox",
        "ResetButton": "Reset",
        "minimaxResetButton": "Reset",
        "OpenAIResetButton": "Reset",
        "PathLabel":"Path",
        "Browse":"Browse", 
        "ShowAzure":"Config",
        "ShowMiniMax": "Config",
        "ShowOpenAI": "Config",
        "ShowMiniMaxClone": "Clone",
        "minimaxDeleteVoice":"Delete",
        "CopyrightButton":f"☕ Explore More Features ☕\n\n© 2025, Copyright by {SCRIPT_AUTHOR}.",
        "infoTxt":SCRIPT_INFO_EN,
        "AzureLabel":"Azure API",
        "RegionLabel":"Region",
        "ApiKeyLabel":"Key",
        "UseAPICheckBox":"Use API",
        "minimaxSubtitleCheckBox":"Subtitle Enable",
        "AzureConfirm":"OK",
        "AzureRegisterButton":"Register",
        "minimaxLabel":"MiniMax API",
        "minimaxCloneLabel":"Add MiniMax Clone Voice",
        "minimaxCloneVoiceNameLabel":"Voice Name",
        "minimaxSoundEffectLabel":"Effect",
        #"minimaxCloneGuide":"$3 per voice. \n\nYou won’t be charged for cloning a voice right away \n\n the cloning fee will only be charged the first time you use that cloned voice for speech synthesis.",
        "minimaxCloneVoiceIDLabel":"Voice ID",
        "minimaxCloneFileIDLabel":"File ID",
        "minimaxOnlyAddID":"I already have a clone voice.(just fill in below).",
        "minimaxNeedNoiseReduction":"Noise Reduction",
        "minimaxNeedVolumeNormalization":"Volume Normalization",
        "minimaxClonePreviewLabel":"Input text for cloned voice preview:\n(Limited to 2000 characters. )",
        "minimaxApiKeyLabel":"Key",
        "minimaxcloneinfoTxt":MINIMAX_CLONE_INFO_EN,
        "intlCheckBox": "intl",
        "MiniMaxConfirm":"OK",
        "MiniMaxCloneConfirm":"Add",
        "MiniMaxCloneCancel":"Cancel",
        "MiniMaxVoiceModifyConfirm":"OK",
        "MiniMaxVoiceModifyCancel":"Cancel",
        "minimaxRegisterButton":"Register",
        "OpenAILabel":"OpenAI API",
        "OpenAIBaseURLLabel":"Base URL",
        "OpenAIApiKeyLabel":"Key",
        "OpenAIConfirm":"OK",
        "OpenAIRegisterButton":"Register",
    }
}
items = win.GetItems()
azure_items = azure_config_window.GetItems()
minimax_items = minimax_config_window.GetItems()
openai_items = openai_config_window.GetItems()
minimax_clone_items = minimax_clone_window.GetItems()
minimax_voice_modify_items = minimax_voice_modify_window.GetItems()
msgbox_items = msgbox.GetItems()
items["MyStack"].CurrentIndex = 0

language_combo_entries: List[Dict[str, Any]] = []
type_combo_entries: List[Dict[str, Any]] = []
current_name_entries: List[Dict[str, Any]] = []
current_multilingual_codes: List[str] = []
is_updating_language_combo = False
is_updating_type_combo = False
is_updating_name_combo = False

def get_minimax_emotion_code_from_text(text: str) -> str:
    for cn, en in MINIMAX_EMOTIONS:
        if text in (cn, en):
            return en
    return MINIMAX_EMOTIONS[0][1]

def get_selected_minimax_emotion_code() -> str:
    return get_minimax_emotion_code_from_text(items["minimaxEmotionCombo"].CurrentText)

def set_minimax_emotion_by_code(code: str):
    for idx, (_, en) in enumerate(MINIMAX_EMOTIONS):
        if en == code:
            items["minimaxEmotionCombo"].CurrentIndex = idx
            return
    items["minimaxEmotionCombo"].CurrentIndex = 0

def get_selected_sound_effect_code() -> str:
    text = minimax_voice_modify_items["minimaxSoundEffectCombo"].CurrentText
    for cn, en in MINIMAX_SOUND_EFFECTS:
        if text in (cn, en):
            return en
    return MINIMAX_SOUND_EFFECTS[0][1]

def set_sound_effect_by_code(code: str):
    for idx, (_, en) in enumerate(MINIMAX_SOUND_EFFECTS):
        if en == code:
            minimax_voice_modify_items["minimaxSoundEffectCombo"].CurrentIndex = idx
            return
    minimax_voice_modify_items["minimaxSoundEffectCombo"].CurrentIndex = 0

def get_sound_effect_code_by_index(index: int) -> str:
    safe_index = max(0, min(index, len(MINIMAX_SOUND_EFFECTS) - 1))
    return MINIMAX_SOUND_EFFECTS[safe_index][1]

def get_sound_effect_index_from_code(code: str) -> int:
    for idx, (_, en) in enumerate(MINIMAX_SOUND_EFFECTS):
        if en == code:
            return idx
    return 0

def populate_sound_effect_combo(use_en: bool, preserved_code: str = None):
    if preserved_code is None:
        preserved_code = get_selected_sound_effect_code()
    combo = minimax_voice_modify_items["minimaxSoundEffectCombo"]
    combo.Clear()
    for cn, en in MINIMAX_SOUND_EFFECTS:
        combo.AddItem(en if use_en else cn)
    set_sound_effect_by_code(preserved_code)

def get_ui_lang_key() -> str:
    return "en" if items["LangEnCheckBox"].Checked else "cn"

def get_default_label() -> str:
    return DEFAULT_CHOICE_LABELS[get_ui_lang_key()]

def is_using_azure_api() -> bool:
    return azure_items["UseAPICheckBox"].Checked

def get_active_voice_source() -> Dict[str, Any]:
    return AZURE_VOICE_SOURCE if is_using_azure_api() else EDGE_VOICE_SOURCE

def get_label_text(labels: Dict[str, str]) -> str:
    key = get_ui_lang_key()
    return labels.get(key) or labels.get("en") or labels.get("cn") or next(iter(labels.values()), "")

def refresh_type_combo(preserve_type: Optional[str] = None, saved_index: Optional[int] = None):
    global type_combo_entries, is_updating_type_combo
    source = get_active_voice_source()
    type_combo_entries = source.get("voice_types", [])
    items["NameTypeCombo"].Clear()
    for entry in type_combo_entries:
        items["NameTypeCombo"].AddItem(get_label_text(entry["labels"]))
    if not type_combo_entries:
        return
    target_index = 0
    if preserve_type:
        for idx, entry in enumerate(type_combo_entries):
            if entry["id"] == preserve_type:
                target_index = idx
                break
    elif saved_index is not None and 0 <= saved_index < len(type_combo_entries):
        target_index = saved_index
    is_updating_type_combo = True
    items["NameTypeCombo"].CurrentIndex = target_index
    is_updating_type_combo = False

def get_selected_type_id() -> Optional[str]:
    index = items["NameTypeCombo"].CurrentIndex
    if 0 <= index < len(type_combo_entries):
        return type_combo_entries[index]["id"]
    return None

def handle_voice_type_change(_index: int, saved_voice_index: Optional[int] = None):
    update_name_combo(saved_index=saved_voice_index)

def refresh_language_combo(
    preserve_locale: Optional[str] = None,
    saved_index: Optional[int] = None,
    saved_voice_index: Optional[int] = None,
    preserve_voice_id: Optional[str] = None,
):
    global language_combo_entries, is_updating_language_combo
    source = get_active_voice_source()
    language_combo_entries = source.get("languages", [])
    items["LanguageCombo"].Clear()
    for entry in language_combo_entries:
        items["LanguageCombo"].AddItem(get_label_text(entry["labels"]))
    if not language_combo_entries:
        return
    target_index = 0
    if preserve_locale:
        for idx, entry in enumerate(language_combo_entries):
            if entry["id"] == preserve_locale:
                target_index = idx
                break
    elif saved_index is not None and 0 <= saved_index < len(language_combo_entries):
        target_index = saved_index
    is_updating_language_combo = True
    items["LanguageCombo"].CurrentIndex = target_index
    is_updating_language_combo = False
    handle_language_selection_change(target_index, saved_voice_index=saved_voice_index, preserve_voice_id=preserve_voice_id)

def handle_language_selection_change(index: int, saved_voice_index: Optional[int] = None, preserve_voice_id: Optional[str] = None):
    global lang
    if not language_combo_entries:
        lang = ""
        items["AlphabetButton"].Enabled = False
        return
    if index < 0 or index >= len(language_combo_entries):
        index = 0
    lang = language_combo_entries[index]["id"]
    is_simplified_chinese = lang.lower() in ("zh-cn", "zh-hans")
    items["AlphabetButton"].Enabled = is_simplified_chinese and is_using_azure_api()
    update_name_combo(saved_index=saved_voice_index, preserve_voice_id=preserve_voice_id)

def get_selected_voice_id() -> Optional[str]:
    index = items["NameCombo"].CurrentIndex
    if 0 <= index < len(current_name_entries):
        return current_name_entries[index]["id"]
    return None

def update_name_combo(saved_index: Optional[int] = None, preserve_voice_id: Optional[str] = None):
    global current_name_entries, is_updating_name_combo
    items["NameCombo"].Clear()
    current_name_entries = []
    reset_style_combo()
    reset_multilingual_combo()
    source = get_active_voice_source()
    locale_entry = source["language_map"].get(lang)
    if not locale_entry:
        return
    selected_type = get_selected_type_id()
    filtered = []
    for voice_entry in locale_entry["voices"]:
        gender = voice_entry.get("type", "")
        if not selected_type or (gender and gender.lower() == selected_type.lower()):
            filtered.append(voice_entry)
    current_name_entries = filtered
    for entry in filtered:
        items["NameCombo"].AddItem(get_label_text(entry["labels"]))
    if not filtered:
        return
    target_index = 0
    if saved_index is not None and 0 <= saved_index < len(filtered):
        target_index = saved_index
    elif preserve_voice_id:
        for idx, entry in enumerate(filtered):
            if entry["id"] == preserve_voice_id:
                target_index = idx
                break
    is_updating_name_combo = True
    items["NameCombo"].CurrentIndex = target_index
    is_updating_name_combo = False
    handle_name_selection_change(target_index)

def reset_style_combo():
    items["StyleCombo"].Clear()
    items["StyleCombo"].AddItem(get_default_label())
    items["StyleCombo"].Enabled = False
    items["StyleCombo"].CurrentIndex = 0

def reset_multilingual_combo():
    current_multilingual_codes.clear()
    items["MultilingualCombo"].Clear()
    items["MultilingualCombo"].AddItem(get_default_label())
    items["MultilingualCombo"].Enabled = False
    items["MultilingualCombo"].CurrentIndex = 0

def get_locale_label(code: str) -> str:
    entry = get_active_voice_source().get("locale_labels", {}).get(code, {})
    return build_label_pair(entry, code).get(get_ui_lang_key(), code)

def update_style_combo(voice_entry: Dict[str, Any]):
    reset_style_combo()
    styles = [style for style in voice_entry.get("styles", []) if style]
    if not styles or not is_using_azure_api():
        return
    style_map = STYLE_LABELS or {}
    items["StyleCombo"].Enabled = True
    for style_code in styles:
        label_entry = style_map.get(style_code, {})
        display_text = label_entry.get(get_ui_lang_key()) or label_entry.get("en") or label_entry.get("cn") or style_code
        items["StyleCombo"].AddItem(display_text)

def update_multilingual_combo(voice_entry: Dict[str, Any]):
    reset_multilingual_combo()
    codes = [code for code in voice_entry.get("multilingual", []) if code]
    if not codes or not is_using_azure_api():
        return
    seen = set()
    for code in codes:
        if code in seen:
            continue
        seen.add(code)
        current_multilingual_codes.append(code)
        items["MultilingualCombo"].AddItem(get_locale_label(code))
    if current_multilingual_codes:
        items["MultilingualCombo"].Enabled = True

def handle_name_selection_change(index: Optional[int] = None):
    if index is None:
        index = items["NameCombo"].CurrentIndex
    if not (0 <= index < len(current_name_entries)):
        reset_style_combo()
        reset_multilingual_combo()
        return
    voice_entry = current_name_entries[index]
    update_style_combo(voice_entry)
    update_multilingual_combo(voice_entry)

def get_selected_multilingual_code() -> Optional[str]:
    if items["MultilingualCombo"].CurrentIndex <= 0:
        return None
    inner_index = items["MultilingualCombo"].CurrentIndex - 1
    if 0 <= inner_index < len(current_multilingual_codes):
        return current_multilingual_codes[inner_index]
    return None

def get_selected_style_code() -> Optional[str]:
    text = items["StyleCombo"].CurrentText.strip()
    if not text or text == get_default_label():
        return None
    for code, labels in STYLE_LABELS.items():
        if text == labels.get("cn") or text == labels.get("en"):
            return code
    return text

def show_warning_message(status_tuple):
    use_english = items["LangEnCheckBox"].Checked
    message = status_tuple[0] if use_english else status_tuple[1]
    msgbox_items["InfoLabel"].Text = message
    msgbox.Show()

def on_msg_ok_clicked(ev):
    msgbox.Hide()   
msgbox.On.OkButton.Clicked = on_msg_ok_clicked

for tab_name in translations["cn"]["Tabs"]:
    items["MyTabs"].AddTab(tab_name)

def toggle_api_checkboxes(use_api_checked):
    azure_items["ApiKey"].Enabled = use_api_checked
    azure_items["Region"].Enabled = use_api_checked
    items["StyleCombo"].Enabled = use_api_checked
    items["MultilingualCombo"].Enabled = use_api_checked
    items["PlayButton"].Enabled = use_api_checked
    items["BreakButton"].Enabled = use_api_checked
    is_simplified_chinese = lang.lower() in ("zh-cn", "zh-hans") if lang else False
    items["AlphabetButton"].Enabled = use_api_checked and is_simplified_chinese
    items["StyleDegreeSpinBox"].Enabled = use_api_checked
    items["StyleDegreeSlider"].Enabled = use_api_checked
    print("Using Azure API" if use_api_checked else "Using EdgeTTS")


subtitle = ""
lang = ""
multilingual = None
ssml = ''
flag = True
voice_name = ""
style = None
rate = None
pitch = None
volume = None
style_degree = None
stream = None
minimax_voice_index_initialized = False
voice_modify_snapshot = None



# 加载Voice
minimax_voice_file = os.path.join(voices_dir, 'minimax_voices.json')
if not os.path.exists(minimax_voice_file):
    show_warning_message(STATUS_MESSAGES.voices_list)
openai_voice_file = os.path.join(voices_dir, 'openai_voices.json')
if not os.path.exists(openai_voice_file):
    show_warning_message(STATUS_MESSAGES.voices_list)

minimax_voice_data = load_json_file(minimax_voice_file, {})
openai_voice_data = load_json_file(openai_voice_file, {})
voice_file = minimax_voice_file

edge_voice_file = os.path.join(voices_dir, "edge_voices.json")
if not os.path.exists(edge_voice_file):
    show_warning_message(STATUS_MESSAGES.edge_voices)
edge_voice_list = load_json_file(edge_voice_file, [])

azure_voice_list_file = os.path.join(voices_dir, "azure_voices.json")
locale_labels_file = os.path.join(config_dir, "locale_labels.json")
style_labels_file = os.path.join(config_dir, "style_labels.json")

LOCALE_LABELS = load_json_file(locale_labels_file, {})
STYLE_LABELS = load_json_file(style_labels_file, {})
AZURE_FULL_VOICE_LIST = load_json_file(azure_voice_list_file, [])

OPENAI_VOICES = openai_voice_data.get("voices", [])
# 加载 EN 和 CN 两套语音和克隆语音
MINIMAX_VOICES_EN = minimax_voice_data.get("minimax_system_voice_en", [])
MINIMAX_VOICES_CN = minimax_voice_data.get("minimax_system_voice_cn", [])
MINIMAX_CLONE_VOICES_EN = minimax_voice_data.get("minimax_clone_voices_en", [])
MINIMAX_CLONE_VOICES_CN = minimax_voice_data.get("minimax_clone_voices_cn", [])

def is_intl_mode() -> bool:
    """检查是否使用国际版（EN）API"""
    return minimax_items["intlCheckBox"].Checked

def get_current_minimax_voices() -> list:
    """根据intlCheckBox状态返回当前使用的系统语音列表"""
    return MINIMAX_VOICES_EN if is_intl_mode() else MINIMAX_VOICES_CN

def get_current_minimax_clone_voices() -> list:
    """根据intlCheckBox状态返回当前使用的克隆语音列表"""
    return MINIMAX_CLONE_VOICES_EN if is_intl_mode() else MINIMAX_CLONE_VOICES_CN

def get_current_minimax_languages() -> list:
    """根据intlCheckBox状态返回当前使用的语言列表"""
    voices = get_current_minimax_voices()
    clones = get_current_minimax_clone_voices()
    return extract_minimax_languages(voices, clones)

# 初始化时使用CN版本（默认）
MINIMAX_VOICES = MINIMAX_VOICES_CN
MINIMAX_CLONE_VOICES = MINIMAX_CLONE_VOICES_CN
MINIMAX_LANGUAGES = extract_minimax_languages(MINIMAX_VOICES, MINIMAX_CLONE_VOICES)

AZURE_VOICE_SOURCE = build_azure_voice_source(AZURE_FULL_VOICE_LIST, LOCALE_LABELS, STYLE_LABELS)
EDGE_VOICE_SOURCE = build_azure_voice_source(edge_voice_list, LOCALE_LABELS, STYLE_LABELS)

OPENAI_PRESET_FILE = os.path.join(config_dir, 'instruction.json')

if not os.path.exists(OPENAI_PRESET_FILE):
    preset_data = {
        "Custom": {
            "Description": ""
        }
    }
else:
    with open(OPENAI_PRESET_FILE, "r", encoding="utf-8") as file:
        preset_data = json.load(file)

for preset_name in preset_data:
    items["OpenAIPresetCombo"].AddItem(preset_name)

# 选项变更时触发的函数
def on_openai_preset_combo_changed(event):
    # 获取当前选中的 preset 名称
    selected_preset = items["OpenAIPresetCombo"].CurrentText
    if selected_preset in preset_data:
        description = preset_data[selected_preset]["Description"]
        items["OpenAIInstructionText"].Text = description
    else:
        items["OpenAIInstructionText"].Text = "（未找到对应的描述）"
win.On["OpenAIPresetCombo"].CurrentIndexChanged = on_openai_preset_combo_changed

# 将每个子列表转换为元组
def return_voice_name(_name=None):
    return get_selected_voice_id()

for model in MINIMAX_MODELS:
    items["minimaxModelCombo"].AddItem(model)


for model in OPENAI_MODELS:
    items["OpenAIModelCombo"].AddItem(model)


for voice in OPENAI_VOICES:
    items["OpenAIVoiceCombo"].AddItem(voice)

def refresh_minimax_voice_combos():
    """根据intlCheckBox状态刷新MiniMax语言和语音下拉框"""
    global MINIMAX_VOICES, MINIMAX_CLONE_VOICES, MINIMAX_LANGUAGES
    
    # 获取当前使用的语音列表
    MINIMAX_VOICES = get_current_minimax_voices()
    MINIMAX_CLONE_VOICES = get_current_minimax_clone_voices()
    MINIMAX_LANGUAGES = get_current_minimax_languages()
    
    # 保存当前选择
    current_lang_text = items["minimaxLanguageCombo"].CurrentText
    current_voice_text = items["minimaxVoiceCombo"].CurrentText
    
    # 刷新语言下拉框
    items["minimaxLanguageCombo"].Clear()
    for lang_item in MINIMAX_LANGUAGES:
        items["minimaxLanguageCombo"].AddItem(lang_item)
    
    # 尝试恢复之前选择的语言（使用Python列表查找索引）
    lang_restored = False
    for idx, lang_item in enumerate(MINIMAX_LANGUAGES):
        if lang_item == current_lang_text:
            items["minimaxLanguageCombo"].CurrentIndex = idx
            lang_restored = True
            break
    if not lang_restored and len(MINIMAX_LANGUAGES) > 0:
        items["minimaxLanguageCombo"].CurrentIndex = 0
    
    # 刷新语音下拉框
    selected_lang = items["minimaxLanguageCombo"].CurrentText
    items["minimaxVoiceCombo"].Clear()
    
    # 构建当前语言的语音列表
    current_voice_list = []
    for voice in MINIMAX_CLONE_VOICES + MINIMAX_VOICES:
        if voice.get("language") == selected_lang:
            current_voice_list.append(voice["voice_name"])
            items["minimaxVoiceCombo"].AddItem(voice["voice_name"])
    
    # 尝试恢复之前选择的语音（使用Python列表查找索引）
    voice_restored = False
    for idx, voice_name in enumerate(current_voice_list):
        if voice_name == current_voice_text:
            items["minimaxVoiceCombo"].CurrentIndex = idx
            voice_restored = True
            break
    if not voice_restored and len(current_voice_list) > 0:
        items["minimaxVoiceCombo"].CurrentIndex = 0

def on_intl_checkbox_clicked(ev):
    """intlCheckBox状态变化时刷新语音列表"""
    refresh_minimax_voice_combos()
    mode = "EN (国际版)" if is_intl_mode() else "CN (国内版)"
    print(f"MiniMax API 切换到: {mode}")
minimax_config_window.On.intlCheckBox.Clicked = on_intl_checkbox_clicked

# 初始化时添加语言和语音
for lang_item in MINIMAX_LANGUAGES:
    items["minimaxLanguageCombo"].AddItem(lang_item)

def update_voice_list(ev):
    global minimax_voice_index_initialized
    selected_lang = items["minimaxLanguageCombo"].CurrentText
    items["minimaxVoiceCombo"].Clear()  
    # 只添加与 selected_lang 匹配的条目
    current_voices = get_current_minimax_voices()
    current_clones = get_current_minimax_clone_voices()
    for voice in current_clones + current_voices:
        if voice.get("language") == selected_lang:
            items["minimaxVoiceCombo"].AddItem(voice["voice_name"])
    # 只在第一次设置
    if not minimax_voice_index_initialized:
        items["minimaxVoiceCombo"].CurrentIndex = saved_settings.get(
            "minimax_Voice",
            DEFAULT_SETTINGS["minimax_Voice"]
        )
        minimax_voice_index_initialized = True
win.On["minimaxLanguageCombo"].CurrentIndexChanged = update_voice_list         


for cn, en in MINIMAX_EMOTIONS:
    if items["LangEnCheckBox"].Checked:
        items["minimaxEmotionCombo"].AddItem(en)  
    else:
        items["minimaxEmotionCombo"].AddItem(cn)  

populate_sound_effect_combo(items["LangEnCheckBox"].Checked)

"""
def on_minimax_model_combo_changed(event):
    selected_model = items["minimaxModelCombo"].CurrentText
    if selected_model in [ "speech-01-240228","speech-01-turbo-240228",]:
        items["minimaxEmotionCombo"].CurrentIndex = 0
        items["minimaxEmotionCombo"].Enabled = False  
    else:
        items["minimaxEmotionCombo"].Enabled = True  
    if selected_model in ["speech-02-hd","speech-02-turbo","speech-01-hd","speech-01-turbo",]:
        items["minimaxSubtitleCheckBox"].Enabled = True
    else:
        items["minimaxSubtitleCheckBox"].Checked = False
        items["minimaxSubtitleCheckBox"].Enabled = False

win.On["minimaxModelCombo"].CurrentIndexChanged = on_minimax_model_combo_changed
"""
def on_openai_model_combo_changed(event):
    selected_model = items["OpenAIModelCombo"].CurrentText
    if selected_model not in ["tts-1", "tts-1-hd"]:
        items["OpenAIInstructionText"].PlaceholderText = ""
        items["OpenAIInstructionText"].Enabled = True  
        items["OpenAIPresetCombo"].Enabled = True  
    else:
        items["OpenAIInstructionText"].PlaceholderText = "Does not work with tts-1 or tts-1-hd."
        items["OpenAIInstructionText"].Enabled = False
        items["OpenAIPresetCombo"].CurrentIndex = 0    
        items["OpenAIPresetCombo"].Enabled = False  

win.On["OpenAIModelCombo"].CurrentIndexChanged = on_openai_model_combo_changed
# 在启动时检查模型状态
#on_minimax_model_combo_changed({"Index": items["minimaxModelCombo"].CurrentIndex})
on_openai_model_combo_changed({"Index": items["OpenAIModelCombo"].CurrentIndex})


def switch_language(lang):
    """
    根据 lang (可取 'cn' 或 'en') 切换所有控件的文本
    """
    previous_locale = lang
    previous_voice_id = get_selected_voice_id()
    previous_type = get_selected_type_id()
    current_emotion_code = get_selected_minimax_emotion_code()
    current_sound_effect_code = get_selected_sound_effect_code()
    items["minimaxEmotionCombo"].Clear()

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
        elif item_id in minimax_items:    
            minimax_items[item_id].Text = text_value
        elif item_id in openai_items:    
            openai_items[item_id].Text = text_value
        elif item_id in minimax_clone_items:    
            minimax_clone_items[item_id].Text = text_value
        elif item_id in minimax_voice_modify_items:
            minimax_voice_modify_items[item_id].Text = text_value
        else:
            print(f"[Warning] items 中不存在 ID 为 {item_id} 的控件，无法设置文本！")

    checked = items["LangEnCheckBox"].Checked
    for cn, en in MINIMAX_EMOTIONS:
        items["minimaxEmotionCombo"].AddItem(en if checked else cn)
    set_minimax_emotion_by_code(current_emotion_code)
    populate_sound_effect_combo(checked, preserved_code=current_sound_effect_code)
    refresh_type_combo(preserve_type=previous_type)
    refresh_language_combo(preserve_locale=previous_locale, preserve_voice_id=previous_voice_id)

def on_lang_checkbox_clicked(ev):
    is_en_checked = ev['sender'].ID == "LangEnCheckBox"
    items["LangCnCheckBox"].Checked = not is_en_checked
    items["LangEnCheckBox"].Checked = is_en_checked
    switch_language("en" if is_en_checked else "cn")

win.On.LangCnCheckBox.Clicked = on_lang_checkbox_clicked
win.On.LangEnCheckBox.Clicked = on_lang_checkbox_clicked

# 从保存的设置中设置 UseAPICheckBox 的状态
if saved_settings:
    azure_items["UseAPICheckBox"].Checked = saved_settings.get("USE_API", DEFAULT_SETTINGS["USE_API"])
    items["LangCnCheckBox"].Checked = saved_settings.get("CN", DEFAULT_SETTINGS["CN"])
    items["LangEnCheckBox"].Checked = saved_settings.get("EN", DEFAULT_SETTINGS["EN"])

if items["LangEnCheckBox"].Checked :
    switch_language("en")
else:
    switch_language("cn")


audio_formats = {
    "mp3": speechsdk.SpeechSynthesisOutputFormat.Audio48Khz96KBitRateMonoMp3,
    "wav": speechsdk.SpeechSynthesisOutputFormat.Riff48Khz16BitMonoPcm,
}

for fmt in audio_formats.keys():
    items["OutputFormatCombo"].AddItem(fmt)

initial_language_index = DEFAULT_SETTINGS["LANGUAGE"]
initial_type_index = DEFAULT_SETTINGS["TYPE"]
initial_voice_index = DEFAULT_SETTINGS["NAME"]

if saved_settings:
    azure_items["ApiKey"].Text = saved_settings.get("API_KEY", DEFAULT_SETTINGS["API_KEY"])
    azure_items["Region"].Text = saved_settings.get("REGION", DEFAULT_SETTINGS["REGION"])
    initial_language_index = saved_settings.get("LANGUAGE", initial_language_index)
    initial_type_index = saved_settings.get("TYPE", initial_type_index)
    initial_voice_index = saved_settings.get("NAME", initial_voice_index)
    items["RateSpinBox"].Value = saved_settings.get("RATE", DEFAULT_SETTINGS["RATE"])
    items["PitchSpinBox"].Value = saved_settings.get("PITCH", DEFAULT_SETTINGS["PITCH"])
    items["VolumeSpinBox"].Value = saved_settings.get("VOLUME", DEFAULT_SETTINGS["VOLUME"])
    items["StyleDegreeSpinBox"].Value = saved_settings.get("STYLEDEGREE", DEFAULT_SETTINGS["STYLEDEGREE"])
    saved_format_index = saved_settings.get("OUTPUT_FORMATS", DEFAULT_SETTINGS["OUTPUT_FORMATS"])
    max_format_index = max(len(audio_formats) - 1, 0)
    items["OutputFormatCombo"].CurrentIndex = max(0, min(saved_format_index, max_format_index))

    minimax_items["minimaxApiKey"].Text = saved_settings.get("minimax_API_KEY", DEFAULT_SETTINGS["minimax_API_KEY"])
    minimax_items["minimaxGroupID"].Text = saved_settings.get("minimax_GROUP_ID", DEFAULT_SETTINGS["minimax_GROUP_ID"])
    minimax_items["intlCheckBox"].Checked = saved_settings.get("minimax_intlCheckBox", DEFAULT_SETTINGS["minimax_intlCheckBox"])
    # 根据intlCheckBox状态刷新语音列表
    refresh_minimax_voice_combos()
    items["Path"].Text = saved_settings.get("Path", DEFAULT_SETTINGS["Path"])
    items["minimaxModelCombo"].CurrentIndex = saved_settings.get("minimax_Model", DEFAULT_SETTINGS["minimax_Model"])
    items["minimaxLanguageCombo"].CurrentIndex= saved_settings.get("minimax_Language", DEFAULT_SETTINGS["minimax_Language"])
    items["minimaxVoiceCombo"].CurrentIndex= saved_settings.get("minimax_Voice", DEFAULT_SETTINGS["minimax_Voice"])
    items["minimaxSubtitleCheckBox"].Checked = saved_settings.get("minimax_SubtitleCheckBox", DEFAULT_SETTINGS["minimax_SubtitleCheckBox"])
    items["minimaxEmotionCombo"].CurrentIndex = saved_settings.get("minimax_Emotion", DEFAULT_SETTINGS["minimax_Emotion"])
    items["minimaxRateSpinBox"].Value = saved_settings.get("minimax_Rate", DEFAULT_SETTINGS["minimax_Rate"])
    items["minimaxVolumeSpinBox"].Value = saved_settings.get("minimax_Volume", DEFAULT_SETTINGS["minimax_Volume"])
    items["minimaxPitchSpinBox"].Value = saved_settings.get("minimax_Pitch", DEFAULT_SETTINGS["minimax_Pitch"])
    
    openai_items["OpenAIApiKey"].Text = saved_settings.get("OpenAI_API_KEY", DEFAULT_SETTINGS["OpenAI_API_KEY"])
    openai_items["OpenAIBaseURL"].Text = saved_settings.get("OpenAI_BASE_URL", DEFAULT_SETTINGS["OpenAI_BASE_URL"])    
    items["OpenAIModelCombo"].CurrentIndex = saved_settings.get("OpenAI_Model", DEFAULT_SETTINGS["OpenAI_Model"])
    items["OpenAIVoiceCombo"].CurrentIndex= saved_settings.get("OpenAI_Voice", DEFAULT_SETTINGS["OpenAI_Voice"])
    items["OpenAIPresetCombo"].CurrentIndex = saved_settings.get("OpenAI_Preset", DEFAULT_SETTINGS["OpenAI_Preset"])
    items["OpenAIRateSpinBox"].Value = saved_settings.get("OpenAI_Rate", DEFAULT_SETTINGS["OpenAI_Rate"])
    items["OpenAIInstructionText"].Text = saved_settings.get("OpenAI_Instruction", DEFAULT_SETTINGS["OpenAI_Instruction"])
else:
    items["OutputFormatCombo"].CurrentIndex = DEFAULT_SETTINGS["OUTPUT_FORMATS"]

refresh_type_combo(saved_index=initial_type_index)
refresh_language_combo(saved_index=initial_language_index, saved_voice_index=initial_voice_index)
if saved_settings:
    items["StyleCombo"].CurrentIndex = saved_settings.get("STYLE", DEFAULT_SETTINGS["STYLE"])

def flagmark():
    global flag
    flag = True
def on_outputformat_combo_current_index_changed(ev):
    flagmark()
win.On.OutputFormatCombo.CurrentIndexChanged = on_outputformat_combo_current_index_changed

def on_multilingual_combo_current_index_changed(ev):
    flagmark()
win.On.MultilingualCombo.CurrentIndexChanged = on_multilingual_combo_current_index_changed

def on_style_combo_current_index_changed(ev):
    flagmark()
win.On.StyleCombo.CurrentIndexChanged = on_style_combo_current_index_changed


# 定义一个通用的更新函数
def handle_value_change(ev, last_update_time, update_interval, from_widget, to_widget, multiplier=1.0):
    current_time = time.time()
    if current_time - last_update_time < update_interval:
        return last_update_time
    flagmark()
    value = round(ev['Value'] * multiplier, 2)
    items[to_widget].Value = value
    return current_time

# 定义全局变量
last_updates = {
    "style_degree": 0,
    "rate": 0,
    "pitch": 0,
    "volume": 0
}
update_intervals = {
    "style_degree": 0.1,
    "rate": 0.1,
    "pitch": 0.1,
    "volume": 0.1
}
VOICE_MODIFY_WIDGETS = {
    "timbre": ("minimaxTimbreSpinBoxLeft", "minimaxTimbreSlider", "minimaxTimbreSpinBoxRight"),
    "intensity": ("minimaxIntensitySpinBoxLeft", "minimaxIntensitySlider", "minimaxIntensitySpinBoxRight"),
    "pitch": ("minimaxModifyPitchSpinBoxLeft", "minimaxModifyPitchSlider", "minimaxModifyPitchSpinBoxRight"),
}
voice_modify_last_updates = {k: 0 for k in VOICE_MODIFY_WIDGETS}
VOICE_MODIFY_UPDATE_INTERVAL = 0.1

def clamp_voice_modify_value(value: float) -> int:
    low, high = MINIMAX_VOICE_MODIFY_RANGE
    return max(low, min(high, int(round(value))))

def update_voice_modify_widgets(name: str, value: int):
    left_id, slider_id, right_id = VOICE_MODIFY_WIDGETS[name]
    minimax_voice_modify_items[slider_id].Value = value
    minimax_voice_modify_items[left_id].Value = value if value < 0 else 0
    minimax_voice_modify_items[right_id].Value = value if value > 0 else 0

def set_voice_modify_value(name: str, value: float):
    clamped = clamp_voice_modify_value(value)
    update_voice_modify_widgets(name, clamped)
    voice_modify_last_updates[name] = time.time()

def sync_voice_modify_value(name: str, sender_id: str, value: float):
    now = time.time()
    if now - voice_modify_last_updates[name] < VOICE_MODIFY_UPDATE_INTERVAL:
        return
    flagmark()
    clamped = clamp_voice_modify_value(value)
    voice_modify_last_updates[name] = now
    update_voice_modify_widgets(name, clamped)

def get_voice_modify_state() -> Dict[str, Any]:
    return {
        "timbre": minimax_voice_modify_items["minimaxTimbreSlider"].Value,
        "intensity": minimax_voice_modify_items["minimaxIntensitySlider"].Value,
        "pitch": minimax_voice_modify_items["minimaxModifyPitchSlider"].Value,
        "sound_effect": get_selected_sound_effect_code(),
    }

def apply_voice_modify_state(state: Dict[str, Any]):
    set_voice_modify_value("timbre", state.get("timbre", 0))
    set_voice_modify_value("intensity", state.get("intensity", 0))
    set_voice_modify_value("pitch", state.get("pitch", 0))
    set_sound_effect_by_code(state.get("sound_effect", MINIMAX_SOUND_EFFECTS[0][1]))

def load_voice_modify_from_settings(settings: Dict[str, Any]):
    if settings is None:
        settings = {}
    state = {
        "timbre": settings.get("minimaxVoiceTimbre", DEFAULT_SETTINGS["minimaxVoiceTimbre"]),
        "intensity": settings.get("minimaxVoiceIntensity", DEFAULT_SETTINGS["minimaxVoiceIntensity"]),
        "pitch": settings.get("minimaxVoicePitch", DEFAULT_SETTINGS["minimaxVoicePitch"]),
        "sound_effect": get_sound_effect_code_by_index(
            settings.get("minimaxVoiceEffect", DEFAULT_SETTINGS["minimaxVoiceEffect"])
        ),
    }
    apply_voice_modify_state(state)

# 音色效果 Slider 和 SpinBox 事件处理
def on_minimax_timbre_slider_value_changed(ev):
    sync_voice_modify_value("timbre", "minimaxTimbreSlider", ev["Value"])
minimax_voice_modify_window.On.minimaxTimbreSlider.ValueChanged = on_minimax_timbre_slider_value_changed

def on_minimax_timbre_spinbox_left_value_changed(ev):
    sync_voice_modify_value("timbre", "minimaxTimbreSpinBoxLeft", ev["Value"])
minimax_voice_modify_window.On.minimaxTimbreSpinBoxLeft.ValueChanged = on_minimax_timbre_spinbox_left_value_changed

def on_minimax_timbre_spinbox_right_value_changed(ev):
    sync_voice_modify_value("timbre", "minimaxTimbreSpinBoxRight", ev["Value"])
minimax_voice_modify_window.On.minimaxTimbreSpinBoxRight.ValueChanged = on_minimax_timbre_spinbox_right_value_changed

def on_minimax_intensity_slider_value_changed(ev):
    sync_voice_modify_value("intensity", "minimaxIntensitySlider", ev["Value"])
minimax_voice_modify_window.On.minimaxIntensitySlider.ValueChanged = on_minimax_intensity_slider_value_changed

def on_minimax_intensity_spinbox_left_value_changed(ev):
    sync_voice_modify_value("intensity", "minimaxIntensitySpinBoxLeft", ev["Value"])
minimax_voice_modify_window.On.minimaxIntensitySpinBoxLeft.ValueChanged = on_minimax_intensity_spinbox_left_value_changed

def on_minimax_intensity_spinbox_right_value_changed(ev):
    sync_voice_modify_value("intensity", "minimaxIntensitySpinBoxRight", ev["Value"])
minimax_voice_modify_window.On.minimaxIntensitySpinBoxRight.ValueChanged = on_minimax_intensity_spinbox_right_value_changed

def on_minimax_modify_pitch_slider_value_changed(ev):
    sync_voice_modify_value("pitch", "minimaxModifyPitchSlider", ev["Value"])
minimax_voice_modify_window.On.minimaxModifyPitchSlider.ValueChanged = on_minimax_modify_pitch_slider_value_changed

def on_minimax_modify_pitch_spinbox_left_value_changed(ev):
    sync_voice_modify_value("pitch", "minimaxModifyPitchSpinBoxLeft", ev["Value"])
minimax_voice_modify_window.On.minimaxModifyPitchSpinBoxLeft.ValueChanged = on_minimax_modify_pitch_spinbox_left_value_changed

def on_minimax_modify_pitch_spinbox_right_value_changed(ev):
    sync_voice_modify_value("pitch", "minimaxModifyPitchSpinBoxRight", ev["Value"])
minimax_voice_modify_window.On.minimaxModifyPitchSpinBoxRight.ValueChanged = on_minimax_modify_pitch_spinbox_right_value_changed

load_voice_modify_from_settings(saved_settings)

# 速率 Slider 和 SpinBox 事件处理
def on_minimax_rate_slider_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "minimaxRateSlider", "minimaxRateSpinBox", 1/100.0)
win.On.minimaxRateSlider.ValueChanged = on_minimax_rate_slider_value_changed

def on_minimax_rate_spinbox_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "minimaxRateSpinBox", "minimaxRateSlider", 100)
win.On.minimaxRateSpinBox.ValueChanged = on_minimax_rate_spinbox_value_changed

# 速率 Slider 和 SpinBox 事件处理
def on_openai_rate_slider_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "OpenAIRateSlider", "OpenAIRateSpinBox", 1/100.0)
win.On.OpenAIRateSlider.ValueChanged = on_openai_rate_slider_value_changed

def on_openai_rate_spinbox_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "OpenAIRateSpinBox", "OpenAIRateSlider", 100)
win.On.OpenAIRateSpinBox.ValueChanged = on_openai_rate_spinbox_value_changed

# 音调 Slider 和 SpinBox 事件处理
def on_minimax_pitch_slider_value_changed(ev):
    last_updates["pitch"] = handle_value_change(ev, last_updates["pitch"], update_intervals["pitch"], "minimaxPitchSlider", "minimaxPitchSpinBox", 1/100.0)
win.On.minimaxPitchSlider.ValueChanged = on_minimax_pitch_slider_value_changed

def on_minimax_pitch_spinbox_value_changed(ev):
    last_updates["pitch"] = handle_value_change(ev, last_updates["pitch"], update_intervals["pitch"], "minimaxPitchSpinBox", "minimaxPitchSlider", 100)
win.On.minimaxPitchSpinBox.ValueChanged = on_minimax_pitch_spinbox_value_changed

# 音量 Slider 和 SpinBox 事件处理
def on_minimax_volume_slider_value_changed(ev):
    last_updates["volume"] = handle_value_change(ev, last_updates["volume"], update_intervals["volume"], "minimaxVolumeSlider", "minimaxVolumeSpinBox", 1/100.0)
win.On.minimaxVolumeSlider.ValueChanged = on_minimax_volume_slider_value_changed

def on_minimax_volume_spinbox_value_changed(ev):
    last_updates["volume"] = handle_value_change(ev, last_updates["volume"], update_intervals["volume"], "minimaxVolumeSpinBox", "minimaxVolumeSlider", 100)
win.On.minimaxVolumeSpinBox.ValueChanged = on_minimax_volume_spinbox_value_changed

# 样式度 Slider 和 SpinBox 事件处理
def on_style_degree_slider_value_changed(ev):
    last_updates["style_degree"] = handle_value_change(ev, last_updates["style_degree"], update_intervals["style_degree"], "StyleDegreeSlider", "StyleDegreeSpinBox", 1/100.0)
win.On.StyleDegreeSlider.ValueChanged = on_style_degree_slider_value_changed

def on_style_degree_spinbox_value_changed(ev):
    last_updates["style_degree"] = handle_value_change(ev, last_updates["style_degree"], update_intervals["style_degree"], "StyleDegreeSpinBox", "StyleDegreeSlider", 100)
win.On.StyleDegreeSpinBox.ValueChanged = on_style_degree_spinbox_value_changed

# 速率 Slider 和 SpinBox 事件处理
def on_rate_slider_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "RateSlider", "RateSpinBox", 1/100.0)
win.On.RateSlider.ValueChanged = on_rate_slider_value_changed

def on_rate_spinbox_value_changed(ev):
    last_updates["rate"] = handle_value_change(ev, last_updates["rate"], update_intervals["rate"], "RateSpinBox", "RateSlider", 100)
win.On.RateSpinBox.ValueChanged = on_rate_spinbox_value_changed

# 音调 Slider 和 SpinBox 事件处理
def on_pitch_slider_value_changed(ev):
    last_updates["pitch"] = handle_value_change(ev, last_updates["pitch"], update_intervals["pitch"], "PitchSlider", "PitchSpinBox", 1/100.0)
win.On.PitchSlider.ValueChanged = on_pitch_slider_value_changed

def on_pitch_spinbox_value_changed(ev):
    last_updates["pitch"] = handle_value_change(ev, last_updates["pitch"], update_intervals["pitch"], "PitchSpinBox", "PitchSlider", 100)
win.On.PitchSpinBox.ValueChanged = on_pitch_spinbox_value_changed

# 音量 Slider 和 SpinBox 事件处理
def on_volume_slider_value_changed(ev):
    last_updates["volume"] = handle_value_change(ev, last_updates["volume"], update_intervals["volume"], "VolumeSlider", "VolumeSpinBox", 1/100.0)
win.On.VolumeSlider.ValueChanged = on_volume_slider_value_changed

def on_volume_spinbox_value_changed(ev):
    last_updates["volume"] = handle_value_change(ev, last_updates["volume"], update_intervals["volume"], "VolumeSpinBox", "VolumeSlider", 100)
win.On.VolumeSpinBox.ValueChanged = on_volume_spinbox_value_changed

def on_my_tabs_current_changed(ev):
    items["MyStack"].CurrentIndex = ev["Index"]
win.On.MyTabs.CurrentChanged = on_my_tabs_current_changed

def on_subtitle_text_changed(ev):
    flagmark()
    global stream
    stream = None
win.On.AzureTxt.TextChanged = on_subtitle_text_changed

def on_minimax_only_add_id_checkbox_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()

    if not current_timeline:
        print("❌ 当前没有打开的时间线。")
        return

    checked = minimax_clone_items["minimaxOnlyAddID"].Checked
    en_checked = items["LangEnCheckBox"].Checked
    marker_frame = 0
    #print(marker_frame)
    marker_name = "Clone Marker" if en_checked else "克隆标记" 
    marker_note = "Drag the marker points to define the range for clone audio, which should be greater than 10 seconds and less than 5 minutes." if en_checked else"拖拽Mark点范围确定克隆音频的范围，大于10s，小于5分钟"
    marker_date = "clone"
    marker_color = "Red"
    marker_duration = 250
    if checked:
        success = current_timeline.DeleteMarkerByCustomData(marker_date)
        print("✅ Marker removed successfully!" if success else "❌ Failed to remove marker, please remove it manually")
    else:
        current_timeline.DeleteMarkerAtFrame(marker_frame)
        success = current_timeline.AddMarker(
            marker_frame,
            marker_color,
            marker_name,
            marker_note,
            marker_duration,
            marker_date
        )
        print("✅ Marker added successfully!" if success else "❌ Failed to add marker, please check if the frameId or other parameters are correct.")

    # 批量处理控件启用状态
    for key in ["minimaxNeedNoiseReduction", "minimaxNeedVolumeNormalization", "minimaxClonePreviewText"]:
        minimax_clone_items[key].Enabled = not checked

    # 设置按钮文本
    minimax_clone_items["MiniMaxCloneConfirm"].Text = ("Add" if checked else "Clone") if items["LangEnCheckBox"].Checked else ("添加" if checked else "克隆")
minimax_clone_window.On.minimaxOnlyAddID.Clicked = on_minimax_only_add_id_checkbox_clicked

def on_useapi_checkbox_clicked(ev):
    previous_locale = lang
    previous_voice_id = get_selected_voice_id()
    previous_type = get_selected_type_id()
    toggle_api_checkboxes(azure_items["UseAPICheckBox"].Checked)
    refresh_type_combo(preserve_type=previous_type)
    refresh_language_combo(preserve_locale=previous_locale, preserve_voice_id=previous_voice_id)
    
azure_config_window.On.UseAPICheckBox.Clicked = on_useapi_checkbox_clicked

def on_language_combo_current_index_changed(ev):
    flagmark()
    if is_updating_language_combo:
        return
    index = ev["Index"] if isinstance(ev, dict) and "Index" in ev else items["LanguageCombo"].CurrentIndex
    handle_language_selection_change(index)
    
win.On.LanguageCombo.CurrentIndexChanged = on_language_combo_current_index_changed

def on_name_combo_current_index_changed(ev):
    flagmark()
    if is_updating_name_combo:
        return
    index = ev["Index"] if isinstance(ev, dict) and "Index" in ev else items["NameCombo"].CurrentIndex
    handle_name_selection_change(index)
win.On.NameCombo.CurrentIndexChanged = on_name_combo_current_index_changed

def on_name_type_combo_current_index_changed(ev):
    flagmark()
    if is_updating_type_combo:
        return
    index = ev["Index"] if isinstance(ev, dict) and "Index" in ev else items["NameTypeCombo"].CurrentIndex
    handle_voice_type_change(index)
    
win.On.NameTypeCombo.CurrentIndexChanged = on_name_type_combo_current_index_changed


toggle_api_checkboxes(azure_items["UseAPICheckBox"].Checked)

##frame_rate = float(current_project.GetSetting("timelineFrameRate"))

def get_subtitles(timeline):
    subtitles = []
    track_count = timeline.GetTrackCount("subtitle")
    print(f"Subtitle track count: {track_count}")

    for track_index in range(1, track_count + 1):
        track_enabled = timeline.GetIsTrackEnabled("subtitle", track_index)
        if track_enabled:
            subtitleTrackItems = timeline.GetItemListInTrack("subtitle", track_index)
            for item in subtitleTrackItems:
                try:
                    start_frame = item.GetStart()
                    end_frame = item.GetEnd()
                    text = item.GetName()
                    subtitles.append({'start': start_frame, 'end': end_frame, 'text': text})
                except Exception as e:
                    print(f"Error processing item: {e}")

    return subtitles

def get_subtitle_texts(subtitles):
    return "\n".join([subtitle['text'] for subtitle in subtitles])

def frame_to_timecode(frame, framerate):
    total_seconds = frame / framerate
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = int(total_seconds % 60)
    milliseconds = int((total_seconds % 1) * 1000)
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"

def timecode_to_frames(timecode, frame_rate):
    """
    将时间码转换为帧数。
    参数：
    - timecode: 格式为 'hh:mm:ss;ff' 或 'hh:mm:ss:ff' 的时间码。
    - frame_rate: 时间线的帧率。
    返回值：
    - 对应时间码的帧数。
    """
    try:
        # 提取时间组件
        match = re.match(r"^(\d{2}):(\d{2}):(\d{2})([:;])(\d{2,3})$", timecode)
        if not match:
            raise ValueError(f"Invalid timecode format: {timecode}")
        
        hours, minutes, seconds, separator, frames = match.groups()
        hours = int(hours)
        minutes = int(minutes)
        seconds = int(seconds)
        frames = int(frames)
        
        is_drop_frame = separator == ';'
        
        if is_drop_frame:
            # 计算名义帧率和丢帧数
            if frame_rate in [23.976, 29.97, 59.94, 119.88]:
                nominal_frame_rate = round(frame_rate * 1000 / 1001)
                drop_frames = int(round(nominal_frame_rate / 15))
            else:
                raise ValueError(f"Unsupported drop frame rate: {frame_rate}")

            # 总分钟数
            total_minutes = hours * 60 + minutes

            # 计算总的丢帧数
            total_dropped_frames = drop_frames * (total_minutes - total_minutes // 10)

            # 计算总帧数
            frame_count = ((hours * 3600) + (minutes * 60) + seconds) * nominal_frame_rate + frames
            frame_count -= total_dropped_frames

        else:
            # 非丢帧时间码
            if frame_rate in [23.976, 29.97, 47.952, 59.94, 95.904, 119.88]:
                nominal_frame_rate = round(frame_rate * 1000 / 1001)
            else:
                nominal_frame_rate = frame_rate

            frame_count = ((hours * 3600) + (minutes * 60) + seconds) * nominal_frame_rate + frames

        return frame_count

    except ValueError as e:
        print(f"Error converting timecode to frames: {e}")
        return None


def print_srt(subtitles, framerate):
    for index, subtitle in enumerate(subtitles):
        start_time = frame_to_timecode(subtitle['start'], framerate)
        end_time = frame_to_timecode(subtitle['end'], framerate)
        print(f"{index + 1}\n{start_time} --> {end_time}\n{subtitle['text']}\n")


def print_text_on_box(text):
    items['AzureTxt'].PlainText = text
    items['minimaxText'].PlainText = text
    items['OpenAIText'].PlainText = text

def on_getsub_button_clicked(ev):
    frame_rate = float(current_project.GetSetting("timelineFrameRate"))
    subtitles = get_subtitles(current_timeline)
    subtitle_texts = get_subtitle_texts(subtitles)
    items["AzureTxt"].Text = subtitle_texts
    items["minimaxText"].Text = subtitle_texts
    items["OpenAIText"].Text = subtitle_texts
    print_srt(subtitles,frame_rate)
win.On.GetSubButton.Clicked = on_getsub_button_clicked
win.On.minimaxGetSubButton.Clicked = on_getsub_button_clicked
win.On.OpenAIGetSubButton.Clicked = on_getsub_button_clicked
#============== Azure ====================#
def process_text_with_breaks(parent, text):
    parts = text.split('<break')
    for i, part in enumerate(parts):
        if i == 0:
            handle_phoneme_and_text(parent, part.strip(), is_initial=True)
        else:
            end_idx = part.find('>')
            if end_idx != -1:
                break_tag = '<break' + part[:end_idx + 1]
                remaining_text = part[end_idx + 1:].strip()
                
                break_elem = ET.fromstring(break_tag)
                parent.append(break_elem)
                
                handle_phoneme_and_text(parent, remaining_text)

def handle_phoneme_and_text(parent, text, is_initial=False):
    phoneme_parts = text.split('<phoneme')
    for j, phoneme_part in enumerate(phoneme_parts):
        if j == 0:
            if is_initial:
                if parent.text:
                    parent.text += phoneme_part.strip()
                else:
                    parent.text = phoneme_part.strip()
            else:
                if parent[-1].tail:
                    parent[-1].tail += phoneme_part.strip()
                else:
                    parent[-1].tail = phoneme_part.strip()
        else:
            end_phoneme_idx = phoneme_part.find('</phoneme>')
            if end_phoneme_idx != -1:
                phoneme_end_tag = '</phoneme>'
                phoneme_start_idx = phoneme_part.find('>') + 1
                phoneme_tag = '<phoneme' + phoneme_part[:phoneme_start_idx]
                remaining_text = phoneme_part[phoneme_start_idx:end_phoneme_idx]
                tail_text = phoneme_part[end_phoneme_idx + len(phoneme_end_tag):].strip()
                
                phoneme_elem = ET.fromstring(phoneme_tag + remaining_text + phoneme_end_tag)
                parent.append(phoneme_elem)
                
                if tail_text:
                    if phoneme_elem.tail:
                        phoneme_elem.tail += tail_text
                    else:
                        phoneme_elem.tail = tail_text
            else:
                if parent[-1].tail:
                    parent[-1].tail += phoneme_part.strip()
                else:
                    parent[-1].tail = phoneme_part.strip()

def create_ssml(lang, voice_name, text, rate=None, pitch=None, volume=None, style=None, styledegree=None, multilingual = None):
    speak = ET.Element('speak', xmlns="http://www.w3.org/2001/10/synthesis", attrib={
        "xmlns:mstts": "http://www.w3.org/2001/mstts",
        "xmlns:emo": "http://www.w3.org/2009/10/emotionml",
        "version": "1.0",
        "xml:lang": f"{lang}"
    })
    voice = ET.SubElement(speak, 'voice', name=voice_name)
    if multilingual != None:
        lang_tag = ET.SubElement(voice, 'lang', attrib={"xml:lang": multilingual})
        parent_tag = lang_tag
    else:
        parent_tag = voice
    lines = text.split('\n')
    for line in lines:
        if line.strip():
            paragraph = ET.SubElement(parent_tag, 's')
            if style:
                express_as_attribs = {'style': style}
                if styledegree is not None and styledegree != 1.0:
                    express_as_attribs['styledegree'] = f"{styledegree:.2f}"
                express_as = ET.SubElement(paragraph, 'mstts:express-as', attrib=express_as_attribs)
                prosody_attrs = {}
                if rate is not None and rate != 1.0:
                    prosody_rate = f"+{(rate-1)*100:.2f}%" if rate > 1 else f"-{(1-rate)*100:.2f}%"
                    prosody_attrs['rate'] = prosody_rate
                if pitch is not None and pitch != 1.0:
                    prosody_pitch = f"+{(pitch-1)*100:.2f}%" if pitch > 1 else f"-{(1-pitch)*100:.2f}%"
                    prosody_attrs['pitch'] = prosody_pitch
                if volume is not None and volume != 1.0:
                    prosody_volume = f"+{(volume-1)*100:.2f}%" if volume > 1 else f"-{(1-volume)*100:.2f}%"
                    prosody_attrs['volume'] = prosody_volume
                if prosody_attrs:
                    prosody = ET.SubElement(express_as, 'prosody', attrib=prosody_attrs)
                    process_text_with_breaks(prosody, line.strip())
                else:
                    process_text_with_breaks(express_as, line.strip())
            else:
                prosody_attrs = {}
                if rate is not None and rate != 1.0:
                    prosody_rate = f"+{(rate-1)*100:.2f}%" if rate > 1 else f"-{(1-rate)*100:.2f}%"
                    prosody_attrs['rate'] = prosody_rate
                if pitch is not None and pitch != 1.0:
                    prosody_pitch = f"+{(pitch-1)*100:.2f}%" if pitch > 1 else f"-{(1-pitch)*100:.2f}%"
                    prosody_attrs['pitch'] = prosody_pitch
                if volume is not None and volume != 1.0:
                    prosody_volume = f"+{(volume-1)*100:.2f}%" if volume > 1 else f"-{(1-volume)*100:.2f}%"
                    prosody_attrs['volume'] = prosody_volume
                if prosody_attrs:
                    prosody = ET.SubElement(paragraph, 'prosody', attrib=prosody_attrs)
                    process_text_with_breaks(prosody, line.strip())
                else:
                    process_text_with_breaks(paragraph, line.strip())
        if multilingual:
            parent_tag.tail = "\n"
    return format_xml(ET.tostring(speak, encoding='unicode'))

def format_xml(xml_string):
    parsed = minidom.parseString(xml_string)
    pretty_xml_as_string = parsed.toprettyxml(indent="", newl="")
    pretty_xml_as_string = ''.join([line for line in pretty_xml_as_string.split('\n') if line.strip()])
    return pretty_xml_as_string

def get_current_subtitle(current_timeline):
    frame_rate = float(current_timeline.GetSetting("timelineFrameRate"))
    current_timecode = current_timeline.GetCurrentTimecode()  
    current_frame = timecode_to_frames(current_timecode, frame_rate)

    track_count = current_timeline.GetTrackCount("subtitle")
    if not track_count or track_count < 1:
        return None, current_frame, current_frame

    # Resolve subtitle track index grows from bottom to top; scan from topmost track first.
    for track_index in range(track_count, 0, -1):
        if not current_timeline.GetIsTrackEnabled("subtitle", track_index):
            continue
        items = current_timeline.GetItemListInTrack("subtitle", track_index) or []
        for item in items:
            start_frame = item.GetStart()
            end_frame = item.GetEnd()
            if start_frame is not None and end_frame is not None and start_frame <= current_frame <= end_frame:
                return item.GetName(), start_frame, end_frame

    return None, current_frame, current_frame

def generate_filename(base_path, subtitle, extension):
    if not os.path.exists(base_path):
        os.makedirs(base_path)
    
    # 先把换行去掉
    clean_subtitle = subtitle.replace('\n', ' ').replace('\r', ' ')
    # 再用正则去除 Windows 不允许的字符
    clean_subtitle = re.sub(r'[<>:"/\\|?*]', '', clean_subtitle)
    # 也可以控制下长度，比如只取前 15 或 30 个字符等
    clean_subtitle = clean_subtitle[:15]

    count = 0
    while True:
        count += 1
        filename = f"{base_path}/{clean_subtitle}#{count}{extension}"
        if not os.path.exists(filename):
            return filename

def on_fromsub_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    current_timeline = current_project.GetCurrentTimeline()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return
    
    if items["Path"].Text == '':
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return

    use_api = is_using_azure_api()
    try:
        provider = AzureTTSProvider(
            api_key=azure_items["ApiKey"].Text,
            region=azure_items["Region"].Text,
            use_api=use_api
        )
    except ValueError as e:
        show_warning_message(STATUS_MESSAGES.enter_api_key)
        return

    global subtitle, stream, flag
    subtitle, start_frame, end_frame = get_current_subtitle(current_timeline)
    if subtitle is None:
        show_warning_message(STATUS_MESSAGES.no_subtitle_at_playhead)
        return
    print_text_on_box(subtitle)
    
    selected_format = items["OutputFormatCombo"].CurrentText or "mp3"
    extension = ".mp3" if not use_api else f".{selected_format}"
    filename = generate_filename(items["Path"].Text, subtitle, extension)
    
    voice_name = return_voice_name(items["NameCombo"].CurrentText)
    rate = items["RateSpinBox"].Value
    pitch = items["PitchSpinBox"].Value
    volume = items["VolumeSpinBox"].Value
    style = get_selected_style_code()
    style_degree = items["StyleDegreeSpinBox"].Value
    multilingual = get_selected_multilingual_code()
    
    audio_format = audio_formats.get(selected_format)
    if use_api and not audio_format:
        show_warning_message(STATUS_MESSAGES.unsupported_audio)
        return

    success, result = provider.synthesize(subtitle, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format, filename, start_frame, end_frame)
    if success:
        flag = False
win.On.FromSubButton.Clicked = on_fromsub_button_clicked

def on_fromtxt_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    current_timeline = current_project.GetCurrentTimeline()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return
    if items["Path"].Text == '':
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return

    use_api = is_using_azure_api()
    try:
        provider = AzureTTSProvider(
            api_key=azure_items["ApiKey"].Text,
            region=azure_items["Region"].Text,
            use_api=use_api
        )
    except ValueError as e:
        show_warning_message(STATUS_MESSAGES.enter_api_key)
        return

    global subtitle, stream, flag
    subtitle = items["AzureTxt"].PlainText
    if not subtitle.strip():
        show_warning_message(STATUS_MESSAGES.prev_txt)
        return
    
    selected_format = items["OutputFormatCombo"].CurrentText or "mp3"
    extension = ".mp3" if not use_api else f".{selected_format}"
    filename = generate_filename(items["Path"].Text, subtitle, extension)
    
    voice_name = return_voice_name(items["NameCombo"].CurrentText)
    rate = items["RateSpinBox"].Value
    pitch = items["PitchSpinBox"].Value
    volume = items["VolumeSpinBox"].Value
    style = get_selected_style_code()
    style_degree = items["StyleDegreeSpinBox"].Value
    multilingual = get_selected_multilingual_code()

    audio_format = audio_formats.get(selected_format)
    if use_api and not audio_format:
        show_warning_message(STATUS_MESSAGES.unsupported_audio)
        return

    frame_rate = float(current_timeline.GetSetting("timelineFrameRate"))
    current_frame = timecode_to_frames(current_timeline.GetCurrentTimecode(), frame_rate)
    end_frame = current_timeline.GetEndFrame()

    if stream and flag:
        stream.save_to_wav_file(filename)
        time.sleep(1)
        add_to_media_pool_and_timeline(current_frame, end_frame, filename)
        flag = False
        stream = None
    elif flag:
        success, result = provider.synthesize(subtitle, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format, filename, current_frame, end_frame)
        if success:
            flag = False
    else:
        
        show_warning_message(STATUS_MESSAGES.media_clip_exists)
win.On.FromTxtButton.Clicked = on_fromtxt_button_clicked

def on_play_button_clicked(ev):
    if items["Path"].Text == '':
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return
    if items["AzureTxt"].PlainText == '':
        show_warning_message(STATUS_MESSAGES.prev_txt)
        return
    
    use_api = is_using_azure_api()
    try:
        provider = AzureTTSProvider(
            api_key=azure_items["ApiKey"].Text,
            region=azure_items["Region"].Text,
            use_api=use_api
        )
    except ValueError as e:
        show_warning_message(STATUS_MESSAGES.enter_api_key)
        return

    items["PlayButton"].Enabled = False
    
    global subtitle, ssml, stream
    subtitle = items["AzureTxt"].PlainText
    rate = items["RateSpinBox"].Value
    pitch = items["PitchSpinBox"].Value
    volume = items["VolumeSpinBox"].Value
    style = get_selected_style_code()
    style_degree = items["StyleDegreeSpinBox"].Value
    multilingual = get_selected_multilingual_code()
    voice_name = return_voice_name(items["NameCombo"].CurrentText)
    
    selected_format = items["OutputFormatCombo"].CurrentText or "mp3"
    audio_format = audio_formats.get(selected_format)
    if use_api and not audio_format:
        show_warning_message(STATUS_MESSAGES.unsupported_audio)
        items["PlayButton"].Enabled = True
        return
    
    success, result = provider.preview(subtitle, voice_name, rate, pitch, volume, style, style_degree, multilingual, audio_format)
    
    if success:
        stream = result
        flagmark()
    
    items["PlayButton"].Enabled = True
win.On.PlayButton.Clicked = on_play_button_clicked
#============== MINIMAX ====================#
def json_to_srt(json_data, srt_path, start_offset_seconds=0.0):
    """
    将JSON格式的字幕信息转换为 .srt 文件并保存。
    """
    srt_output = []
    subtitle_id = 1
    for item in json_data:
        text = item["text"]
        # 移除可能出现的 BOM
        if text.startswith("\ufeff"):
            text = text[1:]
        start_seconds = item["time_begin"] / 1000 + start_offset_seconds
        end_seconds = item["time_end"] / 1000 + start_offset_seconds
        start_time = frame_to_timecode(start_seconds, 1)
        end_time = frame_to_timecode(end_seconds, 1)
        srt_output.append(f"{subtitle_id}")
        srt_output.append(f"{start_time} --> {end_time}")
        srt_output.append(text)
        srt_output.append("")
        subtitle_id += 1
    try:
        with open(srt_path, 'w', encoding='utf-8') as file:
            file.write("\n".join(srt_output))
        print(f"SRT 文件已保存：{srt_path}")
    except Exception as e:
        print(f"保存 SRT 文件失败: {e}")

def load_clone_data(voice_file: str) -> Dict[str, Any]:
    """
    读取 JSON 文件，返回包含 key 'minimax_clone_voices' 的字典
    若文件不存在或解析失败，则返回空 dict 并初始化该 key
    """
    try:
        with open(voice_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (IOError, json.JSONDecodeError):
        data = {}
    data.setdefault("minimax_clone_voices", [])
    return data

def save_clone_data(voice_file: str, data: Dict[str, Any]) -> None:
    """
    将 data 写回 voice_file，格式化输出
    """
    try:
        with open(voice_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
    except IOError:
        raise Exception(f"Cannot write to file: {voice_file}")

def refresh_voice_combo(
    items: Dict[str, Any],
    clone_list: List[Dict[str, Any]],
    system_list: List[Dict[str, Any]],
) -> None:
    """
    刷新下拉框：只添加 language 与当前语言一致的条目
    """
    combo = items["minimaxVoiceCombo"]
    combo.Clear()

    current_lang = items["minimaxLanguageCombo"].CurrentText.strip()
    # 先添加符合当前语言的��隆列表
    for v in clone_list:
        if v.get("language", "").strip() == current_lang:
            combo.AddItem(v["voice_name"])
    # 再添加符合当前语言的系统列表
    for v in system_list:
        if v.get("language", "").strip() == current_lang:
            combo.AddItem(v["voice_name"])

def add_clone_voice(
    voice_file: str,
    voice_name: str,
    voice_id: str,
    items: Dict[str, Any],
    minimax_clone_voices: List[Dict[str, str]],
    minimax_voices: List[Dict[str, str]],
) -> List[Dict[str, str]]:
    # 1. 加载现有数据
    data = load_clone_data(voice_file)

    # 2. 重复检查
    for v in data["minimax_clone_voices"]:
        if v.get("voice_name") == voice_name or v.get("voice_id") == voice_id:
            show_warning_message(STATUS_MESSAGES.error_2039)
            return minimax_clone_voices

    # 3. 插入新条目到列表开头
    new_voice = {
        "voice_id": voice_id,
        "voice_name": voice_name,
        "description": [],
        "created_time": "1970-01-01",
        "language": items["minimaxLanguageCombo"].CurrentText
    }
    data["minimax_clone_voices"].insert(0, new_voice)

    # 4. 保存并刷新 UI
    save_clone_data(voice_file, data)
    refresh_voice_combo(items, data["minimax_clone_voices"], minimax_voices)
    minimax_clone_items["minimaxCloneFileID"].Text = ""
    win.Show()
    minimax_clone_window.Hide()
    show_warning_message(STATUS_MESSAGES.add_clone_succeed)
    
    return data["minimax_clone_voices"]

def delete_clone_voice(
    voice_file: str,
    voice_name: str,
    items: Dict[str, Any],
    minimax_clone_voices: List[Dict[str, str]],
    minimax_voices: List[Dict[str, str]],
) -> List[Dict[str, str]]:
    # 1. 加载现有数据
    data = load_clone_data(voice_file)
    original = data["minimax_clone_voices"]

    # 2. 过滤出所有不匹配的条目（strip + lower 匹配）
    key = voice_name.strip().lower()
    filtered = [
        v for v in original
        if v.get("voice_name", "").strip().lower() != key
    ]

    # 3. 如果没有任何条目被删除，提示并返回旧列表
    if len(filtered) == len(original):
        show_warning_message(STATUS_MESSAGES.delete_clone_error)
        return minimax_clone_voices

    # 4. 保存并刷新 UI
    data["minimax_clone_voices"] = filtered
    save_clone_data(voice_file, data)
    refresh_voice_combo(items, filtered, minimax_voices)

    show_warning_message(STATUS_MESSAGES.delete_clone_succeed)
    return filtered

def on_delete_minimax_clone_voice(ev):
    global MINIMAX_CLONE_VOICES
    voice_name = items["minimaxVoiceCombo"].CurrentText.strip()
    MINIMAX_CLONE_VOICES = delete_clone_voice(
            voice_file=voice_file,
            voice_name=voice_name,
            items=items,
            minimax_clone_voices=MINIMAX_CLONE_VOICES,
            minimax_voices=MINIMAX_VOICES,
        )
win.On.minimaxDeleteVoice.Clicked = on_delete_minimax_clone_voice

def on_minimax_clone_confirm(ev):
    # 1. Parameter validation
    if not minimax_items["minimaxGroupID"].Text or not minimax_items["minimaxApiKey"].Text:
        show_warning_message(STATUS_MESSAGES.enter_api_key)
        return

    if not items["Path"].Text:
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return

    global MINIMAX_CLONE_VOICES
    voice_name = minimax_clone_items["minimaxCloneVoiceName"].Text.strip()
    voice_id = minimax_clone_items["minimaxCloneVoiceID"].Text.strip()
    if not voice_name or not voice_id:
        show_warning_message(STATUS_MESSAGES.clone_id_error)
        return

    # 2. Initialize Provider
    try:
        provider = MiniMaxProvider(
            api_key=minimax_items["minimaxApiKey"].Text,
            group_id=minimax_items["minimaxGroupID"].Text,
            is_intl=minimax_items["intlCheckBox"].Checked
        )
    except ValueError as e:
        print(e)
        return

    # 3. Handle "Add ID Only" mode
    if minimax_clone_items["minimaxOnlyAddID"].Checked:
        MINIMAX_CLONE_VOICES = add_clone_voice(
            voice_file=voice_file, voice_name=voice_name, voice_id=voice_id, items=items,
            minimax_clone_voices=MINIMAX_CLONE_VOICES, minimax_voices=MINIMAX_VOICES
        )
        return

    # 4. Full clone process: Get File ID -> Submit -> Download
    file_id_text = minimax_clone_items["minimaxCloneFileID"].Text.strip()
    if not file_id_text:
        show_warning_message(STATUS_MESSAGES.file_upload)
        audio_path = render_audio_by_marker(AUDIO_TEMP_DIR)
        if not audio_path:
            show_warning_message(STATUS_MESSAGES.render_audio_failed)
            return
        resolve.OpenPage("edit")
        if os.path.exists(audio_path) and os.path.getsize(audio_path) > 20 * 1024 * 1024:
            show_warning_message(STATUS_MESSAGES.file_size)
            return

        upload_result = provider.upload_file_for_clone(audio_path)
        if upload_result["error_message"]:
            err_code = upload_result["error_code"]
            attr = f"error_{err_code}"
            status_tuple = getattr(
                    STATUS_MESSAGES,
                    attr,
                    STATUS_MESSAGES.error_1000
                )
            show_warning_message(status_tuple)
            return
        
        file_id = upload_result["file_id"]
        minimax_clone_items["minimaxCloneFileID"].Text = str(file_id)
    else:
        file_id = int(file_id_text)

    # 5. Submit clone job
    show_warning_message(STATUS_MESSAGES.file_clone)
    clone_result = provider.submit_clone_job(
        file_id=file_id, voice_id=voice_id,
        need_nr=minimax_clone_items["minimaxNeedNoiseReduction"].Checked,
        need_vn=minimax_clone_items["minimaxNeedVolumeNormalization"].Checked,
        text=minimax_clone_items["minimaxClonePreviewText"].PlainText.strip()
    )

    if clone_result["error_message"]:
        err_code = clone_result["error_code"]
        attr = f"error_{err_code}"
        status_tuple = getattr(
                STATUS_MESSAGES,
                attr,
                STATUS_MESSAGES.error_1000
            )
        show_warning_message(status_tuple)
        #minimax_clone_items["minimaxCloneStatus"].Text = f"ERROR: {clone_result['error_message']}"
        return

    # 6. Download demo and update lists
    if clone_result["demo_url"]:
        show_warning_message(STATUS_MESSAGES.download_preclone)
        demo_content = provider.download_media(clone_result["demo_url"])
        if demo_content:
            demo_path = os.path.join(items["Path"].Text, f"preview_{voice_id}.mp3")
            with open(demo_path, 'wb') as f:
                f.write(demo_content)
            add_to_media_pool_and_timeline(current_timeline.GetStartFrame(), current_timeline.GetEndFrame(), demo_path)

    MINIMAX_CLONE_VOICES = add_clone_voice(
        voice_file=voice_file, voice_name=voice_name, voice_id=voice_id, items=items,
        minimax_clone_voices=MINIMAX_CLONE_VOICES, minimax_voices=MINIMAX_VOICES
    )
    show_warning_message(STATUS_MESSAGES.clone_success)
minimax_clone_window.On.MiniMaxCloneConfirm.Clicked = on_minimax_clone_confirm

def on_minimax_clone_close(ev):
    minimax_clone_items["minimaxCloneFileID"].Text = ""
    current_timeline.DeleteMarkerAtFrame(0)
    win.Show()
    minimax_clone_window.Hide()
minimax_clone_window.On.MiniMaxCloneWin.Close = on_minimax_clone_close
minimax_clone_window.On.MiniMaxCloneCancel.Clicked = on_minimax_clone_close

def on_minimax_preview_button_click(ev):
    if minimax_items["intlCheckBox"].Checked:
        webbrowser.open(MINIMAX_PREW_URL)
    else:
        webbrowser.open(MINIMAXI_PREW_URL)   
win.On.minimaxPreviewButton.Clicked = on_minimax_preview_button_click

def build_voice_modify_payload() -> Dict[str, Any]:
    state = get_voice_modify_state()
    payload: Dict[str, Any] = {}
    for key in ("timbre", "intensity", "pitch"):
        val = int(state.get(key, 0))
        if val != 0:
            payload[key] = val

    default_effect = MINIMAX_SOUND_EFFECTS[0][1]
    effect = state.get("sound_effect", default_effect)
    if effect and effect != default_effect:
        payload["sound_effects"] = effect
    return payload

def on_show_voice_modify_window(ev):
    global voice_modify_snapshot
    voice_modify_snapshot = get_voice_modify_state()
    minimax_voice_modify_window.Show()

def on_voice_modify_confirm(ev):
    minimax_voice_modify_window.Hide()

def on_voice_modify_cancel(ev):
    global voice_modify_snapshot
    if isinstance(voice_modify_snapshot, dict):
        apply_voice_modify_state(voice_modify_snapshot)
    minimax_voice_modify_window.Hide()

win.On.minimaxVoiceEffectButton.Clicked = on_show_voice_modify_window
minimax_voice_modify_window.On.MiniMaxVoiceModifyConfirm.Clicked = on_voice_modify_confirm
minimax_voice_modify_window.On.MiniMaxVoiceModifyCancel.Clicked = on_voice_modify_cancel
minimax_voice_modify_window.On.MiniMaxVoiceModifyWin.Close = on_voice_modify_cancel

def process_minimax_request(text_func, timeline_func):
    resolve, current_project, current_timeline = connect_resolve()
    # 1. Validate inputs
    save_path = items["Path"].Text
    api_key = minimax_items["minimaxApiKey"].Text
    group_id = minimax_items["minimaxGroupID"].Text

    if not save_path:
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return

    if not api_key or not group_id:
        show_warning_message(STATUS_MESSAGES.enter_api_key)
        return


    #show_warning_message(STATUS_MESSAGES.synthesizing)

    # 2. Initialize Provider
    try:
        provider = MiniMaxProvider(
            api_key=api_key,
            group_id=group_id,
            is_intl=minimax_items["intlCheckBox"].Checked
        )
    except ValueError as e:
        print(e)
        show_warning_message(STATUS_MESSAGES.synthesis_failed)
        return

    # 3. Get voice ID and other params
    voice_name = items["minimaxVoiceCombo"].CurrentText
    all_voices = MINIMAX_VOICES + MINIMAX_CLONE_VOICES
    voice_id = next((v["voice_id"] for v in all_voices if v["voice_name"] == voice_name), None)
    if not voice_id:
        show_warning_message(STATUS_MESSAGES.synthesis_failed) # Or a more specific "voice not found" message
        print(f"Could not find voice_id for {voice_name}")
        return

    emotion_name = items["minimaxEmotionCombo"].CurrentText
    emotion_value = get_minimax_emotion_code_from_text(emotion_name)
    voice_modify_payload = build_voice_modify_payload()
    # 4. Call synthesis logic
    text = text_func()
    selected_format = items["OutputFormatCombo"].CurrentText or "mp3"
    print_text_on_box(text)
    result = provider.synthesize(
        text=text,
        model=items["minimaxModelCombo"].CurrentText,
        voice_id=voice_id,
        speed=items["minimaxRateSpinBox"].Value,
        vol=items["minimaxVolumeSpinBox"].Value,
        pitch=items["minimaxPitchSpinBox"].Value,
        file_format=selected_format,
        subtitle_enable=items["minimaxSubtitleCheckBox"].Checked,
        emotion=emotion_value,
        voice_modify=voice_modify_payload,
    )

    # 5. Handle result
    if result["error_message"]:
        err_code = result["error_code"]
        attr = f"error_{err_code}"
        status_tuple = getattr(
                STATUS_MESSAGES,
                attr,
                STATUS_MESSAGES.error_1000
            )
        show_warning_message(status_tuple)
        return

    filename = generate_filename(save_path, text, f".{selected_format}")
    start_frame, end_frame = timeline_func()
    srt_path = None
    if items["minimaxSubtitleCheckBox"].Checked and result["subtitle_url"]:
        subtitle_content = provider.download_media(result["subtitle_url"])
        if subtitle_content:
            subtitle_json_path = os.path.splitext(filename)[0] + ".json"
            srt_path = os.path.splitext(filename)[0] + ".srt"
            try:
                with open(subtitle_json_path, 'wb') as f:
                    f.write(subtitle_content)
                
                with open(subtitle_json_path, 'r', encoding='utf-8') as f:
                    json_data = json.load(f)
                
                frame_rate = float(current_timeline.GetSetting("timelineFrameRate"))
                start_offset_seconds = 0.0
                if start_frame is not None and frame_rate:
                    timeline_start_frame = current_timeline.GetStartFrame()
                    relative_start = start_frame - timeline_start_frame
                    if relative_start < 0:
                        relative_start = 0
                    start_offset_seconds = relative_start / frame_rate
                json_to_srt(json_data, srt_path, start_offset_seconds)
                os.remove(subtitle_json_path) # Clean up temp json
            except (IOError, json.JSONDecodeError) as e:
                print(f"Failed to process subtitle file: {e}")
                srt_path = None

    # Save audio
    try:
        with open(filename, "wb") as f:
            f.write(result["audio_content"])
        add_to_media_pool_and_timeline(start_frame, end_frame, filename)
    except IOError as e:
        print(f"Failed to write audio file: {e}")
        show_warning_message(STATUS_MESSAGES.audio_save_failed)
        return

    if srt_path:
        if import_srt_to_timeline(srt_path):
            try:
                os.remove(srt_path)
            except OSError as e:
                print(f"Failed to remove srt file: {e}")
    
    show_warning_message(STATUS_MESSAGES.loaded_to_timeline)

def on_minimax_fromsub_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return
    if items["Path"].Text == '':
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return
    subtitle_text, start_frame, end_frame = get_current_subtitle(current_timeline)
    if subtitle_text is None:
        show_warning_message(STATUS_MESSAGES.no_subtitle_at_playhead)
        return
    process_minimax_request(
        text_func=lambda: subtitle_text,
        timeline_func=lambda: (start_frame, end_frame)
    )
win.On.minimaxFromSubButton.Clicked = on_minimax_fromsub_button_clicked

def on_minimax_fromtxt_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return
    if items["Path"].Text == '':
        show_warning_message(STATUS_MESSAGES.select_save_path)
        return
    
    text = items["minimaxText"].PlainText
    if not text.strip():
        show_warning_message(STATUS_MESSAGES.prev_txt)
        return
    process_minimax_request(
        text_func=lambda: text,
        timeline_func=lambda: (
            # 动态获取当前帧和时间线结束?
            timecode_to_frames(
                current_timeline.GetCurrentTimecode(),
                float(current_timeline.GetSetting("timelineFrameRate"))
            ),
            current_timeline.GetEndFrame()
        )
    )
win.On.minimaxFromTxtButton.Clicked = on_minimax_fromtxt_button_clicked

def on_minimax_break_button_clicked(ev):
    breaktime =  items["minimaxBreakSpinBox"].Value/1000
    # 插入<break>标志
    items["minimaxText"].InsertPlainText(f'<#{breaktime}#>')
win.On.minimaxBreakButton.Clicked = on_minimax_break_button_clicked

def on_minimax_reset_button_clicked(ev):
    """
    重置所有输入控件为默认设置。
    """
    items["minimaxModelCombo"].CurrentIndex = DEFAULT_SETTINGS["minimax_Model"]
    items["minimaxVoiceCombo"].CurrentIndex = DEFAULT_SETTINGS["minimax_Voice"]
    items["minimaxLanguageCombo"].CurrentIndex = DEFAULT_SETTINGS["minimax_Language"]
    items["minimaxEmotionCombo"].CurrentIndex = DEFAULT_SETTINGS["minimax_Emotion"]
    items["minimaxRateSpinBox"].Value = DEFAULT_SETTINGS["minimax_Rate"]
    items["minimaxVolumeSpinBox"].Value = DEFAULT_SETTINGS["minimax_Volume"]
    items["minimaxPitchSpinBox"].Value = DEFAULT_SETTINGS["minimax_Pitch"]
    items["minimaxBreakSpinBox"].Value = DEFAULT_SETTINGS["minimax_Break"]
    items["minimaxSubtitleCheckBox"].Checked = DEFAULT_SETTINGS["minimax_SubtitleCheckBox"]
    apply_voice_modify_state(
        {
            "timbre": DEFAULT_SETTINGS["minimaxVoiceTimbre"],
            "intensity": DEFAULT_SETTINGS["minimaxVoiceIntensity"],
            "pitch": DEFAULT_SETTINGS["minimaxVoicePitch"],
            "sound_effect": get_sound_effect_code_by_index(DEFAULT_SETTINGS["minimaxVoiceEffect"]),
        }
    )
    items["OutputFormatCombo"].CurrentIndex = DEFAULT_SETTINGS["OUTPUT_FORMATS"]
win.On.minimaxResetButton.Clicked = on_minimax_reset_button_clicked

def on_minimax_register_link_button_clicked(ev):
    if minimax_items["intlCheckBox"].Checked:
        url= "https://intl.minimaxi.com/login"
    else:
        url = "https://platform.minimaxi.com/registration"
        
    webbrowser.open(url)
minimax_config_window.On.minimaxRegisterButton.Clicked = on_minimax_register_link_button_clicked

def on_minimax_close(ev):
    print("MiniMax API 配置完成")
    minimax_config_window.Hide()
minimax_config_window.On.MiniMaxConfirm.Clicked = on_minimax_close
minimax_config_window.On.MiniMaxConfigWin.Close = on_minimax_close

#============== OPENAI ====================#
def process_openai_request(text_func, timeline_func):
    # 1. Input validation
    save_path = items["Path"].Text
    api_key = openai_items["OpenAIApiKey"].Text
    if not save_path or not api_key:
        show_warning_message(STATUS_MESSAGES.select_save_path if not save_path else STATUS_MESSAGES.enter_api_key)
        return

    #show_warning_message(STATUS_MESSAGES.synthesizing)

    # 2. Initialize Provider
    try:
        provider = OpenAIProvider(api_key, openai_items["OpenAIBaseURL"].Text)
    except ValueError as e:
        print(e)
        show_warning_message(STATUS_MESSAGES.synthesis_failed)
        return

    # 3. Call synthesis logic
    text = text_func()
    selected_format = items["OutputFormatCombo"].CurrentText or "mp3"
    print_text_on_box(text)
    audio_content = provider.synthesize(
        text=text,
        model=items["OpenAIModelCombo"].CurrentText,
        voice=items["OpenAIVoiceCombo"].CurrentText,
        speed=items["OpenAIRateSpinBox"].Value,
        file_format=selected_format,
        instructions=items["OpenAIInstructionText"].PlainText.strip()
    )

    # 4. Handle the result
    if audio_content:
        filename = generate_filename(save_path, text, f".{selected_format}")
        try:
            with open(filename, "wb") as f:
                f.write(audio_content)
            
            start_frame, end_frame = timeline_func()
            add_to_media_pool_and_timeline(start_frame, end_frame, filename)
        except IOError as e:
            print(f"Failed to write audio file: {e}")
            show_warning_message(STATUS_MESSAGES.audio_save_failed)
    else:
        show_warning_message(STATUS_MESSAGES.synthesis_failed)

def on_openai_fromsub_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return False
    
    subtitle_text, start_frame, end_frame = get_current_subtitle(current_timeline)
    if subtitle_text is None:
        show_warning_message(STATUS_MESSAGES.no_subtitle_at_playhead)
        return False
    process_openai_request(
        text_func=lambda: subtitle_text,
        timeline_func=lambda: (start_frame, end_frame)
        )
win.On.OpenAIFromSubButton.Clicked = on_openai_fromsub_button_clicked

def on_openai_fromtxt_button_clicked(ev):
    resolve, current_project,current_timeline = connect_resolve()
    if not current_timeline:
        show_warning_message(STATUS_MESSAGES.create_timeline)
        return False
    
    text = items["OpenAIText"].PlainText
    if not text.strip():
        show_warning_message(STATUS_MESSAGES.prev_txt)
        return False
    process_openai_request(
        text_func=lambda: text,
        timeline_func=lambda: (
            # 动态获取当前帧和时间线结束?
            timecode_to_frames(
                current_timeline.GetCurrentTimecode(),
                float(current_timeline.GetSetting("timelineFrameRate"))
            ),
            current_timeline.GetEndFrame()
        )
    )
win.On.OpenAIFromTxtButton.Clicked = on_openai_fromtxt_button_clicked


def on_openai_reset_button_clicked(ev):
    """
    重置所有输入控件为默认设置。
    """
    items["OpenAIModelCombo"].CurrentIndex = DEFAULT_SETTINGS["OpenAI_Model"]
    items["OpenAIVoiceCombo"].CurrentIndex = DEFAULT_SETTINGS["OpenAI_Voice"]
    items["OpenAIRateSpinBox"].Value = DEFAULT_SETTINGS["OpenAI_Rate"]
    items["OpenAIInstructionText"].Text = DEFAULT_SETTINGS["OpenAI_Instruction"]
    items["OpenAIPresetCombo"].CurrentIndex = DEFAULT_SETTINGS["OpenAI_Preset"]
    items["OutputFormatCombo"].CurrentIndex = DEFAULT_SETTINGS["OUTPUT_FORMATS"]
win.On.OpenAIResetButton.Clicked = on_openai_reset_button_clicked

def on_openai_preview_button_clicked(ev):
    webbrowser.open(OPENAI_FM)
win.On.OpenAIPreviewButton.Clicked = on_openai_preview_button_clicked

def on_openai_close(ev):
    print("OpenAI API 配置完成")
    openai_config_window.Hide()
openai_config_window.On.OpenAIConfirm.Clicked = on_openai_close
openai_config_window.On.OpenAIConfigWin.Close = on_openai_close

def on_browse_button_clicked(ev):
    current_path = items["Path"].Text
    selected_path = fusion.RequestDir(current_path)
    if selected_path:
        # 创建以项目名称命名的子目录
        project_subdir = os.path.join(selected_path, f"{current_project.GetName()}_TTS")
        try:
            os.makedirs(project_subdir, exist_ok=True)
            items["Path"].Text = str(project_subdir)
            print(f"Directory created: {project_subdir}")
        except Exception as e:
            print(f"Failed to create directory: {e}")
    else:
        print("No directory selected or the request failed.")
win.On.Browse.Clicked = on_browse_button_clicked

def close_and_save(settings_file):
    settings = {
        "API_KEY": azure_items["ApiKey"].Text,
        "REGION": azure_items["Region"].Text,
        "LANGUAGE": items["LanguageCombo"].CurrentIndex,
        "TYPE": items["NameTypeCombo"].CurrentIndex,
        "NAME": items["NameCombo"].CurrentIndex,
        "RATE": items["RateSpinBox"].Value,
        "PITCH": items["PitchSpinBox"].Value,
        "VOLUME": items["VolumeSpinBox"].Value,
        "STYLEDEGREE": items["StyleDegreeSpinBox"].Value,
        "OUTPUT_FORMATS": items["OutputFormatCombo"].CurrentIndex,
        "USE_API": azure_items["UseAPICheckBox"].Checked,

        "minimax_API_KEY": minimax_items["minimaxApiKey"].Text,
        "minimax_GROUP_ID": minimax_items["minimaxGroupID"].Text,
        "minimax_intlCheckBox":minimax_items["intlCheckBox"].Checked,
        "Path": items["Path"].Text,
        "minimax_Model": items["minimaxModelCombo"].CurrentIndex,
        #"Text": items["minimaxText"].PlainText,
        "minimax_Voice": items["minimaxVoiceCombo"].CurrentIndex,
        "minimax_Language": items["minimaxLanguageCombo"].CurrentIndex,
        "minimax_SubtitleCheckBox":items["minimaxSubtitleCheckBox"].Checked,
        "minimax_Emotion": items["minimaxEmotionCombo"].CurrentIndex,
        "minimax_Rate": items["minimaxRateSpinBox"].Value,
        "minimax_Volume": items["minimaxVolumeSpinBox"].Value,
        "minimax_Pitch": items["minimaxPitchSpinBox"].Value,
        "minimax_Break":items["minimaxBreakSpinBox"].Value,
        "minimaxVoiceTimbre": minimax_voice_modify_items["minimaxTimbreSlider"].Value,
        "minimaxVoiceIntensity": minimax_voice_modify_items["minimaxIntensitySlider"].Value,
        "minimaxVoicePitch": minimax_voice_modify_items["minimaxModifyPitchSlider"].Value,
        "minimaxVoiceEffect": minimax_voice_modify_items["minimaxSoundEffectCombo"].CurrentIndex,

        "OpenAI_API_KEY": openai_items["OpenAIApiKey"].Text,
        "OpenAI_BASE_URL": openai_items["OpenAIBaseURL"].Text,
        "OpenAI_Model": items["OpenAIModelCombo"].CurrentIndex,
        "OpenAI_Voice": items["OpenAIVoiceCombo"].CurrentIndex,
        "OpenAI_Rate": items["OpenAIRateSpinBox"].Value,
        "OpenAI_Instruction":items["OpenAIInstructionText"].PlainText,
        "OpenAI_Preset":items["OpenAIPresetCombo"].CurrentIndex,

        "CN":items["LangCnCheckBox"].Checked,
        "EN":items["LangEnCheckBox"].Checked,
        
    }

    save_settings(settings, settings_file)

def on_open_link_button_clicked(ev):
    if items["LangEnCheckBox"].Checked :
        webbrowser.open(SCRIPT_KOFI_URL)
    else :
        webbrowser.open(SCRIPT_TAOBAO_URL)
win.On.CopyrightButton.Clicked = on_open_link_button_clicked

def on_azure_register_link_button_clicked(ev):
    url = "https://speech.microsoft.com/portal/voicegallery"
    webbrowser.open(url)
azure_config_window.On.AzureRegisterButton.Clicked = on_azure_register_link_button_clicked

def on_open_guide_button_clicked(ev):
    html_path  = os.path.join(SCRIPT_PATH, 'Installation-Usage-Guide.html') 
    if os.path.exists(html_path):
        webbrowser.open(f'file://{html_path}')
    else:
        print("找不到教程文件:", html_path)
win.On.openGuideButton.Clicked = on_open_guide_button_clicked

def on_show_azure(ev):
    azure_config_window.Show()
win.On.ShowAzure.Clicked = on_show_azure

def on_show_minimax(ev):
    minimax_config_window.Show()
win.On.ShowMiniMax.Clicked = on_show_minimax

def on_show_minimax_clone(ev):
    minimax_clone_items["minimaxNeedNoiseReduction"].Enabled = not minimax_clone_items["minimaxOnlyAddID"].Checked
    minimax_clone_items["minimaxNeedVolumeNormalization"].Enabled = not minimax_clone_items["minimaxOnlyAddID"].Checked
    minimax_clone_items["minimaxClonePreviewText"].Enabled = not minimax_clone_items["minimaxOnlyAddID"].Checked
    minimax_clone_items["minimaxOnlyAddID"].Checked = True
    win.Hide()
    minimax_clone_window.Show()
win.On.ShowMiniMaxClone.Clicked = on_show_minimax_clone

def on_show_openai(ev):
    openai_config_window.Show()
win.On.ShowOpenAI.Clicked = on_show_openai

# Azure配置窗口按钮事件
def on_azure_close(ev):
    print("Azure API 配置完成")
    azure_config_window.Hide()
azure_config_window.On.AzureConfirm.Clicked = on_azure_close
azure_config_window.On.AzureConfigWin.Close = on_azure_close

def on_break_button_clicked(ev):
    breaktime =  items["BreakSpinBox"].Value
    # 插入<break>标志
    items["AzureTxt"].InsertPlainText(f'<break time="{breaktime}ms" />')
win.On.BreakButton.Clicked = on_break_button_clicked

def on_alphabet_button_clicked(ev):
    items["AzureTxt"].Copy()
    from pypinyin import pinyin, Style

    def convert_to_pinyin_with_tone(text):
        pinyin_list = pinyin(text, style=Style.TONE3, heteronym=False)
        pinyin_with_tone = []

        for word in pinyin_list:
            if word[0][-1].isdigit():  # 如果最后一个字符是数字（声调）
                pinyin_with_tone.append(f"{word[0][:-1]} {word[0][-1]}")
            else:  # 否则，表示是轻声
                pinyin_with_tone.append(f"{word[0]} 5")
        
        return ' '.join(pinyin_with_tone)

    alphabet = dispatcher.AddWindow(
        {
            "ID": 'Alphabet',
            "WindowTitle": '多音字',
            "Geometry": [750, 400, 500, 150],
            "Spacing": 10,
        },
        [   
            ui.VGroup(
                [
                    ui.HGroup(
                        {"Weight": 1},
                        [
                            ui.LineEdit({"ID": 'AlphaTxt', "Text": ""}),
                        ]
                    ),
                    ui.HGroup(
                        {"Weight": 0},
                        [
                            ui.Label({"ID": 'msgLabel', "Text": """例如，'li 4 zi 5' 表示 '例子'。数字代表拼音声调。'5' 代表轻声。\n若要控制儿化音，请在拼音的声调前插入 "r"。例如，"hou r 2 shan 1" 代表“猴儿山”。"""}),
                        ]
                    ),
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

    ahb = alphabet.GetItems()
    ahb["AlphaTxt"].Text =  ahb["AlphaTxt"].Paste()
    original_text = ahb["AlphaTxt"].Text
    convert_test= convert_to_pinyin_with_tone(re.sub(r'[^\u4e00-\u9fa5]', '', original_text))
    ahb["AlphaTxt"].Text = convert_test

    def on_ok_button_clicked(ev):
        replace_text = ahb["AlphaTxt"].Text
        replace_text = '' if replace_text == '' else (original_text if replace_text == convert_test else f"<phoneme alphabet=\"sapi\" ph=\"{ahb['AlphaTxt'].Text}\">{original_text}</phoneme>")
        items["AzureTxt"].InsertPlainText(replace_text)
        dispatcher.ExitLoop()
        
    alphabet.On.OkButton.Clicked = on_ok_button_clicked
    def on_close(ev):
        dispatcher.ExitLoop()
    alphabet.On.Alphabet.Close = on_close
    alphabet.Show()
    dispatcher.RunLoop()
    alphabet.Hide()
win.On.AlphabetButton.Clicked = on_alphabet_button_clicked

def on_reset_button_clicked(ev):
    flagmark()
    azure_items["UseAPICheckBox"].Checked = DEFAULT_SETTINGS["USE_API"]
    toggle_api_checkboxes(azure_items["UseAPICheckBox"].Checked)
    refresh_type_combo(saved_index=DEFAULT_SETTINGS["TYPE"])
    refresh_language_combo(
        saved_index=DEFAULT_SETTINGS["LANGUAGE"],
        saved_voice_index=DEFAULT_SETTINGS["NAME"],
    )
    items["RateSpinBox"].Value = DEFAULT_SETTINGS["RATE"]
    items["BreakSpinBox"].Value = DEFAULT_SETTINGS["BREAKTIME"]
    items["PitchSpinBox"].Value = DEFAULT_SETTINGS["PITCH"]
    items["VolumeSpinBox"].Value = DEFAULT_SETTINGS["VOLUME"]
    items["StyleCombo"].CurrentIndex = DEFAULT_SETTINGS["STYLE"]
    items["StyleDegreeSpinBox"].Value = DEFAULT_SETTINGS["STYLEDEGREE"]
    items["OutputFormatCombo"].CurrentIndex = DEFAULT_SETTINGS["OUTPUT_FORMATS"]
win.On.ResetButton.Clicked = on_reset_button_clicked

def on_close(ev):
    resolve, current_project,current_timeline = connect_resolve()
    markers = current_timeline.GetMarkers() or {}
    for frame_id, info in markers.items():
        if info.get("customData") == "clone":
            current_timeline.DeleteMarkerAtFrame(frame_id)
    close_and_save(settings_file)
    import shutil
    for temp_dir in [AUDIO_TEMP_DIR]:
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                print(f"Removed temporary directory: {temp_dir}")
            except OSError as e:
                print(f"Error removing directory {temp_dir}: {e.strerror}")
    dispatcher.ExitLoop()
win.On.MainWin.Close = on_close

loading_win.Hide() 
win.Show()
dispatcher.RunLoop()
azure_config_window.Hide()
minimax_config_window.Hide()
openai_config_window.Hide()
win.Hide()
