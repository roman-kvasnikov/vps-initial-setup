#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════╗
# ║          VPS/VDS Basic Security Hardening Script         ║
# ║                                                          ║
# ║  Automated security hardening for Ubuntu VPS (nftables)  ║
# ╚══════════════════════════════════════════════════════════╝
#

set -euo pipefail

# ─── Colors and formatting ─────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Output functions ──────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✘]${NC} $1"; }
header()  { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${NC}\n"; }

# ─── Log file ──────────────────────────────────────────────
LOG_FILE="/var/log/vps-initial-setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ─── Pre-flight checks ────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo bash $0)"
    exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu/Debian. Other distros may have issues."
    read -rp "Continue? (y/n): " CONTINUE
    [[ "$CONTINUE" != "y" ]] && exit 0
fi

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          VPS/VDS Basic Security Hardening Script         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Log file: ${YELLOW}$LOG_FILE${NC}\n"

# ═══════════════════════════════════════════════════════════════
# STEP 1: Configuration
# ═══════════════════════════════════════════════════════════════
header "STEP 1: Configuration"

# --- Username ---
while true; do
    read -rp "Enter new username: " NEW_USER
    if [[ -z "$NEW_USER" ]]; then
        error "Username cannot be empty"
    elif [[ "$NEW_USER" == "root" ]]; then
        error "Cannot use 'root'"
    elif [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        error "Invalid name. Use lowercase letters, digits, - and _"
    elif id "$NEW_USER" &>/dev/null; then
        warn "User '$NEW_USER' already exists"
        read -rp "Use existing user? (y/n): " USE_EXISTING
        [[ "$USE_EXISTING" == "y" ]] && break
    else
        break
    fi
done

# --- SSH port ---
echo ""
while true; do
    read -rp "Enter new SSH port (1025-65535, recommended 10000-65535): " SSH_PORT
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        error "Port must be a number"
    elif (( SSH_PORT < 1025 || SSH_PORT > 65535 )); then
        error "Port must be in range 1025-65535"
    elif (( SSH_PORT == 2222 || SSH_PORT == 22222 )); then
        warn "Port $SSH_PORT is commonly scanned. Consider choosing another."
        read -rp "Use it anyway? (y/n): " USE_PORT
        [[ "$USE_PORT" == "y" ]] && break
    else
        break
    fi
done

# --- SSH key ---
echo ""
info "Paste your public SSH key (contents of id_ed25519.pub or id_rsa.pub)."
info "Press Enter to skip (you can add it later via ssh-copy-id)."
read -rp "SSH public key: " SSH_PUB_KEY

if [[ -n "$SSH_PUB_KEY" ]]; then
    if ! echo "$SSH_PUB_KEY" | ssh-keygen -l -f - &>/dev/null; then
        error "Invalid SSH key. Check format (ssh-ed25519 AAAA... or ssh-rsa AAAA...)."
        read -rp "Use it anyway? (y/n): " USE_INVALID_KEY
        [[ "$USE_INVALID_KEY" != "y" ]] && SSH_PUB_KEY=""
    fi
fi

# --- Endlessh ---
echo ""
info "Endlessh — SSH tarpit (trap on port 22)."
info "Bots connect to port 22 and get stuck for hours, wasting their resources."
read -rp "Install Endlessh on port 22? (y/n, default y): " INSTALL_ENDLESSH
INSTALL_ENDLESSH=${INSTALL_ENDLESSH:-y}

# --- IP Forwarding ---
echo ""
info "IP forwarding is needed for VPN gateways (WireGuard, OpenVPN), Docker and NAT."
info "If the server is just a host — better to disable."
read -rp "Enable IP forwarding? (y/n, default n): " ENABLE_IP_FORWARD
ENABLE_IP_FORWARD=${ENABLE_IP_FORWARD:-n}

# --- Auto-reboot ---
echo ""
info "Security updates may require a reboot."
info "If enabled — the server will reboot automatically at 4:00 AM (if no users are logged in)."
read -rp "Allow automatic reboot? (y/n, default n): " AUTO_REBOOT
AUTO_REBOOT=${AUTO_REBOOT:-n}

# --- Hostname ---
echo ""
read -rp "Set server hostname? (leave empty to skip): " NEW_HOSTNAME

# --- Timezone ---
echo ""
read -rp "Timezone (e.g. Europe/London, empty = UTC): " TIMEZONE
TIMEZONE=${TIMEZONE:-UTC}

# --- Confirmation ---
echo ""
header "Review settings"
echo -e "  Username:        ${GREEN}$NEW_USER${NC}"
echo -e "  SSH port:        ${GREEN}$SSH_PORT${NC}"
echo -e "  Endlessh:        ${GREEN}$([ "$INSTALL_ENDLESSH" == "y" ] && echo "yes (tarpit on port 22)" || echo "no")${NC}"
echo -e "  IP forwarding:   ${GREEN}$([ "$ENABLE_IP_FORWARD" == "y" ] && echo "enabled (VPN/Docker)" || echo "disabled")${NC}"
echo -e "  SSH key:         ${GREEN}${SSH_PUB_KEY:+provided}${SSH_PUB_KEY:-not provided (add later)}${NC}"
echo -e "  Auto-reboot:     ${GREEN}$([ "$AUTO_REBOOT" == "y" ] && echo "yes (at 4:00 AM, if no users)" || echo "no")${NC}"
echo -e "  Hostname:        ${GREEN}${NEW_HOSTNAME:-unchanged}${NC}"
echo -e "  Timezone:        ${GREEN}$TIMEZONE${NC}"
echo ""
read -rp "Everything correct? Start setup? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && { info "Cancelled."; exit 0; }

# ═══════════════════════════════════════════════════════════════
# STEP 2: System update
# ═══════════════════════════════════════════════════════════════
header "STEP 2: System update"

info "Updating package lists and installing upgrades..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt update -y
apt full-upgrade -y
success "System updated"

# ═══════════════════════════════════════════════════════════════
# STEP 3: Install packages
# ═══════════════════════════════════════════════════════════════
header "STEP 3: Installing packages"

PACKAGES=(
    fail2ban           # Brute-force protection
    iptables
    nftables           # Firewall (iptables replacement)
    unattended-upgrades # Automatic security updates
    curl               # HTTP client
    wget               # File downloader
    htop               # Resource monitor
    iotop              # I/O monitor
    net-tools          # Network utilities (ifconfig, netstat)
    sudo               # Just in case
    logwatch           # Log summary reports
    needrestart        # Check if service restart is needed
    apt-listchanges    # Show changelog on upgrade
)

info "Installing packages: ${PACKAGES[*]}"
apt install -y "${PACKAGES[@]}"
success "Packages installed"

# ═══════════════════════════════════════════════════════════════
# STEP 4: Hostname and timezone
# ═══════════════════════════════════════════════════════════════
header "STEP 4: Basic system settings"

if [[ -n "$NEW_HOSTNAME" ]]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    if ! grep -qw "$NEW_HOSTNAME" /etc/hosts; then
        sed -i "0,/^127\.0\.0\.1/s|^127\.0\.0\.1.*|127.0.0.1 localhost $NEW_HOSTNAME|" /etc/hosts
    fi
    success "Hostname set: $NEW_HOSTNAME"
fi

timedatectl set-timezone "$TIMEZONE"
success "Timezone: $TIMEZONE"

# ═══════════════════════════════════════════════════════════════
# STEP 5: Create user
# ═══════════════════════════════════════════════════════════════
header "STEP 5: Creating user '$NEW_USER'"

if ! id "$NEW_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$NEW_USER"
    success "User '$NEW_USER' created"
else
    warn "User '$NEW_USER' already exists, skipping creation"
fi

usermod -aG sudo "$NEW_USER"
success "User added to sudo group"

info "Set password for user '$NEW_USER':"
while ! passwd "$NEW_USER"; do
    warn "Try again"
done
success "Password set"

USER_HOME=$(getent passwd "$NEW_USER" | cut -d: -f6)
if ! grep -q 'umask 0077' "$USER_HOME/.bashrc" 2>/dev/null; then
    echo 'umask 0077' >> "$USER_HOME/.bashrc"
    success "UMASK 0077 set for $NEW_USER"
fi

info "Locking root account password..."
passwd -l root
success "Root account locked (login via su/ssh disabled, sudo still works)"

# ═══════════════════════════════════════════════════════════════
# STEP 6: SSH keys
# ═══════════════════════════════════════════════════════════════
header "STEP 6: SSH keys"

SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

if [[ -n "$SSH_PUB_KEY" ]]; then
    if [[ -f "$AUTH_KEYS" ]] && grep -qF "$SSH_PUB_KEY" "$AUTH_KEYS"; then
        warn "This SSH key is already added"
    else
        echo "$SSH_PUB_KEY" >> "$AUTH_KEYS"
        success "SSH key added"
    fi
else
    warn "No SSH key provided. Don't forget to add one later:"
    info "  ssh-copy-id -p $SSH_PORT $NEW_USER@<IP_ADDRESS>"
fi

chown -R "$NEW_USER:$NEW_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
[[ -f "$AUTH_KEYS" ]] && chmod 600 "$AUTH_KEYS"
success ".ssh permissions set (700/600)"

# ═══════════════════════════════════════════════════════════════
# STEP 7: SSH configuration
# ═══════════════════════════════════════════════════════════════
header "STEP 7: SSH server configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"

if ! grep -q "^Include /etc/ssh/sshd_config.d/" "$SSHD_CONFIG" 2>/dev/null; then
    warn "$SSHD_CONFIG is missing Include for sshd_config.d/."
    warn "Adding Include directive to the beginning of the file..."
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSHD_CONFIG"
    success "Include added, backup of original created"
fi

if [[ -n "$SSH_PUB_KEY" ]]; then
    PASSWORD_AUTH="no"
else
    PASSWORD_AUTH="yes"
    warn "Password authentication is ENABLED because no SSH key was provided."
    warn "After adding a key, disable password in /etc/ssh/sshd_config.d/00-hardening.conf"
fi

cat > /etc/ssh/sshd_config.d/00-hardening.conf << EOF
# ═══ VPS Hardening Config ═══
# Generated: $(date)

Port $SSH_PORT
LoginGraceTime 1m
PermitRootLogin no

PubkeyAuthentication yes
PasswordAuthentication $PASSWORD_AUTH
PermitEmptyPasswords no
KbdInteractiveAuthentication no

AllowUsers $NEW_USER

ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
MaxAuthTries 3
MaxStartups 10:30:60

UsePAM yes

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com

LogLevel VERBOSE
EOF

chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf

if sshd -t 2>/dev/null; then
    success "SSH configuration is valid"
else
    error "SSH configuration error! Removing drop-in config..."
    rm -f /etc/ssh/sshd_config.d/00-hardening.conf
    error "00-hardening.conf removed. SSH will revert to defaults."
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# STEP 8: Firewall (nftables)
# ═══════════════════════════════════════════════════════════════
header "STEP 8: Firewall (nftables)"

# Switch iptables to nftables backend (needed for Docker compatibility)
if command -v update-alternatives &>/dev/null; then
    update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true
    success "iptables switched to nft backend (Docker compatible)"
else
    warn "update-alternatives not found, skipping iptables-nft switch"
fi

# Backup
if [[ -f /etc/nftables.conf ]]; then
    cp /etc/nftables.conf "/etc/nftables.conf.backup.$(date +%Y%m%d-%H%M%S)"
    info "Backup of /etc/nftables.conf created"
fi

info "Generating /etc/nftables.conf ..."

FORWARD_POLICY=$([ "$ENABLE_IP_FORWARD" == "y" ] && echo "accept" || echo "drop")

cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f
#
# VPS Hardening — nftables firewall
# Generated: $(date)
#

flush ruleset

table inet filter {

    # SSH rate limiting: remembers IPs, auto-cleanup after 300 seconds
    set sshbrute4 {
        type ipv4_addr
        flags dynamic, timeout
        timeout 300s
    }

    set sshbrute6 {
        type ipv6_addr
        flags dynamic, timeout
        timeout 300s
    }

    chain input {
        type filter hook input priority 0; policy drop;

        # Loopback
        iif "lo" accept

        # Drop invalid packets
        ct state invalid drop

        # Established/Related
        ct state established,related accept

        # ICMP (ping)
        ip protocol icmp icmp type echo-request accept

        # ICMPv6 (Neighbor Discovery, Path MTU, etc.)
        ip6 nexthdr ipv6-icmp accept

        # SSH (port $SSH_PORT) with rate limiting — max 4 new connections/min per IP
        tcp dport $SSH_PORT ct state new ip saddr != 127.0.0.0/8 add @sshbrute4 { ip saddr limit rate over 4/minute } \\
            log prefix "nft-ssh-brute: " level warn drop
        tcp dport $SSH_PORT ct state new ip6 saddr != ::1 add @sshbrute6 { ip6 saddr limit rate over 4/minute } \\
            log prefix "nft-ssh-brute6: " level warn drop
        tcp dport $SSH_PORT accept

$(if [[ "$INSTALL_ENDLESSH" == "y" ]]; then
echo "        # Endlessh tarpit (port 22)"
echo "        tcp dport 22 accept"
fi)

        # === Additional ports (add here) ===
        # tcp dport 443 accept
        # tcp dport 80 accept
        # udp dport 51820 accept

        # Log dropped packets
        limit rate 5/minute log prefix "nft-dropped: " level warn
    }

    chain forward {
        type filter hook forward priority 10; policy $FORWARD_POLICY;

        # Let Docker/iptables-nft handle its own traffic first (priority 0)
        # Everything else is dropped
        ct state established,related accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

success "/etc/nftables.conf created"

# Validate before applying
if nft -c -f /etc/nftables.conf; then
    success "nftables configuration is valid"
else
    error "nftables configuration error! Check /etc/nftables.conf"
    exit 1
fi

nft -f /etc/nftables.conf
success "nftables rules loaded"

systemctl enable nftables
success "nftables enabled (rules load on boot)"

info "Current ruleset:"
nft list ruleset

# ═══════════════════════════════════════════════════════════════
# STEP 9: Fail2Ban
# ═══════════════════════════════════════════════════════════════
header "STEP 9: Fail2Ban"

cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled   = true
port      = $SSH_PORT
filter    = sshd
banaction = nftables-multiport
backend   = systemd
maxretry  = 5
findtime  = 600
bantime   = 3600
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 86400
EOF

cat > /etc/fail2ban/jail.d/recidive.local << EOF
[recidive]
enabled   = true
filter    = recidive
logpath   = /var/log/fail2ban.log
banaction = nftables-multiport
maxretry  = 3
findtime  = 86400
bantime   = 604800
EOF

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2Ban configured (banaction: nftables-multiport)"
info "SSH jail: 5 attempts in 10 min → 1 hour ban (increases on repeat)"
info "Recidive jail: repeat offenders → 1 week ban"

# ═══════════════════════════════════════════════════════════════
# STEP 10: Automatic security updates
# ═══════════════════════════════════════════════════════════════
header "STEP 10: Automatic updates"

AUTO_REBOOT_VALUE=$([ "$AUTO_REBOOT" == "y" ] && echo "true" || echo "false")
cat > /etc/apt/apt.conf.d/50unattended-upgrades << UPGEOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT_VALUE}";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
UPGEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
success "Automatic security updates configured"

# ═══════════════════════════════════════════════════════════════
# STEP 11: Additional hardening
# ═══════════════════════════════════════════════════════════════
header "STEP 11: Additional hardening"

info "Configuring kernel parameters (sysctl hardening)..."
cat > /etc/sysctl.d/99-security-hardening.conf << EOF
# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects (MITM protection)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# IP forwarding
net.ipv4.ip_forward = $([ "$ENABLE_IP_FORWARD" == "y" ] && echo 1 || echo 0)

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Ignore ICMP broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable core dumps
fs.suid_dumpable = 0

# Hide kernel addresses (protects against pointer leak exploits)
kernel.kptr_restrict = 2

# Restrict dmesg to root (may contain sensitive info)
kernel.dmesg_restrict = 1

# BPF restricted to root (prevents unprivileged kernel exploits)
kernel.unprivileged_bpf_disabled = 1

# perf restricted to root
kernel.perf_event_paranoid = 3

# Symlink/hardlink attack protection in sticky directories (/tmp, etc.)
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF

sysctl --system > /dev/null 2>&1
success "Kernel parameters hardened"

info "Disabling core dumps..."
if ! grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null; then
    echo "* hard core 0" >> /etc/security/limits.conf
fi
success "Core dumps disabled"

info "Setting default UMASK in login.defs..."
sed -i 's/^UMASK\s.*/UMASK 077/' /etc/login.defs
success "Default UMASK set to 077 in /etc/login.defs"

info "Hardening shared memory (/dev/shm)..."
if ! grep -q "/dev/shm" /etc/fstab 2>/dev/null; then
    echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    mount -o remount /dev/shm 2>/dev/null || true
fi
success "/dev/shm hardened (noexec,nosuid,nodev)"

info "Restricting cron access..."
printf 'root\n%s\n' "$NEW_USER" > /etc/cron.allow
chmod 600 /etc/cron.allow
success "Only $NEW_USER and root can use cron"

info "Restricting su command..."
if ! grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null || grep -q "^#.*pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
    sed -i 's/^#\s*\(auth\s*required\s*pam_wheel.so\).*/\1 group=sudo/' /etc/pam.d/su
    success "su restricted to sudo group"
fi

info "Hardening sudo configuration..."
cat > /etc/sudoers.d/99-hardening << 'EOF'
# Timeout for password cache (minutes)
Defaults timestamp_timeout=5

# Show password prompt on failed attempts, not just silently fail
Defaults passwd_tries=3
EOF
chmod 440 /etc/sudoers.d/99-hardening
if visudo -c &>/dev/null; then
    success "Sudo hardened (timeout=5min, 3 attempts)"
else
    error "Invalid sudoers config, removing..."
    rm -f /etc/sudoers.d/99-hardening
fi

info "Disabling unnecessary services..."
DISABLE_SERVICES=(avahi-daemon cups bluetooth)
for svc in "${DISABLE_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc"
        systemctl disable "$svc"
        success "Disabled: $svc"
    fi
done

# ═══════════════════════════════════════════════════════════════
# STEP 12: Endlessh (SSH Tarpit)
# ═══════════════════════════════════════════════════════════════
if [[ "$INSTALL_ENDLESSH" == "y" ]]; then
    header "STEP 12: Endlessh (SSH Tarpit)"

    if apt-cache show endlessh &>/dev/null; then
        apt install -y endlessh
        success "Endlessh installed from repository"

        ENDLESSH_BIN="/usr/bin/endlessh"
        mkdir -p /etc/systemd/system/endlessh.service.d
        cat > /etc/systemd/system/endlessh.service.d/override.conf << 'EOF'
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=false
InaccessiblePaths=
EOF
        success "Systemd override created"
    else
        info "Endlessh not found in repositories, building from source..."
        apt install -y build-essential git libc6-dev
        (
            cd /tmp
            git clone --depth 1 https://github.com/skeeto/endlessh.git
            cd endlessh
            make
            cp endlessh /usr/local/bin/
            chmod 755 /usr/local/bin/endlessh
        ) || { rm -rf /tmp/endlessh; error "Failed to build endlessh"; exit 1; }
        rm -rf /tmp/endlessh
        ENDLESSH_BIN="/usr/local/bin/endlessh"

        cat > /etc/systemd/system/endlessh.service << 'EOF'
[Unit]
Description=Endlessh SSH Tarpit
After=network.target

[Service]
ExecStart=/usr/local/bin/endlessh -v
ExecStart=/usr/local/bin/endlessh -v -c /etc/endlessh/config
AmbientCapabilities=CAP_NET_BIND_SERVICE
KillSignal=SIGTERM
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        success "Endlessh built and installed"
    fi

    mkdir -p /etc/endlessh
    cat > /etc/endlessh/config << 'EOF'
Port 22
Delay 10000
MaxClients 100
MaxLineLength 32
MaxStartTime 0
BindFamily 0
LogLevel 1
EOF

    setcap 'cap_net_bind_service=+ep' "$ENDLESSH_BIN"
    success "CAP_NET_BIND_SERVICE set"

    systemctl daemon-reload
    systemctl enable endlessh
    systemctl start endlessh

    if systemctl is-active --quiet endlessh; then
        success "Endlessh running on port 22 — bots will suffer 😈"
    else
        warn "Endlessh failed to start. Check: journalctl -u endlessh"
    fi
else
    info "Endlessh skipped"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 13: Restart SSH and verify
# ═══════════════════════════════════════════════════════════════
header "STEP 13: Applying SSH settings"

info "Verifying SSH configuration before restart..."
if ! sshd -t 2>&1; then
    error "SSH configuration is invalid! Aborting restart."
    error "Fix the config and restart manually: systemctl restart ssh"
    exit 1
fi
success "SSH configuration is valid"

warn "WARNING: SSH will be restarted with new settings!"
warn "Your current session will remain active."
warn "Make sure to test the connection in a NEW terminal before closing this session!"
echo ""

if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
    success "SSH server restarted"

    sleep 2

    # Check: is sshd listening on the new port
    if ss -tlnp | grep -q ":${SSH_PORT}\b"; then
        success "SSH is listening on port $SSH_PORT ✔"
    else
        error "SSH is NOT listening on port $SSH_PORT!"
        warn "Checking which port sshd is listening on:"
        ss -tlnp | grep sshd || ss -tlnp | grep ssh
    fi

    # Check: nftables allows the SSH port
    if nft list chain inet filter input 2>/dev/null | grep -q "dport $SSH_PORT"; then
        success "nftables: port $SSH_PORT is open ✔"
    else
        error "nftables: port $SSH_PORT NOT found in rules!"
        warn "Emergency port opening..."
        nft add rule inet filter input tcp dport "$SSH_PORT" accept
        warn "Port $SSH_PORT opened directly. Check /etc/nftables.conf"
    fi
else
    error "Failed to restart SSH! Check manually: systemctl status ssh"
fi

apt autoremove -y

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
header "SETUP COMPLETE"

echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    ✔ All done!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${BOLD}Connect to server:${NC}"
echo -e "  ${CYAN}ssh ${NEW_USER}@<IP_ADDRESS> -p ${SSH_PORT}${NC}"
echo ""

if [[ -z "$SSH_PUB_KEY" ]]; then
    echo -e "  ${YELLOW}⚠ Don't forget to add your SSH key:${NC}"
    echo -e "  ${CYAN}ssh-copy-id -p ${SSH_PORT} ${NEW_USER}@<IP_ADDRESS>${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠ After adding the key, disable password auth:${NC}"
    echo -e "  ${CYAN}sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/00-hardening.conf${NC}"
    echo -e "  ${CYAN}sudo systemctl restart ssh${NC}"
    echo ""
fi

echo -e "  ${BOLD}What was done:${NC}"
echo -e "  ├─ ✔ System updated"
echo -e "  ├─ ✔ User ${GREEN}$NEW_USER${NC} created with sudo"
echo -e "  ├─ ✔ SSH port: ${GREEN}$SSH_PORT${NC}, root disabled, password: ${GREEN}$PASSWORD_AUTH${NC}"
echo -e "  ├─ ✔ SSH ciphers: curve25519/chacha20/ed25519 only"
echo -e "  ├─ ✔ nftables Firewall (inet: IPv4 + IPv6) + SSH rate limiting"
echo -e "  ├─ ✔ Fail2Ban (nftables-multiport) + recidive jail"
echo -e "  ├─ ✔ Automatic security updates"
echo -e "  ├─ ✔ Sysctl + kernel hardening (anti-spoofing, SYN flood, kptr, BPF, perf)"
echo -e "  ├─ ✔ Core dumps disabled, /dev/shm hardened"
echo -e "  ├─ ✔ Cron and su restricted, config files protected"
echo -e "  └─ ✔ Endlessh: ${GREEN}$([ "$INSTALL_ENDLESSH" == "y" ] && echo "tarpit on port 22" || echo "skipped")${NC}"
echo ""

echo -e "  ${BOLD}Firewall:${NC} /etc/nftables.conf"
echo -e "  To open a port, add a line to chain input:"
echo -e "  ${CYAN}tcp dport 443 accept${NC}"
echo -e "  Then apply: ${CYAN}sudo nft -f /etc/nftables.conf${NC}"
echo ""

# --- Ports open through firewall ---
echo -e "  ${BOLD}Ports open in firewall (accessible from outside):${NC}"
while IFS= read -r line; do
    port=$(echo "$line" | grep -oP 'dport \K[0-9]+')
    [[ -z "$port" ]] && continue
    service=$(ss -tlnp "sport = :$port" 2>/dev/null | awk 'NR>1 {
        match($0, /users:\(\("([^"]+)"/, a); if (a[1]) print a[1]
    }' | head -1)
    service=${service:-"(nothing listening)"}
    echo -e "  ${GREEN}✔${NC} port ${CYAN}$port${NC} — $service"
done < <(nft -a list chain inet filter input 2>/dev/null | grep -E 'dport.*accept')
echo ""

echo -e "  ${BOLD}Log:${NC} $LOG_FILE"
echo ""

echo -e "${RED}${BOLD}  ⚠ IMPORTANT: Do not close this session!${NC}"
echo -e "${RED}  Open a NEW terminal and test your connection:${NC}"
echo -e "${CYAN}  ssh ${NEW_USER}@<IP_ADDRESS> -p ${SSH_PORT}${NC}"
echo ""
echo -e "  If you can't connect — fix it from this session."
echo ""
