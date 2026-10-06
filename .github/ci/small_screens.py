#!/usr/bin/env python3
"""Convertit les captures exportées d'un .xcresult (PNG 4K) en JPEG 1280 px
nommées « <test>-<ordre>-<étape>.jpg », pour un artefact léger à consulter.

Usage : python3 small_screens.py build/screenshots build/screens-small
"""
import json
import os
import re
import subprocess
import sys

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for test in json.load(open(os.path.join(src, "manifest.json"))):
    test_name = re.sub(r"\W+", "", test.get("testIdentifier", "test").split("/")[-1])
    attachments = sorted(test["attachments"], key=lambda a: a.get("timestamp", 0))
    for index, attachment in enumerate(attachments):
        exported = attachment["exportedFileName"]
        if not exported.lower().endswith(".png"):
            continue
        step = attachment.get("suggestedHumanReadableName", exported).rsplit("_0_", 1)[0]
        slug = re.sub(r"[^\w.-]+", "_", step)[:80]
        out = os.path.join(dst, f"{test_name}-{index:02d}-{slug}.jpg")
        subprocess.run(
            ["sips", "-Z", "1280", "-s", "format", "jpeg", "-s", "formatOptions", "70",
             os.path.join(src, exported), "--out", out],
            check=True, capture_output=True,
        )
print(f"{len(os.listdir(dst))} captures → {dst}")
