# AoE2 DE Grip Pan

Hold middle mouse and drag to pan the camera in **Age of Empires II: Definitive Edition**. The map stays under your cursor, like drag-scrolling in StarCraft II or AoE4.

This is an AutoHotkey script. Unlike earlier versions, it **finds the game's camera offsets itself after a patch**, so you don't need Cheat Engine or to wait for someone to post new numbers.

> Not affiliated with Microsoft, Xbox Game Studios or Forgotten Empires. Read [Is this safe?](#is-this-safe) before using it online.

---

## Requirements

- Windows, AoE2 DE (tested on the Steam version)
- [AutoHotkey **v1.1**](https://www.autohotkey.com/download/), the **64-bit** build (v2 won't run this script)
- Run the script **as administrator**

## Quick start

1. Download or clone this repository. Keep `AoE2DE-Drag-Scroll-Auto.ahk` and `known-builds.ini` in the same folder.
2. Right-click `AoE2DE-Drag-Scroll-Auto.ahk` → **Run as administrator**.
3. Start a match, hold **middle mouse**, and drag.

If your game build is already listed in `known-builds.ini`, that's all. Otherwise you'll get a tooltip asking you to locate the offsets (next section).

## After a game update

1. Start a **single-player** match (skirmish vs AI is fine).
2. Move the camera somewhere mid-map, away from the edges, and put the cursor over the map. Don't start fully zoomed in.
3. Press **Ctrl+Alt+F** and don't touch anything until the tooltip says it's ready. The camera will nudge right and left, jump a few tiles and back, and zoom in and out. This usually takes a few seconds. After a big patch it can take a minute or two.

The result is saved per game build in `AoE2DE-Drag-Scroll.ini` next to the script, so you only do this once per patch.

## Hotkeys

| Key | What it does |
|---|---|
| Middle mouse (hold + drag) | Grip-pan the camera. A quick click without dragging still works as a normal middle-click |
| Ctrl+Alt+F | Locate offsets for the current game build |
| Ctrl+Alt+D | Diagnostics tooltip (build id, offsets, live camera X/Y, write test, last locate result) |
| Ctrl+Alt+R | Reload the script |

## Settings

Open the script in a text editor. The settings are near the top:

| Setting | Default | Notes |
|---|---|---|
| `PanKey` | `"MButton"` | e.g. `"RButton"`, `"XButton1"`, `"XButton2"` |
| `BasePanSpeed` | `0.0341` | Overall drag speed. Raise or lower it if the map doesn't stay under your cursor |
| `HorizontalMultiplier` / `VerticalMultiplier` | `0.42` / `0.86` | Fine-tune each axis |
| `InvertX` / `InvertY` | `1` | Set to `0` for "move the camera" instead of "drag the map" |
| `SmoothingSlow` | `0.5` | Lower = smoother but more lag |

Save, then press Ctrl+Alt+R.

## Troubleshooting

Press **Ctrl+Alt+D** in a match first. It shows most of what's needed to diagnose a problem.

- **Tooltip says there are no offsets for this build** → run Ctrl+Alt+F (see above).
- **"Camera not found"** → make sure you're in a match (not a menu or the scenario editor), the camera isn't against a map edge, and the arrow keys still scroll the camera (Ctrl+Alt+F uses them).
- **`NOT admin`** or **write test FAILED** → run the script as administrator.
- **Dragging moves the camera, but too fast or slow at some zoom levels** → re-run Ctrl+Alt+F without starting at max zoom-in, so it can find the zoom value.
- **Nothing happens on middle mouse** → check that the AutoHotkey tray icon is there, that you're on the 64-bit v1.1 build, and that your mouse software isn't remapping the middle button.

When reporting an issue, include a screenshot of the Ctrl+Alt+D tooltip.

## Contributing offsets for a new patch

After Ctrl+Alt+F works on a new build, copy that build's section from your `AoE2DE-Drag-Scroll.ini` (Base, Hop, XOff, Zoom) into `known-builds.ini` and open a pull request. Everyone else on that build then works without running Ctrl+Alt+F.

## Is this safe?

Read this before you use it online.

**What it does.** While you drag, the script writes the camera's X/Y position directly into the game's memory. It doesn't inject code, modify game files, or touch gameplay state. The camera is local to your PC (multiplayer only syncs commands), so it can't cause desyncs and shows nothing you couldn't reach by clicking the minimap. The script only holds access to the game while you're dragging, locating or running diagnostics.

**The risk.** Anti-cheat judges *how* a tool works, not why. Writing into another program's memory is the same mechanism map hacks and trainers use. AoE2 DE has client-side anti-tamper ("A running process may be interfering…") that has crashed the game when trainers are attached. Microsoft and Forgotten Empires have not said whether tools like this are allowed, and that could change with any patch.

**Recommendations.**
- Prefer single-player, custom lobby and unranked games.
- Run Ctrl+Alt+F in single-player, never in ranked.
- If losing your account would really hurt, don't use it in ranked.

You use this at your own risk.

If you want this in the game properly, add your voice to the official feature requests, e.g. [Modern camera drag as in AoM and AoE4](https://forums.ageofempires.com/t/modern-camera-drag-as-in-aom-and-aoe4-feature-request/282714).

## How it works

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Credits

- [asieradzk/AoE2Mouse_Camera_Drag](https://github.com/asieradzk/AoE2Mouse_Camera_Drag): original script and drag feel
- [Emerald3ME/AoE2DE-Drag-Scroll](https://github.com/Emerald3ME/AoE2DE-Drag-Scroll): maintained fork and the manual offset guide
- This version adds automatic offset finding, per-build caching and diagnostics

MIT licensed. See [LICENSE](LICENSE).
