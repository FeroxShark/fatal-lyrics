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
from . import art, audio, config, daemon, ipc, lyrics, offsets, setup, system, tray, util

from .util import (
    DAEMON_PID_PATH, FIELD_SEP, LOG_MAX, LOG_PATH, QS_LOG_PATH, QS_PID_PATH,
    RUN_DIR, UA, log, rotate_log, run_dir,
)

from .config import (
    CFG, CONFIG_DIR, CONFIG_PATH, CRT_PATH, DEFAULT_CONFIG, DEFAULTS,
    SING_PATH, TUNE_PATH, apply_config, crt_on, load_config, parse_sing,
    parse_tune, read_config,
    reload_config, set_crt, set_option, watch_config, watch_sing, watch_tune,
    _save_config, _toml_val,
)

from .lyrics import (
    CACHE_DIR, MAX_INFLIGHT, NETEASE_CREDIT_RE, NETEASE_HEADERS, NETEASE_LIMIT,
    NETEASE_SLACK, NETEASE_TIMEOUT, NONE_TTL, OK_TTL, PROVIDERS, RETRIES,
    RETRY_DELAY, RETRY_JITTER, SEG_MAX, SEG_MAX_SHORT, SEG_PUNCT, SEG_SPLIT,
    SPELL_SEP, STATE_PATH, TS_RE, WORD_TS_RE,
    cache_get, cache_put, clean_title, current_line_index, expand_repeats,
    expand_spelled, fetch_lyrics, fetch_lyrics_async, http_json, lrclib_get,
    lrclib_search, netease, netease_pick, parse_lrc,
    purge_cache, seg_key, spelled_run, split_repeats, state_line, write_state,
    _cache_path, _fetch, _fetch_lock, _retry_delay,
)

from .art import album_colors, parse_histogram, send_album_colors

from .system import (
    OPTIONAL_TOOLS, gaming, health_lines, is_game_window,
    missing_tools, playerctl_state,
    _daemon_pid, _monitors, _monitors_lr, _players, _terminal, _tray_available,
)

from .ipc import (
    DEMO_LINES, HANG_TEXT, HANG_TITLE, SOCK_PATH, SYNC_PATH, clear, demo, hang,
    lyrics_list, lyrics_plain, next_line, parse_sync, send, send_soft, show,
    _config_event, _demo_burst, _send_lock, _song_pos, _song_where,
)

from .audio import (
    AUDIO_BANDS, AUDIO_HOP, AUDIO_MIN_SEND, AUDIO_RATE, AudioAnalyzer,
    BPM_HISTORY, BPM_MAX_GAP, BPM_MAX_MS, BPM_MIN_INTERVALS, BPM_MIN_MS,
    BPM_SEND_DELTA, BPM_SEND_EVERY, BPM_TOL, BpmTracker,
    PEAK_GAP, PEAK_HARD, PEAK_MAX, PEAK_PCT, PROFILE_DIR, PROFILE_STEP,
    PeakGate, SECTIONS, SECTION_HOLD, SECTION_SMOOTH, SINK_CHECK_EVERY,
    TrackProfile, VOICE_HOP, audio_loop, band_energy, classify_level,
    profile_for, set_profile, set_voice_sink, sink_changed, sink_node_id,
    voice_loop, voice_rms, _audio_command, _band_table,
    _default_sink, _default_source, _fold_interval, _profile_lock,
    _sink_node_id, _source_node_id, _voice_capture, _voice_command,
)

from .offsets import OFFSETS_DIR, OFFSETS_PATH, get as offset_get, record as offset_record

from .tray import SCALE_STEP, TRAY_CHOICES, TRAY_TOGGLES, start_tray

from .setup import (
    BOLD, DIM, OFF, SETTINGS, YEL, YESNO, _ask_crt_order, _ask_int, _ask_num,
    _ask_player, _ask_screens, _ask_text, _demo, _fmt, _menu, _pick,
)
# el menú en sí es `cartelitos.setup.setup()`: acá `setup` es el módulo

from .daemon import HANG_AFTER, POLL, POLL_IDLE, main
