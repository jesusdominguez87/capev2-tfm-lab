# 04 — Instalación de CAPEv2 en Ubuntu

CAPEv2 incluye un script de instalación automatizada (`cape2.sh`) que gestiona todas las dependencias: Python, Poetry, bases de datos, YARA, volatility, etc. El proceso tarda entre 15 y 30 minutos dependiendo de la conexión.

---

## Prerrequisitos en el Host

Asegúrate de que tienes instalado VirtualBox y que el usuario con el que trabajas pertenece al grupo `vboxusers`:

```bash
sudo usermod -aG vboxusers $USER
# Cierra sesión y vuelve a entrar para que el grupo se aplique
```

---

## Paso 1: Descargar el script de instalación

```bash
wget https://raw.githubusercontent.com/kevoreilly/CAPEv2/master/installer/cape2.sh
chmod +x cape2.sh
```

---

## Paso 2: Ejecutar el instalador

```bash
sudo ./cape2.sh base cape
```

El argumento `base` instala las dependencias del sistema operativo (MongoDB, PostgreSQL, tcpdump, etc.) y `cape` instala el propio CAPEv2.

**El script realizará automáticamente:**
- Instalación de dependencias del sistema (apt)
- Instalación de Poetry (gestor de entornos virtuales de Python)
- Clonado del repositorio de CAPEv2 en `/opt/CAPEv2`
- Instalación de todas las dependencias Python de CAPEv2
- Configuración de la base de datos PostgreSQL
- Registro de los servicios systemd (`cape`, `cape-processor`, `cape-web`)

---

## Paso 3: Ajustar permisos del directorio de CAPE

El script instala CAPE como root, pero los servicios deben correr con tu usuario para que VirtualBox (que corre como tu usuario) sea accesible:

```bash
sudo chown -R $USER:$USER /opt/CAPEv2
```

---

## Paso 4: Verificar la instalación

```bash
ls /opt/CAPEv2/
```

Deberías ver directorios como `agent/`, `conf/`, `web/`, `utils/`, `storage/`, etc.

Verifica que Poetry puede resolver el entorno:
```bash
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python --version
```

---

## Paso 5: Arrancar los servicios

### Opción A — Con systemd (producción)

Si el script registró los servicios correctamente:

```bash
systemctl start cape
systemctl start cape-processor
systemctl start cape-web

# Verificar estado
systemctl status cape
```

### Opción B — Manual con múltiples terminales (desarrollo/debug)

Esta es la opción más útil durante la fase de investigación porque muestra los logs en tiempo real. Abre **3 pestañas de terminal** y ejecuta un comando en cada una:

**Terminal 1 — Núcleo (controla VirtualBox):**
```bash
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python cuckoo.py
```
Mensaje de éxito: `[lib.cuckoo.core.machinery_manager] INFO: Loaded 1 machine.`  
Si aparece "0 machines", hay un problema de configuración en `virtualbox.conf`. Revisa [05 — Configuración](05-configuracion-cape.md).

**Terminal 2 — Procesador (genera los reportes):**
```bash
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python utils/process.py -p 1
```

**Terminal 3 — Servidor web:**
```bash
cd /opt/CAPEv2/web
/etc/poetry/bin/poetry run python manage.py runserver 0.0.0.0:8000
```

---

## Paso 6: Verificar la Web UI

Abre Firefox en Ubuntu y navega a:

```
http://localhost:8000
```

Deberías ver el panel de control de CAPEv2. Si la página no carga, comprueba que el proceso del Terminal 3 no muestra errores.

---

> **Nota sobre el usuario:** Si ves errores de permisos al arrancar `cuckoo.py`, asegúrate de que estás ejecutando como tu usuario normal (no root) y de que has ejecutado el `chown` del Paso 3.

---

Continúa con: [05 — Configurar los ficheros de CAPE →](05-configuracion-cape.md)
