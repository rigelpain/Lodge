# 旧・夏虫沢ヒュッテ（天下森のワールドのロッジ）

天下森スキー場の旧・夏虫沢ヒュッテ（平成7年竣工・木造平屋・284㎡、2019 年のストリートビューの姿）を、図面に起こしてからゲームで組む。

- `dims.py`: 寸法（平面図の 14,000 を物差しにして読んだ。高さは写真からの見積もり）
- `draw_plans.py`: 図面（平面図・入口の妻・4 面の立面図）を描く → `design/tenkamori/hutte-old/01-plans.png`
- ゲームの側: `game/hutte.gd`（定数は dims.py の写し。変えるときは両方を直す）

```bash
python draw_plans.py ../design/tenkamori/hutte-old/01-plans.png
```

matplotlib が要る。手本と出どころは `tenkamori/README.md` の台帳。
