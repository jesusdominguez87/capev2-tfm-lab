# 08 — Análisis con PAFish: Baseline Pre-Hardening

PAFish (Paranoid Fish) es una herramienta de código abierto de demostración que simula el comportamiento evasivo del malware moderno. Realiza decenas de comprobaciones Anti-VM, Anti-Debug y Anti-Analysis para determinar si está corriendo dentro de una sandbox. Es la herramienta de benchmarking perfecta para medir el nivel de detección de nuestro entorno.

---

## Descargar PAFish

En Ubuntu:

```
mkdir ~/muestras && cd ~/muestras
wget https://github.com/a0rtega/pafish/releases/download/v0.3.6/pafish.exe
# Versión de 64 bits (más representativa de malware moderno):
# pafish64.exe está en la misma release de GitHub
```
> PAFish es una herramienta de demostración inofensiva. No realiza ninguna acción maliciosa; solo verifica el entorno y reporta sus hallazgos.

---

## Enviar la muestra a CAPEv2

1. Abre Firefox en Ubuntu y ve a `http://localhost:8000`.
2. Haz clic en **Submit** (Enviar análisis) en el menú superior.
3. Selecciona el fichero `pafish64.exe`.
4. En las opciones de análisis:
  - **Machine:** selecciona `Win10-Lab`
  - **Timeout:** 120 segundos (por defecto)
  - **Package:** `exe`
5. Haz clic en **Analyze**.

CAPE realizará la siguiente secuencia automáticamente:

1. Restaura el snapshot `CAPE_Limpio` en VirtualBox
2. Arranca el Guest desde ese estado
3. Envía `pafish64.exe` al agente (TCP 8000)
4. El agente lo ejecuta e intenta inyectar el monitor
5. Espera el timeout o hasta que el proceso termine
6. Recoge los logs y genera el reporte

---

## Resultados del análisis baseline (pre-hardening)

El reporte completo está en [`reports/baseline/1_report_pafish64_pre-hardening.json`](../reports/baseline/1_report_pafish64_pre-hardening.json).

### Metadatos del análisis

| Campo               | Valor                  |
| ------------------- | ---------------------- |
| ID de análisis      | 1                      |
| Fecha               | 2026-08-28 11:09:40    |
| Duración real       | **238 segundos**       |
| Timeout configurado | 120 segundos*          |
| Máquina             | Win10-Lab (VirtualBox) |
| Ruta de red         | none                   |

\* *La duración real supera el timeout configurado porque incluye el tiempo de arranque/parada de la máquina y el procesamiento posterior; el proceso de PAFish se ejecutó y completó su comportamiento con normalidad dentro de la ventana de análisis.*

### Metadatos de la muestra

| Campo  | Valor                                                              |
| ------ | ------------------------------------------------------------------ |
| Nombre | `pafish64.exe`                                                     |
| Tamaño | 121.344 bytes                                                      |
| Tipo   | PE32+ executable (x86-64, console)                                 |
| MD5    | `4b6229d1b32d7346cf4c8312a8bc7925`                                 |
| SHA1   | `4d83e18a7e1650b4f9bb5e866ea4ad97a21522bd`                         |
| SHA256 | `ff24b9da6cddd77f8c19169134eb054130567825eee1008b5a32244e1028e76f` |

### Resultados de extracción

| Métrica                 | Valor                | Interpretación                          |
| ------------------------ | -------------------- | ---------------------------------------- |
| **Malscore**              | **9.0 / 10**          | Clasificado como "Malicious"             |
| **Malstatus**             | **Malicious**         | Comportamiento evasivo detectado         |
| **Procesos capturados**   | **1**                 | Comportamiento completo registrado       |
| **Firmas disparadas**     | **28 de 36**          | Amplia cobertura de técnicas Anti-VM/Anti-Analysis |
| **Actividad de red**      | Ninguna               | Esperado (PAFish no realiza C2)          |

### Firmas de comportamiento relevantes (análisis dinámico)

El API Hooking del agente capturó comportamiento completo. Estas son las firmas más relevantes desde el punto de vista de detección Anti-VM (se omiten firmas genéricas de comportamiento no relacionadas, como comprobaciones de idioma o TLS callbacks):

| Severidad | Firma                    | Descripción                                                        |
| --------- | ------------------------- | ------------------------------------------------------------------- |
| 3         | `antivm_vbox_files`        | Detecta VirtualBox por la presencia de 17 archivos de Guest Additions (`vboxdisp.dll`, `VBoxTray.exe`, `VBoxMouse.sys`, etc.) |
| 3         | `antivm_vbox_window`       | Detecta VirtualBox por la ventana `VBoxTrayToolWndClass` activa    |
| 3         | `antivm_vbox_provname`     | Detecta VirtualBox mediante el truco `WNetGetProviderName`         |
| 3         | `antivm_wmi`                | Ejecuta consultas WMI (`Win32_ComputerSystem`/`Win32_BIOS`) usables para anti-virtualización |
| 3         | `antivm_generic_disk`       | Consulta información de disco para detección de virtualización     |
| 3         | `antivm_generic_scsi`       | Detecta virtualización mediante el identificador SCSI del disco    |
| 3         | `physical_drive_access`     | Accede directamente al disco físico                                |
| 3         | `recon_fingerprint`         | Recolecta huella del sistema vía `HKLM\HARDWARE\DESCRIPTION\System\SystemBiosDate` |
| 1         | `antivm_network_adapters`   | Consulta direcciones de adaptador de red (prefijo MAC `08:00:27` de VirtualBox) |
| 3         | `antisandbox_unhook`        | Detecta y restaura 11 funciones WMI (`IWbemServices_*`) previamente hookeadas por el agente de monitorización de CAPE |
| 3         | `binary_yara` / `procmem_yara` | Múltiples reglas YARA activadas sobre el binario y volcados de proceso |
| 2         | `packer_entropy`            | Alta entropía, probables datos cifrados o comprimidos              |

### TTPs detectadas (MITRE ATT&CK)

| TTP       | Técnica                                       | Firma(s)                                          |
| --------- | ---------------------------------------------- | -------------------------------------------------- |
| T1497     | Virtualization/Sandbox Evasion                  | `antivm_wmi`, `antivm_vbox_files`, `mouse_movement_detect` |
| T1082     | System Information Discovery                    | `antivm_wmi`, `recon_fingerprint`, `privilege_elevation_check` |
| T1012     | Query Registry                                  | `recon_fingerprint`, `antivm_vbox_keys`             |
| T1057     | Process Discovery                               | `antivm_vbox_files`, `enumerates_running_processes` |
| T1083     | File and Directory Discovery                    | `antivm_vbox_files`, `antivm_vbox_devices`          |
| T1047     | Windows Management Instrumentation               | `antivm_wmi`                                        |
| T1562 / T1562.001 | Impair Defenses / Disable or Modify Tools | `antisandbox_unhook`, `amsi_enumeration`            |
| T1542 / T1542.003 | Pre-OS Boot / Bootkit                     | `physical_drive_access`                             |
| T1027 / T1027.002 | Obfuscated Files or Information / Software Packing | `packer_entropy`, `pe_tls_callbacks`      |
| T1055     | Process Injection                               | `antianalysis_tls_section`, `pe_tls_callbacks`      |

---

## Interpretación: qué revela el baseline

El baseline confirma que, sin ninguna medida de hardening, **el entorno es identificable como VirtualBox por múltiples vías independientes y simultáneas**:

**Guest Additions como vector dominante.**
17 de los artefactos detectados provienen de un único origen: las VirtualBox Guest Additions instaladas en el Guest. Archivos (`vboxdisp.dll`, `VBoxTray.exe`, drivers `.sys`...) y una ventana activa (`VBoxTrayToolWndClass`) delatan el entorno sin que PAFish necesite ninguna técnica sofisticada — basta con listar `C:\Windows\System32`.

**WMI y disco como vectores secundarios pero robustos.**
Las consultas WMI a `Win32_BIOS`/`Win32_ComputerSystem` y el identificador SCSI del disco virtual (`VBOX HARDDISK`) son artefactos que persisten incluso si se retiran las Guest Additions, porque provienen de la emulación de hardware (BIOS/DMI) del propio hipervisor, no del software instalado en el Guest.

**Evasión activa contra la instrumentación.**
La firma `antisandbox_unhook` es especialmente relevante: PAFish no solo detecta el entorno, sino que **detecta y revierte activamente 11 hooks WMI** instalados por el propio agente de monitorización de CAPE. Esto confirma que la instrumentación en sí misma es un vector de detección adicional, no solo el hipervisor subyacente.

**Malscore 9.0 ("Malicious") con comportamiento completo capturado.**
A diferencia de un análisis fallido, aquí CAPE tuvo visibilidad total sobre el comportamiento de PAFish. El malscore alto no indica que PAFish sea dañino (es una herramienta de demostración inofensiva) — indica que **el conjunto de técnicas de evasión que ejecuta con éxito** es amplio, lo cual es exactamente el resultado esperado de un entorno sin endurecer y el punto de partida cuantitativo del TFM.

### Vectores de detección a neutralizar

En orden de prioridad según el número de artefactos que aportan:

1. **VirtualBox Guest Additions** (17 archivos + ventana activa) — desinstalación completa, sin residuos
2. **DMI/BIOS emulado** (fabricante, modelo, versión de BIOS reportados vía WMI) — spoofing a nivel de hipervisor
3. **Identificadores de disco** (modelo, firmware, número de serie SCSI/ATA) — spoofing a nivel de hipervisor
4. **Dirección MAC** (prefijo `08:00:27`) — regeneración/spoofing de MAC
5. **Claves de registro residuales** (`SystemBiosDate` y similares en `HKLM\HARDWARE\DESCRIPTION\System`) — se regeneran automáticamente desde la BIOS emulada al aplicar (2)

---

## Qué sigue: el hardening Anti-VM

El objetivo del TFM es neutralizar el mayor número posible de estos vectores de detección para que PAFish (y por extensión, el malware real evasivo) no pueda distinguir la sandbox de una máquina física real.

Los resultados comparativos post-hardening se documentan de forma incremental en [`reports/`](https://github.com/jesusdominguez87/capev2-tfm-lab/tree/main/reports), con una carpeta por cada capa de hardening aplicada (spoofing de MAC, DMI/BIOS y disco, retirada de Guest Additions...), permitiendo medir el impacto individual de cada medida sobre el malscore y las firmas disparadas.

**Métricas objetivo post-hardening:**

- Firmas de categoría `anti-vm` disparadas: reducción sustancial frente a las 8+ del baseline
- `antivm_vbox_files` / `antivm_vbox_window`: 0 artefactos tras la retirada de Guest Additions
- `antivm_wmi`, `antivm_generic_disk`, `antivm_generic_scsi`: sin disparo tras el spoofing de DMI/BIOS/disco
- `antivm_network_adapters`: sin disparo tras el spoofing de MAC
