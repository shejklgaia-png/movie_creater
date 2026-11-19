extends SceneTree
## Regression for viewport camera/edit switching and primitive-free startup.

func _initialize() -> void:
    call_deferred("_test")

func _fail(reason: String) -> void:
    push_error("CAMERA VIEW TOGGLE FAILED: " + reason)
    quit(1)

func _test() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    await process_frame
    # Old test runs and preexisting user projects must not change this result.
    editor.call("_new_project")
    await process_frame
    if not (editor.get("objects_by_id") as Dictionary).is_empty():
        _fail("New project must not contain demo cube or sphere")
        return
    var preview_panel: Control = editor.get("preview_panel")
    var toggle: Button = editor.get("camera_view_button")
    if toggle.get_parent() != preview_panel:
        _fail("Camera toggle is not inside the preview panel")
        return
    if toggle.text != "カメラ視点":
        _fail("Editor view should offer camera view")
        return
    if toggle.anchor_right != 1.0 or toggle.anchor_top != 0.0:
        _fail("Camera toggle is not pinned to the top right")
        return

    var buttons: Array[Button] = []
    _collect_buttons(editor, buttons)
    for button in buttons:
        if button.text.contains("＋箱") or button.text.contains("＋球"):
            _fail("Obsolete primitive add button is visible")
            return

    # Exercise the real button's signal and verify its hit rectangle.
    for screen in [Vector2(320, 640), Vector2(360, 800), Vector2(432, 960)]:
        editor.size = screen
        await process_frame
        await process_frame
        var bounds := toggle.get_global_rect()
        var preview_bounds := preview_panel.get_global_rect()
        if bounds.position.x < preview_bounds.position.x or bounds.end.x > preview_bounds.end.x + 0.5:
            _fail("Camera toggle extends beyond preview width at %s" % str(screen))
            return
        if bounds.position.y < preview_bounds.position.y or bounds.end.y > preview_bounds.end.y + 0.5:
            _fail("Camera toggle extends beyond preview height at %s" % str(screen))
            return
        if bounds.size.x < 44.0 or bounds.size.y < 44.0:
            _fail("Camera toggle is too small to tap")
            return

    var camera: Camera3D = editor.get("editor_camera")
    var shot: Camera3D = editor.get("shot_camera")
    var tools: Array[Button] = editor.get("transform_buttons")
    var label: Label = editor.get("part_label")
    editor.set("orbit_target", Vector3(2.0, 1.2, -3.0))
    editor.set("orbit_yaw", 0.98)
    editor.set("orbit_pitch", 0.38)
    editor.set("orbit_distance", 12.0)
    editor.call("_update_camera")
    var original_matrix := camera.global_transform
    var original_fov := camera.fov
    var original_target: Vector3 = editor.get("orbit_target")
    var original_yaw: float = editor.get("orbit_yaw")
    var original_pitch: float = editor.get("orbit_pitch")
    var original_distance: float = editor.get("orbit_distance")

    toggle.emit_signal("pressed")
    await process_frame
    if not bool(editor.get("shot_preview")) or not shot.current:
        _fail("Button did not switch to movie camera")
        return
    if toggle.text != "編集視点" or label.visible:
        _fail("Shot view still shows editing controls")
        return
    for tool_button in tools:
        if tool_button.visible:
            _fail("Model transform tools obscure the shot preview")
            return

    # Timeline/keyframed camera motion should not affect the stored viewpoint.
    editor.call("_seek", 5.0)
    shot.position = Vector3(-10, 12, 8)
    editor.set("orbit_target", Vector3(99, 88, 77))
    editor.set("orbit_yaw", -2.0)
    editor.set("orbit_pitch", 1.1)
    editor.set("orbit_distance", 22.0)
    editor.call("_update_camera")

    toggle.emit_signal("pressed")
    await process_frame
    if bool(editor.get("shot_preview")) or not camera.current:
        _fail("Button did not return to edit camera")
        return
    if toggle.text != "カメラ視点" or not label.visible:
        _fail("Editing overlay did not return")
        return
    for tool_button in tools:
        if not tool_button.visible:
            _fail("Model transform buttons did not return")
            return
    if camera.global_position.distance_to(original_matrix.origin) > 0.0005:
        _fail("Camera position was not restored")
        return
    if not camera.global_transform.basis.is_equal_approx(original_matrix.basis):
        _fail("Camera rotation was not restored")
        return
    if absf(camera.fov - original_fov) > 0.0001:
        _fail("Camera field of view was not restored")
        return
    if (editor.get("orbit_target") as Vector3).distance_to(original_target) > 0.0001:
        _fail("Original camera pan target was not restored")
        return
    if absf(float(editor.get("orbit_yaw")) - original_yaw) > 0.0001:
        _fail("Original camera yaw was not restored")
        return
    if absf(float(editor.get("orbit_pitch")) - original_pitch) > 0.0001:
        _fail("Original camera pitch was not restored")
        return
    if absf(float(editor.get("orbit_distance")) - original_distance) > 0.0001:
        _fail("Original zoom distance was not restored")
        return
    if not (editor.get("edit_view_snapshot") as Dictionary).is_empty():
        _fail("Old camera snapshot was not cleared")
        return

    # Switching multiple times must preserve the current edit view each time.
    editor.set("orbit_yaw", 1.3)
    editor.call("_update_camera")
    var second_matrix := camera.global_transform
    toggle.emit_signal("pressed")
    toggle.emit_signal("pressed")
    if camera.global_position.distance_to(second_matrix.origin) > 0.0005:
        _fail("Repeated toggle did not preserve the latest edit view")
        return
    print("CAMERA VIEW TOGGLE PASSED: no demo objects, top-right toggle, original edit view restored")
    quit(0)

func _collect_buttons(node: Node, output: Array[Button]) -> void:
    if node is Button and node.is_visible_in_tree():
        output.append(node)
    for child in node.get_children():
        _collect_buttons(child, output)
