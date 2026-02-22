#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════╗
# ║          VPS/VDS Basic Security Hardening Script         ║
# ║                                                          ║
# ║  Автоматизация базовой настройки безопасности            ║
# ║  Ubuntu VPS-сервера                                      ║
# ╚══════════════════════════════════════════════════════════╝
#

set -euo pipefail

# ─── Цвета и форматирование ─────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Функции вывода ─────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✘]${NC} $1"; }
header()  { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${NC}\n"; }

# ─── Лог-файл ───────────────────────────────────────────────
LOG_FILE="/var/log/vps-setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ─── Проверки перед началом ──────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Скрипт нужно запускать от root (sudo bash $0)"
    exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    warn "Скрипт оптимизирован для Ubuntu/Debian. На других дистрибутивах могут быть проблемы."
    read -rp "Продолжить? (y/n): " CONTINUE
    [[ "$CONTINUE" != "y" ]] && exit 0
fi

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          VPS/VDS Basic Security Hardening Script         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Лог записывается в: ${YELLOW}$LOG_FILE${NC}\n"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 1: Ввод параметров
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 1: Параметры настройки"

# --- Имя пользователя ---
while true; do
    read -rp "Введите имя нового пользователя: " NEW_USER
    if [[ -z "$NEW_USER" ]]; then
        error "Имя пользователя не может быть пустым"
    elif [[ "$NEW_USER" == "root" ]]; then
        error "Нельзя использовать 'root'"
    elif [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        error "Недопустимое имя. Используйте строчные латинские буквы, цифры, - и _"
    elif id "$NEW_USER" &>/dev/null; then
        warn "Пользователь '$NEW_USER' уже существует"
        read -rp "Использовать существующего? (y/n): " USE_EXISTING
        [[ "$USE_EXISTING" == "y" ]] && break
    else
        break
    fi
done

# --- SSH порт ---
while true; do
    read -rp "Введите новый SSH порт (1025-65535, рекомендуется 10000-65535): " SSH_PORT
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        error "Порт должен быть числом"
    elif (( SSH_PORT < 1025 || SSH_PORT > 65535 )); then
        error "Порт должен быть в диапазоне 1025-65535"
    elif (( SSH_PORT == 2222 || SSH_PORT == 22222 )); then
        warn "Порт $SSH_PORT часто сканируется. Лучше выбрать другой."
        read -rp "Всё равно использовать? (y/n): " USE_PORT
        [[ "$USE_PORT" == "y" ]] && break
    else
        break
    fi
done

# --- Отключение IPv6 ---
read -rp "Отключить IPv6? (y/n, по умолчанию y): " DISABLE_IPV6
DISABLE_IPV6=${DISABLE_IPV6:-y}

# --- SSH-ключ ---
echo ""
info "Вставьте ваш публичный SSH-ключ (содержимое id_ed25519.pub или id_rsa.pub)."
info "Если хотите пропустить (добавите позже через ssh-copy-id), нажмите Enter."
read -rp "SSH публичный ключ: " SSH_PUB_KEY

if [[ -n "$SSH_PUB_KEY" ]]; then
    if ! echo "$SSH_PUB_KEY" | ssh-keygen -l -f - &>/dev/null; then
        error "SSH-ключ невалиден. Проверьте формат (ssh-ed25519 AAAA... или ssh-rsa AAAA...)."
        read -rp "Всё равно использовать? (y/n): " USE_INVALID_KEY
        [[ "$USE_INVALID_KEY" != "y" ]] && SSH_PUB_KEY=""
    fi
fi

# --- Endlessh ---
echo ""
info "Endlessh — SSH tarpit (ловушка на порту 22)."
info "Боты подключаются к порту 22 и зависают на часы, тратя свои ресурсы впустую."
read -rp "Установить Endlessh на порт 22? (y/n, по умолчанию y): " INSTALL_ENDLESSH
INSTALL_ENDLESSH=${INSTALL_ENDLESSH:-y}

# --- IP Forwarding ---
echo ""
info "IP forwarding нужен для VPN-шлюзов (WireGuard, OpenVPN), Docker и NAT."
info "Если сервер будет просто хостом — лучше отключить."
read -rp "Включить IP forwarding? (y/n, по умолчанию n): " ENABLE_IP_FORWARD
ENABLE_IP_FORWARD=${ENABLE_IP_FORWARD:-n}

# --- Автоперезагрузка ---
echo ""
info "При обновлениях безопасности может потребоваться перезагрузка."
info "Если включить — сервер перезагрузится автоматически в 4:00 (если нет залогиненных пользователей)."
read -rp "Разрешить автоматическую перезагрузку? (y/n, по умолчанию n): " AUTO_REBOOT
AUTO_REBOOT=${AUTO_REBOOT:-n}

# --- Hostname ---
read -rp "Задать hostname сервера? (оставьте пустым для пропуска): " NEW_HOSTNAME

# --- Timezone ---
read -rp "Часовой пояс (например Europe/Moscow, пусто = UTC): " TIMEZONE
TIMEZONE=${TIMEZONE:-UTC}

# --- Подтверждение ---
echo ""
header "Проверьте параметры"
echo -e "  Пользователь:    ${GREEN}$NEW_USER${NC}"
echo -e "  SSH порт:        ${GREEN}$SSH_PORT${NC}"
echo -e "  Отключить IPv6:  ${GREEN}$DISABLE_IPV6${NC}"
echo -e "  Endlessh:        ${GREEN}$([ "$INSTALL_ENDLESSH" == "y" ] && echo "да (tarpit на порту 22)" || echo "нет")${NC}"
echo -e "  IP forwarding:   ${GREEN}$([ "$ENABLE_IP_FORWARD" == "y" ] && echo "включён (VPN/Docker)" || echo "отключён")${NC}"
echo -e "  SSH-ключ:        ${GREEN}${SSH_PUB_KEY:+задан}${SSH_PUB_KEY:-не задан (добавите позже)}${NC}"
echo -e "  Автоперезагрузка:${GREEN}$([ "$AUTO_REBOOT" == "y" ] && echo "да (в 4:00, если нет пользователей)" || echo "нет")${NC}"
echo -e "  Hostname:        ${GREEN}${NEW_HOSTNAME:-без изменений}${NC}"
echo -e "  Часовой пояс:    ${GREEN}$TIMEZONE${NC}"
echo ""
read -rp "Всё верно? Начинаем настройку? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && { info "Отменено."; exit 0; }

# ═══════════════════════════════════════════════════════════════
# ЭТАП 2: Обновление системы
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 2: Обновление системы"

info "Обновление списка пакетов и установка обновлений..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt full-upgrade -y
success "Система обновлена"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 3: Установка необходимых пакетов
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 3: Установка пакетов"

PACKAGES=(
    fail2ban           # Защита от брутфорса
    iptables-persistent # Firewall (автозагрузка правил iptables)
    unattended-upgrades # Автоматические обновления безопасности
    curl               # HTTP-клиент
    wget               # Загрузчик файлов
    htop               # Мониторинг ресурсов
    iotop              # Мониторинг I/O
    net-tools          # Сетевые утилиты (ifconfig, netstat)
    sudo               # На случай если нет
    logwatch           # Сводка логов на email
    needrestart        # Проверка нужен ли рестарт сервисов
    apt-listchanges    # Показ изменений при обновлении
)

info "Установка пакетов: ${PACKAGES[*]}"
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt install -y "${PACKAGES[@]}"
success "Пакеты установлены"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 4: Настройка hostname и timezone
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 4: Базовые настройки системы"

if [[ -n "$NEW_HOSTNAME" ]]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    # Обновляем /etc/hosts
    if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
        sed -i "s|127.0.0.1.*|127.0.0.1 localhost $NEW_HOSTNAME|" /etc/hosts
    fi
    success "Hostname установлен: $NEW_HOSTNAME"
fi

timedatectl set-timezone "$TIMEZONE"
success "Часовой пояс: $TIMEZONE"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 5: Создание пользователя
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 5: Создание пользователя '$NEW_USER'"

if ! id "$NEW_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$NEW_USER"
    success "Пользователь '$NEW_USER' создан"
else
    warn "Пользователь '$NEW_USER' уже существует, пропускаем создание"
fi

usermod -aG sudo "$NEW_USER"
success "Пользователь добавлен в группу sudo"

# Установка пароля
info "Установите пароль для пользователя '$NEW_USER':"
while ! passwd "$NEW_USER"; do
    warn "Попробуйте ещё раз"
done
success "Пароль установлен"

# Настройка umask
USER_HOME=$(getent passwd "$NEW_USER" | cut -d: -f6)
if ! grep -q 'umask 0077' "$USER_HOME/.bashrc" 2>/dev/null; then
    echo 'umask 0077' >> "$USER_HOME/.bashrc"
    success "UMASK 0077 установлен для $NEW_USER"
fi

# ═══════════════════════════════════════════════════════════════
# ЭТАП 6: Настройка SSH-ключей
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 6: Настройка SSH-ключей"

SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

if [[ -n "$SSH_PUB_KEY" ]]; then
    # Проверяем, не добавлен ли уже этот ключ
    if [[ -f "$AUTH_KEYS" ]] && grep -qF "$SSH_PUB_KEY" "$AUTH_KEYS"; then
        warn "Этот SSH-ключ уже добавлен"
    else
        echo "$SSH_PUB_KEY" >> "$AUTH_KEYS"
        success "SSH-ключ добавлен"
    fi
else
    warn "SSH-ключ не задан. Не забудьте добавить его позже:"
    info "  ssh-copy-id -p $SSH_PORT $NEW_USER@<IP_ADDRESS>"
fi

# Права доступа
chown -R "$NEW_USER:$NEW_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
[[ -f "$AUTH_KEYS" ]] && chmod 600 "$AUTH_KEYS"
success "Права на .ssh установлены (700/600)"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 7: Конфигурация SSH
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 7: Конфигурация SSH-сервера"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Проверяем, что основной конфиг подключает drop-in директорию
if ! grep -q "^Include /etc/ssh/sshd_config.d/" "$SSHD_CONFIG" 2>/dev/null; then
    warn "В $SSHD_CONFIG нет Include для sshd_config.d/."
    warn "Добавляю строку Include в начало файла..."
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSHD_CONFIG"
    success "Include добавлен, бэкап оригинала создан"
fi

# Определяем, нужно ли оставить пароль (если нет SSH-ключа)
if [[ -n "$SSH_PUB_KEY" ]]; then
    PASSWORD_AUTH="no"
else
    PASSWORD_AUTH="yes"
    warn "Аутентификация по паролю ВКЛЮЧЕНА, т.к. SSH-ключ не задан."
    warn "После добавления ключа отключите пароль в /etc/ssh/sshd_config.d/00-hardening.conf"
fi

# Drop-in конфиг — перезаписывает параметры из основного sshd_config
cat > /etc/ssh/sshd_config.d/00-hardening.conf << EOF
# ═══ VPS Hardening Config ═══
# Сгенерировано: $(date)

# Порт
Port $SSH_PORT

# Таймаут аутентификации
LoginGraceTime 1m

# Запрет root
PermitRootLogin no

# Аутентификация по ключам
PubkeyAuthentication yes

# Пароль
PasswordAuthentication $PASSWORD_AUTH
PermitEmptyPasswords no
KbdInteractiveAuthentication no

# Разрешённые пользователи
AllowUsers $NEW_USER

# Таймаут неактивной сессии (10 минут)
ClientAliveInterval 300
ClientAliveCountMax 2

# Отключение X11 forwarding (не нужен на сервере)
X11Forwarding no

# Ограничение максимума попыток аутентификации
MaxAuthTries 3

# Ограничение одновременных неаутентифицированных соединений
MaxStartups 3:50:10

UsePAM yes

# Только сильные алгоритмы шифрования
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com

# Правовой баннер
Banner /etc/issue.net

# Логирование
LogLevel VERBOSE
EOF

# Правовой баннер при подключении
cat > /etc/issue.net << 'EOF'
*******************************************************************
  WARNING: Unauthorized access to this system is prohibited.
  All connections are monitored and recorded.
  Disconnect IMMEDIATELY if you are not an authorized user.
*******************************************************************
EOF

# Проверяем конфиг
if sshd -t 2>/dev/null; then
    success "SSH-конфигурация валидна"
else
    error "Ошибка в SSH-конфигурации! Удаляю drop-in конфиг..."
    rm -f /etc/ssh/sshd_config.d/00-hardening.conf
    error "Файл 00-hardening.conf удалён. SSH вернётся к настройкам по умолчанию."
    error "Проверьте конфигурацию вручную и перезапустите скрипт."
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# ЭТАП 8: Отключение IPv6
# ═══════════════════════════════════════════════════════════════
if [[ "$DISABLE_IPV6" == "y" ]]; then
    header "ЭТАП 8: Отключение IPv6"

    SYSCTL_CONF="/etc/sysctl.d/99-disable-ipv6.conf"
    cat > "$SYSCTL_CONF" << 'EOF'
# Отключение IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    sysctl --system > /dev/null 2>&1
    success "IPv6 отключён"
else
    info "IPv6 оставлен включённым"
fi

# ═══════════════════════════════════════════════════════════════
# ЭТАП 9: Настройка Firewall (iptables)
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 9: Настройка Firewall (iptables)"

mkdir -p /etc/iptables

info "Бэкап текущих правил..."
iptables-save > "/etc/iptables/rules.v4.backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
ip6tables-save > "/etc/iptables/rules.v6.backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

info "Генерация /etc/iptables/rules.v4 ..."

cat > /etc/iptables/rules.v4 << EOF
*filter

# === Политики по умолчанию ===
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# === Loopback ===
-A INPUT -i lo -j ACCEPT

# === Сброс невалидных пакетов ===
-A INPUT -m conntrack --ctstate INVALID -j DROP

# === Established/Related ===
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# === ICMP (ping) ===
-A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# === SSH (порт $SSH_PORT) с rate limiting ===
# Не более 4 новых соединений за 60 секунд с одного IP
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --set --name sshbrute
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name sshbrute -j LOG --log-prefix "iptables-ssh-brute: " --log-level 4
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name sshbrute -j DROP
-A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

$(if [[ "$INSTALL_ENDLESSH" == "y" ]]; then
echo "# === Endlessh tarpit (порт 22) ==="
echo "-A INPUT -p tcp --dport 22 -j ACCEPT"
fi)

# === Логирование дропнутого ===
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4

COMMIT
EOF

success "Файл /etc/iptables/rules.v4 создан"

# --- IPv6 правила ---
info "Генерация /etc/iptables/rules.v6 ..."

if [[ "$DISABLE_IPV6" == "y" ]]; then
    cat > /etc/iptables/rules.v6 << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
COMMIT
EOF
else
    cat > /etc/iptables/rules.v6 << EOF
*filter

# === Политики по умолчанию ===
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# === Loopback ===
-A INPUT -i lo -j ACCEPT

# === Сброс невалидных пакетов ===
-A INPUT -m conntrack --ctstate INVALID -j DROP

# === Established/Related ===
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# === ICMPv6 (необходим для работы IPv6: Neighbor Discovery, Path MTU и т.д.) ===
-A INPUT -p ipv6-icmp -j ACCEPT

# === SSH (порт $SSH_PORT) с rate limiting ===
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --set --name sshbrute6
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name sshbrute6 -j LOG --log-prefix "ip6tables-ssh-brute: " --log-level 4
-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name sshbrute6 -j DROP
-A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

$(if [[ "$INSTALL_ENDLESSH" == "y" ]]; then
echo "# === Endlessh tarpit (порт 22) ==="
echo "-A INPUT -p tcp --dport 22 -j ACCEPT"
fi)

# === Логирование дропнутого ===
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "ip6tables-dropped: " --log-level 4

COMMIT
EOF
fi

success "Файл /etc/iptables/rules.v6 создан"

# --- Применяем правила из файлов ---
iptables-restore < /etc/iptables/rules.v4
success "Правила IPv4 загружены"

ip6tables-restore < /etc/iptables/rules.v6
success "Правила IPv6 загружены"

systemctl enable netfilter-persistent
success "netfilter-persistent включён (правила загружаются при старте)"

info "Текущие правила iptables:"
iptables -L -n --line-numbers

# ═══════════════════════════════════════════════════════════════
# ЭТАП 10: Настройка Fail2Ban
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 10: Настройка Fail2Ban"

cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled   = true
port      = $SSH_PORT
filter    = sshd
banaction = iptables-multiport
backend   = systemd
maxretry  = 5
findtime  = 600
bantime   = 3600
# Увеличиваем время бана при повторных нарушениях
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 86400
EOF

# Защита от повторных нарушителей (recidive jail)
cat > /etc/fail2ban/jail.d/recidive.local << EOF
[recidive]
enabled   = true
filter    = recidive
logpath   = /var/log/fail2ban.log
maxretry  = 3
findtime  = 86400
bantime   = 604800
EOF

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2Ban настроен и запущен"
info "SSH jail: 5 попыток за 10 мин → бан 1 час (увеличивается при повторах)"
info "Recidive jail: повторные нарушители → бан на неделю"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 11: Автоматические обновления безопасности
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 11: Автоматические обновления"

AUTO_REBOOT_VALUE=$([ "$AUTO_REBOOT" == "y" ] && echo "true" || echo "false")
cat > /etc/apt/apt.conf.d/50unattended-upgrades << UPGEOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

// Автоматическое удаление неиспользуемых зависимостей
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Автоматическая перезагрузка если требуется (в 4:00)
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT_VALUE}";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";

// Не перезагружать, если пользователь залогинен
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
success "Автоматические обновления безопасности настроены"

# ═══════════════════════════════════════════════════════════════
# ЭТАП 12: Дополнительные улучшения безопасности
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 12: Дополнительные улучшения"

# --- Hardening sysctl ---
info "Настройка параметров ядра (sysctl hardening)..."
cat > /etc/sysctl.d/99-security-hardening.conf << EOF
# Защита от IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Игнорировать ICMP redirects (защита от MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# IP forwarding (1 = включён для VPN/Docker, 0 = отключён)
net.ipv4.ip_forward = $([ "$ENABLE_IP_FORWARD" == "y" ] && echo 1 || echo 0)

# Защита от SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Игнорировать ICMP broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Логирование подозрительных пакетов
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Запрет source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Запрет core dumps (могут содержать пароли/ключи из памяти)
fs.suid_dumpable = 0
EOF

sysctl --system > /dev/null 2>&1
success "Параметры ядра захардены"

# --- Отключение core dumps через limits ---
info "Отключение core dumps..."
if ! grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null; then
    echo "* hard core 0" >> /etc/security/limits.conf
fi
success "Core dumps отключены"

# --- Hardening /dev/shm ---
info "Защита shared memory (/dev/shm)..."
if ! grep -q "/dev/shm" /etc/fstab 2>/dev/null; then
    echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    mount -o remount /dev/shm 2>/dev/null || true
fi
success "/dev/shm защищён (noexec,nosuid,nodev)"

# --- Ограничение доступа к cron ---
info "Ограничение доступа к cron..."
echo "$NEW_USER" > /etc/cron.allow
chmod 600 /etc/cron.allow
success "Только $NEW_USER и root могут использовать cron"

# --- Ограничение su ---
info "Ограничение команды su..."
if ! grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null || grep -q "^#.*pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
    sed -i 's/^#\s*\(auth\s*required\s*pam_wheel.so\).*/\1 group=sudo/' /etc/pam.d/su
    success "Команда su ограничена группой sudo"
fi

# --- Защита важных файлов ---
info "Защита конфигурационных файлов..."
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null
chmod 640 /var/log/auth.log 2>/dev/null
success "Права на конфиги ужесточены"

# --- Отключение ненужных сервисов ---
info "Отключение ненужных сервисов..."
DISABLE_SERVICES=(
    avahi-daemon     # mDNS/DNS-SD, не нужен на VPS
    cups             # Система печати
    bluetooth        # Bluetooth
)

for svc in "${DISABLE_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc"
        systemctl disable "$svc"
        success "Отключён: $svc"
    fi
done

# ═══════════════════════════════════════════════════════════════
# ЭТАП 13: Установка Endlessh (SSH Tarpit)
# ═══════════════════════════════════════════════════════════════
if [[ "$INSTALL_ENDLESSH" == "y" ]]; then
    header "ЭТАП 13: Установка Endlessh (SSH Tarpit)"

    # Проверяем, доступен ли endlessh в репозиториях
    if apt-cache show endlessh &>/dev/null; then
        apt install -y endlessh
        success "Endlessh установлен из репозитория"

        ENDLESSH_BIN="/usr/bin/endlessh"
        mkdir -p /etc/systemd/system/endlessh.service.d
        cat > /etc/systemd/system/endlessh.service.d/override.conf << 'EOF'
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=false
InaccessiblePaths=
EOF
        success "Systemd override создан (порт 22, снятие sandbox-ограничений)"
    else
        # Собираем из исходников
        info "Endlessh не найден в репозиториях, собираем из исходников..."
        apt install -y build-essential git libc6-dev
        (
            cd /tmp
            git clone --depth 1 --branch 1.1 https://github.com/skeeto/endlessh.git
            cd endlessh
            make
            cp endlessh /usr/local/bin/
            chmod 755 /usr/local/bin/endlessh
        ) || { rm -rf /tmp/endlessh; error "Не удалось собрать endlessh"; exit 1; }
        rm -rf /tmp/endlessh
        ENDLESSH_BIN="/usr/local/bin/endlessh"

        cat > /etc/systemd/system/endlessh.service << 'EOF'
[Unit]
Description=Endlessh SSH Tarpit
Documentation=man:endlessh(1)
After=network.target

[Service]
ExecStart=/usr/local/bin/endlessh -v
AmbientCapabilities=CAP_NET_BIND_SERVICE
KillSignal=SIGTERM
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        success "Endlessh собран и установлен"
    fi

    # Конфигурация
    mkdir -p /etc/endlessh
    cat > /etc/endlessh/config << 'EOF'
# Порт — стандартный SSH, ловим ботов
Port 22
# Задержка между отправкой строк (в мс)
Delay 10000
# Максимум одновременных клиентов
MaxClients 4096
# Длина строки
MaxLineLength 32
# Время жизни клиента (в секундах, 0 = бесконечно)
MaxStartTime 0
# Логировать каждые N секунд
BindFamily 0
LogLevel 1
EOF

    setcap 'cap_net_bind_service=+ep' "$ENDLESSH_BIN"
    success "CAP_NET_BIND_SERVICE установлен для $ENDLESSH_BIN"

    systemctl daemon-reload
    systemctl enable endlessh
    systemctl start endlessh

    if systemctl is-active --quiet endlessh; then
        success "Endlessh запущен на порту 22 — боты будут страдать 😈"
    else
        warn "Endlessh не запустился. Проверьте: journalctl -u endlessh"
    fi
else
    info "Endlessh пропущен"
fi

# ═══════════════════════════════════════════════════════════════
# ЭТАП 14: Перезапуск SSH и проверка
# ═══════════════════════════════════════════════════════════════
header "ЭТАП 14: Применение настроек SSH"

warn "ВНИМАНИЕ: SSH будет перезапущен с новыми настройками!"
warn "Текущая сессия останется активной."
warn "Обязательно проверьте подключение в НОВОМ терминале перед закрытием этой сессии!"
echo ""

# Перезапускаем SSH
if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
    success "SSH-сервер перезапущен"

    # --- Проверка: слушает ли sshd новый порт ---
    sleep 2
    if ss -tlnp | grep -q ":${SSH_PORT}\b"; then
        success "SSH слушает на порту $SSH_PORT ✔"
    else
        error "SSH НЕ слушает на порту $SSH_PORT!"
        warn "Проверяем, на каком порту слушает sshd:"
        ss -tlnp | grep sshd || ss -tlnp | grep ssh
        warn "Возможно, нужно перезапустить вручную: systemctl restart ssh"
    fi

    # --- Проверка: iptables пропускает SSH-порт ---
    if iptables -L INPUT -n | grep -q "dpt:${SSH_PORT}"; then
        success "iptables: порт $SSH_PORT открыт ✔"
    else
        error "iptables: порт $SSH_PORT НЕ найден в правилах INPUT!"
        warn "Экстренное открытие порта..."
        iptables -I INPUT 5 -p tcp --dport "$SSH_PORT" -j ACCEPT
        warn "Порт $SSH_PORT открыт напрямую. Проверьте /etc/iptables/rules.v4"
    fi
else
    error "Не удалось перезапустить SSH! Проверьте вручную: systemctl status ssh"
    warn "Настройки применятся после ручного перезапуска."
fi

# ═══════════════════════════════════════════════════════════════
# ИТОГИ
# ═══════════════════════════════════════════════════════════════
header "НАСТРОЙКА ЗАВЕРШЕНА"

echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   ✔ Всё готово!                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${BOLD}Подключение к серверу:${NC}"
echo -e "  ${CYAN}ssh ${NEW_USER}@<IP_ADDRESS> -p ${SSH_PORT}${NC}"
echo ""

if [[ -z "$SSH_PUB_KEY" ]]; then
    echo -e "  ${YELLOW}⚠ Не забудьте добавить SSH-ключ:${NC}"
    echo -e "  ${CYAN}ssh-copy-id -p ${SSH_PORT} ${NEW_USER}@<IP_ADDRESS>${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠ После добавления ключа отключите пароль:${NC}"
    echo -e "  ${CYAN}sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/00-hardening.conf${NC}"
    echo -e "  ${CYAN}sudo systemctl restart ssh${NC}"
    echo ""
fi

echo -e "  ${BOLD}Что было сделано:${NC}"
echo -e "  ├─ ✔ Система обновлена"
echo -e "  ├─ ✔ Пользователь ${GREEN}$NEW_USER${NC} создан с sudo"
echo -e "  ├─ ✔ SSH порт: ${GREEN}$SSH_PORT${NC}, root запрещён, пароль: ${GREEN}$PASSWORD_AUTH${NC}"
echo -e "  ├─ ✔ SSH шифры: только curve25519/chacha20/ed25519"
echo -e "  ├─ ✔ IPv6: ${GREEN}$([ "$DISABLE_IPV6" == "y" ] && echo "отключён" || echo "включён (rules.v6 настроен)")${NC}"
echo -e "  ├─ ✔ IP forwarding: ${GREEN}$([ "$ENABLE_IP_FORWARD" == "y" ] && echo "включён" || echo "отключён")${NC}"
echo -e "  ├─ ✔ iptables Firewall + SSH rate limiting (4 conn/60s)"
echo -e "  ├─ ✔ Fail2Ban с прогрессивным баном + recidive jail"
echo -e "  ├─ ✔ Автообновления безопасности"
echo -e "  ├─ ✔ Sysctl hardening (anti-spoofing, SYN flood, source routing)"
echo -e "  ├─ ✔ Core dumps отключены, /dev/shm захардена"
echo -e "  ├─ ✔ Ограничение cron и su, защита конфигов"
echo -e "  ├─ ✔ Правовой баннер при подключении"
echo -e "  └─ ✔ Endlessh: ${GREEN}$([ "$INSTALL_ENDLESSH" == "y" ] && echo "tarpit на порту 22" || echo "пропущен")${NC}"
echo ""

echo -e "  ${BOLD}Лог:${NC} $LOG_FILE"
echo ""

echo -e "${RED}${BOLD}  ⚠ ВАЖНО: Не закрывайте эту сессию!${NC}"
echo -e "${RED}  Откройте НОВЫЙ терминал и проверьте подключение:${NC}"
echo -e "${CYAN}  ssh ${NEW_USER}@<IP_ADDRESS> -p ${SSH_PORT}${NC}"
echo ""
echo -e "  Если не подключается — исправьте из текущей сессии."
echo ""
