# 白い息の見比べ（2026-10-30）

上の段が直す前、下の段が直したあと。左から ふだんの息・声の息（ウン）・B の長い息（仲間はおーい）。
`game/tools/breath_shots.gd` で撮った。決まりは [アートコンセプト](../art-concept.md) の「白い息」。

| 絵 | 何を |
|---|---|
| `day_side.jpg` | 昼、顔の横から（煙の形がいちばん分かる） |
| `evening_side.jpg` | 夕方（18 時半）、顔の横から |
| `lodge_side.jpg` | ロッジの中、顔の横から |
| `day_fp.jpg` | 昼、一人称（右下の小窓も写る） |
| `lodge_fp.jpg` | ロッジの中、一人称 |

撮り直すには（`--view=fp|tp|side`、`--time=18.6` で夕方、`--spawn=inside` でロッジの中。ロッジの中は音を入れて起動する）:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --bots=2 --no-snow --no-sound --view=side --tag=now --dir="$PWD/design/breath/raw"
```

重さ: `--fps` で、あなたと仲間 2 人が 10 秒吐き続けるあいだの fps を出す（`--disable-vsync` を付けて測る）。
