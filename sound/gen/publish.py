"""wav と確かめの絵を開発ダッシュボード（docs/sound/）へ写し、一覧を manifest.json に書く。
.venv/bin/python gen/publish.py
"""
import json
import pathlib
import shutil

import numpy as np
from scipy.io import wavfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
WAV, CHECK = ROOT / "sound" / "wav", ROOT / "sound" / "check"
DST = ROOT / "docs" / "sound"


def main():
    (DST / "wav").mkdir(parents=True, exist_ok=True)
    (DST / "png").mkdir(parents=True, exist_ok=True)
    files = []
    for path in sorted(WAV.glob("*.wav")):
        shutil.copy2(path, DST / "wav" / path.name)
        png = CHECK / (path.stem + ".png")
        if png.exists():
            shutil.copy2(png, DST / "png" / png.name)
        sr, x = wavfile.read(path)
        x = x.astype(np.float64) / 32767
        files.append({
            "file": path.name,
            "dur": round(len(x) / sr, 2),
            "peak": round(float(20 * np.log10(np.max(np.abs(x)) + 1e-12)), 1),
            "rms": round(float(20 * np.log10(np.sqrt(np.mean(x * x)) + 1e-12)), 1),
            "loop": path.name.endswith("_loop.wav"),
        })
    # 消えた wav の写しは片付ける
    names = {f["file"] for f in files}
    for old in (DST / "wav").glob("*.wav"):
        if old.name not in names:
            old.unlink()
            (DST / "png" / (old.stem + ".png")).unlink(missing_ok=True)
    (DST / "manifest.json").write_text(json.dumps(files, ensure_ascii=False, indent=1) + "\n")
    print(f"docs/sound/ へ {len(files)} 本")


if __name__ == "__main__":
    main()
