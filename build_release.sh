#!/bin/bash
# 配る zip（Windows と Mac）を作る。できた zip は build/<日付>-<コミット>/ に置く。
# 手順の説明は docs/playtest-online.md の「作る人向け」。
#   ./build_release.sh
# 書きかけの変更が混ざらないよう、まっさらな作業場（git worktree）で動かすのがよい。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
GAME="$ROOT/game"

if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
	echo "書きかけの変更があります。まっさらな作業場で動かしてください（git worktree add …）" >&2
	exit 1
fi
if [ -e "$GAME/sound" ]; then
	echo "game/sound がもうあります。前の書き出しの残りなら消してから動かしてください" >&2
	exit 1
fi

SHA=$(git -C "$ROOT" rev-parse --short HEAD)
OUT="$ROOT/build/$(date +%Y-%m-%d)-$SHA"
WORK=$(mktemp -d)
trap 'rm -rf "$GAME/sound" "$WORK"' EXIT

# 1. 音をゲームの中に入れる。音はふだんゲームの外の sound/wav から読むので、書き出したゲームには入らない。
#    読み込みはせず、wav のまま入れる（audio.gd が res://sound/wav から読む）
mkdir -p "$GAME/sound/wav"
cp "$ROOT"/sound/wav/*.wav "$GAME/sound/wav/"
for f in "$GAME"/sound/wav/*.wav; do
	printf '[remap]\n\nimporter="keep"\n' > "$f.import"
done
echo "音 $(ls "$GAME"/sound/wav/*.wav | wc -l | tr -d ' ') 個を入れた"

# 2. 読み込み（はじめての作業場では数分かかる）
"$GODOT" --headless --path "$GAME" --import > /dev/null 2>&1 || true

# 3. 書き出し
mkdir -p "$WORK/win/Lodge" "$WORK/mac" "$OUT"
"$GODOT" --headless --path "$GAME" --export-release "Windows Desktop" "$WORK/win/Lodge/Lodge.exe"
"$GODOT" --headless --path "$GAME" --export-release "macOS" "$WORK/mac/Lodge.zip"

# 4. Windows: Lodge.exe ひとつ（中身は exe に埋め込み）をフォルダごと zip に
(cd "$WORK/win" && zip -qr "$OUT/Lodge-windows.zip" Lodge)

# 5. Mac: Godot の雛形は Intel と Apple の両方入りしかないので、Apple の分だけにして署名し直す
cd "$WORK/mac"
unzip -q Lodge.zip && rm Lodge.zip
lipo Lodge.app/Contents/MacOS/Lodge -thin arm64 -output Lodge.arm64
mv Lodge.arm64 Lodge.app/Contents/MacOS/Lodge
codesign --force --deep -s - Lodge.app
ditto -c -k --keepParent Lodge.app "$OUT/Lodge-mac.zip"

ls -lh "$OUT"
