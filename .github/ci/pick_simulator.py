#!/usr/bin/env python3
"""Affiche l'UDID d'un simulateur Apple TV 4K sur le runtime tvOS le plus récent
(en crée un si l'image CI n'en fournit pas)."""
import json
import subprocess
import sys

listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"]))
runtimes = [r for r in listing["runtimes"] if r.get("platform") == "tvOS" and r.get("isAvailable")]
if not runtimes:
    sys.exit("Aucun runtime tvOS disponible")
runtime = max(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])

devices = [d for d in listing["devices"].get(runtime["identifier"], []) if d.get("isAvailable")]
devices.sort(key=lambda d: ("4K" not in d["name"], d["name"]))
if devices:
    udid, name = devices[0]["udid"], devices[0]["name"]
else:
    types = [t for t in listing["devicetypes"] if t.get("productFamily") == "Apple TV" and "4K" in t["name"]]
    name = types[-1]["name"]
    udid = subprocess.check_output(
        ["xcrun", "simctl", "create", "CI Apple TV", types[-1]["identifier"], runtime["identifier"]]
    ).decode().strip()

print(f"Simulateur : {name} — tvOS {runtime['version']} ({udid})", file=sys.stderr)
print(udid)
