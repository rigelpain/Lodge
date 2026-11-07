# 双眼鏡と、テラスの双眼鏡台

2026-11-07。代表の言葉：「アイテムとしての双眼鏡と、テラスに固定の双眼鏡台が欲しいです。よく観光地にあるやつ。」「双眼鏡台は木のボタン1枚か雪玉で起動してほしい」

## 見て汲み取ったもの

- 観光地の据え付け双眼鏡（Wikimedia Commons の [Coin-operated binoculars](https://commons.wikimedia.org/wiki/Category:Coin-operated_binoculars)、[Tower viewer](https://en.wikipedia.org/wiki/Tower_viewer)）: 幅広の頭、景色の側に大きな丸い目が 2 つ、人の側に寄ったのぞき口、Y の受け、支柱、丸い足の板、支柱か頭の硬貨口。写真の真似はせず、この並びだけを借りた
- 紙筒の工作の双眼鏡（[Mommy Evolution](https://mommyevolution.com/binocular-craft-for-kids/)、[Kids Activity Zone](https://kidsactivityzone.com/santa-binoculars/)）: 2 本の筒に紙やフェルトを巻き、毛糸のひもを通す。持ち歩く双眼鏡の作りに借りた

外の絵やモデルは入れていない。形は [ideas.py](ideas.py) で、素材は `props/common.py`・`props/kit.py` の本番の物。

## 形

[台の 3 案](00-stands.jpg)と[手持ちの 3 案](01-hands.jpg)を代表に見せて決めた（「双眼鏡台はまんなか、手持ち双眼鏡は左が良いかな」）。

- 台: 毛糸を巻いた糸巻きを 2 本並べた筒（案 B）。のぞき口は小さな糸巻き。足と支柱は木に麻ひも、足の板は真鍮のボタンで床に留める
- 頭の高さ: 案の絵は 1.40 m で描いたが、人形の目（笠 1.16 m、小さい人形は 0.6〜0.8 m）に寄せて 1.20 m に下げた。のぞく視点は手すりの上の 1.43 m のまま
- 料金の袋: 支柱の人の側の、手の高さ。藍のフェルトで、前に見本の木のボタンと雪玉を縫い付け、字を使わずに値段を見せる
- 手持ち: フェルトを巻いた筒に、木の 4 つ穴ボタンの目と毛糸のひも（左の案）

## 遊び方の決まり

| | 手の双眼鏡 | テラスの台 |
|---|---|---|
| 手に入れ方 | 山男の棚で木のボタン 30 個 | テラスに 1 台 |
| のぞく | 手に持って左ボタンを押しているあいだ。立っていても座っていても | 前で F |
| 料金 | なし | 雪玉 1 個。なければ木のボタン 1 枚。どちらもなければ赤い × |
| 倍率（縦の画角） | 約 3.5 倍（24°） | 約 8.5 倍（10°） |
| やめる | 離す。持ち替え・設定の画面でも下ろす | F・Esc。60 秒で穴がすぼんで閉じる。残りは覆いの下の縫い目の長さで見せる |

- 見回しの速さは画角に合わせてゆっくりになる。のぞいているあいだは歩かず、ほかの操作もしない。雪玉が当たって飛ばされればやめる
- 台は一度に 1 人。のぞく人は支柱のまわりを回って立ち、見回せるのは景色の向きから左右に約 77°。頭はのぞいている人の見ている所へ向く（どの画面でも同じ）
- 相手の画面では、手の双眼鏡なら両手で目に当てた形が、台なら両手を台の頭に添えた姿が見える
- のぞく窓は濃いフェルトの覆いに丸い穴が 2 つ、縁は白糸のなみ縫い。視野を狭めるだけで描く物は増やさない

台が 60 秒で閉じるのは、代表の返事がなかったので観光地の物に合わせた仮の決まり（`game/binoculars.gd` の STAND_SECONDS）。

## 作り

- 品目・値段・画角・案内の絵: `game/binoculars.gd`（棚の 1 行は `game/mountain_goods.gd`）
- 台の節: `game/binocular_stand.gd`。置き場は `game/main.gd` の BINOCULAR_AT（`lodge/dims.py` の BINOCULAR_STAND）。ロッジの glb は作り直していない
- のぞく動き: `game/player.gd` の peek。窓: `game/binocular_view.gd`。人形の姿勢: `game/doll.gd` の `_plan_peek`
- 出来事: `game/craft.gd` の scope_on・scope_off。ホストが空きを確かめて払う
- 確かめ: `game/tools/binoculars_shots.gd`、`game/tools/binoculars_net_shots.gd`
