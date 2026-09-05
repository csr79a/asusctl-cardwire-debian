# asusctl-cardwire-debian

Script de instalación de **asusctl** + **rog-control-center** (compilados desde
código fuente) y **Cardwire** (gestor de GPU vía eBPF LSM) en Debian y
distribuciones derivadas, orientado a KDE Plasma con sesión **Wayland**.

**No instala supergfxctl.** Ese proyecto está en desuso; Cardwire cubre la
misma función (conmutación/gestión de GPU híbrida).

## Qué instala

- **asusctl** y **rog-control-center**: compilados desde el repo activo en
  GitHub (`OpenGamingCollective/asusctl`), vía Rust/rustup, empaquetados con
  `checkinstall` para que queden registrados en dpkg (y se puedan
  desinstalar limpiamente). Se detecta y compila automáticamente la **última
  versión publicada**, sin número fijo en el script.

  > Nota: el repo histórico `gitlab.com/asus-linux/asusctl` está **archivado
  > (solo lectura)** y su última tag se quedó congelada en 6.3.8. El
  > desarrollo activo continúa en el fork de GitHub, de donde clona este
  > script.

- **Cardwire**: paquete `.deb` oficial más reciente, descargado
  automáticamente desde las releases de GitHub
  (`OpenGamingCollective/cardwire`) siguiendo la redirección pública de
  `/releases/latest` (sin pasar por `api.github.com`, para no toparse con
  su límite de 60 peticiones/hora sin autenticar).

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

El script se detiene en el primer error real y pide confirmación antes de
pasos sensibles (como enmascarar `power-profiles-daemon`). Si `asusd` o
`cardwired` no logran arrancar por falta de hardware real (p. ej. en una VM),
el script **avisa y continúa** en vez de abortar — no es un fallo del
script, es esperado sin un portátil ASUS ROG real de por medio. Revisa el
contenido antes de ejecutarlo, especialmente si vas a lanzarlo en un equipo
que no sea de pruebas. Guarda un registro de lo que cambió en
`~/.local/state/asusctl-cardwire-debian/install.env`, que usa el script de
desinstalación para revertir solo lo que él mismo tocó.

## Desinstalar / revertir

```bash
chmod +x uninstall-asusctl-cardwire-debian.sh
./uninstall-asusctl-cardwire-debian.sh
```

Quita Cardwire y asusctl/rog-control-center (ambos vía `apt purge`, ya que
quedan registrados en dpkg), y revierte los cambios de sistema conocidos
(desenmascarar `power-profiles-daemon` si el instalador lo enmascaró,
opción de quitar rustup si lo instaló el propio script). Las dependencias
de compilación instaladas por apt no se tocan, por ser librerías que puede
compartir otro software.

Ver [MANUAL.md](MANUAL.md) para el detalle de cada paso, permisos necesarios
y cómo revertir la instalación.

## Estado

Validado en una VM de Debian 13 con KDE Plasma: el flujo completo (asusctl,
rog-control-center, Cardwire) se instala de principio a fin sin
intervención manual. `asusd` no puede arrancar sin hardware ASUS ROG real
(esperado en VM); Cardwire sí arranca y detecta GPUs (incluida la virtual de
la VM). Pendiente de validar en hardware ASUS ROG real.
