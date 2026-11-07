extends RefCounted
## お金を払う施設の「近づくと動く」の見張り（2026-11-07 代表「お金を払う施設はすべて近づくと動きのあるインタラクションをすることで注意を引いてほしい」）。
## 自分・ボット・つないでいるほかの人のだれでも（emotes.gd の people。bandai_curtain.gd と同じ。Area3D は、ほかの人の当たりの層が 0 なので拾えない）。
## 毎フレーム見ないように、使う側は CHECK 秒ごとに呼ぶ

const CHECK := 0.25          # 人を見る間隔 (s)


## 施設 node の真ん中から水平に r m の内に人がいるか。front_z を入れると、node の座標の z がそれより後ろの人は数えない
static func someone_near(main: Node, node: Node3D, r: float, front_z := -INF) -> bool:
	var emotes: Node = main.get("emotes") if main else null
	if emotes == null:
		return false
	for who in emotes.people.values():
		if not is_instance_valid(who):
			continue
		var d: Vector3 = (who as Node3D).global_position - node.global_position
		if absf(d.y) > 2.0 or d.x * d.x + d.z * d.z > r * r:
			continue
		if front_z == -INF or node.to_local((who as Node3D).global_position).z > front_z:
			return true
	return false
