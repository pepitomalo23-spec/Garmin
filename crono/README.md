# Crono pj.fire — cronómetro del Fenix 6X Pro conectado a pj.fire

App de reloj (Connect IQ, Monkey C) para el **Fenix 6X Pro** (280 × 280, Connect IQ 3.4, sin pantalla táctil).
Cronómetro manual con vueltas que guarda cada sesión en el reloj y la manda a pj.fire
(sección **GARMIN / CRONÓMETRO**) a través de la app Garmin Connect del móvil.

## Botones
| Botón | Preparado | En marcha | En pausa |
|---|---|---|---|
| START | empieza | pausa | sigue |
| BACK | sale de la app | marca vuelta | Guardar / Seguir / Descartar |
| UP mantenido (menú) | Registros · Sincronizar · Estado | + Salir (sigue contando) | igual |
| DOWN | registros del reloj | — | — |

## Cómo se sincroniza
1. Al guardar, el registro se escribe **primero en el reloj** (pendiente).
2. Si el móvil está conectado, se manda en seguida (`POST …/garmin-api/registros`).
3. El servidor responde con los ids que ha guardado (`confirmados`); solo esos pasan a «enviado».
4. Si falla (sin móvil, sin Internet, error), se queda pendiente y se reintenta: cada 30 s con la app abierta
   y cada 5 min en segundo plano aunque la app esté cerrada (lo mínimo que permite Garmin).
5. Si un envío se repite, el servidor no lo duplica (clave `user_id + id`).

El reloj guarda los últimos 40 registros; nunca borra uno pendiente.

## Tiempo real
El tiempo no sale de los repintados de pantalla: se guarda el momento de salida (`System.getTimer()` en ms y,
de respaldo, `Time.now()` en s) y se calcula lo transcurrido cada vez. Se guarda en la memoria del reloj a cada
pulsación: si sales de la app o se reinicia el reloj, al volver sigue en su punto.

## Clave
En pj.fire → Inicio → Garmin → **Crear clave**. Se pega una vez en Connect IQ (móvil) → Crono pj.fire → Ajustes →
«Clave del reloj». En el código no hay ninguna clave.

## Compilar
`.github/workflows/compilar-crono.yml` (al tocar `crono/`): `crono/build/CronoPjfire.iq` (para subir como
app beta) y `crono/build/log.txt` (registro y resultado de las pruebas de `crono/test/`).
