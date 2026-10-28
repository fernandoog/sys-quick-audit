#!/usr/bin/env bash
# sys-quick-audit.sh — Auditoría rápida del sistema por consola
# Uso: ./sys-quick-audit.sh [--save] [--no-public-ip]
set -u

VERSION="1.0.0"
SAVE=0
NO_PUBLIC_IP=0
OUT=""

for arg in "$@"; do
  case "$arg" in
    --save|-s) SAVE=1 ;;
    --no-public-ip) NO_PUBLIC_IP=1 ;;
    --help|-h)
      cat <<EOF
sys-quick-audit v${VERSION}

Uso: $0 [opciones]

  --save, -s        Guardar informe en archivo .txt
  --no-public-ip    No consultar IP pública (sin red externa)
  --help, -h        Mostrar esta ayuda
EOF
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg (usa --help)" >&2
      exit 1
      ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

section() {
  printf '\n'
  printf '════════════════════════════════════════════════════════════\n'
  printf '  %s\n' "$1"
  printf '════════════════════════════════════════════════════════════\n'
}

kv() {
  printf '  %-22s %s\n' "$1:" "${2:-N/D}"
}

run_safe() {
  # Ejecuta comando; si falla, muestra mensaje corto
  if ! "$@" 2>/dev/null; then
    echo "  (no disponible)"
  fi
}

collect() {
  section "IDENTIDAD DEL EQUIPO"
  kv "Hostname" "$(hostname 2>/dev/null || echo N/D)"
  kv "FQDN" "$(hostname -f 2>/dev/null || echo N/D)"
  kv "Usuario actual" "$(whoami 2>/dev/null) (uid=$(id -u 2>/dev/null))"
  kv "Grupos" "$(id -nG 2>/dev/null | tr ' ' ', ')"
  kv "Shell" "${SHELL:-N/D}"
  kv "Home" "${HOME:-N/D}"
  kv "Fecha/hora" "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
  kv "Timezone" "$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || date +%Z)"
  kv "Uptime" "$(uptime -p 2>/dev/null || uptime 2>/dev/null)"
  kv "Boot" "$(who -b 2>/dev/null | awk '{print $3,$4}' || echo N/D)"

  section "SISTEMA OPERATIVO"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    kv "OS" "${PRETTY_NAME:-$NAME}"
    kv "ID" "${ID:-N/D} ${VERSION_ID:-}"
  elif have lsb_release; then
    kv "OS" "$(lsb_release -ds 2>/dev/null)"
  else
    kv "OS" "$(uname -s)"
  fi
  kv "Kernel" "$(uname -r)"
  kv "Arquitectura" "$(uname -m)"
  kv "Plataforma" "$(uname -s) $(uname -v | cut -c1-60)"
  if have systemd-detect-virt; then
    # sale con código ≠0 cuando no hay hipervisor; el texto sigue siendo "none"
    kv "Virtualización" "$(systemd-detect-virt 2>/dev/null || true)"
  elif have hostnamectl; then
    kv "Chassis/Virt" "$(hostnamectl 2>/dev/null | awk -F: '/Chassis|Virtualization/{gsub(/^ +/,"",$2); print $1"="$2}' | paste -sd ', ' -)"
  fi
  if [[ -f /proc/cmdline ]]; then
    kv "Cmdline" "$(tr -s ' ' </proc/cmdline | cut -c1-80)…"
  fi

  section "HARDWARE / CPU"
  if [[ -f /proc/cpuinfo ]]; then
    kv "Modelo CPU" "$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ //')"
    kv "Núcleos lógicos" "$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
    kv "Sockets" "$(grep -c '^physical id' /proc/cpuinfo 2>/dev/null | awk '{print ($1==0)?1:$1}')"
  fi
  if have lscpu; then
    echo
    lscpu 2>/dev/null | awk '
      /Architecture|CPU\(s\)|Thread|Core|Socket|Model name|MHz|Vendor|Virtualization|Cache/ {
        printf "  %s\n", $0
      }'
  fi
  if have lspci; then
    echo
    echo "  GPU / dispositivos PCI relevantes:"
    lspci 2>/dev/null | grep -Ei 'vga|3d|display|network|ethernet|wireless|audio' | sed 's/^/    /' || echo "    (ninguno listado)"
  fi

  section "MEMORIA"
  if have free; then
    free -h
    echo
    free -m | awk '
      /^Mem:/ {
        used=$3; total=$2; pct=(total>0)?(used*100/total):0
        printf "  Uso RAM: %d MiB / %d MiB (%.1f%%)\n", used, total, pct
      }
      /^Swap:/ {
        used=$3; total=$2; pct=(total>0)?(used*100/total):0
        printf "  Uso Swap: %d MiB / %d MiB (%.1f%%)\n", used, total, pct
      }'
  fi
  if [[ -f /proc/meminfo ]]; then
    echo
    awk '
      /^(MemTotal|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|AnonPages):/ {
        printf "  %-16s %s\n", $1, $2 " " $3
      }' /proc/meminfo
  fi

  section "ALMACENAMIENTO"
  echo "  Filesystems montados:"
  df -hT -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | sed 's/^/  /' || df -h | sed 's/^/  /'
  echo
  echo "  Inodos:"
  df -hi -x tmpfs -x devtmpfs 2>/dev/null | sed 's/^/  /' || true
  if have lsblk; then
    echo
    echo "  Dispositivos de bloque:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA,UUID 2>/dev/null | sed 's/^/  /'
  fi
  if have findmnt; then
    echo
    echo "  Puntos de montaje (resumen):"
    findmnt -D -t notmpfs,nodevtmpfs 2>/dev/null | head -40 | sed 's/^/  /' || true
  fi

  section "RED — INTERFACES E IPs PRIVADAS"
  if have ip; then
    echo "  Interfaces:"
    ip -br addr 2>/dev/null | sed 's/^/  /' || ip addr | sed 's/^/  /'
    echo
    echo "  Direcciones IPv4/IPv6:"
    ip -4 addr show scope global 2>/dev/null | awk '/inet /{printf "  %-12s %s\n", $NF, $2}'
    ip -6 addr show scope global 2>/dev/null | awk '/inet6 /{printf "  %-12s %s\n", $NF, $2}'
  elif have ifconfig; then
    ifconfig -a 2>/dev/null | sed 's/^/  /'
  fi
  echo
  echo "  Hostname → IP local (getent/host):"
  if have getent; then
    getent hosts "$(hostname)" 2>/dev/null | sed 's/^/  /' || true
  fi

  section "RED — RUTAS"
  if have ip; then
    echo "  Tabla de rutas IPv4:"
    ip -4 route show 2>/dev/null | sed 's/^/  /'
    echo
    echo "  Tabla de rutas IPv6:"
    ip -6 route show 2>/dev/null | head -20 | sed 's/^/  /'
    echo
    DEF=$(ip -4 route show default 2>/dev/null | head -1)
    kv "Gateway default" "${DEF:-N/D}"
  elif have route; then
    route -n 2>/dev/null | sed 's/^/  /'
  fi
  if have resolvectl; then
    echo
    echo "  DNS (resolvectl):"
    resolvectl status 2>/dev/null | awk '
      /DNS Server|DNS Domain|Current DNS|protocols/ {print "  "$0}
    ' | head -30
  elif [[ -f /etc/resolv.conf ]]; then
    echo
    echo "  DNS (/etc/resolv.conf):"
    grep -E '^(nameserver|search|domain)' /etc/resolv.conf 2>/dev/null | sed 's/^/  /'
  fi

  section "RED — IP PÚBLICA"
  if [[ "$NO_PUBLIC_IP" -eq 1 ]]; then
    echo "  (omitido: --no-public-ip)"
  else
    PUB=""
    for url in \
      "https://ifconfig.me/ip" \
      "https://api.ipify.org" \
      "https://icanhazip.com" \
      "https://checkip.amazonaws.com"; do
      if have curl; then
        PUB=$(curl -4 -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]') && [[ -n "$PUB" ]] && break
      elif have wget; then
        PUB=$(wget -qO- --timeout=4 "$url" 2>/dev/null | tr -d '[:space:]') && [[ -n "$PUB" ]] && break
      fi
    done
    kv "IP pública" "${PUB:-no disponible / sin salida a Internet}"
  fi

  section "RED — PUERTOS Y CONEXIONES"
  if have ss; then
    echo "  Escuchando (TCP/UDP):"
    ss -tulpn 2>/dev/null | sed 's/^/  /' || ss -tuln 2>/dev/null | sed 's/^/  /'
    echo
    echo "  Conexiones establecidas (top 25):"
    ss -tan state established 2>/dev/null | head -26 | sed 's/^/  /'
  elif have netstat; then
    netstat -tulpn 2>/dev/null | sed 's/^/  /' || netstat -tuln | sed 's/^/  /'
  fi

  section "PROCESOS PRINCIPALES"
  echo "  Top CPU (15):"
  ps aux --sort=-%cpu 2>/dev/null | head -16 | sed 's/^/  /' \
    || ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -16 | sed 's/^/  /'
  echo
  echo "  Top memoria (15):"
  ps aux --sort=-%mem 2>/dev/null | head -16 | sed 's/^/  /' \
    || ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -16 | sed 's/^/  /'
  echo
  kv "Procesos totales" "$(ps -e --no-headers 2>/dev/null | wc -l)"
  if have systemctl; then
    echo
    echo "  Servicios fallidos:"
    systemctl --failed --no-pager 2>/dev/null | sed 's/^/  /' || echo "  (ninguno / N/D)"
    echo
    echo "  Unidades activas (muestra):"
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -25 | sed 's/^/  /'
  fi

  section "USUARIOS Y SESIONES"
  echo "  Sesiones activas:"
  who 2>/dev/null | sed 's/^/  /' || w | sed 's/^/  /'
  echo
  echo "  Últimos logins:"
  last -n 10 2>/dev/null | sed 's/^/  /' || echo "  (comando last no disponible)"
  echo
  echo "  Usuarios con shell de login (/etc/passwd):"
  awk -F: '$7 !~ /(nologin|false)/ {printf "  %-16s uid=%-6s home=%s shell=%s\n", $1,$3,$6,$7}' /etc/passwd 2>/dev/null
  if [[ -r /etc/sudoers ]] || have sudo; then
    echo
    echo "  Miembros de grupos privilegiados:"
    for g in wheel sudo root adm; do
      if getent group "$g" >/dev/null 2>&1; then
        echo "  $g: $(getent group "$g" | cut -d: -f4)"
      fi
    done
  fi

  section "SEGURIDAD RÁPIDA"
  kv "SELinux" "$(getenforce 2>/dev/null || echo N/D o no instalado)"
  if have aa-status; then
    kv "AppArmor" "$(aa-status --enabled 2>/dev/null && echo enabled || echo disabled/unknown)"
  else
    kv "AppArmor" "$( [[ -d /sys/kernel/security/apparmor ]] && echo presente || echo N/D )"
  fi
  if have firewall-cmd; then
    kv "Firewalld" "$(firewall-cmd --state 2>/dev/null || echo N/D)"
  fi
  if have ufw; then
    kv "UFW" "$(ufw status 2>/dev/null | head -1)"
  fi
  if have nft; then
    echo
    echo "  nftables (reglas, resumen):"
    nft list ruleset 2>/dev/null | head -40 | sed 's/^/  /' || echo "  (sin permisos o vacío)"
  elif have iptables; then
    echo
    echo "  iptables -L (resumen):"
    iptables -L -n 2>/dev/null | head -30 | sed 's/^/  /' || echo "  (sin permisos)"
  fi
  echo
  echo "  SSH (si aplica):"
  if [[ -f /etc/ssh/sshd_config ]]; then
    grep -E '^(PermitRootLogin|PasswordAuthentication|Port|PubkeyAuthentication)' /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /' \
      || echo "  (valores por defecto / no legible)"
  else
    echo "  (sin sshd_config)"
  fi
  if [[ -d /home ]]; then
    echo
    echo "  Claves SSH autorizadas (conteo por usuario):"
    for d in /home/* /root; do
      [[ -d "$d" ]] || continue
      ak="$d/.ssh/authorized_keys"
      if [[ -r "$ak" ]]; then
        printf '  %-20s %s claves\n' "$(basename "$d")" "$(grep -cE '^(ssh-|ecdsa-|sk-)' "$ak" 2>/dev/null || echo 0)"
      fi
    done
  fi

  section "ACTUALIZACIONES / PAQUETES"
  if have pacman; then
    kv "Gestor" "pacman (Arch/Omarchy)"
    kv "Paquetes instalados" "$(pacman -Q 2>/dev/null | wc -l)"
    echo "  Actualizaciones pendientes (checkupdates si existe):"
    if have checkupdates; then
      UPD=$(checkupdates 2>/dev/null | wc -l)
      kv "Pendientes" "$UPD"
      checkupdates 2>/dev/null | head -15 | sed 's/^/  /'
    else
      echo "  (instala pacman-contrib para checkupdates)"
    fi
  elif have apt; then
    kv "Gestor" "apt"
    kv "Paquetes" "$(dpkg -l 2>/dev/null | grep -c '^ii')"
  elif have dnf; then
    kv "Gestor" "dnf"
  elif have zypper; then
    kv "Gestor" "zypper"
  fi
  if have flatpak; then
    kv "Flatpaks" "$(flatpak list --app 2>/dev/null | wc -l)"
  fi

  section "ENTORNO Y PATH"
  kv "PATH" "${PATH:-}"
  kv "LANG" "${LANG:-N/D}"
  kv "TERM" "${TERM:-N/D}"
  if have env; then
    echo
    echo "  Variables de entorno relevantes:"
    env 2>/dev/null | grep -Ei '^(PATH|HOME|USER|SHELL|LANG|DISPLAY|WAYLAND|XDG_|SSH_|HTTP|PROXY|EDITOR)' | sort | sed 's/^/  /'
  fi

  section "RESUMEN RÁPIDO"
  HOST=$(hostname 2>/dev/null)
  OS_LINE=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)
  MEM=$(free -h 2>/dev/null | awk '/^Mem:/{print $3"/"$2}')
  DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')
  PRIV=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -3 | paste -sd ', ' -)
  [[ "$NO_PUBLIC_IP" -eq 1 ]] && PUB_SUM="omitida" || PUB_SUM="${PUB:-N/D}"
  echo "  Host:     $HOST"
  echo "  OS:       $OS_LINE"
  echo "  Kernel:   $(uname -r)"
  echo "  RAM:      $MEM"
  echo "  Disco /:  $DISK"
  echo "  IP priv:  ${PRIV:-N/D}"
  echo "  IP pub:   $PUB_SUM"
  echo "  Fecha:    $(date -Iseconds 2>/dev/null || date)"
  echo
  echo "  Informe generado por sys-quick-audit v${VERSION}"
}

HEADER() {
  cat <<EOF
╔════════════════════════════════════════════════════════════╗
║           SYS-QUICK-AUDIT  v${VERSION}                        ║
║     Auditoría rápida de sistema (solo lectura)             ║
╚════════════════════════════════════════════════════════════╝
EOF
}

main() {
  if [[ "$SAVE" -eq 1 ]]; then
    TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
    HOST=$(hostname -s 2>/dev/null || echo host)
    OUT="sys-audit-${HOST}-${TS}.txt"
    {
      HEADER
      collect
    } | tee "$OUT"
    echo
    echo "Informe guardado en: $OUT"
  else
    HEADER
    collect
  fi
}

main
