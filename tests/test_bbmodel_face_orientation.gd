extends SceneTree
## Free meshes: correct reversed polygons in closed shells, preserve backface
## culling for solids, but show both sides of intentionally open sheet geometry.
const Importer = preload("res://scripts/bbmodel_importer.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("BBMODEL FACE ORIENTATION FAILED: " + reason)
    quit(1)

func _run() -> void:
    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    var doc: Dictionary = JSON.parse_string(source)
    var first: Dictionary = doc["elements"][0]
    var f0: Dictionary = first["faces"]["f0"]
    var vertices: Array = f0["vertices"]
    vertices.reverse()
    f0["vertices"] = vertices

    var importer := Importer.new()
    var loaded: Dictionary = importer.import_text(JSON.stringify(doc))
    if not bool(loaded.get("ok", false)):
        _fail("Closed model with a reversed face was rejected")
        return
    var model: Node3D = loaded["root"]
    root.add_child(model)
    var part: Node3D = model.find_child("body_mesh", true, false)
    if part == null:
        _fail("Closed body mesh missing")
        return
    var visual: MeshInstance3D = part.get_node_or_null("BBFaceMesh")
    if visual == null:
        _fail("No polygon surface in closed mesh")
        return
    var material: Material = visual.mesh.surface_get_material(0)
    if not (material is BaseMaterial3D) or (material as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_BACK:
        _fail("Closed mesh must not switch to transparent/double-sided fallback")
        return
    var arrays: Array = visual.mesh.surface_get_arrays(0)
    var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var center: Vector3 = visual.mesh.get_aabb().get_center()
    for i in range(0, positions.size(), 3):
        var face_center: Vector3 = (positions[i] + positions[i + 1] + positions[i + 2]) / 3.0
        if normals[i].dot(face_center - center) <= 0.01:
            _fail("A solid's triangle is inward-facing at index %d" % i)
            return

    # A plane has open boundary edges; its visible front/back should not
    # disappear solely because the artist views it from behind.
    first["faces"] = {"f0": f0}
    loaded = importer.import_text(JSON.stringify(doc))
    if not bool(loaded.get("ok", false)):
        _fail("Open polygon mesh could not be loaded")
        return
    var plane: Node3D = loaded["root"]
    root.add_child(plane)
    var open_part: Node3D = plane.find_child("body_mesh", true, false)
    if open_part == null:
        _fail("Open mesh missing")
        return
    var open_visual: MeshInstance3D = open_part.get_node_or_null("BBFaceMesh")
    if open_visual == null:
        _fail("Open mesh has no surface")
        return
    var open_material: Material = open_visual.mesh.surface_get_material(0)
    if not (open_material is BaseMaterial3D) or (open_material as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
        _fail("Open polygon should be visible from either side")
        return
    print("BBMODEL FACE ORIENTATION PASSED: corrected solid normals and winding, preserved opaque backface culling, two-sided open sheets")
    quit(0)
