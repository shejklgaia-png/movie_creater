extends SceneTree
## Blockbench's bone Euler order differs from element/mesh Euler order.
## This regression reproduces a multi-axis pose from a four-leg creature
## without committing any private model or textures.

const Importer = preload("res://scripts/bbmodel_importer.gd")
const EPS := 0.0001

func _initialize() -> void:
    call_deferred("_test")

func _fail(reason: String) -> void:
    push_error("BONE ROTATION TEST FAILED: " + reason)
    quit(1)

func _test() -> void:
    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    var importer := Importer.new()
    var result: Dictionary = importer.import_text(source)
    if not bool(result.get("ok", false)):
        _fail("Fixture failed to load")
        return
    var model: Node3D = result["root"]
    root.add_child(model)
    var groups: Dictionary = result["groups"]
    var bone: Node3D = groups["grp_1"]["node"]
    var child: Node3D = groups["grp_2"]["node"]
    var mesh: Node3D = bone.get_node_or_null("synthetic_part_1")
    if mesh == null:
        _fail("Element under bone missing")
        return
    if bone.rotation_order != EULER_ORDER_ZYX:
        _fail("Groups must use ZYX Euler order")
        return
    if mesh.rotation_order != EULER_ORDER_XYZ:
        _fail("Mesh elements must continue to use XYZ Euler order")
        return
    var angle_x := -21.1693
    var angle_y := 37.7553
    var angle_z := -32.3125
    var clip := {"animators": {"grp_1": {"keyframes": [{
        "time": 0.0, "channel": "rotation", "interpolation": "linear",
        "data_points": [{"x": str(angle_x), "y": str(angle_y), "z": str(angle_z)}]
    }]}}}
    importer.apply_clip(groups, clip, 0.0, false)
    var bx := Basis(Vector3.RIGHT, deg_to_rad(angle_x))
    var by := Basis(Vector3.UP, deg_to_rad(angle_y))
    var bz := Basis(Vector3.BACK, deg_to_rad(angle_z))
    var expected := bz * by * bx
    var wrong_xyz := bx * by * bz
    var probe := Vector3(3.0, 2.0, -4.0)
    var actual := bone.basis * probe
    if actual.distance_to(expected * probe) > EPS:
        _fail("Bone does not match independent Rz*Ry*Rx reference")
        return
    if actual.distance_to(wrong_xyz * probe) < 0.1:
        _fail("Test pose does not discriminate XYZ from ZYX")
        return

    # Descendant position must be rotated by the same parent basis.
    var expected_child := bone.global_position + bone.global_basis * child.position
    if child.global_position.distance_to(expected_child) > EPS:
        _fail("Nested group pivot did not follow rotated bone")
        return
    importer.apply_clip(groups, {}, 0.0, false)
    if bone.basis.x.distance_to(Vector3.RIGHT) > EPS:
        _fail("Removing animation did not reset bone rotation")
        return
    print("BONE ROTATION TEST PASSED: groups ZYX, elements XYZ, multi-axis pose, child pivot, reset")
    quit(0)
