# MANUAL — asusctl + Cardwire en Debian/derivados

## 1. Antes de empezar

Este manual acompaña a `setup-asusctl-cardwire-debian.sh`. Está pensado para
una instalación **limpia**, sin asusctl, supergfxctl ni Cardwire instalados
previamente.

Comprueba manualmente antes de ejecutar el script:

```bash
echo $XDG_SESSION_TYPE     # debe decir "wayland"
uname -r                   # debe ser >= 6.6
cat /sys/kernel/security/lsm   # debe incluir "bpf" en la lista
```

Si `/sys/kernel/security/lsm` no incluye `bpf`, hay que activarlo a mano
antes de continuar (ver sección 5).

## 2. Permisos

El script pide `sudo` en varios puntos (instalación de paquetes, `make
install`, activación de servicios systemd, y opcionalmente enmascarar
`power-profiles-daemon`). No hace falta ejecutar el script completo como
root; usa `sudo` internamente solo donde es necesario.

No modifica `/etc/default/grub` ni otros archivos de arranque de forma
automática — si hace falta tocar GRUB (ver sección 5), es un paso manual
deliberado, para no arriesgar el arranque del sistema sin supervisión.

## 3. Qué hace el script, paso a paso

1. **Comprobaciones previas**: sesión Wayland, versión de kernel, BPF LSM.
   Si alguna falla de forma bloqueante, el script se detiene sin tocar nada.
2. **Dependencias apt**: instala las librerías de compilación necesarias
   para asusctl y Cardwire (lista revisada para evitar duplicados y
   paquetes inexistentes).
3. **Rust**: si detecta `cargo`/`rustc` instalados vía `apt`, los quita
   (para evitar builds rotos por versiones antiguas) e instala Rust vía
   `rustup`.
4. **asusctl**: clona la versión indicada, aplica un parche al grupo de las
   reglas udev (`wheel` → `sudo`, ya que Debian/Ubuntu no usa el grupo
   `wheel`), compila e instala con `make` / `sudo make install`, y activa
   el servicio `asusd`.
5. **Cardwire**: descarga automáticamente el `.deb` más reciente desde las
   releases de GitHub del proyecto, lo instala con `apt`, y activa el
   servicio `cardwired`.
6. **Conflicto conocido**: si `power-profiles-daemon` está activo, pregunta
   si quieres enmascararlo (puede chocar con la gestión de energía de
   `asusd`).
7. **Validación final**: muestra el estado de ambos servicios y ejecuta
   `asusctl -s` y `cardwire list` para confirmar que detectan el hardware
   real, no solo que el proceso está "activo".

## 4. Verificación manual posterior

```bash
systemctl status asusd
systemctl status cardwired
asusctl -s
cardwire list
cardwire get
```

`cardwire list` debe mostrar tu iGPU y dGPU con sus IDs; `cardwire get`
debe mostrar el modo actual (por defecto, Cardwire arranca en modo
Hybrid).

## 5. Si `CONFIG_BPF_LSM` no está activo

Editar `/etc/default/grub` y añadir `bpf` a la lista existente de
`GRUB_CMDLINE_LINUX_DEFAULT` (sin borrar el resto):

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
```

Luego:

```bash
sudo update-grub
sudo reboot
```

Tras reiniciar, repite la comprobación de `/sys/kernel/security/lsm` y
vuelve a lanzar el script si se había detenido en ese punto.

## 6. Revertir / desinstalar

```bash
sudo systemctl disable --now cardwired
sudo apt purge cardwire

sudo systemctl disable --now asusd
sudo asusctl-uninstall 2>/dev/null || true   # si el Makefile de asusctl provee target de desinstalación
cd ~/Proyectos/asusctl-cardwire-build/asusctl && sudo make uninstall 2>/dev/null || echo "Revisa el Makefile de asusctl para el target correcto de desinstalación"
```

*(Pendiente de validar el target exacto de desinstalación de asusctl en
esta versión — anotar aquí una vez comprobado en la instalación de prueba.)*

## 7. Notas / decisiones tomadas en este proyecto

- Se descartó supergfxctl deliberadamente: está en desuso, Cardwire cubre
  su función.
- Se prefirió el `.deb` oficial de Cardwire (releases de GitHub) sobre
  compilarlo desde fuente, por simplicidad — la opción de compilación
  manual queda documentada en la investigación previa por si hiciera falta.
- Cardwire exige Wayland; si en algún momento se necesita volver a X11,
  este proyecto no aplicaría y habría que revisar alternativas.
