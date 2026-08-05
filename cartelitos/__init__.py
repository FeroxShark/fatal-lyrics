"""cartelitos / fatal-lyrics — synced Spotify lyrics as Windows error dialogs.

Follows playback via MPRIS (playerctl), fetches synced lyrics from
lrclib.net, and sends each line to the Quickshell overlay over a Unix
socket. Config at ~/.config/cartelitos/config.toml (auto-created with
defaults).

El código vive en los submódulos; acá se reexporta todo con el nombre de
siempre para que `import cartelitos` siga viéndose igual que cuando esto era
un archivo solo.

OJO al parchear: reasignar `cartelitos.CFG` (o cualquier otro global mutable
de acá) NO cambia lo que lee el resto — estos nombres son una copia de la
referencia. Para pisar un global hay que hacerlo en su módulo:
`cartelitos.config.CFG`, `cartelitos.lyrics.CACHE_DIR`, etc.
"""
from . import art, audio, config, daemon, ipc, lyrics, setup, system, tray, util

from .util import FIELD_SEP, UA, log

from .config import (
    CFG, CONFIG_DIR, CONFIG_PATH, CRT_PATH, DEFAULT_CONFIG, DEFAULTS,
    TUNE_PATH, apply_config, crt_on, load_config, parse_tune, read_config,
    reload_config, set_crt, set_option, watch_config, watch_tune,
    _save_config, _toml_val,
)

from .lyrics import (
    CACHE_DIR, NONE_TTL, RETRIES, RETRY_DELAY, SEG_MAX, SEG_MAX_SHORT,
    SEG_PUNCT, SEG_SPLIT, SPELL_SEP, TS_RE, cache_get, cache_put,
    current_line_index, expand_repeats, expand_spelled, fetch_lyrics,
    fetch_lyrics_async, http_json, parse_lrc, seg_key, spelled_run,
    split_repeats, _cache_path, _fetch, _fetch_lock,
)

from .art import album_colors, parse_histogram, send_album_colors

from .system import (
    NOT_A_GAME, gaming, is_game_window, playerctl_state,
    _daemon_pid, _monitors, _monitors_lr, _players, _terminal,
)

from .ipc import (
    DEMO_LINES, SOCK_PATH, clear, demo, send, send_soft, show,
    _config_event, _demo_burst, _send_lock, _song_pos, _song_where,
)

from .audio import (
    AUDIO_BANDS, AUDIO_HOP, AUDIO_MIN_SEND, AUDIO_RATE, AudioAnalyzer,
    PEAK_GAP, PEAK_HARD, PEAK_MAX, PEAK_PCT, PROFILE_DIR, PROFILE_STEP,
    PeakGate, SECTIONS, SECTION_HOLD, SECTION_SMOOTH, TrackProfile,
    audio_loop, band_energy, classify_level, profile_for, set_profile,
    sink_node_id, _audio_command, _band_table, _default_sink, _profile_lock,
    _sink_node_id,
)

from .tray import SCALE_STEP, TRAY_CHOICES, TRAY_TOGGLES, start_tray

from .setup import (
    BOLD, DIM, OFF, SETTINGS, YEL, YESNO, _ask_crt_order, _ask_int, _ask_num,
    _ask_player, _ask_screens, _ask_text, _demo, _fmt, _menu, _pick,
)
# el menú en sí es `cartelitos.setup.setup()`: acá `setup` es el módulo

from .daemon import POLL, POLL_IDLE, main
