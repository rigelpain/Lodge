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

落としたが、使っていないもの: eZZin「Walking in cold snow」(683920。聞き比べで不採用)、cabled_mess「Footstep in the snow_01 [RAW]」(384423)、florianreichelt「footsteps in fresh snow」(453168)、Davor「Fire crackling in fireplace」(382616)、Sirnak「Sound of Ceramic Dishes」(813608)。
