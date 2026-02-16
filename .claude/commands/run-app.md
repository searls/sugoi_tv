# Run App — Build, Launch, Interact, Screenshot

Build and run the app, then interact with it and take screenshots for visual
verification.

## Quick Start

Build and launch:

```bash
# macOS (default)
script/build_and_run --platform mac

# Simulators
script/build_and_run --platform iphone
script/build_and_run --platform ipad
script/build_and_run --platform appletv
```

The script prints the **app path** (macOS) or **simulator UDID** (simulators)
on its last line of output. Capture this for use with the tools below.

---

## macOS App Interaction

### Screenshots (macOS)

Capture a specific app window (not the whole screen) using its Quartz window ID:

```bash
# Get the window ID for SugoiTV
WID=$(python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == 'SugoiTV':
        print(w['kCGWindowNumber']); break
")

# Capture just that window
screencapture -x -l "$WID" /tmp/screenshot.png
```

Then read `/tmp/screenshot.png` to visually verify.

> **Requires**: `pyobjc-framework-Quartz` (already installed).
> Window IDs change on every app launch — always re-query.

### Clicking and Typing (macOS) — cliclick

`cliclick` (`/opt/homebrew/bin/cliclick`) automates mouse and keyboard on
macOS. It operates on **screen coordinates**, not accessibility elements.

**Workflow: screenshot first, then identify coordinates, then click.**

```bash
# Click at absolute screen coordinates
cliclick c:400,300

# Double-click
cliclick dc:400,300

# Right-click
cliclick rc:400,300

# Type text into the focused field
cliclick t:"hello world"

# Press a named key
cliclick kp:return
cliclick kp:escape
cliclick kp:tab
cliclick kp:space
cliclick kp:delete
cliclick kp:arrow-up
cliclick kp:arrow-down
cliclick kp:arrow-left
cliclick kp:arrow-right

# Hold modifier + press key (e.g., Cmd+A to select all)
cliclick kd:cmd t:a ku:cmd

# Move mouse without clicking
cliclick m:400,300

# Print current cursor position
cliclick p

# Wait between actions (milliseconds)
cliclick c:400,300 w:500 c:400,400

# Drag from one point to another
cliclick dd:100,200 du:300,400

# Chain multiple actions
cliclick c:400,300 w:1000 t:"search term" kp:return
```

**Coordinate tips:**
- Use relative values with `+`/`-`: `cliclick c:+50,+0` (50px right of current)
- Use `.` for current position: `cliclick c:.` (click where cursor is)
- `-r` flag restores mouse position after: `cliclick -r c:400,300`
- `-m verbose` prints actions before executing: `cliclick -m verbose c:400,300`

### DO NOT use AppleScript for UI automation

AppleScript's `System Events` / `UI scripting` is unreliable and fragile.
**Never** write AppleScript to click buttons, navigate menus, or interact with
app UI. Use `cliclick` for macOS apps instead.

---

## Simulator Interaction — axe

`axe` (`/opt/homebrew/bin/axe`) automates iOS/iPadOS/tvOS simulators via
CoreSimulator. Every command requires `--udid <SIMULATOR_UDID>`.

Get the UDID from `build_and_run` output, or list booted simulators:
```bash
axe list-simulators
```

### Screenshots (Simulator)

```bash
axe screenshot --udid <UDID> --output /tmp/screenshot.png
```

Then read `/tmp/screenshot.png` to visually verify.

### UI Exploration — describe-ui

Dump the full accessibility tree to find element labels and identifiers:

```bash
axe describe-ui --udid <UDID>
```

**Use this before tapping** to discover what labels/identifiers are available.
Pipe through `head -100` or grep for specific text if output is large.

### Tapping

```bash
# Tap by accessibility label (PREFERRED — resilient to layout changes)
axe tap --label "Settings" --udid <UDID>

# Tap by accessibility identifier (if set in code via .accessibilityIdentifier)
axe tap --id "settings-button" --udid <UDID>

# Tap by coordinates (fallback — use describe-ui or screenshot to find coords)
axe tap -x 200 -y 400 --udid <UDID>

# Add delays before/after tap (seconds)
axe tap --label "Play" --pre-delay 1.0 --post-delay 0.5 --udid <UDID>
```

### Typing

```bash
# Type text (US keyboard characters only)
axe type "Hello World" --udid <UDID>

# Type from stdin (for special characters or long text)
echo "Hello World!" | axe type --stdin --udid <UDID>

# Type from file
axe type --file input.txt --udid <UDID>
```

### Swiping

```bash
# Swipe up (scroll down)
axe swipe --start-x 200 --start-y 500 --end-x 200 --end-y 200 --udid <UDID>

# Swipe with duration (slower = more like a drag)
axe swipe --start-x 200 --start-y 500 --end-x 200 --end-y 200 --duration 0.5 --udid <UDID>
```

### Hardware Buttons

```bash
# Available: home, lock, side-button, siri, apple-pay
axe button home --udid <UDID>

# Long-press (hold duration in seconds)
axe button lock --duration 2.0 --udid <UDID>
```

### Key Presses

```bash
# Press Enter (keycode 40)
axe key 40 --udid <UDID>

# Press Backspace (keycode 42)
axe key 42 --udid <UDID>

# Hold a key (seconds)
axe key 42 --duration 1.0 --udid <UDID>

# Common keycodes: 40=Return, 42=Backspace, 43=Tab, 44=Space
```

---

## Workflow Example

### Simulator (iPhone)

```bash
# 1. Build and launch
UDID=$(script/build_and_run --platform iphone | tail -1)

# 2. Wait for app to settle
sleep 3

# 3. Screenshot initial state
axe screenshot --udid "$UDID" --output /tmp/initial.png
# Read /tmp/initial.png to verify

# 4. Explore the UI tree
axe describe-ui --udid "$UDID" | head -50

# 5. Tap a specific element by label
axe tap --label "NHK" --udid "$UDID"
sleep 2

# 6. Screenshot after interaction
axe screenshot --udid "$UDID" --output /tmp/after-tap.png
# Read /tmp/after-tap.png to verify
```

### macOS

```bash
# 1. Build and launch
script/build_and_run --platform mac
sleep 3

# 2. Screenshot
WID=$(python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == 'SugoiTV':
        print(w['kCGWindowNumber']); break
")
screencapture -x -l "$WID" /tmp/screenshot.png
# Read /tmp/screenshot.png to verify

# 3. Click something (use screenshot to find coordinates)
cliclick c:400,300
sleep 1

# 4. Screenshot again
screencapture -x -l "$WID" /tmp/after-click.png
# Read /tmp/after-click.png to verify
```

## Limitations

- **axe only works with simulators**, not macOS apps. For macOS, use `cliclick`
  and `screencapture`
- **cliclick uses screen coordinates**, not accessibility elements. Always
  screenshot first to find the right coordinates
- **axe type** only supports US keyboard characters (A-Z, 0-9, common symbols).
  No international characters
- **Simulator boot time**: first launch after boot takes 10-30 seconds. The
  script handles booting automatically
- **Credentials**: the app needs YOITV_USER/YOITV_PASS to get past the login
  screen. These must be set in the Xcode scheme environment variables
