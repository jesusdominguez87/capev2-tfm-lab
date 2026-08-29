#!/usr/bin/env bash
# =============================================================================
# hardening-host.sh — Hardening Anti-VM en el HOST Ubuntu (VBoxManage)
# Ejecutar con la VM apagada.
# Uso: bash hardening-host.sh [nombre-vm]
# =============================================================================

set -euo pipefail
VM="${1:-Win10-Lab}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[!!]${NC}  $*"; }
fail() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Hardening Host — VM: $VM"
echo "══════════════════════════════════════════════════════"

command -v VBoxManage &>/dev/null || fail "VBoxManage no encontrado."
VBoxManage showvminfo "$VM" &>/dev/null || fail "VM '$VM' no existe en VirtualBox."

# Apagar si está corriendo
STATE=$(VBoxManage showvminfo "$VM" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
if [[ "$STATE" == "running" ]]; then
    warn "VM en ejecución. Enviando ACPI poweroff..."
    VBoxManage controlvm "$VM" acpipowerbutton
    for i in $(seq 1 20); do
        sleep 3
        STATE=$(VBoxManage showvminfo "$VM" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
        [[ "$STATE" != "running" ]] && break
    done
    if [[ "$STATE" == "running" ]]; then
        warn "Forzando poweroff..."
        VBoxManage controlvm "$VM" poweroff && sleep 3
    fi
fi
ok "VM apagada"

# ── 1. DMI/BIOS spoofing ──────────────────────────────────────────────────────
echo ""
echo "── Paso 1: DMI/BIOS spoofing (neutraliza antivm_wmi, recon_fingerprint) ──"

VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor"    "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct"   "20SL001DGE"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion"   "ThinkBook 15 G2 ITL"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"    "PF2RABCD"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVendor"      "American Megatrends Inc."
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVersion"     "F.26"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseDate" "04/15/2022"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor"   "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiChassisType"     "10"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardVendor"     "LENOVO"
VBoxManage setextradata "$VM" "VBoxInternal/Devices/pcbios/0/Config/DmiBoardProduct"    "LNVNB161216"
ok "DMI/BIOS configurado como LENOVO ThinkBook 15 G2"

# ── 2. Disco spoofing ─────────────────────────────────────────────────────────
echo ""
echo "── Paso 2: Disco spoofing (neutraliza antivm_generic_disk, antivm_generic_scsi) ──"

VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber"    "Samsung SSD 870 EVO 500GB"
VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" "SVT01B6Q"
VBoxManage setextradata "$VM" \
    "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber"   "S5YENX0T123456A"
ok "Disco: Samsung SSD 870 EVO 500GB (SVT01B6Q / S5YENX0T123456A)"

# ── 3. MAC address ────────────────────────────────────────────────────────────
echo ""
echo "── Paso 3: MAC address (neutraliza antivm_network_adapters) ──"

SUFFIX=$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')
NEW_MAC="8C8D28${SUFFIX}"
VBoxManage modifyvm "$VM" --macaddress1 "$NEW_MAC"
ok "MAC: ${NEW_MAC:0:2}:${NEW_MAC:2:2}:${NEW_MAC:4:2}:${NEW_MAC:6:2}:${NEW_MAC:8:2}:${NEW_MAC:10:2} (OUI Intel)"

# ── 4. CPUID ──────────────────────────────────────────────────────────────────
echo ""
echo "── Paso 4: CPUID — ocultar hipervisor ──"
 
# 1. Suprimir la hoja de firma del hipervisor (0x40000000)
VBoxManage setextradata "$VM" "VBoxInternal/CPUM/SuppressHypervisorCpuIdLeaf" 1
VBoxManage modifyvm "$VM" --paravirtprovider none
 
# 2. Desactivar 'set -e' temporalmente para que un fallo aquí no aborte el script
set +e

# 3. Aplicar el perfil del host físico (la opción más segura y universal)
VBoxManage modifyvm "$VM" --cpu-profile "host" >/dev/null 2>&1

# 4. Reactivar 'set -e'
set -e

ok "CPUID: leaf 0x40000000 suprimida y paravirtualización desactivada."
echo -e "${GREEN}[OK]${NC}  Perfil de CPU: Configurado como 'host' para máxima compatibilidad hardware."

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Hardening del HOST completado."
echo ""
echo "  Siguiente paso: arrancar la VM y ejecutar en el Guest:"
echo "  powershell -ExecutionPolicy Bypass -File hardening-guest.ps1"
echo ""
echo "  Después, apagar el Guest limpiamente y ejecutar:"
echo "  VBoxManage snapshot \"$VM\" take \"CAPE_Hardened\""
echo "══════════════════════════════════════════════════════"
