# 気温と白い息の見比べ（2026-10-30）

気温（`game/temperature.gd`）で、白い息の見え方が変わる。決まりは [アートコンセプト](../../art-concept.md) の「気温と白い息」。
どれも顔の横から。ふもとと戸口の外は、白い息が雪を背にすると見えないので、空のほう（ロッジのほう）を向いて撮った。

| 絵 | 何を |
|---|---|
| `places.jpg` | 場所と時刻で比べる。上の段が B の長い息、下の段がふだんの息。左から ふもと 14 時（−6.7 °C）・ふもと 夜 23 時（−12.1 °C）・丘の頂上 14 時（−9.0 °C）・ロッジの中（18 °C、見えない）・暖炉のそば（22 °C、見えない） |
| `move.jpg` | 出入り。B で吐きながら、上の段はロッジの中から戸口の外へ、下の段は戸口の外からロッジの中へ移り、0.6〜4.2 秒後を撮った。見え方は数秒かけてなじむ（外へ 0.24→0.92、中へ 0.88→0.15） |

撮り直すには:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/breath_shots.gd -- --view=side --only=long,normal --place=foot --tag=foot --dir="$PWD/design/breath/temperature/raw"
```

`--place=foot|summit|inside|fire`、`--time=23` で夜、`--move=out|in` で出入り。気温の表は `tools/temperature_check.gd`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://tools/temperature_check.gd
```
