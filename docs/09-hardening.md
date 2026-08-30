# 09 — Hardening Anti-VM: Implementacion y Resultados

> Este documento parte de los resultados del analisis baseline (doc `08`) y recoge las medidas de hardening aplicadas sobre el entorno VirtualBox + Windows 10, junto con los resultados del analisis post-hardening con PAFish. Se realizo un unico ciclo completo de hardening para concentrar el esfuerzo en el tiempo disponible.

---

## Vectores de deteccion identificados en el baseline

El analisis baseline (ID 1, 2026-08-28) revelo que PAFish ejecuto con plena visibilidad por parte de CAPE (238 s, Malscore 9.0, 28/36 firmas). El objetivo del hardening no es que CAPE vea mas comportamiento — es que **PAFish no pueda identificar el entorno como una sandbox** y, por tanto, no active sus rutinas de evasion.

Los vectores prioritarios, en orden de impacto sobre el numero de firmas:

| Prioridad | Vector                          | Firmas baseline asociadas                                    |
|-----------|---------------------------------|--------------------------------------------------------------|
| 1 (critico) | VirtualBox Guest Additions    | `antivm_vbox_files` (17 artefactos), `antivm_vbox_window`, `antivm_vbox_provname` |
| 2 (alto)  | DMI/BIOS emulado                | `antivm_wmi`, `recon_fingerprint`                            |
| 3 (alto)  | Identificadores de disco        | `antivm_generic_disk`, `antivm_generic_scsi`, `physical_drive_access` |
| 4 (medio) | Direccion MAC Oracle            | `antivm_network_adapters`                                    |
| 5 (medio) | Claves de registro residuales   | `recon_fingerprint`                                          |

---

## Medidas de hardening aplicadas

El hardening se aplico en dos planos: el Host Ubuntu via `VBoxManage` (con la VM apagada) y el Guest Windows 10 via PowerShell como Administrador. Los scripts completos se encuentran en `scripts/hardening-host.sh` y `scripts/hardening-guest.ps1`.

### Plano Host (VBoxManage)

**Paso 1 — DMI/BIOS spoofing**
Neutraliza la emulacion de hardware que VirtualBox expone via tablas SMBIOS/DMI, leidas por WMI (`Win32_BIOS`, `Win32_ComputerSystem`) y por acceso directo al registro (`HKLM\HARDWARE\DESCRIPTION\System`).

```bash
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor"    "LENOVO"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct"   "20SL001DGE"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion"   "ThinkBook 15 G2 ITL"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVendor"      "American Megatrends Inc."
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVersion"     "F.26"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseDate" "04/15/2022"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor"   "LENOVO"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardVendor"     "LENOVO"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardProduct"    "LNVNB161216"
```

**Paso 2 — Disco spoofing**
Reemplaza el string `VBOX HARDDISK` en el firmware ATA/SCSI emulado, visible via IOCTL y via `Win32_DiskDrive`.

```bash
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber"      "Samsung SSD 870 EVO 500GB"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" "SVT01B6Q"
VBoxManage setextradata "Win10-Lab" "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber"     "S5YENX0T123456A"
```

**Paso 3 — MAC address**
Sustituye el prefijo Oracle (`08:00:27`) por un OUI de Intel, eliminando la deteccion via `GetAdaptersInfo`.

```bash
VBoxManage modifyvm "Win10-Lab" --macaddress1 "8C8D28$(openssl rand -hex 3 | tr a-z A-Z)"
```

**Paso 4 — CPUID**
Suprime la hoja de firma del hipervisor (`EAX=0x40000000`, que devuelve `VBoxVBoxVBox`) y desactiva la paravirtualizacion.

```bash
VBoxManage setextradata "Win10-Lab" "VBoxInternal/CPUM/SuppressHypervisorCpuIdLeaf" 1
VBoxManage modifyvm "Win10-Lab" --paravirtprovider none
VBoxManage modifyvm "Win10-Lab" --cpu-profile "host"
```

### Plano Guest (PowerShell + spoof_bios.bat)

**Paso 1 — Desinstalacion de Guest Additions**
Via `Win32_Product.Uninstall()`. Elimina simultaneamente los 17 artefactos de `antivm_vbox_files`, el proceso `VBoxTray.exe` responsable de `antivm_vbox_window`, y la DLL `VBoxMRXNP.dll` responsable de `antivm_vbox_provname`.

**Paso 2 — Limpieza de ficheros residuales**
Eliminacion de drivers, DLLs y ejecutables restantes en `System32`, `SysWOW64` y `drivers\`. `VBoxWddm.sys` no pudo eliminarse en ningun ciclo de reinicio — el kernel lo retiene de forma persistente, lo que constituye una limitacion real del entorno documentada en la seccion de limitaciones.

**Paso 3 — Eliminacion de servicios y registro**
Deshabilitacion (`Start=4`) y borrado de los servicios `VBoxGuest`, `VBoxMouse`, `VBoxService`, `VBoxSF`, `VBoxVideo`, `VBoxNetAdp`, `VBoxNetLwf`. Limpieza de claves ACPI (`DSDT\VBOX__`, `FADT\VBOX__`, `RSDT\VBOX__`) y eliminacion de la entrada `VBoxSF` de `NetworkProvider\Order`.

**spoof_bios.bat (startup)**
Script de autoarranque que falsifica `SystemBiosVersion` en `HKLM\HARDWARE\DESCRIPTION\System`, complementando el spoofing DMI/BIOS del hipervisor con valores coherentes con el perfil LENOVO configurado en el host:

```bat
@echo off
reg add "HKLM\HARDWARE\DESCRIPTION\System" /v SystemBiosVersion /t REG_MULTI_SZ /d "LENOVO - F.26" /f
reg add "HKLM\HARDWARE\DESCRIPTION\System" /v VideoBiosVersion /t REG_MULTI_SZ /d "Intel(R) UHD Graphics Controller" /f
```

**Simulacion de actividad humana (CAPE auxiliary.conf)**

```ini
[human]
enabled = yes
```

Habilita el modulo de simulacion de movimiento de raton e interaccion con ventanas durante el analisis, mitigando detecciones basadas en ausencia de actividad de usuario.

---

## Resultados del analisis post-hardening

El reporte completo esta en [`reports/post-hardening/2_report_pafish64_post-hardening.json`](../reports/post-hardening/2_report_pafish64_post-hardening.json).

### Metadatos del analisis

| Campo               | Valor                  |
|---------------------|------------------------|
| ID de analisis      | 2                      |
| Fecha               | 2026-08-30             |
| Maquina             | Win10-Lab (VirtualBox) |
| Snapshot            | CAPE_Hardened          |

### Metadatos de la muestra

Identica al baseline: `pafish64.exe`, MD5 `4b6229d1b32d7346cf4c8312a8bc7925`.

### Resultados de extraccion

| Metrica               | Baseline (ID 1) | Post-hardening (ID 2) | Variacion      |
|-----------------------|-----------------|----------------------|----------------|
| **Malscore**          | 9.0 / 10        | 9.0 / 10             | Sin cambio     |
| **Malstatus**         | Malicious       | Malicious            | Sin cambio     |
| **Procesos capturados** | 1             | 1                    | Sin cambio     |

> **Nota sobre el Malscore:** el Malscore de CAPE no mide si el entorno es detectado como VM — mide la peligrosidad del comportamiento capturado. PAFish ejecuta siempre las mismas tecnicas independientemente de si detecta o no la sandbox, por lo que el Malscore es estable entre analisis. La metrica relevante para el TFM es el conjunto de firmas `anti-vm` disparadas, no el Malscore.

---

## Comparativa de firmas: baseline vs post-hardening

### Firmas neutralizadas

Firmas presentes en el baseline que **no se dispararon** en el analisis post-hardening:

| Firma                  | Descripcion                                          | Medida que la neutralizo       |
|------------------------|------------------------------------------------------|--------------------------------|
| `antivm_generic_disk`  | Deteccion de disco virtual via WMI/IOCTL             | Disco spoofing (host)          |
| `antivm_generic_scsi`  | Identificador SCSI del disco virtual                 | Disco spoofing (host)          |
| `antivm_network_adapters` | Prefijo MAC `08:00:27` de Oracle/VirtualBox       | MAC address cambiada (host)    |
| `physical_drive_access`| Acceso directo al disco fisico                       | Disco spoofing (host)          |
| `binary_yara`          | Reglas YARA sobre el binario                         | Entorno modificado             |
| `procmem_yara`         | Reglas YARA sobre volcados de proceso                | Entorno modificado             |

**6 firmas neutralizadas**, de las cuales 4 son directamente `anti-vm` y 2 son detecciones estaticas que desaparecieron al cambiar el contexto de ejecucion.

### Firmas persistentes

Firmas presentes en ambos analisis. Se dividen en dos grupos segun su naturaleza:

**Inherentes a PAFish / inamovibles sin romper CAPE:**

| Firma                  | Motivo de persistencia                                                    |
|------------------------|---------------------------------------------------------------------------|
| `antisandbox_unhook`   | PAFish detecta los hooks WMI del agente de CAPE. Inherente a la instrumentacion; eliminarlo requeriria desactivar la monitorizacion. |
| `antivm_wmi`           | PAFish realiza consultas WMI a `Win32_ComputerSystem`/`Win32_BIOS`. La firma se dispara por el patron de llamadas, no por el valor devuelto. |
| `mouse_movement_detect`| Deteccion de movimiento de raton. La simulacion humana de CAPE no es suficiente para engañar a PAFish en esta comprobacion. |
| `recon_fingerprint`    | Lectura de `SystemBiosDate`. La clave existe aunque su valor sea correcto. |
| `amsi_enumeration`     | Enumeracion de proveedores AMSI; comportamiento de PAFish independiente del entorno. |
| `privilege_elevation_check` | Comprobacion de privilegios; inamovible.                            |

**Artefactos de Guest Additions residuales (parcialmente eliminados):**

| Firma                  | Causa                                                                     |
|------------------------|---------------------------------------------------------------------------|
| `antivm_vbox_files`    | Ficheros residuales detectados: `vboxoglpackspu.dll`, `vboxoglpassthroughspu.dll`, `vboxoglfeedbackspu.dll`, `VBoxSF.sys`, `VBoxControl.exe`, `vboxservice.exe`, `vboxtray.exe`, `VBoxGuest.sys`, `VBoxMouse.sys`, `VBoxVideo.sys`. |
| `antivm_vbox_window`   | `VBoxTrayToolWndClass` aun activa durante el analisis.                   |
| `antivm_vbox_provname` | `VBoxMRXNP.dll` o entrada de NetworkProvider aun presente.               |
| `packer_entropy`       | Alta entropia del binario; caracteristica propia de PAFish.               |
| `pe_tls_callbacks` / `antianalysis_tls_section` | Estructura del binario; independiente del entorno. |
| `enumerates_running_processes` | Comportamiento de PAFish; inamovible.                           |

### Firmas nuevas (aparecidas por primera vez en post-hardening)

Estas firmas no estaban en el baseline. Su aparicion indica que PAFish ahora ejecuta comprobaciones adicionales que antes no alcanzaba a realizar, probablemente porque en el baseline detectaba el entorno mas rapidamente y terminaba antes de llegar a esas rutinas:

| Firma                   | Descripcion                                              | Categoria  |
|-------------------------|----------------------------------------------------------|------------|
| `antivm_vbox_devices`   | Deteccion de VirtualBox por dispositivos del sistema    | anti-vm    |
| `antivm_vbox_keys`      | Deteccion de VirtualBox por claves de registro          | anti-vm    |
| `antivm_generic_bios`   | Lectura de BIOS via registro para deteccion de VM       | anti-vm    |
| `antivm_generic_diskreg`| Comprobacion de identificadores de disco en el registro | anti-vm    |
| `antivm_checks_available_memory` | Comprobacion de memoria RAM disponible         | anti-vm    |
| `antivm_vmware_devices` | Busqueda de dispositivos VMware (PAFish lo comprueba siempre) | anti-vm |
| `antivm_vmware_files`   | Busqueda de ficheros VMware                             | anti-vm    |
| `antiemu_wine_reg`      | Deteccion de Wine via registro                          | anti-emu   |
| `antisandbox_joe_anubis_files` | Busqueda de ficheros de sandboxes comerciales   | anti-sandbox |
| `query_fips_reconnaissance` | Consulta de estado FIPS                             | discovery  |

> La aparicion de estas firmas es un **indicador positivo del hardening**: revelan que PAFish ejecuto mas rutinas de comprobacion que en el baseline, lo que significa que no se cerro anticipadamente al detectar el entorno. Sin embargo, al llegar a esas nuevas comprobaciones, encontro artefactos residuales de VirtualBox que el hardening no elimino completamente.

---

## Analisis de causas: firmas Anti-VM persistentes

### `antivm_vbox_files` — Artefactos residuales

El script de hardening del Guest elimino los ficheros principales de Guest Additions. Sin embargo, PAFish detecto un segundo conjunto de DLLs de OpenGL especificas de VirtualBox que no estaban en la lista inicial:

- `vboxoglpackspu.dll`
- `vboxoglpassthroughspu.dll`
- `vboxoglfeedbackspu.dll`

Estas DLLs forman parte del pipeline de aceleracion OpenGL de Guest Additions y residen tambien en `System32`. Son detectables por PAFish aunque el ejecutable principal `VBoxTray.exe` haya sido eliminado.

Ademas, `VBoxWddm.sys` — el driver de display activo — no pudo eliminarse en ningun ciclo de reinicio: el kernel lo retiene de forma persistente independientemente del numero de intentos, lo que constituye una limitacion real del entorno y no un error de procedimiento.

### `antivm_vbox_window` y `antivm_vbox_provname`

La ventana `VBoxTrayToolWndClass` seguia activa durante el analisis post-hardening. Esto indica que `VBoxTray.exe` estaba en ejecucion en el momento de crear el snapshot `CAPE_Hardened`, probablemente porque el reinicio post-eliminacion no se completo antes de tomar la instantanea, o porque el proceso se reinicio desde una entrada de autoarranque residual.

### `antivm_vbox_keys` y `antivm_generic_diskreg`

PAFish encontro claves de registro relacionadas con VirtualBox. Las claves bajo `HKLM\HARDWARE\ACPI` con el string `VBOX__` son regeneradas por el hipervisor en cada arranque desde los datos DMI; aunque el spoofing DMI cambia el fabricante y modelo, algunas subclaves ACPI pueden persistir si el DSDT de la VM no fue modificado a nivel de hipervisor.

---

## Tabla resumen de efectividad

| Vector de deteccion         | Firmas afectadas            | Estado post-hardening    |
|-----------------------------|-----------------------------|--------------------------| 
| Disco VBOX HARDDISK         | `antivm_generic_disk`, `antivm_generic_scsi`, `physical_drive_access` | **Neutralizado** |
| MAC 08:00:27 (Oracle)       | `antivm_network_adapters`   | **Neutralizado**         |
| Deteccion estatica (YARA)   | `binary_yara`, `procmem_yara` | **Neutralizado**       |
| Guest Additions (principal) | `antivm_vbox_files` (parcial), `antivm_vbox_window`, `antivm_vbox_provname` | **Parcial** |
| DMI/BIOS                    | `antivm_wmi`, `antivm_generic_bios` | **Parcial**       |
| Claves de registro          | `antivm_vbox_keys`, `antivm_generic_diskreg` | **Parcial** |
| Instrumentacion CAPE        | `antisandbox_unhook`        | **Inamovible**           |
| Comportamiento de PAFish    | `packer_entropy`, `pe_tls_callbacks`, `amsi_enumeration` | **Inamovible** |

---

## Limitaciones identificadas

1. **DLLs OpenGL de VirtualBox no incluidas en el script inicial.** Las DLLs `vboxogl*spu.dll` no formaban parte de la lista de residuales del hardening. Requieren inclusion explicita en una iteracion futura.

2. **`VBoxWddm.sys` inextirpable.** El driver de display de VirtualBox no pudo eliminarse tras multiples ciclos de reinicio. El kernel lo retiene de forma persistente incluso con `MoveFileEx MOVEFILE_DELAY_UNTIL_REBOOT`. Es una limitacion real del entorno: su eliminacion requeriria deshabilitar el driver en el Administrador de dispositivos y sustituirlo por el driver de pantalla generica de Microsoft antes de intentar el borrado.

3. **Regeneracion de tablas ACPI por el hipervisor.** Las claves `HARDWARE\ACPI\DSDT\VBOX__` son regeneradas por VirtualBox en cada arranque desde el DSDT embebido de la VM. El spoofing DMI/BIOS no las afecta directamente; su eliminacion requeriria modificar el DSDT a nivel de imagen de disco de la VM.

4. **`VBoxTrayToolWndClass` en el snapshot.** La ventana estaba activa en el momento de crear `CAPE_Hardened`, lo que indica que el proceso `VBoxTray.exe` estaba en memoria o que una entrada de autoarranque residual lo relanzaba. El snapshot deberia tomarse con el proceso confirmado como inexistente.

5. **`antisandbox_unhook` es inherente a CAPE.** PAFish detecta y revierte activamente los hooks WMI del agente de monitorizacion. Esta firma no puede neutralizarse sin desactivar la instrumentacion de comportamiento de CAPE, lo que contradice el objetivo del entorno.

---

## Snapshot final

```bash
VBoxManage snapshot "Win10-Lab" take "CAPE_Hardened" \
    --description "Post-hardening: GA parcialmente eliminadas, DMI/BIOS/disco spoofed, MAC Intel, CPUID oculto"

# Configuracion en /opt/CAPEv2/conf/virtualbox.conf
# snapshot = CAPE_Hardened
```

---

## Referencias

- [VBoxManage extradata — Oracle VirtualBox Manual §9.9](https://www.virtualbox.org/manual/ch09.html#idm6006)
- [PAFish — Paranoid Fish (a0rtega)](https://github.com/a0rtega/pafish)
- [Al-Khaser — Anti-VM checks reference](https://github.com/LordNoteworthy/al-khaser)
- [CAPEv2 — Configuration Reference](https://github.com/kevoreilly/CAPEv2/tree/master/conf)
- [MITRE ATT&CK T1497 — Virtualization/Sandbox Evasion](https://attack.mitre.org/techniques/T1497/)
