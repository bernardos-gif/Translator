#!/usr/bin/env bash
#
# vpn.sh: a personal WireGuard VPN server in one script.
#
#   sudo ./vpn.sh install            set up the server (run once)
#   sudo ./vpn.sh add <name>         create a device config and show its QR code
#   sudo ./vpn.sh show <name>        show a device's config and QR code again
#   sudo ./vpn.sh remove <name>      revoke a device
#   sudo ./vpn.sh list               list devices and when each last connected
#   sudo ./vpn.sh uninstall          remove the VPN and every config
#
# Settings for `install` (environment variables, all optional):
#   VPN_ENDPOINT   public IP or hostname clients connect to (auto-detected)
#   VPN_PORT       UDP port                       (default 51820)
#   VPN_DNS        DNS servers handed to clients  (default 1.1.1.1, 1.0.0.1)
#
# Supports Debian, Ubuntu, Fedora, RHEL-family, Arch and Alpine.

# Variables like ENDPOINT and PORT come from the sourced params file.
# shellcheck disable=SC2153
set -euo pipefail

WG_IF="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_IF.conf"
PARAMS="$WG_DIR/vpn-params"
CLIENT_DIR="$WG_DIR/clients"
SYSCTL_FILE="/etc/sysctl.d/99-vpn-forwarding.conf"

# Tunnel address space: IPv4 /24 plus an IPv6 ULA /64. Routing IPv6 through the
# tunnel too means a client's IPv6 traffic can't leak around the VPN.
NET4_PREFIX="10.66.66"
NET6_PREFIX="fd42:42:42::"

die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

need_root() { [[ $EUID -eq 0 ]] || die "run this with sudo (root is needed to configure networking)."; }
need_installed() { [[ -f $PARAMS ]] || die "the VPN isn't installed yet. Run: sudo $0 install"; }

valid_name() {
	[[ $1 =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "device names use letters, digits, - and _ (max 32 characters)."
}

# --------------------------------------------------------------------------
# install
# --------------------------------------------------------------------------

install_packages() {
	info "Installing WireGuard"
	if command -v apt-get >/dev/null; then
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -q
		apt-get install -yq wireguard-tools qrencode iptables curl
	elif command -v dnf >/dev/null; then
		dnf install -yq wireguard-tools qrencode iptables curl
	elif command -v pacman >/dev/null; then
		pacman -Sy --noconfirm --needed wireguard-tools qrencode iptables curl
	elif command -v apk >/dev/null; then
		apk add --no-cache wireguard-tools qrencode iptables ip6tables curl
	else
		die "unsupported distribution: install wireguard-tools, qrencode and iptables yourself, then rerun."
	fi
}

detect_endpoint() {
	local ip
	ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
	[[ -n $ip ]] || ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
	[[ -n $ip ]] || die "couldn't detect this server's public IP. Set VPN_ENDPOINT and rerun."
	printf '%s' "$ip"
}

cmd_install() {
	need_root
	[[ -f $PARAMS ]] && die "already installed. Use 'add <name>' to create devices, or 'uninstall' to start over."

	local endpoint="${VPN_ENDPOINT:-}" port="${VPN_PORT:-51820}" dns="${VPN_DNS:-1.1.1.1, 1.0.0.1}"
	if ! [[ $port =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
		die "VPN_PORT must be 1-65535."
	fi

	local wan
	wan="$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
	[[ -n $wan ]] || die "no default network interface found."

	install_packages
	[[ -n $endpoint ]] || endpoint="$(detect_endpoint)"

	info "Generating server keys"
	umask 077
	mkdir -p "$WG_DIR" "$CLIENT_DIR"
	local server_priv server_pub
	server_priv="$(wg genkey)"
	server_pub="$(printf '%s' "$server_priv" | wg pubkey)"

	cat >"$PARAMS" <<-EOF
		ENDPOINT=$endpoint
		PORT=$port
		DNS="$dns"
		WAN=$wan
		SERVER_PUB=$server_pub
	EOF

	# NAT and forwarding rules live in PostUp/PostDown so they follow the
	# interface: brought up with it, removed with it.
	cat >"$WG_CONF" <<-EOF
		[Interface]
		Address = $NET4_PREFIX.1/24, ${NET6_PREFIX}1/64
		ListenPort = $port
		PrivateKey = $server_priv
		PostUp = iptables -I FORWARD -i %i -j ACCEPT; iptables -I FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o $wan -j MASQUERADE
		PostUp = ip6tables -I FORWARD -i %i -j ACCEPT || true; ip6tables -I FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT || true; ip6tables -t nat -A POSTROUTING -o $wan -j MASQUERADE || true
		PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $wan -j MASQUERADE
		PostDown = ip6tables -D FORWARD -i %i -j ACCEPT || true; ip6tables -D FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT || true; ip6tables -t nat -D POSTROUTING -o $wan -j MASQUERADE || true
	EOF

	info "Enabling IP forwarding"
	printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' >"$SYSCTL_FILE"
	sysctl -q -p "$SYSCTL_FILE"

	if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
		info "Opening UDP $port in ufw"
		ufw allow "$port/udp" >/dev/null
	elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
		info "Opening UDP $port in firewalld"
		firewall-cmd -q --permanent --add-port="$port/udp"
		firewall-cmd -q --permanent --add-masquerade
		firewall-cmd -q --reload
	fi

	info "Starting the VPN"
	if command -v systemctl >/dev/null; then
		systemctl enable --now "wg-quick@$WG_IF" >/dev/null
	elif command -v rc-update >/dev/null; then
		ln -sf /etc/init.d/wg-quick "/etc/init.d/wg-quick.$WG_IF" 2>/dev/null || true
		rc-update add "wg-quick.$WG_IF" default >/dev/null 2>&1 || true
		wg-quick up "$WG_IF"
	else
		wg-quick up "$WG_IF"
	fi

	cat <<-EOF

		VPN server is running on $endpoint, UDP port $port.

		If your host has a cloud firewall (AWS security group, DigitalOcean,
		Hetzner, Oracle...), allow inbound UDP $port there too.

		Next, create a config for each device:
		    sudo $0 add phone
	EOF
}

# --------------------------------------------------------------------------
# clients
# --------------------------------------------------------------------------

# Defines ENDPOINT, PORT, DNS, WAN and SERVER_PUB.
# shellcheck source=/dev/null
load_params() { source "$PARAMS"; }

client_exists() { grep -qx "### Client $1" "$WG_CONF"; }

next_host_id() {
	local used id
	used="$(grep -oE "^AllowedIPs = ${NET4_PREFIX//./\\.}\.[0-9]+" "$WG_CONF" | awk -F. '{print $NF}')"
	for id in $(seq 2 254); do
		grep -qx "$id" <<<"$used" || { printf '%s' "$id"; return; }
	done
	die "the VPN is full (253 devices). Remove one first."
}

# Apply wg0.conf changes to the running interface without dropping anyone.
reload() {
	wg show "$WG_IF" >/dev/null 2>&1 || return 0
	wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
}

print_client() {
	local file="$CLIENT_DIR/$1.conf"
	[[ -f $file ]] || die "no device named '$1'."
	printf '\n--- %s ---\n' "$file"
	cat "$file"
	printf '\nScan with the WireGuard app (iOS / Android):\n\n'
	qrencode -t ansiutf8 <"$file"
}

cmd_add() {
	need_root; need_installed
	local name="${1:-}"
	[[ -n $name ]] || die "usage: $0 add <name>"
	valid_name "$name"
	client_exists "$name" && die "a device named '$name' already exists."
	load_params

	local id priv pub psk
	id="$(next_host_id)"
	umask 077
	priv="$(wg genkey)"
	pub="$(printf '%s' "$priv" | wg pubkey)"
	psk="$(wg genpsk)"

	cat >>"$WG_CONF" <<-EOF

		### Client $name
		[Peer]
		PublicKey = $pub
		PresharedKey = $psk
		AllowedIPs = $NET4_PREFIX.$id/32, ${NET6_PREFIX}$id/128
	EOF

	local host="$ENDPOINT"
	[[ $host == *:* ]] && host="[$host]"   # bracket IPv6 endpoints

	cat >"$CLIENT_DIR/$name.conf" <<-EOF
		[Interface]
		PrivateKey = $priv
		Address = $NET4_PREFIX.$id/32, ${NET6_PREFIX}$id/128
		DNS = $DNS

		[Peer]
		PublicKey = $SERVER_PUB
		PresharedKey = $psk
		Endpoint = $host:$PORT
		AllowedIPs = 0.0.0.0/0, ::/0
		PersistentKeepalive = 25
	EOF

	reload
	info "Added '$name' ($NET4_PREFIX.$id)"
	print_client "$name"
}

cmd_show() {
	need_root; need_installed
	[[ -n ${1:-} ]] || die "usage: $0 show <name>"
	valid_name "$1"
	print_client "$1"
}

cmd_remove() {
	need_root; need_installed
	local name="${1:-}"
	[[ -n $name ]] || die "usage: $0 remove <name>"
	valid_name "$name"
	client_exists "$name" || die "no device named '$name'."

	# Drop the "### Client <name>" block: everything up to the next blank line.
	local tmp
	tmp="$(mktemp "$WG_DIR/.wg.XXXXXX")"
	awk -v marker="### Client $name" '
		$0 == marker { skip = 1; next }
		skip && /^[[:space:]]*$/ { skip = 0; next }
		!skip
	' "$WG_CONF" >"$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$WG_CONF"
	rm -f "$CLIENT_DIR/$name.conf"

	reload
	info "Removed '$name'. That device can no longer connect."
}

cmd_list() {
	need_root; need_installed
	local names
	names="$(sed -n 's/^### Client //p' "$WG_CONF")"
	if [[ -z $names ]]; then
		echo "No devices yet. Add one with: sudo $0 add <name>"
		return
	fi

	local now name pub ip ts ago
	now="$(date +%s)"
	printf '%-20s %-15s %s\n' "DEVICE" "ADDRESS" "LAST CONNECTED"
	while IFS= read -r name; do
		pub="$(awk -v m="### Client $name" '$0==m{f=1} f && /^PublicKey/{print $3; exit}' "$WG_CONF")"
		ip="$(awk -v m="### Client $name" '$0==m{f=1} f && /^AllowedIPs/{sub(/\/.*/, "", $3); print $3; exit}' "$WG_CONF")"
		ts="$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk -v k="$pub" '$1==k{print $2}' || true)"
		if [[ -z $ts || $ts == 0 ]]; then
			ago="never"
		else
			ago="$(( (now - ts) / 60 )) min ago"
		fi
		printf '%-20s %-15s %s\n' "$name" "$ip" "$ago"
	done <<<"$names"
}

cmd_uninstall() {
	need_root; need_installed
	read -r -p "This deletes the VPN and every device config. Type 'yes' to continue: " answer
	[[ $answer == yes ]] || { echo "Cancelled."; return; }
	load_params

	if command -v systemctl >/dev/null; then
		systemctl disable --now "wg-quick@$WG_IF" >/dev/null 2>&1 || true
	fi
	wg-quick down "$WG_IF" >/dev/null 2>&1 || true

	if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
		ufw delete allow "$PORT/udp" >/dev/null 2>&1 || true
	fi

	rm -rf "$WG_CONF" "$CLIENT_DIR" "$PARAMS" "$SYSCTL_FILE"
	sysctl -q --system >/dev/null 2>&1 || true
	info "VPN removed. (The wireguard-tools package is still installed.)"
}

# --------------------------------------------------------------------------

usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
	install)   cmd_install ;;
	add)       cmd_add "${2:-}" ;;
	show)      cmd_show "${2:-}" ;;
	remove)    cmd_remove "${2:-}" ;;
	list)      cmd_list ;;
	uninstall) cmd_uninstall ;;
	*)         usage; exit 1 ;;
esac
