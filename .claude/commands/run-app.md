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

## macOS Tools

### Screenshots

```bash
# Full screen
screencapture -x /tmp/screenshot.png

# Specific window (by window ID)
screencapture -x -l$(osascript -e 'tell app "SugoiTV" to id of window 1') /tmp/screenshot.png
```

Then read `/tmp/screenshot.png` to visually verify.

### Interaction with cliclick

[cliclick](https://github.com/BlueM/cliclick) automates mouse/keyboard on
macOS. Install: `brew install cliclick`

```bash
# Click at coordinates
cliclick c:400,300

# Double-click
cliclick dc:400,300

# Type text
cliclick t:"hello"

# Press a key (return, escape, arrow-left, arrow-right, arrow-up, arrow-down, tab, space, delete)
cliclick kp:return
cliclick kp:escape

# Move mouse
cliclick m:400,300

# Print current cursor position
cliclick p
```

## Simulator Tools (axe)

[axe](https://github.com/nicklama/axe) automates simulators via
CoreSimulator. Works with the UDID printed by `build_and_run`.

### Screenshots

```bash
axe screenshot --udid <UDID> --output /tmp/screenshot.png
```

Then read `/tmp/screenshot.png` to visually verify.

### UI Exploration

```bash
# Dump the full accessibility tree
axe describe-ui --udid <UDID>

# Describe a specific element
axe describe-ui --udid <UDID> --label "Channel List"
```

### Interaction

```bash
# Tap by coordinates
axe tap --udid <UDID> --point 200,400

# Tap by accessibility label
axe tap --udid <UDID> --label "Settings"

# Type text into the focused field
axe type --udid <UDID> --text "hello"

# Press hardware buttons
axe button --udid <UDID> --name home
```

## Workflow Example

A typical visual verification flow:

1. **Build and launch**
   ```bash
   UDID=$(script/build_and_run --platform iphone | tail -1)
   ```

2. **Wait for app to settle** (2-3 seconds)
   ```bash
   sleep 3
   ```

3. **Screenshot the initial state**
   ```bash
   axe screenshot --udid "$UDID" --output /tmp/screenshot.png
   ```

4. **Read the screenshot** to verify the UI

5. **Interact** (e.g., tap a channel)
   ```bash
   axe tap --udid "$UDID" --label "NHK"
   sleep 2
   axe screenshot --udid "$UDID" --output /tmp/after-tap.png
   ```

6. **Read the after screenshot** to verify the result

## Limitations

- **axe only works with simulators**, not macOS apps. For macOS interaction,
  use `cliclick` and `screencapture`
- **Simulator boot time**: first launch after boot takes 10-30 seconds. The
  script handles booting automatically
- **Credentials**: the app needs YOITV_USER/YOITV_PASS to get past the login
  screen. These must be set in the Xcode scheme environment variables
