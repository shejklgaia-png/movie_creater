extends SceneTree
## Validate 3D part manipulation and persistency without changing Blockbench's
## original animation or top-level timeline data.
func _initialize() -> void:
    call_deferred("_test")

func _fail(message: String) -> void:
    push_error("PART EDITOR TEST FAILED: " + message)
    quit(1)

func _close(a: float, b: float, tol: float = 0.15) -> bool:
    return absf(a - b) <= tol

func _test() -> void:
    var scene: PackedScene = load("res://scenes/editor.tscn")
    var editor: Control = scene.instantiate()
    root.add_child(editor)
    await process_frame
    var buttons: Array = editor.get("transform_buttons")
    var panel: Control = editor.get("preview_panel")
    if buttons.size() != 4:
        _fail("Expected four preview buttons: select/move/rotate/scale")
        return
    if buttons[0].text != "選択" or buttons[1].text != "移動" or buttons[2].text != "回転" or buttons[3].text != "拡縮":
        _fail("Preview mode buttons are mislabeled")
        return
    if buttons[0].get_parent().get_parent() != panel:
        _fail("Transform UI is not placed INSIDE the 3D preview panel")
        return
    if buttons[0].get_parent().anchor_right != 1.0 or buttons[0].get_parent().anchor_bottom != 1.0:
        _fail("Transform buttons are not anchored at preview bottom-right")
        return

    var source := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Model"):
        _fail("Could not load .bbmodel fixture")
        return
    var model_id: String = editor.get("selected_id")
    var assets: Dictionary = editor.get("bb_assets")
    var nodes: Dictionary = assets[model_id]["groups"]
    var arm: Node3D = nodes["arm"]["node"]
    var model: Node3D = (editor.get("objects_by_id") as Dictionary)[model_id]
    var path := str(model.get_path_to(arm))
    editor.call("_set_part_selection", model_id, path)
    if editor.call("_get_selected_target") != arm:
        _fail("A hierarchy element cannot be individually selected")
        return
    editor.call("_open_part_picker")
    if not (editor.get("picker_overlay") as Control).visible:
        _fail("Hierarchy picker did not open")
        return
    editor.call("_close_picker")

    editor.call("_seek", 1.0)
    if not _close(arm.rotation_degrees.y, 90.0, 0.2):
        _fail("Original animation could not play")
        return
    var base_position := arm.position
    var base_rotation := arm.rotation_degrees
    var base_scale := arm.scale
    arm.position += Vector3(0.2, 0.1, 0.0)
    arm.rotation_degrees.y += 10.0
    arm.scale = Vector3(1.1, 1.3, 0.9)
    var old_offset: Dictionary = editor.call("_get_part_offset", model_id, path)
    editor.call("_commit_part_edit", arm, base_position, base_rotation, base_scale, old_offset)
    editor.call("_seek", 1.0)
    if not _close(arm.rotation_degrees.y, 100.0, 0.2):
        _fail("Manual part rotation did not overlay the existing animation")
        return
    if not _close(arm.position.x, base_position.x + 0.2, 0.02):
        _fail("Manual part translation did not persist")
        return
    if not _close(arm.scale.y, 1.3, 0.02):
        _fail("Manual part scaling did not persist")
        return
    editor.call("_seek", 0.0)
    if not _close(arm.rotation_degrees.y, 10.0, 0.2):
        _fail("Element edit did not remain independent of source animation keys")
        return
    editor.call("_seek", 1.0)
    if not _close(arm.position.x, base_position.x + 0.2, 0.02):
        _fail("Repeated seek accumulated the transform offset")
        return

    editor.call("_set_transform_mode", 2)
    if int(editor.get("mode_index")) != 2:
        _fail("Scale mode was not activated")
        return
    if not (editor.get("gizmo") as Node3D).visible:
        _fail("No 3D transform gizmo visible")
        return
    editor.call("_open_transform_inspector")
    if not (editor.get("transform_overlay") as Control).visible:
        _fail("Numeric inspector not displayed")
        return
    editor.call("_set_numeric_transform", 1.6, "scale", 2)
    if not _close(arm.scale.z, 1.6, 0.03):
        _fail("Numeric XYZ scale editing failed")
        return
    editor.call("_close_transform_inspector")

    var mesh_part: Node3D = nodes["body"]["node"].get_node_or_null("body")
    if mesh_part == null:
        _fail("Static cuboid element could not be found")
        return
    var mesh_path := str(model.get_path_to(mesh_part))
    editor.call("_set_part_selection", model_id, mesh_path)
    var static_initial := mesh_part.position
    var rest_rot := mesh_part.rotation_degrees
    var rest_scale := mesh_part.scale
    mesh_part.position += Vector3(0.12, 0, 0)
    editor.call("_commit_part_edit", mesh_part, static_initial, rest_rot, rest_scale, editor.call("_get_part_offset", model_id, mesh_path))
    for i in range(4):
        editor.call("_seek", 0.5)
    if not _close(mesh_part.position.x - static_initial.x, 0.12, 0.02):
        _fail("Static mesh transform accumulated after timeline scrubbing")
        return

    var saved: Dictionary = editor.call("_serialize_project")
    if int(saved.get("version", 0)) != 3:
        _fail("Project version is not 3")
        return
    var record_valid := false
    for entry in saved["objects"]:
        if str(entry.get("id", "")) == model_id:
            var offsets: Dictionary = entry.get("element_offsets", {})
            if not offsets.has(mesh_path) or not offsets.has(path):
                _fail("Part edits were not stored for model hierarchy paths")
                return
            record_valid = true
    if not record_valid:
        _fail("Edited model was omitted from serialization")
        return

    editor.call("_reset_selected_transform")
    editor.call("_seek", 0.5)
    if not _close(mesh_part.position.x - static_initial.x, 0.0, 0.02):
        _fail("Reset did not remove mesh transform override")
        return

    print("PART EDITOR TEST PASSED: right preview UI, hierarchy, scale/rotate/move, numeric edits, animated offsets, nonaccumulation, save")
    quit(0)
