#!/usr/bin/env bash
#
# setup-asusctl-cardwire-debian.sh
#
# Instala asusctl + rog-control-center (compilados desde código fuente) y
# Cardwire (gestor de GPU vía eBPF LSM, sustituto de supergfxctl) en Debian
# y derivados (Debian 13/trixie o posterior, KDE Plasma, sesión Wayland).
#
# NO instala supergfxctl: ese proyecto está en desuso, Cardwire lo sustituye.
#
# Uso:
#   chmod +x setup-asusctl-cardwire-debian.sh
#   ./setup-asusctl-cardwire-debian.sh
#
# El script se detiene en el primer error (set -e) y pide confirmación
# antes de cada bloque grande. Revisa el contenido antes de ejecutarlo.

set -euo pipefail

ASUSCTL_VERSION="6.3.8"   # ajusta si quieres otra versión/tag concreto
BUILD_DIR="$HOME/Proyectos/asusctl-cardwire-build"

log()  { echo -e "\n\033[1;34m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

confirm() {
    read -r -p "$1 [s/N] " resp
    case "$resp" in
        [sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 0. Comprobaciones previas (bloqueantes)
# ---------------------------------------------------------------------------

log "Comprobando requisitos previos"

# 0.1 Sesión Wayland (Cardwire no soporta X11)
if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
    die "La sesión actual es '${XDG_SESSION_TYPE:-desconocida}', no Wayland. Cardwire solo soporta Wayland. Cambia a una sesión Wayland en el gestor de acceso (SDDM) e inténtalo de nuevo."
fi
echo "  - Sesión Wayland: OK"

# 0.2 Kernel >= 6.6 (mínimo exigido por asusctl)
KERNEL_VERSION=$(uname -r | cut -d- -f1)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
if [ "$KERNEL_MAJOR" -lt 6 ] || { [ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 6 ]; }; then
    die "Kernel detectado: $KERNEL_VERSION. asusctl exige kernel >= 6.6. En Debian 12/bookworm necesitarías un kernel de backports; en Debian 13/trixie (6.12) ya cumple."
fi
echo "  - Kernel $KERNEL_VERSION: OK (>= 6.6)"

# 0.3 CONFIG_BPF_LSM activo en el kernel en ejecución (requisito de Cardwire)
if [ -r /sys/kernel/security/lsm ]; then
    if ! grep -q "bpf" /sys/kernel/security/lsm; then
        warn "BPF LSM no aparece activo en /sys/kernel/security/lsm (contenido actual: $(cat /sys/kernel/security/lsm))."
        warn "En Debian/Ubuntu estándar debería venir activo de fábrica; si no lo está, hay que editar"
        warn "/etc/default/grub y añadir 'bpf' a GRUB_CMDLINE_LINUX_DEFAULT (sin quitar el resto de la lista lsm=...),"
        warn "luego 'sudo update-grub' y reiniciar. Este script NO toca GRUB automáticamente por seguridad."
        confirm "¿Continuar de todas formas? Cardwire no arrancará hasta resolver esto" || die "Abortado por el usuario."
    else
        echo "  - BPF LSM activo: OK"
    fi
else
    warn "No se pudo leer /sys/kernel/security/lsm, no se puede verificar BPF LSM automáticamente."
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1. Dependencias de compilación (apt)
# ---------------------------------------------------------------------------
#
# Lista corregida frente al primer borrador del proyecto:
#   - deduplicados libclang-dev, libxkbcommon-dev, libgtk-3-dev
#   - corregido "libexpat-dev" (no existe) -> libexpat1-dev
#   - añadido libdrm-dev (confirmado como dependencia real de asusctl)
#   - añadidas las dependencias propias de Cardwire (eBPF/Vulkan/Wayland)

log "Instalando dependencias de compilación (asusctl + Cardwire)"

sudo apt update

sudo apt install -y \
    build-essential git cmake pkg-config \
    curl checkinstall \
    libpci-dev libsysfs-dev libudev-dev libboost-dev \
    libgtk-3-dev libglib2.0-dev \
    libseat-dev libasound2-dev \
    libfreetype6-dev libfontconfig1-dev \
    libexpat1-dev \
    libxcb-composite0-dev libxcb1-dev libx11-dev libx11-xcb-dev \
    libssl-dev \
    libclang-dev llvm clang \
    libinput-dev libxkbcommon-dev libgbm-dev \
    libdrm-dev \
    libzstd-dev libpcre2-dev \
    libsystemd-dev \
    npm \
    libbpf-dev \
    libegl1-mesa-dev libvulkan-dev libglvnd-dev libwayland-dev

# ---------------------------------------------------------------------------
# 2. Rust: quitar el de los repos de Debian (si existe) e instalar rustup
# ---------------------------------------------------------------------------
#
# Confirmado en el packaging real de PikaOS para asusctl: usan rustup en vez
# del rustc/cargo de apt, precisamente para evitar builds rotos por versiones
# de Rust demasiado antiguas en los repos de Debian/Ubuntu.

log "Preparando Rust (rustup)"

if dpkg -l | grep -qE '^ii\s+(cargo|rustc)\s'; then
    warn "Se detectó cargo/rustc instalados vía apt. Se van a quitar para evitar conflictos con rustup."
    sudo apt remove -y cargo rustc || true
fi

if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup default stable

# ---------------------------------------------------------------------------
# 3. Compilar e instalar asusctl
# ---------------------------------------------------------------------------

log "Clonando y compilando asusctl v$ASUSCTL_VERSION"

if [ ! -d "asusctl" ]; then
    git clone --depth=1 https://gitlab.com/asus-linux/asusctl.git -b "$ASUSCTL_VERSION" asusctl
fi
cd asusctl

# Fix de permisos udev: las reglas de asusctl usan por defecto el grupo
# "wheel" (convención de Fedora/Arch). En Debian/Ubuntu el grupo de
# administración es "sudo", no "wheel". Sin este parche, asusd puede
# instalarse y arrancar "bien" pero sin permisos reales sobre el hardware.
if [ -f data/99-asusd.rules ] && grep -q 'GROUP="wheel"' data/99-asusd.rules; then
    log "Aplicando parche de grupo udev (wheel -> sudo)"
    sed -i 's/GROUP="wheel"/GROUP="sudo"/g' data/99-asusd.rules
fi

make
sudo make install
sudo systemctl daemon-reload
sudo systemctl enable --now asusd

cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Instalar Cardwire (paquete .deb oficial)
# ---------------------------------------------------------------------------

log "Instalando Cardwire desde el .deb oficial"

CARDWIRE_DEB_URL=$(curl -s https://api.github.com/repos/OpenGamingCollective/cardwire/releases/latest \
    | grep "browser_download_url.*\.deb" \
    | cut -d '"' -f 4 \
    | head -n1)

if [ -z "$CARDWIRE_DEB_URL" ]; then
    die "No se pudo obtener la URL del último .deb de Cardwire desde GitHub. Descárgalo manualmente desde https://github.com/OpenGamingCollective/cardwire/releases"
fi

curl -L -o cardwire.deb "$CARDWIRE_DEB_URL"
sudo apt install -y ./cardwire.deb
sudo systemctl enable --now cardwired

# ---------------------------------------------------------------------------
# 5. Conflicto conocido: power-profiles-daemon
# ---------------------------------------------------------------------------

if systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    warn "power-profiles-daemon está activo y puede chocar con asusd (perfiles de energía)."
    if confirm "¿Enmascarar power-profiles-daemon ahora?"; then
        sudo systemctl mask power-profiles-daemon
        sudo systemctl stop power-profiles-daemon || true
    fi
fi

# ---------------------------------------------------------------------------
# 6. Validación final
# ---------------------------------------------------------------------------

log "Validación final"

echo "--- asusd ---"
systemctl status asusd --no-pager || true
echo
echo "--- cardwired ---"
systemctl status cardwired --no-pager || true
echo
echo "--- asusctl -s (soporte detectado en el hardware) ---"
asusctl -s || warn "asusctl -s falló; revisa 'journalctl -u asusd' para más detalle."
echo
echo "--- cardwire list (GPUs detectadas) ---"
cardwire list || warn "cardwire list falló; revisa 'journalctl -u cardwired' para más detalle."

log "Instalación completada. Revisa la salida anterior antes de dar el proyecto por bueno."
