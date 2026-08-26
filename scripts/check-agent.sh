#!/bin/bash
# check-agent.sh — Verifica que el agente de CAPE responde en el Guest
#
# Uso: ./check-agent.sh [IP_GUEST] [PUERTO]
# Ejemplo: ./check-agent.sh 192.168.56.101 8000

GUEST_IP="${1:-192.168.56.101}"
AGENT_PORT="${2:-8000}"
AGENT_URL="http://${GUEST_IP}:${AGENT_PORT}"

echo "================================================"
echo "  Verificación del Agente CAPE"
echo "  URL: ${AGENT_URL}"
echo "================================================"

# Comprobar conectividad básica
echo ""
echo "[1/3] Comprobando conectividad con el Guest..."
if ping -c 1 -W 2 "${GUEST_IP}" > /dev/null 2>&1; then
    echo "  ✓ El Guest responde al ping (${GUEST_IP})"
else
    echo "  ✗ ERROR: No hay conectividad con ${GUEST_IP}"
    echo "    Verifica que la VM está arrancada y la red Host-Only está configurada."
    exit 1
fi

# Comprobar que el agente responde
echo ""
echo "[2/3] Comprobando respuesta del agente..."
RESPONSE=$(curl -s --connect-timeout 5 "${AGENT_URL}" 2>&1)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    echo "  ✗ ERROR: El agente no responde en ${AGENT_URL}"
    echo "    Posibles causas:"
    echo "    - El agente (agent.pyw) no está en la carpeta de inicio de Windows"
    echo "    - Python no está instalado o no está en el PATH del Guest"
    echo "    - El Firewall de Windows está bloqueando el puerto ${AGENT_PORT}"
    exit 1
fi

echo "  ✓ El agente responde"
echo "  Respuesta: ${RESPONSE}"

# Comprobar privilegios de administrador
echo ""
echo "[3/3] Verificando privilegios de administrador..."
IS_ADMIN=$(echo "${RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('is_user_admin','unknown'))" 2>/dev/null)

if [ "${IS_ADMIN}" = "True" ] || [ "${IS_ADMIN}" = "true" ]; then
    echo "  ✓ El agente corre como Administrador (is_user_admin: true)"
    echo ""
    echo "================================================"
    echo "  ✓ El agente está listo para análisis"
    echo "================================================"
elif [ "${IS_ADMIN}" = "False" ] || [ "${IS_ADMIN}" = "false" ]; then
    echo "  ✗ ADVERTENCIA: El agente NO tiene privilegios de Administrador"
    echo "    El API Hooking puede fallar. Solución:"
    echo "    1. En el Guest, abre CMD como Administrador"
    echo "    2. Ejecuta: reg add \"HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System\" /v EnableLUA /t REG_DWORD /d 0 /f"
    echo "    3. Reinicia la VM"
    echo "    Referencia: docs/07-troubleshooting.md"
    exit 1
else
    echo "  ? No se pudo determinar el nivel de privilegios"
    echo "  Respuesta completa: ${RESPONSE}"
fi
