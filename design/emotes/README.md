# 身ぶり（エモート）の絵

`game/tools/emote_shots.gd` で撮った確かめの絵（2026-10-28）。決まりは [アートコンセプト](../art-concept.md) の「身ぶり」。

名前は `身ぶり_視点.jpg`（撮る道具は png で書き出すので、入れるときに JPEG にした）。視点は 3 つ。

- `fp` 一人称（あなたの目）。自分の手袋・雪玉・手のひら・白い息が画面に見えるか
- `tp` 三人称（C の視点）
- `front` 横の少し前から（人形の形と、二人の手が合う所）

| 名前 | 何のコマか |
|---|---|
| `hand_up` | 手のひらを掲げて待つ（8 コマ目） |
| `five_pull` | 届いて、引く（ため、1 コマ目） |
| `high_five` | 叩きつけて、手が合う（3 コマ目。紙の星と紙吹雪が出る） |
| `five_burst` | 紙吹雪が散る（5 コマ目） |
| `whiff` | 6 秒待っても合わず、空振り |
| `breath_in` / `breath_out` | 深呼吸の吸う所と、長く吐く所 |
| `make_ball` | しゃがんで雪玉を丸める |
| `windup` / `throw` | 振りかぶる、投げる |
| `hit_bot` / `hit_me` | 雪玉が仲間に当たる／あなたに当たる（のけぞる） |
| `sled` | ソリに当たって、綿の雪が残る |
| `clap` / `bow` | 拍手、おじぎ |
| `wa` / `un` / `nn` | 声「ワ〜」「ウン」「ンーン」の身ぶり |
| `banzai` | ソリの上で万歳 |

撮り直すには（`--only=hand_up,high_five` で一部だけ）:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/emote_shots.gd -- --bots=1 --no-sound --no-pip --no-snow --view=fp --dir="$PWD/design/emotes"
```

仲間の返し（ハイタッチに来る・声を返す・おじぎを返す）は `--check` で、撮らずに出来事の記録で確かめる。

## 声

声は `sound/gen/voice.py` で合成した（録音も生成サービスも使っていない）。波形とスペクトログラムは `sound/check/voice_*.png`。

| 声 | ファイル | 長さ | 高さの動き |
|---|---|---|---|
| ワ〜 | `sound/wav/voice_wa_01..03.wav` | 0.74〜0.84 秒 | 約 290 Hz から 375 Hz へ上がり、290 Hz へ下りる |
| ウン | `sound/wav/voice_un_01..03.wav` | 0.31〜0.33 秒 | 約 300 Hz から 235 Hz へ短く下がる |
| ンーン | `sound/wav/voice_nn_01..03.wav` | 0.61〜0.65 秒 | 約 320 Hz の山のあと一度切れ、255 Hz から 220 Hz へ |

聞き方: `sound/check/listen.html` をブラウザで開くと、波形とスペクトログラムを見ながら再生できる（`voice_`・`felt_pat_`・`snow_splat_`・`swish_` が今回の音）。Finder で `sound/wav/` のファイルを選んでスペースキーでも鳴る。ゲームの中では 1・2・3 キー。人ごとに高さが違う（あなた 1.0、② 0.9、③ 1.18）。合成なので、やわらかさ・人形らしさは代表の耳で判断してほしい。
