# Lodge

ゲレンデで大きなソリをみんなで押して丘を登り、一緒に乗って一気に下る、3D 一人称の協力ゲーム。Steam での販売を目指しています。

- 開発ダッシュボード: `docs/`（GitHub Pages で公開。中身は `docs/data.json` を書き換える）
- ゲーム本体（Godot 4.6）: `game/`
- 絵柄の見本: これから `prototypes/` に置く

## 原型を遊ぶ

Godot 4.6 で `game/project.godot` を開いて実行する。コマンドからなら:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

WASD で歩き、マウスで見回す。ソリに向かって W で押す。E で乗り降り（乗ったら W で前へ、A/D で曲がる）。R でソリをふもとへ戻す。青い仲間が一緒に押してくれる。

確かめ用の引数（`--` のあと）: `--bots=2`（仲間の数）、`--no-player`（仲間だけ）、`--log`（ソリの高さを1秒ごとに出す）、`--shot=絵.png`（数秒後に画面を保存）、`--quit-at=秒`。

## Claude Code のスキル

`.claude/skills/` に入れています（どちらも MIT）。

- `landing-page-design` … [elayadesign/ai-design-skills](https://github.com/elayadesign/ai-design-skills)（a2735a3）
- `semantic-web` ほか 9 本 … [nyattoh/semantic-web-skill](https://github.com/nyattoh/semantic-web-skill)（4b205c8）。本体は `.claude/semantic-web-skill/`、スキル内の相対リンクが通るよう `.claude/docs` などをリンクにしています
