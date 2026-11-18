extends SceneTree
## Portrait UI regression: Android content URIs must NEVER become visible model
## titles, selecting an object never repositions the camera, and all property
## buttons remain within viewport width after import.
const SourceImporter = preload("res://scripts/bbmodel_importer.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MOBILE UI TEST FAILED: " + message)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    await process_frame

    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if source.is_empty():
        _fail("Fixture unavailable")
        return
    var parsed: Dictionary = JSON.parse_string(source)
    parsed["name"] = "ビットタラン"
    source = JSON.stringify(parsed)
    var saf_uri := "content://com.android.externalstorage.documents/document/primary_3AGAME_2FGit_2Fmodels_2Fstorage_2FFileName_very_very_very_long_12423"
    if not editor.call("_import_bbmodel_text", source, saf_uri):
        _fail("Could not import model with Android SAF placeholder filename")
        return
    await process_frame

    var objects: Dictionary = editor.get("objects_by_id")
    var selected_id: String = editor.get("selected_id")
    var model: Node3D = objects[selected_id]
    if model.name != "ビットタラン":
        _fail("Imported model did not use the project name: " + model.name)
        return

    var selected_button: Button = editor.get("selection")
    var mode_button: Button = editor.get("mode_option")
    var axis_button: Button = editor.get("axis_option")
    var status: Label = editor.get("status_label")
    if not selected_button.clip_text or not mode_button.clip_text or not axis_button.clip_text or not status.clip_text:
        _fail("Text content is not constrained to portrait layout")
        return
    if selected_button.text.contains("primary_3A") or status.text.contains("primary_3A"):
        _fail("Android content URI leaks into visible UI")
        return
    if selected_button.text.length() > 19:
        _fail("Selection label is not shortened")
        return
    if selected_button.size.x + mode_button.size.x + axis_button.size.x > editor.size.x + 1.0:
        _fail("Property controls overflow the portrait editor width")
        return

    var initial_target: Vector3 = editor.get("orbit_target")
    var initial_yaw: float = editor.get("orbit_yaw")
    var initial_pitch: float = editor.get("orbit_pitch")
    var initial_distance: float = editor.get("orbit_distance")
    editor.call("_set_selection", selected_id)
    if (editor.get("orbit_target") as Vector3).distance_to(initial_target) > 0.001:
        _fail("Selecting a model unexpectedly changes the orbit target")
        return
    if absf(float(editor.get("orbit_distance")) - initial_distance) > 0.001:
        _fail("Selecting a model unexpectedly changes camera distance")
        return

    # Touch noise (8 pixels) should never rotate an orbit or translate a mesh.
    var start := Vector2(35, 35)
    editor.call("_begin_pointer", start)
    editor.call("_move_pointer", start + Vector2(6, 4))
    editor.call("_finish_pointer", start + Vector2(6, 4))
    if (editor.get("orbit_target") as Vector3).distance_to(initial_target) > 0.001:
        _fail("Touch jitter changed orbit target")
        return
    if absf(float(editor.get("orbit_yaw")) - initial_yaw) > 0.0001:
        _fail("Touch jitter rotated the camera yaw")
        return
    if absf(float(editor.get("orbit_pitch")) - initial_pitch) > 0.0001:
        _fail("Touch jitter rotated the camera pitch")
        return

    # A held imported model must not summon a huge selection bounding frame.
    var outline: Node3D = model.get_node_or_null("SelectionFrame")
    if outline == null or outline.visible:
        _fail("Imported model wireframe is obscuring the viewport")
        return

    # Restoring older saved model names still prefers embedded Blockbench name.
    var records: Dictionary = editor.call("_serialize_project")
    var found := false
    for record in records["objects"]:
        if str(record.get("kind", "")) == "bbmodel":
            if str(record.get("display_name", "")) != "ビットタラン":
                _fail("Readable model name was not serialized")
                return
            found = true
    if not found:
        _fail("bbmodel absent from saved records")
        return
    print("MOBILE UI TEST PASSED: short BB name, bounded controls, stable camera taps, save metadata")
    quit(0)
