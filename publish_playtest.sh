#!/bin/bash
# build_release.sh で作った zip を GitHub Releases に載せる。載せるとテストプレイのページ（docs/playtest.html）に出る。
#   ./publish_playtest.sh                         build/ のいちばん新しい zip を載せる
#   ./publish_playtest.sh build/2026-11-13-42403e1  場所を決めて載せる
# 版の名前（タグ）は playtest-<日付>-<コミット>。「変わったこと」は前の版からのコミットの題名。
# 要るもの: gh（gh auth login 済み）。リポジトリは公開なので、載せた zip は URL を知っていればだれでも取れる。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
DIR=${1:-$(ls -d "$ROOT"/build/????-??-??-*/ 2>/dev/null | sort | tail -1)}
DIR=${DIR%/}
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
	echo "zip の場所が見つかりません。先に ./build_release.sh を動かしてください" >&2
	exit 1
fi
NAME=$(basename "$DIR")
WIN="$DIR/Lodge-windows.zip"
MAC="$DIR/Lodge-mac.zip"
for f in "$WIN" "$MAC"; do
	[ -f "$f" ] || { echo "$f がありません" >&2; exit 1; }
done

DATE=${NAME:0:10}
SHORT=${NAME:11}
SHA=$(git -C "$ROOT" rev-parse --verify "$SHORT^{commit}")
TAG="playtest-$NAME"

if gh release view "$TAG" -R rigelpain/Lodge > /dev/null 2>&1; then
	echo "$TAG はもう載っています。https://github.com/rigelpain/Lodge/releases/tag/$TAG" >&2
	exit 1
fi

# 前の版（このコミットより前の playtest-* でいちばん新しいもの）からのコミットを並べる
git -C "$ROOT" fetch -q --tags origin || true
PREV=""
for t in $(git -C "$ROOT" tag -l 'playtest-*' | sort -r); do
	if git -C "$ROOT" merge-base --is-ancestor "$t" "$SHA" 2>/dev/null && [ "$(git -C "$ROOT" rev-parse "$t^{commit}")" != "$SHA" ]; then
		PREV=$t
		break
	fi
done
if [ -n "$PREV" ]; then
	LOG=$(git -C "$ROOT" log --no-merges --format='- %s' "$PREV..$SHA")
	HEAD_LINE="前の版（$PREV）から変わったこと:"
else
	LOG=$(git -C "$ROOT" log --no-merges --format='- %s' -n 15 "$SHA")
	HEAD_LINE="最近のコミット:"
fi
[ -n "$LOG" ] || LOG="- （コミットの違いはありません）"

NOTES=$(printf '%s\n\n%s\n\n遊び方: https://rigelpain.github.io/Lodge/playtest.html\n' "$HEAD_LINE" "$LOG")

echo "載せます: $TAG（$(du -ch "$WIN" "$MAC" | tail -1 | cut -f1)）"
gh release create "$TAG" "$WIN" "$MAC" \
	-R rigelpain/Lodge \
	--target "$SHA" \
	--title "テスト版 $DATE（$SHORT）" \
	--notes "$NOTES" \
	--latest

echo "載せました。ページ: https://rigelpain.github.io/Lodge/playtest.html"
