extends Control
## Movie Creator 0.1: a portrait-first cutscene blocking and keyframe editor.
## All editor state stays in this project; other game repositories are untouched.

const TimelineView = preload("res://scripts/timeline.gd")
const BBModelImporter = preload("res://scripts/bbmodel_importer.gd")
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
var selection: Button
var axis_option: Button
var mode_option: Button
var motion_button: Button
var bb_file_dialog: FileDialog
var bb_assets: Dictionary = {}
var picker_overlay: Control
var picker_list: VBoxContainer
var mode_index := 0
var axis_index := 0

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
# Android touch: touching a model edits it; touching empty space orbits the camera.
var touches: Dictionary = {}
var pointer_active := false
var pointer_touch_index := -1
var pointer_origin := Vector2.ZERO
var pointer_last := Vector2.ZERO
var drag_target_id := ""
var drag_moved := false
var drag_position_start := Vector3.ZERO
var drag_rotation_start := Vector3.ZERO
var drag_grab_point := Vector3.ZERO
var mouse_left_held := false

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
    _make_button(add_row, "BB読込", _choose_bbmodel)
    _make_button(add_row, "◆ キー登録", _insert_key)
    var motion_row := HBoxContainer.new()
    dock.add_child(motion_row)
    motion_button = _make_button(motion_row, "モーション：なし ▷", _cycle_bb_animation)
    motion_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    motion_button.tooltip_text = "読み込んだモデルのアニメーションを切り替え"


    var properties := HBoxContainer.new()
    dock.add_child(properties)
    selection = _make_button(properties, "モデル選択 ▾", _toggle_picker)
    selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mode_option = _make_button(properties, "移動 ↻", _cycle_mode)
    axis_option = _make_button(properties, "自由 ↻", _cycle_axis)

    var nudge_row := HBoxContainer.new()
    dock.add_child(nudge_row)
    _make_button(nudge_row, "－", func(): _nudge(-1.0))
    var nudge_hint := Label.new()
    nudge_hint.text = "モデルを直接ドラッグできます"
    nudge_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    nudge_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    nudge_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    nudge_row.add_child(nudge_hint)
    _make_button(nudge_row, "＋", func(): _nudge(1.0))

    status_label = Label.new()
    status_label.custom_minimum_size.y = 28
    status_label.add_theme_font_size_override("font_size", 12)
    dock.add_child(status_label)
    _build_picker()

func _choose_bbmodel() -> void:
    _set_playing(false)
    # Android native Storage Access Framework; FileAccess supports returned content:// URI.
    if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
        var err: Error = DisplayServer.file_dialog_show(
            "Blockbenchモデルを開く", "", "", false,
            DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
            PackedStringArray(["*.bbmodel,*.json;Blockbenchモデル;application/json,application/octet-stream"]),
            _on_native_bbmodel_chosen)
        if err == OK:
            return
    # Desktop/fallback when a native picker is unavailable.
    if bb_file_dialog == null:
        bb_file_dialog = FileDialog.new()
        bb_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
        bb_file_dialog.use_native_dialog = false
        bb_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        bb_file_dialog.add_filter("*.bbmodel,*.json", "Blockbenchモデル")
        bb_file_dialog.file_selected.connect(_import_bbmodel_path)
        add_child(bb_file_dialog)
    bb_file_dialog.popup_centered_ratio(0.9)

func _on_native_bbmodel_chosen(accepted: bool, selected: PackedStringArray, _filter: int) -> void:
    if accepted and not selected.is_empty():
        _import_bbmodel_path(selected[0])

func _import_bbmodel_path(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _show_message("BBファイルを開けません: %s" % error_string(FileAccess.get_open_error()))
        return
    if file.get_length() > 18000000:
        _show_message("BBファイルが18MBを超えています")
        file.close()
        return
    var source := file.get_as_text()
    file.close()
    _import_bbmodel_text(source, path.get_file().get_basename())

func _import_bbmodel_text(source: String, filename: String = "Blockbench") -> bool:
    var importer := BBModelImporter.new()
    var result: Dictionary = importer.import_text(source)
    if not bool(result.get("ok", false)):
        _show_message("BB読込エラー: %s" % str(result.get("error", "不明なエラー")))
        return false
    _set_playing(false)
    var id := str(next_id)
    next_id += 1
    var node: Node3D = result["root"]
    node.name = filename.validate_node_name()
    node.set_meta("movie_id", id)
    node.set_meta("kind", "bbmodel")
    node.set_meta("tint", "#ffffff")
    scene_root.add_child(node)
    objects_by_id[id] = node
    tracks[id] = [_capture_key(node, 0.0)]
    var clips: Array = result.get("animations", [])
    bb_assets[id] = {
        "source": source, "groups": result["groups"], "clips": clips,
        "clip_index": 0 if not clips.is_empty() else -1,
        "old_format": int(str(node.get_meta("bb_format", "5")).get_slice(".", 0)) < 5
    }
    _refresh_selector()
    _set_selection(id)
    _refresh_timeline()
    _seek(current_time)
    var notices: Array = result.get("warnings", [])
    var issue_info := (" / 注意: " + str(notices[0])) if not notices.is_empty() else ""
    _show_message("BB読込: %dキューブ・%dモーション%s" % [int(result["cubes"]), clips.size(), issue_info])
    return true

func _cycle_bb_animation() -> void:
    if not bb_assets.has(selected_id):
        _show_message("先にBBモデルを選択してください")
        return
    var asset: Dictionary = bb_assets[selected_id]
    var clips: Array = asset.get("clips", [])
    if clips.is_empty():
        _show_message("このモデルにモーションはありません")
        return
    asset["clip_index"] = (int(asset["clip_index"]) + 2) % (clips.size() + 1) - 1
    bb_assets[selected_id] = asset
    _refresh_motion_button()
    _sample_bb_animations()

func _refresh_motion_button() -> void:
    if motion_button == null:
        return
    motion_button.text = "モーション：なし ▷"
    if not bb_assets.has(selected_id):
        return
    var asset: Dictionary = bb_assets[selected_id]
    var clips: Array = asset.get("clips", [])
    var selected := int(asset.get("clip_index", -1))
    if selected >= 0 and selected < clips.size():
        motion_button.text = "モーション：%s ▷" % str(clips[selected].get("name", "Animation"))

func _sample_bb_animations() -> void:
    var sampler := BBModelImporter.new()
    for id_value in bb_assets.keys():
        var asset: Dictionary = bb_assets[id_value]
        var clips: Array = asset.get("clips", [])
        var index := int(asset.get("clip_index", -1))
        if index < 0 or index >= clips.size():
            sampler.apply_clip(asset["groups"], {}, 0.0, bool(asset["old_format"]))
            continue
        var clip: Dictionary = clips[index]
        var clip_length := maxf(0.01, float(clip.get("length", 0.01)))
        var anim_time := fposmod(current_time, clip_length) if str(clip.get("loop", "")) == "loop" else minf(current_time, clip_length)
        sampler.apply_clip(asset["groups"], clip, anim_time, bool(asset["old_format"]))

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
    if picker_overlay != null and picker_overlay.visible:
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index] = event.position
            if touches.size() == 1:
                pointer_touch_index = event.index
                _begin_pointer(event.position)
            else:
                # Moving from single-touch dragging to pinch commits the edited pose.
                _finish_pointer(pointer_last)
                pointer_touch_index = -1
        else:
            if touches.size() == 1 and pointer_touch_index == event.index:
                _finish_pointer(event.position)
            touches.erase(event.index)
            if touches.is_empty():
                pointer_touch_index = -1
        accept_event()
    elif event is InputEventScreenDrag:
        if touches.has(event.index):
            var old_position: Vector2 = touches[event.index]
            touches[event.index] = event.position
            if touches.size() == 1 and pointer_touch_index == event.index:
                _move_pointer(event.position)
            elif touches.size() == 2:
                _two_finger_camera(event.index, old_position, event.position)
        accept_event()
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                mouse_left_held = true
                _begin_pointer(event.position)
            elif mouse_left_held:
                _finish_pointer(event.position)
                mouse_left_held = false
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            orbit_distance = maxf(2.0, orbit_distance * 0.9)
            _update_camera()
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            orbit_distance = minf(30.0, orbit_distance * 1.1)
            _update_camera()
            accept_event()
    elif event is InputEventMouseMotion and mouse_left_held:
        _move_pointer(event.position)
        accept_event()

func _begin_pointer(at: Vector2) -> void:
    pointer_active = true
    pointer_origin = at
    pointer_last = at
    drag_moved = false
    drag_target_id = _hit_object_id(at)
    if not drag_target_id.is_empty():
        _set_playing(false)
        _set_selection(drag_target_id)
        var node: Node3D = objects_by_id[drag_target_id]
        drag_position_start = node.position
        drag_rotation_start = node.rotation_degrees
        drag_grab_point = _world_on_level(at, node.position.y, node.position)

func _move_pointer(at: Vector2) -> void:
    if not pointer_active:
        return
    var motion := at - pointer_last
    pointer_last = at
    if drag_target_id.is_empty():
        _orbit(motion)
        return
    if not drag_moved and at.distance_to(pointer_origin) < 9.0:
        return
    drag_moved = true
    _apply_model_drag(at)

func _finish_pointer(at: Vector2) -> void:
    if not pointer_active:
        return
    if drag_moved and not drag_target_id.is_empty():
        _apply_model_drag(at)
        # A completed direct manipulation always produces a persistent keyframe.
        _insert_key()
        _show_message("指で編集した姿勢を %.2f 秒に記録しました" % current_time)
    pointer_active = false
    drag_moved = false
    drag_target_id = ""

func _apply_model_drag(at: Vector2) -> void:
    if not objects_by_id.has(drag_target_id):
        return
    var node: Node3D = objects_by_id[drag_target_id]
    if mode_index == 1:
        # Drag horizontally to rotate. In 'free' mode, rotate about world Y.
        var axis: int = 1 if axis_index == 0 else axis_index - 1
        var angle := drag_rotation_start
        angle[axis] += (at.x - pointer_origin.x) * 0.55
        node.rotation_degrees = angle
        return

    var position := drag_position_start
    if axis_index == 2:
        # Vertical axis: drag upward to lift, with sensitivity based on camera distance.
        var height_scale: float = 2.0 * orbit_distance * tan(deg_to_rad(editor_camera.fov) * 0.5) / maxf(preview_box.size.y, 1.0)
        position.y += (pointer_origin.y - at.y) * height_scale
    else:
        # Ground-plane manipulation; preserve the initial finger-to-object offset.
        var hit := _world_on_level(at, drag_position_start.y, drag_grab_point)
        var offset: Vector3 = hit - drag_grab_point
        if axis_index == 0 or axis_index == 1:
            position.x += offset.x
        if axis_index == 0 or axis_index == 3:
            position.z += offset.z
    node.position = position

func _two_finger_camera(changed_index: int, old_position: Vector2, new_position: Vector2) -> void:
    var indices: Array = touches.keys()
    var other_index: int = indices[0] if indices[1] == changed_index else indices[1]
    var other_position: Vector2 = touches[other_index]
    var old_distance := old_position.distance_to(other_position)
    var new_distance := new_position.distance_to(other_position)
    if old_distance > 2.0 and new_distance > 2.0:
        orbit_distance = clampf(orbit_distance * old_distance / new_distance, 2.0, 30.0)

    # The midpoint follows two fingers: intuitive world-space camera panning.
    var midpoint_motion := (new_position - old_position) * 0.5
    var world_per_pixel: float = 2.0 * orbit_distance * tan(deg_to_rad(editor_camera.fov) * 0.5) / maxf(preview_box.size.y, 1.0)
    orbit_target += (editor_camera.global_transform.basis.x * -midpoint_motion.x + editor_camera.global_transform.basis.y * midpoint_motion.y) * world_per_pixel
    _update_camera()

func _orbit(motion: Vector2) -> void:
    orbit_yaw -= motion.x * 0.008
    orbit_pitch = clampf(orbit_pitch + motion.y * 0.008, 0.08, 1.45)
    _update_camera()

func _viewport_position(local: Vector2) -> Vector2:
    # SubViewportContainer stretches the render target to fit the Android UI.
    return local * Vector2(preview.size) / preview_box.size

func _world_on_level(local: Vector2, height: float, fallback: Vector3) -> Vector3:
    var screen_pos := _viewport_position(local)
    var origin := editor_camera.project_ray_origin(screen_pos)
    var direction := editor_camera.project_ray_normal(screen_pos)
    var world_hit: Variant = Plane(Vector3.UP, height).intersects_ray(origin, direction)
    if world_hit is Vector3:
        return world_hit
    return fallback

func _hit_object_id(local: Vector2) -> String:
    # Recursive mesh ray cast; supports imported nested cuboids.
    var screen_pos := _viewport_position(local)
    var ray_origin := editor_camera.project_ray_origin(screen_pos)
    var ray_dir := editor_camera.project_ray_normal(screen_pos)
    var closest_id := ""
    var closest_distance := INF
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var root_node: Node3D = objects_by_id[id]
        var stack: Array[Node] = [root_node]
        while not stack.is_empty():
            var item: Node = stack.pop_back()
            if item is MeshInstance3D and item.is_visible_in_tree() and item.name != "SelectionFrame":
                var mesh: MeshInstance3D = item
                if mesh.mesh != null:
                    var transform_inv := mesh.global_transform.affine_inverse()
                    var local_origin: Vector3 = transform_inv * ray_origin
                    var local_direction: Vector3 = transform_inv.basis * ray_dir
                    var intersection: Variant = mesh.get_aabb().intersects_ray(local_origin, local_direction)
                    if intersection is Vector3:
                        var world_hit: Vector3 = mesh.global_transform * (intersection as Vector3)
                        var distance: float = ray_origin.distance_to(world_hit)
                        if distance < closest_distance:
                            closest_distance = distance
                            closest_id = id
            for child in item.get_children():
                stack.append(child)
    return closest_id

func _pick_object(screen_position: Vector2) -> void:
    var id := _hit_object_id(screen_position)
    if not id.is_empty():
        _set_selection(id)

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
    mesh.name = "EditableMesh"
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
    _add_selection_frame(node, kind)
    objects_by_id[id] = node
    _refresh_selector()
    _refresh_timeline()

func _add_selection_frame(node: Node3D, kind: String) -> void:
    var extent: float = 0.68 if kind == "sphere" else 0.58
    var corners: Array[Vector3] = [
        Vector3(-extent, -extent, -extent), Vector3(extent, -extent, -extent),
        Vector3(extent, -extent, extent), Vector3(-extent, -extent, extent),
        Vector3(-extent, extent, -extent), Vector3(extent, extent, -extent),
        Vector3(extent, extent, extent), Vector3(-extent, extent, extent)
    ]
    var segments := [
        Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
        Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
        Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)
    ]
    var lines := ImmediateMesh.new()
    lines.surface_begin(Mesh.PRIMITIVE_LINES)
    for segment in segments:
        lines.surface_add_vertex(corners[segment.x])
        lines.surface_add_vertex(corners[segment.y])
    lines.surface_end()
    var frame := MeshInstance3D.new()
    frame.name = "SelectionFrame"
    frame.mesh = lines
    frame.visible = false
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color("#ffcb67")
    material.no_depth_test = true
    frame.material_override = material
    node.add_child(frame)

func _set_selection(id: String) -> void:
    if not objects_by_id.has(id):
        return
    selected_id = id
    selection.text = "%s ▾" % (objects_by_id[id] as Node3D).name
    for object_id in objects_by_id.keys():
        var object_node: Node3D = objects_by_id[object_id]
        var frame: Node3D = object_node.get_node_or_null("SelectionFrame")
        if frame != null:
            frame.visible = str(object_id) == selected_id
    _refresh_motion_button()
    _show_message("選択中: %s" % (objects_by_id[id] as Node3D).name)

func _refresh_selector() -> void:
    if selection == null:
        return
    if objects_by_id.has(selected_id):
        selection.text = "%s ▾" % (objects_by_id[selected_id] as Node3D).name
    elif not objects_by_id.is_empty():
        _set_selection(str(objects_by_id.keys()[0]))
    else:
        selection.text = "モデル選択 ▾"

func _cycle_mode() -> void:
    mode_index = (mode_index + 1) % 2
    mode_option.text = ("移動 ↻" if mode_index == 0 else "回転 ↻")

func _cycle_axis() -> void:
    axis_index = (axis_index + 1) % 4
    axis_option.text = ["自由 ↻", "X ↻", "Y ↻", "Z ↻"][axis_index]

func _build_picker() -> void:
    # A native OptionButton PopupMenu is hard to dismiss on Android.
    # This in-scene sheet has three explicit exit paths: choose, X, outside.
    picker_overlay = Control.new()
    picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(picker_overlay)

    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.04, 0.07, 0.75)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    picker_overlay.add_child(shade)

    var outside_button := Button.new()
    outside_button.flat = true
    outside_button.focus_mode = Control.FOCUS_NONE
    outside_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outside_button.pressed.connect(_close_picker)
    picker_overlay.add_child(outside_button)

    var sheet := PanelContainer.new()
    sheet.anchor_left = 0.0
    sheet.anchor_top = 0.45
    sheet.anchor_right = 1.0
    sheet.anchor_bottom = 1.0
    sheet.mouse_filter = Control.MOUSE_FILTER_STOP
    picker_overlay.add_child(sheet)

    var contents := VBoxContainer.new()
    contents.add_theme_constant_override("separation", 8)
    sheet.add_child(contents)

    var title_row := HBoxContainer.new()
    contents.add_child(title_row)
    var title := Label.new()
    title.text = "モデルを選択"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    title_row.add_child(title)
    _make_button(title_row, "✕ 閉じる", _close_picker)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    contents.add_child(scroll)
    picker_list = VBoxContainer.new()
    picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(picker_list)
    picker_overlay.hide()

func _toggle_picker() -> void:
    if picker_overlay.visible:
        _close_picker()
        return
    _refresh_picker_list()
    picker_overlay.show()

func _refresh_picker_list() -> void:
    for child in picker_list.get_children():
        picker_list.remove_child(child)
        child.queue_free()
    for id_value in objects_by_id.keys():
        var item_id := str(id_value)
        var button := Button.new()
        button.text = ("✓ " if item_id == selected_id else "　") + (objects_by_id[item_id] as Node3D).name
        button.custom_minimum_size.y = 56.0
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(_choose_model.bind(item_id))
        picker_list.add_child(button)

func _choose_model(id: String) -> void:
    _set_selection(id)
    _close_picker()

func _close_picker() -> void:
    if picker_overlay != null:
        picker_overlay.hide()

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if picker_overlay != null and picker_overlay.visible:
            _close_picker()
            get_viewport().set_input_as_handled()

func _nudge(direction: float) -> void:
    if not objects_by_id.has(selected_id):
        _show_message("編集するモデルを選択してください")
        return
    _set_playing(false)
    var node: Node3D = objects_by_id[selected_id]
    # '+'/'-' is a precise fallback for touch gestures.
    var axis: int = 0 if mode_index == 0 and axis_index == 0 else (1 if axis_index == 0 else axis_index - 1)
    if mode_index == 0:
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
    _sample_bb_animations()

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
            "keyframes": tracks.get(id, []),
            "bb_source": str(bb_assets[id]["source"]) if bb_assets.has(id) else "",
            "bb_clip_index": int(bb_assets[id]["clip_index"]) if bb_assets.has(id) else -1
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
    bb_assets.clear()
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
        if kind != "sphere" and kind != "bbmodel":
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
        if kind == "bbmodel":
            var source := str(record.get("bb_source", ""))
            var importer := BBModelImporter.new()
            var bb_result: Dictionary = importer.import_text(source)
            if not bool(bb_result.get("ok", false)):
                _show_message("保存したBBモデルの復元に失敗しました")
                tracks.erase(id)
                continue
            var model: Node3D = bb_result["root"]
            model.position = pos
            model.rotation_degrees = angles
            model.set_meta("movie_id", id)
            model.set_meta("kind", "bbmodel")
            model.set_meta("tint", "#ffffff")
            scene_root.add_child(model)
            objects_by_id[id] = model
            var clips: Array = bb_result.get("animations", [])
            bb_assets[id] = {
                "source": source, "groups": bb_result["groups"], "clips": clips,
                "clip_index": clampi(int(record.get("bb_clip_index", -1)), -1, clips.size() - 1),
                "old_format": int(str(model.get_meta("bb_format", "5")).get_slice(".", 0)) < 5
            }
        else:
            _create_object(id, kind, pos, angles, str(record.get("tint", "#ffffff")))
    _refresh_selector()
    _refresh_timeline()
    _seek(0.0)
    _show_message("プロジェクトを読み込みました")

func _show_message(message: String) -> void:
    if status_label != null:
        status_label.text = message
