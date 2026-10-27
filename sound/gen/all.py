"""全部を作り直す。 .venv/bin/python gen/all.py"""
import runpy
import sys
import pathlib

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here))
for name in ["steps", "breath", "runner", "wind", "fire", "kitchen", "door", "sled", "music", "speaker", "check", "publish"]:
    print(f"--- {name}")
    sys.argv = [name]
    runpy.run_path(str(here / f"{name}.py"), run_name="__main__")
