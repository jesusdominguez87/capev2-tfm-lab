# 01 — Arquitectura y Componentes del Laboratorio

## Visión general

El laboratorio implementa un paradigma **Out-of-Band** de análisis dinámico: el código malicioso se ejecuta en un entorno completamente aislado (Guest), mientras que todos los componentes de monitorización y orquestación residen en el Host, fuera del alcance del malware.

Esta separación es crítica: si el malware pudiera acceder o detectar el orquestador, modificaría su comportamiento y el análisis sería inútil.

---

## Componentes

### Host — Ubuntu Linux 22.04

El Host actúa como **centro de mando** del laboratorio. Aloja:

**Orquestador CAPEv2**  
El núcleo de CAPE gestiona el ciclo de vida completo de cada análisis:
- Recibe las muestras a través de la Web UI o la API REST
- Ordena a VirtualBox que restaure el snapshot limpio
- Envía la muestra al agente del Guest
- Recoge los resultados a través del ResultServer
- Genera el reporte final (JSON) con IoCs y firmas YARA

**ResultServer (TCP 2042)**  
Servicio de escucha pasivo en el Host. El agente del Guest le envía de forma asíncrona los volcados de memoria, las llamadas a la API registradas y los ficheros que el malware genera o modifica (*dropped files*). El ResultServer los persiste en disco antes de que la VM sea destruida.

**Web UI (TCP 8000)**  
Interfaz web de CAPE, levantada con Django. Permite subir muestras, configurar opciones de análisis, consultar reportes históricos y visualizar los IoCs extraídos.

**VirtualBox**  
Hipervisor de tipo 2 que gestiona el Guest de Windows 10. CAPE se comunica con él mediante la herramienta de línea de comandos `VBoxManage`, que permite restaurar snapshots, iniciar/detener la VM y consultar su estado.

---

### Guest — Windows 10 x64

El Guest actúa como **zona de detonación**. Su configuración es deliberadamente vulnerable (sin antivirus, sin UAC, con el agente ejecutándose como Administrador) para maximizar la visibilidad del comportamiento del malware.

**Agente de monitorización (`agent.pyw`)**  
Servidor HTTP ligero escrito en Python que escucha en el puerto 8000 del Guest. Al recibir una muestra del orquestador:
1. La escribe en disco
2. La ejecuta en el contexto del sistema
3. Inyecta una DLL de monitorización en el proceso del malware (*API Hooking*)
4. Intercepta y registra todas las llamadas a la API nativa de Windows (CreateProcess, VirtualAlloc, RegSetValueEx, etc.)
5. Envía los logs al ResultServer del Host

**Snapshot base (`CAPE_Limpio`)**  
Instantánea en memoria del Guest con el SO completamente cargado, la CPU estabilizada y el agente en espera. CAPE restaura este snapshot antes de cada análisis, garantizando que todas las muestras se ejecuten sobre un estado idéntico y limpio.

---

## Topología de red

Se utiliza una red **Host-Only** (`vboxnet0`) en el rango `192.168.56.0/24`. Esta configuración:

- **Aísla el Guest de la LAN física**: el malware no puede propagarse lateralmente a otros equipos de la red
- **Mantiene la conectividad Host↔Guest**: necesaria para que CAPE pueda enviar muestras y recibir resultados
- **Permite la captura de tráfico**: todo el tráfico de red del Guest pasa por el Host, donde CAPE lo captura en formato PCAP para análisis posterior de IoCs de red (dominios C2, peticiones DNS, etc.)

| Nodo | IP | Puertos relevantes |
|---|---|---|
| Host (Ubuntu) | `192.168.56.1` | 2042 (ResultServer), 8000 (Web UI) |
| Guest (Windows 10) | `192.168.56.101` | 8000 (Agente) |

---

## Flujo completo de un análisis

```
Usuario
  │
  │ 1. Sube pafish64.exe a http://localhost:8000
  ▼
Web UI (Host:8000)
  │
  │ 2. Encola el análisis en la BD de CAPE
  ▼
Orquestador (cuckoo.py)
  │
  │ 3. Restaura snapshot "CAPE_Limpio" via VBoxManage
  ├──► VirtualBox ──► Guest arranca desde estado limpio
  │
  │ 4. Envía la muestra al agente
  ├──► Agent (Guest:8000) recibe pafish64.exe
  │         │
  │         │ 5. Ejecuta la muestra e inyecta el monitor
  │         ├──► pafish64.exe corre en el Guest
  │         │
  │         │ 6. Envía logs al ResultServer
  │         └──► ResultServer (Host:2042) persiste datos
  │
  │ 7. Fin del timeout (120s por defecto)
  ├──► VirtualBox apaga y destruye el estado sucio del Guest
  │
  │ 8. El procesador (process.py) genera el reporte
  ▼
reports/2/report.json  ◄── IoCs, firmas, comportamiento, YARA
```

---

## Por qué VirtualBox y no KVM/QEMU

VirtualBox fue elegido por su madurez en la integración con CAPEv2 y la disponibilidad de módulos de Python (`vboxapi`) que CAPE usa nativamente. KVM ofrece mayor rendimiento y menor huella de detección por parte del malware, pero requiere una configuración adicional de los módulos de maquinería de CAPE. La extensión del laboratorio a KVM es un trabajo futuro contemplado en el TFM.

Continúa con: [02 — Configurar la red Host-Only →](02-setup-red-host-only.md)
