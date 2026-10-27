# 人（人形）

ゲームの人の形。Blender の台本で組み、外の素材は使わない（書体だけ Blender に入っているもの）。決めたことは [アートコンセプトの「人」](../design/art-concept.md)。

| 人形 | 中身 |
|---|---|
| `kasa` ① 笠と千代紙 | 紙の笠、閉じた目、黒い紙の髪、千代紙を重ねて折った着物 |
| `origami` ② 多面体の折り紙 | 大きな平面と稜線の紙の体、頭巾、茶の髪、青いエプロン |
| `news` ③ 新聞紙と麻布 | 北欧の新聞紙を貼った張り子、ボタンの目、毛羽立った麻布の頭巾と上着 |

## ファイル

| ファイル | 中身 |
|---|---|
| [build_dolls.py](build_dolls.py) | 3 体を組んで描く。`--export` で骨を入れてゲーム用に書き出す |
| [rig_export.py](rig_export.py) | 骨と重み、色と法線の焼き込み、glb の書き出し（骨の名前は 3 体で同じ） |
| [newsprint.py](newsprint.py) | 北欧の新聞紙の地（`textures/newsprint.png`）。読めない作り語の段組み |
| `blend/*.blend` | 開いて回して見る用。Blender で開き、`Z` →「Rendered」、「View → Cameras → Active Camera」で絵と同じ光と構図 |
| `renders/` | 描いた絵と、ゲームの中の録画（`06-play-*.mp4`） |

## 動かし方

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P person/build_dolls.py -- --doll kasa --views quarter,front --prefix person/renders/kasa
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P person/build_dolls.py -- --doll kasa --export game/person
```

- 描くのは Eevee。Cycles の GPU は画面なしだと装置を探すところで止まるので使わない（焼き込みは Cycles の CPU）
- 書き出しは 1 体 30 秒ほど。`game/person/<doll>.glb` に色と法線の画像（2048）が入る
- ゲームの中の確かめ: `game/tools/doll_shots.gd`（3 体を並べて撮る）、`game/tools/play_record.gd`（押す・乗る・滑るをソリの横から録る）
