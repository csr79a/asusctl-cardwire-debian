#!/usr/bin/env bash
#
# setup-asusctl-cardwire-debian.sh
#
# Instala asusctl + rog-control-center (compilados desde código fuente, vía
# checkinstall) y Cardwire (gestor de GPU vía eBPF LSM, sustituto de
# supergfxctl) en Debian y derivados (Debian 13/trixie o posterior, KDE
# Plasma, sesión Wayland).
#
# NO instala supergfxctl: ese proyecto está en desuso, Cardwire lo sustituye.
#
# Todo lo instalado queda registrado en dpkg (checkinstall para asusctl,
# .deb oficial para Cardwire), así que se puede revertir limpiamente con
# uninstall-asusctl-cardwire-debian.sh.
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
STATE_DIR="$HOME/.local/state/asusctl-cardwire-debian"
STATE_FILE="$STATE_DIR/install.env"

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

mkdir -p "$STATE_DIR"
: > "$STATE_FILE"   # el estado se reescribe en cada ejecución
state_set() { echo "$1=$2" >> "$STATE_FILE"; }

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
# Estas dependencias NO se desinstalan automáticamente en el revertido: son
# librerías del sistema que pueden compartirse con otro software, así que
# quitarlas a ciegas es más arriesgado que dejarlas. El script de
# desinstalación deja la lista impresa por si quieres limpiarlas a mano.

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

log "Preparando Rust (rustup)"

CARGO_RUSTC_REMOVED="no"
if dpkg -l | grep -qE '^ii\s+(cargo|rustc)\s'; then
    warn "Se detectó cargo/rustc instalados vía apt. Se van a quitar para evitar conflictos con rustup."
    sudo apt remove -y cargo rustc || true
    CARGO_RUSTC_REMOVED="si"
fi
state_set CARGO_RUSTC_REMOVED "$CARGO_RUSTC_REMOVED"

RUSTUP_INSTALLED_BY_SCRIPT="no"
if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    RUSTUP_INSTALLED_BY_SCRIPT="si"
fi
state_set RUSTUP_INSTALLED_BY_SCRIPT "$RUSTUP_INSTALLED_BY_SCRIPT"

# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup default stable

# ---------------------------------------------------------------------------
# 3. Compilar e instalar asusctl (vía checkinstall -> paquete dpkg real)
# ---------------------------------------------------------------------------

log "Clonando y compilando asusctl v$ASUSCTL_VERSION"

if [ ! -d "asusctl" ]; then
    git clone --depth=1 https://gitlab.com/asus-linux/asusctl.git -b "$ASUSCTL_VERSION" asusctl
fi
cd asusctl

# Fix de permisos udev: las reglas de asusctl usan por defecto el grupo
# "wheel" (convención de Fedora/Arch). En Debian/Ubuntu el grupo de
# administración es "sudo", no "wheel".
if [ -f data/99-asusd.rules ] && grep -q 'GROUP="wheel"' data/99-asusd.rules; then
    log "Aplicando parche de grupo udev (wheel -> sudo)"
    sed -i 's/GROUP="wheel"/GROUP="sudo"/g' data/99-asusd.rules
fi

make

log "Empaquetando asusctl con checkinstall (para que quede registrado en dpkg)"
sudo checkinstall \
    --pkgname=asusctl \
    --pkgversion="$ASUSCTL_VERSION" \
    --provides=asusctl \
    --nodoc \
    -y \
    make install

sudo systemctl daemon-reload
sudo systemctl enable asusd

# --- PARCHE: no abortar el script si asusd no arranca --------------------
# systemctl enable --now hacía las dos cosas en un solo comando; si el
# arranque fallaba (p.ej. sin hardware ASUS ROG real, como en una VM), ese
# comando devolvía código de error y set -e mataba el script aquí mismo,
# sin llegar nunca a instalar Cardwire. Separando "enable" de "start" y
# metiendo el start dentro de un "if", un fallo aquí solo genera un aviso
# y el script continúa con normalidad.
if ! sudo systemctl start asusd; then
    warn "asusd no ha arrancado (el proceso de control ha devuelto un error)."
    warn "Esto es ESPERABLE si no hay hardware ASUS ROG real (p.ej. en una VM):"
    warn "asusd necesita las interfaces ACPI/WMI reales del portátil para poder arrancar."
    warn "El servicio ha quedado 'enabled', así que arrancará solo en el hardware real."
    warn "Detalle: 'systemctl status asusd' / 'journalctl -xeu asusd.service'."
    warn "Continuando con la instalación de Cardwire de todas formas."
fi

cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Instalar Cardwire (paquete .deb oficial, sin pasar por api.github.com)
# ---------------------------------------------------------------------------
#
# api.github.com limita a 60 peticiones/hora sin autenticar, y en VMs/IPs
# compartidas ese cupo puede estar ya agotado por tráfico ajeno. En vez de
# consultar esa API, seguimos la redirección HTTP pública de
# /releases/latest (la misma que usa el navegador), que no pasa por la API
# JSON y por tanto no choca con ese límite.

log "Instalando Cardwire desde el .deb oficial"

CARDWIRE_TAG=$(curl -sI https://github.com/OpenGamingCollective/cardwire/releases/latest \
    | grep -i '^location:' \
    | sed 's#.*/tag/##' \
    | tr -d '\r\n')

if [ -z "$CARDWIRE_TAG" ]; then
    die "No se pudo determinar la última versión de Cardwire (falló la redirección de /releases/latest). Descarga el .deb manualmente desde https://github.com/OpenGamingCollective/cardwire/releases e instálalo con: sudo apt install ./cardwire_*.deb"
fi

CARDWIRE_VERSION="${CARDWIRE_TAG#v}"
CARDWIRE_DEB_URL="https://github.com/OpenGamingCollective/cardwire/releases/download/${CARDWIRE_TAG}/cardwire_${CARDWIRE_VERSION}-1_amd64.deb"

log "Última versión detectada: $CARDWIRE_TAG"

curl -fL -o cardwire.deb "$CARDWIRE_DEB_URL" || die "No se pudo descargar $CARDWIRE_DEB_URL — el nombre del asset puede haber cambiado. Revisa https://github.com/OpenGamingCollective/cardwire/releases/tag/${CARDWIRE_TAG} y descarga el .deb manualmente."

# apt hace la descarga/verificación de paquetes locales como el usuario sin
# privilegios _apt, que no siempre puede atravesar $HOME (permisos 700 por
# defecto en Debian). Copiamos a /tmp, que es legible/atravesable por todos,
# para evitar el aviso "Permiso denegado" de pkgAcquire.
CARDWIRE_DEB_TMP="/tmp/cardwire-install.deb"
cp cardwire.deb "$CARDWIRE_DEB_TMP"
chmod 644 "$CARDWIRE_DEB_TMP"
sudo apt install -y "$CARDWIRE_DEB_TMP"
rm -f "$CARDWIRE_DEB_TMP"
sudo systemctl enable cardwired

# --- PARCHE: mismo tratamiento que asusd, por consistencia y robustez ----
# En hardware real con GPU híbrida debería arrancar sin problema; esto solo
# evita que un fallo puntual de arranque bloquee la validación final.
if ! sudo systemctl start cardwired; then
    warn "cardwired no ha arrancado (el proceso de control ha devuelto un error)."
    warn "Puede deberse a falta de una GPU híbrida real que gestionar (p.ej. en una VM)."
    warn "El servicio ha quedado 'enabled'; arrancará solo en el hardware real."
    warn "Detalle: 'systemctl status cardwired' / 'journalctl -xeu cardwired.service'."
fi

# ---------------------------------------------------------------------------
# 5. Conflicto conocido: power-profiles-daemon
# ---------------------------------------------------------------------------

PPD_MASKED_BY_SCRIPT="no"
if systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    warn "power-profiles-daemon está activo y puede chocar con asusd (perfiles de energía)."
    if confirm "¿Enmascarar power-profiles-daemon ahora?"; then
        sudo systemctl mask power-profiles-daemon
        sudo systemctl stop power-profiles-daemon || true
        PPD_MASKED_BY_SCRIPT="si"
    fi
fi
state_set PPD_MASKED_BY_SCRIPT "$PPD_MASKED_BY_SCRIPT"

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
echo "--- asusctl info (versión y datos del sistema detectados) ---"
if systemctl is-active --quiet asusd; then
    # asusctl pasó de flags sueltos (-s, -v...) a subcomandos (info, aura,
    # profile...) en algún punto de su desarrollo; "-s" ya no existe y da
    # "Unrecognized argument" pase lo que pase con el hardware.
    asusctl info || warn "asusctl info falló pese a que asusd está activo; revisa 'asusctl --help' por si la CLI ha cambiado de nuevo. Detalle: 'journalctl -u asusd'."
else
    warn "asusd no está activo, se omite 'asusctl info' (no hay daemon con el que hablar; ver el aviso de la sección 3)."
fi
echo
echo "--- cardwire list (GPUs detectadas) ---"
cardwire list || warn "cardwire list falló; revisa 'journalctl -u cardwired' para más detalle."

log "Instalación completada. Estado guardado en $STATE_FILE para el revertido."
echo "Para desinstalar todo limpiamente, usa: ./uninstall-asusctl-cardwire-debian.sh"
