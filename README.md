# Lodge

ゲレンデで大きなソリをみんなで押して丘を登り、一緒に乗って一気に下る、3D 一人称の協力ゲーム。Steam での販売を目指しています。

- 設計の文書: `design/`
  - [ゲームの構想](design/game-concept.md) … ふたつの原体験、狙い、場所、ロッジ、通信、売り方
  - [ゲームデザインの骨組み](design/game-design.md) … 体験の柱 5 本、進め方、柱どうしがぶつかる所
  - [アートコンセプト](design/art-concept.md) … 手芸の世界（毛糸・フェルト・紙）、色、光、動き、音
  - [操作と物理の決まり](design/controls-and-physics.md) … 力の向きだけ入力し、あとは物理。仲間の挙動、確かめ方
  - [音の設計](design/sound-concept.md) … 雪が吸った乾いた音。柱のスピーカー、登り、滑り出す一瞬、ロッジの中。素材の決まりと出どころ（`sound/`）
- 開発ダッシュボード: `docs/`（GitHub Pages で公開。中身は `docs/data.json` を書き換える）
- ゲーム本体（Godot 4.6）: `game/`
- 絵柄の見本: これから `prototypes/` に置く

## 原型を遊ぶ

Godot 4.6 で `game/project.godot` を開いて実行する。コマンドからなら:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

WASD で歩き、マウスで見回す。ソリに向かって W で押す。E で乗り降り（乗ったら W で前へ、A/D で曲がる）。R でソリをふもとへ戻す。青い仲間が一緒に押してくれる。

確かめ用の引数（`--` のあと）: `--bots=2`（仲間の数）、`--no-player`（仲間だけ）、`--log`（ソリの高さを1秒ごとに出す）、`--shot=絵.png`（数秒後に画面を保存）、`--quit-at=秒`、`--spawn=lodge`／`--spawn=inside`（ロッジの前／食堂の中から始める。音の確かめ用）。

ソリで速く滑ると、目の横を毛糸の切れはし・綿の毛・毛玉の雪が後ろへ流れる（`game/ride_wind.gd`。乗っている本人の画面だけ）。強さは設定（Esc）の「風の流れ（滑るとき）」で変えられ、「視点の揺れ」を切ると控えめになる。`--no-wind` で出さない。頂上から滑り降りて一人称の絵を撮るには:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 1280x720 -s res://tools/ride_shots.gd -- --bots=0 --no-sound --dir="$PWD/design/ride-wind"
```

ロッジの中の大きなミシンは、前に立つと針が持ち上がり、T で縫う（7 つの場面の動きの試作。`game/sewing_machine.gd`）。Y でコマ撮り（12 fps、既定）／なめらか、H で仲間を足踏みに呼ぶと速く縫える。`--spawn=sew` でミシンの前から始まる。絵と感想は [design/sewing-motion](design/sewing-motion/README.md)。場面ごとの絵を撮るには:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sew_shots.gd -- --bots=0 --no-snow --no-sound --view=close --dir=/tmp/sew
```

## Claude Code のスキル

`.claude/skills/` に入れています（どちらも MIT）。

- `landing-page-design` … [elayadesign/ai-design-skills](https://github.com/elayadesign/ai-design-skills)（a2735a3）
- `semantic-web` ほか 9 本 … [nyattoh/semantic-web-skill](https://github.com/nyattoh/semantic-web-skill)（4b205c8）。本体は `.claude/semantic-web-skill/`、スキル内の相対リンクが通るよう `.claude/docs` などをリンクにしています

### &wind の会社のスキル（2026-10-27）

会社のリポジトリ company_and_wind の `.claude/skills/` にあり、`~/.claude/skills/` のシンボリックリンクで、このリポジトリの会話から `/<名前>` で呼べます（ここには写していません。出どころとライセンスは各スキルの `SOURCE.md`）。前からある `game-3d-stack`（3D ゲームの既製部品、2026-10-21）に、ゲーム・効果音・曲の 28 本を足しました。`gamedev-router` と Godot・作法・工程の 24 本は [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)（184b72b、Apache-2.0。基準は Godot 4.7。Lodge は 4.6 なので食い違えば 4.6 を優先）、`earshot` は [Leonxlnx/earshot](https://github.com/Leonxlnx/earshot)（591fa3e、MIT）、`game-sfx-code` と `game-music-local` は会社が書いたものです。

| スキル | Lodge でこう使う |
|---|---|
| `gamedev-router` | 「Godot で〜したい」と言ったとき、下のどのスキルを読むかを決める入口 |
| `godot-gdscript`、`godot-nodes-scenes`、`godot-signals-groups`、`godot-resources` | `game/*.gd` の書き方、場面の組み方、信号。`main.gd` への差し込みを最小にする相談 |
| `godot-physics`、`physics-tuning` | ソリ（RigidBody3D、Jolt）と人（CharacterBody3D）の当たり・力のかけ方・時間刻み。[操作と物理の決まり](design/controls-and-physics.md) の確かめ |
| `godot-3d-essentials`、`godot-shaders` | カメラ・光・WorldEnvironment と、手芸の見た目（フェルト・毛糸・紙）のシェーダー |
| `godot-animation`、`camera-systems`、`game-feel`、`input-systems` | 視点の揺れ・画角の変化（設定画面）、押す・乗るの手触り、キーとマウスの割り当て |
| `godot-audio`、`audio-design` | `game/audio.gd` のバス（Outdoor・Inside・Self）、AudioStreamPlayer3D、音のばらつき、dB の作法 |
| `game-sfx-code` | 効果音を `sound/gen/` で合成し、弱い所を CC0 の録音で補い、`sound/SOURCES.md` に残す道筋（[音の設計](design/sound-concept.md) の作り方が元） |
| `game-music-local` | 柱のスピーカーの曲（`sound/gen/music.py`）の続きと、本番の曲の 3 つの道（コード／手元の生成モデル／人）、権利の確かめ方 |
| `earshot` | Claude が音を「聞いて」言葉と数値で返す道具の使い方（本体はまだ入れていない。約 1.1 GB） |
| `godot-multiplayer` | Steam の P2P に進む前の、Godot の高レベル通信（RPC・同期）の下調べ |
| `godot-ui-control`、`game-ui-ux` | 設定画面（Esc）とスタンプの表示。言葉を使わない案内 |
| `level-design` | ゲレンデの登り道・柱の並び・ロッジの置き方の見直し |
| `performance-optimization` | FPS の測り方と予算（描画の解像度、360° 映像の間引き） |
| `save-systems` | 設定の保存（`settings.gd`）と、将来の記録 |
| `godot-export`、`godot-gdscript-headless-testing` | Mac・Windows への書き出し、`--headless` での確かめ |
| `steam-publish` | Steamworks・SteamPipe での登録と配信の手順（登録料は代表） |
| `prototype-fast` | 一つの問いに答える小さな原型の切り方 |
