# Muestras de análisis

Este directorio no contiene muestras de malware ni ejecutables. Las muestras deben obtenerse directamente de sus fuentes oficiales.

---

## PAFish (Paranoid Fish)

PAFish es la herramienta de benchmarking usada en este TFM. Es una herramienta de demostración inofensiva que verifica si el entorno es una sandbox.

**Descarga oficial:**

```bash
# Versión de 32 bits
wget https://github.com/a0rtega/pafish/releases/download/v0.3.6/pafish.exe

# Versión de 64 bits (usada en este TFM como pafish64.exe)
# Disponible en la misma release de GitHub
```

**Repositorio oficial:** https://github.com/a0rtega/pafish  
**Versión usada en el TFM:** v0.3.6

**Hashes de la muestra usada en el TFM (pafish64.exe):**

| Algoritmo | Hash |
|---|---|
| MD5 | `4b6229d1b32d7346cf4c8312a8bc7925` |
| SHA1 | `4d83e18a7e1650b4f9bb5e866ea4ad97a21522bd` |
| SHA256 | `ff24b9da6cddd77f8c19169134eb054130567825eee1008b5a32244e1028e76f` |

Verifica los hashes después de descargar para asegurarte de que el fichero es el correcto:

```bash
md5sum pafish64.exe
sha256sum pafish64.exe
```

---

## Aviso legal

Este repositorio está diseñado para investigación académica en entornos controlados. No se hostean ni distribuyen muestras de malware real. Cualquier muestra de malware real que se use en el laboratorio debe obtenerse a través de repositorios de inteligencia de amenazas con los permisos y el contexto legal apropiados (MalwareBazaar, VirusTotal Intelligence, etc.).
