# 白い息の見比べ（2026-10-30）

上の段が直す前、下の段が直したあと。左から ふだんの息・声の息（ウン）・B の長い息（仲間はおーい）。
`game/tools/breath_shots.gd` で撮った。決まりは [アートコンセプト](../art-concept.md) の「白い息」。

| 絵 | 何を |
|---|---|
| `day_side.jpg` | 昼、顔の横から（煙の形がいちばん分かる） |
| `evening_side.jpg` | 夕方（18 時半）、顔の横から |
| `lodge_side.jpg` | ロッジの中、顔の横から（気温を入れる前。いまはロッジの中では息は白くならない。[temperature/](temperature/README.md)） |
| `day_fp.jpg` | 昼、一人称（右下の小窓も写る） |
| `lodge_fp.jpg` | ロッジの中、一人称 |

撮り直すには（`--view=fp|tp|side`、`--time=18.6` で夕方、`--spawn=inside` でロッジの中。ロッジの中は音を入れて起動する）:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --bots=2 --no-snow --no-sound --view=side --tag=now --dir="$PWD/design/breath/raw"
```

重さ: `--fps` で、あなたと仲間 2 人が 10 秒吐き続けるあいだの fps を出す（`--disable-vsync` を付けて測る）。

## B の息を大きく、高く（2026-11-07）

`big-exhale/before-after.jpg`: 左が直す前、右が直したあと。どれも B を押して 4.5 秒。上から 離れた所から（真横 7 m）、顔の横から、一人称（自分が吐く）、一人称（仲間が 2 人で吐くのを見る）。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --bots=2 --no-snow --no-sound --view=other --only=b --when=1.0,2.5,4.5 --tag=now --dir="$PWD/design/breath/raw"
```

数字は同じ道具の `--measure`（`--view=other` で見える高さ、`--view=fp` で画面をふさぐ割合）。`--only=b_bot` は仲間が B で吐くのを自分の目で見る絵、`--pitch=0.5` は見上げる絵。通信の確かめは `tools/breath_net_check.gd`（2 つ立ち上げる）。
