extends SceneTree
# Run: godot --headless --path . --script res://tests/transform_roundtrip.gd
# Baseline engine contract: parent/child transforms, JSON numeric persistence,
# and quaternion interpolation. This does NOT test application exporters.
const EPS := 0.0001
var failed := false

func _initialize() -> void:
    var parent := Transform3D(Basis.from_euler(Vector3(0.2, 0.5, -0.1)).scaled(Vector3(1.2, 1.2, 1.2)), Vector3(3.0, -2.0, 1.0))
    var child := Transform3D(Basis.from_euler(Vector3(-0.3, 0.1, 0.4)), Vector3(0.4, 1.2, -0.8))
    var world := parent * child
    var local_again := parent.affine_inverse() * world
    _check(local_again.origin.distance_to(child.origin) < EPS, "parent/child position")
    _check(local_again.basis.is_equal_approx(child.basis), "parent/child basis")

    var payload := {"position": [world.origin.x, world.origin.y, world.origin.z], "time": 1.25}
    var parsed = JSON.parse_string(JSON.stringify(payload))
    _check(parsed is Dictionary, "JSON dictionary")
    if parsed is Dictionary:
        var coords: Array = parsed.get("position", [])
        _check(coords.size() == 3, "JSON coordinate count")
        if coords.size() == 3:
            var restored := Vector3(float(coords[0]), float(coords[1]), float(coords[2]))
            _check(restored.distance_to(world.origin) < EPS, "JSON position roundtrip")
        _check(absf(float(parsed.get("time", 0.0)) - 1.25) < EPS, "JSON timeline roundtrip")

    var q0 := Quaternion.IDENTITY
    var q1 := Quaternion(Vector3.UP, PI / 2.0)
    var midpoint := q0.slerp(q1, 0.5)
    _check(absf(midpoint.get_angle() - PI / 4.0) < EPS, "rotation interpolation")
    if failed:
        quit(1)
    else:
        print("Transform roundtrip baseline: PASS")
        quit(0)

func _check(condition: bool, label: String) -> void:
    if not condition:
        push_error("Transform roundtrip baseline: FAIL: " + label)
        quit(1)
