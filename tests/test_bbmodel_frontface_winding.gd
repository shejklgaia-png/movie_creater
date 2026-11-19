extends SceneTree
## Godot SurfaceTool renders the clockwise side as FRONT. This is not the
## same thing as supplying a correct outward-facing shading normal.
## Catch a polygon or cuboid whose normal points outward while its
## CULL_BACK geometry hides the outside and displays the inside instead.
const Importer = preload("res://scripts/bbmodel_importer.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("BBMODEL FRONTFACE WINDING FAILED: " + reason)
    quit(1)

func _assert_winding(model: Node, kind: String) -> bool:
    var checked := 0
    var surfaces := 0
    var nodes: Array[Node] = [model]
    while not nodes.is_empty():
        var item: Node = nodes.pop_back()
        if item is MeshInstance3D:
            var part := item as MeshInstance3D
            for surface in range(part.mesh.get_surface_count()):
                surfaces += 1
                var array_data: Array = part.mesh.surface_get_arrays(surface)
                var points: PackedVector3Array = array_data[Mesh.ARRAY_VERTEX]
                var normals: PackedVector3Array = array_data[Mesh.ARRAY_NORMAL]
                if points.size() != normals.size() or points.size() % 3 != 0:
                    _fail("%s: invalid vertex/normal count in %s" % [kind, part.name])
                    return false
                for i in range(0, points.size(), 3):
                    var cross: Vector3 = (points[i + 1] - points[i]).cross(points[i + 2] - points[i])
                    if cross.length_squared() < 0.0000000001:
                        continue
                    if normals[i].length_squared() < 0.9:
                        _fail("%s: invalid shading normal at triangle %d" % [kind, i / 3])
                        return false
                    # Godot 4's clockwise front face has a triangle cross
                    # product opposite to the front-facing shading normal.
                    if cross.normalized().dot(normals[i]) > -0.98:
                        _fail("%s: inward/culled front face at triangle %d in %s (dot %.3f)" % [
                            kind, i / 3, part.name, cross.normalized().dot(normals[i])])
                        return false
                    checked += 1
        for child in item.get_children():
            nodes.append(child)
    if checked < 4 or surfaces < 1:
        _fail("%s: not enough triangles/surfaces examined" % kind)
        return false
    return true

func _run() -> void:
    for fixture in ["res://tests/fixtures/free_mesh_5.bbmodel", "res://tests/fixtures/simple_5.bbmodel"]:
        var data := FileAccess.get_file_as_string(fixture)
        var model := Importer.new().import_text(data)
        if not bool(model.get("ok", false)):
            _fail("Could not import " + fixture)
            return
        var node: Node3D = model["root"]
        root.add_child(node)
        if not _assert_winding(node, fixture):
            return
    print("BBMODEL FRONTFACE WINDING PASSED: imported polygons and cubes expose outward faces with Godot clockwise triangles")
    quit(0)
