extends SceneTree
## Diagnostic-only UX smoke suite for 432x960 Android portrait editor.
## Report measured sizes and reachability. This test does NOT change the UI
## and should never conceal a usability warning behind "CI passed".

func _initialize() -> void:
    call_deferred("_audit")

func _buttons(node: Node, result: Array[Button]) -> void:
    if node is Button and node.is_visible_in_tree():
        result.append(node)
    for child in node.get_children():
        _buttons(child, result)

func _all_editable_nodes(node: Node, result: Array[Node3D]) -> void:
    for child in node.get_children():
        if child is Node3D and child.name not in ["SelectionFrame", "BBFaceMesh", "EditableMesh"]:
            result.append(child)
            _all_editable_nodes(child, result)

func _audit() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    await process_frame
    var issues: Array[String] = []
    var viewport_size := editor.size
    var preview: Control = editor.get("preview_panel")
    var timeline: Control = editor.get("timeline")
    var timeline_scroll: ScrollContainer = editor.get("timeline_scroll")
    var overlay: Control = editor.get("clip_overlay")
    var transform_overlay: Control = editor.get("transform_overlay")
    print("UX_AUDIT_SCREEN editor=%.0fx%.0f preview=%.0fx%.0f timeline=%.0fx%.0f" % [
        viewport_size.x, viewport_size.y, preview.size.x, preview.size.y,
        timeline.size.x, timeline_scroll.size.y])

    var buttons: Array[Button] = []
    _buttons(editor, buttons)
    var small: Array[String] = []
    var outside: Array[String] = []
    for button in buttons:
        var rect := button.get_global_rect()
        if rect.size.x < 44.0 or rect.size.y < 44.0:
            small.append("%s %.0fx%.0f" % [button.text, rect.size.x, rect.size.y])
        var parent_root := editor.get_global_rect()
        if rect.position.x < parent_root.position.x - 1.0 or rect.end.x > parent_root.end.x + 1.0:
            outside.append(button.text)
    print("UX_AUDIT_TOUCH visible_buttons=%d small_under_44=%d %s" % [
        buttons.size(), small.size(), str(small.slice(0, 14))])
    print("UX_AUDIT_HORIZONTAL_OVERFLOW %s" % str(outside))
    if not outside.is_empty():
        issues.append("Buttons outside screen width")
    if not small.is_empty():
        issues.append("Tap targets smaller than 44px")

    var mode_buttons: Array = editor.get("transform_buttons")
    var part_label: Label = editor.get("part_label")
    if mode_buttons.size() != 4:
        issues.append("Missing lower-right 3D mode buttons")
    else:
        var toolbar: Control = mode_buttons[0].get_parent()
        if toolbar.get_global_rect().intersects(part_label.get_global_rect()):
            issues.append("Selected-element label overlaps 3D mode buttons")
        print("UX_AUDIT_PREVIEW_CONTROLS toolbar=%s label=%s" % [
            str(toolbar.get_global_rect()), str(part_label.get_global_rect())])

    if overlay.visible or transform_overlay.visible:
        issues.append("Blocking inspector open at startup")

    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Usability"):
        push_error("UX_AUDIT failed to import test model")
        quit(1)
        return
    var model_id: String = editor.get("selected_id")
    var model: Node3D = (editor.get("objects_by_id") as Dictionary)[model_id]
    var initial_focus: Vector3 = editor.get("orbit_target")
    editor.call("_set_selection", model_id)
    if (editor.get("orbit_target") as Vector3).distance_to(initial_focus) > 0.001:
        issues.append("Selecting model unexpectedly changes camera focus")

    editor.call("_open_part_picker")
    var picker: Control = editor.get("picker_overlay")
    var picker_list: VBoxContainer = editor.get("picker_list")
    var all_nodes: Array[Node3D] = []
    _all_editable_nodes(model, all_nodes)
    print("UX_AUDIT_PART_PICKER actual_items=%d expected_editable_parts=%d" % [
        picker_list.get_child_count(), all_nodes.size() + 1])
    if picker_list.get_child_count() < all_nodes.size() + 1:
        issues.append("Deep model parts are missing from hierarchy picker")
    if not picker.visible:
        issues.append("Hierarchy panel did not open")
    editor.call("_close_picker")

    var clip_map: Dictionary = editor.get("clip_tracks")
    if clip_map.has(model_id) and not (clip_map[model_id] as Array).is_empty():
        var uid := str(clip_map[model_id][0].get("uid", ""))
        editor.call("_open_clip_editor", model_id, uid)
        if not overlay.visible:
            issues.append("Animation bar inspector did not open")
        editor.call("_close_clip_editor")
    else:
        issues.append("Default animation clip not reachable")

    editor.call("_open_transform_inspector")
    if not transform_overlay.visible:
        issues.append("Numeric transform inspector did not open")
    editor.call("_close_transform_inspector")

    editor.call("_toggle_pose_record")
    var record_mode: bool = editor.get("pose_record_mode")
    print("UX_AUDIT_POSE mode=%s label=%s" % [
        str(record_mode), str((editor.get("pose_record_button") as Button).text)])
    if not record_mode:
        issues.append("Pose ON toggle failed")
    editor.call("_toggle_pose_record")

    var second_per_px := float(timeline.get("duration")) / maxf(timeline.size.x - 97.0, 1.0)
    print("UX_AUDIT_TIMELINE content_height=%.0f visible_height=%.0f row_height=38 key_hit_half_width=13 seconds_per_pixel=%.4f" % [
        timeline.custom_minimum_size.y, timeline_scroll.size.y, second_per_px])
    if timeline.custom_minimum_size.y > timeline_scroll.size.y + 1.0:
        print("UX_AUDIT_TIMELINE requires_vertical_scrolling=true")
    if second_per_px > 0.03:
        issues.append("15s fixed-width timeline too coarse for frame-accurate keys")

    # Stress a narrower portrait canvas for smaller phones / split windows.
    editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    editor.size = Vector2(360.0, 800.0)
    await process_frame
    await process_frame
    var small_buttons: Array[Button] = []
    _buttons(editor, small_buttons)
    var narrow_toolbar: Control = (editor.get("transform_buttons") as Array)[0].get_parent()
    var narrow_label: Label = editor.get("part_label")
    var label_overlap := narrow_toolbar.get_global_rect().intersects(narrow_label.get_global_rect())
    var narrow_overflow: Array[String] = []
    for button in small_buttons:
        var rect := button.get_global_rect()
        if rect.position.x < -1.0 or rect.end.x > editor.size.x + 1.0:
            narrow_overflow.append(button.text)
    print("UX_AUDIT_NARROW editor=%.0fx%.0f preview=%.0fx%.0f label_overlap=%s overflow=%s" % [
        editor.size.x, editor.size.y, preview.size.x, preview.size.y,
        str(label_overlap), str(narrow_overflow)])
    if label_overlap:
        issues.append("Selected part label and modeling controls overlap on 360px canvas")
    if not narrow_overflow.is_empty():
        issues.append("Buttons outside 360px canvas")

    print("UX_AUDIT_RESULT finding_count=%d" % issues.size())
    for issue in issues:
        print("UX_AUDIT_WARNING: " + issue)
    print("UX_AUDIT_FINISHED")
    quit(0)
