# Pablo Face — esfera Garmin compilada en la nube

Repositorio privado del proyecto Garmin.

- `source/` — código Monkey C de la esfera (hora, fecha, pulso, pasos con anillo de objetivo, batería; modo bajo consumo AMOLED).
- `.github/workflows/compilar-garmin.yml` — descarga el SDK oficial 9.3.0 y los archivos de dispositivos con tu cuenta Garmin (secretos `GARMIN_USERNAME` y `GARMIN_PASSWORD`), compila para todos los relojes compatibles y guarda `build/PabloFace.iq`.
- `keys/developer_key.der` — clave de firma de la app. Repo privado: no la compartas. Debe ser siempre la misma para poder publicar actualizaciones.

Instalación sin cable: subir `build/PabloFace.iq` como **app beta** en https://apps.garmin.com/developer y añadirla al reloj desde la app Connect IQ del móvil.

<!-- build 2026-11-20T09:42:37Z -->
