extends Node
## 体のぬくもり（2026-11-01 代表「火に当たるより温かいゲージは小さくあがるけど下がりづらくなって長く続く感じ」。design/snowman-food/）。
## 人ごとに 2 つ持つ:
##   fire  暖炉・ロッジの暖かさ（temperature.gd の calm_of）。そこにいると早く上がり、外へ出ると早く冷める
##   food  食べた物の温かさ（food.gd の warmth。ひと口ではなく食べ終えたときに足す）。少しだけ上がり、外でもゆっくり長く残る。
##         重ねて食べると足されて長く続く（1 まで）
## 食べたぬくもり（food）が残っているあいだ:
##   ・外でもふるえにくい（doll.gd の warm_food がふるえを弱める。白い息はそのまま）
##   ・ソリを押す力が少し増す（player.gd・bot.gd の push_boost。sled.gd の push がかける）
## あなたのぬくもりは、画面の右に湯たんぽの絵で出す（文字なし）。下から赤が食べたぬくもり、その上の橙が暖炉のぬくもり

const Temp := preload("res://temperature.gd")
const Icons := preload("res://hud_icons.gd")

const FIRE_UP := 2.5         # 暖かい所で fire が追いつく時定数 (s)
const FIRE_DOWN := 5.0       # 寒い所で冷める時定数 (s)。食べ物よりずっと早い
const FOOD_FADE := 1.0 / 540.0   # food が 1 秒に減る量（0.3 の食べ物で約 2.7 分残る）
const SHIVER_CUT := 0.85     # 食べたぬくもりで、ふるえをいちばんこれだけ弱める
const PUSH_MORE := 0.2       # 食べたぬくもりで、押す力をいちばんこれだけ増やす（2 割）

var main: Node
var fire := {}               # 人の番号 → 0〜1
var food := {}               # 人の番号 → 0〜1
var _hud: CanvasLayer


func _ready() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 3
	add_child(_hud)
	var v := Pouch.new()
	v.w = self
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(v)


## 食べ終えた（craft.gd の bite で ev.ate が入ったとき、main.gd から呼ぶ）
func ate(who: int, dish: String) -> void:
	var Food := preload("res://food.gd")
	food[who] = minf(1.0, float(food.get(who, 0.0)) + Food.warmth(dish))


## 食べたぬくもりの効き（0〜1）。少しでも残っていれば効き始め、0.3 あればほぼいっぱい
func food_k(who: int) -> float:
	return clampf(float(food.get(who, 0.0)) * 3.0, 0.0, 1.0)


func _physics_process(dt: float) -> void:
	var hub = main.get("emotes") if main else null
	if hub == null:
		return
	var temp := get_node_or_null("/root/Temperature")
	for id in hub.people:
		var who: Node3D = hub.who_of(id)
		if who == null:
			continue
		var want: float = Temp.calm_of(temp.at(who.global_position)) if temp else 0.0
		var f: float = fire.get(id, want)
		fire[id] = lerpf(f, want, 1.0 - exp(-dt / (FIRE_UP if want > f else FIRE_DOWN)))
		food[id] = maxf(0.0, float(food.get(id, 0.0)) - FOOD_FADE * dt)
		var k := food_k(id)
		var doll = who.get("doll")
		if doll and is_instance_valid(doll):
			doll.set("warm_food", k * SHIVER_CUT)
		who.set("push_boost", 1.0 + PUSH_MORE * k)


class Pouch extends Control:
	var w: Node
	var _shown := 0.0

	func _process(_dt: float) -> void:
		queue_redraw()

	## 湯たんぽ: 生成りの編み地のカバーをかけた丸い袋。中のぬくもりが下から満ちる（赤 = 食べた物、橙 = 暖炉）
	func _draw() -> void:
		var p = w.main.get("player") if w.main else null
		if p == null:
			return
		var id := int(p.get("id"))
		var fo: float = w.food.get(id, 0.0)
		var fi: float = w.fire.get(id, 0.0)
		var total := clampf(fo + fi, 0.0, 1.0)
		_shown = lerpf(_shown, 1.0 if total > 0.03 else 0.0, 0.15)
		if _shown < 0.02:
			return
		var u := Icons.ui_scale(size.y)
		var bw := 40.0 * u
		var bh := 64.0 * u
		var c := Vector2(size.x - 34.0 * u - bw / 2.0, size.y * 0.42)
		var a := _shown
		Icons.screen()
		# 栓と首
		Icons.patch(self, Icons.rr(c.x - 7.0 * u, c.y - bh / 2.0 - 12.0 * u, 14.0 * u, 14.0 * u, 4.0 * u), Color(0.55, 0.36, 0.22), a, false)
		# 袋の外形（生成りの編み地のカバー）
		var body := Icons.rr(c.x - bw / 2.0, c.y - bh / 2.0, bw, bh, 14.0 * u)
		Icons.patch(self, body, Color(0.96, 0.92, 0.84), a, true, Color(0.70, 0.57, 0.38))
		# 中身: 下から食べたぬくもり（赤）、その上に暖炉のぬくもり（橙）
		var inner := Rect2(c.x - bw / 2.0 + 6.0 * u, c.y - bh / 2.0 + 6.0 * u, bw - 12.0 * u, bh - 12.0 * u)
		var hf := inner.size.y * clampf(fo, 0.0, 1.0)
		var hi := inner.size.y * clampf(fi, 0.0, 1.0 - clampf(fo, 0.0, 1.0))
		if hf > 0.5:
			Icons.patch(self, Icons.rr(inner.position.x, inner.end.y - hf, inner.size.x, hf, 6.0 * u), Color(0.80, 0.24, 0.20), a, false)
		if hi > 0.5:
			Icons.patch(self, Icons.rr(inner.position.x, inner.end.y - hf - hi, inner.size.x, hi, 6.0 * u), Color(0.93, 0.58, 0.24), a, false)
		# 編み目の横縞（カバーの編み地）
		for k in 4:
			var y := inner.position.y + inner.size.y * (k + 0.5) / 4.0
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.98, 0.95, 0.88, 0.35 * a), 1.2 * u, true)
