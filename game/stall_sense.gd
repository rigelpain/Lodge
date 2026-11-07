extends RefCounted
## お金を払う施設の「近づくと動く」の見張り（2026-11-07 代表「お金を払う施設はすべて近づくと動きのあるインタラクションをすることで注意を引いてほしい」）。
## 自分・ボット・つないでいるほかの人のだれでも（emotes.gd の people。bandai_curtain.gd と同じ。Area3D は、ほかの人の当たりの層が 0 なので拾えない）。
## 毎フレーム見ないように、使う側は CHECK 秒ごとに呼ぶ

const CHECK := 0.25          # 人を見る間隔 (s)


## 施設 node の真ん中から水平に r m の内で、いちばん近い人（いなければ null）。front_z を入れると、node の座標の z がそれより後ろの人は数えない
static func nearest(main: Node, node: Node3D, r: float, front_z := -INF) -> Node3D:
	var emotes: Node = main.get("emotes") if main else null
	if emotes == null:
		return null
	var best: Node3D = null
	var best_d := r * r
	for who in emotes.people.values():
		if not is_instance_valid(who):
			continue
		var p: Node3D = who
		var d: Vector3 = p.global_position - node.global_position
		var h := d.x * d.x + d.z * d.z
		if absf(d.y) > 2.0 or h > best_d:
			continue
		if front_z == -INF or node.to_local(p.global_position).z > front_z:
			best = p
			best_d = h
	return best
