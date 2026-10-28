@tool
extends Node3D
## 小物を組み合わせた場面（game/props/sets/*.tscn）。下に置いた glb に、手芸の素材と灯りを着せる。
## 場面は props/build_scenes.py が書き出す。置き方は Blender で確かめた配置と同じ。

const Props := preload("res://props.gd")


func _ready() -> void:
	Props.dress(self)
