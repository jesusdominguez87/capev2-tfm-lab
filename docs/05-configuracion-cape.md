# 05 — Configuración de CAPEv2

Los ficheros de configuración se encuentran en `/opt/CAPEv2/conf/`. Son ficheros de texto en formato INI que puedes editar con cualquier editor de texto.

Las plantillas comentadas de ambos ficheros están disponibles en el directorio [`config/`](../config/) de este repositorio.

---

## virtualbox.conf — Configuración del hipervisor

Este fichero le indica a CAPE cómo interactuar con VirtualBox y qué máquina virtual usar.

```bash
nano /opt/CAPEv2/conf/virtualbox.conf
```

Ajusta los siguientes parámetros:

```ini
[virtualbox]
# Modo de control de VirtualBox
mode = gui

# Ruta al ejecutable VBoxManage
path = /usr/bin/VBoxManage

# Directorio donde VirtualBox guarda las VMs del usuario actual
# Cámbialo si tu usuario no es el por defecto
machines = Win10-Lab

[Win10-Lab]
# Nombre exacto de la VM tal como aparece en VirtualBox
label = Win10-Lab

# Sistema operativo del Guest
platform = windows

# IP estática que configuramos en el Guest
ip = 192.168.56.101

# Nombre exacto del snapshot base (respeta mayúsculas/minúsculas)
snapshot = CAPE_Limpio

# Interfaz de red del Guest (el adaptador Host-Only)
interface = vboxnet0

# Arquitectura del Guest
resultserver_ip = 192.168.56.1
resultserver_port = 2042
```

> **Atención:** El valor de `snapshot` debe coincidir **exactamente** (incluyendo mayúsculas, tildes y espacios) con el nombre que le diste al snapshot en VirtualBox. Un error aquí hará que CAPE no encuentre la máquina.

---

## cuckoo.conf — Configuración principal

Controla el comportamiento global de CAPE: dónde escucha el ResultServer, el directorio temporal para las muestras subidas, los timeouts, etc.

```bash
nano /opt/CAPEv2/conf/cuckoo.conf
```

Parámetros clave a revisar:

```ini
[cuckoo]
# IP en la que el ResultServer escucha (la interfaz vboxnet0 del Host)
resultserver_ip = 192.168.56.1
resultserver_port = 2042

# Tiempo máximo de análisis en segundos (ajusta según la muestra)
analysis_timeout = 120

# Directorio temporal para las muestras subidas vía Web UI
# MUY IMPORTANTE: cambia esto si /tmp está montado en RAM (ver abajo)
tmppath = /opt/CAPEv2/storage/tmp

[database]
# Cadena de conexión a PostgreSQL
connection = postgresql://cape:cape@localhost/cape
```

### Por qué cambiar `tmppath`

Por defecto, Linux monta `/tmp` en memoria RAM (`tmpfs`), con un límite habitual de 1-2 GB. Si subes una muestra grande o el sistema tiene poca RAM, CAPE fallará con un error de espacio insuficiente al intentar escribir el fichero temporal.

Mover `tmppath` a un directorio dentro de `/opt` (donde tienes el espacio del disco real) soluciona el problema:

```bash
# Crear el directorio y asignar permisos
mkdir -p /opt/CAPEv2/storage/tmp
chown -R $USER:$USER /opt/CAPEv2/storage
```

---

## Verificar la detección de la VM

Después de editar `virtualbox.conf`, arranca el núcleo de CAPE y comprueba que detecta la máquina:

```bash
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python cuckoo.py
```

Busca en la salida:
```
[lib.cuckoo.core.machinery_manager] INFO: Loaded 1 machine.
```

Si ves `0 machines`, revisa:
1. Que el nombre en `machines =` coincide con el nombre de la VM en VirtualBox
2. Que el nombre en `snapshot =` coincide exactamente con el nombre del snapshot
3. Que el usuario actual tiene acceso a VirtualBox (`groups` debe incluir `vboxusers`)

---

Continúa con: [06 — Crear el Snapshot base →](06-snapshot.md)
