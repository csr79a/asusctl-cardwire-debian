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

El script pide `sudo` en varios puntos (instalación de paquetes,
`checkinstall` para empaquetar e instalar asusctl, activación de servicios
systemd, y opcionalmente enmascarar `power-profiles-daemon`). No hace falta
ejecutar el script completo como root; usa `sudo` internamente solo donde es
necesario. Lo mismo aplica al script de desinstalación.

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
   `wheel`), compila con `make`, y lo empaqueta e instala con
   `checkinstall` (en vez de `sudo make install` a pelo) para que quede
   registrado en dpkg como el paquete `asusctl` — así se puede desinstalar
   limpiamente con `apt purge` más adelante. Activa el servicio `asusd`.
5. **Cardwire**: determina la última versión siguiendo la redirección
   pública de `https://github.com/.../releases/latest` (sin consultar la
   API de GitHub, para no toparse con su límite de 60 peticiones/hora sin
   autenticar — un problema real detectado al probar el script en una VM
   con IP compartida), descarga el `.deb` correspondiente, lo instala con
   `apt`, y activa el servicio `cardwired`.
6. **Conflicto conocido**: si `power-profiles-daemon` está activo, pregunta
   si quieres enmascararlo (puede chocar con la gestión de energía de
   `asusd`). Queda registrado en el estado si se hizo, para poder
   revertirlo luego.
7. **Validación final**: muestra el estado de ambos servicios y ejecuta
   `asusctl -s` y `cardwire list` para confirmar que detectan el hardware
   real, no solo que el proceso está "activo".
8. **Estado guardado**: al final deja un registro en
   `~/.local/state/asusctl-cardwire-debian/install.env` con qué cambios de
   sistema hizo (si quitó cargo/rustc de apt, si instaló rustup desde
   cero, si enmascaró power-profiles-daemon). El script de desinstalación
   lee ese archivo para revertir solo lo que él mismo cambió, no lo que ya
   tenías configurado de antes.

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
chmod +x uninstall-asusctl-cardwire-debian.sh
./uninstall-asusctl-cardwire-debian.sh
```

Qué hace, en orden:

1. Lee `~/.local/state/asusctl-cardwire-debian/install.env` (si existe) para
   saber exactamente qué cambió el instalador.
2. Desactiva y purga `cardwired`/`cardwire` vía `apt purge` (paquete `.deb`
   normal, sin trucos).
3. Desactiva y purga `asusd`/`asusctl` vía `apt purge` — funciona porque el
   instalador usó `checkinstall` en vez de `make install` a pelo, así que
   asusctl y rog-control-center quedan registrados como paquete dpkg real,
   no como archivos sueltos difíciles de rastrear. Si en algún momento se
   instaló a mano sin `checkinstall`, el script imprime las rutas típicas a
   revisar manualmente en vez de adivinar y borrar a ciegas.
4. Si el instalador había enmascarado `power-profiles-daemon`, lo
   desenmascara y reactiva.
5. Si el instalador instaló `rustup` porque no existía antes, **pregunta**
   si quieres quitarlo también (no lo hace por defecto, por si lo usas para
   otra cosa). Si había quitado `cargo`/`rustc` de apt, pregunta si
   quieres reinstalarlos.
6. Pregunta si quieres borrar también el directorio de compilación
   (`~/Proyectos/asusctl-cardwire-build`).
7. Verificación final: confirma que los binarios y los servicios ya no
   existen.

Las **dependencias de compilación** instaladas por apt en el paso 1 del
instalador (`libclang-dev`, `libbpf-dev`, `libgtk-3-dev`, etc.) no se
desinstalan automáticamente: son librerías de sistema que puede compartir
otro software, así que quitarlas a ciegas es más arriesgado que dejarlas.
El script las deja instaladas a propósito.

## 7. Notas / decisiones tomadas en este proyecto

- Se descartó supergfxctl deliberadamente: está en desuso, Cardwire cubre
  su función.
- Se prefirió el `.deb` oficial de Cardwire (releases de GitHub) sobre
  compilarlo desde fuente, por simplicidad — la opción de compilación
  manual queda documentada en la investigación previa por si hiciera falta.
- Cardwire exige Wayland; si en algún momento se necesita volver a X11,
  este proyecto no aplicaría y habría que revisar alternativas.
