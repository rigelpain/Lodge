# 食べ物と飲み物の見た目の作り直し（2026-11-05）

代表「食べ物飲み物の見た目が微妙すぎて、おにぎりとかひどいですよ謎の具がちょい見えしてたりして。ちゃんと imozuru かネットで見た目検索してからアートコンセプトに合うように作ってください」「食べるは大事な要素なので作り込んでほしい。できれば食べてる途中の食べ口と中身も作ってほしい」

## 前の形のまずかった所

- おにぎり: 海苔は体より幅の広い箱が腰に刺さっているだけ。具（橙の板）が体の面から少し頭を出している。これが「謎の具」
- 麺: 毛糸の管を軽くする処理（decimate）で三角の破片に崩れていた（ラーメン・うどん・そば・焼きそば）
- 絵（焼き込み）が 1 品 64 px ほど。米粒も縫い目も潰れる
- 手に持つと遠くて小さく、ひと口ごとに形をそのまま小さくするだけ（食べ口がない）
- 湯気が品より大きく、品を隠す

## 調べた物と、汲み取った物

実物の写真は Wikimedia Commons、手芸は Creema（ハンドメイドの通販）の作品写真を見た。形を借りるだけで、画像は使っていない。

| 品 | 見た物 | 汲み取った物 |
|---|---|---|
| おにぎり | [Commons Category:Onigiri](https://commons.wikimedia.org/wiki/Category:Onigiri)（Onigiri 002、Salmon onigiri）、[Creema フェルトのおにぎり](https://www.creema.jp/listing?q=%E3%83%95%E3%82%A7%E3%83%AB%E3%83%88+%E3%81%8A%E3%81%AB%E3%81%8E%E3%82%8A)、[具が外せるおにぎり](https://www.creema.jp/item/6710721/detail) | 角の丸い三角で、厚みは幅の半分ほど。海苔は底から巻く幅の狭い帯で、両脇と上に米粒が見える。フェルトの作品は 2 枚合わせのふっくらした形で、海苔の縁と合わせ目に縫い目。具の切り口は中央の丸いかたまり。包んだ姿では具を見せない |
| たい焼き | Commons（Taiyaki 005、Taiyaki）、[Creema 羊毛フェルトのたい焼き](https://www.creema.jp/listing?q=%E7%BE%8A%E6%AF%9B%E3%83%95%E3%82%A7%E3%83%AB%E3%83%88+%E3%81%9F%E3%81%84%E7%84%BC%E3%81%8D) | 羊毛の作品は厚くふっくら。うろこは大きな菱の格子で、盛り上がった所が濃い。焼き色は山が濃く、谷が明るい |
| 肉まん | Commons（Nikuman、Family Mart imuraya nikuman）、[Creema フェルトの肉まん](https://www.creema.jp/listing?q=%E3%83%95%E3%82%A7%E3%83%AB%E3%83%88+%E8%82%89%E3%81%BE%E3%82%93) | 丸くふくらみ、てっぺんへ細いひだが集まる。底に薄い紙。羊毛の作品は白くなめらかで、ひだの筋だけ。あんは豚肉・玉ねぎ・たけのこ・椎茸（[セブンの肉まんの紹介](https://macaro-ni.jp/114479)ほか） |
| ラーメン | Commons（Shoyu Ramen、Tokyo Ramen の写真）、[Creema フェルトのラーメン](https://www.creema.jp/listing?q=%E3%83%95%E3%82%A7%E3%83%AB%E3%83%88+%E3%83%A9%E3%83%BC%E3%83%A1%E3%83%B3) | 白い器の縁に雷紋。麺をそろえて見せ、具は片側に寄せる。のりは奥の縁に立てかける。なるとは波の縁に桃色の渦、卵は切り口が上で濃い黄身、焼き豚は脂の明るい縁。手芸では麺は太い毛糸で平行に流す |
| ココア | [Creema 羊毛のラテのピンクッション](https://www.creema.jp/listing?q=%E3%83%95%E3%82%A7%E3%83%AB%E3%83%88+%E3%83%9E%E3%82%B0%E3%82%AB%E3%83%83%E3%83%97+%E3%82%B3%E3%82%B3%E3%82%A2) | 器の内側が見え、飲み物の面は羊毛の平らな面。飾りを少しだけ載せる |

かじった跡を手芸で作った作品は、見つからなかった（検索「フェルト おにぎり かじった 断面」）。切り口の作りは、切り分けて具を見せる「具が外せるおにぎり」と、実物の断面から決めた。

## 決めたこと

- 2 枚合わせのふっくらした形を基本にする（`props/food_bite.py` の `pillow`）
- 粒（米粒・具のかけら・気孔）は thread の役割にして絵に焼くだけにする。軽い形に入れないので、三角の破片にならない
- 食べている途中の形を glb で持つ（`<名前>_b1`・`_b2`）。`game/food.gd` の `dish_glb(dish, bites)` が選び、持ち物のアイコンも同じ口数の絵になる
- 食べ口は歯の跡が並ぶ丸でくり抜き、切り口は中身の色の面へ替える（`props/food_bite.py` の `mouth`・`carve`）
- 汁物と飲み物は、飲むほど水面が下がり、具が減り、内側に飲んだ跡の輪が残る

## 道具

- `Blender -b -P props/build_food.py -- --only 名前,名前 --views sheet --prefix 出力`: 並べて描く
- `Blender -b -P props/build_food.py -- --only 名前,名前 --look flat --export game/props/food`: 書き出す
- `Godot --path game --resolution 1280x720 -s res://tools/food_models_shot.gd -- --only=onigiri,taiyaki --bites --out=x.png`: ゲームの素材で 3 段階を並べる
- `Godot --path game --resolution 1280x720 -s res://tools/food_bite_shots.gd -- --bots=0 --no-pip --dishes=onigiri --mouth --dir=x`: 手に持った姿を撮る
