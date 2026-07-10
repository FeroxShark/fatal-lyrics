# fatal-lyrics

Synced Spotify lyrics shown as Windows 95 error dialogs popping up on your
desktop.

- Every lyric line appears as an error dialog at a random position.
- The dialog for the line playing **right now** is bigger and stays still.
- Older dialogs vibrate like holograms, glitch with broken-GPU artifacts
  (magenta/green/purple blocks), get a **split window** (real tearing), and
  die with a CRT-style collapse.
- On track change a **vinyl sleeve** pops up: a square card with the album
  art and a classic Windows border. It appears big in the center, then after
  a few seconds shrinks and docks into a corner (configurable, or always
  centered), with a **Win95 progress bar** that tracks the song. Draggable
  anywhere; a quick click hides it until the next track.
- A **spinning vinyl record** peeks out of the sleeve, labeled with the
  album art.
- On track change, old dialogs don't just vanish: they die **in a chain**,
  a domino of CRT collapses from oldest to newest.
- Optional **karaoke** mode: the current line paints word by word as it's
  sung (estimated timing — lrclib provides per-line timestamps).
- **Multi-monitor**: `screen = "all"` (or a list) shows dialogs across
  several screens at once, each with its own random positions.
- Dead dialogs leave a **burnt shadow** (CRT burn-in) that fades out over a
  couple seconds.
- Random Windows icons: error, warning, question, info.
- Dialogs can be **dragged** by their title bar.
- On the current dialog: `Yes` / `Cancel` / `✕` close it, `No` **duplicates**
  it (like 2000s malware popups). On old (broken) ones: click to close.
- Auto-pauses if it detects a running game; clears everything if music stays
  paused too long; every dialog has a max lifetime (nothing floats forever).

## Requirements

- Wayland with a wlroots-like compositor (tested on **Hyprland**)
- [Quickshell](https://quickshell.org/) (`qs`)
- `playerctl`
- `python3` ≥ 3.11 (stdlib only)
- Spotify (or any MPRIS player — configurable)

Lyrics come from [lrclib.net](https://lrclib.net) (free, no API key).

## Installation

### Arch Linux (AUR)

```bash
yay -S fatal-lyrics-git
```

### Manual

```bash
git clone https://github.com/FeroxShark/fatal-lyrics ~/fatal-lyrics
~/fatal-lyrics/install.sh
```

## Usage

```bash
fatal            # toggle on/off
fatal on|off     # explicit
fatal restart    # restart (applies config changes)
fatal status     # ON / OFF
fatal config     # interactive menu, every setting, no need to touch the TOML by hand
fatal setup      # same as `fatal config` (first-run alias)
fatal edit       # opens the raw config.toml in $EDITOR, for people who prefer that
```

## Configuration

On first run it creates `~/.config/cartelitos/config.toml` with defaults.
`fatal config` walks through every option as a numbered menu (enter = keep
the current value) — detects your monitors and MPRIS players, and offers to
restart for you at the end. Prefer a text editor? `fatal edit` opens the raw
TOML instead; apply changes with `fatal restart`.

| Section    | Option               | What it does                                                    | Default     |
|------------|----------------------|------------------------------------------------------------------|-------------|
| `display`  | `screen`             | `"auto"` (first), `"all"` (every monitor), a name (`"DP-1"`) or a list (`["DP-1", "DP-2"]`) | `"auto"`   |
| `display`  | `max_dialogs`        | Max live dialogs at once (`0` = unlimited)                      | `0`         |
| `display`  | `scale`              | Base size for all dialogs                                       | `1.0`       |
| `display`  | `current_scale`      | Extra size factor for the current-line dialog                   | `1.3`       |
| `display`  | `spawn_area`         | Spawn zone: `full`/`top`/`bottom`/`left`/`right`/`edges`         | `"full"`   |
| `display`  | `karaoke`            | Current line paints word by word                                 | `false`     |
| `effects`  | `glitch`             | Intensity: `off`/`soft`/`normal`/`aggressive`                    | `"normal"`  |
| `effects`  | `effects_on_current` | The current dialog also vibrates/glitches                        | `false`     |
| `effects`  | `tearing`            | Old dialogs get a split window                                   | `true`      |
| `effects`  | `death_age_min/max`  | A dialog dies between N and M dialogs later                      | `3` / `7`   |
| `effects`  | `max_lifetime`       | Max lifetime per dialog in seconds (`0` = unlimited)              | `60`        |
| `effects`  | `burn_in`            | Dead dialogs leave a fading burnt shadow                          | `true`      |
| `effects`  | `cascade`            | On track change, dialogs die in a chain (domino)                 | `true`      |
| `behavior` | `now_playing`        | Vinyl sleeve with album art on track change                       | `true`      |
| `behavior` | `np_corner`          | Where it docks: `top-left`/`top-right`/`bottom-left`/`bottom-right`/`center` | `"top-right"` |
| `behavior` | `np_margin`          | Free pixels against the edges (in case of a bar/panel)            | `14`        |
| `behavior` | `np_vinyl`           | Spinning vinyl record peeking out of the sleeve                   | `true`      |
| `behavior` | `troll_no`           | The `No` button duplicates the dialog                              | `true`      |
| `behavior` | `click_through`      | Dialogs don't capture the mouse                                    | `false`     |
| `behavior` | `pause_clear`        | Seconds paused before clearing everything (`0` = never)            | `15`        |
| `behavior` | `player`             | MPRIS player name (`playerctl -l`)                                 | `"spotify"` |
| `behavior` | `offset`             | Sync lead time in seconds                                          | `0.15`      |
| `behavior` | `game_pause`         | Auto-pause when a window goes fullscreen (any game, no process list needed) | `true`      |

## How it works

```
Spotify ──playerctl (MPRIS)──▶ cartelitos.py ──Unix socket──▶ Quickshell overlay
                                    │
                                    └──HTTP──▶ lrclib.net (synced LRC lyrics)
```

The daemon polls playback position, resolves which line applies, and sends
JSON events to the overlay over `$XDG_RUNTIME_DIR/cartelitos.sock`. Config is
sent over the same socket on connect.

## Uninstall

```bash
fatal off
# AUR: sudo pacman -R fatal-lyrics-git
# manual:
rm ~/.local/bin/fatal && rm -rf ~/fatal-lyrics
rm -rf ~/.config/cartelitos   # optional: delete config
```

## License

MIT
