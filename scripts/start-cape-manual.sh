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

if [ ! -d "${CAPE_DIR}" ]; then
    echo "ERROR: No se encuentra el directorio ${CAPE_DIR}"
    echo "¿Has ejecutado el instalador cape2.sh?"
    exit 1
fi

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
echo "Para detener todos los servicios: cierra las tres terminales."
