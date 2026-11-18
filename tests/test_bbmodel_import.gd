extends SceneTree

const BBModelImporter = preload("res://scripts/bbmodel_importer.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("BBMODEL TEST FAILED: " + reason)
    quit(1)

func _run() -> void:
    var text := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if text.is_empty():
        _fail("Missing fixture")
        return
    var importer := BBModelImporter.new()
    var result: Dictionary = importer.import_text(text)
    if not result.get("ok", false):
        _fail("Could not import fixture: " + str(result.get("error", "")))
        return
    if int(result["cubes"]) != 2:
        _fail("Expected two cube elements")
        return
    if not result["groups"].has("arm") or not result["groups"].has("body"):
        _fail("Group UUIDs or hierarchy lost")
        return
    var model: Node3D = result["root"]
    root.add_child(model)
    var body: Node3D = result["groups"]["body"]["node"]
    var arm: Node3D = result["groups"]["arm"]["node"]
    if arm.get_parent() != body:
        _fail("Nested group parent lost")
        return
    if arm.position.distance_to(Vector3(0.5, 0.25, 0.0)) > 0.0001:
        _fail("Nested group pivot not in parent-relative coordinates")
        return
    var meshes: Array[MeshInstance3D] = []
    var queue: Array[Node] = [model]
    while not queue.is_empty():
        var item: Node = queue.pop_back()
        if item is MeshInstance3D:
            meshes.append(item)
        for child in item.get_children():
            queue.append(child)
    if meshes.size() < 2:
        _fail("Cuboid meshes missing")
        return
    var found_texture := false
    for mesh in meshes:
        var geom := mesh.mesh
        if geom != null and geom.get_surface_count() > 0:
            var material: Material = geom.surface_get_material(0)
            if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null:
                found_texture = true
    if not found_texture:
        _fail("Embedded PNG texture was not decoded")
        return

    var clip: Dictionary = result["animations"][0]
    importer.apply_clip(result["groups"], clip, 0.5, false)
    if absf(arm.rotation_degrees.y - 45.0) > 0.2:
        _fail("Animation rotation preview differs from expected 45 degrees")
        return
    importer.apply_clip(result["groups"], clip, 0.0, false)
    if absf(arm.rotation_degrees.y) > 0.2:
        _fail("Scrubbing back to zero did not restore rest pose")
        return
    var editor_scene: PackedScene = load("res://scenes/editor.tscn")
    var editor: Control = editor_scene.instantiate()
    root.add_child(editor)
    await process_frame
    if not editor.call("_import_bbmodel_text", text, "BBModel Test"):
        _fail("Editor integration import failed")
        return
    var bb_assets: Dictionary = editor.get("bb_assets")
    if bb_assets.is_empty():
        _fail("Editor did not register imported asset")
        return
    var saved: Dictionary = editor.call("_serialize_project")
    var serialized_count := 0
    for entry in saved["objects"]:
        if str(entry.get("kind", "")) == "bbmodel" and str(entry.get("bb_source", "")).length() > 10:
            serialized_count += 1
    if serialized_count != 1:
        _fail("Embedded model data not persisted in project")
        return
    print("BBMODEL TEST PASSED: hierarchy, pivots, 3D geometry, UV texture, animation, persistence")
    quit(0)
