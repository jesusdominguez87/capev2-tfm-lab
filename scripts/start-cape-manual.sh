#!/bin/bash
# start-cape-manual.sh — Arranca los tres servicios de CAPE en terminales separadas
#
# Uso: ./start-cape-manual.sh
#
# Abre tres ventanas de gnome-terminal con los servicios de CAPE.
# Requiere gnome-terminal. Si usas otro emulador, ajusta el comando.
#
# Alternativa: ejecuta manualmente cada bloque en una pestaña de terminal.

CAPE_DIR="/opt/CAPEv2"
POETRY="/etc/poetry/bin/poetry"
VBOXNET_IF="vboxnet0"
VBOXNET_IP="192.168.56.1/24"

if [ ! -d "${CAPE_DIR}" ]; then
    echo "ERROR: No se encuentra el directorio ${CAPE_DIR}"
    echo "¿Has ejecutado el instalador cape2.sh?"
    exit 1
fi

# --- Comprobación de la red Host-Only (ResultServer) ---
# vboxnet0 puede quedar en estado DOWN tras reiniciar el host, aunque
# conserve la IP asignada. Sin esto, el agente del Guest es inalcanzable
# aunque esté corriendo (timeout, no "connection refused").
# Ver docs/07-troubleshooting.md — Problema 6.
echo "Comprobando la interfaz ${VBOXNET_IF}..."

if ! ip link show "${VBOXNET_IF}" > /dev/null 2>&1; then
    echo "ERROR: La interfaz ${VBOXNET_IF} no existe."
    echo "¿Está VirtualBox instalado y la red Host-Only configurada? (docs/02-setup-red-host-only.md)"
    exit 1
fi

IF_STATE=$(ip -o link show "${VBOXNET_IF}" | awk '{print $9}')
if [ "${IF_STATE}" != "UP" ] && [ "${IF_STATE}" != "UNKNOWN" ]; then
    echo "[!] ${VBOXNET_IF} está en estado ${IF_STATE}. Levantando la interfaz..."
    sudo ip link set "${VBOXNET_IF}" up
fi

if ! ip addr show "${VBOXNET_IF}" | grep -q "192.168.56.1/24"; then
    echo "[!] ${VBOXNET_IF} no tiene la IP ${VBOXNET_IP}. Asignándola..."
    sudo ip addr add "${VBOXNET_IP}" dev "${VBOXNET_IF}"
fi

echo "[+] ${VBOXNET_IF} operativa."
echo ""
echo "Sugerencia: ejecuta scripts/setup-vboxnet0.sh una sola vez para automatizar"
echo "esto en cada arranque del host y no depender de este script."
echo ""

echo "Arrancando servicios de CAPEv2..."
echo ""
echo "Se abrirán 3 terminales:"
echo "  1. Núcleo (cuckoo.py) — controla VirtualBox"
echo "  2. Procesador (process.py) — genera los reportes"
echo "  3. Servidor web (manage.py) — interfaz en http://localhost:8000"
echo ""

# Terminal 1: Núcleo
gnome-terminal --title="CAPE - Núcleo" -- bash -c "
    echo '=== CAPE NÚCLEO (cuckoo.py) ===';
    echo 'Busca: Loaded 1 machine.';
    echo '';
    cd ${CAPE_DIR};
    ${POETRY} run python cuckoo.py;
    echo 'El proceso terminó. Pulsa Enter para cerrar.';
    read
" &

sleep 1

# Terminal 2: Procesador
gnome-terminal --title="CAPE - Procesador" -- bash -c "
    echo '=== CAPE PROCESADOR (process.py) ===';
    echo '';
    cd ${CAPE_DIR};
    ${POETRY} run python utils/process.py -p 1;
    echo 'El proceso terminó. Pulsa Enter para cerrar.';
    read
" &

sleep 1

# Terminal 3: Servidor web
gnome-terminal --title="CAPE - Web UI" -- bash -c "
    echo '=== CAPE WEB UI (manage.py) ===';
    echo 'Accede en: http://localhost:8000';
    echo '';
    cd ${CAPE_DIR}/web;
    ${POETRY} run python manage.py runserver 0.0.0.0:8000;
    echo 'El proceso terminó. Pulsa Enter para cerrar.';
    read
" &

echo "Servicios arrancando..."
echo "Abre Firefox y navega a http://localhost:8000"
echo ""
echo "Para detener todos los servicios: cierra las tres terminales con Ctrl + C y despues Enter en cada una."
