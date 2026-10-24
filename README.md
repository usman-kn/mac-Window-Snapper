# Snapper

A tiny window-snapping app for macOS that lives in the menu bar. Snap windows with keyboard shortcuts, or drag them to a screen edge like on Windows.
It's one Swift file with no dependencies, no network access and no telemetry.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥ ← / → | Left / right half (press again to cycle through ½, ⅔ and ⅓) |
| ⌃⌥ ↑ / ↓ | Top / bottom half (also cycles) |
| ⌃⌥ U / I / J / K | Top-left / top-right / bottom-left / bottom-right quarter |
| ⌃⌥ D / F / G | First / center / last third |
| ⌃⌥ E / T | First / last two thirds |
| ⌃⌥ Return | Maximize |
| ⌃⌥ C | Center |
| ⌃⌥ ⌫ | Restore the window's size and position from before it was snapped |
| ⌃⌥⌘ ← / → | Move the window to the previous / next display |

## Drag to snap

Drag a window by its title bar to the screen's edge:

- **Left or right edge** snaps it to that half.
- **Top edge** maximizes it.
- **A corner** snaps it to that quarter.

A highlight shows where the window will land. You can turn this off from the menu bar icon.

## Permissions and privacy

Snapper needs **Accessibility** access (System Settings → Privacy & Security → Accessibility). That's the only way a Mac app can move other apps' windows.

- **Keyboard:** it registers only the shortcuts above and never sees anything else you type.
- **Mouse:** it watches left-clicks and drags only, to spot a window being dragged to an edge.
- **Nothing saved or sent:** it makes no network connections and doesn't store or send anything. The only setting it saves is whether drag-to-snap is on.

## Install

Requires macOS 13 or later and Apple's command line tools (`xcode-select --install`).

```bash
git clone https://github.com/usman-kn/snapper.git
cd snapper
./build.sh
open ~/Applications/Snapper.app
```

`build.sh` compiles `main.swift`, ad-hoc signs the app and copies it to `~/Applications`. If an older Snapper is running there, the script quits it and replaces it.

Because the build is ad-hoc signed, macOS treats each rebuild as a new app. After rebuilding, remove Snapper from the Accessibility list and add it again.

You can turn on **Launch at Login** from the menu bar icon.

## License

MIT. See [LICENSE](LICENSE).
