extends SceneTree
## 染め桶の決まりを確かめる（画面なしで動く）。
##   Godot --headless --path game -s res://tools/dye_check.gd
## 染め代は変える部位の数で上がる・同じ色では染めない・足りなければ断る・保存の戻しはただ・人形ごとに色が残る・前の保存を部位に直す

const Craft := preload("res://craft.gd")

var fails := 0


func _ok(what: String, cond: bool) -> void:
	print(("OK  " if cond else "NG  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	var c := Craft.new()
	root.add_child(c)
	c.join(1)
	c.wallets[1] = 200
	var start: int = c.wallet(1)
	var P: Array = Craft.DYE_PRICES
	_ok("部位が多いほど高い", P[1] < P[2] and P[2] < P[3] and P[3] < P[4])
	_ok("まとめて染めると 1 部位ぶんずつは安い", P[2] < 2 * P[1] and P[4] < 4 * P[1])
	_ok("染める（kasa の主の色と 3 番目）", c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["c9603c", "", "d8a43e", ""]}))
	_ok("2 部位ぶんの染め代を取る", c.wallet(1) == start - P[2])
	_ok("同じ色では染めない", not c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["C9603C", "", "d8a43e", ""]}))
	_ok("断ったら取らない", c.wallet(1) == start - P[2])
	_ok("主の色だけ戻す", c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["", "", "d8a43e", ""]}))
	_ok("戻すのも 1 部位の染め", c.wallet(1) == start - P[2] - P[1])
	var o: Array = c.outfit_of(1, "kasa")
	_ok("部位は 4 つ。主はもとの色・3 番目は色", o.size() == 4 and o[0] == null and o[2] is Color)
	var w: int = c.wallet(1)
	_ok("4 部位とも染める（golem）", c.send({"kind": "dye", "who": 1, "doll": "golem", "colors": ["aa3322", "3355aa", "ddbb33", "33aa55"]}) \
			and c.wallet(1) == w - P[4] and c.outfits[1]["golem"] == ["aa3322", "3355aa", "ddbb33", "33aa55"])
	_ok("ほかの人形の色は残る", (c.outfit_of(1, "kasa")[2] as Color).to_html(false) == "d8a43e")
	_ok("ない人形は断る", not c.send({"kind": "dye", "who": 1, "doll": "nobody", "colors": ["ffffff"]}))
	_ok("全部もとの色に戻すと、帳面から消える", c.send({"kind": "dye", "who": 1, "doll": "golem", "colors": ["", "", "", ""]}) and not c.outfits[1].has("golem"))
	c.wallets[1] = P[2] - 1
	_ok("足りなければ断る（2 部位）", not c.send({"kind": "dye", "who": 1, "doll": "news", "colors": ["7a4a6e", "", "", "3f6b4a"]}))
	_ok("1 部位なら足りる", c.send({"kind": "dye", "who": 1, "doll": "news", "colors": ["", "", "", "3f6b4a"]}))
	c.wallets[1] = 0
	_ok("保存の戻し（outfit）はただ", c.send({"kind": "outfit", "who": 1, "doll": "robo", "colors": ["7a4a6e", "", "", ""]}) and c.wallet(1) == 0)
	_ok("色でない文字は、もとの色", Craft.dye_colors("musha", ["zz", Color("d8a43e"), "", ""]) == ["", "d8a43e", "", ""])
	# 前の保存（布ごとの 1〜2 色）は、部位に直して読む
	_ok("前の保存の 1 色は主の色", Craft.dye_colors("origami", ["3f6b4a"]) == ["3f6b4a", "", "", ""])
	_ok("前の保存: golem の 2 枚めの布（茶の継ぎ当て）は 3 番目", Craft.dye_colors("golem", ["aa3322", "ddbb33"]) == ["aa3322", "", "ddbb33", ""])
	_ok("前の保存: news の上着の色は、上着と頭巾の両方", Craft.dye_colors("news", ["7a4a6e"]) == ["7a4a6e", "7a4a6e", "", ""])
	_ok("前の保存（outfit）を読み込める", c.send({"kind": "outfit", "who": 1, "doll": "kasa", "colors": ["c9603c", "d8a43e"]}) \
			and c.outfits[1]["kasa"] == ["c9603c", "d8a43e", "", ""])
	var Outfit := preload("res://outfit.gd")
	_ok("7 体とも塗り分けの絵がある", ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"].all(func(k): return Outfit.mask(k) != null))
	_ok("7 体とも部位が 4 つ", ["kasa", "origami", "news", "robo", "musha", "ningyo", "golem"].all(func(k): return Outfit.cloth_count(k) == 4))
	_ok("一人称の袖: 緑の着物の色が染まる", Outfit.tint("kasa", "sleeve", 0, Color("3E6E66"), [Color("c9603c"), null, null, null]).h < 0.1)
	_ok("一人称の袖: 白い水玉は残る", Outfit.tint("kasa", "sleeve", 0, Color("CFE0D6"), [Color("c9603c"), null, null, null]).is_equal_approx(Color("CFE0D6")))
	_ok("一人称の袖: golem の灰色の腕は 2 番目の色", Outfit.tint("golem", "sleeve", 1, Color("8C877F"), [null, Color("3355aa"), null, null]).b > 0.5)
	_ok("一人称の脚: 染めない部位なら、そのまま", Outfit.tint("golem", "leg", 0, Color("8C877F"), [null, Color("3355aa"), null, null]).is_equal_approx(Color("8C877F")))
	print("ぜんぶ OK" if fails == 0 else "NG が %d" % fails)
	quit(1 if fails else 0)
