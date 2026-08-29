#Requires -RunAsAdministrator
# =============================================================================
# hardening-guest.ps1 — Hardening Anti-VM en el Guest Windows 10
# Neutraliza: antivm_vbox_files, antivm_vbox_window, antivm_vbox_provname
#             y claves de registro residuales de VirtualBox
# Ejecutar como Administrador en PowerShell
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
function ok   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green  }
function warn { param($m) Write-Host "[!!]  $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "[ ]   $m" -ForegroundColor Cyan   }

Write-Host ""
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Hardening Guest — Windows 10" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── 1. Desinstalar VirtualBox Guest Additions ─────────────────────────────────
info "Paso 1: Desinstalar VirtualBox Guest Additions..."
info "  (Neutraliza: antivm_vbox_files x17, antivm_vbox_window, antivm_vbox_provname)"

$ga = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*VirtualBox*" }
if ($ga) {
    Write-Host "  Encontrado: $($ga.Name)" -ForegroundColor White
    $resultado = $ga.Uninstall()
    if ($resultado.ReturnValue -eq 0) {
        ok "Guest Additions desinstaladas. REINICIA LA VM antes de continuar con el Paso 2."
        Write-Host ""
        Write-Host "  ► Reinicia la VM ahora y vuelve a ejecutar este script para completar los pasos 2-4." -ForegroundColor Yellow
        exit 0
    } else {
        warn "La desinstalación devolvió código: $($resultado.ReturnValue). Intenta manualmente desde Panel de Control."
    }
} else {
    warn "Guest Additions no encontradas en Win32_Product (quizás ya desinstaladas — continuando)."
}

# ── 2. Limpieza de ficheros residuales ────────────────────────────────────────
info "Paso 2: Eliminar ficheros residuales de VirtualBox..."

# Estos son los 17 ficheros que PAFish detectó en el baseline (firma antivm_vbox_files)
$residuales = @(
    "C:\Windows\System32\drivers\VBoxMouse.sys",
    "C:\Windows\System32\drivers\VBoxGuest.sys",
    "C:\Windows\System32\drivers\VBoxSF.sys",
    "C:\Windows\System32\drivers\VBoxVideo.sys",
    "C:\Windows\System32\VBoxDisp.dll",
    "C:\Windows\System32\VBoxHook.dll",
    "C:\Windows\System32\VBoxMRXNP.dll",   # ← responsable de antivm_vbox_provname
    "C:\Windows\System32\VBoxOGL.dll",
    "C:\Windows\System32\VBoxService.exe",
    "C:\Windows\System32\VBoxTray.exe",     # ← responsable de antivm_vbox_window
    "C:\Windows\System32\VBoxControl.exe",
    "C:\Windows\SysWOW64\VBoxDisp.dll",
    "C:\Windows\SysWOW64\VBoxHook.dll",
    "C:\Windows\SysWOW64\VBoxMRXNP.dll",
    "C:\Windows\SysWOW64\VBoxOGL.dll",
    "C:\Windows\SysWOW64\VBoxControl.exe",
    "C:\Program Files\Oracle\VirtualBox Guest Additions"
)

foreach ($f in $residuales) {
    if (Test-Path $f) {
        try {
            takeown /F $f /A /R /D Y 2>$null | Out-Null
            icacls $f /grant "Administrators:F" /T 2>$null | Out-Null
            Remove-Item $f -Recurse -Force
            ok "Eliminado: $f"
        } catch {
            warn "No se pudo eliminar: $f"
        }
    }
}

# ── 3. Eliminar servicios residuales ─────────────────────────────────────────
info "Paso 3: Eliminar servicios de VirtualBox..."

$servicios = @("VBoxService", "VBoxMouse", "VBoxGuest", "VBoxSF", "VBoxVideo", "VBoxNetAdp", "VBoxNetLwf")
foreach ($svc in $servicios) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc 2>$null | Out-Null
        ok "Servicio eliminado: $svc"
    }
}

# ── 4. Limpiar registro ───────────────────────────────────────────────────────
info "Paso 4: Eliminar claves de registro de VirtualBox..."

$claves = @(
    "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions",
    "HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox Guest Additions",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxGuest",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxMouse",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxService",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSF",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxVideo",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxNetAdp",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxNetLwf",
    "HKLM:\HARDWARE\ACPI\DSDT\VBOX__",
    "HKLM:\HARDWARE\ACPI\FADT\VBOX__",
    "HKLM:\HARDWARE\ACPI\RSDT\VBOX__"
)

foreach ($c in $claves) {
    if (Test-Path $c) {
        Remove-Item -Path $c -Recurse -Force
        ok "Eliminada: $c"
    }
}

# ── 5. Verificación completa ──────────────────────────────────────────────────
Write-Host ""
Write-Host "── Verificación ──────────────────────────────────────" -ForegroundColor Cyan

# 5a. Ficheros críticos
$criticos = @(
    "C:\Windows\System32\VBoxTray.exe",
    "C:\Windows\System32\VBoxMRXNP.dll",
    "C:\Windows\System32\drivers\VBoxGuest.sys"
)
foreach ($f in $criticos) {
    if (Test-Path $f) {
        Write-Host "[FALLO] Aún existe: $f" -ForegroundColor Red
    } else {
        ok "No encontrado: $f"
    }
}

# 5b. Ventana VBoxTrayToolWndClass
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
$hwnd = [WinAPI]::FindWindow("VBoxTrayToolWndClass", $null)
if ($hwnd -eq [IntPtr]::Zero) {
    ok "VBoxTrayToolWndClass: no encontrada (antivm_vbox_window neutralizada)"
} else {
    Write-Host "[FALLO] VBoxTrayToolWndClass activa — VBoxTray.exe puede estar aún en memoria" -ForegroundColor Red
    warn "Reinicia la VM y vuelve a verificar."
}

# 5c. DMI/BIOS (verificar que el spoofing del host se aplicó correctamente)
$bios = Get-WmiObject Win32_BIOS
$cs   = Get-WmiObject Win32_ComputerSystem
Write-Host ""
Write-Host "  Win32_BIOS.Manufacturer:        $($bios.Manufacturer)"
Write-Host "  Win32_BIOS.SMBIOSBIOSVersion:   $($bios.SMBIOSBIOSVersion)"
Write-Host "  Win32_ComputerSystem.Manufacturer: $($cs.Manufacturer)"
Write-Host "  Win32_ComputerSystem.Model:        $($cs.Model)"
if ($cs.Manufacturer -like "*LENOVO*") {
    ok "DMI/BIOS spoofing verificado (antivm_wmi neutralizada)"
} else {
    warn "DMI/BIOS aún muestra '$($cs.Manufacturer)' — verifica que hardening-host.sh se ejecutó antes de arrancar la VM"
}

# 5d. Disco
$disco = Get-WmiObject Win32_DiskDrive | Select-Object -First 1
Write-Host ""
Write-Host "  Win32_DiskDrive.Model:  $($disco.Model)"
if ($disco.Model -like "*Samsung*" -or $disco.Model -notlike "*VBOX*") {
    ok "Disco spoofing verificado (antivm_generic_disk neutralizada)"
} else {
    warn "Disco aún reporta '$($disco.Model)'"
}

# 5e. MAC
$mac = (Get-NetAdapter | Select-Object -First 1).MacAddress
Write-Host ""
Write-Host "  MAC address: $mac"
if ($mac -notlike "08-00-27*") {
    ok "MAC verificada — prefijo Oracle eliminado"
} else {
    warn "MAC aún es $mac — verifica que hardening-host.sh cambió la MAC"
}

# ── Resumen ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Hardening del GUEST completado." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pasos siguientes:" -ForegroundColor Yellow
Write-Host "  1. Revisa los [FALLO] arriba si los hay" -ForegroundColor Yellow
Write-Host "  2. Apaga la VM limpiamente (Inicio > Apagar)" -ForegroundColor Yellow
Write-Host "  3. En el Host ejecuta:" -ForegroundColor Yellow
Write-Host '     VBoxManage snapshot "Win10-Lab" take "CAPE_Hardened"' -ForegroundColor White
Write-Host "  4. Actualiza snapshot en /opt/CAPEv2/conf/virtualbox.conf" -ForegroundColor Yellow
Write-Host "  5. Envía pafish64.exe de nuevo para el análisis post-hardening" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
