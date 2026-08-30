# CAPEv2 TFM Lab — Hardening de Sandbox para Análisis de Malware Evasivo

> **Trabajo Fin de Máster** · Campus Internacional de Ciberseguridad / UCAM  
> Autor: Jesús Domínguez Bueno

Este repositorio documenta de forma reproducible el despliegue, configuración y endurecimiento de un entorno de análisis dinámico basado en **CAPEv2** sobre Ubuntu Linux + VirtualBox + Windows 10 Guest.

El objetivo es que cualquier investigador o alumno pueda replicar el laboratorio desde cero, comprender las decisiones técnicas tomadas y estudiar el impacto del hardening Anti-VM sobre la extracción de IoCs.

---

## 🗂️ Estructura del repositorio

```
capev2-tfm-lab/
├── docs/
│   ├── 01-arquitectura.md          # Topología de red y componentes
│   ├── 02-setup-red-host-only.md   # Configuración de la red Host-Only en VirtualBox
│   ├── 03-setup-windows10.md       # Preparación del Guest Windows 10
│   ├── 04-instalacion-capev2.md    # Instalación de CAPEv2 en Ubuntu
│   ├── 05-configuracion-cape.md    # Ficheros de configuración clave
│   ├── 06-snapshot.md              # Creación del snapshot base
│   ├── 07-troubleshooting.md       # Errores comunes y soluciones
│   └── 08-analisis-pafish.md       # Envío de muestras y análisis de reportes
├── config/
│   ├── virtualbox.conf.example     # Plantilla de configuración del hipervisor
│   └── cuckoo.conf.example         # Plantilla de configuración principal de CAPE
├── reports/
│   ├── baseline/
│   │   └── 2_report_pafish64_pre-hardening.json  # Reporte CAPE — estado inicial
│   └── post-hardening/
│       └── (pendiente — se añadirá al completar el TFM)
├── scripts/
│   ├── check-agent.sh              # Verificar que el agente del Guest responde
│   └── start-cape-manual.sh        # Arrancar los servicios de CAPE manualmente
└── samples/
    └── README.md                   # Cómo obtener PAFish (no se hostea malware aquí)
```

---

## 🏗️ Arquitectura del laboratorio

```
┌─────────────────────────────────────────────────────────────────┐
│                    HOST — Ubuntu Linux 22.04                    │
│                                                                 │
│  ┌─────────────────────┐      ┌─────────────────────────────┐   │
│  │   Orquestador CAPE  │      │   VirtualBox Hypervisor     │   │
│  │  IP: 192.168.56.1   │      │                             │   │
│  │  ResultServer: 2042 │      │  ┌───────────────────────┐  │   │
│  │  Web UI:      8000  │◄────►│  │  Guest — Windows 10   │  │   │
│  └─────────────────────┘      │  │  IP: 192.168.56.101   │  │   │
│                               │  │  Agent: TCP 8000      │  │   │
│         vboxnet0              │  │  Snapshot: CAPE_Limpio│  │   │
│    192.168.56.0/24            │  └───────────────────────┘  │   │
│                               └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Flujo de análisis:**
1. El usuario sube una muestra a la Web UI de CAPE (`http://localhost:8000`)
2. CAPE restaura el snapshot `CAPE_Limpio` en VirtualBox
3. El orquestador envía la muestra al agente del Guest (TCP 8000)
4. El agente inyecta el monitor de API Hooking en el proceso malicioso
5. Los logs de comportamiento se envían al ResultServer (TCP 2042)
6. Al finalizar el análisis, CAPE genera el reporte JSON con IoCs

---

## ⚡ Prerrequisitos

| Componente | Versión usada |
|---|---|
| SO Host | Ubuntu 22.04 LTS |
| Hipervisor | VirtualBox (última versión estable) |
| SO Guest | Windows 10 x64 |
| CAPEv2 | Instalado vía `cape2.sh` (rama `master`) |
| Python (Guest) | 3.8.10 (32-bit) |
| Muestra de prueba | PAFish v0.3.6 (`pafish64.exe`) |

**Hardware mínimo recomendado:**
- CPU con soporte VT-x/AMD-V habilitado en BIOS
- 8 GB RAM (4 GB para el host, 4 GB asignables al Guest)
- 80 GB de disco libre en la partición donde resida `/opt`

---

## 🚀 Guía de inicio rápido

Sigue los documentos en orden:

1. [Arquitectura y componentes](docs/01-arquitectura.md)
2. [Configurar la red Host-Only](docs/02-setup-red-host-only.md)
3. [Preparar el Guest Windows 10](docs/03-setup-windows10.md)
4. [Instalar CAPEv2 en Ubuntu](docs/04-instalacion-capev2.md)
5. [Configurar los ficheros de CAPE](docs/05-configuracion-cape.md)
6. [Crear el Snapshot base](docs/06-snapshot.md)
7. [Solución de problemas comunes](docs/07-troubleshooting.md)
8. [Enviar muestras y analizar reportes](docs/08-analisis-pafish.md)
9. [Hardening y resultados](docs/07-troubleshooting.md)
10. [Conclusiones Finales](docs/08-analisis-pafish.md)

---

## 📊 Resultados del baseline (pre-hardening)

El baseline real de `pafish64.exe`, ejecutado sobre el entorno sin ninguna medida de hardening aplicada (Guest Additions instaladas, sin spoofing de MAC/DMI/BIOS/disco), produjo estos resultados:

| Métrica                  | Valor                              |
| ------------------------- | ----------------------------------- |
| Duración del análisis     | **238 segundos** (ejecución completa) |
| Procesos capturados       | **1** (comportamiento completo)     |
| Malscore                  | **9.0 / 10**                        |
| Clasificación             | **Malicious**                       |
| Firmas disparadas         | **28 de 36**                        |

**Vectores de detección anti-VM confirmados:**

| Vector | Evidencia | Firma CAPE |
| --- | --- | --- |
| VirtualBox Guest Additions | 17 archivos (`vboxdisp.dll`, `VBoxTray.exe`, `VBoxMouse.sys`, etc.) + ventana `VBoxTrayToolWndClass` activa | `antivm_vbox_files`, `antivm_vbox_window`, `antivm_vbox_provname` |
| Consultas WMI (fabricante/modelo) | Llamada a `Win32_ComputerSystem`/`Win32_BIOS` | `antivm_wmi` |
| Identificador de disco | Cadena `VBOX HARDDISK` vía SCSI + acceso directo al disco físico | `antivm_generic_disk`, `antivm_generic_scsi`, `physical_drive_access` |
| Dirección MAC | Prefijo `08:00:27` (OUI de VirtualBox) | `antivm_network_adapters` |
| Registro BIOS | Clave `HKLM\HARDWARE\DESCRIPTION\System\SystemBiosDate` sin spoofear | `recon_fingerprint` |

Adicionalmente, PAFish detectó y restauró (*unhooked*) 11 funciones WMI (`IWbemServices_*`) instrumentadas por el propio agente de monitorización de CAPE (`antisandbox_unhook`), evidenciando evasión activa contra la instrumentación además de contra el hipervisor.

**Conclusión:** el entorno sin endurecer es trivialmente identificable como una máquina virtual VirtualBox por múltiples vías independientes (archivos, registro, WMI, disco, red). El análisis dinámico se ejecuta con normalidad (PAFish no aborta la ejecución), pero cualquier muestra real con lógica de evasión condicional revelaría un comportamiento distinto —o nulo— frente al que mostraría en un entorno no detectado. Este baseline establece el punto de partida cuantitativo para medir el impacto de cada medida de hardening aplicada en las siguientes secciones.

El reporte completo está en [`reports/baseline/1_report_pafish64_pre-hardening.json`](reports/baseline/1_report_pafish64_pre-hardening.json).

---

## 📄 Publicación

Este repositorio complementa el TFM:

> *"Mejora del Análisis de Malware Mediante el Endurecimiento de Entornos de Análisis Dinámico (CAPEv2)"*  
> Jesús Domínguez Bueno — Campus Internacional de Ciberseguridad / UCAM

---

## ⚠️ Aviso

Este laboratorio está diseñado exclusivamente para investigación académica y formación en ciberseguridad en entornos controlados y aislados. No se hostean muestras de malware real en este repositorio.
