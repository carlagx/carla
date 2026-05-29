#!/usr/bin/env python3
"""
Lädt das Vosk-Sprachmodell für Deutsch herunter.

Ausführen VOR dem ersten App-Start (einmalig):
    python download_model.py [--lang de] [--dest /sdcard/vosk-model]
"""

import argparse
import os
import sys
import urllib.request
import zipfile

MODELS = {
    "de": {
        "name": "vosk-model-de-0.21",
        "url": "https://alphacephei.com/vosk/models/vosk-model-de-0.21.zip",
        "size": "~1.9 GB",
    },
    "de-small": {
        "name": "vosk-model-small-de-0.15",
        "url": "https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip",
        "size": "~45 MB  (weniger genau, dafür sehr kompakt)",
    },
    "en": {
        "name": "vosk-model-en-us-0.22",
        "url": "https://alphacephei.com/vosk/models/vosk-model-en-us-0.22.zip",
        "size": "~1.8 GB",
    },
    "en-small": {
        "name": "vosk-model-small-en-us-0.15",
        "url": "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip",
        "size": "~40 MB",
    },
}


def download_with_progress(url: str, dest: str):
    def _progress(count, block, total):
        pct = min(int(count * block * 100 / total), 100)
        bar = "#" * (pct // 2) + "-" * (50 - pct // 2)
        print(f"\r  [{bar}] {pct:3d}%", end="", flush=True)

    urllib.request.urlretrieve(url, dest, reporthook=_progress)
    print()  # Zeilenumbruch nach Fortschrittsbalken


def main():
    parser = argparse.ArgumentParser(description="Vosk-Modell herunterladen")
    parser.add_argument("--lang", default="de-small", choices=list(MODELS), help="Sprachmodell (default: de-small)")
    parser.add_argument("--dest", default=None, help="Zielordner (default: ./model neben diesem Skript)")
    args = parser.parse_args()

    info = MODELS[args.lang]
    dest_dir = args.dest or os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")

    print(f"Modell  : {info['name']}")
    print(f"Größe   : {info['size']}")
    print(f"Ziel    : {dest_dir}")

    if os.path.isdir(dest_dir):
        print("Modell-Ordner existiert bereits – überspringe Download.")
        sys.exit(0)

    zip_path = dest_dir + ".zip"
    print(f"\nHerunterladen von {info['url']} …")
    try:
        download_with_progress(info["url"], zip_path)
    except Exception as exc:
        print(f"Download fehlgeschlagen: {exc}", file=sys.stderr)
        sys.exit(1)

    print("Entpacken …")
    with zipfile.ZipFile(zip_path, "r") as zf:
        extract_root = os.path.dirname(dest_dir)
        zf.extractall(extract_root)

    # Umbenennen: vosk-model-de-0.21  →  model
    extracted = os.path.join(extract_root, info["name"])
    if os.path.isdir(extracted):
        os.rename(extracted, dest_dir)

    os.remove(zip_path)
    print(f"Fertig! Modell liegt in: {dest_dir}")
    print("\nTipp: Für Android das 'model'-Verzeichnis nach /sdcard/vosk-model kopieren:")
    print("  adb push model /sdcard/vosk-model")


if __name__ == "__main__":
    main()
