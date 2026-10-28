# 手の形と身ぶり（エモート）の絵

`game/tools/emote_shots.gd` で撮った確かめの絵（2026-10-28）。決まりは [アートコンセプト](../art-concept.md) の「手の形と身ぶり」。

名前は `身ぶり_視点.jpg`（撮る道具は png で書き出すので、入れるときに JPEG にした）。視点は 3 つ。

- `fp` 一人称（あなたの目）。自分の手袋・雪玉・手のひら・白い息が画面に見えるか
- `tp` 三人称（C の視点）
- `front` 横の少し前から（人形の形と、二人の手が合う所）

| 名前 | 何のコマか |
|---|---|
| `ring` | Tab の輪（右上の手のひらを選んでいる） |
| `palm` `palms` `fist` `fists` `thumb` `thumbs` `peace` | 手の形を掲げた所（前を見て） |
| `palms_up` | 両手のひらで見上げる（万歳になる） |
| `five_pull` / `high_five` / `five_burst` | 手のひら同士で近づいて、引く → 叩きつける（紙の星）→ 紙吹雪が散る |
| `fist_bump` | グー同士で近づいて、こつん |
| `whiff` | 仲間がよそを向いたまま寄って、空振り |
| `clap` | 両手のひらで左クリック |
| `breath_in` / `breath_out` | B を押した瞬間に吸う所と、押したまま長く吐く所 |
| `crouch` / `make_ball` | 左 Ctrl でしゃがむ、雪面を見て F で雪玉を丸める |
| `windup` / `throw` | 左クリックを押してためる、離して投げる |
| `hit_bot` / `hit_me` | 雪玉が仲間に当たる／あなたに当たる（のけぞる） |
| `sled` | ソリに当たって、綿の雪が残る |
| `wa` / `un` / `nn` | 声「ワ〜」「ウン」「ンーン」の身ぶり |
| `banzai` | ソリの上で両手のひらを掲げて見上げる |

撮り直すには（`--only=hand_up,high_five` で一部だけ）:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 960x540 -s res://tools/emote_shots.gd -- --bots=1 --no-sound --no-pip --no-snow --view=fp --dir="$PWD/design/emotes"
```

仲間の返し（ハイタッチ・グータッチに来る・同じ形で返す・声を返す・拍手を返す）は `--check` で、撮らずに出来事の記録で確かめる。

## 声

声は `sound/gen/voice.py` で合成した（録音も生成サービスも使っていない）。波形とスペクトログラムは `sound/check/voice_*.png`。

| 声 | ファイル | 長さ | 高さの動き |
|---|---|---|---|
| ワ〜 | `sound/wav/voice_wa_01..03.wav` | 0.74〜0.84 秒 | 約 290 Hz から 375 Hz へ上がり、290 Hz へ下りる |
| ウン | `sound/wav/voice_un_01..03.wav` | 0.31〜0.33 秒 | 約 300 Hz から 235 Hz へ短く下がる |
| ンーン | `sound/wav/voice_nn_01..03.wav` | 0.61〜0.65 秒 | 約 320 Hz の山のあと一度切れ、255 Hz から 220 Hz へ |

聞き方: `sound/check/listen.html` をブラウザで開くと、波形とスペクトログラムを見ながら再生できる（`voice_`・`felt_pat_`・`snow_splat_`・`swish_` が今回の音）。Finder で `sound/wav/` のファイルを選んでスペースキーでも鳴る。ゲームの中では 1・2・3 キー。人ごとに高さが違う（あなた 1.0、② 0.9、③ 1.18）。合成なので、やわらかさ・人形らしさは代表の耳で判断してほしい。
