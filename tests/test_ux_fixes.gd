extends SceneTree
## Strict regression for findings in docs/usability-audit-2026-11-19.md.
## This is a real editor headless test, not a source string inspection.

func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("UX FIX TEST FAILED: " + reason)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    await process_frame

    editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    editor.size = Vector2(360, 800)
    await process_frame
    await process_frame
    var preview: Control = editor.get("preview_panel")
    if preview.size.x > 360.5:
        _fail("3D preview exceeds 360px portrait width: %s" % str(preview.size))
        return
    var toolbar: Control = (editor.get("transform_buttons") as Array)[0].get_parent()
    var part_label: Label = editor.get("part_label")
    if toolbar.get_global_rect().intersects(part_label.get_global_rect()):
        _fail("Element title overlaps transform mode toolbar")
        return
    var buttons: Array[Button] = []
    _collect_buttons(editor, buttons)
    for button in buttons:
        var rect := button.get_global_rect()
        if rect.position.x < -0.5 or rect.end.x > editor.size.x + 0.5:
            _fail("Control overflows portrait width: %s, rect %s" % [button.text, str(rect)])
            return
        if rect.size.x < 44.0 or rect.size.y < 44.0:
            _fail("Touch target smaller than 44px: %s, rect %s" % [button.text, str(rect)])
            return

    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "UI Fixture"):
        _fail("Could not load layered model")
        return
    var model_id: String = editor.get("selected_id")
    editor.call("_open_part_picker")
    var part_list: VBoxContainer = editor.get("picker_list")
    if part_list.get_child_count() < 35:
        _fail("Deep nested parts missing: %d of at least 35" % part_list.get_child_count())
        return
    editor.call("_close_picker")

    var timeline: Control = editor.get("timeline")
    var scroller: ScrollContainer = editor.get("timeline_scroll")
    var before_span: float = timeline._view_span()
    editor.call("_change_timeline_zoom", 1)
    if timeline._view_span() >= before_span:
        _fail("TL '+' did not zoom in")
        return
    editor.call("_change_timeline_zoom", -1)
    if absf(timeline._view_span() - before_span) > 0.01:
        _fail("TL '-' did not restore original zoom")
        return
    editor.call("_seek", 2.0)
    timeline._start_interaction(Vector2(140, 110))
    var after_start: float = editor.get("current_time")
    timeline._move_interaction(Vector2(143, 40))
    if not bool(timeline.get("vertical_panning")):
        _fail("Vertical finger drag not recognized as timeline list scrolling")
        return
    if absf(float(editor.get("current_time")) - after_start) > 0.001:
        _fail("Vertical track scrolling altered playhead")
        return
    if scroller.scroll_vertical <= 0:
        _fail("Vertical track scrolling did not move ScrollContainer")
        return
    timeline._finish_interaction(Vector2(143, 40))
    if bool(timeline.get("vertical_panning")):
        _fail("Vertical scroll state did not reset")
        return

    editor.call("_set_project_duration", 50.0)
    if absf(float(editor.get("DURATION")) - 50.0) > 0.001 or absf(float(timeline.get("duration")) - 50.0) > 0.001:
        _fail("Changing movie duration failed")
        return

    editor.call("_save_project")
    if not FileAccess.file_exists("user://movie_project.json"):
        _fail("Project save file missing")
        return
    var first_json := FileAccess.get_file_as_string("user://movie_project.json")
    if not first_json.contains("\"duration\": 50"):
        _fail("Saved movie duration is missing")
        return
    editor.call("_add_object", "sphere")
    editor.call("_save_project")
    if not FileAccess.file_exists("user://movie_project.backup.json"):
        _fail("Backup is missing after second save")
        return
    if FileAccess.get_file_as_string("user://movie_project.backup.json") != first_json:
        _fail("Backup does not preserve previous saved project")
        return
    if not editor.call("_export_project_path", "user://ux_export_project.json"):
        _fail("Project export function did not write JSON")
        return
    var count_before: int = (editor.get("objects_by_id") as Dictionary).size()
    editor.call("_new_project")
    if not (editor.get("objects_by_id") as Dictionary).is_empty():
        _fail("New project did not clear all objects")
        return
    if not editor.call("_import_project_path", "user://ux_export_project.json"):
        _fail("Exported JSON could not be restored")
        return
    if (editor.get("objects_by_id") as Dictionary).size() != count_before:
        _fail("Imported project lost objects")
        return
    if absf(float(editor.get("DURATION")) - 50.0) > 0.001:
        _fail("Imported project lost duration")
        return
    var current_id: String = editor.get("selected_id")
    if not (editor.get("objects_by_id") as Dictionary).has(current_id):
        editor.call("_set_selection", str((editor.get("objects_by_id") as Dictionary).keys()[0]))
    var count_with_model: int = (editor.get("objects_by_id") as Dictionary).size()
    editor.call("_delete_selected_model")
    if (editor.get("objects_by_id") as Dictionary).size() != count_with_model - 1:
        _fail("Deleting selected model did not remove it")
        return

    print("UX FIX TEST PASSED: 360x800 layout, deep hierarchy, vertical TL pan, time zoom, custom duration, backup, export/import, model deletion")
    quit(0)

func _collect_buttons(node: Node, out: Array[Button]) -> void:
    if node is Button and node.is_visible_in_tree():
        out.append(node)
    for child in node.get_children():
        _collect_buttons(child, out)
