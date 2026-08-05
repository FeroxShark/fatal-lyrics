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
- A whole second mode: **CRT takeover** — every monitor becomes one giant
  dying cathode ray tube with the lyric inside it (see below).
- Auto-pauses for a fullscreen **game** — but not for a fullscreen browser or
  video player, which is exactly when you still want it; clears everything if music stays
  paused too long; every dialog has a max lifetime (nothing floats forever).

## CRT mode

A second, completely different mode: **every screen becomes one giant dying
cathode ray tube** and the lyric fills it. No dialogs, no desktop — the tube
takes the whole machine, on every monitor at once.

```bash
fatal crt on | off | toggle | status
```

What the tube does:

- **Real glass**: the picture is bent by barrel curvature, darkened towards
  the corners, and lit by a faint sheen off the top-left of the tube face.
- **The screen is lit, not black.** Like the tubes in the video: a burnt yellow
  screen with dark red letters, or a deep blue one with cyan letters, and the
  light bleeding around the glyphs. Two families that alternate across your
  monitors so the wall never looks uniform.
- **Phosphor**: the light bleeds around the glyphs (and *into* them on a lit
  screen, which is what thins the letters on a real tube), the raster is combed
  by scanlines that crawl, and an aperture-grille triad breaks every pixel into
  R/G/B — text never looks clean, exactly like a real tube.
- **Words arrive as they're sung**: each one lands with a kick of static and a
  flash of its own colour (the whole jolt — flash, colour ghosts and size kick —
  is `word_flash`; at `0` the word simply arrives, still, in its final colour),
  its colour channels split apart and snap back, and it settles into the
  phosphor in under a fifth of a second. No pre-printed line lighting up word by
  word — the tube tunes each word in as it's sung. Three entries take turns
  (a dry snap, a hard slam, a roll down into sync) so a long song never looks
  looped. Every entry is interpolated per frame, so it runs at whatever each
  monitor actually does (200, 144 or 60 Hz here).
- **Broken signal**: RGB channels drift apart (red left, blue right), the
  raster snakes, horizontal bands jump sideways, blocks of the image corrupt,
  static crawls, and a bright bar rolls slowly down the screen. **The flicker is
  on the peaks, not on the beat**: a beat is every kick drum that stands out —
  hundreds a song, and a tube that lifts on all of them lifts all the time. A
  peak is being at the top of *this* track (percentile against the whole song,
  at least 15 s from the last one, a handful per song), and that's the only
  thing that makes the picture beat — and, if you turn `flicker` up, drop out
  for a couple of frames like a set short of current. `flicker` sets how hard,
  never how often, and at `0` nothing at all moves with the volume: not the
  light, not the camera, not the animations on the other screens. A change of
  verse kicks the signal, and between verses it breaks by itself every so often
  — but only that: beats, single words and colour changes deliberately do *not*
  glitch, and everything that asks for one goes through a single gate that
  refuses anything too soon after the last. Five sources firing at once is what
  turns a tube into a screen that never stops vibrating. The kick of a new verse
  lands only on the screen the phrase arrives at, and the spontaneous breakdown
  is scheduled once for the whole wall — three screens each breaking "only every
  twenty seconds" still means something breaks every six.
- **Critical states**: a line can flip the whole tube to a red alarm wash that
  pulses, with `CRITICAL` on the readout instead of `REC` — but only a line that
  lands on a peak. Drawn by lot alone it came up every forty seconds or so, and
  a red that shows up for no reason is just another colour.
- **A phosphor per screen**: amber, cyan, green, violet or red — a different
  one on each monitor, rotating with every track (or pin one).
- **A director, not three clones**: one screen is in focus and the phrase
  *continues* on the next one — `I DON'T WANT YOU` on the middle screen, then
  `TO LEAVE` picks up on the one beside it, with the piece you already read
  still burning dim behind. Short phrases hop from screen to screen instead.
  The screens without lyric aren't dead: they run an animation (see below).
- **A layout per line**, picked from the line itself so every screen agrees
  without talking to each other: the phrase wrapped big, one word per line,
  typed out with a block cursor, tiled across the tube — or **cut in pieces
  across your monitors**, `TA` on one screen and `KE` on the next.
- **Your monitors in order**: the pieces follow your screens left to right.
  By default it reads the layout the compositor already knows; `fatal config`
  also lets you name the order yourself, for any number of screens.
- **It knows where it is inside the song.** Loud and quiet are measured against
  *that* track, not against a fixed number — the loudest moment of a lofi tune
  still counts as its drop, and an average bar of a metal song doesn't. The tube
  reads which part is playing (quiet / verse / build / drop) off a smoothed
  curve, so a section lasts a verse and not a bar, and everything follows:
  animations slow right down in the quiet parts and speed up into the chorus,
  the signal breaks more often when it's loud, and both the animation and the
  colour split across your screens change when the song changes part.
- **And it remembers the song.** The energy curve of each track is kept in
  `~/.cache/cartelitos/audio/`, so the second time you play it the tube already
  knows where the drops are and starts pushing a couple of seconds *before* they
  land, instead of reacting after the fact.
- **The colour travels with the lyric.** When the phrase is about to jump to the
  next monitor, that monitor takes the colour of the one handing it over — a
  third of a second *before* the words land, so the screen is already infected
  when they arrive. And it is a move, not a copy: the screen that let go takes
  the other colour, otherwise after three jumps the whole wall ends up the same
  shade and the two-tone look is gone.
- **Repeats get their own screen**: `take, take, take me to the beach` is not one
  phrase — it's three hits, and each lands on a different monitor. It catches
  every shape a lyric writes a repeat in: spaces, commas, **hyphens**
  (`Take-take-take-take-take me to the beach` is one word to anything that
  splits on spaces), repeated pairs (`take me, take me, take me`) and trios,
  slashes, any script. **Spelled-out words split per letter** — `T-A-K-E` is sung
  one letter at a time, so each letter takes a screen on its own and fills it —
  and so do stutters (`B-B-B-Baby`), while compound words and one-letter
  hyphenations (`people-pleasing`, `e-mail`, `T-shirt`, `K-pop`, `U-turn`) are
  left alone. The cutting is done in the daemon, where it is covered by tests,
  and travels to the overlay already cut.
- **It reacts to what's actually playing.** The daemon captures the sound
  card's own monitor (`pw-record`, or `parec` — whatever your PipeWire/Pulse
  setup already provides, no extra packages, no cava) and reads level, bass,
  treble, a pitch estimate and beats out of it in plain Python. It also keeps a
  map of each track (an energy curve, cached between plays), so "loud" means
  loud *for this song* and the peaks can be picked against the whole thing
  instead of against the last two seconds. The phosphor glow breathes with the
  level, the peaks kick the signal and flash the focused screen, the animations
  move with the spectrum, and the framing opens and closes. Capture only runs while the tube is up; without it everything falls
  back to the lyric clock and still works.
- **The colours come from the cover.** Each palette is *two* faces that go
  together — one lit screen (burnt background, dark letters) and one dark tube
  (deep background, glowing letters) — and your monitors alternate between them,
  so there are never three colours fighting each other. By default both come out
  of the album art of whatever is playing (needs ImageMagick), skipping any
  greys in it, because a grey has no hue of its own and picking one paints the
  wall a colour that belongs to nothing. No cover, no ImageMagick, or a black
  and white sleeve: it falls back to six presets, and with `palette = "auto"`
  the register of the song picks between them — on the peaks, not whenever the
  register moves. A voice climbs in every chorus, and repainting the whole wall
  each time it does is a carousel of colours, not a tube.
- **Two of water** — both made of loose points, both with every point its own
  particle: no mesh, no deformed sheet.
  - **The sea**: a field of points seen from just above the surface, running
    off into the distance. A long swell rides under the fine chop, the bass
    moves the rollers and the treble the ripple, and every beat drops a stone:
    a ring that crosses the water and lifts each dot as the front reaches
    *it*, then rings down.
  - **The pond**: the whole screen is water, seen from above, and it **shivers
    at the frequency of what is playing**. It is the physics-class demo — water
    on a speaker stops being flat and stands still in a pattern. The register of
    the song sets the pattern (higher voice, tighter rings and more lobes) and
    the rate of the shiver; the volume sets how violent it is; a beat drops a
    stone that ripples out and comes back off the edge.

  The delay is the whole point in both: a beat that lifts the entire surface at
  once is a screen flashing, not water. Crests catch the light and troughs fade
  out instead of being painted dark, so they work on a lit palette as well as on
  a dark tube. They take their turn like every other animation (`water = false`
  leaves them out) and `water_amp` says how much the water moves. Each is one
  shader (`shell/ocean.frag`, `shell/pond.frag`): a few hundred QML rectangles
  with per-frame bindings on a 200 Hz screen is hundreds of thousands of
  evaluations a second, and this costs about 1% of a core.
- **Animations where the lyric isn't** — six more, meant to look like
  something a machine of that era would put on a tube rather than a music
  visualiser bolted on top: a wireframe **eye** that opens and blinks with its
  iris breathing, a **scope** tracing a Lissajous figure that twists with the
  bass and treble, a **radar** sweep with echoes that light on the beat, a
  **rain** of characters, a **hyperspace** of streaks, and a **test card** with
  its hand going round. They change with the *part* of the song, not with every
  line — otherwise the side screens flick between drawings every two seconds and
  read as a nervous screensaver. Two screens never run the same one, the quiet
  parts pick the calm ones, and words like *eye*, *look*, *silence* (English or
  Spanish) pull the eye up on purpose, on **one** screen, not all of them.
- **Karaoke built in**: words light up as they're sung and stay dim before.
- **Console readouts**: REC dot, channel and phosphor, timecode, track, a
  block progress bar and framing brackets. Turn them off with `chrome = false`.
- **No signal**: with nothing playing the tube falls back to colour bars,
  heavy static and a blinking `NO SIGNAL`.

### Getting out

The tube takes the input too, so leaving it is one motion — `exit_on` picks
which:

- `"mouse"` (default): the **cursor is hidden** while the tube is up, and
  **moving the mouse** — or a click, or the wheel — puts the desktop back.
  Movement arms half a second after the tube appears and needs a few pixels of
  travel, so the click that opened it doesn't close it right away.
- `"keyboard"`: **any key** puts the desktop back, but the cursor stays
  visible and clicks fall through to whatever is underneath.

You can't have both: a layer surface that holds the keyboard stops receiving
the pointer (tested with exclusive *and* on-demand focus), so hiding the
cursor and catching bare keypresses are mutually exclusive. A line in tiny
letters on the tube says how to get out — it shows up for a few seconds when
the tube starts and then fades down to almost nothing.

Either way there are two exits that never depend on the overlay: a compositor
keybind, and the command itself.

```
bind = SUPER SHIFT, C, exec, fatal crt toggle   # Hyprland
```

It is **opt-in** and never turns itself on. The switch is a file in
`$XDG_RUNTIME_DIR`, not the socket, so `fatal crt off` puts the desktop back
even if the daemon is wedged or dead. It also switches itself off while a game
is fullscreen and comes back when you're out.

Everything else lives under `[crt]` in the config (screens, order, palette,
split mode, font, and the strength of curvature, scanlines, chroma, bloom,
noise, roll and vignette), all with live reload like the rest.

Want the old behaviour — the same line on every screen at once, no travelling
focus? `focus = "all"`.

It is not free: three full screens running a shader cost around a fifth of a
CPU core and a few points of GPU while the tube is up. Off, it costs nothing —
no capture, no textures, no timers. `quality` trades resolution for load, and
`focus`/`motifs`/`audio` each turn off a piece of the work.

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
fatal restart    # restart it
fatal status     # ON / OFF, plus anything optional that's missing and what it costs you
fatal config     # settings menu — every option on one screen, applies live
fatal setup      # same as `fatal config` (first-run alias)
fatal edit       # opens the raw config.toml in $EDITOR, for people who prefer that
fatal demo       # throws a few fake dialogs, to try settings without music
fatal crt on|off|toggle   # CRT mode: the tube takes over every screen
fatal tune       # sliders for the CRT settings you want to move while it plays
```

## Configuration

On first run it creates `~/.config/cartelitos/config.toml` with defaults.

**Nothing needs a restart.** Saving the config — from the menu or from your
own editor — is picked up within about a second and applied to the dialogs
already on screen. If the file has a typo, the running config is kept as is
and the error goes to `$XDG_RUNTIME_DIR/cartelitos/daemon.log`; nothing gets
reset. Logs (and the PID files next to them) live under
`$XDG_RUNTIME_DIR/cartelitos/`, and are rotated at 5 MB keeping one `.1` backup,
so a daemon that runs for weeks can't fill your tmpfs.

`fatal config` opens a menu with every setting and its current value on one
screen. Type a number to change that one thing, and you're back at the menu —
no walking through questions you don't care about. Changed rows are marked
and show what the value was when you opened it, `u` puts everything back, and
`d` throws a few fake dialogs so you can see your changes even with nothing
playing. It detects your monitors and MPRIS players on its own.

Prefer a text editor? `fatal edit` opens the raw TOML — same live apply.

And for the handful of CRT settings you only understand by moving them while the
music plays — how hard it beats, how restless the tube is, the glow, the
scanlines — `fatal tune` (or **Sliders…** in the tray) opens a small panel of
sliders. Each one writes straight into the config, so the tube follows along and
the value is still there next time.

### From the tray

While it's running there's a tray icon, and its menu carries the settings
you actually reach for mid-song: glitch level and spawn zone as submenus,
size as bigger/smaller/reset, and one-click toggles for karaoke, album art
and tearing — plus the demo dialogs and a way into the full menu. Each item
shows its current value in its own label, so you can see how things are set
without opening anything.

The tray needs `gtk3` and `libayatana-appindicator`. Without them the daemon
runs exactly the same, just without an icon.

## Lyrics

Synced lyrics come from [lrclib.net](https://lrclib.net). Results are cached
under `~/.cache/cartelitos/lyrics/`, keyed by artist, title, album and
duration — so replaying a song is instant and costs lrclib nothing, and songs
you've already heard still work with no connection.

"This track has no synced lyrics" is cached too, but only for a week: lrclib
gains lyrics over time. A failure to *reach* lrclib is never cached, and is
retried a couple of times instead — otherwise every song played during a
dropout would be remembered as having no lyrics.

## Development

```bash
python3 -m unittest discover -s tests
```

Covers the LRC parser, the config writer (it has to leave your comments and
alignment alone), live config reloading, the lyrics cache, and the race where
a slow lookup for a track you already skipped could overwrite the current
one. No dependencies beyond the standard library.

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
| `crt`      | `enabled`            | Start with the tube on (live switch: `fatal crt on/off`)           | `false`     |
| `crt`      | `screens`            | Screens the tube takes: `"all"`, a name, a list, or `"same"` as the dialogs | `"all"` |
| `crt`      | `order`              | Screens left to right (decides where each piece of a split line lands): `"auto"` or a list | `"auto"` |
| `crt`      | `exit_on`            | How you get out: `mouse` (cursor hidden, moving it returns) / `keyboard` (any key returns) | `"mouse"` |
| `crt`      | `director`           | The lyric travels across the screens instead of cloning        | `true`      |
| `crt`      | `focus`              | `roam` (one screen at a time) / `all` (every screen shows the whole line) | `"roam"` |
| `crt`      | `audio`              | React to what's playing (captures the sound card's monitor)     | `true`      |
| `crt`      | `color_from_pitch`   | Phosphor leans on the register of what's playing                | `true`      |
| `crt`      | `color_hold`         | Seconds a colour must stay before it may change                 | `10`        |
| `crt`      | `motifs`             | Animations on the screens without lyric                         | `true`      |
| `crt`      | `water`              | The two water animations (the sea, and the pond that shivers with the song) take their turn | `true` |
| `crt`      | `water_amp`          | How much the water moves (`0` = a flat field of points)         | `0.55`      |
| `crt`      | `camera`             | How much the framing moves (letterbox, zoom); `0` = still       | `1.0`       |
| `crt`      | `quality`            | Resolution the tube is drawn at before the CRT pass (`1.0` = native) | `1.0`   |
| `crt`      | `palette`            | Where the two colours come from: `album` (the cover) / `auto` (by register) / `dragons` / `ado` / `poison` / `bloodline` / `vapor` / `bone` | `"album"` |
| `crt`      | `split`              | Line across screens: `mixed` / `whole` / `fragment`                 | `"mixed"`   |
| `crt`      | `font`               | Font family for the lyric (`""` = system default)                   | `""`        |
| `crt`      | `chrome`             | Console readouts: REC, track, timecode, progress bar                | `true`      |
| `crt`      | `intensity`          | How often the signal breaks by itself (`0` = never)                 | `1.0`       |
| `crt`      | `curvature`          | Tube glass curvature (`0` = flat panel)                             | `1.0`       |
| `crt`      | `scanlines`          | Depth of the horizontal comb                                        | `0.75`      |
| `crt`      | `chroma`             | Steady RGB misalignment                                             | `1.0`       |
| `crt`      | `bloom`              | Phosphor glow around the letters                                    | `1.0`       |
| `crt`      | `noise`              | Static                                                              | `0.5`       |
| `crt`      | `roll`               | Brightness bar rolling down the tube                                | `1.0`       |
| `crt`      | `vignette`           | Darkening towards the corners                                       | `0.9`       |
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

`cartelitos.py` is only the launcher; the code lives in the `cartelitos/`
package:

| Module      | What's in it                                                        |
|-------------|---------------------------------------------------------------------|
| `util`      | `log()` + rotation, runtime paths (PID/log), `UA`, `FIELD_SEP`        |
| `config`    | defaults, TOML read/write, live reload, CRT switch, sliders watcher   |
| `lyrics`    | lrclib client, on-disk cache, line splitting into beats               |
| `art`       | album-cover colours (ImageMagick, optional)                           |
| `system`    | playerctl / hyprctl / terminal lookups, daemon PID, optional-tool check |
| `ipc`       | the Unix socket and every event sent to the overlay                   |
| `audio`     | capture, DSP (RMS/DFT/beats/peaks) and the per-track energy profile    |
| `tray`      | system-tray icon (GTK + AyatanaAppIndicator3, optional)               |
| `setup`     | the interactive `fatal config` menu                                   |
| `daemon`    | the main loop                                                         |

Mutable globals (`CFG`, `CACHE_DIR`, `CRT_PATH`, …) are re-exported from
`cartelitos/__init__.py` for convenience, but they must be **patched in their
own module** — rebinding `cartelitos.CFG` does not change what the rest of the
package reads.

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
