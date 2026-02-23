# VPS Initial Setup

Automated security hardening script for fresh Ubuntu/Debian VPS servers. Interactive setup with sensible defaults — run once, get a production-ready baseline.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/roman-kvasnikov/vps-initial-setup/master/vps-initial-setup.sh -o ./vps-initial-setup.sh && sudo bash ./vps-initial-setup.sh
```

## What It Does

**User & Access**
- Creates a non-root sudo user with SSH key authentication
- Disables root login, configures custom SSH port
- Restricts SSH ciphers to curve25519/chacha20/ed25519 only

**Firewall (nftables)**
- `inet` family — single ruleset for IPv4 + IPv6
- Default policy: drop all incoming, accept established
- SSH rate limiting: 4 new connections/min per IP (separate sets for v4/v6)
- Endlessh tarpit on port 22 (optional) — wastes bot resources

**Intrusion Prevention**
- Fail2Ban with nftables backend — progressive bans (1h → 24h)
- Recidive jail — repeat offenders banned for 1 week

**Kernel Hardening**
- Anti-spoofing (`rp_filter`), SYN flood protection (`tcp_syncookies`)
- ICMP redirect and source routing disabled
- Kernel pointer hiding (`kptr_restrict = 2`)
- Unprivileged BPF and perf restricted
- Symlink/hardlink/FIFO attack protection in sticky directories
- Core dumps disabled

**Maintenance**
- Unattended security upgrades with optional auto-reboot
- Shared memory hardened (`/dev/shm` noexec)
- Cron and `su` restricted, config file permissions tightened

## Requirements

- Ubuntu 22.04+ or Debian 11+
- Root access
- Fresh server (run before deploying services)

## After Running

The script shows a summary with open firewall ports and connection instructions. To open additional ports, edit `/etc/nftables.conf`:

```
tcp dport 443 accept
```

Then apply:

```bash
sudo nft -f /etc/nftables.conf
```
