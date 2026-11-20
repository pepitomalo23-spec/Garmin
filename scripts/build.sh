#!/usr/bin/env bash
# Compilación completa. Toda la salida va a build/log.txt (con la contraseña enmascarada)
# para poder diagnosticar desde fuera de GitHub.
set -uo pipefail
mkdir -p build
LOG=build/log.txt
: > "$LOG"

mask() { perl -pe 'BEGIN{$|=1; $p=$ENV{GARMIN_PASSWORD}; $u=$ENV{GARMIN_USERNAME}} s/\Q$p\E/***/g; s/\Q$u\E/<usuario>/g'; }
step() {
  echo "=== $1 ($(date -u +%T))" | tee -a "$LOG"
  shift
  "$@" 2>&1 | mask | tail -n 60 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  echo "--- código de salida: $rc" | tee -a "$LOG"
  return $rc
}

fail() { echo "ESTADO: FALLO en '$1'" | tee -a "$LOG"; exit 1; }

step "Instalar CLI" go install "github.com/lindell/connect-iq-sdk-manager-cli@${SDK_MANAGER_VERSION}" || fail "Instalar CLI"
export PATH="$(go env GOPATH)/bin:$PATH"
step "Aceptar licencia" connect-iq-sdk-manager-cli agreement accept || fail "Aceptar licencia"
step "Login Garmin" connect-iq-sdk-manager-cli login || fail "Login Garmin"
step "SDK" connect-iq-sdk-manager-cli sdk set "${SDK_VERSION}" || fail "SDK"
step "Dispositivos" connect-iq-sdk-manager-cli device download --download-all || fail "Dispositivos"
export PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
step "Lista de relojes" python3 scripts/fill_products.py manifest.xml || fail "Lista de relojes"
step "Compilar .iq" monkeyc -e -r -w -f monkey.jungle -y keys/developer_key.der -o build/PabloFace.iq || fail "Compilar .iq"
grep -o 'id="[^"]*"' manifest.xml | grep -v f416abff | tr '\n' ' ' > build/relojes.txt
echo "ESTADO: OK" | tee -a "$LOG"
