#!/usr/bin/env bash
# Compila «Crono pj.fire» para el Fenix 6X Pro y pasa las pruebas en el simulador.
# Lo lanza .github/workflows/compilar-crono.yml. Todo queda en crono/build/log.txt
# (con la contraseña enmascarada) para poder verlo desde fuera de GitHub.
#   crono/build/CronoPjfire.iq   paquete para subir como app beta a la tienda Connect IQ
#   crono/build/CronoPjfire.prg  la app suelta (para instalar por cable o en el simulador)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=crono/build
mkdir -p "$OUT"
LOG=$OUT/log.txt
: > "$LOG"

mask() { perl -pe 'BEGIN{$|=1; $p=$ENV{GARMIN_PASSWORD}; $u=$ENV{GARMIN_USERNAME}; $k=$ENV{CLAVE_FIRMA}} s/\Q$k\E/***/g if length $k; s/\Q$p\E/***/g if length $p; s/\Q$u\E/<usuario>/g if length $u'; }
step() {
  echo "=== $1 ($(date -u +%T))" | tee -a "$LOG"
  shift
  "$@" 2>&1 | mask | tail -n 80 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  echo "--- código de salida: $rc" | tee -a "$LOG"
  return $rc
}
fail() { echo "ESTADO: FALLO en '$1'" | tee -a "$LOG"; exit 1; }

step "Clave de firma" python3 scripts/derive_key.py /tmp/developer_key.der || fail "Clave de firma (secreto CLAVE_FIRMA)"
step "Instalar CLI" go install "github.com/lindell/connect-iq-sdk-manager-cli@${SDK_MANAGER_VERSION}" || fail "Instalar CLI"
export PATH="$(go env GOPATH)/bin:$PATH"
step "Aceptar licencia" connect-iq-sdk-manager-cli agreement accept || fail "Aceptar licencia"
step "Login Garmin" connect-iq-sdk-manager-cli login || fail "Login Garmin"
step "SDK" connect-iq-sdk-manager-cli sdk set "${SDK_VERSION}" || fail "SDK"
step "Dispositivo fenix6xpro" connect-iq-sdk-manager-cli device download --device=fenix6xpro || fail "Dispositivo"
BIN="$(connect-iq-sdk-manager-cli sdk current-path --bin)"
export PATH="$BIN:$PATH"

step "Compilar .iq (tienda)" monkeyc -e -r -w -f crono/monkey.jungle -y /tmp/developer_key.der -o "$OUT/CronoPjfire.iq" || fail "Compilar .iq"
step "Compilar .prg (fenix6xpro)" monkeyc -r -w -d fenix6xpro -f crono/monkey.jungle -y /tmp/developer_key.der -o "$OUT/CronoPjfire.prg" || fail "Compilar .prg"

# ---- Pruebas en el simulador (no bloquean la compilación) ----
PRUEBAS="no ejecutadas"
pruebas() {
  sudo apt-get update -qq >/dev/null 2>&1
  for p in xvfb libusb-1.0-0 libsm6 libwebkit2gtk-4.1-0 libsoup-3.0-0 libjpeg-turbo8 libgtk-3-0t64 libsecret-1-0; do
    sudo apt-get install -y -qq "$p" >/dev/null 2>&1 || echo "no se pudo instalar $p"
  done
  echo "Bibliotecas que faltan al simulador:"; ldd "$BIN/simulator" | grep "not found" || echo "(ninguna)"
  monkeyc --unit-test -w -d fenix6xpro -f crono/pruebas.jungle -y /tmp/developer_key.der -o /tmp/pruebas.prg || return 1
  (xvfb-run -a -s "-screen 0 1280x1024x24" "$BIN/simulator" > /tmp/sim.log 2>&1 &)
  sleep 20
  timeout 240 monkeydo /tmp/pruebas.prg fenix6xpro -t > /tmp/resultado.txt 2>&1
  local rc=$?
  cat /tmp/resultado.txt
  echo "--- simulador:"; tail -n 15 /tmp/sim.log
  return $rc
}
if step "Pruebas en el simulador" pruebas; then
  PRUEBAS="$(grep -oE 'PASSED.*|FAILED.*|[0-9]+ (tests )?passed.*' /tmp/resultado.txt | tail -n1)"
  [ -z "$PRUEBAS" ] && PRUEBAS="ejecutadas (ver log)"
else
  grep -q "FAIL" /tmp/resultado.txt 2>/dev/null && PRUEBAS="CON FALLOS" || PRUEBAS="no se pudieron ejecutar"
fi
echo "ESTADO: OK (pruebas: $PRUEBAS)" | tee -a "$LOG"
