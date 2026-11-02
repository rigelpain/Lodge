#!/bin/sh
# 案の絵（props/build_nook.py --plan N --cpu --views room,plan,sit --prefix design/hearth-nook/proposal-N の png）を 1 枚にまとめる: 左から「入口の側から」「暖炉の前に座った目線」「真上から（北が上）」
#   sh design/hearth-nook/sheet.sh
cd "$(dirname "$0")"
for n in 1 2 3; do
  [ -f proposal-$n-room.png ] || continue
  ffmpeg -y -loglevel error -i proposal-$n-room.png -i proposal-$n-sit.png -i proposal-$n-plan.png \
    -filter_complex "[2]hflip,vflip[p];[0][1][p]hstack=inputs=3,scale=2400:-1" -q:v 3 proposal-$n.jpg
done
