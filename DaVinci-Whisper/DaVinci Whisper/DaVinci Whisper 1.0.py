SCRIPT_NAME    = "DaVinci Whisper"
SCRIPT_VERSION = " 1.4" # Updated version
SCRIPT_AUTHOR  = "HEIBA"
print(f"{SCRIPT_NAME} | {SCRIPT_VERSION.strip()} | {SCRIPT_AUTHOR}")
SCREEN_WIDTH, SCREEN_HEIGHT = 1920, 1080
WINDOW_WIDTH, WINDOW_HEIGHT = 725, 425
X_CENTER = (SCREEN_WIDTH  - WINDOW_WIDTH ) // 2
Y_CENTER = (SCREEN_HEIGHT - WINDOW_HEIGHT) // 2

SCRIPT_KOFI_URL      = "https://ko-fi.com/heiba"
SCRIPT_BILIBILI_URL  = "https://shop120058726.taobao.com"

MODEL_LINK_EN ="https://drive.google.com/drive/folders/16FLicjnstLhrl3yKgCHOvle5-3_mLii5?usp=sharing"
MODEL_LINK_CN ="https://pan.baidu.com/s/1kthNbHJAggTUT2cv9nKaUg?pwd=8888"
LANGUAGE_MAP = {
    "Auto": None,
    "中文（普通话）": "zh",
    "English": "en",
    "Japanese": "ja",
    "Korean": "ko",
    "Spanish": "es",
    "Portuguese": "pt",
    "French": "fr",
    "German": "de",
    "Russian": "ru",
    "Italian": "it",
    "Arabic": "ar",
    "Turkish": "tr",
    "Ukrainian": "uk",
    "Vietnamese": "vi",
    "Thai": "th",
    "Lao": "lo",
    "Khmer": "km",
    "Burmese": "my",
    "Tibetan": "bo",
    "Indonesian": "id",
    "Dutch": "nl",
    "Uzbek": "uz",
    "Polish": "pl",
    "Czech": "cs",
    "Danish": "da",
    "Finnish": "fi",
    "Swedish": "sv",
    "Hebrew": "he",
    "Greek": "el",
    "Hindi": "hi",
    "Bengali": "bn",
    "Swahili": "sw",
    "Malay": "ms",
    "Romanian": "ro"
}

import os
import time
import platform
import sys
import random
import webbrowser
import subprocess
import string
import shutil
import glob
import re
import unicodedata
import io
import threading
import json
from fractions import Fraction
from itertools import tee
from difflib import SequenceMatcher
from typing import Optional, List, Generator, Dict, Any
from urllib.parse import quote_plus
from abc import ABC, abstractmethod
os.environ["CUDA_VISIBLE_DEVICES"] = ""
SCRIPT_PATH = os.path.dirname(os.path.abspath(sys.argv[0]))
AUDIO_TEMP_DIR = os.path.join(SCRIPT_PATH, "audio_temp")
SUB_TEMP_DIR = os.path.join(SCRIPT_PATH, "sub_temp")
SETTINGS = os.path.join(SCRIPT_PATH, "config", "settings.json")
LANGUAGE_SUPPORT = os.path.join(SCRIPT_PATH, "config", "language_support.json")
RAND_CODE = "".join(random.choices(string.digits, k=2))

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

if os.path.exists(LANGUAGE_SUPPORT):
    with open(LANGUAGE_SUPPORT, "r", encoding="utf-8") as f:
        LANGUAGE_MAP = json.load(f)

DEFAULT_SETTINGS = {

    "OPENAI_FORMAT_BASE_URL": "",
    "OPENAI_FORMAT_API_KEY": "",
    "PROVIDER":False,
    "MODEL": 0,
    "LANGUAGE": 0,
    "MAX_CHARS": 42,
    "REMOVE_GAPS": False,
    "TRIM_PUNCT": False, 
    "SMART":False,
    "CN":True,
    "EN":False,
}

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
_loading_notice_text = ""

def _on_loading_confirm(ev):
    global _loading_confirmation_pending
    if not _loading_confirmation_pending:
        return
    _loading_confirmation_pending = False
    try:
        _loading_items["ConfirmButton"].Enabled = False
        _loading_items["ConfirmButton"].Visible = False
    except Exception:
        pass
    dispatcher.ExitLoop()

def _loading_timer_worker():
    while not _loading_timer_stop:
        try:
            elapsed = int(time.time() - _loading_start_ts)
            base_text = f"Please wait , loading... \n( {elapsed}s elapsed )"
            notice = _loading_notice_text.strip()
            if notice:
                base_text = f"{notice}\n\n{base_text}"
            _loading_items["LoadLabel"].Text = base_text
        except Exception:
            pass
        time.sleep(1.0)

loading_win.On.ConfirmButton.Clicked = _on_loading_confirm
threading.Thread(target=_loading_timer_worker, daemon=True).start()

# ---------- Resolve/Fusion 连接,外部环境使用（先保存起来） ----------
"""
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
"""
def connect_resolve():
    pm  = resolve.GetProjectManager()
    prj = pm.GetCurrentProject()
    mp  = prj.GetMediaPool()
    root= mp.GetRootFolder()
    tl  = prj.GetCurrentTimeline()
    fps_frac = _get_timeline_fps(tl, prj)
    return resolve, prj, mp, root, tl, fps_frac

if not hasattr(sys.stderr, "flush"):
    sys.stderr.flush = lambda: None

try:
    import requests
    import regex as re_u
    import faster_whisper
except ImportError:
    system = platform.system()
    if system == "Windows":
        lib_dir = os.path.join(os.environ.get("PROGRAMDATA", r"C:\ProgramData"), "Blackmagic Design", "DaVinci Resolve", "Fusion", "HB", SCRIPT_NAME, "Lib")
    elif system == "Darwin":
        lib_dir = os.path.join("/Library", "Application Support", "Blackmagic Design", "DaVinci Resolve", "Fusion", "HB", SCRIPT_NAME, "Lib")
    else:
        lib_dir = os.path.normpath(os.path.join(SCRIPT_PATH, "..", "..", "..", "HB", SCRIPT_NAME, "Lib"))

    lib_dir = os.path.normpath(lib_dir)
    if os.path.isdir(lib_dir):
        sys.path.insert(0, lib_dir)
    else:
        print(f"Warning: The Whisper/Lib directory doesn’t exist:{lib_dir}", file=sys.stderr)

    try:
        import requests
        import regex as re_u
        import faster_whisper
        print(lib_dir)
    except ImportError as e:
        print("Dependency import failed—please make sure all dependencies are bundled into the Lib directory:", lib_dir, "\nError message:", e)
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

def _check_for_updates():
    global _loading_confirmation_pending, _loading_notice_text
    current_version = (SCRIPT_VERSION or "").strip()
    result = supabase_client.check_update(SCRIPT_NAME)
    if not result:
        return

    latest_version = (result.get("latest") or "").strip()
    if not latest_version or latest_version == current_version:
        return

    messages = []
    for key in ("cn", "en"):
        text = (result.get(key) or "").strip()
        if text:
            messages.append(text)

    readable_current = current_version or "未知"
    version_line = f"Update: {readable_current} → {latest_version}\nDownload on your purchase page."
    messages.append(version_line)
    notice_text = "\n".join(messages).strip()

    try:
        _loading_items["UpdateLabel"].Text = notice_text
        _loading_items["UpdateLabel"].Visible = True
    except Exception:
        pass

    _loading_notice_text = notice_text
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

# ================== Transcription Provider Abstraction ==================

class TranscriptionProvider(ABC):
    """Abstract base class for transcription services."""
    
    @abstractmethod
    def get_available_models(self) -> List[str]:
        """Returns a list of available model names."""
        pass

    @abstractmethod
    def transcribe(self, **kwargs) -> Optional[str]:
        """
        Performs transcription and returns the path to the generated SRT file,
        or None on failure.
        """
        pass
    
    def _format_time(self, seconds: float) -> str:
        milliseconds = int((seconds % 1) * 1000)
        return time.strftime('%H:%M:%S', time.gmtime(seconds)) + f',{milliseconds:03d}'
    
    def _write_srt(self, srt_path: str, subtitle_blocks: List[Dict]):
        with open(srt_path, "w", encoding="utf-8") as f:
            for idx, blk in enumerate(subtitle_blocks, 1):
                f.write(f"{idx}\n")
                f.write(f"{self._format_time(blk['start'])} --> {self._format_time(blk['end'])}\n")
                f.write(f"{blk['text'].strip()}\n\n")

class FasterWhisperProvider(TranscriptionProvider):
    """Transcription provider using the faster‑whisper library."""

    # ---------------- 公共配置 ----------------
    def get_available_models(self) -> List[str]:
        return ["tiny", "small", "base", "medium", "large-v3"]

    # 逐字分词的语言集合
    CJK_LANGS = {"zh", "ja", "ko", "th", "lo", "km", "my", "bo"}

    # ---------- 1. 通用符号 ----------
    _SYMS_RAW   = "%％$€¥+-–—#&@°℃"
    _SYM_CLASS  = re_u.escape(_SYMS_RAW)          # "%％\$€¥\+\-\–—#&@°℃"
    _SYM_CLASS  = f"[{_SYM_CLASS}]"              # 供字符类复用

    # ---------- 2. 文件 / 标识符 token ----------
    # 连续字母数字，中间可含 . _ - ，但首尾均为字母/数字
    _FILELIKE = r"[\p{L}\p{Nd}]+(?:[._-][\p{L}\p{Nd}]+)+"

    # ---------- 3. 正则模式 ----------
    # 3‑1 CJK 语境下的分词
    _CJK_PATTERN = re_u.compile(
        rf"(?:\s+(?:{_FILELIKE}|[A-Za-z0-9][A-Za-z0-9'\-]*)"
        rf"|(?:{_FILELIKE}|[A-Za-z0-9][A-Za-z0-9'\-]*)"
        rf"|\p{{Han}}|\p{{Hiragana}}|\p{{Katakana}}|\p{{Hangul}}"
        rf"|\p{{Thai}}|\p{{Lao}}|\p{{Khmer}}|\p{{Myanmar}}|\p{{Tibetan}}"
        rf"|[^\s])",
        flags=re_u.VERSION1
    )

    # 3‑2 非 CJK 语境下的分词
    _NON_CJK_PATTERN = re_u.compile(
        rf"(?:\s+(?:{_FILELIKE}|[\p{{L}}\p{{Nd}}][\p{{L}}\p{{Nd}}'\-]*){_SYM_CLASS}?"
        rf"|(?:{_FILELIKE}|[\p{{L}}\p{{Nd}}][\p{{L}}\p{{Nd}}'\-]*){_SYM_CLASS}?"
        rf"|[.,!?…;:，。？！；：{_SYM_CLASS[1:-1]}]|\s+)",
        flags=re_u.VERSION1
    )

    # 3‑3 拆分 Whisper 非 CJK word 中的内部标点
    _WHISPER_NON_CJK_SPLIT = re_u.compile(
        rf"(?:{_FILELIKE}|[\p{{L}}\p{{Nd}}][\p{{L}}\p{{Nd}}'\-]*{_SYM_CLASS}?"
        rf"|[.,!?…;:，。？！；：{_SYM_CLASS[1:-1]}])",
        flags=re_u.VERSION1
    )
    _CJK_ANY_RE = re_u.compile(
        r"\p{Han}|\p{Hiragana}|\p{Katakana}|\p{Hangul}|\p{Thai}|\p{Lao}|\p{Khmer}|\p{Myanmar}|\p{Tibetan}",
        flags=re_u.VERSION1
    )
    _PUNCTS_RIGHT_ATTACH = set(list(".,?!…;:，。？！；：)]}»、」』》"))
    _PUNCTS_LEFT_ATTACH  = set(list("([{«「『《"))
    _QUOTES              = set(['"', "'", "“", "”", "‘", "’"])
    def _is_cjk_token(self, s: str) -> bool:
        return bool(self._CJK_ANY_RE.search(s))

    def _should_joiner(self, prev_tok: str, cur_tok: str) -> str:
        """
        返回前缀连接符："" 或 " "
        规则：
        - 标点（右侧附着，如 , . ! ? … 等）前不加空格
        - 左括号/开引号后不加空格
        - CJK↔CJK 不加空格
        - 其它情况默认加一个空格（含 CJK↔非CJK），避免“全粘在一起”
        """
        if not prev_tok:
            return ""
        if cur_tok in self._PUNCTS_RIGHT_ATTACH or cur_tok in self._QUOTES and cur_tok in ('"', "”", "’"):
            return ""
        if prev_tok in self._PUNCTS_LEFT_ATTACH or prev_tok in self._QUOTES and prev_tok in ('"', "“", "‘"):
            return ""
        prev_is_cjk = self._is_cjk_token(prev_tok)
        cur_is_cjk  = self._is_cjk_token(cur_tok)
        if prev_is_cjk and cur_is_cjk:
            return ""
        return " "
    # ---------- 4. 辅助方法 ----------
    @staticmethod
    def _insert_boundary_spaces(text: str) -> str:
        cjk = "Han|Hiragana|Katakana|Hangul|Thai|Lao|Khmer|Myanmar|Tibetan"
        text = re_u.sub(rf"(\p{{{cjk}}})([A-Za-z0-9])", r"\1 \2", text)
        return re_u.sub(rf"([A-Za-z0-9])(\p{{{cjk}}})", r"\1 \2", text)

    @staticmethod
    def _preprocess_camel_case(text: str) -> str:
        return re_u.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", text)

    # ---------- 5. _normalize_text ----------
    
    def _normalize_text(self, text: str, language: Optional[str]) -> List[str]:
        # 1) 统一到 NFKC，拉直全角/兼容字符
        text = unicodedata.normalize("NFKC", (text or "").strip())
        # 2) 聪明引号/破折号 ↦ ASCII
        text = (text
                .replace("\u2019", "'")   # ’ -> '
                .replace("\u2018", "'")   # ‘ -> '
                .replace("\u201C", '"')   # “ -> "
                .replace("\u201D", '"')   # ” -> "
                .replace("\u2013", "-")   # – -> -
                .replace("\u2014", "-"))  # — -> -

        # 3) 你原有的预处理
        text = self._preprocess_camel_case(text)   # "DaVinci" -> "Da Vinci"
        text = re_u.sub(r"\s+", " ", text)

        if language in self.CJK_LANGS:
            text = self._insert_boundary_spaces(text)
            tokens = self._CJK_PATTERN.findall(text)
        else:
            tokens = [tk for tk in self._NON_CJK_PATTERN.findall(text) if tk.strip()]

        # 4) **去掉你 findall 带来的前导空格**
        return [t.lstrip() for t in tokens if t.strip()]
    def _coalesce_hyphen_tokens(self, tokens: List[Dict]) -> List[Dict]:
        """
        将 ['sub','-','title'] 合并为 ['sub-title']，并贯通时间。
        合并条件：中间 token 恰为 '-'，且三者相邻；允许 0.02s 微小间隙。
        """
        if not tokens:
            return tokens
        merged = []
        i = 0
        while i < len(tokens):
            if (i + 2 < len(tokens)
                and tokens[i+1]["token"] == "-"
                and tokens[i]["end"] >= tokens[i+1]["start"] - 0.02
                and tokens[i+2]["start"] <= tokens[i+1]["end"] + 0.02):
                merged.append({
                    "token": tokens[i]["token"] + "-" + tokens[i+2]["token"],
                    "start": tokens[i]["start"],
                    "end"  : tokens[i+2]["end"],
                })
                i += 3
            else:
                merged.append(tokens[i])
                i += 1
        return merged
    # ---------- 6. _collect_words ----------
    def _collect_words(self, segments_gen, language: Optional[str]) -> List[Dict]:
        tokens: List[Dict] = []
        for seg in segments_gen:
            if not seg.words:
                continue
            for w in seg.words:
                if language in self.CJK_LANGS:
                    for tk in self._CJK_PATTERN.findall(w.word):
                        tokens.append({"token": tk, "start": float(w.start), "end": float(w.end)})
                else:
                    for tk in self._WHISPER_NON_CJK_SPLIT.findall(w.word.lstrip()):
                        tokens.append({"token": tk, "start": float(w.start), "end": float(w.end)})
        tokens = self._coalesce_hyphen_tokens(tokens)
        return tokens

    # ---------- 6.1 计算“有效 token”覆盖率（用于回退判定） ----------
    def _is_meaningful_token(self, tok: str) -> bool:
        """过滤掉纯标点/空白，仅保留包含字母/数字/各主要文字脚本的 token。"""
        return bool(re_u.search(
            r"\p{L}|\p{Nd}|\p{Han}|\p{Hiragana}|\p{Katakana}|\p{Hangul}|\p{Thai}|\p{Lao}|\p{Khmer}|\p{Myanmar}|\p{Tibetan}",
            tok
        ))

    # ---------- 3. _align_time ----------
    def _align_time(self, whisper_tokens: List[Dict], gpt_tokens: List[str]) -> Generator:
        from types import SimpleNamespace
        # Case-insensitive compare to improve robustness
        A_cmp = [t["token"].lstrip().casefold() for t in whisper_tokens]
        B_cmp = [b.lstrip().casefold() for b in gpt_tokens]
        matcher = SequenceMatcher(None, A_cmp, B_cmp, autojunk=False)
        mapping = {}
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag == "equal":
                for k in range(i2 - i1):
                    mapping[j1 + k] = i1 + k

        aligned, B_keys = [], sorted(mapping.keys())
        for j, tok in enumerate(gpt_tokens):
            tok_clean = tok.lstrip()
            if j in mapping:
                w = whisper_tokens[mapping[j]]
                start, end = w["start"], w["end"]
            else:
                prev = next((k for k in reversed(B_keys) if k < j), None)
                nxt  = next((k for k in B_keys if k > j), None)
                if prev is not None and nxt is not None and prev != nxt:
                    t0 = whisper_tokens[mapping[prev]]["end"]
                    t1 = whisper_tokens[mapping[nxt]]["start"]
                    start = t0 + (t1 - t0) * (j - prev) / (nxt - prev)
                elif prev is not None:
                    start = whisper_tokens[mapping[prev]]["end"]
                elif nxt is not None:
                    start = whisper_tokens[mapping[nxt]]["start"]
                else:
                    start = 0.0
                end = start + 0.05
            aligned.append({"word": tok_clean, "start": start, "end": end})
            
        if aligned and whisper_tokens:
            last_whisper_token_end = whisper_tokens[-1]["end"]
            aligned[-1]["end"] = max(aligned[-1]["end"], last_whisper_token_end)

        yield SimpleNamespace(words=[
            SimpleNamespace(word=t["word"], start=t["start"], end=t["end"])
            for t in aligned])


    def _split_segments_by_max_chars(self, segments: Generator, max_chars: int) -> List[Dict]:
        END_OF_CLAUSE_CHARS = tuple(".,?!。，？！")
        subtitle_blocks = []
        current_block = {"start": 0, "end": 0, "text": ""}
        max_chars_tolerance = int(max_chars * 1.20)

        def finalize_and_reset_block():
            nonlocal current_block
            if current_block["text"]:
                current_block["text"] = current_block["text"].strip()
                subtitle_blocks.append(current_block)
            current_block = {"start": 0, "end": 0, "text": ""}

        prev_tok_for_join = ""  # 仅用于判定是否加空格

        for segment in segments:
            if not segment.words:
                continue
            for word in segment.words:
                wtxt = (word.word or "")
                if not wtxt:
                    continue

                # —— 是否为“单独句末标点” —— #
                ws = wtxt.strip()
                word_ends_clause = (ws.endswith(END_OF_CLAUSE_CHARS) and len(ws) == 1)

                if not current_block["text"]:
                    # 第一词直接放入
                    current_block = {"start": word.start, "end": word.end, "text": wtxt}
                    prev_tok_for_join = wtxt
                    if word_ends_clause:
                        finalize_and_reset_block()
                        prev_tok_for_join = ""
                    continue

                # —— 计算连接符（按相邻 token 判定，避免 language 误判） —— #
                joiner = self._should_joiner(prev_tok_for_join, wtxt)
                to_add = joiner + wtxt
                potential_len = len(current_block["text"]) + len(to_add)

                if potential_len <= max_chars:
                    current_block["text"] += to_add
                    current_block["end"] = word.end
                    prev_tok_for_join = wtxt
                    if word_ends_clause:
                        finalize_and_reset_block()
                        prev_tok_for_join = ""
                elif potential_len <= max_chars_tolerance and word_ends_clause:
                    current_block["text"] += to_add
                    current_block["end"] = word.end
                    finalize_and_reset_block()
                    prev_tok_for_join = ""
                else:
                    finalize_and_reset_block()
                    current_block = {"start": word.start, "end": word.end, "text": wtxt}
                    prev_tok_for_join = wtxt

        finalize_and_reset_block()
        return subtitle_blocks
    
    def _progress_reporter(self, segments_gen, total_duration: float, callback, max_fps: float = 10.0):
        if total_duration <= 0:
            for seg in segments_gen: yield seg
            callback(100.0)
            return

        last_end, last_report_ts = 0.0, 0.0
        min_interval = 1.0 / max_fps if max_fps > 0 else 0.0
        progress = 0.0

        for seg in segments_gen:
            last_end = max(last_end, seg.end)
            progress = min(last_end / total_duration * 100.0, 100.0)
            now = time.time()
            if now - last_report_ts >= min_interval or progress >= 100.0:
                last_report_ts = now
                callback(progress)
            yield seg
        
        if progress < 100.0:
            callback(100.0)

    def _transcribe_audio(self,
                        file_path: str,
                        api_key: str,
                        base_url: str = "https://api.openai.com",
                        model_name: str = "gpt-4o-mini-transcribe",
                        language: Optional[str] = None,
                        hotwords: Optional[str] = None,
                        retries: int = 3,
                        # 直接切片参数
                        chunk_bytes: int = 5 * 1024 * 1024,   # 5MB 一片
                        chunk_overlap_ratio: float = 0.0,    # 重叠比例（按字节）
                        progress_callback=None
                        ) -> str:
        """
        总是切片上传（串行，带 prompt 接力），并通过 progress_callback 汇报进度。
        返回：合并去重后的完整文本。
        变更：当 chunk_overlap_ratio <= 0.1 时，不执行文本去重，直接拼接。
        """
        headers = {"Authorization": f"Bearer {api_key}"}
        url     = f"{base_url.rstrip('/')}/v1/audio/transcriptions"

        def _safe_post(name: str, byts: bytes) -> str:
            files = {"file": (name, io.BytesIO(byts), "audio/mpeg")}
            data  = {"model": model_name, "response_format": "json"}
            if language:
                data["language"] = language

            last_err = None
            for attempt in range(1, retries + 1):
                try:
                    resp = requests.post(
                        url, headers=headers, files=files, data=data,
                        timeout=(10, 60)
                    )
                    if resp.status_code == 413:
                        raise RuntimeError("HTTP 413: Payload too large")
                    resp.raise_for_status()
                    jr = resp.json()
                    return jr.get("text", "")
                except (requests.exceptions.ConnectTimeout,
                        requests.exceptions.ReadTimeout,
                        requests.exceptions.ConnectionError) as e:
                    last_err = e
                    if attempt < retries:
                        time.sleep(2 ** attempt)
                        continue
                except requests.exceptions.RequestException as e:
                    try:
                        emsg = e.response.json()["error"]["message"]  # type: ignore
                    except Exception:
                        emsg = str(e)
                    raise RuntimeError(f"API Request failed: {emsg}") from e
            raise RuntimeError(f"Failed after {retries} retries: {last_err}")  # type: ignore

        def _split_plan(file_size: int) -> List[Dict]:
            # 计算每片起止字节（含重叠）
            overlap = int(chunk_bytes * max(0.0, min(0.5, chunk_overlap_ratio)))
            stride  = max(1, chunk_bytes - overlap)
            chunks, start, idx = [], 0, 0
            while start < file_size:
                end = min(file_size, start + chunk_bytes)
                chunks.append({"idx": idx, "start": start, "end": end})
                idx   += 1
                start += stride
            return chunks

        # ✅ 新增：可控的合并策略（是否启用去重）
        def _smart_merge(prev_text: str, new_text: str,
                        tail_win: int = 1000, head_win: int = 1000,
                        min_overlap_chars: int = 60,
                        min_overlap_ratio: float = 0.30,
                        dedupe_enabled: bool = True) -> str:
            # 没有上一段，直接返回
            if not prev_text:
                return new_text
            # 未启用去重：直接拼接
            if not dedupe_enabled:
                return prev_text + new_text

            # 启用去重：基于尾/头窗口检测重叠并消除
            tail = prev_text[-tail_win:]
            head = new_text[:head_win]
            m = SequenceMatcher(None, tail, head, autojunk=False).find_longest_match(0, len(tail), 0, len(head))
            if m and m.size > 0:
                overlap_len = m.size
                if overlap_len >= min_overlap_chars:
                    ratio = overlap_len / max(1, min(len(tail), len(head)))
                    if ratio >= min_overlap_ratio:
                        return prev_text + new_text[m.b + m.size:]
            return prev_text + new_text

        file_size = os.path.getsize(file_path)
        plan      = _split_plan(file_size)
        total_n   = len(plan)
        completed = 0

        if progress_callback:
            progress_callback(5.0)  # 5% 起步，切片准备中

        merged = ""

        # ✅ 在这里根据 chunk_overlap_ratio 控制是否去重
        dedupe_enabled = (chunk_overlap_ratio > 0.1)

        with open(file_path, "rb") as f:
            for ch in plan:
                f.seek(ch["start"])
                byts = f.read(ch["end"] - ch["start"])
                name = f"{os.path.basename(file_path)}.part{ch['idx']:03d}.mp3"

                part_text = _safe_post(name, byts)
                merged    = _smart_merge(
                    merged,
                    part_text,
                    dedupe_enabled=dedupe_enabled  # ✅ 只在 >0.1 时去重
                )

                # 进度更新（5% -> 99%）
                completed += 1
                if progress_callback:
                    p = 5.0 + 94.0 * (completed / max(1, total_n))
                    progress_callback(min(99.0, p))

        if progress_callback:
            progress_callback(100.0)
        return merged

    def _remove_gaps_between_blocks(self, blocks: List[Dict]) -> List[Dict]:
        if len(blocks) < 2:
            return blocks
        for i in range(len(blocks) - 1):
            blocks[i]["end"] = blocks[i+1]["start"]
        return blocks
    
    

    def transcribe(self, **kwargs) -> Optional[str]:
        input_audio   = kwargs.get("input_audio")
        model_name    = kwargs.get("model_name", "base")
        language      = kwargs.get("language")
        output_dir    = kwargs.get("output_dir", ".")
        output_filename = kwargs.get("output_filename")
        max_chars     = kwargs.get("max_chars", 40)
        batch_size    = kwargs.get("batch_size", 4)
        hotwords      = kwargs.get("hotwords")
        verbose       = kwargs.get("verbose", True)
        progress_cb   = kwargs.get("progress_callback")
        vad_filter    = kwargs.get("vad_filter", False)
        remove_gaps   = kwargs.get("remove_gaps", False)
        match_text   = (kwargs.get("match_text") or "").strip()

        # ---- 状态标记（用于最终用户可见总结）----
        ai_correct_enabled = bool(items["AICorrectCheckBox"].Checked)
        ai_correct_applied = False
        ai_correct_reason  = ""   # 失败/回退原因，仅在失败时展示

        local_model_path = os.path.join(SCRIPT_PATH, "model", model_name)
        try:
            if verbose:
                show_dynamic_message(f"Loading model '{model_name}' on CPU...", f"正在以 CPU 模式加载模型 '{model_name}'...")
            model = faster_whisper.WhisperModel(
                local_model_path,
                device="cpu",
                compute_type="int8",
                cpu_threads=max(1, (os.cpu_count() or 4) - 1),
                num_workers=1
            )
            pipeline = faster_whisper.BatchedInferencePipeline(model=model)
            if verbose:
                show_dynamic_message(f"Model '{model_name}' loaded (CPU).", f"模型 '{model_name}' (CPU) 加载成功。")
        except Exception as e:
            show_dynamic_message(f"Model '{model_name}' is unavailable", f"模型'{model_name}'不可用")
            print(f"Error loading model {model_name}: {e}")
            return None

        transcribe_args = {
            "beam_size": 5,
            "log_progress": True,
            "batch_size": max(1, batch_size),
            "word_timestamps": True,
            "hotwords": hotwords,
            "vad_filter": vad_filter
        }
        if language:
            transcribe_args["language"] = language

        if verbose:
            show_dynamic_message("[Whisper] Starting...", "[Whisper] 开始...")

        # 1) 原始生成器
        segments_gen, info = pipeline.transcribe(input_audio, **transcribe_args)
        if verbose:
            show_dynamic_message(f"[Whisper] Language: {info.language}", f"[Whisper] 语言: {info.language}")

        # 2) 进度包装（在 tee 之前）
        if progress_cb:
            segments_gen = self._progress_reporter(segments_gen, info.duration, progress_cb)

        # 3) 复制生成器，保证回退有“未消费”的分支可用
        segments_for_tokens, segments_for_split = tee(segments_gen, 2)

        if match_text:
            try:
                show_dynamic_message("[Whisper] Aligning with script...", "[Whisper] 正在按文稿对齐...")
                # 收集 Whisper 的逐词 token（不消耗 split 分支）
                whisper_tokens = self._collect_words(segments_for_tokens, info.language)
                print("----------------whisper_tokens----------------")
                print(whisper_tokens)
                print("----------------whisper_tokens----------------")
                print("----------------match_text----------------")
                print(match_text)
                print("----------------match_text----------------")
                # 规范化用户文稿为 token
                match_tokens   = self._normalize_text(match_text, info.language)
                print("----------------match_tokens----------------")
                print(match_tokens)
                print("----------------match_tokens----------------")
                if not match_tokens:
                    raise RuntimeError("Empty tokens from script text")
                # 覆盖率判定：当完全不匹配（或低于阈值）时，触发回退
                segments_to_split = self._align_time(whisper_tokens, match_tokens)
            except Exception as e:
                print(f"[Script Match Fallback] {e}")
                show_dynamic_message("[Whisper] Script match failed, fallback to local result.",
                                    "[Whisper] 文稿匹配失败，已回退为本地结果。")
                segments_to_split = segments_for_split
        else:
            # 4) Smart 模式（可选）
            if ai_correct_enabled:
                show_dynamic_message(f"[Whisper] Smart optimization takes up more time...", f"[Whisper] 智能优化会占用更多时间...")

                def _net_progress(pct: float):
                    show_dynamic_message(f"[Whisper] Refining... {pct:.1f}%",
                                        f"[Whisper] 优化中... {pct:.1f}%")
                try:
                    # 先把 Whisper 的逐词 token 收集出来（用 tokens 分支，避免消费 split 分支）
                    whisper_tokens = self._collect_words(segments_for_tokens, info.language)
                    print("----------------whisper_tokens----------------")
                    print(whisper_tokens)
                    print("----------------whisper_tokens----------------")
                    # 缺少 API Key 时，直接回退避免无意义的联网尝试
                    api_key_for_refine = kwargs.get("api_key", "")
                    if not api_key_for_refine:
                        raise RuntimeError("Missing API key")

                    # 在线 refine（分片上传+合并）
                    gpt_text = self._transcribe_audio(
                        file_path = input_audio,
                        api_key   = api_key_for_refine,
                        base_url  = kwargs.get("base_url", "https://api.openai.com/").rstrip('/'),
                        language  = None,
                        hotwords  = None,
                        progress_callback = _net_progress
                    )
                    print("----------------gpt_text----------------")
                    print(gpt_text)
                    print("----------------gpt_text----------------")
                    # 判空即触发回退
                    if not gpt_text or not gpt_text.strip():
                        raise RuntimeError("Empty online transcript")

                    gpt_tokens = self._normalize_text(gpt_text, info.language)
                    if not gpt_tokens:
                        raise RuntimeError("Empty tokenized transcript")
                    print("----------------gpt_tokens----------------")
                    print(gpt_tokens)
                    print("----------------gpt_tokens----------------")
                    # 基于匹配关系对齐时间
                    segments_to_split = self._align_time(whisper_tokens, gpt_tokens)
                    ai_correct_applied = True
                    show_dynamic_message("[Whisper] AI Correct applied ✅",
                                        "[Whisper] 字幕优化已应用 ✅")

                except Exception as e:
                    # 记录失败原因，回退到本地
                    ai_correct_applied = False
                    ai_correct_reason  = str(e)[:160]  # 避免过长
                    print(f"[AI Correct Fallback] Online refine failed: {e}")
                    show_dynamic_message("[Whisper] AI Correct failed, falling back to local.",
                                        "[Whisper] 智能优化失败，已回退为本地结果。")
                    segments_to_split = segments_for_split
            else:
                # 未开启 AI Correct：直接用未被消费的分支
                segments_to_split = segments_for_split

        # 5) CJK 语言下字符上限折半
        if info.language in self.CJK_LANGS:
            max_chars = max_chars / 2

        # 6) 分段
        subtitle_blocks = self._split_segments_by_max_chars(segments_to_split, int(max_chars))
        #print(subtitle_blocks)
        # 7.x) 帧量化 & 修复重叠/零时长
        try:
            _, _, _, _, _, fps_now = connect_resolve()
        except Exception:
            fps_now = FPS_FALLBACK

        subtitle_blocks = _quantize_and_fix_blocks(
            subtitle_blocks,
            fps=fps_now,
            enforce_no_gaps=items["NoGapCheckBox"].Checked,
            min_frames=1
        )
        # 7) 去间隙（可选）
        if remove_gaps:
            subtitle_blocks = self._remove_gaps_between_blocks(subtitle_blocks)

        # 8) 去除中文内部空格
        for blk in subtitle_blocks:
            blk["text"] = re.sub(r"(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])", "", blk["text"])
        
        if items["TrimPunctCheckBox"].Checked:
            TRAIL_PUNCT_RE = re.compile(r"[，。！？、；：,.!?;:…\s]+$")
            for blk in subtitle_blocks:
                blk["text"] = TRAIL_PUNCT_RE.sub("", blk["text"])
        _refresh_subtitle_tree(subtitle_blocks)
        # 9) 输出 SRT
        if not output_filename:
            base = os.path.splitext(os.path.basename(input_audio))[0]
            output_filename = f"{base}_whisper"
        os.makedirs(output_dir, exist_ok=True)
        srt_path = os.path.join(output_dir, f"{output_filename}.srt")

        # 调试
        print(subtitle_blocks)
        self._write_srt(srt_path, subtitle_blocks)

        # 10) 在函数内部给出“最终状态总结”，避免用户只看到外层统一的 ‘Finished! 100%’
        if ai_correct_enabled:
            if ai_correct_applied:
                # 成功应用 AI Correct
                show_dynamic_message("Done. AI Correct:  ✅",
                                    "完成。字幕优化： ✅")
            else:
                # AI Correct 失败已回退，给出简明原因
                en = "Done. AI Correct:  ❌  Reason: " + (ai_correct_reason or "unknown")
                zh = "完成。字幕优化：❌  原因：" + (ai_correct_reason or "未知")
                show_dynamic_message(en, zh)
        else:
            # 未启用 AI Correct
            show_dynamic_message("Done.",
                                "完成。")

        if verbose:
            print(f"[Whisper] Generated SRT: {srt_path}")
        return srt_path

class OpenAIProvider(TranscriptionProvider):
    """
    Transcription provider using the OpenAI API, with robust subtitle generation.
    """
    CJK_LANGS = {
        'zh','chinese',
        'ja','japanese',
        'th','thai',
        'lo','lao',
        'km','khmer',
        'my','burmese','myanmar',
        'bo','tibetan',
    }

    # 2) name ➜ ISO 映射
    LANG_ALIAS = {
        'chinese': 'zh', 'japanese': 'ja', 'thai': 'th',
        'lao': 'lo', 'khmer': 'km',
        'burmese': 'my', 'myanmar': 'my',
        'tibetan': 'bo',
    }
    def get_available_models(self) -> List[str]:
        return ["whisper-1"]

    def _format_srt_time(self, seconds: float) -> str:
        """Formats seconds into SRT time format HH:MM:SS,ms"""
        millis = int(seconds * 1000)
        hours = millis // 3600000
        millis %= 3600000
        minutes = millis // 60000
        millis %= 60000
        seconds = millis // 1000
        millis %= 1000
        return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"

    def _write_srt(self, file_path: str, blocks: List[Dict]):
        """Writes a list of subtitle blocks to an SRT file."""
        with open(file_path, 'w', encoding='utf-8') as f:
            for i, block in enumerate(blocks):
                f.write(str(i + 1) + '\n')
                start_time = self._format_srt_time(block['start'])
                end_time = self._format_srt_time(block['end'])
                f.write(f"{start_time} --> {end_time}\n")
                f.write(block['text'].strip() + '\n\n')

    def _align_punctuations(self, words: List[Dict], text: str, language: str) -> List[Dict]:
        """
        将 text 中的标点优雅地归并回 words。
        对 CJK 语言使用字级指针算法；其他语言沿用 SequenceMatcher。
        """
        if not words or not text:
            return words

        # ---------- 新的 CJK 逻辑 ----------
        if language in self.CJK_LANGS:
            # 1) 去掉 text 中的空白字符，保持与 words 顺序一致
            plain_text = re.sub(r"\s+", "", text)

            # 2) 双指针同步
            new_words = []
            p_text = 0
            len_text = len(plain_text)

            for w in words:
                ch = w["word"]
                # 向前滑动直到找到同一字符
                while p_text < len_text and plain_text[p_text] != ch:
                    p_text += 1
                if p_text >= len_text:
                    # 对齐失败，直接回退
                    return words
                p_text += 1  # 越过当前匹配字符

                # 3) 向后累加所有紧随其后的标点
                punct = []
                while p_text < len_text and plain_text[p_text] in "。，？！…,.!?;；":
                    punct.append(plain_text[p_text])
                    p_text += 1

                # 4) 构造新 word
                new_word = w.copy()
                new_word["word"] = ch + "".join(punct)
                new_words.append(new_word)

            return new_words

        # ---------- 英语及其他语言：保留你的原实现 ----------
        api_word_list = [w['word'].strip().lower() for w in words]
        original_text_tokens = re.findall(r"[\w'-]+|[.,!?;]", text)
        text_word_list = [w.lower() for w in original_text_tokens]

        matcher = SequenceMatcher(None, api_word_list, text_word_list, autojunk=False)
        new_words = []
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag == 'equal':
                for i in range(i1, i2):
                    j = j1 + (i - i1)
                    new_word = words[i].copy()
                    new_word['word'] = original_text_tokens[j]
                    new_words.append(new_word)
            elif tag in ('replace', 'delete'):
                if i1 < i2:
                    combined = " ".join(original_text_tokens[j1:j2]).strip()
                    if combined:
                        new_words.append({
                            'word': combined,
                            'start': words[i1]['start'],
                            'end'  : words[i2-1]['end']
                        })
            elif tag == 'insert' and new_words:
                new_words[-1]['word'] += "".join(original_text_tokens[j1:j2])
        return new_words
    def _split_words_into_blocks(self, words: List[Dict], max_chars: int, language: str) -> List[Dict]:
        END_OF_CLAUSE_CHARS = tuple(".,?!。，？！")
        separator = "" if language in self.CJK_LANGS else " "
        subtitle_blocks = []
        current_block = {"start": 0, "end": 0, "text": ""}
        max_chars_tolerance = int(max_chars * 1.20)

        def finalize_and_reset_block():
            nonlocal current_block
            if current_block["text"]:
                current_block["text"] = current_block["text"].strip()
                subtitle_blocks.append(current_block)
            current_block = {"start": 0, "end": 0, "text": ""}

        for word in words:
            word_text = word["word"].strip()
            if not word_text:
                continue

            if not current_block["text"]:
                current_block = {"start": word["start"], "end": word["end"], "text": word_text}
                continue

            # Use language-aware separator
            potential_text = current_block["text"] + separator + word_text
            potential_len = len(potential_text)
            word_ends_clause = any(word_text.endswith(c) for c in END_OF_CLAUSE_CHARS)

            if potential_len <= max_chars:
                current_block["text"] = potential_text
                current_block["end"] = word["end"]
                if word_ends_clause:
                    finalize_and_reset_block()
            elif potential_len <= max_chars_tolerance and word_ends_clause:
                current_block["text"] = potential_text
                current_block["end"] = word["end"]
                finalize_and_reset_block()
            else:
                finalize_and_reset_block()
                current_block = {"start": word["start"], "end": word["end"], "text": word_text}
        
        finalize_and_reset_block()
        return subtitle_blocks

    def _remove_gaps_between_blocks(self, blocks: List[Dict]) -> List[Dict]:
        """Ensures there is no time gap between consecutive subtitle blocks."""
        if len(blocks) < 2:
            return blocks
        for i in range(len(blocks) - 1):
            blocks[i]["end"] = blocks[i+1]["start"]
        return blocks
    
    def transcribe(self, **kwargs) -> Optional[str]:
        # Get arguments with fallbacks
        api_key = kwargs.get("api_key","")
        base_url = kwargs.get("base_url", "https://api.openai.com/").rstrip('/')
        input_audio = kwargs.get("input_audio")
        language = kwargs.get("language")
        model_name = kwargs.get("model_name", "base")
        output_dir = kwargs.get("output_dir", ".")
        output_filename = kwargs.get("output_filename")
        max_chars = kwargs.get("max_chars", 40)
        hotwords = kwargs.get("hotwords")
        progress_callback = kwargs.get("progress_callback")
        remove_gaps = kwargs.get("remove_gaps", False)

        if not api_key:
            show_dynamic_message("OpenAI API Key not found.", "未找到 OpenAI API 密钥。")
            print("Error: OpenAI API Key not provided.")
            return None

        headers = {"Authorization": f"Bearer {api_key}"}
        url = f"{base_url}/v1/audio/transcriptions"
        
        files = {'file': (os.path.basename(input_audio), open(input_audio, 'rb'), 'audio/mpeg')}
        data = {
            "model": model_name,
            "response_format": "json",
            "timestamp_granularities[]": "word",
        }
        
        if language: data["language"] = language
        if hotwords: data["prompt"] = hotwords

        if progress_callback: progress_callback(10.0)
        def safe_post(url, headers, files, data, retries=3):
            for i in range(retries):
                try:
                    # connect timeout 10 s，首包后 read timeout 60 s
                    return requests.post(url, headers=headers, files=files, data=data,
                                        timeout=(10, 60))
                except (requests.exceptions.ConnectTimeout,
                        requests.exceptions.ReadTimeout,
                        requests.exceptions.ConnectionError) as e:
                    print(f"[Attempt {i+1}] {e}")
                    if i == retries - 1:
                        raise
                    time.sleep(2 ** i)  # 递增回退
        try:
            print(data)
            show_dynamic_message(f"Calling API: {url}...", f"调用接口: {url}...")

            response = safe_post(url, headers, files, data)

            response.raise_for_status()
            result = response.json()
            text = result.text
            print(text)
            
            if progress_callback: progress_callback(50.0)

            detected_language = result.get('language', 'en')
            detected_language = self.LANG_ALIAS.get(detected_language, detected_language)
            if detected_language in self.CJK_LANGS:
                max_chars = int(max_chars / 2)

            # --- THIS IS THE CORRECTED LOGIC BLOCK ---
            original_words = result.get('words', [])
            full_text = result.get('text', '')
            

            words_to_split = self._align_punctuations(original_words, full_text, detected_language)

            subtitle_blocks = self._split_words_into_blocks(words_to_split, int(max_chars), detected_language)
            print(subtitle_blocks)
            # --- END OF THE FINAL FIX ---
            # --- END OF CORRECTION ---
            
            if remove_gaps:
                subtitle_blocks = self._remove_gaps_between_blocks(subtitle_blocks)
            
            for blk in subtitle_blocks:
                blk["text"] = re.sub(r"(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])", "", blk["text"])

            if items["TrimPunctCheckBox"].Checked:
                TRAIL_PUNCT_RE = re.compile(r"[，。！？、；：,.!?;:…\s]+$")
                for blk in subtitle_blocks:
                    blk["text"] = TRAIL_PUNCT_RE.sub("", blk["text"])

            if not output_filename:
                base = os.path.splitext(os.path.basename(input_audio))[0]
                output_filename = f"{base}_openai"
                
            os.makedirs(output_dir, exist_ok=True)
            srt_path = os.path.join(output_dir, f"{output_filename}.srt")
            self._write_srt(srt_path, subtitle_blocks)

            if progress_callback: progress_callback(100.0)
            print(f"[OpenAI] Generated SRT: {srt_path}")
            return srt_path

        except requests.exceptions.RequestException as e:
            error_message = str(e)
            try:
                if e.response is not None:
                    error_details = e.response.json()
                    if 'error' in error_details and 'message' in error_details['error']:
                        error_message = error_details['error']['message']
            except (AttributeError, ValueError, KeyError):
                 pass
            
            show_dynamic_message(f"API Error: {error_message}", f"API 错误: {error_message}")
            print(f"OpenAI API request failed: {error_message}")
            return None
        finally:
            if 'file' in files and files['file'][1]:
                files['file'][1].close()
# ================== UI Definition and Logic ==================

# Instantiate the transcription providers
faster_whisper_provider = FasterWhisperProvider()
openai_provider = OpenAIProvider()

# ——（替换原 AddWindow 的 children 部分）——
whisper_win = dispatcher.AddWindow(
    {
        "ID": 'WhisperWin',
        "WindowTitle": SCRIPT_NAME + SCRIPT_VERSION,
        "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],
        "Spacing": 10,
        "StyleSheet": "*{font-size:14px;}"
    },
    ui.VGroup([
        # ---------- 上半部分：左右两栏 ----------
        ui.HGroup([
            # === 左侧参数区 ===
            ui.VGroup([
                ui.VGroup({"Weight":1},[
                    ui.Label({"ID":"TitleLabel","Text":"Create subtitles from audio",
                              "Alignment": {"AlignHCenter": True, "AlignVCenter": True},"Weight":0}),
                    ui.VGap(5),
                    ui.HGroup({"Weight":0.1},[
                        ui.Label({"ID":"ModelLabel","Text":"Model","Weight":0.5}),
                        ui.ComboBox({"ID":"ModelCombo","Weight":0.4}),
                        ui.CheckBox({"ID":"OnlineCheckBox", "Text":"Use OpenAI API", "Checked":False, "Weight":0}),
                    ]),
                    ui.HGroup({"Weight":0},[
                        ui.Button({"ID":"DownloadButton","Text":"Download Model","Weight":1}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.CheckBox({"ID":"MatchTextCheckBox", "Text":"文稿匹配", "Checked":False, "Weight":0}),
                        ui.Label({"Text": ""}),
                        ui.CheckBox({"ID":"AICorrectCheckBox", "Text":"AI Correct (beta)", "Checked":False, "Weight":0}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.Label({"ID":"LangLabel","Text":"Language","Weight":0.4}),
                        ui.ComboBox({"ID":"LangCombo","Weight":0.6}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.Label({"ID":"MaxCharsLabel","Text":"Max Chars","Weight":0.4}),
                        ui.SpinBox({"ID": "MaxChars", "Minimum": 0, "Maximum": 100, "Value": 42,
                                    "SingleStep": 1, "Weight": 0.6}),
                    ]),
                    ui.HGroup({"Weight":0.1},[
                        ui.CheckBox({"ID":"NoGapCheckBox", "Text":"No Gaps Between Subtitles",
                                     "Checked":False, "Weight":0}),
                        ui.Label({"Text": ""}),
                        ui.CheckBox({"ID":"TrimPunctCheckBox", "Text":"是否保留标点符号",
                                     "Checked":False, "Weight":0}),
                    ]),
                    
                    ui.Label({"ID":"HotwordsLabel","Text":"Phrases / Prompt","Weight":0.1}),
                    ui.TextEdit({"ID":"Hotwords","Text":"","Weight":0.1}),
                    ui.Button({"ID":"CreateButton","Text":"Create","Weight":0}),
                    ui.Button({
                    "ID": "CopyrightButton",
                    "Text": f"© 2025, Copyright by {SCRIPT_AUTHOR}",
                    "Alignment": {"AlignLeft": True, "AlignVCenter": True},  # 左对齐
                    "Font": ui.Font({"PixelSize": 12, "StyleName": "Bold"}),
                    "Flat": True,
                    "TextColor": [0.1, 0.3, 0.9, 1],
                    "BackgroundColor": [1, 1, 1, 0],
                    "Weight": 0
                }),
                ]),
            ], {"Weight": 4}),

            # === 右侧 Tree + Editor ===
            ui.VGroup([
                ui.Label({
                    "ID": "TreeTitleLabel",
                    "Text": "Subtitles / 字幕",
                    "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                    "Weight": 0
                }),
                ui.VGap(5),
                ui.HGroup({
                    "Weight": 0,
                    "Spacing": 6
                }, [
                    ui.LineEdit({
                        "ID": "FindInput",
                        "PlaceholderText": "Find text",
                        "Weight": 1,
                        "Events": {"TextChanged": True, "EditingFinished": True}
                    }),
                    ui.Button({
                        "ID": "FindButton",
                        "Text": "Find",
                        "Weight": 0
                    }),
                    ui.LineEdit({
                        "ID": "ReplaceInput",
                        "PlaceholderText": "Replace with",
                        "Weight": 1
                    }),
                    ui.Button({
                        "ID": "AllReplaceButton",
                        "Text": "Replace All",
                        "Weight": 0
                    }),
                    ui.Button({
                        "ID": "SingleReplaceButton",
                        "Text": "Replace",
                        "Weight": 0
                    }),
                ]),
                ui.Tree({
                    "ID": "SubtitleTree",
                    "AlternatingRowColors": True,
                    "WordWrap": True,
                    "UniformRowHeights": False,
                    "HorizontalScrollMode": True,
                    "FrameStyle": 1,
                    "SelectionMode": "SingleSelection",
                    "Weight": 1
                }),
                ui.TextEdit({
                    "ID": "SubtitleEditor",
                    "Weight": 0
                }),
                ui.Button({
                    "ID": "UpdateSubtitleButton",
                    "Text": "更新字幕",
                    "Weight": 0
                }),
                ui.HGroup({"Weight":0.1},[
                    ui.Label({"ID":"StatusLabel","Text":"","Weight":0.4}),
                    ui.CheckBox({"ID":"LangEnCheckBox","Text":"EN","Checked":True,"Weight":0}),
                    ui.CheckBox({"ID":"LangCnCheckBox","Text":"简体中文","Checked":False,"Weight":0}),
                ]),
               
            ], {"Weight": 6})
        ], {"Weight": 4}),

    ])
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
                    ui.HGroup({"Weight": 0}, [ui.Button({"ID": 'OkButton', "Text": 'OK'})]),
                ]
            ),
        ]
    )
openai_config_window = dispatcher.AddWindow(
    {
        "ID": "OpenAIConfigWin",
        "WindowTitle": "OpenAI API",
        "Geometry": [900, 400, 350, 150],
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
                ui.Label({"ID": "OpenAIFormatLabel","Text": "填写OpenAI API信息", "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "OpenAIFormatBaseURLLabel", "Text": "Base URL", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "OpenAIFormatBaseURL", "Text":"","PlaceholderText": "https://api.openai.com", "Weight": 0.8}),
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Label({"ID": "OpenAIFormatApiKeyLabel", "Text": "API Key", "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                    ui.LineEdit({"ID": "OpenAIFormatApiKey", "Text": "", "EchoMode": "Password", "Weight": 0.8}),
                    
                ]),
                ui.HGroup({"Weight": 1}, [
                    ui.Button({"ID": "OpenAIConfirm", "Text": "确定","Weight": 1}),
                    ui.Button({"ID": "OpenAIRegisterButton", "Text": "注册","Weight": 1}),
                ]),
                
            ]
        )
    ]
)
match_window = dispatcher.AddWindow(
    {
        "ID": "ScriptMatchWin",
        "WindowTitle": "Match Text",
        "Geometry": [X_CENTER, Y_CENTER, WINDOW_WIDTH, WINDOW_HEIGHT],
        "Hidden": True,
        "StyleSheet": "*{font-size:14px;}"
    },
    [
        ui.VGroup([
            ui.Label({
                "ID": "MatchInfoLabel",
                "Text": "请在下方粘贴完整文稿（将按该文本对齐 Whisper 时间轴）：",
                "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                "Weight": 0.2,
                'WordWrap': True
            }),
            # 将文本框与提示说明并排显示
            ui.HGroup({"Weight": 1}, [
                ui.VGroup({"Weight": 0.6},[
                    ui.TextEdit({
                        "ID": "MatchTextEdit",
                        "Text": "",
                        "PlaceholderText": "",
                        "StyleSheet": "*{font-size:18px;}",
                        "Weight": 3
                    }),
                ]),
                
                ui.VGroup({"Weight": 0.4},[
                    ui.Label({
                        "ID": "MatchTipLabel",
                        "Text": "",
                        'WordWrap': True,
                        "Weight": 1
                    }),
                    ui.Label({"Text": "","Weight": 2}),
                ])
            ]),
            ui.HGroup({"Weight": 0}, [
                ui.Button({"ID": "MatchConfirmBtn", "Text": "确定", "Weight": 0.6}),
                ui.Button({"ID": "MatchCancelBtn", "Text": "取消", "Weight": 0.4}),
            ])
        ])
    ]
)

def show_dynamic_message(en_text, zh_text):
    use_en = items["LangEnCheckBox"].Checked
    msg = en_text if use_en else zh_text
    msgbox.Show()
    msg_items["WarningLabel"].Text = msg

def on_msg_close(ev):
    msgbox.Hide()
msgbox.On.OkButton.Clicked = on_msg_close
msgbox.On.msg.Close = on_msg_close

translations = {
    "cn": {
        "TitleLabel":"从音频创建字幕", 
        "LangLabel":"语言", 
        "ModelLabel":"模型", 
        "CreateButton":"创建字幕", 
        "DownloadButton":"模型下载",
        "HotwordsLabel":"短语列表 / 提示", 
        "MaxCharsLabel":"每行最大字符", 
        "NoGapCheckBox":"字幕间无空隙",
        "TrimPunctCheckBox":"删除句尾标点",
        "MatchTextCheckBox":"文稿匹配",
        "TreeTitleLabel":"字幕编辑",
        "UpdateSubtitleButton": "更新字幕",
        "FindButton": "查找下一个",
        "AllReplaceButton": "全部替换",
        "SingleReplaceButton": "替换",
        "MatchInfoLabel":"请在下方粘贴完整文稿（将按该文本对齐）：",
        "MatchTipLabel": "• 建议一句一换行，无标点符号\n• 句号、叹号、问号等会自动分句，逗号不会自动分句\n• 避免置入无标点和无换行的文本",
        #"MatchTextEdit":"在此粘贴全文...",
        "MatchConfirmBtn":"确定",
        "MatchCancelBtn":"取消",
        "CopyrightButton":f"更多功能 © 2025 {SCRIPT_AUTHOR} 版权所有",
        "OnlineCheckBox": "使用 API",
        "AICorrectCheckBox": "AI字幕优化 (beta)",
        "OpenAIFormatLabel":"填写 OpenAI Format API 信息",
        "OpenAIConfirm":"确定",
        "OpenAIRegisterButton":"注册",
        },
    "en": {
        "TitleLabel":"Create subtitles from audio", 
        "LangLabel":"Language", 
        "ModelLabel":"Model", 
        "DownloadButton":"Download Model",
        "CreateButton":"Create SRT", 
        "MatchTextCheckBox":"Match Text",
        "MatchInfoLabel":"Please paste the full document below (it will be aligned to this text):",
        "MatchTipLabel": "• One sentence per line; avoid punctuation.\n• Periods/exclamation/question marks auto-split; commas do not.\n• Avoid text without punctuation or line breaks.",
        #"MatchTextEdit":"Paste the full text here...",
        "MatchConfirmBtn":"Confirm",
        "MatchCancelBtn":"Cancel",
        "TreeTitleLabel":"Subtitle Editor",
        "UpdateSubtitleButton": "Update SRT",
        "FindButton": "Find Next",
        "AllReplaceButton": "Replace All",
        "SingleReplaceButton": "Replace",
        "CopyrightButton":f"More Features © 2025 by {SCRIPT_AUTHOR}",
        "HotwordsLabel":"Phrases / Prompt", 
        "MaxCharsLabel":"Max Chars", 
        "NoGapCheckBox":"No Gaps",
        "TrimPunctCheckBox":"No End Punct.",
        "OnlineCheckBox": "Use API",
        "AICorrectCheckBox": "AI Correct (beta)",
        "OpenAIFormatLabel":"OpenAI Format API",
        "OpenAIConfirm":"Confirm",
        "OpenAIRegisterButton":"Register",
        }
}
placeholder_translations = {
    "cn": {
        "FindInput": "查找文本",
        "ReplaceInput": "替换文本"
    },
    "en": {
        "FindInput": "Find text",
        "ReplaceInput": "Replace with"
    }
}

STATUS_MESSAGES = {
    "enter_find_text": {"cn": "请输入查找文本", "en": "Enter text to search."},
    "matches_rows_occ": {"cn": "包含条目：%d 条；出现次数：%d 处", "en": "Found %d rows / %d matches."},
    "no_find_results": {"cn": "未找到匹配字幕", "en": "No matches found."},
    "match_progress": {"cn": "匹配项：第 %d 个结果，共 %d 个结果", "en": "Match %d of %d."},
    "replace_no_find": {"cn": "请先填写查找文本", "en": "Specify text to find first."},
    "no_replace": {"cn": "未替换任何字幕", "en": "No replacement performed."},
    "replace_done": {"cn": "完成替换，共 %d 处", "en": "Replaced %d occurrence(s)."}
}


""
items = whisper_win.GetItems()
msg_items = msgbox.GetItems()
openai_items = openai_config_window.GetItems()
match_items = match_window.GetItems()

tree_widget = items.get("SubtitleTree")
if tree_widget:
    applied = False
    for attr in ("SetSelectionMode", "setSelectionMode"):
        setter = getattr(tree_widget, attr, None)
        if callable(setter):
            try:
                setter("SingleSelection")
                applied = True
                break
            except Exception:
                pass
    if not applied:
        try:
            tree_widget.SelectionMode = "SingleSelection"
        except Exception:
            pass

items["SubtitleTree"].SetHeaderLabels(["#", "Start", "End", "Subtitle"]) 
items["SubtitleTree"].ColumnWidth[0] = 50    # 文件名
items["SubtitleTree"].ColumnWidth[1] = 50    # 开始TC
items["SubtitleTree"].ColumnWidth[2] = 50    # 结束TC
for lang_display_name in LANGUAGE_MAP.keys():
    items["LangCombo"].AddItem(lang_display_name)

FIND_HIGHLIGHT_COLOR = {"R": 0.40, "G": 0.40, "B": 0.40, "A": 0.60}
TRANSPARENT_COLOR = {"R": 0.0, "G": 0.0, "B": 0.0, "A": 0.0}

def _is_find_highlight_color(color, tolerance=1e-6):
    if not isinstance(color, dict):
        return False
    try:
        return all(abs(float(color.get(component, 0.0)) - float(FIND_HIGHLIGHT_COLOR.get(component, 0.0))) <= tolerance for component in ("R", "G", "B"))
    except Exception:
        return False

_last_status_key = None
_last_status_args = ()
_find_query = ""
_find_matches = []
_find_index = 0
_current_match_highlight = None
_sticky_highlights = set()
_find_rows = 0
_find_occurrences = 0
_suppress_tree_event = False

def update_status(key, *args):
    global _last_status_key, _last_status_args
    _last_status_key = key
    _last_status_args = args
    label = items.get("StatusLabel")
    if not label:
        return
    if key is None:
        label.Text = ""
        return
    lang_checkbox = items.get("LangEnCheckBox")
    lang = "en" if lang_checkbox and lang_checkbox.Checked else "cn"
    templates = STATUS_MESSAGES.get(key)
    text = None
    if templates:
        text = templates.get(lang) or templates.get("cn")
    if text is None:
        text = str(key)
    try:
        label.Text = text % args if args else text
    except Exception:
        label.Text = text

def populate_models(use_openai):
    provider = openai_provider if use_openai else faster_whisper_provider
    items["AICorrectCheckBox"].Enabled = not use_openai
    items["DownloadButton"].Enabled = not use_openai
    items["AICorrectCheckBox"].Checked = False
    if use_openai:
        openai_config_window.Show() 
    else:
        openai_config_window.Hide()
    items["ModelCombo"].Clear()
    for model in provider.get_available_models():
        items["ModelCombo"].AddItem(model)

def on_ai_correct_clicked(ev):
    checked = items["AICorrectCheckBox"].Checked
    if checked:
        items["MatchTextCheckBox"].Checked = False
        items["MatchTextCheckBox"].Enabled = False
        openai_config_window.Show()
        match_window.Hide()
    else:
        items["MatchTextCheckBox"].Enabled = True
        openai_config_window.Hide()

whisper_win.On.AICorrectCheckBox.Clicked = on_ai_correct_clicked

def on_match_checkbox_clicked(ev):
    checked = items["MatchTextCheckBox"].Checked
    if checked:
        # 勾选文稿匹配 -> 取消并禁用 AI Correct，弹窗输入文稿
        items["AICorrectCheckBox"].Checked = False
        items["AICorrectCheckBox"].Enabled = False
        match_window.Show()
        whisper_win.Hide()
    else:
        # 取消勾选 -> 恢复 AI Correct 的可用
        items["AICorrectCheckBox"].Enabled = True
        match_window.Hide()

whisper_win.On.MatchTextCheckBox.Clicked = on_match_checkbox_clicked

def on_match_confirm(ev):
    match_window.Hide()  # 保持“文稿匹配”勾选状态不变
    whisper_win.Show()

def on_match_cancel(ev):
    # 取消则恢复现场：撤销勾选、恢复 AI Correct
    items["MatchTextCheckBox"].Checked = False
    items["AICorrectCheckBox"].Enabled = True
    match_window.Hide()
    whisper_win.Show()

match_window.On.MatchConfirmBtn.Clicked = on_match_confirm
match_window.On.MatchCancelBtn.Clicked  = on_match_cancel
match_window.On.ScriptMatchWin.Close    = on_match_cancel

def on_provider_switch(ev):
    populate_models(items["OnlineCheckBox"].Checked)
whisper_win.On.OnlineCheckBox.Clicked = on_provider_switch
populate_models(False) # Initial population

def switch_language(lang):
    for item_id, text_value in translations[lang].items():
        if item_id in items:
            items[item_id].Text = text_value
        elif item_id in openai_items:    
            openai_items[item_id].Text = text_value
        elif item_id in match_items:   
            match_items[item_id].Text = text_value
        else:
            print(f"[Warning] No control with ID {item_id} exists in items, so the text cannot be set!")
    placeholders = placeholder_translations.get(lang, {})
    find_widget = items.get("FindInput")
    replace_widget = items.get("ReplaceInput")
    if find_widget and "FindInput" in placeholders:
        find_widget.PlaceholderText = placeholders["FindInput"]
    if replace_widget and "ReplaceInput" in placeholders:
        replace_widget.PlaceholderText = placeholders["ReplaceInput"]
    update_status(_last_status_key, *_last_status_args)

def on_lang_checkbox_clicked(ev):
    is_en_checked = ev['sender'].ID == "LangEnCheckBox"
    items["LangCnCheckBox"].Checked = not is_en_checked
    items["LangEnCheckBox"].Checked = is_en_checked
    switch_language("en" if is_en_checked else "cn")

whisper_win.On.LangCnCheckBox.Clicked = on_lang_checkbox_clicked
whisper_win.On.LangEnCheckBox.Clicked = on_lang_checkbox_clicked

def on_openai_close(ev):
    print("OpenAI API 配置完成")
    openai_config_window.Hide()
openai_config_window.On.OpenAIConfirm.Clicked = on_openai_close
openai_config_window.On.OpenAIConfigWin.Close = on_openai_close

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

saved_settings = load_settings(SETTINGS)

if saved_settings:
    openai_items["OpenAIFormatBaseURL"].Text = saved_settings.get("OPENAI_FORMAT_BASE_URL", DEFAULT_SETTINGS["OPENAI_FORMAT_BASE_URL"])
    openai_items["OpenAIFormatApiKey"].Text = saved_settings.get("OPENAI_FORMAT_API_KEY", DEFAULT_SETTINGS["OPENAI_FORMAT_API_KEY"])
    #items["OnlineCheckBox"].Checked = saved_settings.get("PROVIDER", DEFAULT_SETTINGS["PROVIDER"])
    items["ModelCombo"].CurrentIndex = saved_settings.get("MODEL", DEFAULT_SETTINGS["MODEL"])
    items["LangCombo"].CurrentIndex = saved_settings.get("LANGUAGE", DEFAULT_SETTINGS["LANGUAGE"])
    items["MaxChars"].Value = saved_settings.get("MAX_CHARS", DEFAULT_SETTINGS["MAX_CHARS"])
    items["NoGapCheckBox"].Checked = saved_settings.get("REMOVE_GAPS", DEFAULT_SETTINGS["REMOVE_GAPS"])
    items["TrimPunctCheckBox"].Checked = saved_settings.get("TRIM_PUNCT", DEFAULT_SETTINGS["TRIM_PUNCT"])
    items["LangCnCheckBox"].Checked = saved_settings.get("CN", DEFAULT_SETTINGS["CN"])
    items["LangEnCheckBox"].Checked = saved_settings.get("EN", DEFAULT_SETTINGS["EN"])
    #items["AICorrectCheckBox"].Checked = saved_settings.get("SMART", DEFAULT_SETTINGS["SMART"])
if items["LangEnCheckBox"].Checked :
    switch_language("en")
else:
    switch_language("cn")

items["OnlineCheckBox"].Enabled=False

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

def load_audio_only_preset(project, keyword="audio only"):
    presets = project.GetRenderPresetList() or []
    def norm(x): return (x if isinstance(x, str) else x.get("PresetName","")).lower()
    hit = next((p for p in presets if keyword in norm(p)), None)
    if hit:
        name = hit if isinstance(hit, str) else hit.get("PresetName")
        if project.LoadRenderPreset(name): return name
    if project.LoadRenderPreset("Audio Only"): return "Audio Only"
    return None

def render_timeline_audio(output_dir: str, custom_name: str) -> Optional[str]:
    resolve, project, _, _, timeline, _ = connect_resolve()
    if not project or not timeline: return None
    render_preset = "render_to_mp3"
    #render_preset = "Audio Only"
    resolve.ImportRenderPreset(os.path.join(SCRIPT_PATH, "render_preset", f"{render_preset}.xml"))
    project.LoadRenderPreset(render_preset)
    
    # ② 强制指定想要的格式/编码器（可选，但最稳妥）
    #project.SetCurrentRenderFormatAndCodec("MP3", "Linear PCM")   # 或 ("MP4","aac")
    #load_audio_only_preset(project)
    os.makedirs(output_dir, exist_ok=True)
    render_settings = {
        "SelectAllFrames": True, 
        "ExportVideo": False, 
        "ExportAudio": True,
        "TargetDir": output_dir, 
        "CustomName": custom_name,
        "AudioSampleRate": 48000, 
        "AudioCodec": "mp3", 
        "AudioBitDepth": 16,
    }
    project.SetRenderSettings(render_settings)

    job_id = project.AddRenderJob()
    print(f"Render job added, ID: {job_id}")

    if not job_id: 
        return None
    
    project.StartRendering([job_id], isInteractiveMode=False)
    print("Rendering in progress, waiting for completion...")
    while project.IsRenderingInProgress():
        print("Rendering...")
        time.sleep(2)
    print("Render complete!")
    project.DeleteRenderJob(job_id) # 
    return os.path.join(output_dir, f"{custom_name}.mp3")


def _count_occurrences(haystack: str, needle: str) -> int:
    if not haystack or not needle:
        return 0
    start = 0
    total = 0
    while True:
        idx = haystack.find(needle, start)
        if idx == -1:
            break
        total += 1
        start = idx + 1
    return total

def _current_selection_index() -> Optional[int]:
    if not _selected_row_id:
        return None
    try:
        return int(_selected_row_id)
    except (TypeError, ValueError):
        return None

def _clear_tree_selection():
    tree = items.get("SubtitleTree")
    if not tree:
        return
    cleared = False
    for attr in ("ClearSelection", "clearSelection"):
        method = getattr(tree, attr, None)
        if callable(method):
            try:
                method()
                cleared = True
                break
            except Exception:
                pass
    if cleared:
        return
    try:
        selected = tree.SelectedItems()
    except Exception:
        selected = None
    if isinstance(selected, (list, tuple)):
        for entry in selected:
            try:
                entry.Selected = False
            except Exception:
                pass

def _select_only_tree_row(entry_index):
    tree = items.get("SubtitleTree")
    if not tree or entry_index is None:
        return
    target_row = max(0, int(entry_index) - 1)
    try:
        total_rows = tree.TopLevelItemCount()
    except Exception:
        total_rows = len(_subtitle_blocks_state)
    for row in range(total_rows):
        try:
            row_item = tree.TopLevelItem(row)
        except Exception:
            row_item = None
        if not row_item:
            continue
        try:
            row_item.Selected = (row == target_row)
        except Exception:
            pass

def _clear_current_highlight(preserve_if_still_match=False):
    global _current_match_highlight
    if not _current_match_highlight:
        return
    tree = items.get("SubtitleTree")
    if not tree:
        _current_match_highlight = None
        return
    idx = _current_match_highlight
    try:
        item = tree.TopLevelItem(idx - 1)
    except Exception:
        item = None
    _current_match_highlight = None
    if not item:
        return
    text = item.Text[3] or ""
    if preserve_if_still_match and _find_query and _find_query in text:
        item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
        _current_match_highlight = idx
        return
    if idx in _sticky_highlights:
        item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
        return
    try:
        item.BackgroundColor[3] = TRANSPARENT_COLOR
    except Exception:
        item.BackgroundColor[3] = None

def _clear_all_find_highlights(force=False):
    global _current_match_highlight, _sticky_highlights
    tree = items.get("SubtitleTree")
    if not tree:
        return
    try:
        total_rows = tree.TopLevelItemCount()
    except Exception:
        total_rows = len(_subtitle_blocks_state)
    for row in range(total_rows):
        try:
            item = tree.TopLevelItem(row)
        except Exception:
            item = None
        if not item:
            continue
        row_index = row + 1
        if not force and row_index in _sticky_highlights:
            continue
        try:
            current_color = item.BackgroundColor[3]
        except Exception:
            current_color = None
        if force or _is_find_highlight_color(current_color):
            try:
                item.BackgroundColor[3] = TRANSPARENT_COLOR
            except Exception:
                item.BackgroundColor[3] = None
    if force:
        _sticky_highlights.clear()
    _current_match_highlight = None

def _reset_find_state(clear_query=False):
    global _find_matches, _find_index, _find_rows, _find_occurrences, _find_query, _sticky_highlights, _current_match_highlight
    _clear_all_find_highlights(force=True)
    _find_matches = []
    _find_index = 0
    _find_rows = 0
    _find_occurrences = 0
    if clear_query:
        _find_query = ""
    else:
        find_widget = items.get("FindInput")
        _find_query = (find_widget.Text if find_widget else _find_query) or ""
    _sticky_highlights.clear()
    _current_match_highlight = None
    update_status(None)

def _apply_tree_item_logic(item, do_timeline=True):
    global _selected_row_id, _editor_programmatic
    if not item:
        return False
    start_tc = (item.Text[1] or "").strip()
    if do_timeline and start_tc:
        try:
            resolve, project, _, _, timeline, _ = connect_resolve()
        except Exception:
            resolve, timeline = None, None
        if resolve and timeline:
            try:
                current_page = resolve.GetCurrentPage()
                if current_page not in ("cut", "edit", "color", "fairlight", "deliver"):
                    resolve.OpenPage("edit")
            except Exception:
                pass
            try:
                timeline.SetCurrentTimecode(start_tc)
            except Exception:
                pass
    _selected_row_id = item.Text[0] or ""
    editor_widget = items.get("SubtitleEditor")
    if editor_widget:
        try:
            _editor_programmatic = True
            editor_widget.Text = item.Text[3] or ""
        finally:
            _editor_programmatic = False
    return True

def _jump_to_tree_row(entry_index, do_timeline=True, ensure_visible=True):
    tree = items.get("SubtitleTree")
    if not tree or entry_index is None:
        return False
    try:
        item = tree.TopLevelItem(entry_index - 1)
    except Exception:
        item = None
    if not item:
        return False
    global _suppress_tree_event
    if ensure_visible:
        _suppress_tree_event = True
        try:
            _clear_tree_selection()
            try:
                setter = getattr(tree, "SetCurrentItem", None)
                if callable(setter):
                    setter(item)
                else:
                    tree.CurrentItem = item
            except Exception:
                tree.CurrentItem = item
            _select_only_tree_row(entry_index)
        finally:
            _suppress_tree_event = False
    else:
        _select_only_tree_row(entry_index)
    try:
        tree.ScrollToItem(item)
    except Exception:
        pass
    return _apply_tree_item_logic(item, do_timeline)

def _refresh_find_matches():
    global _find_query, _find_matches, _find_index, _find_rows, _find_occurrences
    find_widget = items.get("FindInput")
    tree = items.get("SubtitleTree")
    if not find_widget or not tree:
        return False
    query = find_widget.Text or ""
    _find_query = query
    _find_matches = []
    _find_index = 0
    _find_rows = 0
    _find_occurrences = 0
    _clear_all_find_highlights()
    if not query:
        update_status("enter_find_text")
        return False
    matches = []
    total_occ = 0
    for idx, block in enumerate(_subtitle_blocks_state, 1):
        text = block.get("text", "") or ""
        occ = _count_occurrences(text, query)
        if occ:
            matches.append(idx)
            total_occ += occ
            try:
                item = tree.TopLevelItem(idx - 1)
                if item:
                    item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
            except Exception:
                pass
    if not matches:
        update_status("no_find_results")
        return False
    _find_matches = matches
    _find_index = 1
    _find_rows = len(matches)
    _find_occurrences = total_occ
    update_status("matches_rows_occ", len(matches), total_occ)
    return True

def _ensure_find_matches():
    find_widget = items.get("FindInput")
    if not find_widget:
        return False
    query = find_widget.Text or ""
    if not query:
        update_status("enter_find_text")
        return False
    if query != _find_query or not _find_matches:
        return _refresh_find_matches()
    if _find_matches:
        return True
    return _refresh_find_matches()

def _goto_next_match():
    global _find_index, _current_match_highlight
    if not _ensure_find_matches():
        return None
    if not _find_matches:
        update_status("no_find_results")
        return None
    idx = _find_index or 1
    if idx > len(_find_matches):
        idx = 1
    entry_index = _find_matches[idx - 1]
    _find_index = idx + 1 if idx < len(_find_matches) else 1
    _clear_current_highlight(preserve_if_still_match=True)
    if _jump_to_tree_row(entry_index, do_timeline=True, ensure_visible=True):
        _current_match_highlight = entry_index
        tree = items.get("SubtitleTree")
        if tree:
            try:
                item = tree.TopLevelItem(entry_index - 1)
                if item:
                    item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
            except Exception:
                pass
        update_status("match_progress", idx, len(_find_matches))
        return entry_index
    return None

def _apply_replace_all():
    global _find_matches, _find_index, _current_match_highlight, _editor_programmatic, _sticky_highlights
    find_widget = items.get("FindInput")
    replace_widget = items.get("ReplaceInput")
    if not find_widget:
        return
    find_text = find_widget.Text or ""
    if not find_text:
        update_status("replace_no_find")
        return
    replace_text = (replace_widget.Text if replace_widget else "") or ""
    total_replaced = 0
    tree = items.get("SubtitleTree")
    for idx, block in enumerate(_subtitle_blocks_state, 1):
        text = block.get("text", "") or ""
        count = text.count(find_text)
        if count:
            new_text = text.replace(find_text, replace_text)
            block["text"] = new_text
            total_replaced += count
            if tree:
                try:
                    item = tree.TopLevelItem(idx - 1)
                    if item:
                        item.Text[3] = new_text
                        item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
                except Exception:
                    pass
            if str(idx) == (_selected_row_id or ""):
                editor_widget = items.get("SubtitleEditor")
                if editor_widget:
                    try:
                        _editor_programmatic = True
                        editor_widget.Text = new_text
                    finally:
                        _editor_programmatic = False
            _sticky_highlights.add(idx)
    if total_replaced == 0:
        update_status("no_replace")
        return
    _current_match_highlight = None
    _find_matches = []
    _find_index = 0
    _refresh_find_matches()
    update_status("replace_done", total_replaced)

def _replace_single():
    global _find_matches, _find_index, _current_match_highlight, _editor_programmatic, _sticky_highlights
    find_widget = items.get("FindInput")
    replace_widget = items.get("ReplaceInput")
    if not find_widget:
        return
    find_text = find_widget.Text or ""
    if not find_text:
        update_status("replace_no_find")
        return
    if not _ensure_find_matches():
        return
    def current_contains():
        idx = _current_selection_index()
        if idx is None or not (1 <= idx <= len(_subtitle_blocks_state)):
            return False
        text = _subtitle_blocks_state[idx - 1].get("text", "") or ""
        return find_text in text
    attempts = 0
    max_attempts = len(_find_matches)
    while not current_contains() and attempts < max_attempts:
        jumped = _goto_next_match()
        attempts += 1
        if not jumped:
            break
    if not current_contains():
        update_status("no_replace")
        return
    replace_text = (replace_widget.Text if replace_widget else "") or ""
    idx = _current_selection_index()
    if idx is None:
        update_status("no_replace")
        return
    text = _subtitle_blocks_state[idx - 1].get("text", "") or ""
    count = text.count(find_text)
    if count == 0:
        update_status("no_replace")
        return
    new_text = text.replace(find_text, replace_text)
    _subtitle_blocks_state[idx - 1]["text"] = new_text
    tree = items.get("SubtitleTree")
    if tree:
        try:
            item = tree.TopLevelItem(idx - 1)
            if item:
                item.Text[3] = new_text
                item.BackgroundColor[3] = FIND_HIGHLIGHT_COLOR
        except Exception:
            pass
    editor_widget = items.get("SubtitleEditor")
    if editor_widget:
        try:
            _editor_programmatic = True
            editor_widget.Text = new_text
        finally:
            _editor_programmatic = False
    _sticky_highlights.add(idx)
    _current_match_highlight = None
    _find_matches = []
    _find_index = 0
    if _refresh_find_matches():
        matches = list(_find_matches)
        if matches:
            next_index = 1
            for position, entry_idx in enumerate(matches, 1):
                if entry_idx > idx:
                    next_index = position
                    break
            else:
                next_index = 1
            _find_index = next_index
            #_goto_next_match()
    else:
        update_status("match_progress", 0, 0)

def _on_find_input_text_changed(ev):
    global _find_query, _find_matches, _find_index, _find_rows, _find_occurrences, _current_match_highlight, _sticky_highlights
    find_widget = items.get("FindInput")
    _find_query = (find_widget.Text if find_widget else "") or ""
    _find_matches = []
    _find_index = 0
    _find_rows = 0
    _find_occurrences = 0
    _clear_all_find_highlights(force=True)
    _sticky_highlights.clear()
    _current_match_highlight = None
    update_status(None)

def _on_find_input_editing_finished(ev):
    _refresh_find_matches()

def _on_find_button_clicked(ev):
    _goto_next_match()

def _on_all_replace_clicked(ev):
    _apply_replace_all()

def _on_single_replace_clicked(ev):
    _replace_single()

_editor_programmatic = False
_selected_row_id = None
_subtitle_blocks_state = []
# —— 新增：把 subtitle_blocks 刷新到 Tree —— 
def _frames_to_timecode(total_frames: int, fps) -> str:
    int_fps = _fps_timebase(fps)
    if total_frames < 0:
        total_frames = 0
    frames = total_frames % int_fps
    total_seconds = total_frames // int_fps
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    s = total_seconds % 60
    return f"{h:02d}:{m:02d}:{s:02d}:{frames:02d}"

def _secs_to_abs_timecode(seconds: float, fps, start_frame: int) -> str:
    fps_frac = _fps_to_fraction(fps)
    rel_frames = int(round(seconds * float(fps_frac)))
    return _frames_to_timecode(start_frame + rel_frames, fps_frac)

def _refresh_subtitle_tree(subtitle_blocks):
    global _subtitle_blocks_state
    _subtitle_blocks_state = [dict(blk) for blk in subtitle_blocks]
    try:
        _, project, _, _, timeline, fps = connect_resolve()
        start_frame = timeline.GetStartFrame() or 0   # ???
    except Exception:
        fps = FPS_FALLBACK
        start_frame = 0

    tree = items.get("SubtitleTree")
    if not tree:
        return
    _reset_find_state(clear_query=False)
    tree.Clear()
    tree.SetHeaderLabels(["#", "Start", "End", "Subtitle"])

    for idx, blk in enumerate(subtitle_blocks, 1):
        itm = tree.NewItem()
        itm.Text[0] = str(idx)
        itm.Text[1] = _secs_to_abs_timecode(blk["start"], fps, start_frame)  # ?? Start
        itm.Text[2] = _secs_to_abs_timecode(blk["end"],   fps, start_frame)  # ?? End
        itm.Text[3] = blk["text"].replace("\n", " ")
        tree.AddTopLevelItem(itm)
    if _find_query:
        _refresh_find_matches()


    tree = items.get("SubtitleTree")
    if not tree:
        return
    tree.Clear()
    tree.SetHeaderLabels(["#", "Start", "End", "Subtitle"])

    for idx, blk in enumerate(subtitle_blocks, 1):
        itm = tree.NewItem()
        itm.Text[0] = str(idx)
        itm.Text[1] = _secs_to_abs_timecode(blk["start"], fps, start_frame)  # 绝对 Start
        itm.Text[2] = _secs_to_abs_timecode(blk["end"],   fps, start_frame)  # 绝对 End
        itm.Text[3] = blk["text"].replace("\n", " ")
        tree.AddTopLevelItem(itm)


# 点击 Tree 的行，跳转到对应字幕开始时间码
def _on_subtitle_tree_item_clicked(ev):
    global _suppress_tree_event
    if _suppress_tree_event:
        return
    tree = items.get("SubtitleTree")
    if not tree:
        return
    item = tree.CurrentItem()
    if not item:
        return
    try:
        entry_index = int(item.Text[0])
    except (TypeError, ValueError):
        entry_index = None
    _suppress_tree_event = True
    try:
        _clear_tree_selection()
        if entry_index is not None:
            _select_only_tree_row(entry_index)
        else:
            try:
                item.Selected = True
            except Exception:
                pass
    finally:
        _suppress_tree_event = False
    _apply_tree_item_logic(item, do_timeline=True)
whisper_win.On['SubtitleTree'].ItemClicked = _on_subtitle_tree_item_clicked

def _on_subtitle_editor_text_changed(ev):
    global _editor_programmatic, _selected_row_id
    if _editor_programmatic:
        return  # 程序化赋值时不回写，避免循环

    tree = items["SubtitleTree"]
    itm = tree.CurrentItem()
    if not itm:
        return
    curr_id = itm.Text[0] or ""
    if _selected_row_id and curr_id != _selected_row_id:
        return
    new_text = items["SubtitleEditor"].PlainText or ""
    itm.Text[3] = new_text 
    try:
        idx = int(itm.Text[0])  # 第一列是序号，从 1 开始
        if 1 <= idx <= len(_subtitle_blocks_state):
            _subtitle_blocks_state[idx - 1]["text"] = new_text
    except Exception:
        pass
whisper_win.On['SubtitleEditor'].TextChanged = _on_subtitle_editor_text_changed

whisper_win.On.FindInput.TextChanged = _on_find_input_text_changed
whisper_win.On.FindInput.EditingFinished = _on_find_input_editing_finished
whisper_win.On.FindButton.Clicked = _on_find_button_clicked
whisper_win.On.AllReplaceButton.Clicked = _on_all_replace_clicked
whisper_win.On.SingleReplaceButton.Clicked = _on_single_replace_clicked

def _quantize_and_fix_blocks(blocks, fps, enforce_no_gaps=False, min_frames=1):
    """
    将字幕块按帧量化，并确保：
    1) start/end 至少相差 min_frames 帧；
    2) 不与上一条重叠；
    3) 勾选了“无空隙”时，后一条 start == 前一条 end（但仍保证至少 1 帧时长）。
    返回：新的 blocks（start/end 仍然用秒表示）。
    """
    fps_frac = _fps_to_fraction(fps)
    fps_float = float(fps_frac)
    fixed = []
    prev_end_f = 0

    for blk in blocks:
        start_sec = float(blk.get("start", 0.0))
        end_sec = float(blk.get("end", 0.0))
        s_f = int(round(start_sec * fps_float))
        e_f = int(round(end_sec * fps_float))

        # 无空隙：下一条的 start 钳到上一条 end
        if enforce_no_gaps:
            s_f = max(s_f, prev_end_f)
        else:
            # 允许存在空隙，但绝不允许“向前穿插/重叠”
            s_f = max(s_f, prev_end_f)

        # 至少 1 帧时长
        if e_f <= s_f:
            e_f = s_f + min_frames

        fixed.append({
            "start": s_f / fps_float,
            "end"  : e_f / fps_float,
            "text" : blk.get("text", "")
        })
        prev_end_f = e_f

    return fixed

def _format_srt_time(seconds: float) -> str:
    # 与 provider 内部一致：HH:MM:SS,mmm
    ms = int(round((seconds - int(seconds)) * 1000))
    s = int(seconds)
    hh = s // 3600
    mm = (s % 3600) // 60
    ss = s % 60
    return f"{hh:02d}:{mm:02d}:{ss:02d},{ms:03d}"

def _write_srt_from_blocks(blocks, srt_path: str):
    with open(srt_path, "w", encoding="utf-8") as f:
        for i, blk in enumerate(blocks, 1):
            f.write(f"{i}\n")
            f.write(f"{_format_srt_time(float(blk['start']))} --> {_format_srt_time(float(blk['end']))}\n")
            f.write((blk["text"] or "").strip() + "\n\n")

def on_update_subtitle_clicked(ev):
    # 1) 基本校验
    if not _subtitle_blocks_state:
        show_dynamic_message("No subtitle data to export.", "没有可导出的字幕数据。")
        return

    resolve, project, _, _, timeline, _ = connect_resolve()
    if not timeline:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return

    # 2) 生成输出路径（自增序号）
    timeline_name = timeline.GetName()
    os.makedirs(SUB_TEMP_DIR, exist_ok=True)
    pattern = os.path.join(SUB_TEMP_DIR, f"{timeline_name}_subtitle_update_{RAND_CODE}_*.srt")

    indices = []
    for p in glob.glob(pattern):
        m = re.search(rf"_{RAND_CODE}_(\d+)\.srt$", os.path.basename(p))
        if m:
            try:
                indices.append(int(m.group(1)))
            except ValueError:
                pass
    next_idx = max(indices) + 1 if indices else 1
    filename = f"{timeline_name}_subtitle_update_{RAND_CODE}_{next_idx}"
    srt_path = os.path.join(SUB_TEMP_DIR, f"{filename}.srt")
    # 3-) 量化并修复（使用当前时间线帧率）
    try:
        _, _, _, _, _, fps_now = connect_resolve()
    except Exception:
        fps_now = FPS_FALLBACK

    sanitized_blocks = _quantize_and_fix_blocks(
        _subtitle_blocks_state,
        fps=fps_now,
        enforce_no_gaps=items["NoGapCheckBox"].Checked,
        min_frames=1
    )
    # 3) 写 SRT（以内存状态为准，避免绝对 TC 偏移）
    try:
        _write_srt_from_blocks(sanitized_blocks, srt_path)
    except Exception as e:
        show_dynamic_message(f"Write SRT failed: {e}", f"写入 SRT 失败：{e}")
        return

    # 4) 导入时间线（复用你已有的方法）
    ok = import_srt_to_first_empty(srt_path)
    if ok:
        show_dynamic_message("Updated SRT imported.", "更新后的 SRT 已导入。")
    else:
        show_dynamic_message("Failed to import SRT.", "导入 SRT 失败。")
whisper_win.On.UpdateSubtitleButton.Clicked = on_update_subtitle_clicked

def on_create_clicked(ev):
    resolve, _, _, _, timeline, _ = connect_resolve()
    if not timeline:
        show_dynamic_message("No active timeline.", "没有激活的时间线。")
        return
        
    timeline_name = timeline.GetName()
    safe_name = timeline_name.replace(" ", "_")
    audio_file_prefix = f"{safe_name}_audio_temp"
    audio_path = os.path.join(AUDIO_TEMP_DIR, f"{audio_file_prefix}.mp3")
    
    raw_hotwords = items["Hotwords"].PlainText or ""
    hotwords_list = [
        ph.strip() 
        for ph in re.split(r"[，,、；;]\s*|\s+", raw_hotwords) 
        if ph.strip()
    ]
    
    def update_transcribe_progress(progress):
        show_dynamic_message(f"Transcribing... {progress:.1f}%", f"转录中... {progress:.1f}%")
    
    try:
        show_dynamic_message("Checking for cached audio...", "检查音频缓存...")
        print(f"Checking for existing audio file with prefix '{audio_file_prefix}'")
        if not os.path.exists(audio_path):
            show_dynamic_message("Rendering audio...", "音频处理中...")
            audio_path = render_timeline_audio(output_dir=AUDIO_TEMP_DIR, custom_name=audio_file_prefix)
        else:
            print(f"Found cached audio: {audio_path}. Skipping render.")

        if not audio_path:
            show_dynamic_message("Failed to get audio file.", "获取音频文件失败。")
            return

        pattern = os.path.join(SUB_TEMP_DIR, f"{timeline_name}_subtitle_*.srt")
        indices = [int(f.split('_')[-1].split('.')[0]) for f in glob.glob(pattern) if f.split('_')[-1].split('.')[0].isdigit()]
        next_idx = max(indices) + 1 if indices else 1
        filename = f"{timeline_name}_subtitle_{RAND_CODE}_{next_idx}"

        show_dynamic_message("Transcribing... 0.0%", "转录中... 0.0%")
        resolve.OpenPage("edit")
        
        # Determine which provider to use
        use_openai = items["OnlineCheckBox"].Checked
        match_enabled = items["MatchTextCheckBox"].Checked
        provider = openai_provider if use_openai else faster_whisper_provider

        transcribe_params = {
            "input_audio": audio_path,
            "base_url":openai_items["OpenAIFormatBaseURL"].Text,
            "api_key":openai_items["OpenAIFormatApiKey"].Text,
            "model_name": items["ModelCombo"].CurrentText,
            "language": LANGUAGE_MAP.get(items["LangCombo"].CurrentText),
            "output_dir": SUB_TEMP_DIR,
            "output_filename": filename,
            "max_chars": items["MaxChars"].Value,
            "hotwords": ",".join(hotwords_list) if hotwords_list else None,
            "progress_callback": update_transcribe_progress,
            "remove_gaps": items["NoGapCheckBox"].Checked
        }
        transcribe_params.update({
            "match_text": match_items["MatchTextEdit"].PlainText if match_enabled else None
        })
        # Add provider-specific parameters
        if not use_openai:
            transcribe_params.update({"batch_size": 4, "vad_filter": True})
        
        srt_path = provider.transcribe(**transcribe_params)
        
        if srt_path:
            import_srt_to_first_empty(srt_path)
            
        else:
            print("Failed to generate SRT. Provider might have failed.")
            if not use_openai:
                show_dynamic_message("Model file is missing. Click the 'Download Model' button.", "缺少模型文件,请点击模型下载按钮。")
            # OpenAI provider shows its own specific error messages
            
    except Exception as e:
        show_dynamic_message(f"Error: {e}", f"错误: {e}")
        print(f"An error occurred: {e}")
        
whisper_win.On.CreateButton.Clicked = on_create_clicked

def on_download_clicked(ev):
    show_dynamic_message("Place the downloaded model into the plugin's model folder.","请将下载的模型放入插件的 model 文件夹。")
    url = MODEL_LINK_EN if items["LangEnCheckBox"].Checked else MODEL_LINK_CN
    # Optionally also open the model download page
    time.sleep(2)
    webbrowser.open(url)
    # Ensure the model folder exists and open it in the OS file explorer
    model_dir = os.path.join(SCRIPT_PATH, "model")
    os.makedirs(model_dir, exist_ok=True)
    try:
        if sys.platform.startswith('darwin'):
            subprocess.Popen(["open", model_dir])
        elif os.name == 'nt':
            os.startfile(model_dir)
        else:
            subprocess.Popen(["xdg-open", model_dir])
    except Exception as e:
        show_dynamic_message(f"Unable to open model folder: {e}", f"无法打开模型文件夹: {e}")

    
whisper_win.On.DownloadButton.Clicked = on_download_clicked
    
def on_open_link_button_clicked(ev):
    url = SCRIPT_KOFI_URL if items["LangEnCheckBox"].Checked else SCRIPT_BILIBILI_URL
    webbrowser.open(url)
whisper_win.On.CopyrightButton.Clicked = on_open_link_button_clicked

def save_file():
    settings = {
        "OPENAI_FORMAT_BASE_URL": openai_items["OpenAIFormatBaseURL"].Text,
        "OPENAI_FORMAT_API_KEY": openai_items["OpenAIFormatApiKey"].Text,
        "PROVIDER":items["OnlineCheckBox"].Checked,
        "MODEL": items["ModelCombo"].CurrentIndex,
        "LANGUAGE": items["LangCombo"].CurrentIndex,
        "MAX_CHARS": items["MaxChars"].Value,
        "SMART":items["AICorrectCheckBox"].Checked,
        "REMOVE_GAPS": items["NoGapCheckBox"].Checked,
        "TRIM_PUNCT": items["TrimPunctCheckBox"].Checked,
        "CN":items["LangCnCheckBox"].Checked,
        "EN":items["LangEnCheckBox"].Checked,
    }
    
    settings_file = os.path.join(SCRIPT_PATH, "config", "settings.json")
    try:
        os.makedirs(os.path.dirname(settings_file), exist_ok=True)
        
        with open(settings_file, 'w', encoding='utf-8') as f:
            json.dump(settings, f, ensure_ascii=False, indent=4)
        print(f"Settings saved to {settings_file}")
    except OSError as e:
        print(f"Error saving settings to {settings_file}: {e.strerror}")

def on_close(ev):
    for temp_dir in [AUDIO_TEMP_DIR, SUB_TEMP_DIR]:
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                print(f"Removed temporary directory: {temp_dir}")
            except OSError as e:
                print(f"Error removing directory {temp_dir}: {e.strerror}")
    save_file()
    dispatcher.ExitLoop()
whisper_win.On.WhisperWin.Close = on_close
# ================== >>> 新增：把时间线现有字幕加载到 Tree ==================

def _frames_to_seconds(frames: int, fps) -> float:
    fps_frac = _fps_to_fraction(fps)
    return float(frames) / float(fps_frac)

def _collect_subtitles_from_timeline(timeline) -> list:
    """
    从【当前时间线】采集启用的字幕轨上的字幕项，返回形如：
    [{"start": <相对秒>, "end": <相对秒>, "text": <字符串>}, ...]
    注意：start/end 为【相对时间线起点】的秒值（而非绝对帧换算的秒），
    以适配你已有的 _refresh_subtitle_tree 内部“起始帧 + 相对秒 → 绝对TC”的逻辑。
    """
    blocks = []
    if not timeline:
        return blocks

    try:
        fps = _get_timeline_fps(timeline)
    except Exception:
        # 回退到 connect_resolve 的 fps
        try:
            _, _, _, _, _, fps = connect_resolve()
        except Exception:
            fps = FPS_FALLBACK

    try:
        start_frame_base = timeline.GetStartFrame() or 0
    except Exception:
        start_frame_base = 0

    try:
        track_count = timeline.GetTrackCount("subtitle") or 0
    except Exception:
        track_count = 0

    print(f"[load] subtitle tracks = {track_count}")

    for track_index in range(1, track_count + 1):
        try:
            if not timeline.GetIsTrackEnabled("subtitle", track_index):
                continue
            items_in_track = timeline.GetItemListInTrack("subtitle", track_index) or []
        except Exception as e:
            print(f"[load] track {track_index} error: {e}")
            continue

        for it in items_in_track:
            try:
                s_f = int(it.GetStart())  # 帧
                e_f = int(it.GetEnd())    # 帧
                name = it.GetName() or ""

                # —— 关键：换算成【相对时间线起点】的秒 —— #
                s_rel_sec = _frames_to_seconds(max(0, s_f - start_frame_base), fps)
                e_rel_sec = _frames_to_seconds(max(0, e_f - start_frame_base), fps)

                # 最小时长兜底：至少 1 帧
                if e_rel_sec <= s_rel_sec:
                    e_rel_sec = s_rel_sec + (1.0 / float(_fps_to_fraction(fps)))

                blocks.append({"start": s_rel_sec, "end": e_rel_sec, "text": name})
            except Exception as e:
                print(f"[load] item error: {e}")

    # 统一排序，避免乱序
    blocks.sort(key=lambda b: (b.get("start", 0.0), b.get("end", 0.0)))
    return blocks

def load_existing_subtitles_into_tree_once():
    """
    插件启动时调用：如果当前时间线存在字幕，则刷新到右侧 Tree；
    若没有或读取失败，则静默跳过，不打断用户流程。
    """
    try:
        resolve, project, _, _, timeline, _ = connect_resolve()
        if not (project and timeline):
            print("[load] no active project/timeline, skip")
            return
        blocks = _collect_subtitles_from_timeline(timeline)
        if blocks:
            _refresh_subtitle_tree(blocks)
            print(f"[load] loaded {len(blocks)} subtitle blocks from timeline")
        else:
            print("[load] no subtitle items found on enabled subtitle tracks")
    except Exception as e:
        # 静默失败：不弹框，不干扰 UI
        print(f"[load] failed: {e}")
_loading_timer_stop = True
loading_win.Hide() 
whisper_win.Show()
load_existing_subtitles_into_tree_once()
dispatcher.RunLoop()
whisper_win.Hide()
