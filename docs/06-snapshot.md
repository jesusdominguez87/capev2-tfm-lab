# 06 — Crear el Snapshot Base

El snapshot es el elemento más crítico del laboratorio. Garantiza que cada muestra de malware se ejecute siempre sobre el mismo estado limpio y reproducible del sistema operativo. Sin un buen snapshot, el análisis puede ser ruidoso, inconsistente o directamente inútil.

---

## Por qué importa el estado de la VM en el momento del snapshot

El malware evasivo utiliza técnicas de **Time-Based Evasion**: comprueba si la CPU está al 100% de uso (síntoma de que se acaba de arrancar el SO o de que hay procesos de fondo corriendo), si el disco tiene actividad intensa o si el tiempo de respuesta del sistema es inusual. Si detecta estrés, se oculta.

Un snapshot tomado justo después de arrancar la VM o con el escritorio lleno de ventanas puede introducir falsos negativos en los análisis.

---

## Condiciones previas al snapshot

Antes de tomar la instantánea, el Guest debe estar en este estado:

- [ ] **Windows está completamente cargado** — el escritorio es visible y estable
- [ ] **El agente está corriendo** — verificado con `curl http://192.168.56.101:8000` desde Ubuntu
- [ ] **`is_user_admin: true`** — el agente tiene privilegios de Administrador
- [ ] **Windows Defender desactivado** — comprobado en Seguridad de Windows
- [ ] **UAC desactivado** — `EnableLUA = 0` en el Registro
- [ ] **No hay ventanas abiertas** — solo el fondo de pantalla visible
- [ ] **30-40 segundos de inactividad** — el uso de CPU debe haberse estabilizado en los valores mínimos del SO en reposo

> **Comprobación de CPU:** En el Administrador de tareas (Ctrl+Shift+Esc), la columna CPU de los procesos del sistema no debería superar el 5-10% agregado antes de tomar el snapshot.

---

## Pasos para tomar el snapshot

**Desde Ubuntu, con el Guest visible:**

1. En la ventana principal de VirtualBox, selecciona la VM de Windows 10.
2. Haz clic en el menú desplegable junto al botón **Mostrar** → **Instantáneas** (o usa el atajo `Ctrl+Shift+S`).
3. Haz clic en **Tomar** (botón de cámara).
4. Asigna el nombre: `CAPE_Limpio`
5. (Opcional) Añade una descripción: `Estado base para análisis CAPEv2. Agente activo, sin antivirus, UAC desactivado.`
6. Haz clic en **Aceptar**.

VirtualBox puede tardar entre 10 y 30 segundos en guardar el estado de la memoria RAM del Guest.

---

## Verificar el snapshot desde la línea de comandos

```bash
VBoxManage snapshot "Win10-Lab" list
```

Deberías ver:
```
Name: CAPE_Limpio (UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
   Description: Estado base para análisis CAPEv2...
```

---

## Actualizar el snapshot

Si necesitas modificar el Guest (instalar software, aplicar hardening adicional) y volver a congelar el estado:

1. Arranca el Guest desde el snapshot `CAPE_Limpio` existente.
2. Realiza los cambios.
3. Vuelve a preparar el estado (ventanas cerradas, CPU en reposo, agente activo).
4. Toma un nuevo snapshot con el mismo nombre `CAPE_Limpio` (o borra el anterior primero con `VBoxManage snapshot "Win10-Lab" delete "CAPE_Limpio"`).
5. Actualiza `virtualbox.conf` si el nombre del snapshot cambió.

---

## Después del snapshot: reiniciar los servicios de CAPE

Cada vez que modifiques el snapshot o la configuración de la VM, reinicia el núcleo de CAPE para que recargue el estado:

```bash
cd /opt/CAPEv2
/etc/poetry/bin/poetry run python cuckoo.py
```

Confirma que aparece `Loaded 1 machine.` en los logs.

---

Continúa con: [07 — Solución de problemas →](07-troubleshooting.md)
