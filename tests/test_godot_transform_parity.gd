extends SceneTree
# Regression contract: Godot local/world transform and serialized pose must agree.
# This test is intentionally independent of the editor UI; device gestures remain unverified.
func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var parent := Transform3D(Basis.from_euler(Vector3(0.2, -0.4, 0.3)).scaled(Vector3(1.2, 1.2, 1.2)), Vector3(2.0, 1.0, -3.0))
	var child := Transform3D(Basis.from_euler(Vector3(-0.3, 0.5, 0.1)).scaled(Vector3(0.8, 1.3, 1.1)), Vector3(0.7, -1.2, 2.5))
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
	# Store the complete Basis columns: quaternion + scale decomposition may lose shear
	# or alter non-uniform scale ordering in a hierarchy.
	var payload := {"position": [child.origin.x, child.origin.y, child.origin.z], "basis": [[child.basis.x.x, child.basis.x.y, child.basis.x.z], [child.basis.y.x, child.basis.y.y, child.basis.y.z], [child.basis.z.x, child.basis.z.y, child.basis.z.z]]}
	var parsed = JSON.parse_string(JSON.stringify(payload))
	if not parsed is Dictionary:
		push_error("Pose JSON roundtrip failed")
		quit(1)
		return
	var p: Array = parsed["position"]
	var b: Array = parsed["basis"]
	var restored_basis := Basis(Vector3(float(b[0][0]), float(b[0][1]), float(b[0][2])), Vector3(float(b[1][0]), float(b[1][1]), float(b[1][2])), Vector3(float(b[2][0]), float(b[2][1]), float(b[2][2])))
	var restored := Transform3D(restored_basis, Vector3(float(p[0]), float(p[1]), float(p[2])))
	var actual := parent * restored
	if actual.origin.distance_to(expected.origin) > 0.0001 or actual.basis.x.distance_to(expected.basis.x) > 0.0001 or actual.basis.y.distance_to(expected.basis.y) > 0.0001 or actual.basis.z.distance_to(expected.basis.z) > 0.0001:
		push_error("Serialized local pose does not reproduce Godot world pose")
		quit(1)
		return
	print("GODOT TRANSFORM PARITY PASSED")
	quit(0)
