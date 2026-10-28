extends SceneTree
## 乗っているときの操作の確かめ用（数字だけ出す。画面は使わない）。
##   Godot --headless --path game -s res://tools/ride_check.gd -- --case=<名前> [main.gd の引数]
##
## 登る速さ（同じ区間を登る時間。ソリの高さが 8 m → 16 m になるまで。スタートは約 6.8 m）:
##   --case=climb --no-player --bots=2            二人で押す
##   --case=climb --no-player --bots=1            一人で押す
##   --case=climb --bots=1 --ride --keys=W        あなたが乗って W、仲間一人が押す
##   --case=climb --bots=1 --ride --keys=         あなたが乗って何もしない、仲間一人が押す
##   --case=climb --bots=2 --ride --keys=         あなたが乗って何もしない、仲間二人が押す
## 曲がりやすさ（あなた一人が乗る。--bots=0 で使う）:
##   --case=turn-fast --bots=0   頂上から W で滑り降り、6 m/s を超えたら D を 1 秒。向きの変わり方を出す
##   --case=turn-slow --bots=0   ふもとの先の平らな所で、止まった所から W と D を 3 秒。向きの変わり方を出す

const FROM_Y := 8.0
const TO_Y := 16.0

var args := {}
var main: Node3D
var t := 0.0
var _seated := false
var _t_from := -1.0
var _t_to := -1.0
var _keys := {}
var _phase := 0
var _t_phase := 0.0
var _yaw0 := 0.0
var _speed_sum := 0.0
var _speed_n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _key(k: Key, on: bool) -> void:
	if _keys.get(k, false) == on:
		return
	_keys[k] = on
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _sit(at: Vector3, yaw: float) -> void:
	var sled: RigidBody3D = main.sled
	sled.reset_to(at)
	sled.rotation.y = yaw
	var p = main.player
	p.global_position = sled.global_position + sled.global_basis.x * 1.5
	p.get_on()


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + 0.6, z)


func _physics_process(dt: float) -> bool:
	t += dt
	var sled: RigidBody3D = main.sled
	if sled == null:
		return false
	match args.get("case", "climb"):
		"climb":
			_climb(sled)
		"turn-fast":
			_turn_fast(sled, dt)
		"turn-slow":
			_turn_slow(sled, dt)
	if t > float(args.get("secs", "90")):
		print("時間切れ t=%.1f 高さ=%.2f" % [t, sled.global_position.y])
		quit()
	return false


func _climb(sled: RigidBody3D) -> void:
	var p = main.player
	if args.has("ride") and p and not _seated and t > 0.5:
		_seated = true
		p.global_position = sled.global_position + sled.global_basis.x * 1.5
		p.get_on()
		for c in args.get("keys", "W"):
			_key(OS.find_keycode_from_string(c), true)
		print("乗る: mode=%d 乗る人=%d" % [p.mode, sled.riders.size()])
	var y: float = sled.global_position.y
	if _t_from < 0.0 and y >= FROM_Y:
		_t_from = t
	if _t_to < 0.0 and y >= TO_Y:
		_t_to = t
		print("結果: 高さ %.0f→%.0f m に %.1f 秒（%.0f m に着いたのは t=%.1f）" % [FROM_Y, TO_Y, _t_to - _t_from, TO_Y, t])
		quit()


## 頂上から +Z（ふもと）へ向けて乗り、W で滑り出す。6 m/s を超えたら D を 1 秒
func _turn_fast(sled: RigidBody3D, dt: float) -> void:
	if not _seated and t > 0.3:
		_seated = true
		_sit(_ground(0, 3), PI)   # 回転 PI でソリの前（-Z）が +Z を向く
		_key(KEY_W, true)
	if not _seated:
		return
	var v: float = sled.linear_velocity.length()
	if _phase == 0 and v > 6.0:
		_phase = 1
		_t_phase = t
		_yaw0 = sled.rotation.y
		_key(KEY_D, true)
	elif _phase == 1:
		_speed_sum += v
		_speed_n += 1
		if t - _t_phase >= 1.0:
			var d := rad_to_deg(wrapf(sled.rotation.y - _yaw0, -PI, PI))
			print("結果: 速いとき D 1 秒で向きが %.1f° 変わる（平均の速さ %.1f m/s）" % [d, _speed_sum / _speed_n])
			quit()


## 丘から離れた平らな所で、止まった所から W と D を 3 秒
func _turn_slow(sled: RigidBody3D, dt: float) -> void:
	if not _seated and t > 0.3:
		_seated = true
		_sit(_ground(90, 0), 0.0)
	if not _seated:
		return
	if _phase == 0 and t > 1.0:
		_phase = 1
		_t_phase = t
		_yaw0 = sled.rotation.y
		_key(KEY_W, true)
		_key(KEY_D, true)
	elif _phase == 1:
		_speed_sum += sled.linear_velocity.length()
		_speed_n += 1
		if t - _t_phase >= 3.0:
			var d := rad_to_deg(wrapf(sled.rotation.y - _yaw0, -PI, PI))
			print("結果: 止まった所から W+D 3 秒で向きが %.1f° 変わる（平均の速さ %.2f m/s）" % [d, _speed_sum / _speed_n])
			quit()
