#!/usr/bin/env python3
"""Génère l'icône d'app iOS (iPhone/iPad) : dégradé violet « Stremio » + triangle
« play » blanc arrondi, 1024×1024. Écrit dans Sources/iOS/Assets.xcassets.

iOS applique lui-même le masque aux coins : on dessine donc un carré plein.
Dépend de Pillow (PIL).
"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "Sources", "iOS", "Assets.xcassets")
ICONSET = os.path.join(ROOT, "AppIcon.appiconset")

TOP = (138, 92, 246)      # #8a5cf6
BOTTOM = (43, 18, 59)      # #2b123b
SIZE = 1024


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(TOP[0] * (1 - t) + BOTTOM[0] * t)
        g = round(TOP[1] * (1 - t) + BOTTOM[1] * t)
        b = round(TOP[2] * (1 - t) + BOTTOM[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def draw_play(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    cx, cy = SIZE / 2, SIZE / 2
    half = SIZE * 0.24          # demi-hauteur
    depth = SIZE * 0.40          # largeur (pointe à droite)
    x0 = cx - depth * 0.42
    points = [
        (x0, cy - half),
        (x0, cy + half),
        (x0 + depth, cy),
    ]
    # Triangle blanc, coins légèrement adoucis via joint arrondi.
    d.polygon(points, fill=(255, 255, 255))
    d.line(points + [points[0]], fill=(255, 255, 255), width=48, joint="curve")


def write_json(path: str, obj: dict) -> None:
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def main() -> None:
    os.makedirs(ICONSET, exist_ok=True)
    img = gradient(SIZE)
    draw_play(img)
    img.save(os.path.join(ICONSET, "AppIcon.png"))

    write_json(os.path.join(ICONSET, "Contents.json"), {
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1},
    })
    write_json(os.path.join(ROOT, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    print("Icône iOS générée :", os.path.normpath(ICONSET))


if __name__ == "__main__":
    main()
