extends SceneTree
## 染め桶の決まりを確かめる（画面なしで動く）。
##   Godot --headless --path game -s res://tools/dye_check.gd
## 染め代を 1 回ごとに取る・同じ色では染めない・足りなければ断る・保存の戻しはただ・人形ごとに色が残る・布の数にそろえる

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
	c.wallets[1] = 100
	var start: int = c.wallet(1)
	_ok("染める（kasa の 2 枚の布）", c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["c9603c", "d8a43e"]}))
	_ok("染め代を 1 回ぶん取る", c.wallet(1) == start - Craft.DYE_PRICE)
	_ok("同じ色では染めない", not c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["C9603C", "d8a43e"]}))
	_ok("断ったら取らない", c.wallet(1) == start - Craft.DYE_PRICE)
	_ok("1 枚めだけ戻す", c.send({"kind": "dye", "who": 1, "doll": "kasa", "colors": ["", "d8a43e"]}))
	_ok("戻すのも 1 回の染め", c.wallet(1) == start - 2 * Craft.DYE_PRICE)
	var o: Array = c.outfit_of(1, "kasa")
	_ok("1 枚めはもとの色・2 枚めは色", o.size() == 2 and o[0] == null and o[1] is Color)
	_ok("布の数にそろえる（origami は 1 枚。余りは捨てる）", c.send({"kind": "dye", "who": 1, "doll": "origami", "colors": ["3f6b4a", "ffffff"]}) \
			and c.outfits[1]["origami"] == ["3f6b4a"])
	_ok("ほかの人形の色は残る", (c.outfit_of(1, "kasa")[1] as Color).to_html(false) == "d8a43e")
	_ok("ない人形は断る", not c.send({"kind": "dye", "who": 1, "doll": "nobody", "colors": ["ffffff"]}))
	_ok("全部もとの色に戻すと、帳面から消える", c.send({"kind": "dye", "who": 1, "doll": "origami", "colors": [""]}) and not c.outfits[1].has("origami"))
	c.wallets[1] = Craft.DYE_PRICE - 1
	_ok("足りなければ断る", not c.send({"kind": "dye", "who": 1, "doll": "news", "colors": ["7a4a6e"]}))
	_ok("保存の戻し（outfit）はただ", c.send({"kind": "outfit", "who": 1, "doll": "news", "colors": ["7a4a6e"]}) and c.wallet(1) == Craft.DYE_PRICE - 1)
	_ok("色でない文字は、もとの色", Craft.dye_colors("musha", ["zz", Color("d8a43e")]) == ["", "d8a43e"])
	var Outfit := preload("res://outfit.gd")
	_ok("一人称の袖: 緑の着物の色が染まる", Outfit.tint("kasa", Color("3E6E66"), [Color("c9603c")]).h < 0.1)
	_ok("一人称の袖: 布でない色（手の色）は残る", Outfit.tint("kasa", Color("F0D2A6"), [Color("c9603c")]).is_equal_approx(Color("F0D2A6")))
	print("ぜんぶ OK" if fails == 0 else "NG が %d" % fails)
	quit(1 if fails else 0)
