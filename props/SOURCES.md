# 小物の質感の出どころ

`game/props/textures/` に入れた画像の台帳。形（モデル）はすべて `props/` の台本で作っていて、外の物は使っていない。
質感の画像は、2026-10-28 に代表が「外の素材使ってもいいよ」と緩めたので、CC0 の写真の質感を全部の小物で使い回す。
条件は音と同じ（[sound/SOURCES.md](../sound/SOURCES.md)）: CC0 を基本にし、NC（非商用）は使わない。

すべて CC0 1.0（パブリックドメイン。帰属表示は不要だが、礼儀として credits に作者名を載せる）。取得日は 2026-10-28。解像度は 1K。
元の画像は git に入れない。加工は [make_textures.py](make_textures.py)（明暗を灰色にして平均を 0.92 にそろえた `*_detail.png` と、凹凸の `*_normal.png`）。

| 使いみち | ゲームの画像 | 元の名前 | 出どころ | 作者 |
|---|---|---|---|---|
| フェルト（`felt_*`） | `felt_detail.png` `felt_normal.png` | Caban | https://polyhaven.com/a/caban | colormass（撮影）、Rico Cilliers（加工） |
| 綿（`cotton`） | `cotton_detail.png` `cotton_normal.png` | Polar Fleece | https://polyhaven.com/a/polar_fleece | colormass、Rico Cilliers |
| 麻ひも（`hemp`） | `hemp_detail.png` `hemp_normal.png` | Hessian 230 | https://polyhaven.com/a/hessian_230 | colormass、Rico Cilliers |
| 毛糸・糸（`yarn_*` `thread*`） | `yarn_detail.png` `yarn_normal.png` | Jersey Melange | https://polyhaven.com/a/jersey_melange | colormass、Rico Cilliers |
| 木（`wood*` `pole` `trunk` `button` `floor`） | `wood_detail.png` `wood_normal.png` | Fine Grained Wood | https://polyhaven.com/a/fine_grained_wood | Rob Tuytel |
| 紙（`paper*`） | `paper_detail.png` `paper_normal.png` | Paper 001 | https://ambientcg.com/view?id=Paper001 | ambientCG（Lennart Demes） |
