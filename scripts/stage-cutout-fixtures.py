#!/usr/bin/env python3
"""Stage local image fixtures before running CutoutFlowTests on a simulator."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Simulator UDID; defaults to the booted iPhone Duo")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

    def simctl(*arguments):
        return subprocess.check_output(["xcrun", "simctl", *arguments], env=env, text=True).strip()

    device = args.device
    if not device:
        inventory = json.loads(simctl("list", "devices", "available", "--json"))
        device = next((item["udid"] for group in inventory["devices"].values() for item in group
                       if item["name"] == "iPhone Duo" and item["state"] == "Booted"), None)
    if not device:
        parser.error("Boot an iPhone Duo simulator, or provide --device <UDID>.")

    container = Path(simctl("get_app_container", device, "com.xiuyuancai.brewwww", "data"))
    documents = container / "Documents"
    documents.mkdir(exist_ok=True)
    shutil.copy2(root / "BrewwwwTests/Fixtures/coffee.jpg", documents / "cutout-test.jpg")
    shutil.copy2(root / "预览/主体抠图-实测.png", documents / "cutout-test.png")
    print("Staged coffee photo and the actual Mac-generated cutout in the simulator.")


if __name__ == "__main__":
    main()
