extends RefCounted
## Blockbench .bbmodel v4/v5 cuboid + polygon mesh importer.
## 16 Blockbench pixels = 1 Godot meter. In particular, free-form meshes are
## NOT cubes (the user's actual Blockbench 5 assets use type "mesh" exclusively).
## Preserve absolute pivot locations through parent-relative node transforms.
const UNIT := 0.0625
const MAX_ELEMENTS := 4000
const MAX_MESH_VERTICES := 20000
const MAX_POLYGON_VERTICES := 256
const BLOCKBENCH_COLORS := [
    "#ff6b6b", "#f6a45d", "#f6d365", "#90d26d",
    "#58c6b9", "#63b8ec", "#7284ea", "#b18ce5",
    "#ed8cd4", "#df83aa", "#c7d1de", "#86b7b9",
    "#9bb66c", "#c4a885", "#829aaf", "#e1b7a7"
]
var warnings: Array[String] = []
var _elements: Dictionary = {}
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _dimensions: Dictionary = {}
var _group_states: Dictionary = {}
var _all_elements: Dictionary = {}
var _cubes_created := 0
var _meshes_created := 0
var _triangles_created := 0
var _default_texture_size := Vector2(16.0, 16.0)

func import_text(source: String) -> Dictionary:
    warnings.clear()
    _elements.clear()
    _groups.clear()
    _materials.clear()
    _dimensions.clear()
    _group_states.clear()
    _all_elements.clear()
    _cubes_created = 0
    _meshes_created = 0
    _triangles_created = 0
    _default_texture_size = Vector2(16.0, 16.0)
    var json := JSON.new()
    var err := json.parse(source)
    if err != OK or not (json.data is Dictionary):
        return {"ok": false, "error": "JSONの形式が正しくありません"}
    var document: Dictionary = json.data
    if not (document.get("elements", null) is Array):
        return {"ok": false, "error": ".bbmodelのelementsがありません"}
    if not (document.get("outliner", null) is Array):
        return {"ok": false, "error": ".bbmodelのoutlinerがありません"}
    var entries: Array = document.get("elements", [])
    if entries.size() > MAX_ELEMENTS:
        return {"ok": false, "error": "モデルが大きすぎます（上限4000要素）"}
    for element_value in entries:
        if element_value is Dictionary:
            var element: Dictionary = element_value
            _elements[str(element.get("uuid", ""))] = element
    for group_value in document.get("groups", []):
        if group_value is Dictionary:
            var group: Dictionary = group_value
            _groups[str(group.get("uuid", ""))] = group
    _parse_textures(document.get("textures", []), document.get("resolution", {}))

    var root := Node3D.new()
    root.name = "BBModel"
    root.set_meta("bb_format", str(document.get("meta", {}).get("format_version", "unknown")))
    var hierarchy: Array = document.get("outliner", [])
    for entry in hierarchy:
        _build_outliner(entry, root, Vector3.ZERO)
    # Some BBModel files store geometry outside the outliner. Import only
    # unreferenced elements; never duplicate geometry already in its groups.
    for uuid in _elements.keys():
        if not _all_elements.has(uuid):
            _all_elements[uuid] = true
            _create_element(_elements[uuid], root, Vector3.ZERO)
    if _cubes_created + _meshes_created == 0:
        root.free()
        return {"ok": false, "error": "表示できる形状がありません（未対応の要素形式か空のモデルです）"}
    var clips: Array = []
    for animation_value in document.get("animations", []):
        if animation_value is Dictionary:
            var anim: Dictionary = animation_value
            clips.append(anim)
            _check_animation_features(anim)
    return {
        "ok": true, "root": root, "model_name": str(document.get("name", "")),
        "groups": _group_states.duplicate(),
        "animations": clips, "warnings": warnings.duplicate(),
        "cubes": _cubes_created, "meshes": _meshes_created,
        "triangles": _triangles_created, "textures": _materials.size()
    }

func _parse_textures(raw: Variant, resolution: Variant) -> void:
    if not (raw is Array):
        return
    var base_size := Vector2(16, 16)
    if resolution is Dictionary:
        base_size = Vector2(maxf(1.0, float(resolution.get("width", 16))), maxf(1.0, float(resolution.get("height", 16))))
    _default_texture_size = base_size
    for i in range(raw.size()):
        if not (raw[i] is Dictionary):
            continue
        var data: Dictionary = raw[i]
        var key := str(data.get("uuid", str(i)))
        var uv_size := Vector2(maxf(1.0, float(data.get("uv_width", base_size.x))), maxf(1.0, float(data.get("uv_height", base_size.y))))
        _dimensions[key] = uv_size
        var material := StandardMaterial3D.new()
        material.albedo_color = Color.WHITE
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        var source := str(data.get("source", ""))
        if source.begins_with("data:image/") and source.contains(";base64,"):
            var comma := source.find(",")
            var decoded := Marshalls.base64_to_raw(source.substr(comma + 1))
            var img := Image.new()
            var image_error := ERR_FILE_UNRECOGNIZED
            if source.begins_with("data:image/png"):
                image_error = img.load_png_from_buffer(decoded)
            elif source.begins_with("data:image/jpeg") or source.begins_with("data:image/jpg"):
                image_error = img.load_jpg_from_buffer(decoded)
            if image_error == OK:
                material.albedo_texture = ImageTexture.create_from_image(img)
            else:
                warnings.append("未対応または破損した埋め込み画像: %s" % str(data.get("name", key)))
        else:
            warnings.append("外部テクスチャを使用: %s（画像をモデル内に埋め込んでください）" % str(data.get("name", key)))
        _materials[key] = material
        _materials[str(i)] = material
        _dimensions[str(i)] = uv_size

func _get_material(texture_ref: Variant) -> Material:
    if _materials.has(str(texture_ref)):
        return _materials[str(texture_ref)]
    if _materials.has("0"):
        return _materials["0"]
    var plain := StandardMaterial3D.new()
    plain.albedo_color = Color("#b5c7dd")
    plain.cull_mode = BaseMaterial3D.CULL_DISABLED
    return plain

func _texture_key(face: Dictionary) -> String:
    var ref: Variant = face.get("texture", 0)
    if ref == null:
        return "__skip__"
    return str(ref)

func _build_outliner(entry: Variant, parent: Node3D, parent_origin: Vector3) -> void:
    if entry is String:
        var uuid := str(entry)
        if _elements.has(uuid) and not _all_elements.has(uuid):
            _all_elements[uuid] = true
            _create_element(_elements[uuid], parent, parent_origin)
        return
    if not (entry is Dictionary):
        return
    var outline: Dictionary = entry
    var id := str(outline.get("uuid", ""))
    # Newer Blockbench files may write elements inline as dictionaries.
    if _elements.has(id) and not _groups.has(id):
        if not _all_elements.has(id):
            _all_elements[id] = true
            _create_element(_elements[id], parent, parent_origin)
        return
    if outline.has("vertices") or outline.has("from"):
        _create_element(outline, parent, parent_origin)
        return
    var group: Dictionary = _groups.get(id, outline)
    var origin := _to_vec(group.get("origin", [0, 0, 0]))
    var node := Node3D.new()
    node.name = str(group.get("name", "Group")).validate_node_name()
    # Blockbench/three.js bones use intrinsic ZYX Euler order (Rx, then Ry, then Rz).
    # Cuboid and free-mesh ELEMENT rotations use XYZ, and stay unchanged.
    # XYZ on multi-axis animated bones displaced legs and feet dramatically.
    node.rotation_order = EULER_ORDER_ZYX
    node.position = (origin - parent_origin) * UNIT
    node.rotation_degrees = _to_vec(group.get("rotation", [0, 0, 0]))
    node.visible = bool(group.get("visibility", true))
    parent.add_child(node)
    if not id.is_empty():
        _group_states[id] = {
            "node": node,
            "position": node.position,
            "rotation": node.rotation_degrees,
            "scale": node.scale
        }
    var children: Array = outline.get("children", [])
    for child in children:
        _build_outliner(child, node, origin)

func _create_element(data: Dictionary, parent: Node3D, parent_origin: Vector3) -> void:
    var kind := str(data.get("type", "cube"))
    match kind:
        "cube":
            _create_cube(data, parent, parent_origin)
        "mesh":
            _create_mesh(data, parent, parent_origin)
        _:
            warnings.append("未対応の要素: %s" % kind)

func _create_cube(data: Dictionary, parent: Node3D, parent_origin: Vector3) -> void:
    var from := _to_vec(data.get("from", [0, 0, 0]))
    var to := _to_vec(data.get("to", [0, 0, 0]))
    var pivot := _to_vec(data.get("origin", (from + to) * 0.5))
    var inflate := float(data.get("inflate", 0))
    var mn := Vector3(minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z)) - Vector3.ONE * inflate
    var mx := Vector3(maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z)) + Vector3.ONE * inflate
    if (mx - mn).length_squared() < 0.00001:
        return
    var cube := Node3D.new()
    cube.name = str(data.get("name", "Cube")).validate_node_name()
    cube.position = (pivot - parent_origin) * UNIT
    cube.rotation_order = EULER_ORDER_XYZ
    cube.rotation_degrees = _to_vec(data.get("rotation", [0, 0, 0]))
    cube.visible = bool(data.get("visibility", true))
    parent.add_child(cube)

    # Build each face into a material-indexed surface (UV per face).
    var sides := _cube_faces((mn - pivot) * UNIT, (mx - pivot) * UNIT)
    var faces: Dictionary = data.get("faces", {})
    var buckets: Dictionary = {}
    for side_name in sides.keys():
        if not faces.has(side_name):
            continue
        var f: Dictionary = faces[side_name]
        if _texture_key(f) == "__skip__":
            continue
        var texture_key := _texture_key(f)
        if not buckets.has(texture_key):
            buckets[texture_key] = []
        (buckets[texture_key] as Array).append({"side": side_name, "corners": sides[side_name], "face": f})
    for texture_key in buckets.keys():
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var texture_size: Vector2 = _dimensions.get(str(texture_key), Vector2(16, 16))
        for record in buckets[texture_key]:
            _emit_face(st, record["corners"], record["face"], texture_size)
        st.set_material(_get_material(texture_key))
        var mesh := st.commit()
        if mesh != null and mesh.get_surface_count() > 0:
            var instance := MeshInstance3D.new()
            instance.name = "BBFaceMesh"
            instance.mesh = mesh
            cube.add_child(instance)
    _cubes_created += 1

func _fallback_mesh_material(color_index: int) -> StandardMaterial3D:
    var key := "__mesh_color_%d" % posmod(color_index, BLOCKBENCH_COLORS.size())
    if _materials.has(key):
        return _materials[key]
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(BLOCKBENCH_COLORS[posmod(color_index, BLOCKBENCH_COLORS.size())])
    material.roughness = 0.85
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _materials[key] = material
    return material

func _create_mesh(data: Dictionary, parent: Node3D, parent_origin: Vector3) -> void:
    var raw_vertices: Variant = data.get("vertices", {})
    var raw_faces: Variant = data.get("faces", {})
    if not (raw_vertices is Dictionary) or not (raw_faces is Dictionary):
        warnings.append("頂点データが不正: %s" % str(data.get("name", "Mesh")))
        return
    var vertices: Dictionary = raw_vertices
    var faces: Dictionary = raw_faces
    if vertices.is_empty() or faces.is_empty() or vertices.size() > MAX_MESH_VERTICES:
        warnings.append("空または頂点数が上限を超えるメッシュ: %s" % str(data.get("name", "Mesh")))
        return
    var pivot := _to_vec(data.get("origin", [0, 0, 0]))
    var mesh_root := Node3D.new()
    mesh_root.name = str(data.get("name", "Mesh")).validate_node_name()
    mesh_root.position = (pivot - parent_origin) * UNIT
    mesh_root.rotation_order = EULER_ORDER_XYZ
    mesh_root.rotation_degrees = _to_vec(data.get("rotation", [0, 0, 0]))
    mesh_root.visible = bool(data.get("visibility", true))
    parent.add_child(mesh_root)

    var records: Dictionary = {}
    var untextured_key := "__fallback"
    var color_index := int(data.get("color", 10))
    var triangle_count := 0
    for face_value in faces.values():
        if not (face_value is Dictionary):
            continue
        var face: Dictionary = face_value
        var raw_ids: Variant = face.get("vertices", [])
        if not (raw_ids is Array):
            continue
        var face_ids: Array = raw_ids
        if face_ids.size() < 3 or face_ids.size() > MAX_POLYGON_VERTICES:
            continue
        var points: Array[Vector3] = []
        var uv_points: Array[Vector2] = []
        var face_uv: Dictionary = face.get("uv", {})
        var valid := true
        for uuid_value in face_ids:
            var uuid := str(uuid_value)
            if not vertices.has(uuid):
                valid = false
                break
            # Blockbench polygon mesh vertices are ALREADY local to the element pivot.
            # Cuboid from/to coordinates, in contrast, are absolute model coordinates.
            points.append(_to_vec(vertices[uuid]) * UNIT)
            var uv_value: Variant = face_uv.get(uuid, [0, 0])
            if uv_value is Array and uv_value.size() >= 2:
                uv_points.append(Vector2(float(uv_value[0]), float(uv_value[1])))
            else:
                uv_points.append(Vector2.ZERO)
        if not valid:
            continue
        # Newell's algorithm works for triangles, quads and non-axis-aligned n-gons.
        var normal := Vector3.ZERO
        for i in range(points.size()):
            var p: Vector3 = points[i]
            var q: Vector3 = points[(i + 1) % points.size()]
            normal.x += (p.y - q.y) * (p.z + q.z)
            normal.y += (p.z - q.z) * (p.x + q.x)
            normal.z += (p.x - q.x) * (p.y + q.y)
        if normal.length_squared() < 0.00000001:
            continue
        normal = normal.normalized()

        # Triangulate in a dominant-axis plane to preserve concave polygon faces.
        var polygon := PackedVector2Array()
        var nabs := normal.abs()
        for p in points:
            if nabs.x >= nabs.y and nabs.x >= nabs.z:
                polygon.append(Vector2(p.y, p.z))
            elif nabs.y >= nabs.z:
                polygon.append(Vector2(p.x, p.z))
            else:
                polygon.append(Vector2(p.x, p.y))
        var indices := Geometry2D.triangulate_polygon(polygon)
        if indices.is_empty():
            # Degenerate self-intersecting polygons are ignored instead of
            # turning one malformed face into an entirely failed import.
            warnings.append("三角形分割できない面: %s" % mesh_root.name)
            continue

        var face_texture: Variant = face.get("texture", null)
        var key := untextured_key if face_texture == null else str(face_texture)
        if not records.has(key):
            records[key] = []
        (records[key] as Array).append({
            "points": points, "uvs": uv_points,
            "indices": indices, "normal": normal
        })
        triangle_count += indices.size() / 3

    for material_key in records.keys():
        var builder := SurfaceTool.new()
        builder.begin(Mesh.PRIMITIVE_TRIANGLES)
        var uv_size: Vector2 = _default_texture_size
        var material: Material = _fallback_mesh_material(color_index)
        if material_key != untextured_key:
            uv_size = _dimensions.get(str(material_key), _default_texture_size)
            material = _get_material(material_key)
        for record in records[material_key]:
            var points: Array = record["points"]
            var uv_points: Array = record["uvs"]
            var indices: PackedInt32Array = record["indices"]
            var face_normal: Vector3 = record["normal"]
            for i in indices:
                builder.set_normal(face_normal)
                builder.set_uv(uv_points[i] / uv_size)
                builder.add_vertex(points[i])
        builder.set_material(material)
        var assembled := builder.commit()
        if assembled != null and assembled.get_surface_count() > 0:
            var instance := MeshInstance3D.new()
            instance.name = "BBFaceMesh"
            instance.mesh = assembled
            mesh_root.add_child(instance)
    if triangle_count > 0:
        _meshes_created += 1
        _triangles_created += triangle_count
    else:
        mesh_root.free()

func _cube_faces(a: Vector3, b: Vector3) -> Dictionary:
    var x0 := a.x
    var y0 := a.y
    var z0 := a.z
    var x1 := b.x
    var y1 := b.y
    var z1 := b.z
    return {
        "north": [Vector3(x0,y0,z0), Vector3(x0,y1,z0), Vector3(x1,y1,z0), Vector3(x1,y0,z0)],
        "south": [Vector3(x1,y0,z1), Vector3(x1,y1,z1), Vector3(x0,y1,z1), Vector3(x0,y0,z1)],
        "east": [Vector3(x1,y0,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3(x1,y0,z1)],
        "west": [Vector3(x0,y0,z1), Vector3(x0,y1,z1), Vector3(x0,y1,z0), Vector3(x0,y0,z0)],
        "up": [Vector3(x0,y1,z0), Vector3(x0,y1,z1), Vector3(x1,y1,z1), Vector3(x1,y1,z0)],
        "down": [Vector3(x0,y0,z1), Vector3(x0,y0,z0), Vector3(x1,y0,z0), Vector3(x1,y0,z1)]
    }

func _emit_face(st: SurfaceTool, corners: Array, face: Dictionary, tex_size: Vector2) -> void:
    var uv: Array = face.get("uv", [0, 0, tex_size.x, tex_size.y])
    if uv.size() < 4:
        uv = [0, 0, tex_size.x, tex_size.y]
    var coords: Array[Vector2] = [
        Vector2(float(uv[0]), float(uv[3])),
        Vector2(float(uv[0]), float(uv[1])),
        Vector2(float(uv[2]), float(uv[1])),
        Vector2(float(uv[2]), float(uv[3]))
    ]
    var turns := posmod(int(round(float(face.get("rotation", 0)) / 90.0)), 4)
    var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
    for index in [0, 1, 2, 0, 2, 3]:
        var rotated: int = (int(index) + turns) % 4
        st.set_normal(normal)
        st.set_uv(coords[rotated] / tex_size)
        st.add_vertex(corners[index])

func _check_animation_features(anim: Dictionary) -> void:
    for animator in anim.get("animators", {}).values():
        if not (animator is Dictionary):
            continue
        for value in animator.get("keyframes", []):
            if value is Dictionary:
                var mode := str(value.get("interpolation", "linear"))
                if mode != "linear" and mode != "step":
                    if not warnings.has("補間方式 %s は現在線形でプレビューします" % mode):
                        warnings.append("補間方式 %s は現在線形でプレビューします" % mode)

func apply_clip(groups: Dictionary, clip: Dictionary, time: float, old_format: bool) -> void:
    for uuid in groups.keys():
        var state: Dictionary = groups[uuid]
        var node: Node3D = state["node"]
        if not is_instance_valid(node):
            continue
        node.position = state["position"]
        node.rotation_degrees = state["rotation"]
        node.scale = state["scale"]
    var animators: Dictionary = clip.get("animators", {})
    for uuid in animators.keys():
        if not groups.has(uuid):
            continue
        var animator: Dictionary = animators[uuid]
        var frames: Array = animator.get("keyframes", [])
        var state: Dictionary = groups[uuid]
        var node: Node3D = state["node"]
        for channel in ["position", "rotation", "scale"]:
            var sampled: Variant = _sample_channel(frames, channel, time)
            if sampled == null:
                continue
            var delta: Vector3 = sampled
            if old_format:
                if channel == "position":
                    delta.x = -delta.x
                elif channel == "rotation":
                    delta.x = -delta.x
                    delta.y = -delta.y
            match channel:
                "position":
                    node.position = state["position"] + delta * UNIT
                "rotation":
                    node.rotation_degrees = state["rotation"] + delta
                "scale":
                    node.scale = state["scale"] * delta

func _sample_channel(frames: Array, channel: String, time: float) -> Variant:
    var candidates: Array[Dictionary] = []
    for value in frames:
        if value is Dictionary and str(value.get("channel", "")) == channel:
            candidates.append(value)
    if candidates.is_empty():
        return null
    candidates.sort_custom(func(a, b): return float(a.get("time", 0)) < float(b.get("time", 0)))
    var before: Dictionary = candidates[0]
    var after: Dictionary = candidates[candidates.size() - 1]
    if time <= float(before.get("time", 0)):
        after = before
    elif time >= float(after.get("time", 0)):
        before = after
    else:
        for i in range(candidates.size() - 1):
            if time >= float(candidates[i].get("time", 0)) and time <= float(candidates[i+1].get("time", 0)):
                before = candidates[i]
                after = candidates[i+1]
                break
    var vec0 := _key_vector(before, false)
    if str(before.get("interpolation", "")) == "step":
        return vec0
    var vec1 := _key_vector(after, true)
    var t0 := float(before.get("time", 0))
    var t1 := float(after.get("time", t0))
    var blend := 0.0 if absf(t1 - t0) < 0.00001 else clampf((time-t0)/(t1-t0), 0, 1)
    return vec0.lerp(vec1, blend)

func _key_vector(key: Dictionary, pre: bool) -> Vector3:
    var points: Array = key.get("data_points", [])
    if points.is_empty():
        return Vector3.ZERO
    var point: Dictionary = points[0] if pre else points[points.size()-1]
    return Vector3(
        _numeric(point.get("x", 0)), _numeric(point.get("y", 0)), _numeric(point.get("z", 0)))

func _numeric(value: Variant) -> float:
    if value is float or value is int:
        return float(value)
    var s := str(value)
    return float(s) if s.is_valid_float() else 0.0

func _to_vec(value: Variant) -> Vector3:
    if value is Array and value.size() >= 3:
        return Vector3(float(value[0]), float(value[1]), float(value[2]))
    if value is Vector3:
        return value
    return Vector3.ZERO
