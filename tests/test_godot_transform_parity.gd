extends SceneTree
# Regression contract: Godot local/world transform and serialized pose must agree.
# This test is intentionally independent of the editor UI; device gestures remain unverified.
func _initialize() -> void:
	var parent := Transform3D(Basis.from_euler(Vector3(0.2, -0.4, 0.3)).scaled(Vector3(1.2, 1.2, 1.2)), Vector3(2.0, 1.0, -3.0))
	var child := Transform3D(Basis.from_euler(Vector3(-0.3, 0.5, 0.1)), Vector3(0.7, -1.2, 2.5))
	var expected := parent * child
	var root := Node3D.new()
	get_root().add_child(root)
	root.transform = parent
	var part := Node3D.new()
	root.add_child(part)
	part.transform = child
	if part.global_transform.origin.distance_to(expected.origin) > 0.0001:
		push_error("Parent/child global position differs from Godot matrix composition")
		quit(1)
		return
	var payload := {"position": [child.origin.x, child.origin.y, child.origin.z], "rotation": [part.quaternion.x, part.quaternion.y, part.quaternion.z, part.quaternion.w]}
	var parsed = JSON.parse_string(JSON.stringify(payload))
	if not parsed is Dictionary:
		push_error("Pose JSON roundtrip failed")
		quit(1)
		return
	var p: Array = parsed["position"]
	var q: Array = parsed["rotation"]
	var restored := Transform3D(Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))), Vector3(float(p[0]), float(p[1]), float(p[2])))
	var actual := parent * restored
	if actual.origin.distance_to(expected.origin) > 0.0001 or actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()) > 0.0001:
		push_error("Serialized local pose does not reproduce Godot world pose")
		quit(1)
		return
	print("GODOT TRANSFORM PARITY PASSED")
	quit(0)
