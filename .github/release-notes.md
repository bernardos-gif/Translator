## Translator: run Windows programs on your Mac

**Download the `.dmg` below**, open it, and drag Translator into Applications.

### First launch
Translator isn't notarized by Apple yet, so macOS blocks it the first time:
1. Open Translator from Applications. macOS says it can't verify the developer; click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Translator.
3. Confirm with your password. You only do this once.

Then click **Set Up Translator**. It downloads and installs everything automatically (about 5–10 minutes, ~1.5 GB):
- Rosetta 2 (Apple Silicon Macs only; macOS asks for your password)
- Wine Staging, the Windows compatibility engine, with .NET (Wine Mono) and web (Wine Gecko) support
- DXVK, which translates DirectX 9/10/11 to Metal for games
- A ready-to-use Windows 10 environment with fonts, Visual C++ and DirectX components

### What's inside
- **Library** of every installed program with its real icon; click Play to launch
- **Bottles**: separate Windows environments, with presets for Apps, Games and Older Software
- **Components**: one-click install of 20+ Windows runtimes (.NET, Visual C++, DirectX, XNA, PhysX, fonts…)
- Double-click any `.exe` in Finder, or drag installers onto the window
- Desktop shortcuts, Windows tools (Control Panel, Registry, Task Manager…), and a live log

### Requirements
macOS 13 Ventura or later, Apple Silicon or Intel.
