# 07 — Solución de Problemas

Esta sección documenta los problemas reales encontrados durante el despliegue del laboratorio y sus soluciones. Están ordenados por la fase en la que suelen aparecer.

---

## Problema 1: CAPE no detecta la máquina virtual ("Loaded 0 machines")

**Síntoma:**  
Al arrancar `cuckoo.py`, el log muestra:
```
[lib.cuckoo.core.machinery_manager] INFO: Loaded 0 machines.
```
Los análisis enviados quedan en estado `pending` indefinidamente y nunca pasan a `running`.

**Causa más común:**  
CAPE está ejecutándose como un usuario diferente al que tiene VirtualBox registrado, o hay un error en los nombres de `virtualbox.conf`.

**Solución:**

1. Asegúrate de ejecutar CAPE con tu usuario normal (no root):
   ```bash
   # MAL: sudo /etc/poetry/bin/poetry run python cuckoo.py
   # BIEN:
   cd /opt/CAPEv2
   /etc/poetry/bin/poetry run python cuckoo.py
   ```

2. Verifica que el usuario tiene acceso a VirtualBox:
   ```bash
   groups $USER  # Debe incluir "vboxusers"
   VBoxManage list vms  # Debe listar tu VM de Windows 10
   ```

3. Comprueba que los nombres en `virtualbox.conf` coinciden exactamente con los de VirtualBox:
   ```bash
   VBoxManage list vms
   # Compara la salida con el valor de "label = " en virtualbox.conf
   
   VBoxManage snapshot "Win10-Lab" list
   # Compara la salida con el valor de "snapshot = " en virtualbox.conf
   ```

4. Ajusta los permisos del directorio de CAPE:
   ```bash
   sudo chown -R $USER:$USER /opt/CAPEv2
   ```

---

## Problema 2: Error de espacio en el directorio temporal al subir muestras

**Síntoma:**  
Al intentar subir un fichero a la Web UI, CAPE devuelve un error como:
```
[ERROR] Not enough free disk space available for the temporary directory.
Temp folder from cuckoo.conf: /tmp
```

**Causa:**  
En Ubuntu, `/tmp` se monta habitualmente como `tmpfs` (en RAM), con un límite de 1-2 GB. Si la RAM está ocupada o la muestra es grande, no hay espacio suficiente.

**Solución:**

1. Edita `/opt/CAPEv2/conf/cuckoo.conf` y localiza la variable `tmppath`.
2. Cambia su valor:
   ```ini
   tmppath = /opt/CAPEv2/storage/tmp
   ```
3. Crea el directorio y asigna permisos:
   ```bash
   mkdir -p /opt/CAPEv2/storage/tmp
   sudo chown -R $USER:$USER /opt/CAPEv2/storage
   ```
4. Reinicia los servicios de CAPE.

---

## Problema 3: `is_user_admin: false` en la respuesta del agente {#is_user_admin-false}

**Síntoma:**  
Al verificar el agente desde Ubuntu:
```bash
curl http://192.168.56.101:8000
```
La respuesta incluye `"is_user_admin": false`.

**Por qué importa:**  
El agente necesita privilegios de Administrador para inyectar la DLL de monitorización en el proceso del malware. Sin ellos, el API Hooking falla y el análisis de comportamiento queda vacío.

**Causa:**  
El UAC de Windows está activo e impide que el agente, aunque esté en la carpeta de inicio, obtenga privilegios elevados automáticamente.

**Solución:**

1. En el Guest Windows 10, abre el **Símbolo del sistema como Administrador** (clic derecho en el menú Inicio).
2. Ejecuta el siguiente comando para desactivar completamente el UAC:
   ```cmd
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f
   ```
3. Deberías ver: `La operación se completó correctamente.`
4. **Reinicia la VM** — sin reinicio, el cambio no se aplica.
5. Después del reinicio, verifica de nuevo:
   ```bash
   curl http://192.168.56.101:8000
   ```
   Ahora debería aparecer `"is_user_admin": true`.

> **Nota:** Después de desactivar el UAC y antes de tomar el snapshot, asegúrate de que el escritorio está limpio y que esperaste 30-40 segundos para que la CPU se estabilice (ver [06 — Snapshot](06-snapshot.md)).

---

## Problema 4: El agente no arranca automáticamente al iniciar Windows

**Síntoma:**  
Después de restaurar el snapshot, `curl http://192.168.56.101:8000` no responde o da `Connection refused`.

**Causas posibles y soluciones:**

**a) El fichero está en la carpeta de inicio incorrecta:**  
Hay dos carpetas de inicio en Windows — una por usuario y una del sistema. Asegúrate de usar la del usuario actual:
```
shell:startup  →  C:\Users\<tu_usuario>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```
(No uses `shell:common startup`, que requiere permisos adicionales.)

**b) La extensión del fichero es `.py` en lugar de `.pyw`:**  
Con `.py`, Windows abre una ventana de terminal negra que puede cerrarse o interferir. Con `.pyw`, el script corre en segundo plano silenciosamente.

**c) Python no está en el PATH:**  
Verifica en una CMD de Windows:
```cmd
python --version
```
Si da error, reinstala Python marcando **"Add Python 3.8 to PATH"** durante la instalación.

---

## Problema 5: El análisis queda en "pending" aunque se detecte la máquina

**Síntoma:**  
`cuckoo.py` dice `Loaded 1 machine.` pero los análisis siguen sin ejecutarse.

**Verificaciones:**

```bash
# ¿Está el procesador corriendo?
/etc/poetry/bin/poetry run python utils/process.py -p 1

# ¿El agente del Guest responde?
curl http://192.168.56.101:8000

# ¿Hay errores en la BD?
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python utils/db_migration.py
```

**Causa frecuente:** El procesador no está corriendo. CAPE necesita los tres procesos activos simultáneamente: el núcleo, el procesador y el servidor web.

---

## Problema 6: El agente no responde tras reiniciar el host (`vboxnet0` en estado `DOWN`)

**Síntoma:**
El agente funcionaba correctamente en la sesión anterior, pero tras apagar/reiniciar el host Ubuntu:

```bash
curl http://192.168.56.101:8000
curl: (28) Failed to connect to 192.168.56.101 port 8000 after 134048 ms: Connection timed out
```

A diferencia del Problema 4 (`Connection refused`, inmediato), aquí la conexión hace **timeout** — los paquetes no llegan a ningún sitio, no es que el agente rechace la conexión.

**Causa:**
La interfaz `vboxnet0` (red Host-Only usada por el ResultServer) se queda en estado `DOWN` a nivel de enlace tras reiniciar el host, aunque conserve la IP asignada. Es un comportamiento conocido de VirtualBox en Linux: si la VM que usa la red host-only no está corriendo en el momento en que se recrea la interfaz, esta puede quedar administrativamente caída.

Compruébalo con:

```bash
ip addr show vboxnet0
```

Si ves `state DOWN` en la primera línea (aunque la IP `192.168.56.1/24` aparezca correctamente listada más abajo), este es el problema:

```bash
4: vboxnet0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 0a:00:27:00:00:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.56.1/24 scope global vboxnet0
```

**Solución inmediata:**

```bash
sudo ip link set vboxnet0 up
```

Verifica que el estado cambia a `UP` o `UNKNOWN` y repite el `curl`.

Puedes usar el script [`start-cape-manual.sh`](../scripts/start-cape-manual.sh) que tiene comprobaciones previas y levanta el estado de la interfaz le asigna ip si no la tiene ya.

---

Continúa con: [08 — Análisis con PAFish →](08-analisis-pafish.md)
