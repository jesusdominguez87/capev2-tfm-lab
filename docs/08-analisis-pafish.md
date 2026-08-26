# 08 — Análisis con PAFish: Baseline Pre-Hardening

PAFish (Paranoid Fish) es una herramienta de código abierto de demostración que simula el comportamiento evasivo del malware moderno. Realiza decenas de comprobaciones Anti-VM, Anti-Debug y Anti-Analysis para determinar si está corriendo dentro de una sandbox. Es la herramienta de benchmarking perfecta para medir el nivel de detección de nuestro entorno.

---

## Descargar PAFish

En Ubuntu:

```bash
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

El reporte completo está en [`reports/baseline/2_report_pafish64_pre-hardening.json`](../reports/baseline/2_report_pafish64_pre-hardening.json).

### Metadatos del análisis

| Campo | Valor |
|---|---|
| ID de análisis | 2 |
| Fecha | 2026-08-06 21:42:49 |
| Duración real | **20 segundos** |
| Timeout configurado | 120 segundos |
| Máquina | Win10-Lab (VirtualBox) |
| Ruta de red | none |

### Metadatos de la muestra

| Campo | Valor |
|---|---|
| Nombre | `pafish64.exe` |
| Tamaño | 121.344 bytes |
| Tipo | PE32+ executable (x86-64, console) |
| MD5 | `4b6229d1b32d7346cf4c8312a8bc7925` |
| SHA1 | `4d83e18a7e1650b4f9bb5e866ea4ad97a21522bd` |
| SHA256 | `ff24b9da6cddd77f8c19169134eb054130567825eee1008b5a32244e1028e76f` |

### Resultados de extracción

| Métrica | Valor | Interpretación |
|---|---|---|
| **Malscore** | **1.5 / 10** | Clasificado como "Clean" |
| **Malstatus** | **Clean** | No identificado como malware |
| **Procesos capturados** | **0** | Sin comportamiento registrado |
| **Payloads extraídos** | **0** | Sin desempaquetado |
| **Configs extraídas** | **0** | Sin configuración de C2 |
| **Actividad de red** | **Ninguna** | Sin IoCs de red |

### Firmas detectadas (análisis estático)

Estas firmas son de análisis **estático** (del binario en sí, no de su comportamiento), lo que confirma que el análisis dinámico fue completamente inútil:

| Severidad | Firma | Descripción |
|---|---|---|
| 2 | `antianalysis_tls_section` | Sección `.tls` presente (Thread Local Storage) |
| 2 | `pe_tls_callbacks` | Callbacks TLS que se ejecutan antes del entry point, usados por packers |
| 2 | `packer_entropy` | Alta entropía, probables datos cifrados o comprimidos |
| 3 | `binary_yara` | Múltiples reglas YARA activadas |

### TTPs detectadas (MITRE ATT&CK)

| TTP | Técnica | Firma |
|---|---|---|
| T1055 | Process Injection | `antianalysis_tls_section` |
| T1027 | Obfuscated Files or Information | `pe_tls_callbacks`, `packer_entropy` |
| T1027.002 | Software Packing | `packer_entropy` |

---

## Interpretación: ¿Por qué el análisis falló?

El dato más revelador no está en lo que el reporte contiene, sino en lo que le falta:

**Duración de 20 segundos vs. timeout de 120 segundos.**  
PAFish terminó su ejecución en solo 20 segundos, 100 segundos antes del timeout. Esto significa que PAFish detectó el entorno virtualizado, reportó sus hallazgos y se cerró voluntariamente. No hubo ejecución de payload malicioso porque no había payload que activar — PAFish simplemente se detuvo.

**0 procesos capturados.**  
El API Hooking del agente de CAPE no interceptó ninguna llamada a la API de Windows. Esto indica que PAFish se cerró tan rápidamente que el monitor no tuvo tiempo de registrar nada significativo, o que la inyección del monitor falló por alguna de las técnicas Anti-Injection de PAFish.

**Malscore 1.5 ("Clean").**  
Sin comportamiento dinámico, CAPE solo puede basarse en firmas estáticas del binario. Un ejecutable legítimo con alta entropía (como cualquier ejecutable comprimido o empaquetado) obtendría puntuaciones similares. El sistema de análisis dinámico fue completamente ciego.

### Comprobaciones de PAFish que detectaron el entorno

PAFish verifica docenas de artefactos de virtualización. En un entorno VirtualBox sin hardening, los vectores de detección más comunes son:

- **Drivers de VirtualBox:** `VBoxMouse.sys`, `VBoxGuest.sys`, presentes en el sistema de archivos del Guest
- **Claves de registro de VirtualBox:** Entradas en `HKLM\SOFTWARE\Oracle\VirtualBox Guest Additions`
- **CPUID:** La instrucción CPUID revela que el hipervisor es VirtualBox
- **Dirección MAC:** El prefijo `08:00:27` identifica el adaptador de red como de VirtualBox
- **Resolución de pantalla:** Las resoluciones típicas de VM (800x600, 1024x768) son artefactos conocidos
- **Falta de interacción humana:** No hay movimiento de ratón ni historial de ficheros recientes

---

## Qué sigue: el hardening Anti-VM

El objetivo del TFM es neutralizar el mayor número posible de estos vectores de detección para que PAFish (y por extensión, el malware real evasivo) no pueda distinguir la sandbox de una máquina física real.

Los resultados comparativos post-hardening se añadirán en [`reports/post-hardening/`](../reports/post-hardening/) al completar el TFM.

**Métricas objetivo post-hardening:**
- Duración del análisis: próxima al timeout configurado (120s)
- Procesos capturados: > 0
- Malscore: significativamente superior a 1.5
- IoCs de red: captura de conexiones a C2 simulados
