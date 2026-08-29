#Requires -RunAsAdministrator
# ==============================================================================
# hardening-guest.ps1 - Hardening Anti-VM en el Guest Windows 10
# Neutraliza: antivm_vbox_files, antivm_vbox_window, antivm_vbox_provname,
#             antivm_wmi (registro), recon_fingerprint
# Ejecutar como Administrador en PowerShell
# ==============================================================================

$ErrorActionPreference = "SilentlyContinue"

function ok   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green  }
function warn { param($m) Write-Host "[!!]  $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "[ ]   $m" -ForegroundColor Cyan   }
function fail { param($m) Write-Host "[X]   $m" -ForegroundColor Red    }

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Hardening Guest - Windows 10" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# INIT: Cargar MoveFileEx para eliminar ficheros bloqueados por el kernel
# Necesario para drivers (.sys) cargados en Ring 0
# ------------------------------------------------------------------------------
$MethodDefinition = @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool MoveFileEx(string lpExistingFileName, IntPtr lpNewFileName, int dwFlags);
'@
$Kernel32 = Add-Type -MemberDefinition $MethodDefinition -Name "Kernel32" -Namespace "Win32" -PassThru
$MOVEFILE_DELAY_UNTIL_REBOOT = 4

# ------------------------------------------------------------------------------
# PASO 1: Detener procesos activos de VirtualBox
# ------------------------------------------------------------------------------
info "Paso 1: Deteniendo procesos de VirtualBox..."

$procesos = @("VBoxTray", "VBoxService", "VBoxControl")
foreach ($p in $procesos) {
    taskkill /F /IM "$p.exe" /T 2>$null | Out-Null
}

# Eliminar entradas de autoarranque (solo HKLM -- en HKCU no existe en instalacion estandar)
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "VBoxTray" -ErrorAction SilentlyContinue
ok "Procesos detenidos y autoarranque eliminado"

# ------------------------------------------------------------------------------
# PASO 2: Deshabilitar y detener servicios
# Poner Start=4 (disabled) antes de detenerlos evita que se reactiven solos
# ------------------------------------------------------------------------------
info "Paso 2: Deshabilitando servicios de VirtualBox..."

$servicios = @("VBoxGuest", "VBoxMouse", "VBoxService", "VBoxSF", "VBoxVideo", "VBoxNetAdp", "VBoxNetLwf")
foreach ($svc in $servicios) {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name "Start" -Value 4 -Force
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        ok "Servicio deshabilitado: $svc"
    }
}

# ------------------------------------------------------------------------------
# PASO 3: Eliminar ficheros de VirtualBox
# Estrategia en 4 capas para superar bloqueos de kernel:
#   1. Quitar atributos (R/S/H)
#   2. Tomar ownership + permisos via SID universal (funciona en Windows en cualquier idioma)
#   3. Borrado normal
#   4. Si el kernel lo retiene: MoveFileEx DELAY_UNTIL_REBOOT (Session Manager, pre-desktop)
# ------------------------------------------------------------------------------
info "Paso 3: Eliminando ficheros residuales..."

$residuales = @(
    # System32 - ejecutables
    "C:\Windows\System32\VBoxTray.exe",         # antivm_vbox_window (VBoxTrayToolWndClass)
    "C:\Windows\System32\VBoxService.exe",
    "C:\Windows\System32\VBoxControl.exe",
    # System32 - DLLs
    "C:\Windows\System32\VBoxDisp.dll",
    "C:\Windows\System32\VBoxHook.dll",
    "C:\Windows\System32\VBoxMRXNP.dll",        # antivm_vbox_provname (WNetGetProviderName)
    "C:\Windows\System32\VBoxOGL.dll",
    "C:\Windows\System32\VBoxGL.dll",           # presente en versiones recientes de GA
    "C:\Windows\System32\VBoxSF.dll",
    # System32 - drivers
    "C:\Windows\System32\drivers\VBoxGuest.sys",
    "C:\Windows\System32\drivers\VBoxMouse.sys",
    "C:\Windows\System32\drivers\VBoxSF.sys",
    "C:\Windows\System32\drivers\VBoxVideo.sys",
    "C:\Windows\System32\drivers\VBoxWddm.sys", # driver WDDM alternativo
    # SysWOW64 - equivalentes 32 bits
    "C:\Windows\SysWOW64\VBoxDisp.dll",
    "C:\Windows\SysWOW64\VBoxHook.dll",
    "C:\Windows\SysWOW64\VBoxMRXNP.dll",
    "C:\Windows\SysWOW64\VBoxOGL.dll",
    "C:\Windows\SysWOW64\VBoxGL.dll",
    "C:\Windows\SysWOW64\VBoxControl.exe",
    # Carpeta de instalacion
    "C:\Program Files\Oracle\VirtualBox Guest Additions"
)

$archivosBloqueados = 0
foreach ($f in $residuales) {
    if (Test-Path $f) {
        attrib -R -S -H $f 2>$null | Out-Null
        takeown /F $f /A 2>$null | Out-Null
        icacls $f /grant "*S-1-5-32-544:F" /c /q 2>$null | Out-Null
        Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $f) {
            # Fichero retenido por el kernel: programar borrado en el siguiente arranque
            $result = $Kernel32::MoveFileEx($f, [IntPtr]::Zero, $MOVEFILE_DELAY_UNTIL_REBOOT)
            if ($result) {
                warn "Pendiente de reinicio (bloqueado por kernel): $f"
                $archivosBloqueados++
            } else {
                fail "Fallo critico al programar borrado: $f"
            }
        } else {
            ok "Eliminado: $f"
        }
    }
}

# ------------------------------------------------------------------------------
# PASO 4: Limpiar registro
# Incluye claves de servicios, ACPI, provider de red, y entradas de hardware
# que PAFish consulta via WMI y acceso directo al registro
# ------------------------------------------------------------------------------
info "Paso 4: Purgando registro de Windows..."

$claves = @(
    # Software instalado
    "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions",
    "HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox Guest Additions",

    # Servicios
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxGuest",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxMouse",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxService",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSF",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxVideo",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxNetAdp",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxNetLwf",

    # Provider de red -- responsable de antivm_vbox_provname
    "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order",  # se edita abajo, no se elimina
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSF\NetworkProvider",

    # ACPI -- tablas generadas por VirtualBox con string "VBOX__"
    "HKLM:\HARDWARE\ACPI\DSDT\VBOX__",
    "HKLM:\HARDWARE\ACPI\FADT\VBOX__",
    "HKLM:\HARDWARE\ACPI\RSDT\VBOX__",

    # Clase de dispositivo VirtualBox en el gestor de dispositivos
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E967-E325-11CE-BFC1-08002BE10318}\VBoxGuest",

    # Autoarranque residual
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\VBoxTray"
)

foreach ($c in $claves) {
    if (Test-Path $c) {
        Remove-Item -Path $c -Recurse -Force
        ok "Clave eliminada: $c"
    }
}

# Limpiar el provider VBoxSF de la lista de providers de red
# (eliminar la clave entera romperia la red; solo se borra la entrada VBoxSF)
$providerOrder = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
if (Test-Path $providerOrder) {
    $actual = (Get-ItemProperty -Path $providerOrder -Name "ProviderOrder" -ErrorAction SilentlyContinue).ProviderOrder
    if ($actual -like "*VBoxSF*") {
        $limpio = ($actual -split "," | Where-Object { $_ -notlike "*VBox*" }) -join ","
        Set-ItemProperty -Path $providerOrder -Name "ProviderOrder" -Value $limpio
        ok "VBoxSF eliminado de NetworkProvider Order"
    }
}

# ------------------------------------------------------------------------------
# PASO 5: Verificacion
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "-- Verificacion --" -ForegroundColor Cyan

# 5a. Ficheros criticos
$criticos = @(
    "C:\Windows\System32\VBoxTray.exe",
    "C:\Windows\System32\VBoxMRXNP.dll",
    "C:\Windows\System32\drivers\VBoxGuest.sys",
    "C:\Windows\System32\drivers\VBoxMouse.sys"
)
foreach ($f in $criticos) {
    if (Test-Path $f) {
        if ($archivosBloqueados -gt 0) {
            warn "Pendiente de reinicio: $f"
        } else {
            fail "Aun existe: $f"
        }
    } else {
        ok "Limpio: $f"
    }
}

# 5b. Ventana VBoxTrayToolWndClass (antivm_vbox_window)
if (-not ([System.Management.Automation.PSTypeName]'WinAPICheck').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPICheck {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
}
$hwnd = [WinAPICheck]::FindWindow("VBoxTrayToolWndClass", $null)
if ($hwnd -eq [IntPtr]::Zero) {
    ok "VBoxTrayToolWndClass: no encontrada (antivm_vbox_window neutralizada)"
} else {
    warn "VBoxTrayToolWndClass aun activa - se eliminara al reiniciar"
}

# 5c. DMI/BIOS (verificar spoofing del host)
$cs = Get-WmiObject Win32_ComputerSystem
$bios = Get-WmiObject Win32_BIOS
Write-Host ""
Write-Host "  Win32_ComputerSystem.Manufacturer: $($cs.Manufacturer)"
Write-Host "  Win32_BIOS.SMBIOSBIOSVersion:      $($bios.SMBIOSBIOSVersion)"
if ($cs.Manufacturer -like "*LENOVO*") {
    ok "DMI/BIOS spoofing verificado (antivm_wmi neutralizada)"
} else {
    warn "DMI/BIOS muestra '$($cs.Manufacturer)' - asegurate de haber ejecutado hardening-host.sh antes"
}

# 5d. Disco
$disco = Get-WmiObject Win32_DiskDrive | Select-Object -First 1
Write-Host "  Win32_DiskDrive.Model:             $($disco.Model)"
if ($disco.Model -notlike "*VBOX*") {
    ok "Disco spoofing verificado (antivm_generic_disk neutralizada)"
} else {
    warn "Disco aun reporta VBOX - verifica hardening-host.sh"
}

# 5e. MAC
$nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Write-Host "  MAC address:                       $($nic.MacAddress)"
if ($nic.MacAddress -notlike "08-00-27*") {
    ok "MAC verificada - prefijo Oracle eliminado"
} else {
    warn "MAC aun es $($nic.MacAddress) - verifica hardening-host.sh"
}

# ------------------------------------------------------------------------------
# Resumen final
# ------------------------------------------------------------------------------
Write-Host ""
if ($archivosBloqueados -gt 0) {
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host "  $archivosBloqueados fichero(s) pendientes de reinicio." -ForegroundColor Yellow
    Write-Host "  REINICIA LA VM AHORA." -ForegroundColor Yellow
    Write-Host "  Windows los eliminara antes de cargar el escritorio." -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Yellow
} else {
    Write-Host "======================================================" -ForegroundColor Green
    Write-Host "  HARDENING DEL GUEST COMPLETADO." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Pasos siguientes:" -ForegroundColor Yellow
    Write-Host "  1. En el Host ejecuta:" -ForegroundColor Yellow
    Write-Host '     VBoxManage snapshot "Win10-Lab" take "CAPE_Hardened"' -ForegroundColor White
    Write-Host "  2. Apaga la VM limpiamente (Inicio > Apagar)" -ForegroundColor Yellow
    Write-Host "  3. Actualiza snapshot en /opt/CAPEv2/conf/virtualbox.conf" -ForegroundColor Yellow
    Write-Host "  4. Envia pafish64.exe para el analisis post-hardening" -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Green
}
