# Paired Window Snap

Author: Pavel Potasuev · Questions and contact: https://potasuev.ru

Drag a window to the left or right edge, hold for 0.3 seconds, then release. The window you were previously working in fills the opposite half. Drag to the top edge to maximize only the dragged window. No keyboard shortcuts are installed.

This is a standalone Lua module extracted from Pavel's accepted Hammerspoon setup. It does not require the Window Switcher or any other utility from that setup. Hammerspoon provides the window and mouse APIs; those libraries are not bundled here.

## Install alongside an existing config

1. Back up your existing `~/.hammerspoon/init.lua` and any local modules before editing.
2. Install [Hammerspoon](https://www.hammerspoon.org/) if needed. This module targets the classic Hammerspoon **1.x Lua API**, not the experimental Hammerspoon 2 JavaScript API.
3. Copy `paired-window-snap.lua` into `~/.hammerspoon/`. **Do not replace your init.lua with this file.**
4. Grant Hammerspoon Accessibility access in System Settings → Privacy & Security → Accessibility. If macOS requests Input Monitoring for Hammerspoon, grant it there as well. No Screen Recording permission is needed by this module: it captures no previews.
5. Append this to your existing init.lua, keeping all other settings:

```lua
pairedWindowSnap = require("paired-window-snap")
pairedWindowSnap:configure({ dwell = 0.3 }) -- optional; see CONFIG in the module
local started, message = pairedWindowSnap:start()
if not started then hs.alert.show(message) end
```

6. Resolve conflicting edge snapping first (below), then reload your Hammerspoon config yourself. Requiring the module does not enable it until `start()` is called.

The global `pairedWindowSnap` in the example is an intentional handle for stopping or restarting the module. The module itself creates no globals, hotkeys, menus, network services, or periodic thumbnail timers.

## Settings

Find the `CONFIG` block in the Lua file. Every field includes comments explaining increases and decreases. Values are macOS coordinate points, not display pixels, except `dwell`, which is seconds.

| Setting | Default | Increase | Decrease |
|---|---:|---|---|
| `edge` | 32 | Wider side activation area | Pointer must be closer to the edge |
| `topEdge` | 3 | Easier top maximize | Pointer must reach nearer the very top |
| `dwell` | 0.3 | Longer hold; fewer accidental snaps | Faster activation; zero removes hold |
| `minDrag` | 20 | Longer mouse movement required | Shorter drags qualify |
| `minFrameChange` | 8 | Larger real window-frame change required | Smaller real changes qualify |

All values must be finite nonnegative numbers; `edge` must be positive and should be kept below half a display's width. Configuration changes require stopping before restarting:

```lua
pairedWindowSnap:stop()
pairedWindowSnap:configure({ edge = 24, dwell = 0.5 })
pairedWindowSnap:start()
```

`start()` is idempotent. `stop()` cancels this module's pending timers and its mouse observer, removes only its own focus subscription, and leaves other modules alone. A new gesture invalidates an old pending release.

## Native macOS tiling and other snappers

Running two tools on the same edge gesture can cause competing moves. On macOS versions that offer these settings, open System Settings → Desktop & Dock → Windows and turn off native side-edge tiling and drag-to-menu-bar fill while using this module. Disable Option-drag tiling too if you use Option while dragging. If top-edge Mission Control conflicts, disable that drag gesture in the Mission Control section. Other versions/languages may show different names.

Apple documents these controls in [Change window tiling settings](https://support.apple.com/en-sg/guide/mac-help/mchl118087b0/mac) and [Tile windows on Mac](https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac). Settings are changed by you; this module never changes macOS preferences.

Disable edge dragging in Rectangle, Magnet, another Hammerspoon snapper, or similar tools. Do not add this module on top of the original full-config mouseSnap feature without disabling that existing feature first. Do not blindly delete unrelated subscriptions or event taps.

## Disable or remove

For the current Hammerspoon session, call `pairedWindowSnap:stop()` in its console. For a permanent disable, remove or comment out the installation lines in init.lua and reload your config. Restore your previous native tiling preferences if desired. Your backup can restore your original config.

## Behavior and limits

- Only visible standard windows in the current Space are considered; fullscreen and hidden windows are skipped. Partner selection uses actual focus history, not application names or the second item in a window list. If no valid previous window exists, only the dragged window snaps.
- The destination uses the usable screen frame, respecting its menu bar/Dock reservation. A partner on another display in the current Space may be moved to the dragged window's destination display. Fullscreen/other-Space pairing is not promised.
- Side zones take precedence at top corners. Snapping happens after release, not as a drag preview. Leaving or changing the edge resets the hold.
- Minimum window size, app-specific window restrictions and accessibility support can prevent an exact half-screen fit. A nonstandard window or an unsupported custom app may not work.
- Frame movement is used to distinguish a window gesture from dragging text or page content. Moving or resizing a window near an edge can qualify; this is not a title-bar-only detector.
- Closed/invalid windows and unavailable frames are skipped. No polling watchdog is installed; if macOS disables the event tap, stop/start the module after checking permissions.

## Validation and status

Run `lua tests.lua` with a Lua 5.3/5.4 interpreter for the portable fake-window tests. This does not install or start Hammerspoon.

The accompanying [validation report](validation.json) distinguishes **isolated tests** from real desktop use. The extracted module was loaded and exercised with fake `hs` APIs in a Lua interpreter: geometry, prior-window choice, thresholds, invalid frames, permissions and lifecycle were checked. No real windows or taps were started for these tests. The previous full setup was accepted by Pavel; this exact standalone build has not been installed on another Mac or given a new live end-to-end acceptance. No live demo recording is included. The synthetic tests are not video proof.

API references: [window filter](https://www.hammerspoon.org/docs/hs.window.filter.html), [event tap](https://www.hammerspoon.org/docs/hs.eventtap.html). Documentation checked 8 October 2026.

## License

MIT for the Lua module in this package. Copyright © 2026 Pavel Potasuev. Hammerspoon's own code and license remain with its authors and are not redistributed by this package. No third-party Spoon is bundled. See `LICENSE`.
