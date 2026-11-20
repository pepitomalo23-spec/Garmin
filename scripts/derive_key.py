#!/usr/bin/env python3
"""Deriva SIEMPRE la misma clave de firma RSA-4096 a partir del secreto CLAVE_FIRMA.

Así la clave nunca se guarda en el repositorio (que puede ser público):
misma frase -> misma clave -> la tienda Connect IQ acepta las actualizaciones.
Uso: CLAVE_FIRMA="frase" python3 derive_key.py salida.der
"""
import hashlib
import os
import sys

from Crypto.PublicKey import RSA

seed = os.environ.get("CLAVE_FIRMA", "").encode()
if len(seed) < 12:
    sys.exit("CLAVE_FIRMA falta o es demasiado corta (mínimo 12 caracteres)")


class DeterministicRNG:
    def __init__(self, s: bytes):
        self.key = hashlib.sha256(b"garmin-signing-key-v1" + s).digest()
        self.ctr = 0
        self.buf = b""

    def __call__(self, n: int) -> bytes:
        while len(self.buf) < n:
            self.buf += hashlib.sha256(self.key + self.ctr.to_bytes(8, "big")).digest()
            self.ctr += 1
        out, self.buf = self.buf[:n], self.buf[n:]
        return out


key = RSA.generate(4096, randfunc=DeterministicRNG(seed))
with open(sys.argv[1], "wb") as f:
    f.write(key.export_key(format="DER", pkcs=8))
print("Clave derivada:", hashlib.sha256(key.publickey().export_key()).hexdigest()[:12])
