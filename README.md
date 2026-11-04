# Translator

**Run Windows programs and games on your Mac.** No Windows license, no virtual machine, nothing to configure.

Translator is a native macOS app built on [Wine](https://www.winehq.org/), the open-source compatibility layer behind CrossOver and Whisky. Wine translates what a Windows program asks for into macOS calls as it runs.

## Install

1. Download the latest **`Translator-x.y.z.dmg`** from the [Releases page](https://github.com/bernardos-gif/Translator/releases).
2. Open it and drag **Translator** into **Applications**.
3. Open Translator. The first time, macOS blocks it because it isn't notarized yet: go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Click **Set Up Translator**. Everything else is automatic.

### What setup installs for you

| Step | What it is | Why |
|---|---|---|
| Rosetta 2 | Apple's Intel-code translator (Apple Silicon only) | Wine for macOS is Intel code |
| Wine Staging | The Windows compatibility engine, latest macOS build | Runs the programs; Staging carries extra compatibility patches |
| Wine Mono + Gecko | Open-source .NET and web engine | Programs built on .NET or showing web pages |
| winetricks + cabextract | Component installer (bundled in the app) | One-click Windows runtimes |
| DXVK + MoltenVK | DirectX 9/10/11 → Vulkan → Metal | Better game compatibility and speed |
| "My Windows" bottle | A ready Windows 10 environment | Somewhere to install programs |
| Essentials | Core fonts, Visual C++ 2015–2022, DirectX 9, shader compiler | The most common "missing DLL" errors, fixed up front |

Takes about 5–10 minutes and ~1.5 GB of disk space.

## Using it

- **Install a program**: download its Windows installer, then drop it on the window, click **Install or Run…**, or double-click it in Finder (*Open With → Translator*).
- **Library**: every installed program across all bottles, with its real icon. Click **Play**.
- **Bottles**: separate Windows environments. Presets:
  - **Apps**: Windows 10, fonts, Visual C++
  - **Games**: DXVK on, plus DirectX 9/10/11, XAudio and XInput
  - **Older Software**: Windows 7 and older Visual C++ runtimes
- **Components**: one-click install of 20+ runtimes: .NET Framework 4.8, .NET 6/8, Visual C++ 2005–2022, XNA, PhysX, DirectX libraries, CJK fonts, media codecs.
- **Per-bottle settings**: Windows version (XP → 11), DXVK, faster multithreading (MSync), Retina mode.
- **Tools**: Control Panel, Registry Editor, Task Manager, Command Prompt, File Explorer, uninstaller.
- **Desktop shortcuts** for any program, plus a live **log** (⇧⌘L) for troubleshooting.

### When a program doesn't work

1. Look at its error message and install the matching component (e.g. *"MSVCP140.dll missing"* → Visual C++ 2015–2022; *".NET Framework required"* → .NET 4.8).
2. For games, try toggling **DXVK** in the bottle's Settings.
3. For older programs, set the Windows version to 7 or XP.
4. Check [WineHQ's AppDB](https://appdb.winehq.org/) for program-specific tips.

### What can't run

- Games with kernel-level anti-cheat (Valorant, Fortnite, many online shooters).
- Drivers and system utilities (VPNs, antivirus, hardware tools).
- DirectX 12-only games need Apple's Game Porting Toolkit or CrossOver; point Translator at that Wine in **Settings → Advanced**.

## Building from source

Requires macOS 13+ with Xcode or the Command Line Tools.

```bash
./scripts/fetch-tools.sh
```

```bash
./scripts/build-app.sh --dmg
```

This produces `dist/Translator.app` and `dist/Translator-<version>.dmg`. For quick development runs use `swift run` (helpers then download during setup).

Every push to the default branch builds the app on GitHub Actions, test-runs Wine, and publishes the DMG to the release named after `VERSION`.

## Where things live

- `~/Library/Application Support/Translator/Runtime/`: Wine
- `~/Library/Application Support/Translator/Bottles/<name>/drive_c/`: each bottle's C: drive
- `~/Library/Application Support/Translator/Tools/`: helpers downloaded during setup

## Credits

Wine (LGPL) by the Wine project · macOS Wine builds by Gcenx · DXVK by Philip Rebohle (macOS port by Gcenx) · MoltenVK by the Khronos Group · winetricks · cabextract by Stuart Caie.
