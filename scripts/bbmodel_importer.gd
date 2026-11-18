extends RefCounted
## Blockbench .bbmodel v4 and v5 cuboid import. Units: 16 Blockbench pixels = 1 Godot meter.
## Preserve absolute pivot locations through parent-relative node transforms.
const UNIT := 0.0625
const MAX_CUBES := 4000
var warnings: Array[String] = []
var _elements: Dictionary = {}
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _dimensions: Dictionary = {}
var _group_states: Dictionary = {}
var _all_elements: Dictionary = {}
var _cubes_created := 0

func import_text(source: String) -> Dictionary:
    warnings.clear()
    _elements.clear()
    _groups.clear()
    _materials.clear()
    _dimensions.clear()
    _group_states.clear()
    _all_elements.clear()
    _cubes_created = 0
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
    if entries.size() > MAX_CUBES:
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
    if _cubes_created == 0:
        for element in _elements.values():
            _create_cube(element, root, Vector3.ZERO)
    if _cubes_created == 0:
        root.free()
        return {"ok": false, "error": "表示できるキューブがありません"}
    var clips: Array = []
    for animation_value in document.get("animations", []):
        if animation_value is Dictionary:
            var anim: Dictionary = animation_value
            clips.append(anim)
            _check_animation_features(anim)
    return {
        "ok": true, "root": root, "groups": _group_states.duplicate(),
        "animations": clips, "warnings": warnings.duplicate(),
        "cubes": _cubes_created, "textures": _materials.size()
    }

func _parse_textures(raw: Variant, resolution: Variant) -> void:
    if not (raw is Array):
        return
    var base_size := Vector2(16, 16)
    if resolution is Dictionary:
        base_size = Vector2(maxf(1.0, float(resolution.get("width", 16))), maxf(1.0, float(resolution.get("height", 16))))
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
            _create_cube(_elements[uuid], parent, parent_origin)
        return
    if not (entry is Dictionary):
        return
    var outline: Dictionary = entry
    var id := str(outline.get("uuid", ""))
    var group: Dictionary = _groups.get(id, outline)
    var origin := _to_vec(group.get("origin", [0, 0, 0]))
    var node := Node3D.new()
    node.name = str(group.get("name", "Group")).validate_node_name()
    node.rotation_order = EULER_ORDER_XYZ
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

func _create_cube(data: Dictionary, parent: Node3D, parent_origin: Vector3) -> void:
    if str(data.get("type", "cube")) != "cube":
        warnings.append("未対応の要素: %s" % str(data.get("type", "unknown")))
        return
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
