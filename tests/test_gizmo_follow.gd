extends SceneTree
## Regression: editor gizmo tracks the visible model, the chosen joint pivot,
## and the current camera transform *during* touches and animation playback.

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GIZMO FOLLOW TEST FAILED: " + message)
    quit(1)

func _near_vec(a: Vector3, b: Vector3, tolerance: float = 0.005) -> bool:
    return a.distance_to(b) < tolerance

func _size_on_screen(gizmo: Node3D, camera: Camera3D) -> float:
    var p0: Vector2 = camera.unproject_position(gizmo.global_position)
    var p1: Vector2 = camera.unproject_position(gizmo.global_transform * Vector3(1.15, 0, 0))
    return p0.distance_to(p1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame

    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "18-part fixture"):
        _fail("Could not import multi-joint fixture")
        return
    var model_id: String = editor.get("selected_id")
    var model: Node3D = (editor.get("objects_by_id") as Dictionary)[model_id]
    var gizmo: Node3D = editor.get("gizmo")
    var camera: Camera3D = editor.get("editor_camera")
    var viewport: SubViewport = editor.get("preview")
    var container: SubViewportContainer = editor.get("preview_box")
    var groups: Dictionary = (editor.get("bb_assets") as Dictionary)[model_id]["groups"]
    if not gizmo.visible:
        _fail("Gizmo hidden for selected model")
        return

    # The imported root's Blockbench origin is NOT the visible body center.
    var local_anchor: Vector3 = model.get_meta("editor_gizmo_anchor")
    if local_anchor.length() < 0.05:
        _fail("Imported root anchor was not computed from actual geometry")
        return
    if not _near_vec(gizmo.global_position, model.to_global(local_anchor)):
        _fail("Initial gizmo was not placed at visible-model anchor")
        return
    var p0: Vector3 = gizmo.global_position
    editor.call("_seek", 1.0)
    if not _near_vec(gizmo.global_position, p0, 0.002):
        _fail("Root gizmo jumps with animated limbs instead of using stable local anchor")
        return

    # Move the whole character and check the gizmo during the same event:
    # no release, no timeline seek, no next-frame workaround.
    editor.call("_set_transform_mode", 0)
    editor.set("axis_index", 0)
    editor.set("drag_handle_axis", 0)
    editor.set("drag_target_node", model)
    editor.set("drag_position_start", model.position)
    var preview_p: Vector2 = camera.unproject_position(gizmo.global_position) * container.size / Vector2(viewport.size)
    editor.set("pointer_origin", preview_p)
    editor.set("drag_grab_point", editor.call("_world_on_level", preview_p, gizmo.global_position.y, gizmo.global_position))
    editor.call("_apply_model_drag", preview_p + Vector2(45, 18))
    if model.position.length() < 0.005:
        _fail("Model did not move under finger")
        return
    if not _near_vec(gizmo.global_position, model.to_global(local_anchor)):
        _fail("Gizmo lagged behind a model being translated by a finger")
        return

    # Camera zoom while timeline is PAUSED must resize the axis guides without
    # changing their on-screen size.
    var px_before := _size_on_screen(gizmo, camera)
    var old_distance: float = editor.get("orbit_distance")
    editor.set("orbit_distance", old_distance * 1.5)
    editor.call("_update_camera")
    var px_after := _size_on_screen(gizmo, camera)
    if px_before < 5.0 or absf(px_after - px_before) > px_before * 0.22:
        _fail("Gizmo changes visual size when the user zooms the camera")
        return

    # A child of a multi-axis animated group changes pivot location over time.
    # Its gizmo must stay at the precise joint pivot, not its group's origin
    # or the containing object's bounding-box center.
    var joint: Node3D = groups["grp_2"]["node"]
    var joint_path := str(model.get_path_to(joint))
    editor.call("_set_part_selection", model_id, joint_path)
    editor.call("_seek", 0.0)
    var before: Vector3 = gizmo.global_position
    if not _near_vec(before, joint.global_position):
        _fail("Selected joint gizmo is not at joint pivot")
        return
    editor.call("_seek", 1.0)
    var after: Vector3 = joint.global_position
    if before.distance_to(after) < 0.02:
        _fail("Fixture did not exercise an animated descendant joint")
        return
    if not _near_vec(gizmo.global_position, after):
        _fail("Gizmo did not follow joint animated by the timeline")
        return

    # Rotation of parent joint must also rotate XYZ guide orientation.
    var expected_basis := joint.global_basis.orthonormalized()
    var actual_basis := gizmo.global_basis.orthonormalized()
    if actual_basis.x.dot(expected_basis.x) < 0.999 or actual_basis.y.dot(expected_basis.y) < 0.999:
        _fail("XYZ handles are still world-aligned instead of following the joint")
        return

    # Translate along the drawn local X axis and verify its real-world motion
    # is aligned with the same displayed axis under a rotated parent.
    editor.call("_set_transform_mode", 0)
    editor.set("drag_target_node", joint)
    editor.set("drag_position_start", joint.position)
    editor.set("drag_handle_axis", 1)
    var world_axis: Vector3 = joint.global_basis.orthonormalized().x
    var pivot: Vector3 = joint.global_position
    var start: Vector2 = camera.unproject_position(pivot) * container.size / Vector2(viewport.size)
    var end: Vector2 = camera.unproject_position(pivot + world_axis) * container.size / Vector2(viewport.size)
    editor.set("pointer_origin", start)
    var old_pos: Vector3 = joint.global_position
    editor.call("_apply_model_drag", start + (end - start) * 0.3)
    var displacement := joint.global_position - old_pos
    if absf(displacement.dot(world_axis) - 0.3) > 0.05:
        _fail("Axis drag does not move along the drawn local X handle")
        return
    if displacement.cross(world_axis).length() > 0.025:
        _fail("Axis drag has unintended motion across other axes")
        return
    if not _near_vec(gizmo.global_position, joint.global_position):
        _fail("Joint gizmo did not move in the same touch event")
        return

    # Dragging rotation and scaling must immediately update oriented handles.
    editor.call("_set_transform_mode", 1)
    editor.set("drag_rotation_start", joint.rotation_degrees)
    editor.set("drag_handle_axis", 2)
    editor.set("pointer_origin", start)
    editor.call("_apply_model_drag", start + Vector2(60, 0))
    if gizmo.global_basis.orthonormalized().x.dot(joint.global_basis.orthonormalized().x) < 0.999:
        _fail("Rotation handles do not turn with the edited joint")
        return
    editor.call("_set_transform_mode", 2)
    editor.set("drag_initial_scale", joint.scale)
    editor.set("drag_handle_axis", 3)
    editor.set("pointer_origin", start)
    editor.call("_apply_model_drag", start + Vector2(0, -65))
    if not _near_vec(gizmo.global_position, joint.global_position):
        _fail("Scale handles are detached from the joint")
        return
    if gizmo.global_basis.orthonormalized().x.dot(joint.global_basis.orthonormalized().x) < 0.999:
        _fail("Scale handles inherit a distorted axis orientation")
        return

    editor.call("_set_transform_mode", 3)
    if gizmo.visible:
        _fail("Select-only mode should hide transform guides")
        return
    editor.call("_set_transform_mode", 0)
    editor.call("_toggle_camera_view")
    if gizmo.visible:
        _fail("Gizmo should not cover shooting camera preview")
        return
    editor.call("_toggle_camera_view")
    if not gizmo.visible:
        _fail("Gizmo did not return to the edited part in edit preview")
        return
    print("GIZMO FOLLOW TEST PASSED: model center, live drag, camera zoom, animated joints, local axes, rotate, scale, preview toggle")
    quit(0)
