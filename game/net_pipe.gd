extends Node
## 通信の口ひとつ（net.gd が送り方ごとに 1 つずつ置く）。ノード 1 つに口（_in）を 1 つだけにする。
## 1 つのノードに口が複数あると、Godot が口に振る番号は名前の並べ方で決まる。その並びが画面ごとに変わらないよう、
## 念のため口は 1 つにして、中身の先頭（"state" "up" など）で分ける。
## 送り方（確かに届く・届かなくてよい）と流れの番号は、net.gd が置くときに rpc_config で決める

var net: Node


func _in(m: Array) -> void:
	net.receive(multiplayer.get_remote_sender_id(), m)
