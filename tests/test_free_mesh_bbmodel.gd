extends SceneTree
## Regression coverage for Blockbench 5 free-form polygon meshes.
## Synthetic fixture exercises the SAME all-mesh + grouped format as the
## real uploaded model, without publishing user-owned artwork.

const Importer = preload("res://scripts/bbmodel_importer.gd")

func _initialize() -> void:
    call_deferred("_test")

func _failure(reason: String) -> void:
    push_error("FREE MESH TEST FAILED: " + reason)
    quit(1)

func _test() -> void:
    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if source.is_empty():
        _failure("Missing fixture")
        return
    var importer := Importer.new()
    var result: Dictionary = importer.import_text(source)
    if not bool(result.get("ok", false)):
        _failure("Importer rejected all-mesh model: " + str(result.get("error", "")))
        return
    if int(result.get("meshes", -1)) != 18 or int(result.get("cubes", -1)) != 0:
        _failure("Expected 18 polygon meshes and zero cuboids")
        return
    if int(result.get("triangles", -1)) != 252:
        _failure("Expected 252 triangulated polygon faces, got %s" % str(result.get("triangles", "?")))
        return
    if (result["groups"] as Dictionary).size() != 16:
        _failure("Nested group hierarchy lost")
        return
    var model: Node3D = result["root"]
    root.add_child(model)
    var visual_count := 0
    var stack: Array[Node] = [model]
    while not stack.is_empty():
        var item: Node = stack.pop_back()
        if item is MeshInstance3D:
            var mesh: MeshInstance3D = item
            if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
                visual_count += 1
                if mesh.mesh.get_aabb().size.length() < 0.01:
                    _failure("Mesh has zero-size AABB")
                    return
                var material: Material = mesh.mesh.surface_get_material(0)
                if not (material is StandardMaterial3D):
                    _failure("Untextured polygon face lacks visible fallback material")
                    return
        for child in item.get_children():
            stack.append(child)
    if visual_count != 18:
        _failure("Not all mesh parts created visible geometry: %d" % visual_count)
        return
    # The source mesh's vertices are relative to its rotation pivot, so the
    # geometry itself must remain centered around the LOCAL origin.
    var local_group: Node3D = result["groups"]["grp_1"]["node"]
    var local_part: Node3D = local_group.get_node_or_null("synthetic_part_1")
    if local_part == null:
        _failure("Nested mesh part lost")
        return
    var local_geometry: MeshInstance3D = local_part.get_node_or_null("BBFaceMesh")
    if local_geometry == null or local_geometry.mesh == null:
        _failure("Nested mesh geometry missing")
        return
    if local_geometry.mesh.get_aabb().get_center().length() > 0.0001:
        _failure("Mesh vertices incorrectly offset by their pivot a second time")
        return

    var clip: Dictionary = result["animations"][0]
    importer.apply_clip(result["groups"], clip, 1.0, false)
    var joint: Node3D = result["groups"]["grp_1"]["node"]
    if absf(joint.rotation_degrees.y - 90.0) > 0.1:
        _failure("Rotation animation was not read from group UUID")
        return
    importer.apply_clip(result["groups"], clip, 0.0, false)
    if absf(joint.rotation_degrees.y) > 0.1:
        _failure("Scrubbing did not restore group pose")
        return

    var editor_scene: PackedScene = load("res://scenes/editor.tscn")
    var editor: Control = editor_scene.instantiate()
    root.add_child(editor)
    await process_frame
    if not editor.call("_import_bbmodel_text", source, "Fixture"):
        _failure("Movie Creator UI could not import model")
        return
    var assets: Dictionary = editor.get("bb_assets")
    if assets.size() != 1:
        _failure("Imported asset missing from editor")
        return
    var imported_id: String = str(assets.keys()[0])
    var imported: Node3D = (editor.get("objects_by_id") as Dictionary)[imported_id]
    if imported.get_node_or_null("SelectionFrame") == null:
        _failure("Imported model should have selection outline")
        return
    if not str((editor.get("status_label") as Label).text).contains("18メッシュ"):
        _failure("Success status does not describe the imported free meshes")
        return
    var saved: Dictionary = editor.call("_serialize_project")
    var found := false
    for entry in saved["objects"]:
        if str(entry.get("kind", "")) == "bbmodel":
            if str(entry.get("bb_source", "")).length() != source.length():
                _failure("Saved model source differs")
                return
            found = true
    if not found:
        _failure("Model missing from project serialization")
        return
    print("FREE MESH TEST PASSED: 18 meshes, 134 faces, 252 triangles, 16 groups, color, animation, editor import, serialization")
    quit(0)
