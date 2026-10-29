# 雪玉を 5 つまで持つ（2026-10-30）

決まりは [アートコンセプト](../art-concept.md) の「雪玉」の「持てる数」。この先の案（雪玉で払う・雪合戦）は [ゲームデザイン](../game-design.md)。

| 絵 | 何を |
|---|---|
| `counts.jpg` | 持っている数 0〜5。上の段は前から（右手に 1 つ、残りは帯の雪玉入れの袋に 1 つずつ）、まんなかの段は右下の自分の小窓、下の段は一人称（右手の雪玉のそばに、袋の分の小さな粒） |
| `throw_lodge.jpg` | 3 つ持って投げたところ（右手は空き、次の玉はまだ袋に。4 コマたつと右手に出る）と、ロッジの中に 5 つ持ち込んだところ（いまは溶けない） |

撮り直すには:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/snowball_stock_shots.gd -- --dir="$PWD/design/snowball-stock/raw"
```

`--place=inside` でロッジの中。数の確かめ（6 回丸めて 5 つ・2 つ投げて 3 つ・丸めている途中に当たるとできない）は:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/snowball_check.gd -- --bots=0 --no-sound --no-pip
```
