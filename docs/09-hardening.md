# 09 — Hardening Anti-VM: Neutralización de Vectores de Detección

> Este documento parte de los resultados del análisis baseline (doc `08`). A diferencia de un análisis fallido, CAPE tuvo **visibilidad completa** sobre PAFish (238 s, Malscore 9.0, 28/36 firmas). El objetivo del hardening no es que CAPE vea más — es que **PAFish no pueda distinguir la sandbox de una máquina física** y, por tanto, no active sus rutinas de evasión en el malware real.

---

## Vectores de detección identificados en el baseline

El análisis `08` identificó cinco vectores independientes, ordenados por impacto:

| Prioridad | Vector                              | Firma(s) asociada(s)                                      | Artefactos |
|-----------|-------------------------------------|-----------------------------------------------------------|-----------|
| 1 (crítico) | VirtualBox Guest Additions          | `antivm_vbox_files`, `antivm_vbox_window`, `antivm_vbox_provname` | 17 archivos + 1 ventana activa |
| 2 (alto)  | DMI/BIOS emulado por el hipervisor  | `antivm_wmi`, `recon_fingerprint`                         | Fabricante, modelo, versión BIOS vía WMI |
| 3 (alto)  | Identificadores de disco virtual    | `antivm_generic_disk`, `antivm_generic_scsi`, `physical_drive_access` | Modelo/firmware/S/N SCSI |
| 4 (medio) | Dirección MAC Oracle                | `antivm_network_adapters`                                 | Prefijo `08:00:27` |
| 5 (medio) | Claves de registro residuales       | `recon_fingerprint` (`SystemBiosDate` en `HKLM\HARDWARE`) | Regeneradas automáticamente al aplicar (2) |

> **Nota sobre `antisandbox_unhook`:** PAFish detectó y revirtió activamente 11 hooks WMI instalados por el agente de CAPE. Esta firma se aborda con ajustes de configuración de CAPE (sección 5), no con hardening del Guest.

---

## Arquitectura del hardening

El hardening se aplica en **dos planos**:

```
┌────────────────────────────────────────────────────────────┐
│  HOST UBUNTU — VBoxManage (VM apagada)                     │
│  · Spoofing de DMI/BIOS (vectores 2 y 5)                   │
│  · Spoofing de modelo de disco (vector 3)                  │
│  · Cambio de MAC address (vector 4)                        │
│  · Ocultación de CPUID del hipervisor                      │
└─────────────────────────┬──────────────────────────────────┘
                          │ se aplica primero
┌─────────────────────────▼──────────────────────────────────┐
│  GUEST WINDOWS 10 — PowerShell como Administrador          │
│  · Desinstalación de Guest Additions (vector 1)            │
│  · Limpieza de drivers y ficheros residuales (vector 1)    │
│  · Limpieza de claves de registro residuales (vector 5)    │
└────────────────────────────────────────────────────────────┘
```

Al finalizar: snapshot `CAPE_Hardened` → nuevo análisis → comparativa de firmas.

---

## Preparación previa

Trabaja con la VM **apagada**. El snapshot `CAPE_Limpio` se mantiene intacto como referencia; al terminar el hardening crearás uno nuevo.

```bash
# Verificar estado de la VM
VBoxManage showvminfo "Win10-Lab" --machinereadable | grep VMState
# Si está corriendo:
VBoxManage controlvm "Win10-Lab" acpipowerbutton && sleep 15
```

---

## Paso 1 — Spoofing de DMI/BIOS (Host)

**Vectores neutralizados:** `antivm_wmi` (Win32_BIOS, Win32_ComputerSystem), `recon_fingerprint`

Las consultas WMI a `Win32_BIOS` y `Win32_ComputerSystem` leen directamente de las tablas DMI/SMBIOS que VirtualBox emula con strings identificativos (`innotek GmbH`, `VBOX`, `Oracle`). El spoofing se realiza a nivel de hipervisor, por lo que afecta a todas las vías de lectura (WMI, API de BIOS, acceso directo a memoria).

```bash
# En el Host Ubuntu — VM apagada
VM="Win10-Lab"

# Fabricante y modelo del sistema (Win32_ComputerSystem.Manufacturer / .Model)
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor"    "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct"   "20SL001DGE"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion"   "ThinkBook 15 G2 ITL"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"    "PF2RABCD"

# BIOS (Win32_BIOS.Manufacturer / .SMBIOSBIOSVersion / .ReleaseDate)
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVendor"      "American Megatrends Inc."
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVersion"     "F.26"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseDate" "04/15/2022"

# Chasis
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor"   "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiChassisType"     "10"

# Placa base
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardVendor"     "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardProduct"    "LNVNB161216"
```

**Verificación en el Guest** (tras arrancar la VM después de todos los pasos del host):

```powershell
Get-WmiObject Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
Get-WmiObject Win32_ComputerSystem | Select-Object Manufacturer, Model
# Resultado esperado: LENOVO / American Megatrends Inc. / F.26
```

---

## Paso 2 — Spoofing del disco virtual (Host)

**Vectores neutralizados:** `antivm_generic_disk`, `antivm_generic_scsi`, `physical_drive_access`

PAFish consulta el modelo del disco vía IOCTL (`IDENTIFYDEVICE` / `SCSI INQUIRY`) y vía WMI (`Win32_DiskDrive`). VirtualBox devuelve `VBOX HARDDISK` en ambas vías por defecto.

```bash
VM="Win10-Lab"

# Modelo, firmware y número de serie del disco (controladora AHCI, puerto 0)
VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber" \
    "Samsung SSD 870 EVO 500GB"
VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" \
    "SVT01B6Q"
VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber" \
    "S5YENX0T123456A"
```

> **Nota:** si tu VM usa controladora IDE en lugar de AHCI, sustituye `ahci/0` por `piix3ide/0` en las rutas de extradata. Puedes verificarlo en Configuración > Almacenamiento en la interfaz de VirtualBox.

**Verificación en el Guest:**

```powershell
Get-WmiObject Win32_DiskDrive | Select-Object Model, SerialNumber, FirmwareRevision
# Resultado esperado: Samsung SSD 870 EVO 500GB / S5YENX0T123456A / SVT01B6Q
```

---

## Paso 3 — Cambio de MAC address (Host)

**Vector neutralizado:** `antivm_network_adapters` (prefijo `08:00:27` de Oracle/VirtualBox)

```bash
VM="Win10-Lab"

# OUI de Intel (8C:8D:28) + 3 octetos aleatorios
SUFFIX=$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')
NEW_MAC="8C8D28${SUFFIX}"
VBoxManage modifyvm "$VM" --macaddress1 "$NEW_MAC"
echo "Nueva MAC: ${NEW_MAC:0:2}:${NEW_MAC:2:2}:${NEW_MAC:4:2}:${NEW_MAC:6:2}:${NEW_MAC:8:2}:${NEW_MAC:10:2}"
```

**Verificación en el Guest:**

```powershell
Get-NetAdapter | Select-Object Name, MacAddress
# El prefijo no debe ser 08-00-27
```

---

## Paso 4 — Ocultación del hipervisor en CPUID (Host)

Aunque PAFish no disparó una firma específica de CPUID en el baseline (el API Hooking de CAPE capturó el comportamiento antes de que PAFish se cerrara), la instrucción `CPUID` con `EAX=0x40000000` devuelve `VBoxVBoxVBox` sin hardening. Aplicarlo previene detecciones en malware más sofisticado.

```bash
VM="Win10-Lab"

# Suprimir la hoja de firma del hipervisor
VBoxManage setextradata "$VM" "VBoxInternal/CPUM/SuppressHypervisorCpuIdLeaf" 1

# Desactivar paravirtualización (elimina otra vía de detección)
VBoxManage modifyvm "$VM" --paravirtprovider none

# Perfil de CPU del host real
VBoxManage modifyvm "$VM" --cpu-profile "Intel Core i7-10700"
```

---

## Paso 5 — Desinstalar Guest Additions (Guest)

**Vectores neutralizados:** `antivm_vbox_files` (17 artefactos), `antivm_vbox_window`, `antivm_vbox_provname`

Este es el paso de mayor impacto: un único origen (Guest Additions) es responsable del mayor bloque de detecciones. La desinstalación elimina simultáneamente los 17 archivos detectados y la ventana `VBoxTrayToolWndClass`.

> ⚠️ Ejecutar como **Administrador** en PowerShell dentro del Guest Windows 10.

### 5.1 Desinstalación via WMI

```powershell
$ga = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*VirtualBox*" }
if ($ga) {
    Write-Host "Desinstalando: $($ga.Name)"
    $ga.Uninstall()
    Write-Host "[OK] Desinstalación completada. Reinicia la VM antes de continuar."
} else {
    Write-Host "[!!] Guest Additions no encontradas en Win32_Product."
}
```

Reinicia la VM y continúa con 5.2.

### 5.2 Limpieza de ficheros residuales

Tras el reinicio, algunos drivers y DLLs pueden quedar en disco:

```powershell
$residuales = @(
    "C:\Windows\System32\drivers\VBoxMouse.sys",
    "C:\Windows\System32\drivers\VBoxGuest.sys",
    "C:\Windows\System32\drivers\VBoxSF.sys",
    "C:\Windows\System32\drivers\VBoxVideo.sys",
    "C:\Windows\System32\VBoxDisp.dll",
    "C:\Windows\System32\VBoxHook.dll",
    "C:\Windows\System32\VBoxMRXNP.dll",
    "C:\Windows\System32\VBoxOGL.dll",
    "C:\Windows\System32\VBoxService.exe",
    "C:\Windows\System32\VBoxTray.exe",
    "C:\Windows\SysWOW64\VBoxDisp.dll",
    "C:\Windows\SysWOW64\VBoxHook.dll",
    "C:\Windows\SysWOW64\VBoxMRXNP.dll"
)

foreach ($f in $residuales) {
    if (Test-Path $f) {
        takeown /F $f /A | Out-Null
        icacls $f /grant "Administrators:F" | Out-Null
        Remove-Item $f -Force
        Write-Host "[OK] Eliminado: $f"
    }
}
```

### 5.3 Eliminar servicios residuales

```powershell
$servicios = @("VBoxService", "VBoxMouse", "VBoxGuest", "VBoxSF", "VBoxVideo", "VBoxNetAdp", "VBoxNetLwf")
foreach ($svc in $servicios) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc | Out-Null
        Write-Host "[OK] Servicio eliminado: $svc"
    }
}
```

### 5.4 Verificación

```powershell
# Ninguno de estos ficheros debe existir
$check = @("VBoxTray.exe", "VBoxService.exe", "VBoxGuest.sys", "VBoxMouse.sys", "VBoxDisp.dll")
foreach ($f in $check) {
    $ruta = "C:\Windows\System32\$f"
    if (Test-Path $ruta) {
        Write-Host "[FALLO] Aún existe: $ruta" -ForegroundColor Red
    } else {
        Write-Host "[OK]    No encontrado: $ruta" -ForegroundColor Green
    }
}

# La ventana VBoxTrayToolWndClass no debe aparecer
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
$hwnd = [Win32]::FindWindow("VBoxTrayToolWndClass", $null)
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "[OK]    VBoxTrayToolWndClass: no encontrada" -ForegroundColor Green
} else {
    Write-Host "[FALLO] VBoxTrayToolWndClass aún activa (HWND: $hwnd)" -ForegroundColor Red
}
```

---

## Paso 6 — Limpieza de claves de registro residuales (Guest)

**Vector neutralizado:** `recon_fingerprint` (lectura de `SystemBiosDate` en `HKLM\HARDWARE\DESCRIPTION\System`)

Las claves bajo `HKLM\HARDWARE\ACPI` con el string `VBOX__` son generadas automáticamente por el hipervisor al arrancar. Al haber aplicado el spoofing de DMI/BIOS en el Paso 1, estas claves deberían reflejar ya los nuevos valores. Se limpian las que puedan quedar de la instalación de Guest Additions:

```powershell
$claves = @(
    "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions",
    "HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox Guest Additions",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxGuest",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxMouse",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxService",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSF",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxVideo",
    "HKLM:\HARDWARE\ACPI\DSDT\VBOX__",
    "HKLM:\HARDWARE\ACPI\FADT\VBOX__",
    "HKLM:\HARDWARE\ACPI\RSDT\VBOX__"
)

foreach ($clave in $claves) {
    if (Test-Path $clave) {
        Remove-Item -Path $clave -Recurse -Force
        Write-Host "[OK] Eliminada: $clave"
    }
}

# Verificar que SystemBiosDate no contiene strings de VBox
$biosDate = (Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System" -Name SystemBiosDate -EA SilentlyContinue).SystemBiosDate
Write-Host "SystemBiosDate actual: $biosDate"
# Resultado esperado: una fecha real (ej. "04/15/22"), no "VBOX" ni cadena vacía
```

---

## Paso 7 — Ajuste de configuración de CAPE (Host)

### 7.1 Actualizar el snapshot en virtualbox.conf

```ini
# /opt/CAPEv2/conf/virtualbox.conf
[Win10-Lab]
label           = Win10-Lab
platform        = windows
ip              = 192.168.56.101
snapshot        = CAPE_Hardened     # ← nombre del nuevo snapshot
interface       = vboxnet0
resultserver_ip = 192.168.56.1
```

### 7.2 Revisión de auxiliary.conf (simulación de actividad humana)

La firma `antisandbox_unhook` muestra que PAFish detecta la instrumentación WMI de CAPE. Esto no se puede eliminar completamente sin desactivar capacidades de análisis, pero se puede mitigar habilitando la simulación de actividad humana, que dificulta la detección basada en ausencia de interacción:

```ini
# /opt/CAPEv2/conf/auxiliary.conf
[human]
enabled = yes
```

---

## Paso 8 — Crear el snapshot hardened

Con todos los pasos anteriores aplicados y el Guest **apagado limpiamente** desde Windows (no poweroff forzado):

```bash
# Verificar que el agente de CAPE responde antes de apagar
bash scripts/check-agent.sh

# Crear el snapshot
VBoxManage snapshot "Win10-Lab" take "CAPE_Hardened" \
    --description "Post-hardening: GA desinstaladas, DMI/BIOS/disco spoofed, MAC Intel, CPUID oculto"

# Confirmar
VBoxManage snapshot "Win10-Lab" list
```

---

## Verificación: análisis post-hardening con PAFish

Enviar `pafish64.exe` siguiendo el mismo procedimiento del doc `08` (misma máquina, mismo timeout, mismo package) y registrar el resultado en `reports/01-sin-GA/` (o la carpeta correspondiente a la capa aplicada).

### Métricas objetivo por vector

| Vector neutralizado        | Firma baseline                   | Objetivo post-hardening         |
|----------------------------|----------------------------------|---------------------------------|
| Guest Additions eliminadas | `antivm_vbox_files` (17 archivos) | **0 artefactos detectados**     |
|                            | `antivm_vbox_window`             | **No disparada**                |
|                            | `antivm_vbox_provname`           | **No disparada**                |
| DMI/BIOS spoofed           | `antivm_wmi` (Win32_BIOS)        | **No disparada**                |
|                            | `recon_fingerprint`              | **No disparada**                |
| Disco spoofed              | `antivm_generic_disk`            | **No disparada**                |
|                            | `antivm_generic_scsi`            | **No disparada**                |
|                            | `physical_drive_access`          | Sin cambio (acceso legítimo)    |
| MAC cambiada               | `antivm_network_adapters`        | **No disparada**                |
| Sin cambio esperado        | `antisandbox_unhook`             | Puede persistir (inherente a CAPE) |
| Sin cambio esperado        | `packer_entropy` / `binary_yara` | Sin cambio (análisis estático)  |

### Tabla comparativa de resultados

| Métrica                        | Pre-hardening (baseline) | Post-hardening (objetivo) |
|--------------------------------|--------------------------|--------------------------|
| Duración del análisis          | 238 s                    | ≥ 238 s (sin cambio esperado) |
| Malscore                       | 9.0 / 10                 | Reducción en firmas Anti-VM   |
| Firmas `antivm_*` disparadas   | 8                        | **0–2** (solo las no neutralizables) |
| Firmas totales disparadas      | 28 / 36                  | Reducción proporcional        |
| `antivm_vbox_files` artefactos | 17                        | **0**                    |
| `antivm_vbox_window`           | Disparada                | **No disparada**         |

El reporte post-hardening se guardará en `reports/` con la nomenclatura definida en el repositorio.

---

## Resumen de cambios aplicados

```
┌───────────────────────────────────────────────────────────────────────────┐
│              MAPA DE HARDENING — Win10-Lab                                │
├────────────────────────────┬──────────────────────────────────────────────┤
│ Vector (firma baseline)    │ Acción aplicada                              │
├────────────────────────────┼──────────────────────────────────────────────┤
│ Guest Additions            │ Desinstaladas + limpieza de residuos         │
│ antivm_vbox_files (×17)    │ Todos los artefactos eliminados              │
│ antivm_vbox_window         │ VBoxTray.exe eliminado → ventana inexistente │
│ antivm_vbox_provname       │ VBoxMRXNP.dll eliminado                      │
│ antivm_wmi / recon_fp      │ DMI/BIOS spoofed → LENOVO ThinkBook 15       │
│ antivm_generic_disk/scsi   │ Disco spoofed → Samsung SSD 870 EVO          │
│ antivm_network_adapters    │ MAC → OUI Intel (8C:8D:28:xx:xx:xx)          │
│ CPUID hipervisor           │ Leaf 0x40000000 suprimida                    │
├────────────────────────────┼──────────────────────────────────────────────┤
│ antisandbox_unhook         │ Sin cambio (inherente a la instrumentación   │
│                            │ de CAPE; mitigado con human simulation)      │
└────────────────────────────┴──────────────────────────────────────────────┘
```

---

## Referencias

- [VBoxManage extradata — Oracle VirtualBox Manual §9.9](https://www.virtualbox.org/manual/ch09.html#idm6006)
- [PAFish — Paranoid Fish (a0rtega)](https://github.com/a0rtega/pafish)
- [Al-Khaser — Anti-VM checks reference](https://github.com/LordNoteworthy/al-khaser)
- [CAPEv2 — Configuration Reference](https://github.com/kevoreilly/CAPEv2/tree/master/conf)
- [MITRE ATT&CK T1497 — Virtualization/Sandbox Evasion](https://attack.mitre.org/techniques/T1497/)
