# Pablo Face — esfera Garmin compilada en la nube

Repositorio privado del proyecto Garmin.

- `source/` — código Monkey C de la esfera (hora, fecha, pulso, pasos con anillo de objetivo, batería; modo bajo consumo AMOLED).
- `.github/workflows/compilar-garmin.yml` — descarga el SDK oficial 9.3.0 y los archivos de dispositivos con tu cuenta Garmin (secretos `GARMIN_USERNAME`, `GARMIN_PASSWORD` y `CLAVE_FIRMA`), compila para todos los relojes compatibles y guarda `build/PabloFace.iq`.
- La clave de firma NO está en el repo: se deriva en cada compilación del secreto `CLAVE_FIRMA` (`scripts/derive_key.py`). Usa siempre la misma frase.

Instalación sin cable: subir `build/PabloFace.iq` como **app beta** en https://apps.garmin.com/developer y añadirla al reloj desde la app Connect IQ del móvil.

