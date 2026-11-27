extends Node
## 起動のときの診断: このパソコンの絵の力に、画質の段（settings.gd の quality）を合わせる。
## 2026-11-13 代表「最初にスペック診断してそれに合わせて設定調整できると良いのかな」（Windows で 3D だけ真っ暗、という知らせから）
##
## 1. 真っ暗か: 始まって少しして、HUD を 1 コマ隠して 3D だけの絵を読み、ほとんど黒なら、まず色の照り返し（SSIL）を切り、
##    まだ黒なら光のにじみ（glow）も切って読み直す（main.gd の calm。非数が広がって持ち越される疑い）。それで映れば、切ったまま遊ぶ
##    （GPU と描き方ごとに spec.cfg の [calm] に残し、次からも起動のときに切る）。それでも黒なら、切った分を戻し、描き方を次へ替えて起動し直す
##    （Windows: Vulkan → Direct3D 12 → OpenGL、ほか: ふだんの描き方 → OpenGL）。描き方は user://render.cfg に書き、
##    project.godot の application/config/project_settings_override で起動のときに読む。始まりは朝 10 時なので、夜の暗さと取り違えない
## 2. 速さ: 画面が手前にある間の fps を測り、GOOD_FPS に届かなければ 1 段軽くして測り直す。届くか、いちばん軽い段で終わり
##    （2026-11-02 代表「FPS が 30 以下。低いと画面酔いすんだよね」。上限は 60 なので、揺れても 30 を割らないよう少し上で見る）
## 一度終えたら、GPU か描き方が替わるまでしない。測ったあとに自分で選んだ段は変えない。GPU が CPU（ソフトの描画）なら、はじめからガビガビ
## 確かめ用: --spec で引数があっても診断する、--spec-black で真っ暗とみなす、--spec-black-calm=数 で main.calm がその数に届くまでだけ真っ暗とみなす、
## --spec-fps=数 で測った fps をその数とみなす

const PATH := "user://spec.cfg"
const RENDER := "user://render.cfg"
const WARM := 3.0           # 測る前に待つ (s)。始めのシェーダーの組み立てで重いので
const SPAN := 4.0           # 測る長さ (s)
const GOOD_FPS := 40.0
const BLACK_PART := 0.9     # 3D の絵のこの割合より多くが黒なら、真っ暗
const BLACK_LEVEL := 0.02   # 黒とみなす明るさ（0〜1）

var main: Node   # main.gd
var _t := 0.0
var _frames := 0
var _span_t := 0.0
var _looked := false   # 真っ暗かを見た
var _looking := false  # 真っ暗かを見ている途中（照り返しなどを切って読み直している間は、速さを測らない）
var _key := ""


## 診断を置くか。引数で始めた確かめの道具は、--spec があるときだけ
static func wanted() -> bool:
	var a := OS.get_cmdline_user_args()
	return a.is_empty() or "--spec" in a


## このパソコン（GPU と描き方）の名前。診断の済み・切った分は、これごとに残す
static func key() -> String:
	return "%s|%s|%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()]


## このパソコンで、3D が真っ暗になるので切っておく分（main.gd の calm）。診断を置かない起動でも main.gd が読む
static func calm_level() -> int:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return int((cf.get_value("spec", "calm", {}) as Dictionary).get(key(), 0))


func _ready() -> void:
	_key = key()
	var cf := _cfg()
	if cf.get_value("spec", "done", "") == _key:
		queue_free()
		return
	print("診断: ", _key, "（種類 %d）" % RenderingServer.get_video_adapter_type())
	if cf.get_value("spec", "key", "") != _key:   # はじめて、または GPU・描き方が替わった
		cf.set_value("spec", "key", _key)
		cf.save(PATH)
		if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_CPU:
			_choose(0)


func _process(dt: float) -> void:
	if (not get_window().has_focus() and not main.args.has("spec")) or get_tree().paused:
		_t = 0.0   # 裏にいる間は遅くなるので、手前に戻ってから測り直す
		_frames = 0
		_span_t = 0.0
		return
	_t += dt
	if _t < WARM or _looking:
		return
	if not _looked:
		_looked = true
		_look_black()
		return
	_frames += 1
	_span_t += dt
	if _span_t < SPAN:
		return
	var fps := _frames / _span_t
	if main.args.has("spec-fps"):
		fps = float(main.args["spec-fps"])
	var q := int(main.settings.values.get("quality", 3))
	print("診断: 画質 %d で %.1f fps" % [q, fps])
	if fps >= GOOD_FPS or q <= 0:
		_finish()
		return
	_choose(q - 1)
	_t = WARM * 0.5   # 当て直した段で、少し待ってから測り直す
	_frames = 0
	_span_t = 0.0


func _choose(q: int) -> void:
	print("診断: 画質を %d（%s）へ" % [q, preload("res://settings.gd").QUALITY_NAMES[q]])
	main.settings.choose("quality", q)


func _finish() -> void:
	var cf := _cfg()
	cf.set_value("spec", "done", _key)
	cf.save(PATH)
	print("診断: おわり（画質 %d）" % int(main.settings.values.get("quality", 3)))
	queue_free()


## HUD を 1 コマ隠して 3D だけの絵を読み、ほとんど黒なら、照り返し → 光のにじみの順に切って読み直す。
## それで映れば切ったまま残す。切りきっても黒なら、切った分を戻して描き方を次へ替え、起動し直す
func _look_black() -> void:
	_looking = true
	var black: bool = await _is_black()
	var was: int = main.calm
	while black and main.calm < main.CALM_GLOW:
		main.calm += 1
		print("診断: 3D が真っ暗なので、%s を切って見直す" % ("色の照り返し" if main.calm == main.CALM_SSIL else "光のにじみ"))
		_apply_calm()
		for i in 6:   # 切ったあとのコマが描き上がるまで（照り返しは前のコマを読むので、少し待つ）
			await RenderingServer.frame_post_draw
		black = await _is_black()
	_looking = false
	if not black:
		if main.calm != was:
			var cf := _cfg()
			var calm: Dictionary = cf.get_value("spec", "calm", {})
			calm[_key] = main.calm
			cf.set_value("spec", "calm", calm)
			cf.save(PATH)
			print("診断: 切ったら映った。このパソコンでは切ったまま（calm %d）" % main.calm)
		return
	main.calm = was   # 切っても黒い: 照り返しとにじみのせいではない。戻してから描き方を替える
	_apply_calm()
	_next_renderer()


## main.calm を、いまの設定の値と合わせて環境に当て直す
func _apply_calm() -> void:
	main._apply_setting("ssao", main.settings.values.get("ssao", true))
	main._apply_setting("glow", main.settings.values.get("glow", true))


## HUD を 1 コマ隠して 3D だけの絵を読み、ほとんど黒か
func _is_black() -> bool:
	var hidden: Array[CanvasLayer] = []
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n.visible:
			n.visible = false
			hidden.append(n)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for n in hidden:
		if is_instance_valid(n):
			n.visible = true
	var dark := 0
	var all := 0
	for y in 9:
		for x in 16:
			var c := img.get_pixel(int((x + 0.5) / 16.0 * img.get_width()), int((y + 0.5) / 9.0 * img.get_height()))
			all += 1
			if maxf(c.r, maxf(c.g, c.b)) < BLACK_LEVEL:
				dark += 1
	print("診断: 3D の絵の黒 %d / %d" % [dark, all])
	if main.args.has("spec-black-calm"):
		return main.calm < int(main.args["spec-black-calm"])
	return float(dark) / all >= BLACK_PART or main.args.has("spec-black")


## 試す描き方の順。それぞれ [描き方, Windows のドライバ]
static func steps() -> Array:
	if OS.get_name() == "Windows":
		return [["forward_plus", "vulkan"], ["forward_plus", "d3d12"], ["gl_compatibility", ""]]
	return [["forward_plus", ""], ["gl_compatibility", ""]]


func _next_renderer() -> void:
	var cf := _cfg()
	var tried: Array = cf.get_value("spec", "tried", [])
	tried.append(_key)
	cf.set_value("spec", "tried", tried)
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name().to_lower()
	var all := steps()
	var at := -1
	for i in all.size():
		if all[i][0] == method and (all[i][1] == "" or all[i][1] == driver):
			at = i
	if at < 0 or at + 1 >= all.size():
		print("診断: 真っ暗だが、もう試す描き方がない")
		cf.save(PATH)
		_finish()
		return
	var nx: Array = all[at + 1]
	var rc := ConfigFile.new()
	rc.set_value("rendering", "renderer/rendering_method", nx[0])
	if nx[1] != "":
		rc.set_value("rendering", "rendering_device/driver.windows", nx[1])
	rc.save(RENDER)
	cf.save(PATH)
	print("診断: 真っ暗なので、描き方を %s %s にして起動し直す" % [nx[0], nx[1]])
	# 「--」のあとの確かめ用の引数は渡さない（渡すと Godot の起動し直しが立ち上がらなかった。遊ぶ人は引数なしで起動する）
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


func _cfg() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return cf
