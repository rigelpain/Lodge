extends RefCounted

const Icons := preload("res://hud_icons.gd")
const Badges := preload("res://badges.gd")
## 右下の刺繍枠（自分の小窓）のまわりの、体の調子のバッジ（hud.gd が描く）。
## 紙の水は帯のゲージでは出さない（2026-11-01 代表「リニアなゲージUIって、常にチラ見して管理しなきゃいけないからこのゲームには窮屈」）。
## 濡れは刺繍枠の地の布のしみで見せる（self_cam.gd の MASK_SHADER の wet・crisp。hud.gd が入れる）。
## バッジは刺繍枠の右上に、枠に沿って並べ、出たときに跳ねる（2026-11-01 代表「バフデバフは刺繍の右上に置きましょう」）。
## 段が変わったときに跳ねて出るので、見張らなくても変わったことが分かる

const BADGE := 52.0             # バッジの直径（1080 のとき, px）
const BADGE_R := 42.0           # 窓の縁から、バッジの真ん中までの間（px。木の輪に少しかかる）
const BADGE_FROM := -1.0        # 1 枚目のバッジの向き（右上。刺繍枠の中心から、画面の座標、右が 0、下が正）
const BADGE_STEP := 0.46        # 2 枚目からの、枠に沿った間（rad。右下へ回る）


## バッジ。c は刺繍枠の真ん中、r は窓の半径（px）。pops は名前 → 跳ね（1→0）
static func draw(ci: CanvasItem, c: Vector2, r: float, u: float, badges: Array, pops: Dictionary) -> void:
	Icons.screen()
	for i in badges.size():
		var b: Dictionary = badges[i]
		var t: float = BADGE_FROM + i * BADGE_STEP
		var p := c + Vector2(cos(t), sin(t)) * (r + BADGE_R * u)
		Badges.draw_badge(ci, b, p, BADGE * u, 1.0, pops.get(b.key, 0.0))
	Icons.screen()
