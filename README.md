# Translator

A native macOS app that runs Windows programs on your Mac.

Translator is a friendly front end for [Wine](https://www.winehq.org/), the open-source compatibility layer that CrossOver and Whisky are built on. Wine translates Windows system calls into macOS ones as the program runs, so there's no virtual machine and no Windows license needed.

## What it does

- **Bottles**: each bottle is an isolated Windows environment with its own `C:` drive, registry and settings. Keep games, office apps and old software apart so they can't break each other.
- **Run or install anything**: pick an `.exe`, `.msi`, `.bat` or `.lnk`, drag it onto the window, or double-click it in Finder (choose *Open With → Translator*).
- **Finds installed programs** in each bottle's `Program Files` and lets you pin favourites as a launcher grid.
- **Per-bottle settings**: Windows version (XP → 11), MSync for faster multithreading, Retina mode, detailed logging.
- **Built-in Windows tools**: Wine configuration, Control Panel, uninstaller, Registry Editor, Task Manager, Command Prompt, File Explorer.
- **Stop All** kills every Windows process in a bottle when something hangs.
- **Live log** of Wine's output for troubleshooting (⇧⌘L).
- **Guided setup** that detects Wine automatically and walks you through installing it.

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- Wine for macOS. The app's welcome screen walks you through it; in short:

  ```bash
  softwareupdate --install-rosetta --agree-to-license   # Apple Silicon only
  ```

  ```bash
  brew install --cask wine-stable
  ```

  ```bash
  xattr -drs com.apple.quarantine "/Applications/Wine Stable.app"
  ```

  If the Homebrew cask isn't available, download `wine-stable` from [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds/releases), drag *Wine Stable.app* into Applications, and run the `xattr` command above. Translator also works with any other `wine`/`wine64` binary you point it to (Settings → Choose…).

## Build and run

You need Xcode or the Command Line Tools (`xcode-select --install`).

Quick run during development:

```bash
swift run
```

Build a proper double-clickable app in `dist/Translator.app`:

```bash
./scripts/build-app.sh
```

```bash
cp -R dist/Translator.app /Applications/
```

You can also open `Package.swift` in Xcode and press ⌘R.

Because the app is ad-hoc signed, the first launch may need right-click → **Open**.

## Where things live

- Bottles: `~/Library/Application Support/Translator/Bottles/<name>/`
  - `drive_c/` is the bottle's `C:` drive
  - `bottle.json` holds Translator's settings for the bottle

## Limitations

Wine runs a large share of Windows software, though not all of it:

- Games with kernel-level anti-cheat (Valorant, Fortnite, many online shooters) won't run.
- DirectX 12 games need Apple's Game Porting Toolkit or CrossOver's D3DMetal; point Translator at a GPTK/CrossOver `wine` binary to use them.
- Programs that install drivers (VPNs, hardware utilities) won't work.
- Check [WineHQ's AppDB](https://appdb.winehq.org/) to see how well a specific program runs.

## Project layout

```
Sources/Translator/
  TranslatorApp.swift       App entry, menus, Finder "Open With" handling
  Model/AppModel.swift      Bottles, process launching, logging
  Model/Bottle.swift        Bottle / settings types
  Wine/WineRuntime.swift    Finds Wine and builds the environment for it
  Wine/WineSupport.swift    Built-in tools, file types, program scanner
  Views/                    SwiftUI interface
scripts/build-app.sh        Packages a signed .app bundle
```
