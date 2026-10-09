# Changelog

All notable changes to fatal-lyrics (cartelitos) are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/), grouped
by theme rather than by individual commit. This project doesn't cut versioned
releases (AUR tracks `-git`), so entries are dated instead of numbered.

## 2026-10-09 — Every option in the Settings window

- The Settings window now holds every option, in five tabs (Dialogs, Behavior,
  CRT, CRT scenes, CRT glass): the dialog lifetime, album sleeve, player, lead
  time, Hyprland keys, screens and CRT screen order, font and every CRT knob that
  used to be terminal-only. New row kinds: text fields, monitor pickers and an
  orderable screen list (with **Show numbers**). Also **Undo changes** and
  **Forget this artist** (sync).
- Removed the terminal menu (`cartelitos/setup.py`) and the window's "All
  options…" button that opened it in a terminal. `fatal config` and `fatal setup`
  now open the Settings window. Dropped `[system] terminals` (only used to pick
  that terminal).
- The app launcher entry gained a **Settings** action (`fatal ajustes`).

## 2026-10-09 — Settings window, short tray

- Added `fatal ajustes` (alias `fatal settings`): a Win95 property sheet
  (`shell/settings.qml`) with every everyday option grouped in three columns, a
  one-line hint per row, live apply and persistence. Its schema lives in
  `cartelitos/settings.py`; changes travel through `$XDG_RUNTIME_DIR/cartelitos-settings`
  and the daemon writes them to the TOML. Without the daemon it still saves.
- The tray menu went from ~23 rows to six: status, Settings…, CRT mode, Karaoke, Quit.
  Glitch, spawn zone, size, album art, tearing, palette, split, exit key, the CRT
  sliders and the sync nudge moved to the window.
- Removed `fatal tune` (`shell/tune.qml`): its sliders are the window's
  "CRT fine-tuning" group. `fatal tune` still opens the new window.

## 2026-09-28 — tanda 8: glass without moiré, new audio signals, fonts, splitflap fix

Five parallel slices closing out what Ferox reported after watching tanda 7 with real
music (2026-09-26). Full state of each in `docs/tanda8-estado/`.

- Fixed the tunnel/tube motif's visible seam (`shell/tunnel.frag`) and the CRT glass's
  moiré (star in the center, rings in each corner): both were period-2-pixel patterns
  in curved tube coordinates hitting Nyquist. Scanlines moved to static screen-space
  rows; every phosphor mask now blends by its actual on-screen frequency.
- Added `cut`/`cutf`/`hf` fields to the `aud` socket event (`cartelitos/audio.py`):
  sustained dry-cut detection with a one-frame "hit" on the return, and a treble
  spectral-flux channel independent of the bass, so the CRT can react to more than
  the beat.
- Replaced Press Start 2P (disliked, blocky) with four new OFL-licensed fonts (IBM
  Plex Mono, Space Mono, Chakra Petch, Syne Mono), pooled per entry family instead of
  a single shared font.
- Fixed the splitflap motif's "SIGUE:" row staying permanently empty for
  unsynced/plain lyrics and at track start, plus a sibling bug where the verse row
  stringified the whole lyric-line object instead of its `.text` (same bug still
  present, untouched, in `Swarm.qml`).
- Added visual reaction to the new audio signals (`shell/React.js` + `crt.frag`):
  tube dims on a dry cut and flashes back on the return, treble jitters row position
  and cools highlight color, and the dirt-noise grain now drifts instead of sitting
  static — each on its own axis so nothing doubles up as another per-screen
  animation. Nothing has been watched on-screen with real music yet.

## 2026-08 — package split, portability, config table-driven

The daemon moved from a single `cartelitos.py` script into a real package,
plus a pass on portability, threading safety, config maintainability and test
coverage.

### Package structure
- Split `cartelitos.py` into the `cartelitos/` package (`util`, `config`,
  `lyrics`, `art`, `system`, `ipc`, `audio`, `tray`, `setup`, `daemon`);
  `cartelitos.py` is now just the launcher. Mutable globals (`CFG`,
  `CACHE_DIR`, `CRT_PATH`, …) are re-exported from `cartelitos/__init__.py`
  but must be patched in their owning module.
- Added the Ocean and Pond water motifs (CRT quiet-screen animations) as part
  of the same refactor.

### Ops: paths, logs, health
- PIDs, logs and the health/status file moved out of `/tmp` and into
  `$XDG_RUNTIME_DIR/cartelitos/`, with log rotation at 5 MB (one `.1` backup)
  so a long-running daemon can't fill a tmpfs.

### Hyprland portability
- `system.py` now gates every Hyprland-specific call (`gaming()`/game-pause,
  `_monitors()`/monitor listing) behind a single `_hyprland()` check that
  looks at `HYPRLAND_INSTANCE_SIGNATURE`, `XDG_CURRENT_DESKTOP`, and the
  runtime-dir socket, plus `hyprctl` being on PATH. Off Hyprland these
  features degrade to a clean no-op (game-pause stays off, monitor list comes
  back empty) with a single warning instead of a swallowed
  `FileNotFoundError` per tick. A generic wlroots fallback (`wlr-randr` /
  `swaymsg`) is noted as a future TODO, not implemented.

### Lyrics fetch threading
- Capped the number of concurrent lyric-fetch threads and added jitter to the
  retry backoff, so a burst of track changes can't spawn an unbounded pile of
  requests against lrclib.
- Audio thread is now supervised so a narrow `except` inside it can't take
  the whole capture down silently; audio constants were named instead of
  left as magic numbers.

### Config: table-driven + new knobs
- Collapsed four hand-kept sources of config truth (defaults, the sample
  TOML text, the comments, the key order) down to `DEFAULTS` +
  `_CONFIG_COMMENTS` in `cartelitos/config.py`; the sample `config.toml` is
  now generated from those (`_render_default_config`) instead of hand-written
  and drifting.
- Round-trip tests added for the generated TOML; fixed the sample staying
  readable when a default is a long list (e.g. `[system]`).
- New configurable lists: `[system].not_a_game` (window classes that never
  count as "a game" for auto-pause — browsers, video/music players) and
  `[system].terminals` (terminal emulators to try, in order, when opening the
  full menu, after `$TERMINAL`). Previously hardcoded.
- New CRT knobs, both exposed in `fatal tune`: `infect_lead` (seconds of lead
  the colour takes on the next screen before the line arrives) and
  `alarm_threshold` (how rare the full-red "critical" screen is).

### Tests
- `daemon.py`'s main loop extracted into a testable `DaemonLoop` behind
  dependency injection.
- Added coverage for `tray.py`'s fallback when `gi`/AyatanaAppIndicator isn't
  available, and for the `fatal config` TUI's validation/retry paths under
  mocked input.
- Closed leaked/unclosed file handles across the test suite.
- Suite is now 270 tests (`python3 -m unittest discover -s tests`).

## Earlier history

### CRT mode (full-screen takeover)
Added the second display mode: every monitor becomes one cathode-ray tube
showing the current lyric, layered on top of (but separate from) the dialog
mode. Built up over several passes: barrel curvature/scanlines/chroma/bloom/
noise/vignette glass effects, a director that moves focus across screens
instead of cloning the line, per-line layout picks (wrapped, one-word,
typed-cursor, split-across-screens), audio-reactive behavior (level, bass,
treble, pitch, beat detection from a `pw-record`/`parec` capture, with a
cached per-track energy profile), album-art-driven two-tone palettes with
six built-in presets, colour-that-travels-with-the-lyric between screens,
critical/alarm red-wash states gated to song peaks, six idle-screen motifs
(eye, scope, radar, rain, hyperspace, test card), and the `word_flash` /
`flicker` knobs separating "how it lands" from "how hard it beats" per word
vs. per peak. `exit_on` (mouse vs. keyboard) added as the two mutually
exclusive ways out, since a layer surface can't hold both pointer and
keyboard at once.

### Dialog mode core
Initial release and early iterations: synced Spotify lyrics as Win95 error
dialogs, config system with live TOML reload, real tearing/glitch effects,
TTL and cascade-death behavior, multi-monitor support, the vinyl-sleeve
now-playing card with drag/dock/progress bar, system tray icon with live
settings, the interactive `fatal config` menu, and CLI/config text translated
to English. Also: generic fullscreen-based game detection (not a hardcoded
game list) and the lyrics cache with retry logic.
