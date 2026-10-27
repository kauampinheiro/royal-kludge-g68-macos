# RK G68 for macOS

**English** · [Português](README.pt-BR.md)

A configurator for the **Royal Kludge G68** keyboard on the Mac — the thing RK
only ships for Windows. Remaps keys, drives the RGB lighting and stores
profiles, all written into the keyboard's own firmware.

![Keys, Lighting and Profiles tabs with the keyboard drawn to scale](docs/app.png)

It comes in two shapes, over the same core:

- **RK G68.app** — a native SwiftUI app, with a menu bar icon.
- **rkg68** — a CLI, for scripting and for diagnostics.

## Status

| Feature | State |
|---|---|
| Key remapping | ✅ works |
| Media and brightness layer (⏯ 🔊 🔆) | ✅ via remap, with the codes macOS understands |
| Lighting: effect, brightness, speed, color, sleep | ✅ works |
| Per-key color (*Customize* mode) | ✅ works |
| Profiles on disk | ✅ works |
| White balance (per-channel gain, load- and position-aware) | ✅ works |
| Validated color palette (presets) | ✅ works — CLI only |
| Uniform solid color (`solid`) | ✅ works |
| RK's Gaming / Office key sets | ✅ works |
| Macros in firmware | ❌ RK's macro protocol has never been decoded — see *Limitations* |
| Software macros (on the Mac) | ✅ works — the app's Macros tab |

## Installation

Requires macOS 14+ and Apple's Command Line Tools (`xcode-select --install`).
The full Xcode is not needed.

```bash
./build-app.sh
cp -R "build/RK G68.app" /Applications/      # or ~/Applications

# optional, for the CLI — the binary plus RK's definition tree
sudo cp build/rkg68 /usr/local/bin/
sudo mkdir -p /usr/local/share/rkg68 && sudo cp -R build/rk /usr/local/share/rkg68/rk
```

> `rkg68` does not embed RK's files: it looks for the `rk/` tree next to the
> binary, in `<prefix>/share/rkg68/rk` and, last, inside an installed
> `RK G68.app`. If the app is already in `/Applications` or `~/Applications`,
> copying just the binary works too; with none of the three it fails with
> *"RK resource folder not found"*. `RKG68_RESOURCES=<path>/rk` forces which
> copy it uses.

> **Do not run the app from inside `~/Documents`, `~/Desktop` or `~/Downloads`.**
> macOS raises a folder-access prompt for those and the app sits waiting for an
> answer. Install it in `/Applications` or `~/Applications`.

### Input Monitoring

macOS only lets you open an HID collection on a device that declares itself a
keyboard — the configuration collection included — if you hold **Input
Monitoring**. The first time the app finds the keyboard it asks for the
authorization; just accept. Without it IOKit returns `kIOReturnNotPermitted`
and you get *"macOS denied access to the HID device"*.

If the error persists, it is because the answer is already recorded as a denial
and the system will not ask again:

```bash
tccutil reset ListenEvent com.kauampinheiro.rkg68   # then open the app again
```

Or tick the app by hand in System Settings › Privacy & Security › Input
Monitoring.

**The authorization does not survive a build with a code change.** Without a
developer identity the signature is ad-hoc, and macOS ties the permission to
its hash — which changes along with the code. The checkbox stays ticked in the
list and access is denied anyway. That is why `build-app.sh` resets the record
on every build: the app goes back to asking, instead of failing silently. A
signing identity of your own (even self-signed) fixes it for good — run
`./make-signing-identity.sh` once.

The CLI has no authorization of its own: it inherits the caller's, i.e. the
**Terminal's**. `rkg68 scan` shows where it stands.

## Usage

### The app

1. Connect the G68 **over the USB cable** — not the 2.4G dongle, not Bluetooth.
   Only the cable exposes the configuration channel; the dongle shows up on the
   Mac as `2.4G Wireless Receiver` (Compx `0x25A7`) and the app cannot see it.
2. Open the app: the header shows the detected model.
3. **Keys** — click a key on the drawing, pick the new function, done: it is
   already written to the keyboard.
4. **Lighting** — pick the effect; only the controls that effect accepts show
   up. In the *Customize* effect, click keys to paint them. *Customize*
   (mode 14) is not an effect: it displays the per-key color table stored in
   the keyboard. Enabling it without painting anything leaves the keyboard dark.
5. **Profiles** — save combinations and apply them later from the menu bar.

### The CLI

```bash
rkg68 scan                         # is the keyboard reachable?
rkg68 info                         # model, keys and available effects
rkg68 remap caps=esc               # Caps Lock becomes Esc
rkg68 remap lwin=lalt lalt=lwin    # swap ⌘ and ⌥ (Windows layout on the Mac)
rkg68 remap f5=volup f6=voldown    # F5/F6 become volume
rkg68 led 17 --color '#FF6600' --brightness 5
rkg68 led 14 && rkg68 perkey w=#FF0000 a=#FF0000 s=#FF0000 d=#FF0000
rkg68 reset-remap                  # back to the factory layout
rkg68 keys                         # list keys and their indices
rkg68 targets volume               # search assignable functions
rkg68 keyset jogo                  # light only Esc+WASD+arrows, dim the rest
rkg68 calibrate --preset --white   # set the white balance and light it to judge
rkg68 solid '#FFFFFF'              # uniform solid color, position-corrected
rkg68 palette test '#FF8000' '#FF9000' --rows   # candidates to judge by eye
rkg68 palette add orange '#FF9000' --lit 68     # register the approved color
rkg68 selftest                     # check the protocol, without touching the keyboard
rkg68 dump-buffers remap caps=esc  # show the bytes, send nothing
```

## Key sets (Gaming / Office)

RK's `KB.ini` declares two key sets and one color — `GaoshouKey1`,
`GaoshouKey2` and `clrGaoshou`. In the official software they are the **Gaming
mode** and **Office mode** buttons on the Advanced tab (*gaoshou*, 高手, is
Chinese for "master").

| Set | Keys |
|---|---|
| Gaming | Esc, W, A, S, D, ↑, ↓, ←, → |
| Office | F1–F3, 1–5, Tab, Q, W, E, R, A, S, D, G, Shift, B, Ctrl, Alt, Space, PrtSc, PgUp, PgDn, Home, End |

It is not a protocol command of its own: it is **filling in the per-key color
table**. It lights the set, dims the rest, and therefore comes along with
*Customize* mode. In the app they live under Lighting › Per-key color; from the
CLI, `rkg68 keyset jogo` or `rkg68 keyset escritorio`.

The lists come as Windows VKs and are the same for the whole family, so they
carry keys a 68-key layout does not have — those are ignored.

## White balance

The keyboard drives all three channels at the same PWM, but the LEDs do not
yield equally: on the G68 green is the weakest, so `#FFFFFF` comes out
**pinkish**. Brightness does not fix it — it moves all three together and keeps
the wrong ratio.

The adjustment is a per-channel gain, always ≤ 1: you can only *lower* the
strong channels until the weakest one catches up, never push past 255.
Calibrated white is a little dimmer than raw white; that is the price of white
that is actually white.

In the app it is under **Lighting › White balance**. From the CLI:

```bash
rkg68 calibrate --preset --white   # the gain measured on this G68, already lit
rkg68 calibrate --r 0.09 --white   # still pink? lower red further
rkg68 calibrate --reset            # back to sending raw color
```

It applies to the fixed color of effects and to per-key color. **Effects that
generate their own colors** (rainbow, waves, etc.) are computed inside the
firmware and do not go through the adjustment. Calibration belongs to the
physical unit, so it lives outside profiles, in
`~/Library/Application Support/RKG68Mac/calibration.json`.

### The gain is not a single number

Measured on this G68: the gain that makes white neutral **depends on how many
LEDs are lit**.

| LEDs lit | neutral red | red gain |
|---|---|---|
| 1 | 28 | 0.110 |
| 15 | ~46 | 0.180 |
| 68 | 64 | 0.251 |

The points fall on `gain = base × n^0.19`, which is how the calibration applies
it: `--load-r/-g/-b` store the exponent, `applyLighting` passes the whole
keyboard's load, and per-key color counts the painted keys. Without this,
calibrating with one key lit and applying with 68 turns white **cyan**.

And it depends on **position**: with the keyboard fully lit at calibrated
white, the arrow-key region pulls pink and matches the rest by taking red down
to `0.76×`.

```bash
rkg68 calibrate --keys 'up,down,left,right' --key-r 0.76
rkg68 calibrate --keys-reset       # drop the position corrections
```

The cause is the same on both axes: the red LED has a forward voltage around
2.0 V against roughly 3.0 V for green and blue. Where current runs short (many
LEDs lit) or voltage runs short (far from the injection point on the rail), red
is what is left with headroom.

**In single-color modes the position correction has nowhere to be applied** —
the firmware receives one color and repeats it on every LED. For uniform solid
color, use `solid`, which draws through Customize with the compensated table:

```bash
rkg68 solid '#FFFFFF'              # really solid white, key by key
```

## Validated color palette

Three gains and one exponent do not reproduce every hue. For what the model
cannot reach, the way out is to record the color **approved while looking at
the keyboard**:

```bash
rkg68 palette test '#FF8000' '#FF9000' '#FFA000' --rows   # judge the candidates
rkg68 palette add orange '#FF9000' --lit 68 --note 'actual orange'
rkg68 led 17 --color @orange                              # use the preset
rkg68 palette list
```

`palette test` lights several candidates at once — with `--rows`, one per
physical row with the keyboard fully lit; without it, one per key at sparse
load. Comparing side by side is more accurate than judging one at a time, and
the command already suggests the `palette add` with the right `--lit`.

Two rules in the preset format, both because of the measurements above:

- it stores the **raw byte**, not the requested color — recalibrating does not
  throw the validation away;
- it stores **how many LEDs were lit** when you judged it — the same triple
  changes color with the load, and `palette apply` warns when the applied load
  differs.

A preset goes to the keyboard **without passing through the calibration**: it
already *is* the validated result. It lives in
`~/Library/Application Support/RKG68Mac/palette.json`.

## Background and launch at login

From the menu bar icon, three options:

| Option | What it does |
|---|---|
| **Open at login** | Registers the app through `SMAppService`. macOS may ask for confirmation in System Settings › General › Login Items — the menu shows the button when that is the case. |
| **Start without a window** | Goes straight to the menu bar, no window in your face. |
| **Hide Dock icon** | The app lives in the menu bar only (`.accessory`). Takes effect immediately, no restart. |

Closing the window **does not quit the app** — it stays in the menu bar. That
stopped being a convenience and became a requirement when macros arrived:
software macros only work with the process alive. To really quit, use *Quit* in
the menu bar.

Clicking the Dock icon with the window closed brings it back. In `.accessory`
mode there is no Dock icon, so the way in is *Open window…* from the menu bar.

## Macros

RK's macro protocol has never been reproduced by anyone — it lives in another
command family (`CDev3632::SetMacro`, with CRC and acknowledged packets), and
decoding it means capturing the official software running on Windows. So
**macros cannot be written to the keyboard**.

What the app does is intercept on macOS: the **Macros** tab listens for the
trigger key and types the sequence. Two important differences from remapping:

- **It does not travel with the keyboard.** A remap lives in the firmware and
  holds on any computer; a macro only exists on this Mac, with the app running.
- **It requires Accessibility**, a different authorization from the Input
  Monitoring that HID access already uses. The app shows the state and has a
  button to request it.

The trigger is **recorded by pressing the key**, not picked from a list: RK's
layout speaks Windows VK and the event tap speaks macOS keycode, and keeping a
translation between the two tables would be a guaranteed source of errors with
dead keys, ABNT layouts and sided modifiers. By recording, what goes in is
exactly what the system sees.

A sequence accepts six kinds of step:

| Step | What it does |
|---|---|
| **Text** | Types. Goes as Unicode, so accents and emoji come out right regardless of layout. |
| **Keys** | One combination (⌘S, ⇥, F5) — what text cannot represent. |
| **URL** | Opens the address in the default browser. |
| **Application** | Launches an app; with a URL filled in, opens the address **in it**. That is how you open a page in Chrome instead of the default browser. |
| **Shell** | Runs a command in `/bin/sh`, invisibly. Does not wait for it, does not show output. |
| **Terminal** | Opens a Terminal window in a folder and runs the command there, session alive. |
| **Wait** | Pauses for milliseconds — some applications drop events right after a focus switch. |

Example: to open Gmail in Chrome with one key, the sequence is a single step —
**Application** with `Google Chrome` picked and `mail.google.com` as the URL.
To land in a project with Claude Code running, also one step — **Terminal**
with the folder `Desktop/my-project` and the command `claude`.

The **Terminal** step writes a `.command` script and opens it with Terminal,
rather than sending AppleScript. The usual route
(`osascript -e 'tell application "Terminal" to do script …'`) works, but
requires the **Automation** authorization — a third TCC prompt, on top of Input
Monitoring and Accessibility. The script runs with `zsh -l`: without a login
shell the user's `PATH` is not assembled and nothing installed by Homebrew is
found.

While a macro is enabled, the trigger key **stops working normally** — it is
swallowed before reaching the application.

## Protocol provenance

The commands were checked against two independent sources: Rangoli's code and
**USB captures of RK's official software**. The key map this project generates
is **byte-for-byte identical** to what the vendor's software sends (9/9
buffers, verified on the F68).

From the official installer (`innoextract` plus strings from the binary) came
two things no open source project has:

- **Factory restore**: it is the lighting buffer with `[6] = 0x01`. That byte is
  documented by the community as "reserved, always zero" — which is why nobody
  had the command. Confirmed in captures from two models.
- **Reads**: the official software calls `HidD_GetFeature`, contrary to what
  the projects assume ("write-only"). The keyboard answers report `0x0a`; on
  the G68 it returns a constant status, but the path exists.

The binary also reveals three protocol families living side by side
(`CDevRKKB`, `CDevG5KB`, `CDev3632`) — the newer models use CRC and paging,
which explains why no community project supports them.

## How it works

The keyboard publishes several HID *collections*. Configuration only travels
over the one at **usage page `0x01` / usage `0x80`** (System Control) — the
keyboard collection is reserved by the system. Everything is a **65-byte**
*feature report* with report ID `0x0A`:

| Command | Buffers | Header |
|---|---|---|
| Remap | 9 | `0a 09 <n>` (+ `01 f8` on the first) |
| Lighting | 1 | `0a 01 01 02 29` |
| Per-key color | 7 | `0a 07 <n>` (+ `03 7e 01` on the first) |

In a remap, each key takes 4 bytes at `index × 4` of a contiguous 585-byte
space; in per-key color, 3 bytes at `index × 3`. The codes are **not plain
HID**: RK packs the usage into the high byte (`hid << 8`), uses its own
bitflags for modifiers (`0x020000` = left Shift) and prefixes `0x01000000` on
media keys.

The layout, the available effects and each model's artwork come from RK's own
software files (`Cfg.ini`, `Dev/<PID>/KB.ini`, `led.xml`), embedded in
`Sources/RKCore/Resources/rk/`. That is why the drawn keyboard matches the
physical one, irregularly sized keys included.

Recognized G68 PIDs: `0049`, `0052`, `005C`, `0075`, `00E7`, `013A`
(vendor `0x258A`, SinoWealth).

## Limitations

- **Writing needs the USB cable.** Over 2.4G and Bluetooth the configuration
  channel does not appear. Once written, it holds in any mode and on any
  computer — it is in the firmware, not in the app.
- **The keyboard does not give back what is stored in it.** No project has
  found a read command. That is why the profiles on disk are the only memory of
  what was sent; if you write with the official app on Windows, the profiles
  here do not follow.
- **Macros are not stored in the keyboard.** The protocol has never been
  reproduced. But the official binary shows where it lives: the `CDev3632`
  family (`CDev3632::SetMacro`, `Macro_Buffer_ID`, `MacroBufferNum`,
  `MacroHasMsKey=0x07`), with a transport of its own — `SendCMD_3632`, with CRC
  and acknowledged packets, different from the plain 65-byte command. Closing
  that means capturing the official software's traffic on Windows. The
  Windows-free alternative is a software macro on macOS (an *event tap* that
  expands the shortcut), which works but is not stored in the keyboard.
- **Writing to firmware carries real risk.** Use `dump-buffers` to see the
  bytes before sending, and change one parameter at a time.

> **A note on four LEDs that do not light.** On one G68 under test, Backspace,
> `\`, Enter and `←` (indices 79, 80, 81 and 83 — a whole column of the matrix)
> do not light reliably. **This is a physical board defect, not this
> software**: the phenomenon happens with the keyboard on 2.4G, a mode where
> the configuration channel does not even exist, and pressing the case at that
> corner makes the group light up and go out. The keys type normally — only the
> LED matrix fails. Full diagnosis in `docs/HANDOFF.md` §2 (in Portuguese).

- Profiles live in `~/Library/Application Support/RKG68Mac/profiles`.

## Layout

```
Sources/
  RKCore/           shared core — no UI
    HIDTransport    discovery and writing over IOKit
    Codecs          buffer assembly (remap, lighting, per-key color)
    Keycode         Windows VK → RK firmware code
    KeyboardConfig  reading Cfg.ini / KB.ini / led.xml
    Profile         profiles in JSON
    Resources/rk/   files from the official software (G68 models only)
  rkg68/            CLI + protocol self-test
  RKG68App/         SwiftUI app
build-app.sh        builds, runs the self-test and assembles the .app
```

Without Xcode installed there is no `XCTest` and no `swift-testing`, so the
protocol vectors became `rkg68 selftest`, which `build-app.sh` runs on every
build.

## License

GPL-3.0 — the protocol derives from
[Rangoli](https://github.com/rnayabed/rangoli). See `NOTICE.md` for the full
credits.
