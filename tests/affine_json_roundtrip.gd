extends SceneTree
# Affine transform round-trip contract: nonuniform scale, reflected axes and shear.
# Independent of app exporter; integration parity remains a separate acceptance gate.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var parent := Node3D.new()
    root.add_child(parent)
    parent.transform = Transform3D(Basis.from_euler(Vector3(0.3, -0.4, 0.2)).scaled(Vector3(1.2, 0.8, 1.5)), Vector3(2, -3, 4))
    var child := Node3D.new()
    parent.add_child(child)
    var affine := Basis(Vector3(-1.0, 0.15, 0.0), Vector3(0.25, 1.3, 0.1), Vector3(0.0, -0.2, 0.7))
    child.transform = Transform3D(affine, Vector3(0.5, 1.0, -2.0))
    var expected := child.global_transform
    var t := child.transform
    var payload := {"origin": [t.origin.x, t.origin.y, t.origin.z], "basis": [[t.basis.x.x,t.basis.x.y,t.basis.x.z],[t.basis.y.x,t.basis.y.y,t.basis.y.z],[t.basis.z.x,t.basis.z.y,t.basis.z.z]]}
    # Exercise real filesystem persistence, not just an in-memory JSON conversion.
    var path := "user://affine_roundtrip_ci.json"
    var output := FileAccess.open(path, FileAccess.WRITE)
    if output == null:
        push_error("Cannot open affine test file for writing: %d" % FileAccess.get_open_error())
        quit(1)
        return
    output.store_string(JSON.stringify(payload))
    output.flush()
    output.close()
    var input := FileAccess.open(path, FileAccess.READ)
    if input == null:
        push_error("Cannot reopen affine test file: %d" % FileAccess.get_open_error())
        quit(1)
        return
    var serialized := input.get_as_text()
    input.close()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    var parsed = JSON.parse_string(serialized)
    if not parsed is Dictionary:
        push_error("JSON payload was not a dictionary")
        quit(1)
        return
    var axes: Array = parsed["basis"]
    var restored := Node3D.new()
    parent.add_child(restored)
    restored.transform = Transform3D(Basis(Vector3(axes[0][0], axes[0][1], axes[0][2]), Vector3(axes[1][0], axes[1][1], axes[1][2]), Vector3(axes[2][0], axes[2][1], axes[2][2])), Vector3(parsed["origin"][0], parsed["origin"][1], parsed["origin"][2]))
    var actual := restored.global_transform
    var delta := actual.origin.distance_to(expected.origin)
    for axis in range(3):
        delta = maxf(delta, actual.basis[axis].distance_to(expected.basis[axis]))
    if delta > 0.0001:
        push_error("Affine JSON round-trip mismatch: %f" % delta)
        quit(1)
        return
    print("PASS: affine JSON round-trip, max error %f" % delta)
    quit(0)
