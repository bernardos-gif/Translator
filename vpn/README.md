# VPN

A personal VPN you host yourself, built on [WireGuard](https://www.wireguard.com/). A Mac app sets up your server and manages your devices; the same server tool also works on its own from the command line.

Everything you do online goes through an encrypted tunnel to your own server, so the Wi-Fi you're on (café, hotel, airport) only sees encrypted traffic, and websites see your server's IP address instead of yours.

## What you need

- A Linux server with a public IP. Any small cloud VPS works (1 CPU, 512 MB RAM is plenty). Supported: Ubuntu, Debian, Fedora, RHEL/Rocky/Alma, Arch, Alpine.
- The [WireGuard app](https://www.wireguard.com/install/) on each device: iPhone, Android, Mac, Windows or Linux.

## The Mac app

1. Download the latest **`VPN-x.y.z.dmg`** from the [Releases page](https://github.com/bernardos-gif/Translator/releases) (the release named *VPN*).
2. Open it and drag **VPN** into **Applications**. The first time, macOS blocks it because it isn't notarized yet: go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Enter your server's address and its root password (or an SSH key) and click **Connect**.
4. Click **Install VPN**.
5. **Add Device** shows a QR code to scan with the WireGuard app on a phone, plus copy and save for computers. **Connect This Mac** hands this Mac's config to the WireGuard app.

The app shows each device's status and traffic, and removes devices with one click. It talks to the server over SSH and runs `vpn.sh` there; the password stays in your Keychain.

Requires macOS 13 or later, Apple Silicon or Intel.

### Building the app from source

```bash
cd vpn && ./scripts/build-app.sh --dmg
```

This produces `dist/VPN.app` and `dist/VPN-<version>.dmg`. Every push that changes `vpn/` builds it on GitHub Actions and publishes the release `vpn-v<VERSION>`.

## Command line: set up the server

Copy `vpn.sh` to the server, then:

```bash
chmod +x vpn.sh
```

```bash
sudo ./vpn.sh install
```

This installs WireGuard, generates keys, turns on routing and starts the VPN. It survives reboots.

If your provider has its own firewall panel (AWS security groups, DigitalOcean, Hetzner, Oracle Cloud...), allow inbound **UDP 51820** there.

Optional settings, given before `install`:

```bash
sudo VPN_PORT=443 VPN_DNS="9.9.9.9" VPN_ENDPOINT=vpn.example.com ./vpn.sh install
```

| Variable | Default | Meaning |
|---|---|---|
| `VPN_ENDPOINT` | auto-detected public IP | Address devices connect to. Use a hostname if your IP can change. |
| `VPN_PORT` | `51820` | UDP port. |
| `VPN_DNS` | `1.1.1.1, 1.0.0.1` | DNS servers devices use while connected. |

## Add your devices

```bash
sudo ./vpn.sh add phone
```

- **Phone:** in the WireGuard app tap **+ → Scan from QR code** and scan the code shown in the terminal.
- **Computer:** copy `/etc/wireguard/clients/<name>.conf` to it and import it in the WireGuard app (**Import tunnel(s) from file**).

Give each device its own name. A config can be connected from one device at a time.

## Everyday commands

| Command | What it does |
|---|---|
| `sudo ./vpn.sh add <name>` | Create a device and show its QR code |
| `sudo ./vpn.sh show <name>` | Show a device's config and QR code again |
| `sudo ./vpn.sh list` | List devices and when each last connected |
| `sudo ./vpn.sh remove <name>` | Revoke a device (lost phone, old laptop) |
| `sudo ./vpn.sh uninstall` | Remove the VPN and every config |

Adding and removing devices takes effect immediately, without disconnecting anyone else.

## How it works

- Devices get addresses in `10.66.66.0/24` and `fd42:42:42::/64`. The server is `.1`.
- All of a device's traffic, IPv4 and IPv6, goes through the tunnel, so nothing leaks around it.
- Each device has its own key pair plus a pre-shared key, so revoking one device never affects the others.
- The server translates tunnel traffic to its own public address (NAT). The rules are attached to the `wg0` interface and disappear when it stops.

Files on the server:

- `/etc/wireguard/wg0.conf`: server config and the list of devices
- `/etc/wireguard/clients/`: one config per device (contains private keys: keep it private)
- `/etc/wireguard/vpn-params`: settings chosen at install

## Troubleshooting

- **Connects but no internet:** check the provider's firewall allows UDP on your port, then run `sudo wg show` on the server. A device with a recent "latest handshake" is reaching the server.
- **Never connects:** make sure the `Endpoint` in the device's config is the server's current public IP or hostname.
- **Check the service:** `sudo systemctl status wg-quick@wg0`
