# sys-quick-audit

Script bash de **auditoría rápida** del sistema: imprime por consola (o guarda en archivo) un resumen útil del equipo donde se ejecuta.

Solo lectura. No modifica configuración ni instala nada.

## Qué recoge

| Bloque | Contenido |
|--------|-----------|
| Identidad | Hostname, usuario, uptime, fecha |
| SO | Distro, kernel, virtualización |
| Hardware | CPU, GPU/PCI relevante |
| Memoria | RAM, swap, `/proc/meminfo` |
| Disco | `df`, `lsblk`, montajes |
| Red | Interfaces, IPs privadas, rutas, DNS |
| IP pública | Consulta HTTPS opcional |
| Puertos | `ss` escuchando y conexiones |
| Procesos | Top CPU/memoria, servicios systemd |
| Usuarios | Sesiones, last logins, shells |
| Seguridad | SELinux/AppArmor, firewall, SSH |
| Paquetes | Contadores pacman/apt/dnf |

## Uso

```bash
chmod +x sys-quick-audit.sh
./sys-quick-audit.sh
```

### Opciones

```bash
./sys-quick-audit.sh --save          # guarda sys-audit-<host>-<fecha>.txt
./sys-quick-audit.sh --no-public-ip  # sin consultar IP pública
./sys-quick-audit.sh -s --no-public-ip
./sys-quick-audit.sh --help
```

## Requisitos

- Bash
- Utilidades habituales de Linux (`ip`, `ss`, `free`, `ps`, `df`…)
- Opcional: `curl` o `wget` para la IP pública

Funciona mejor en Arch/Omarchy, Debian/Ubuntu y derivados systemd. Algunas secciones se omiten si el comando no existe o no hay permisos.

## Privacidad

El informe puede incluir IPs, usuarios, rutas y procesos. No lo compartas sin revisar. Con `--save`, el `.txt` queda en el directorio actual (está en `.gitignore`).

## Licencia

MIT — ver [LICENSE](LICENSE).
