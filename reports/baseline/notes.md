# Baseline (pre-hardening)

Entorno sin ninguna medida de hardening aplicada:
- Guest Additions instaladas (sin desinstalar)
- Sin spoofing de MAC (MAC por defecto de VirtualBox, prefijo 08:00:27)
- Sin spoofing de DMI/BIOS ni de disco (Model/Firmware/Serial genéricos VBOX)

Resultado: malscore 9.0/10, "Malicious", 238s, 36 firmas disparadas, 27 detecciones.
Ver la tabla completa de vectores en el README principal.
