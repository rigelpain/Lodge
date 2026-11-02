# 音の出どころ

リポジトリに入れた録音の台帳。合成した音（`sound/gen/` の台本で作ったもの）はここに書かない。
決まりは [design/sound-concept.md](../design/sound-concept.md) の「素材の決まり」。
元ファイルは `sound/raw/`（git には入れない）。切り出しは `gen/cut.py` で、どの秒を使ったかはその中の PICKS にある。

すべて freesound.org、ライセンスは CC0 1.0（パブリックドメイン。帰属表示は不要だが、礼儀として credits に作者名を載せる）。取得日は 2026-10-27。

| ファイル | 元の名前 | 出どころ | 作者 | 加工 |
|---|---|---|---|---|
| `step_snow_01..06.wav` | Footsteps Snow 2 - Walk & run | https://freesound.org/people/Vrymaa/sounds/773740/ | Vrymaa | 歩きの部分から一歩ずつ。120 Hz 以下を落とし、実効値 −25 dB でそろえる |
| `step_snow_push_01..04.wav` | Footsteps_Mountain_Boots_Snow_Walk_Mono | https://freesound.org/people/Nox_Sound/sounds/613849/ | Nox_Sound | 重い一歩を 4 つ。100 Hz 以下を落とす。踏ん張りの歩に |
| `fire_crack_01..08.wav` | fire_crackling.wav | https://freesound.org/people/ceich93/sounds/263864/ | ceich93 | 床より十分大きい破裂を 8 つ切り出し。500 Hz 以下を落とす |
| `fire_bed_loop.wav` | Fire - Chimney / Stove | https://freesound.org/people/Vrymaa/sounds/770108/ | Vrymaa | 19〜27 秒。破裂をならし、9 kHz 以上を落とし、末尾を頭に重ねてループに |
| `dish_01..04.wav` | Tableware - Handle plates | https://freesound.org/people/Vrymaa/sounds/797581/ | Vrymaa | 皿が触れる音を 4 つ。150 Hz 以下を落とす |
| `dish_05..06.wav` | Ceramic Plate Set Down | https://freesound.org/people/bbrocer/sounds/382643/ | bbrocer | 皿を卓に置く音を 2 つ |

外の焚き火（`game/campfire.gd`、2026-11-01）は、新しい録音を足さずに、上の `fire_bed_loop.wav` と `fire_crack_01..08.wav` を使い回す。外の音（Outdoor の通り道）として焚き火の所で鳴らし、ぱちぱちの大きさは火の強さに合わせる（`audio.gd` の `campfire`・`fire_crack`）。

落としたが、使っていないもの: eZZin「Walking in cold snow」(683920。聞き比べで不採用)、cabled_mess「Footstep in the snow_01 [RAW]」(384423)、florianreichelt「footsteps in fresh snow」(453168)、Davor「Fire crackling in fireplace」(382616)、Sirnak「Sound of Ceramic Dishes」(813608)。

## 売り台・ミシン・厨房（2026-11-01）

代表の依頼「購入音、ミシンでの制作音、食べ物の調理音をしっかり作ってほしい」で入れた。合成を土台にして、合成だと太鼓や電子音に聞こえた所（紙・木の当たり・きしみ・はさみ・焼ける音・湯気・沸く湯・注ぐ音）に録音を当てた。
すべて freesound.org の CC0 1.0（各ページで確かめた）。取得日は 2026-11-01。元は各ページの試聴用 mp3（-hq、128 kbps。ログインなしで取れる）で、`sound/raw/craft_dl/` に置き（git には入れない）、ffmpeg で 48 kHz モノラルの wav にした。切る所は `gen/rec.py` の PICKS（秒は元のファイルの中）。

| ファイル | 元の名前 | 出どころ | 作者 | 加工 |
|---|---|---|---|---|
| `till_patch_01..03.wav`・`till_snow_01..03.wav` | old cash register open and close with a bing | https://freesound.org/people/clubmydia+/sounds/584168/ | clubmydia+ | 1.54〜3.47 秒（patch_01）、10.33〜11.45 秒（snow_03）。120 Hz 以下と 10 kHz 以上を落とす。雪だるまの分は 1.22 倍の速さに |
| `till_patch_01..03.wav`・`till_snow_01..03.wav` | Vintage cash register.m4a | https://freesound.org/people/Tompalompa/sounds/475915/ | Tompalompa | 2.51〜4.36 秒（patch_02）、9.81〜11.67 秒（snow_01） |
| `till_patch_01..03.wav`・`till_snow_01..03.wav` | cash register old antique open close drawer with bell ring various combinations.wav | https://freesound.org/people/kyles/sounds/452572/ | kyles | 69.86〜71.30 秒（patch_03）、105.15〜106.55 秒（snow_02） |
| `wrap_paper_01..03.wav` | Wrapping Paper Rustle | https://freesound.org/people/GrayJoy/sounds/344433/ | GrayJoy | 7.68〜9.08・9.26〜10.60・0.17〜1.60 秒。200 Hz 以下を落とし、末尾に合成の「とん」 |
| `wrap_bag_01..03.wav` | Paper Bag Crunching | https://freesound.org/people/steeltowngaming/sounds/537739/ | steeltowngaming | 0.42〜1.70・9.16〜10.35・6.76〜8.13 秒 |
| `wrap_tissue_01..03.wav` | Paper_Wrap.wav | https://freesound.org/people/uniuniversal/sounds/634323/ | uniuniversal | 1.46〜2.24・4.63〜5.07・2.24〜3.10 秒。900 Hz 以下を落として薄い紙に |
| `sew_stitch_01..06.wav` | sewing machine.wav（ゆっくり回す） | https://freesound.org/people/Astounded/sounds/477836/ | Astounded | 前後があいた 1 目を強い順に 6 つ（gen/rec.py の stitches）。120 Hz 以下を落とし、合成の「ぷす」を重ねる。04〜06 は 0.9 倍の速さで 3.2 kHz 以上を落とす |
| `sew_hum_loop.wav` | old sewing machine | https://freesound.org/people/bruno.auzet/sounds/721883/ | bruno.auzet | 62.5〜67.0 秒の 1.6 kHz より下だけを、合成のうなりの下に敷く |
| `sew_snip_01..02.wav` | scissors quick cut.wav | https://freesound.org/people/Kiyoshiakira/sounds/436768/ | Kiyoshiakira | 0.60〜0.85・1.04〜1.29 秒 |
| `sew_start_01..02.wav`・`sew_rest.wav`・`sew_land_01..02.wav`・`cook_*` | Opening Antique Trunk - More Latches.wav | https://freesound.org/people/OverlookHotelRecords/sounds/271377/ | OverlookHotelRecords | 留め金 8.07〜8.31・17.05〜17.43・1.71〜2.20 秒、ふた 30.20〜30.60・4.25〜4.74 秒。床に着く・アイロンを下ろす所は 0.75〜0.8 倍の速さ |
| `sew_treadle_01..03.wav`・`cook_press_*`・`cook_dryer_*` | Furniture Door - Open close | https://freesound.org/people/Vrymaa/sounds/797575/ | Vrymaa | 閉まる「ごとん」9.96〜10.30・11.12〜11.82・2.06〜2.94 秒、開くきしみ 8.04〜9.10・5.96〜7.41 秒 |
| `sew_start_01..02.wav`・`sew_treadle_01..03.wav` | SFX2 - rocking chair creak.wav | https://freesound.org/people/JK129645/sounds/547466/ | JK129645 | 0.14〜1.86 秒から 0.3〜0.4 秒を切る |
| `sew_draw.wav`・`sew_presser_01..02.wav`・`sew_rest.wav`・`till_pal_*`・`cook_iron_done_*` | Little Wooden Box Opening And Closing | https://freesound.org/people/arduenn/sounds/676420/ | arduenn | 8.97〜9.24・13.69〜14.08・10.01〜10.57 秒 |
| `pay_snowball_01..03.wav`・`sew_pop.wav`・`sew_land_*`・`cook_*` | Plushy Plop | https://freesound.org/people/Artistic_Dragonborn/sounds/831458/ | Artistic_Dragonborn | 20.99〜21.25・18.69〜18.94・38.58〜38.85 秒。4〜5 kHz 以上を落とす |
| `till_pal_01..03.wav` | Bell - Japanese, small | https://freesound.org/people/Vrymaa/sounds/739753/ | Vrymaa | 28.52〜29.40・18.05〜18.87・15.63〜16.07 秒。500 Hz 以下を落とす |
| `sew_pop.wav`・`sew_spring.wav` | Clothes/Fabric Grab | https://freesound.org/people/Takimeko/sounds/846612/ | Takimeko | 3.10〜3.79・5.39〜5.81 秒 |
| `sew_draw.wav`・`sew_spring.wav`・`sew_land_*` | Soft Fabric Rustle | https://freesound.org/people/IENBA/sounds/850705/ | IENBA | 6.29〜7.65・1.69〜2.19 秒 |
| `cook_iron_in_*`・`cook_iron_loop.wav` | Bacon Sizzling.wav | https://freesound.org/people/dannydandanshababaloo/sounds/593182/ | dannydandanshababaloo | 10.92〜13.10・2.18〜4.37・7.64〜9.82 秒を重ねてつなぎ、合成の湯気と合わせてループに |
| `cook_iron_done_*`・`cook_press_done_*`・`cook_drink_done_*` | Steam Iron used on board | https://freesound.org/people/Diramus/sounds/346778/ | Diramus | 8.22〜9.15・9.15〜10.88・17.27〜19.27 秒。300 Hz 以下を落とす |
| `cook_press_done_*` | Steam iron.wav | https://freesound.org/people/dersinnsspace/sounds/424971/ | dersinnsspace | 7.43〜9.43 秒 |
| `cook_drink_loop.wav` | Bubbling.wav | https://freesound.org/people/romulofs/sounds/127540/ | romulofs | 0〜5 秒。合成のホースの「ごぼ」と合わせてループに |
| `cook_dryer_loop.wav` | Water Boiling Strong | https://freesound.org/people/Ezcah/sounds/248296/ | Ezcah | 2.25〜6.75 秒。3 kHz 以上を落としてこもらせ、合成の胴のうなりの下に |
| `cook_drink_done_*` | Tea Pouring | https://freesound.org/people/mdayalan/sounds/240125/ | mdayalan | 2.02〜4.00・0.30〜2.02 秒の頭 1.1 秒 |

落としたが、使っていないもの: frodeims「sewing machine.wav」(666220。電気のミシンの立ち上がり。木の機械に合わない)、tutenchwimse「Sewing machine」(410616)、hbinnie11「Pouring cup of tea」(788672)、BeeProductive「Pouring tea.wav」(395615)、WilliamJMeyer「FOLEY_Handling paper bag_1」(495911)、PanosA「Snip with scissor」(546366)、The_Frisbee_of_Peace「Wooden Chest Lid Latches Open」(573653)。
