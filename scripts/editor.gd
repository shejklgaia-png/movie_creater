extends Control
## Movie Creator 0.1: a portrait-first cutscene blocking and keyframe editor.
## All editor state stays in this project; other game repositories are untouched.

const TimelineView = preload("res://scripts/timeline.gd")
const SAVE_PATH := "user://movie_project.json"
const DURATION := 15.0
const COLOR_SET := ["#58b6e8", "#d991e8", "#edb565", "#83d59e", "#e9919c"]

var scene_root: Node3D
var preview: SubViewport
var preview_box: SubViewportContainer
var editor_camera: Camera3D
var timeline: Control
var clock_label: Label
var status_label: Label
var play_button: Button
var time_slider: HSlider
var selection: OptionButton
var axis_option: OptionButton
var mode_option: OptionButton

var objects_by_id: Dictionary = {}
var tracks: Dictionary = {}
var next_id := 1
var selected_id := ""
var current_time := 0.0
var playing := false

var orbit_target := Vector3(0.0, 0.9, 0.0)
var orbit_yaw := 0.65
var orbit_pitch := 0.48
var orbit_distance := 9.0
var touches: Dictionary = {}
var touch_starts: Dictionary = {}
var mouse_start := Vector2.ZERO

func _ready() -> void:
    _build_interface()
    _build_3d_scene()
    if FileAccess.file_exists(SAVE_PATH):
        _load_project()
    else:
        _add_object("box")
        _add_object("sphere")
        _show_message("モデルを選んで移動し、◆でキーフレームを追加")
    _seek(0.0)

func _process(delta: float) -> void:
    if not playing:
        return
    current_time = minf(current_time + delta, DURATION)
    _sample_all()
    _update_clock()
    if is_equal_approx(current_time, DURATION):
        _set_playing(false)

func _build_interface() -> void:
    var layout := VBoxContainer.new()
    layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layout.add_theme_constant_override("separation", 4)
    add_child(layout)

    var header := HBoxContainer.new()
    header.custom_minimum_size.y = 54
    layout.add_child(header)
    var app_title := Label.new()
    app_title.text = "MOVIE CREATOR"
    app_title.add_theme_font_size_override("font_size", 19)
    app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    app_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    header.add_child(app_title)
    _make_button(header, "保存", _save_project)
    _make_button(header, "読込", _load_project)

    preview_box = SubViewportContainer.new()
    preview_box.stretch = true
    preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview_box.custom_minimum_size = Vector2(0, 230)
    preview_box.mouse_filter = Control.MOUSE_FILTER_STOP
    layout.add_child(preview_box)
    preview_box.gui_input.connect(_on_preview_input)

    preview = SubViewport.new()
    preview.size = Vector2i(432, 520)
    preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    preview.own_world_3d = true
    preview_box.add_child(preview)

    var dock := VBoxContainer.new()
    dock.add_theme_constant_override("separation", 3)
    layout.add_child(dock)

    var playback := HBoxContainer.new()
    dock.add_child(playback)
    play_button = _make_button(playback, "▶", _toggle_play)
    clock_label = Label.new()
    clock_label.text = "00:00.00"
    clock_label.custom_minimum_size.x = 92
    clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    playback.add_child(clock_label)
    time_slider = HSlider.new()
    time_slider.min_value = 0.0
    time_slider.max_value = DURATION
    time_slider.step = 0.01
    time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    time_slider.value_changed.connect(_seek)
    playback.add_child(time_slider)

    timeline = TimelineView.new()
    timeline.custom_minimum_size = Vector2(0, 164)
    timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dock.add_child(timeline)
    timeline.seek_requested.connect(_seek)
    timeline.key_dragged.connect(_on_key_dragged)

    var add_row := HBoxContainer.new()
    dock.add_child(add_row)
    _make_button(add_row, "＋箱", func(): _add_object("box"))
    _make_button(add_row, "＋球", func(): _add_object("sphere"))
    _make_button(add_row, "◆ キー登録", _insert_key)

    var properties := HBoxContainer.new()
    dock.add_child(properties)
    selection = OptionButton.new()
    selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    selection.custom_minimum_size.y = 48
    properties.add_child(selection)
    selection.item_selected.connect(_on_selection_changed)
    mode_option = OptionButton.new()
    mode_option.add_item("移動")
    mode_option.add_item("回転")
    mode_option.custom_minimum_size.y = 48
    properties.add_child(mode_option)
    axis_option = OptionButton.new()
    for axis in ["X", "Y", "Z"]:
        axis_option.add_item(axis)
    axis_option.custom_minimum_size.y = 48
    properties.add_child(axis_option)

    var nudge_row := HBoxContainer.new()
    dock.add_child(nudge_row)
    _make_button(nudge_row, "－", func(): _nudge(-1.0))
    var nudge_hint := Label.new()
    nudge_hint.text = "移動 0.25m / 回転 10°"
    nudge_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    nudge_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    nudge_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    nudge_row.add_child(nudge_hint)
    _make_button(nudge_row, "＋", func(): _nudge(1.0))

    status_label = Label.new()
    status_label.custom_minimum_size.y = 28
    status_label.add_theme_font_size_override("font_size", 12)
    dock.add_child(status_label)

func _make_button(parent: Control, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(52, 48)
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _build_3d_scene() -> void:
    scene_root = Node3D.new()
    scene_root.name = "EditingWorld"
    preview.add_child(scene_root)

    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#101823")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#d7e4ff")
    environment.ambient_light_energy = 0.75
    world.environment = environment
    scene_root.add_child(world)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.light_energy = 1.2
    scene_root.add_child(light)

    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(40, 40)
    var floor := MeshInstance3D.new()
    floor.mesh = floor_mesh
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color("#303b47")
    floor.material_override = floor_material
    scene_root.add_child(floor)

    var grid := ImmediateMesh.new()
    grid.surface_begin(Mesh.PRIMITIVE_LINES)
    for i in range(-10, 11):
        var v := float(i)
        grid.surface_add_vertex(Vector3(v, 0.012, -10.0))
        grid.surface_add_vertex(Vector3(v, 0.012, 10.0))
        grid.surface_add_vertex(Vector3(-10.0, 0.012, v))
        grid.surface_add_vertex(Vector3(10.0, 0.012, v))
    grid.surface_end()
    var grid_node := MeshInstance3D.new()
    grid_node.mesh = grid
    var grid_material := StandardMaterial3D.new()
    grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    grid_material.albedo_color = Color("#526174")
    grid_node.material_override = grid_material
    scene_root.add_child(grid_node)

    editor_camera = Camera3D.new()
    editor_camera.current = true
    editor_camera.fov = 54.0
    scene_root.add_child(editor_camera)
    _update_camera()

func _update_camera() -> void:
    var direction := Vector3(
        sin(orbit_yaw) * cos(orbit_pitch),
        sin(orbit_pitch),
        cos(orbit_yaw) * cos(orbit_pitch))
    editor_camera.position = orbit_target + direction * orbit_distance
    editor_camera.look_at(orbit_target, Vector3.UP)

func _on_preview_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index] = event.position
            touch_starts[event.index] = event.position
        else:
            var start: Vector2 = touch_starts.get(event.index, event.position)
            if touches.size() == 1 and start.distance_to(event.position) < 12.0:
                _pick_object(event.position)
            touches.erase(event.index)
            touch_starts.erase(event.index)
        accept_event()
    elif event is InputEventScreenDrag:
        if touches.has(event.index):
            var old_position: Vector2 = touches[event.index]
            touches[event.index] = event.position
            if touches.size() == 1:
                _orbit(event.position - old_position)
            elif touches.size() == 2:
                var indices: Array = touches.keys()
                var other_index: int = indices[0] if indices[1] == event.index else indices[1]
                var other_position: Vector2 = touches[other_index]
                var old_distance := old_position.distance_to(other_position)
                var new_distance: float = event.position.distance_to(other_position)
                if old_distance > 1.0 and new_distance > 1.0:
                    orbit_distance = clampf(orbit_distance * old_distance / new_distance, 2.0, 30.0)
                    _update_camera()
        accept_event()
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                mouse_start = event.position
            elif mouse_start.distance_to(event.position) < 8.0:
                _pick_object(event.position)
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            orbit_distance = maxf(2.0, orbit_distance * 0.9)
            _update_camera()
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            orbit_distance = minf(30.0, orbit_distance * 1.1)
            _update_camera()
            accept_event()
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        _orbit(event.relative)
        accept_event()

func _orbit(motion: Vector2) -> void:
    orbit_yaw -= motion.x * 0.008
    orbit_pitch = clampf(orbit_pitch + motion.y * 0.008, 0.08, 1.45)
    _update_camera()

func _pick_object(screen_position: Vector2) -> void:
    var origin := editor_camera.project_ray_origin(screen_position)
    var end := origin + editor_camera.project_ray_normal(screen_position) * 250.0
    var query := PhysicsRayQueryParameters3D.create(origin, end)
    var hit: Dictionary = preview.world_3d.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return
    var body: Object = hit.get("collider")
    if body != null and body.has_meta("movie_id"):
        _set_selection(str(body.get_meta("movie_id")))

func _add_object(kind: String) -> void:
    _set_playing(false)
    var id := str(next_id)
    next_id += 1
    var spawn := Vector3(float(objects_by_id.size()) * 1.5 - 0.8, 0.7, 0.0)
    var color: String = str(COLOR_SET[(next_id - 2) % COLOR_SET.size()])
    _create_object(id, kind, spawn, Vector3.ZERO, color)
    tracks[id] = [_capture_key(objects_by_id[id], 0.0)]
    _set_selection(id)
    _seek(current_time)
    _show_message("追加しました。位置を調整して◆で記録できます。")

func _create_object(id: String, kind: String, pos: Vector3, angles: Vector3, tint: String) -> void:
    var node := Node3D.new()
    node.name = ("球 " if kind == "sphere" else "箱 ") + id
    node.position = pos
    node.rotation_degrees = angles
    node.set_meta("movie_id", id)
    node.set_meta("kind", kind)
    node.set_meta("tint", tint)
    scene_root.add_child(node)

    var mesh := MeshInstance3D.new()
    var collision := CollisionShape3D.new()
    if kind == "sphere":
        var shape_mesh := SphereMesh.new()
        shape_mesh.radius = 0.6
        shape_mesh.height = 1.2
        mesh.mesh = shape_mesh
        var sphere_shape := SphereShape3D.new()
        sphere_shape.radius = 0.6
        collision.shape = sphere_shape
    else:
        var shape_mesh := BoxMesh.new()
        shape_mesh.size = Vector3.ONE
        mesh.mesh = shape_mesh
        var box_shape := BoxShape3D.new()
        box_shape.size = Vector3.ONE
        collision.shape = box_shape
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.from_string(tint, Color.WHITE)
    mesh.material_override = material
    node.add_child(mesh)
    var body := StaticBody3D.new()
    body.set_meta("movie_id", id)
    body.add_child(collision)
    node.add_child(body)
    objects_by_id[id] = node
    _refresh_selector()
    _refresh_timeline()

func _set_selection(id: String) -> void:
    if not objects_by_id.has(id):
        return
    selected_id = id
    for index in range(selection.item_count):
        if str(selection.get_item_metadata(index)) == id:
            selection.select(index)
            break
    _show_message("選択中: %s" % (objects_by_id[id] as Node3D).name)

func _on_selection_changed(index: int) -> void:
    _set_selection(str(selection.get_item_metadata(index)))

func _refresh_selector() -> void:
    if selection == null:
        return
    selection.clear()
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var node: Node3D = objects_by_id[id]
        selection.add_item(node.name)
        selection.set_item_metadata(selection.item_count - 1, id)
    if objects_by_id.has(selected_id):
        _set_selection(selected_id)
    elif selection.item_count > 0:
        _set_selection(str(selection.get_item_metadata(0)))

func _nudge(direction: float) -> void:
    if not objects_by_id.has(selected_id):
        _show_message("編集するモデルを選択してください")
        return
    _set_playing(false)
    var node: Node3D = objects_by_id[selected_id]
    var axis := axis_option.selected
    if mode_option.selected == 0:
        var pos := node.position
        pos[axis] += direction * 0.25
        node.position = pos
    else:
        var angles := node.rotation_degrees
        angles[axis] += direction * 10.0
        node.rotation_degrees = angles
    _show_message("姿勢を変更しました。◆で現在時刻に登録してください。")

func _capture_key(node: Node3D, at: float) -> Dictionary:
    return {
        "time": snappedf(at, 0.01),
        "position": [node.position.x, node.position.y, node.position.z],
        "rotation": [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z]
    }

func _insert_key() -> void:
    if not objects_by_id.has(selected_id):
        _show_message("モデルを選択してください")
        return
    _set_playing(false)
    var node: Node3D = objects_by_id[selected_id]
    var keys: Array = tracks.get(selected_id, [])
    var key := _capture_key(node, current_time)
    var replaced := false
    for index in range(keys.size()):
        if absf(float(keys[index].get("time", 0.0)) - current_time) < 0.03:
            keys[index] = key
            replaced = true
            break
    if not replaced:
        keys.append(key)
    keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    tracks[selected_id] = keys
    _refresh_timeline()
    _show_message("%.2f秒にキーフレームを%s" % [current_time, "更新" if replaced else "追加"])

func _on_key_dragged(id: String, index: int, new_time: float, finished: bool) -> void:
    if not tracks.has(id):
        return
    var keys: Array = tracks[id]
    if index < 0 or index >= keys.size():
        return
    _set_playing(false)
    var key: Dictionary = keys[index]
    key["time"] = snappedf(clampf(new_time, 0.0, DURATION), 0.01)
    keys[index] = key
    if finished:
        keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    _refresh_timeline()
    _seek(new_time)

func _seek(seconds: float) -> void:
    current_time = clampf(seconds, 0.0, DURATION)
    _sample_all()
    _update_clock()

func _sample_all() -> void:
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var keys: Array = tracks.get(id, [])
        if keys.is_empty():
            continue
        var first: Dictionary = keys[0]
        var last: Dictionary = keys[keys.size() - 1]
        var before: Dictionary = first
        var after: Dictionary = last
        if current_time <= float(first.get("time", 0.0)):
            after = first
        elif current_time >= float(last.get("time", 0.0)):
            before = last
        else:
            for index in range(keys.size() - 1):
                var a: Dictionary = keys[index]
                var b: Dictionary = keys[index + 1]
                if current_time >= float(a["time"]) and current_time <= float(b["time"]):
                    before = a
                    after = b
                    break
        var t0 := float(before.get("time", 0.0))
        var t1 := float(after.get("time", t0))
        var weight := 0.0 if absf(t1 - t0) < 0.0001 else clampf((current_time - t0) / (t1 - t0), 0.0, 1.0)
        var node: Node3D = objects_by_id[id]
        var start_pos := _array_to_vec(before.get("position", []))
        var end_pos := _array_to_vec(after.get("position", []))
        node.position = start_pos.lerp(end_pos, weight)
        var start_rot := _array_to_vec(before.get("rotation", []))
        var end_rot := _array_to_vec(after.get("rotation", []))
        node.rotation = Vector3(
            lerp_angle(deg_to_rad(start_rot.x), deg_to_rad(end_rot.x), weight),
            lerp_angle(deg_to_rad(start_rot.y), deg_to_rad(end_rot.y), weight),
            lerp_angle(deg_to_rad(start_rot.z), deg_to_rad(end_rot.z), weight))

func _array_to_vec(data: Variant) -> Vector3:
    if data is Array and data.size() >= 3:
        return Vector3(float(data[0]), float(data[1]), float(data[2]))
    return Vector3.ZERO

func _refresh_timeline() -> void:
    if timeline == null:
        return
    var rows: Array[Dictionary] = []
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var node: Node3D = objects_by_id[id]
        var times: Array = []
        for key in tracks.get(id, []):
            times.append(float(key.get("time", 0.0)))
        rows.append({"id": id, "label": node.name, "times": times})
    timeline.set_tracks(rows)

func _update_clock() -> void:
    clock_label.text = "%02d:%05.2f" % [int(current_time / 60.0), fmod(current_time, 60.0)]
    time_slider.set_value_no_signal(current_time)
    timeline.set_playhead(current_time)

func _set_playing(value: bool) -> void:
    playing = value
    play_button.text = "Ⅱ" if playing else "▶"

func _toggle_play() -> void:
    if not playing and current_time >= DURATION:
        _seek(0.0)
    _set_playing(not playing)

func _serialize_project() -> Dictionary:
    var records: Array[Dictionary] = []
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var node: Node3D = objects_by_id[id]
        records.append({
            "id": id,
            "kind": str(node.get_meta("kind", "box")),
            "tint": str(node.get_meta("tint", "#ffffff")),
            "keyframes": tracks.get(id, [])
        })
    return {"version": 1, "duration": DURATION, "objects": records}

func _save_project() -> void:
    _set_playing(false)
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _show_message("保存失敗: %s" % error_string(FileAccess.get_open_error()))
        return
    file.store_string(JSON.stringify(_serialize_project(), "\t"))
    file.close()
    _show_message("保存しました: movie_project.json")

func _load_project() -> void:
    _set_playing(false)
    if not FileAccess.file_exists(SAVE_PATH):
        _show_message("保存データがありません")
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        _show_message("読込に失敗しました")
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Dictionary) or int(parsed.get("version", -1)) != 1 or not (parsed.get("objects") is Array):
        _show_message("未対応のプロジェクト形式です")
        return
    for node in objects_by_id.values():
        (node as Node3D).queue_free()
    objects_by_id.clear()
    tracks.clear()
    selected_id = ""
    next_id = 1
    var records: Array = parsed["objects"]
    for record_value in records:
        if not (record_value is Dictionary):
            continue
        var record: Dictionary = record_value
        var id := str(record.get("id", next_id))
        if not id.is_valid_int() or objects_by_id.has(id):
            continue
        next_id = maxi(next_id, int(id) + 1)
        var kind := str(record.get("kind", "box"))
        if kind != "sphere":
            kind = "box"
        var raw_keys: Array = record.get("keyframes", [])
        var keys: Array = []
        for key_value in raw_keys:
            if key_value is Dictionary:
                var key: Dictionary = key_value
                if key.has("time") and key.has("position") and key.has("rotation"):
                    keys.append(key.duplicate(true))
        keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
        var pos := Vector3.ZERO
        var angles := Vector3.ZERO
        if not keys.is_empty():
            pos = _array_to_vec(keys[0]["position"])
            angles = _array_to_vec(keys[0]["rotation"])
        tracks[id] = keys
        _create_object(id, kind, pos, angles, str(record.get("tint", "#ffffff")))
    _refresh_selector()
    _refresh_timeline()
    _seek(0.0)
    _show_message("プロジェクトを読み込みました")

func _show_message(message: String) -> void:
    if status_label != null:
        status_label.text = message
