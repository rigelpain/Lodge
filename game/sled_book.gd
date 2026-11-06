extends Node3D
## 布の見本帳（2026-11-06 代表「見本帖＋自由な色にしてほしい」）。ミシンの近く、下屋の前の雪の上に立つ。
## ぎざぎざに切ったフェルトの布を真鍮の輪で綴じて扇に開いた形（design/sled-custom/build_book.py）。
## 前で F を押すと、自分のソリの色と滑りあとの縫い目を替える画面が開く（sled_book_ui.gd）。
## この節の +Z が見本帳の正面。

const Props := preload("res://props.gd")

const REACH := 3.4           # F が届く距離 (m)
const FACE := 0.5            # 見本帳の方を向いている（見ている向きと見本帳への向きの合い具合）


func _ready() -> void:
	add_child(Props.make("res://props/sled_book/sled_book.glb"))
	var body := StaticBody3D.new()
	body.name = "BookBody"
	# 足もとの板と針山、扇のまんなか（脚と布の下の端は通れるように、当たりは板と脚の分だけ）
	for b in [[Vector3(1.5, 0.35, 0.95), Vector3(0, 0.175, -0.1)], [Vector3(0.9, 2.7, 0.3), Vector3(0, 1.45, -0.1)]]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[0]
		col.shape = box
		col.position = b[1]
		body.add_child(col)
	add_child(body)


func can_use(p: Node3D) -> bool:
	var d := global_position - p.global_position
	if absf(d.y) > 1.5:
		return false
	d.y = 0
	return d.length() <= REACH and (-p.global_basis.z).dot(d.normalized()) > FACE


func hint_at(_p: Node3D) -> Vector3:
	return global_position + Vector3.UP * 3.1
