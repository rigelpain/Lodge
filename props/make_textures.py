"""CC0 の質感画像から、ゲームで全部の小物に重ねる「細部の画像」を作る（Blender の画像の読み書きを使う）。

    /Applications/Blender.app/Contents/MacOS/Blender -b -P props/make_textures.py -- <元の画像のフォルダ>

色は品物ごとに焼いた画像が受け持つので、ここでは明暗の模様と凹凸だけを取る:
  <素材>_detail.png  明暗だけの灰色。平均を 0.92 にそろえる（Godot の細部の重ね方「かけ算」で、色を変えずに模様だけ足す）
  <素材>_normal.png  凹凸（OpenGL の向き）。そのまま
出どころは props/SOURCES.md。元の画像は git に入れない。
"""
import os
import sys

import bpy
import numpy as np

SRC = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "props", "textures")
os.makedirs(OUT, exist_ok=True)

# 素材の名前: (色の画像, 凹凸の画像, 模様の強さ)
SETS = {
    "felt": ("caban_diff_1k.jpg", "caban_nor_gl_1k.jpg", 1.6),
    "cotton": ("polar_fleece_diff_1k.jpg", "polar_fleece_nor_gl_1k.jpg", 1.3),
    "hemp": ("hessian_230_diff_1k.jpg", "hessian_230_nor_gl_1k.jpg", 1.0),
    "yarn": ("jersey_melange_diff_1k.jpg", "jersey_melange_nor_gl_1k.jpg", 1.4),
    "wood": ("fine_grained_wood_col_1k.jpg", "fine_grained_wood_nor_gl_1k.jpg", 1.0),
    "paper": ("paper/Paper001_1K-JPG_Color.jpg", "paper/Paper001_1K-JPG_NormalGL.jpg", 1.5),
}


def load(path):
    im = bpy.data.images.load(os.path.join(SRC, path))
    im.colorspace_settings.name = "Non-Color"
    w, h = im.size
    return np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4), w, h


def save(arr, w, h, path):
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels = arr.reshape(-1)
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    print("wrote", path)


for name, (col, nor, k) in SETS.items():
    a, w, h = load(col)
    lum = a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722
    d = lum / max(1e-4, float(lum.mean()))          # 平均 1
    d = 1.0 + (d - 1.0) * k * 0.5                    # 模様の強さ
    d = np.clip(d * 0.92, 0.0, 1.0)                  # 平均 0.92
    out = np.ones((h, w, 4), dtype=np.float32)
    out[..., 0] = out[..., 1] = out[..., 2] = d
    save(out, w, h, os.path.join(OUT, name + "_detail.png"))
    n, w2, h2 = load(nor)
    n[..., 3] = 1.0
    save(n, w2, h2, os.path.join(OUT, name + "_normal.png"))
