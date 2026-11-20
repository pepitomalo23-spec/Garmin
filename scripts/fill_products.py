#!/usr/bin/env python3
"""Rellena <iq:products> del manifest con todos los relojes descargados que admiten esferas.

Lee ~/.Garmin/ConnectIQ/Devices/*/compiler.json (descargados por el SDK manager)
y añade cada dispositivo que soporte el tipo watchFace con Connect IQ >= MIN_API.
"""
import json
import pathlib
import re
import sys

MIN_API = (3, 2, 0)
DEVICES = pathlib.Path.home() / ".Garmin" / "ConnectIQ" / "Devices"
MANIFEST = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "manifest.xml")


def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])


products = []
for cj in sorted(DEVICES.glob("*/compiler.json")):
    try:
        d = json.loads(cj.read_text())
    except Exception:
        continue
    types = {a.get("type") for a in d.get("appTypes", [])}
    if "watchFace" not in types:
        continue
    if d.get("exportSupport") is False:  # dispositivos en beta que la tienda aún no acepta
        continue
    versions = [ver(p.get("connectIQVersion", "0")) for p in d.get("partNumbers", [])]
    if not versions or max(versions) < MIN_API:
        continue
    products.append(d.get("deviceId", cj.parent.name))

if not products:
    sys.exit("No se encontró ningún reloj compatible en " + str(DEVICES))

lines = "\n".join(f'            <iq:product id="{p}"/>' for p in products)
text = MANIFEST.read_text()
text = re.sub(r"(<iq:products>).*?(\s*</iq:products>)", lambda m: m.group(1) + "\n" + lines + m.group(2), text, flags=re.S)
MANIFEST.write_text(text)
print(f"{len(products)} relojes añadidos al manifest")
