## VPN: your own private VPN, from your Mac

**Download `VPN-x.y.z.dmg` below**, open it, and drag VPN into Applications.

VPN turns a Linux server you rent into a private WireGuard VPN for all your devices. Your traffic goes through your own server, encrypted, so public Wi-Fi only sees scrambled data and websites see your server's address instead of yours.

### What you need
- A Linux server with a public IP: any small cloud server works (Ubuntu, Debian, Fedora, Rocky/Alma, Arch or Alpine). You need its address and a root password or SSH key.
- The free [WireGuard app](https://www.wireguard.com/install/) on each device that connects, including this Mac.

### First launch
VPN isn't notarized by Apple yet, so macOS blocks it the first time:
1. Open VPN from Applications. macOS says it can't verify the developer; click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to VPN.
3. Confirm with your password. You only do this once.

### Using it
1. Enter your server's address and password (or SSH key) and click **Connect**.
2. Click **Install VPN**. It sets up WireGuard on the server in a minute or two.
3. **Add Device** for each phone, tablet or computer, and scan the QR code with the WireGuard app.
4. **Connect This Mac** hands this Mac's config to the WireGuard app; switch it on there or from the menu bar.

Remove a device at any time and it can no longer connect.

### Prefer the command line?
`vpn.sh` (below) is the same server tool on its own. Run `sudo ./vpn.sh install` on the server, then `sudo ./vpn.sh add phone`.

### Requirements
macOS 13 Ventura or later, Apple Silicon or Intel.
