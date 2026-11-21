extends SceneTree

# Standalone Godot 4 headless regression: parent/child transforms and JSON round-trip.
const EPS := 0.0001

func _initialize() -> void:
    var parent := Node3D.new()
    var child := Node3D.new()
    root.add_child(parent)
    parent.add_child(child)
    parent.position = Vector3(2.0, 1.0, -3.0)
    parent.rotation_degrees = Vector3(0.0, 45.0, 0.0)
    parent.scale = Vector3(1.5, 1.5, 1.5)
    child.position = Vector3(0.5, 2.0, -1.0)
    child.rotation_degrees = Vector3(10.0, 20.0, 30.0)
    var expected := parent.global_transform * child.transform
    if not _close_transform(expected, child.global_transform):
        _fail("parent-child global transform mismatch")
        return
    var payload := {"position": [child.position.x, child.position.y, child.position.z], "time": 1.25}
    var encoded := JSON.stringify(payload)
    var decoded = JSON.parse_string(encoded)
    if typeof(decoded) != TYPE_DICTIONARY:
        _fail("JSON round-trip did not produce a dictionary")
        return
    var p: Array = decoded["position"]
    var restored := Vector3(float(p[0]), float(p[1]), float(p[2]))
    if restored.distance_to(child.position) > EPS or absf(float(decoded["time"]) - 1.25) > EPS:
        _fail("JSON position/time round-trip mismatch")
        return
    print("PASS: parent-child transforms and JSON round-trip")
    quit(0)

func _close_transform(a: Transform3D, b: Transform3D) -> bool:
    if a.origin.distance_to(b.origin) > EPS:
        return false
    for i in range(3):
        if (a.basis[i] - b.basis[i]).length() > EPS:
            return false
    return true

func _fail(message: String) -> void:
    push_error(message)
    quit(1)
