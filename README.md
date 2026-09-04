# asusctl-cardwire-debian

Script de instalación de **asusctl** + **rog-control-center** (compilados desde
código fuente) y **Cardwire** (gestor de GPU vía eBPF LSM) en Debian y
distribuciones derivadas, orientado a KDE Plasma con sesión **Wayland**.

**No instala supergfxctl.** Ese proyecto está en desuso; Cardwire cubre la
misma función (conmutación/gestión de GPU híbrida).

## Qué instala

- **asusctl** y **rog-control-center**: compilados desde el repo oficial
  (`gitlab.com/asus-linux/asusctl`), vía Rust/rustup.
- **Cardwire**: paquete `.deb` oficial más reciente, descargado automáticamente
  desde las releases de GitHub (`OpenGamingCollective/cardwire`).

## Requisitos

- Debian 13 (trixie) o derivado reciente — kernel 6.12 por defecto.
- Sesión de escritorio **Wayland** (Cardwire no soporta X11).
- `CONFIG_BPF_LSM` activo en el kernel (viene de fábrica en Debian/Ubuntu
  estándar; el script lo comprueba).
- Kernel >= 6.6 (mínimo exigido por asusctl).

## Uso

```bash
chmod +x setup-asusctl-cardwire-debian.sh
./setup-asusctl-cardwire-debian.sh
```

El script se detiene en el primer error y pide confirmación antes de pasos
sensibles (como enmascarar `power-profiles-daemon`). Revisa el contenido
antes de ejecutarlo, especialmente si vas a lanzarlo en un equipo que no sea
de pruebas.

Ver [MANUAL.md](MANUAL.md) para el detalle de cada paso, permisos necesarios
y cómo revertir la instalación.

## Estado

Proyecto en desarrollo/revisión — pendiente de validar en una instalación
limpia de Debian 13 con KDE Plasma antes de darlo por definitivo.
