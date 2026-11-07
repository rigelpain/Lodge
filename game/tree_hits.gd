extends StaticBody3D
## 木の当たり（丘・大きな山・大山に 1 つずつ。2026-11-07 代表「あれ、木に当たり判定ないかも」）。
## 当たるのは幹の芯だけ。根もとから木の高さの TOP まで、見た目の幹と同じ太さの丸棒（カプセル）を立てる。
## 裾や葉は当たらない（くぐって幹まで近づける。枝で引っかからない）。幹より上も芯があるので、跳んだソリも木の上半分を抜けない。
## 木は数百本あるので、節点を足さず、1 つの体に形だけを足す（create_shape_owner）。
## 木の置き場所はどの画面でも同じ種の乱数で決まるので、当たりも全員の画面で同じ。

const TOP := 0.9             # 芯のてっぺん（木の高さの割合）。先は円錐が細いので、芯が見た目から出ないように
const LAYER := 2             # 木だけを探す当たりの層（ソリが、ぶつかる幹を探すのに使う。ふつうの当たりは層 1 のまま）

static var _sizes := {}      # 木の glb → Vector2(幹の半径, 木の高さ)。倍率 1 のとき


func _init() -> void:
	collision_layer = 1 | LAYER
	add_to_group("tree_hits")


## 当たりの番号（光線や形の問い合わせの shape）の幹の根もと（世界）
func trunk_at(shape: int) -> Vector3:
	return global_transform * shape_owner_get_transform(shape_find_owner(shape)).origin


## その幹の半径 (m)
func radius_at(shape: int) -> float:
	return (shape_owner_get_shape(shape_find_owner(shape), 0) as CapsuleShape3D).radius


## 置いた木（位置と倍率を決めたあと）の幹の当たりを足す。木はこの体と同じ親の下にあること
func add_tree(tree: Node3D) -> void:
	var path := tree.scene_file_path
	if not _sizes.has(path):
		_sizes[path] = _measure(tree)
	var size: Vector2 = _sizes[path] * tree.scale.x
	var bottom := tree.position.y - size.x   # 丸い底が雪より下に隠れ、雪面では幹の太さになる
	var cap := CapsuleShape3D.new()
	cap.radius = size.x
	cap.height = size.y * TOP + size.x
	var own := create_shape_owner(self)
	shape_owner_add_shape(own, cap)
	shape_owner_set_transform(own, Transform3D(Basis.IDENTITY, Vector3(tree.position.x, bottom + cap.height * 0.5, tree.position.z)))


## 形から測る: 幹（*_wood）の半径と、木全体のてっぺんの高さ
static func _measure(tree: Node3D) -> Vector2:
	var radius := 0.0
	var high := 0.0
	for mi in tree.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		var p: Node = mi
		while p != tree:   # 木から見た形（木の位置と倍率は入れない）
			box = (p as Node3D).transform * box
			p = p.get_parent()
		high = maxf(high, box.end.y)
		if String(mi.name).ends_with("_wood"):
			radius = maxf(box.size.x, box.size.z) * 0.5
	return Vector2(radius, high)
