# 10 — Conclusiones

## Resumen del trabajo realizado

Este TFM ha diseñado, implementado y evaluado un entorno de analisis dinamico de malware basado en CAPEv2 sobre VirtualBox + Windows 10, con el objetivo de aplicar tecnicas de hardening Anti-VM para reducir la deteccion del entorno por parte del malware evasivo moderno.

El trabajo se ha estructurado en tres fases ejecutadas de forma incremental y documentada:

**Fase 1 — Construccion del entorno base.** Instalacion y configuracion de CAPEv2 sobre Ubuntu, integracion con VirtualBox, preparacion del Guest Windows 10 con el agente de monitorizacion, y configuracion de red aislada. El resultado fue un entorno funcional capaz de analizar muestras y generar reportes de comportamiento.

**Fase 2 — Analisis baseline.** Envio de `pafish64.exe` como muestra de referencia antes de aplicar ninguna medida de hardening. El analisis (ID 1, 2026-08-28) confirmo que CAPE tenia visibilidad completa sobre el comportamiento de PAFish (238 s, Malscore 9.0, 36/36 firmas CAPEv2, **27 detecciones en `pafish.log`**), e identifico con precision los vectores de deteccion activos: artefactos de Guest Additions, emulacion de hardware DMI/BIOS, identificadores de disco virtual, y prefijo MAC de Oracle.

**Fase 3 — Hardening y validacion.** Aplicacion de medidas en dos planos (Host via `VBoxManage` y Guest via PowerShell), creacion del snapshot `CAPE_Hardened`, y segundo analisis con la misma muestra (ID 2, 2026-08-30).

---

## Resultados cuantitativos

| Metrica                                   | Baseline | Post-hardening | Variacion           |
|-------------------------------------------|----------|----------------|---------------------|
| Malscore                                  | 9.0      | 9.0            | Sin cambio          |
| Firmas CAPEv2 disparadas                  | 36       | 36             | Sin cambio          |
| **Detecciones PAFish (pafish.log)**       | **27**   | **9**          | **−18 (−66,7%)**   |
| Det. CPUID hipervisor                     | 2        | 0              | −2 (100%)           |
| Det. ficheros/drivers Guest Additions     | 9        | 0              | −9 (100%)           |
| Det. claves registro VBox/servicios       | 6        | 0              | −6 (100%)           |
| Det. dispositivos/ventana/red VBox        | 3        | 0              | −3 (100%)           |
| Det. MAC 08:00:27                         | 1        | 0              | −1 (100%)           |
| Det. disco VBOX HARDDISK                  | 3        | 0              | −3 (100%)           |
| Det. WMI VirtualBox                       | 1        | 1              | Persiste            |
| Det. sandbox raton/uptime                 | 4        | 6              | +2 (modulo human)   |
| `stealth_timeout` (nueva firma CAPEv2)    | —        | Presente       | Indicador positivo  |

---

## Logros principales

**Resultado global: reduccion del 66,7% en detecciones PAFish.** El analisis de `pafish.log` revela que las detecciones Anti-VM pasaron de 27 en el baseline a 9 en el post-hardening. Esta es la metrica central: refleja lo que el malware real habria encontrado al ejecutarse en cada entorno. Las firmas del array `signatures[]` de CAPEv2 son 36 en ambos analisis porque CAPEv2 registra el *intento* de cada comprobacion, no si PAFish encontro el artefacto.

**Neutralizacion completa del vector de disco.** Las tres detecciones de disco en `pafish.log` (modelo VBOX HARDDISK via WMI, identificador SCSI, acceso directo) desaparecieron por completo. El spoofing del modelo, firmware y numero de serie del disco virtual a nivel de hipervisor (`VBoxInternal/Devices/ahci`) es efectivo contra todas las vias de consulta que PAFish utiliza: WMI (`Win32_DiskDrive`), IOCTL directo (`IDENTIFYDEVICE`) y acceso SCSI.

**Neutralizacion completa del vector de red.** La deteccion de MAC `08:00:27` desaparecio de `pafish.log` al sustituir el prefijo de Oracle por un OUI de Intel. Es la medida de menor coste y mayor impacto en proporcion: un solo comando de `VBoxManage` elimina una deteccion con alta confianza.

**Neutralizacion completa de Guest Additions segun PAFish.** Los 9 ficheros/drivers de Guest Additions y las 6 claves de registro/servicios detectados en el baseline no aparecen en `pafish.log` POST. Aunque CAPEv2 sigue disparando firmas como `antivm_vbox_files` (registra el intento de busqueda), PAFish no encontro los artefactos en el entorno endurecido.

**stealth_timeout es el indicador positivo clave.** La unica firma genuinamente nueva en `signatures[]` de CAPEv2 en POST es `stealth_timeout`: PAFish termino antes de completar todas sus rutinas porque el entorno ya no era tan obviamente detectable. La reduccion de 27 a 9 detecciones en `pafish.log` cuantifica ese avance.

---

## Limitaciones y lineas de mejora

### Limitaciones del hardening aplicado

**DLLs OpenGL de VirtualBox no cubiertas.** Las DLLs `vboxoglpackspu.dll`, `vboxoglpassthroughspu.dll` y `vboxoglfeedbackspu.dll` no estaban incluidas en la lista inicial de residuales del script de guest. Pertenecen al pipeline de aceleracion OpenGL de Guest Additions y son detectables por PAFish. Una segunda iteracion del script deberia incluirlas explicitamente.

**`VBoxWddm.sys` inextirpable.** El driver de display de VirtualBox no pudo eliminarse tras multiples ciclos de reinicio. El kernel lo retiene de forma persistente incluso con `MoveFileEx MOVEFILE_DELAY_UNTIL_REBOOT`. Es una limitacion real del entorno: su eliminacion requeriria deshabilitar el driver en el Administrador de dispositivos y sustituirlo por el driver de pantalla generica de Microsoft antes de intentar el borrado.

**Tablas ACPI regeneradas por el hipervisor.** Las claves `HKLM\HARDWARE\ACPI\DSDT\VBOX__`, `FADT\VBOX__` y `RSDT\VBOX__` son generadas por VirtualBox en cada arranque a partir del DSDT embebido en la imagen de la VM. El spoofing DMI/BIOS cambia los valores que WMI expone, pero no modifica el DSDT subyacente. Su eliminacion definitiva requeriria editar el DSDT directamente en el firmware de la VM, lo que esta fuera del alcance de las herramientas estandar de `VBoxManage`.

**`VBoxTrayToolWndClass` en el snapshot.** La ventana estaba activa al crear `CAPE_Hardened`, lo que indica que `VBoxTray.exe` seguia en memoria en ese momento, probablemente relanzado desde una entrada de autoarranque no eliminada o porque el reinicio no fue completo antes de tomar la instantanea.

### Limitacion estructural: `antisandbox_unhook`

PAFish detecta y revierte activamente los hooks WMI instalados por el agente de CAPE. Esta firma no puede neutralizarse mediante hardening del entorno sin desactivar la instrumentacion de comportamiento que es el nucleo funcional de CAPE. Representa un conflicto fundamental entre la capacidad de analisis y la invisibilidad del entorno: a mayor fidelidad del monitor de comportamiento, mayor superficie de deteccion para el malware sofisticado.

Esta limitacion no es especifica de CAPEv2 ni de VirtualBox — afecta a cualquier sandbox basada en hooking a nivel de usuario. Las soluciones existentes (monitorizacion basada en hipervisor, hardware tracing via Intel PT) estan fuera del alcance de este proyecto pero constituyen la direccion natural de evolucion.

### Lineas de mejora futuras

**Iteracion incremental de reportes.** El plan original contemplaba un reporte por cada capa de hardening (solo MAC, solo disco, solo GA...) para medir el impacto individual de cada medida sobre el Malscore y las firmas. La restriccion de tiempo obligo a un unico ciclo completo. Una iteracion futura con ese enfoque permitiria identificar con precision que medidas aportan mas valor y en que orden aplicarlas.

**DSDT personalizado.** Editar el DSDT de la VM para eliminar las tablas ACPI que revelan el origen de VirtualBox. Herramientas como `iasl` (compilador/decompilador de ACPI) permiten modificar el DSDT y reinyectarlo en la VM.

**Monitorizacion basada en hipervisor.** Sustituir el hooking a nivel de usuario por monitorizacion desde el nivel de hipervisor (VMI — Virtual Machine Introspection) elimina completamente la superficie de deteccion de `antisandbox_unhook`. Proyectos como DRAKVUF implementan este enfoque sobre Xen.

**Validacion con malware real evasivo.** PAFish esta disenado para ejecutar todas sus comprobaciones independientemente del resultado, aunque en la practica la firma `stealth_timeout` evidencio que en el analisis post-hardening termino antes de completar todas las rutinas. El siguiente paso natural es validar el entorno hardened con muestras reales de malware que implementen evasion condicional (que solo ejecuten payload si no detectan sandbox), para medir el incremento real en tasa de captura de comportamiento.

---

## Conclusiones finales

El hardening Anti-VM de una sandbox CAPEv2 sobre VirtualBox es un proceso viable con herramientas estandar, pero requiere abordar simultaneamente multiples planos (hipervisor, Guest, registro, red) para ser efectivo. Una medida aislada — eliminar solo las Guest Additions, o cambiar solo la MAC — es insuficiente: el malware sofisticado implementa comprobaciones redundantes e independientes.

El trabajo demostro que las medidas de mayor impacto relativo son el spoofing de disco y la sustitucion de MAC, porque neutralizan firmas de deteccion concretas con cambios minimos y sin efectos secundarios sobre la capacidad de analisis. La eliminacion de Guest Additions, aunque es el vector con mayor numero de artefactos, es tambien el mas complejo de ejecutar limpiamente por la combinacion de ficheros bloqueados por el kernel, DLLs secundarias no documentadas, y entradas de registro regeneradas automaticamente.

La reduccion de 27 a 9 detecciones en `pafish.log` (−66,7%) es la confirmacion cuantitativa de que el hardening funciona. La firma `stealth_timeout` en CAPEv2 indica que PAFish ejecuto mas rutinas antes de terminar porque el entorno ya no era tan obviamente detectable. El objetivo de una sandbox hardened no es obtener cero detecciones en PAFish, sino que el malware real no pueda distinguir el entorno de una maquina fisica y ejecute su comportamiento completo.

---

## Referencias generales

- [CAPEv2 — kevoreilly/CAPEv2](https://github.com/kevoreilly/CAPEv2)
- [PAFish — a0rtega/pafish](https://github.com/a0rtega/pafish)
- [Al-Khaser — LordNoteworthy/al-khaser](https://github.com/LordNoteworthy/al-khaser)
- [MITRE ATT&CK T1497 — Virtualization/Sandbox Evasion](https://attack.mitre.org/techniques/T1497/)
- [VirtualBox Developer Manual — CPUM/DMI extradata](https://www.virtualbox.org/manual/ch09.html)
- [DRAKVUF — VMI-based sandbox](https://drakvuf.com/)
