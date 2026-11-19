extends Control
## Movie Creator 0.1: a portrait-first cutscene blocking and keyframe editor.
## All editor state stays in this project; other game repositories are untouched.

const TimelineView = preload("res://scripts/timeline.gd")
const BBModelImporter = preload("res://scripts/bbmodel_importer.gd")
const ClipEngine = preload("res://scripts/clip_engine.gd")
const TransformGizmo = preload("res://scripts/transform_gizmo.gd")
const PoseTrack = preload("res://scripts/pose_track.gd")
const CameraCuts = preload("res://scripts/camera_cuts.gd")
const SAVE_PATH := "user://movie_project.json"
const BACKUP_PATH := "user://movie_project.backup.json"
const TEMP_PATH := "user://movie_project.tmp.json"
var DURATION := 15.0
const COLOR_SET := ["#58b6e8", "#d991e8", "#edb565", "#83d59e", "#e9919c"]

var scene_root: Node3D
var preview: SubViewport
var preview_box: SubViewportContainer
var preview_panel: Control
var part_label: Label
var part_picker_button: Button
var transform_overlay: Control
var transform_field_controls: Dictionary = {}
var transform_title: Label
var transform_buttons: Array[Button] = []
var gizmo: Node3D
var editor_camera: Camera3D
var shot_camera: Camera3D
var camera_marker: MeshInstance3D
var camera_keys: Array = []
# Camera 1 remains camera_keys for compatibility with v1-v4 files.
var camera_tracks: Dictionary = {}
var camera_cuts: Array = []
var next_camera_id := 2
var next_cut_id := 1
var camera_menu: PopupPanel
var shot_preview := false
# An editing viewpoint is preserved independently of the timeline's shot camera.
var edit_view_snapshot: Dictionary = {}
var clip_tracks: Dictionary = {}
var next_clip_id := 1
var timeline_scroll: ScrollContainer
var camera_view_button: Button
var timeline: Control
var clock_label: Label
var status_label: Label
var play_button: Button
var time_slider: HSlider
var selection: Button
var axis_option: Button
var mode_option: Button
var motion_button: Button
var pose_record_button: Button
var pose_record_mode := false
# model_id -> (relative NodePath -> timeline pose keys)
var part_pose_tracks: Dictionary = {}
var bb_file_dialog: FileDialog
var project_file_dialog: FileDialog
var file_menu: PopupPanel
var confirm_new: ConfirmationDialog
var confirm_delete: ConfirmationDialog
var duration_dialog: ConfirmationDialog
var duration_input: SpinBox
var autosave_timer: Timer
var is_project_loading := false
var tl_zoom_buttons: Array[Button] = []
var tl_zoom_label: Label
# A single compact, two-row action panel is visible at a time on phones.
var category_pages: Dictionary = {}
var category_buttons: Dictionary = {}
var active_category := "モデル"
var motion_workspace := false
var workspace_button: Button
var bb_assets: Dictionary = {}
var picker_overlay: Control
var picker_list: VBoxContainer
var picker_title: Label
var picker_mode := "model"
var clip_overlay: Control
var clip_title: Label
var clip_fields: Dictionary = {}
var clip_bone_list: VBoxContainer
var clip_scope_controls: VBoxContainer
var clip_limit_check: CheckBox
var clip_loop_check: CheckBox
var editing_clip_model := ""
var editing_clip_uid := ""
var mode_index := 0
var axis_index := 0
# Sub-element edits are additive to Blockbench animation (the original
# .bbmodel and its keyframes remain unchanged).
var selected_part_path := ""
var selected_part_model := ""
var last_hit_part_path := ""
var element_offsets: Dictionary = {}
var static_element_rest: Dictionary = {}
var drag_part_path := ""
var drag_target_node: Node3D
var drag_initial_scale := Vector3.ONE
var drag_existing_offset: Dictionary = {}
var drag_handle_axis := 0
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

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
        _show_message("BBModelを読み込むと編集を開始できます")
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
    layout.clip_contents = true
    add_child(layout)

    var header := HBoxContainer.new()
    header.custom_minimum_size.y = 54
    layout.add_child(header)
    var app_title := Label.new()
    app_title.text = "MOVIE"
    app_title.add_theme_font_size_override("font_size", 19)
    app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    app_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    header.add_child(app_title)
    _make_button(header, "↶", _undo_part_edit).tooltip_text = "関節編集のみ取り消し"
    _make_button(header, "↷", _redo_part_edit).tooltip_text = "関節編集のみやり直し"
    workspace_button = _make_button(header, "詳細編集", _toggle_workspace)
    workspace_button.tooltip_text = "基本編集と関節・キーフレームの詳細編集を切り替え"
    _make_button(header, "ファイル", _open_file_menu)

    preview_panel = Control.new()
    preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview_panel.custom_minimum_size = Vector2(0, 180)
    layout.add_child(preview_panel)
    preview_box = SubViewportContainer.new()
    preview_box.stretch = true
    preview_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    preview_box.mouse_filter = Control.MOUSE_FILTER_STOP
    preview_panel.add_child(preview_box)
    preview_box.gui_input.connect(_on_preview_input)

    preview = SubViewport.new()
    preview.size = Vector2i(432, 520)
    preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    preview.own_world_3d = true
    preview_box.add_child(preview)

    # Primary view switch is always reachable in the top-right of the preview,
    # independent of the currently selected editing category.
    camera_view_button = _make_button(preview_panel, "カメラ視点", _toggle_camera_view)
    camera_view_button.name = "PreviewCameraToggle"
    camera_view_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    camera_view_button.offset_left = -133.0
    camera_view_button.offset_right = -8.0
    camera_view_button.offset_top = 8.0
    camera_view_button.offset_bottom = 56.0
    camera_view_button.custom_minimum_size = Vector2(125, 48)
    camera_view_button.tooltip_text = "カメラ視点へ切り替え"
    camera_view_button.focus_mode = Control.FOCUS_NONE

    # Always-on modeling tools in the lower-right corner of the 3D preview.
    var overlay_row := HBoxContainer.new()
    overlay_row.anchor_left = 1.0
    overlay_row.anchor_right = 1.0
    overlay_row.anchor_top = 1.0
    overlay_row.anchor_bottom = 1.0
    overlay_row.offset_left = -232.0
    overlay_row.offset_right = -7.0
    overlay_row.offset_top = -53.0
    overlay_row.offset_bottom = -5.0
    overlay_row.add_theme_constant_override("separation", 3)
    preview_panel.add_child(overlay_row)
    for tool in [
        {"text": "選択", "mode": 3},
        {"text": "移動", "mode": 0},
        {"text": "回転", "mode": 1},
        {"text": "拡縮", "mode": 2}
    ]:
        var mode_button := _make_button(overlay_row, str(tool["text"]), _set_transform_mode.bind(int(tool["mode"])))
        mode_button.custom_minimum_size = Vector2(51, 46)
        mode_button.clip_text = true
        mode_button.focus_mode = Control.FOCUS_NONE
        transform_buttons.append(mode_button)
        if int(tool["mode"]) == 0:
            mode_option = mode_button
    part_label = Label.new()
    # The name has its own upper-left lane, never sharing the right toolbar.
    part_label.anchor_top = 0.0
    part_label.anchor_bottom = 0.0
    part_label.anchor_left = 0.0
    part_label.anchor_right = 0.0
    part_label.offset_left = 8.0
    part_label.offset_right = 171.0
    part_label.offset_top = 7.0
    part_label.offset_bottom = 48.0
    part_label.clip_text = true
    part_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    part_label.add_theme_font_size_override("font_size", 12)
    preview_panel.add_child(part_label)
    _set_transform_mode(0)

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
    _make_button(playback, "－", func(): _change_timeline_zoom(-1))
    _make_button(playback, "＋", func(): _change_timeline_zoom(1))

    timeline_scroll = ScrollContainer.new()
    timeline_scroll.custom_minimum_size = Vector2(0, 140)
    timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    dock.add_child(timeline_scroll)
    timeline = TimelineView.new()
    timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_scroll.add_child(timeline)
    timeline.seek_requested.connect(_seek)
    timeline.key_dragged.connect(_on_key_dragged)
    timeline.clip_tapped.connect(_timeline_bar_tapped)
    timeline.clip_dragged.connect(_timeline_bar_dragged)
    timeline.loop_end_dragged.connect(_on_loop_end_dragged)
    timeline.vertical_pan_requested.connect(_timeline_vertical_pan)

    # Four bounded categories replace five permanently stacked toolbar rows.
    # Buttons remain 48px high; only one page consumes vertical space.
    var category_nav := HBoxContainer.new()
    category_nav.add_theme_constant_override("separation", 4)
    dock.add_child(category_nav)
    var category_stack := VBoxContainer.new()
    category_stack.name = "CategoryContent"
    category_stack.custom_minimum_size = Vector2(0, 100)
    category_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    category_stack.add_theme_constant_override("separation", 0)
    dock.add_child(category_stack)
    for category in ["モデル", "変形", "アニメ", "カメラ"]:
        var nav_button := _make_button(category_nav, category, _select_category.bind(category))
        nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        nav_button.custom_minimum_size = Vector2(0, 48)
        nav_button.toggle_mode = true
        nav_button.focus_mode = Control.FOCUS_NONE
        category_buttons[category] = nav_button
        var page := VBoxContainer.new()
        page.name = category
        page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        page.add_theme_constant_override("separation", 4)
        category_stack.add_child(page)
        category_pages[category] = page

    # Model page only imports external assets: no placeholder shapes or
    # generic add-object buttons.
    var model_page: VBoxContainer = category_pages["モデル"]
    var properties := _category_row(model_page)
    _category_action(properties, "BB読込", _choose_bbmodel)
    selection = _category_action(properties, "モデル選択 ▾", _toggle_picker)
    selection.custom_minimum_size.x = 98
    part_picker_button = _category_action(properties, "階層", _open_part_picker)
    part_picker_button.custom_minimum_size.x = 64
    axis_option = _category_action(properties, "自由", _cycle_axis)
    axis_option.custom_minimum_size.x = 74

    # Transform: position/rotation/scale tools stay overlaid on the preview.
    # The numeric and keyframe actions live together in this category.
    var transform_page: VBoxContainer = category_pages["変形"]
    var nudge_row := _category_row(transform_page)
    for action in [
        {"text":"－", "call":func(): _nudge(-1.0)},
        {"text":"＋", "call":func(): _nudge(1.0)},
        {"text":"注視", "call":_focus_selected},
        {"text":"戻す", "call":_reset_selected_transform},
        {"text":"数値", "call":_open_transform_inspector}
    ]:
        _category_action(nudge_row, str(action["text"]), action["call"])
    var key_row := _category_row(transform_page)
    _category_action(key_row, "◆ キー登録", _insert_key)
    var key_hint := Label.new()
    key_hint.text = "現在の変形をタイムラインに記録"
    key_hint.clip_text = true
    key_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    key_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    key_hint.add_theme_font_size_override("font_size", 12)
    key_row.add_child(key_hint)

    # Animation: clips and partial-joint pose capture.
    var animation_page: VBoxContainer = category_pages["アニメ"]
    var motion_row := _category_row(animation_page)
    motion_button = _category_action(motion_row, "＋アニメ配置", _open_motion_picker)
    motion_button.tooltip_text = "読み込んだモデルのアニメーションをタイムラインに追加"
    pose_record_button = _category_action(motion_row, "◆ポーズOFF", _toggle_pose_record)
    pose_record_button.tooltip_text = "ON: 選択関節の操作を現在時刻にキーフレーム記録"
    var animation_hint := Label.new()
    animation_hint.text = "バーをタップして再生範囲・使用関節を編集"
    animation_hint.clip_text = true
    animation_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    animation_hint.custom_minimum_size.y = 48
    animation_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    animation_hint.add_theme_font_size_override("font_size", 12)
    animation_page.add_child(animation_hint)

    # Camera settings stay in their category; view switching lives in preview.
    var camera_page: VBoxContainer = category_pages["カメラ"]
    var camera_row := _category_row(camera_page)
    _category_action(camera_row, "視点→撮影", _copy_editor_to_shot)
    _category_action(camera_row, "カメラ◆", _insert_camera_key)
    _category_action(camera_row, "カット編集", _open_camera_menu)
    _select_category("モデル")
    _refresh_workspace()

    status_label = Label.new()
    status_label.custom_minimum_size = Vector2(0, 24)
    status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status_label.clip_text = true
    status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    status_label.add_theme_font_size_override("font_size", 12)
    dock.add_child(status_label)
    _build_picker()
    _build_clip_editor()
    _build_transform_inspector()
    _build_file_menu()
    _build_camera_menu()
    autosave_timer = Timer.new()
    autosave_timer.one_shot = true
    autosave_timer.wait_time = 20.0
    autosave_timer.timeout.connect(_autosave_project)
    add_child(autosave_timer)

func _category_row(page: Control) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 4)
    page.add_child(row)
    return row

func _category_action(row: Control, title: String, action: Callable) -> Button:
    var button := _make_button(row, title, action)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.custom_minimum_size = Vector2(0, 48)
    button.clip_text = true
    button.focus_mode = Control.FOCUS_NONE
    return button

func _select_category(category: String) -> void:
    if not category_pages.has(category):
        return
    active_category = category
    for key in category_pages:
        (category_pages[key] as Control).visible = key == category
        (category_buttons[key] as Button).set_pressed_no_signal(key == category)

func _toggle_workspace() -> void:
    motion_workspace = not motion_workspace
    if not motion_workspace and pose_record_mode:
        _toggle_pose_record()
    _refresh_workspace()
    _select_category("変形" if motion_workspace else "モデル")
    _show_message("モーション編集: 関節とキーを編集できます" if motion_workspace else "基本編集: 配置・モーション再生・撮影")

func _refresh_workspace() -> void:
    if workspace_button != null:
        workspace_button.text = "基本画面へ" if motion_workspace else "詳細編集"
    if category_buttons.has("変形"):
        (category_buttons["変形"] as Control).visible = motion_workspace
    if pose_record_button != null:
        pose_record_button.visible = motion_workspace

func _change_timeline_zoom(direction: int) -> void:
    if timeline == null:
        return
    var target_zoom: float = timeline.zoom * (1.65 if direction > 0 else 1.0 / 1.65)
    timeline.zoom_to(target_zoom, current_time)
    _show_message("TL拡大: %.1f倍" % timeline.zoom)

func _timeline_vertical_pan(pixels: float) -> void:
    if timeline_scroll == null:
        return
    # Imported/changed tracks may enlarge the timeline before Container's
    # deferred sort has updated its scrollbar. Keep immediate touch scrolling
    # responsive by synchronizing the range with the visible viewport.
    var scroll_bar := timeline_scroll.get_v_scroll_bar()
    if timeline != null and timeline.custom_minimum_size.y > timeline_scroll.size.y:
        scroll_bar.max_value = maxf(scroll_bar.max_value, timeline.custom_minimum_size.y)
        scroll_bar.page = maxf(1.0, timeline_scroll.size.y)
    timeline_scroll.scroll_vertical = maxi(0, timeline_scroll.scroll_vertical + roundi(pixels))

func _build_file_menu() -> void:
    file_menu = PopupPanel.new()
    add_child(file_menu)
    var choices := VBoxContainer.new()
    choices.custom_minimum_size = Vector2(260, 0)
    choices.add_theme_constant_override("separation", 6)
    file_menu.add_child(choices)
    for entry in [
        {"title":"💾 保存", "action":_save_project},
        {"title":"📂 保存済みを開く", "action":_load_project},
        {"title":"⬆ プロジェクトを書き出す", "action":_choose_project_export},
        {"title":"🎮 Godot再生データ出力", "action":_choose_runtime_export},
        {"title":"⬇ プロジェクトを読み込む", "action":_choose_project_import},
        {"title":"⏱ ムービーの長さ", "action":_show_duration_dialog},
        {"title":"＋ 新しいムービー", "action":_confirm_new_project},
        {"title":"🗑 選択モデルを削除", "action":_confirm_delete_model}
    ]:
        var action: Callable = entry["action"]
        var button := _make_button(choices, str(entry["title"]), func():
            file_menu.hide()
            action.call())
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.custom_minimum_size.y = 52
    confirm_new = ConfirmationDialog.new()
    confirm_new.title = "新しいムービーを作成"
    confirm_new.dialog_text = "現在の編集内容を保存して、新しい空のムービーを作成しますか？"
    confirm_new.confirmed.connect(_new_project)
    add_child(confirm_new)
    confirm_delete = ConfirmationDialog.new()
    confirm_delete.title = "モデルを削除"
    confirm_delete.dialog_text = "選択中のモデルを削除します。続けますか？"
    confirm_delete.confirmed.connect(_delete_selected_model)
    add_child(confirm_delete)
    duration_dialog = ConfirmationDialog.new()
    duration_dialog.title = "ムービーの長さ（秒）"
    duration_dialog.dialog_text = "時間軸の長さを設定してください（1～600秒）。"
    duration_input = SpinBox.new()
    duration_input.min_value = 1.0
    duration_input.max_value = 600.0
    duration_input.step = 1.0
    duration_input.custom_minimum_size = Vector2(230, 48)
    duration_dialog.add_child(duration_input)
    duration_dialog.confirmed.connect(func(): _set_project_duration(duration_input.value))
    add_child(duration_dialog)

func _open_file_menu() -> void:
    file_menu.popup_centered(Vector2i(290, 364))

func _show_duration_dialog() -> void:
    duration_input.set_value_no_signal(DURATION)
    duration_dialog.popup_centered(Vector2i(310, 200))

func _set_project_duration(seconds: float) -> void:
    DURATION = clampf(seconds, 1.0, 600.0)
    time_slider.max_value = DURATION
    timeline.duration = DURATION
    timeline.zoom_to(timeline.zoom, minf(current_time, DURATION))
    _seek(minf(current_time, DURATION))
    _mark_dirty()
    _show_message("尺を%.0f秒に変更しました" % DURATION)

func _confirm_new_project() -> void:
    confirm_new.popup_centered()

func _confirm_delete_model() -> void:
    if not objects_by_id.has(selected_id):
        _show_message("削除するモデルを選択してください")
        return
    confirm_delete.dialog_text = "「%s」を削除しますか？" % _model_title(selected_id)
    confirm_delete.popup_centered()

func _new_project() -> void:
    _set_playing(false)
    _autosave_project()
    for node in objects_by_id.values():
        (node as Node3D).queue_free()
    objects_by_id.clear()
    tracks.clear()
    bb_assets.clear()
    clip_tracks.clear()
    camera_tracks.clear()
    camera_cuts.clear()
    next_camera_id = 2
    next_cut_id = 1
    element_offsets.clear()
    static_element_rest.clear()
    part_pose_tracks.clear()
    undo_stack.clear()
    redo_stack.clear()
    next_id = 1
    next_clip_id = 1
    DURATION = 15.0
    timeline.zoom = 1.0
    timeline.view_start = 0.0
    time_slider.max_value = DURATION
    timeline.duration = DURATION
    selected_id = ""
    selected_part_path = ""
    selected_part_model = ""
    current_time = 0.0
    camera_keys = [_capture_camera_key(0.0)]
    _refresh_selector()
    _refresh_timeline()
    _seek(0.0)
    _mark_dirty()
    _show_message("新しいムービーを作成しました")

func _delete_selected_model() -> void:
    if not objects_by_id.has(selected_id):
        return
    _set_playing(false)
    _autosave_project()
    var id := selected_id
    var node: Node3D = objects_by_id[id]
    objects_by_id.erase(id)
    tracks.erase(id)
    bb_assets.erase(id)
    clip_tracks.erase(id)
    element_offsets.erase(id)
    static_element_rest.erase(id)
    part_pose_tracks.erase(id)
    node.queue_free()
    selected_id = ""
    selected_part_path = ""
    selected_part_model = ""
    undo_stack.clear()
    redo_stack.clear()
    _refresh_selector()
    _refresh_timeline()
    _seek(current_time)
    _mark_dirty()
    _show_message("モデルを削除しました。バックアップから復元できます")

func _mark_dirty() -> void:
    if not is_project_loading and autosave_timer != null:
        autosave_timer.start()

func _valid_project_json(source: String) -> bool:
    return MovieProjectStorage.valid_source(source)

func _write_project_text(source: String) -> bool:
    return MovieProjectStorage.write_safe(source, SAVE_PATH, BACKUP_PATH, TEMP_PATH)

func _autosave_project() -> void:
    if is_project_loading:
        return
    if autosave_timer != null:
        autosave_timer.stop()
    if not _write_project_text(JSON.stringify(_serialize_project(), "\t")):
        _show_message("自動保存できません。空き容量を確認してください")

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
        if autosave_timer != null and not autosave_timer.is_stopped():
            _autosave_project()

func _serialize_runtime_data() -> Dictionary:
    # The game resolves models by ID. Blockbench source data is deliberately
    # omitted so runtime JSON is compact; models are supplied by Godot scenes.
    var scene_data := _serialize_project()
    var export_objects: Array = []
    for entry in scene_data.get("objects", []):
        var row: Dictionary = entry.duplicate(true)
        row.erase("bb_source")
        var model_id := str(entry.get("id", ""))
        # Keep the portable export small but preserve the Blockbench identity
        # needed to play matching Godot animations and mask individual joints.
        if bb_assets.has(model_id):
            var asset: Dictionary = bb_assets[model_id]
            var animation_names: Array = []
            for animation_value in asset.get("clips", []):
                if animation_value is Dictionary:
                    animation_names.append(str(animation_value.get("name", "")))
            row["animation_names"] = animation_names
            var group_paths: Dictionary = {}
            var model: Node3D = objects_by_id.get(model_id) as Node3D
            if model != null:
                for uuid_value in (asset.get("groups", {}) as Dictionary).keys():
                    var group: Dictionary = asset["groups"][uuid_value]
                    var part: Node3D = group.get("node") as Node3D
                    if part != null and model.is_ancestor_of(part):
                        group_paths[str(uuid_value)] = str(model.get_path_to(part))
            row["group_paths"] = group_paths
        export_objects.append(row)
    scene_data["objects"] = export_objects
    scene_data.erase("version")
    scene_data["schema"] = "movie_creator_runtime_v1"
    scene_data["source_version"] = 6
    return scene_data

func _choose_runtime_export() -> void:
    _set_playing(false)
    if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
        var err: Error = DisplayServer.file_dialog_show(
            "Godotムービーデータを書き出す", "", "cutscene.movie.json", false,
            DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
            PackedStringArray(["*.json;Movie Creator runtime;application/json"]),
            _on_runtime_export_chosen)
        if err == OK:
            return
    var picker := FileDialog.new()
    picker.access = FileDialog.ACCESS_FILESYSTEM
    picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    picker.add_filter("*.json", "Godotムービー再生データ")
    picker.file_selected.connect(_export_runtime_path)
    add_child(picker)
    picker.popup_centered_ratio(0.9)

func _on_runtime_export_chosen(accepted: bool, selected: PackedStringArray, _filter: int) -> void:
    if accepted and not selected.is_empty():
        _export_runtime_path(selected[0])

func _export_runtime_path(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _show_message("Godot再生データを書き出せません")
        return false
    file.store_string(JSON.stringify(_serialize_runtime_data(), "\t"))
    file.close()
    _show_message("Godotムービー再生データを書き出しました")
    return true

func _choose_project_export() -> void:
    _set_playing(false)
    if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
        var err: Error = DisplayServer.file_dialog_show(
            "ムービーを書き出す", "", "movie_project.json", false,
            DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
            PackedStringArray(["*.json;Movie Creatorプロジェクト;application/json"]),
            _on_export_project_chosen)
        if err == OK:
            return
    _open_project_fallback(true)

func _on_export_project_chosen(accepted: bool, selected: PackedStringArray, _filter: int) -> void:
    if accepted and not selected.is_empty():
        _export_project_path(selected[0])

func _export_project_path(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _show_message("書き出し先へ保存できません")
        return false
    file.store_string(JSON.stringify(_serialize_project(), "\t"))
    file.close()
    _show_message("プロジェクトを書き出しました")
    return true

func _choose_project_import() -> void:
    _set_playing(false)
    if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
        var err: Error = DisplayServer.file_dialog_show(
            "ムービーを読み込む", "", "", false,
            DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
            PackedStringArray(["*.json;Movie Creatorプロジェクト;application/json"]),
            _on_import_project_chosen)
        if err == OK:
            return
    _open_project_fallback(false)

func _on_import_project_chosen(accepted: bool, selected: PackedStringArray, _filter: int) -> void:
    if accepted and not selected.is_empty():
        _import_project_path(selected[0])

func _import_project_path(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _show_message("選択したファイルを開けません")
        return false
    if file.get_length() > 60000000:
        file.close()
        _show_message("プロジェクトが60MBを超えています")
        return false
    var source := file.get_as_text()
    file.close()
    if not _valid_project_json(source):
        _show_message("対応しないプロジェクト形式です")
        return false
    _autosave_project()
    if not _write_project_text(source):
        _show_message("プロジェクトを安全に保存できません")
        return false
    _load_project()
    return true

func _open_project_fallback(exporting: bool) -> void:
    if project_file_dialog != null:
        project_file_dialog.queue_free()
    project_file_dialog = FileDialog.new()
    project_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    project_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
    project_file_dialog.add_filter("*.json", "Movie Creatorプロジェクト")
    if exporting:
        project_file_dialog.file_selected.connect(_export_project_path)
    else:
        project_file_dialog.file_selected.connect(_import_project_path)
    add_child(project_file_dialog)
    project_file_dialog.popup_centered_ratio(0.9)

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
    # Android SAF returns a content:// URI, not a human-readable filename.
    # Prefer the name embedded in the Blockbench JSON.
    _import_bbmodel_text(source, "BBモデル")

func _safe_model_name(project_name: String, fallback: String, id: String) -> String:
    var candidate := project_name.strip_edges()
    if candidate.is_empty():
        candidate = fallback.strip_edges()
    if candidate.begins_with("content:") or candidate.contains("%2F") or candidate.contains("_2F") or candidate.length() > 48:
        candidate = "BBモデル " + id
    candidate = candidate.validate_node_name()
    if candidate.is_empty():
        candidate = "BBモデル " + id
    return candidate.substr(0, 24)

func _short_text(value: String, max_chars: int) -> String:
    if value.length() <= max_chars:
        return value
    return value.substr(0, maxi(1, max_chars - 1)) + "…"

func _model_title(id: String) -> String:
    if not objects_by_id.has(id):
        return "モデル"
    var node: Node3D = objects_by_id[id]
    return _short_text(node.name, 13)

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
    node.name = _safe_model_name(str(result.get("model_name", "")), filename, id)
    node.set_meta("movie_id", id)
    node.set_meta("kind", "bbmodel")
    node.set_meta("tint", "#ffffff")
    scene_root.add_child(node)
    _add_bbmodel_selection_frame(node)
    objects_by_id[id] = node
    tracks[id] = [_capture_key(node, 0.0)]
    var clips: Array = result.get("animations", [])
    bb_assets[id] = {
        "source": source, "groups": result["groups"], "clips": clips,
        "clip_index": 0 if not clips.is_empty() else -1,
        "old_format": int(str(node.get_meta("bb_format", "5")).get_slice(".", 0)) < 5
    }
    _capture_static_element_rest(id)
    _refresh_selector()
    _set_selection(id)
    var imported_clips: Array = result.get("animations", [])
    if not imported_clips.is_empty():
        _add_animation_clip(id, 0, 0.0)
    _refresh_timeline()
    _seek(current_time)
    # Animate first, then frame the *actual displayed* pose (not rest pose).
    _focus_bbmodel(node)
    var notices: Array = result.get("warnings", [])
    var issue_info := " / 注意あり" if not notices.is_empty() else ""
    _show_message("BB読込: %s｜%dメッシュ・%dモーション%s" % [_model_title(id), int(result.get("meshes", 0)), clips.size(), issue_info])
    _mark_dirty()
    return true

func _bbmodel_bounds(node: Node3D) -> AABB:
    # Combined world AABB from every mesh, excluding an existing selection frame.
    var low := Vector3(1e12, 1e12, 1e12)
    var high := Vector3(-1e12, -1e12, -1e12)
    var found := false
    var stack: Array[Node] = [node]
    while not stack.is_empty():
        var item: Node = stack.pop_back()
        if item is MeshInstance3D and item.name != "SelectionFrame":
            var model_mesh: MeshInstance3D = item
            if model_mesh.mesh != null:
                for i in range(8):
                    var point := model_mesh.global_transform * model_mesh.get_aabb().get_endpoint(i)
                    low = low.min(point)
                    high = high.max(point)
                    found = true
        for child in item.get_children():
            stack.append(child)
    if not found:
        return AABB(Vector3.ZERO, Vector3.ZERO)
    return AABB(low, high - low)

func _add_bbmodel_selection_frame(model: Node3D) -> void:
    var bounds := _bbmodel_bounds(model)
    if bounds.size.length_squared() < 0.00001:
        return
    var margin := maxf(0.03, bounds.size.length() * 0.02)
    bounds = bounds.grow(margin)
    var points: Array[Vector3] = []
    for i in range(8):
        points.append(model.to_local(bounds.get_endpoint(i)))
    var edges := [
        Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 4),
        Vector2i(1, 3), Vector2i(1, 5), Vector2i(2, 3),
        Vector2i(2, 6), Vector2i(3, 7), Vector2i(4, 5),
        Vector2i(4, 6), Vector2i(5, 7), Vector2i(6, 7)
    ]
    var lines := ImmediateMesh.new()
    lines.surface_begin(Mesh.PRIMITIVE_LINES)
    for edge in edges:
        lines.surface_add_vertex(points[edge.x])
        lines.surface_add_vertex(points[edge.y])
    lines.surface_end()
    var border := MeshInstance3D.new()
    border.name = "SelectionFrame"
    border.mesh = lines
    border.visible = false
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#ffcc70")
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.no_depth_test = true
    border.material_override = material
    model.add_child(border)

func _focus_bbmodel(model: Node3D) -> void:
    var bounds := _bbmodel_bounds(model)
    if bounds.size.length_squared() < 0.00001:
        return
    orbit_target = bounds.get_center()
    var radius := maxf(bounds.size.length() * 0.5, 0.3)
    var aspect := maxf(preview_box.size.x / maxf(preview_box.size.y, 1.0), 0.3)
    var half_vertical_fov := deg_to_rad(editor_camera.fov) * 0.5
    var half_horizontal_fov := atan(tan(half_vertical_fov) * aspect)
    orbit_distance = clampf(radius / sin(minf(half_vertical_fov, half_horizontal_fov)) * 1.35, 2.5, 80.0)
    _update_camera()

func _focus_selected() -> void:
    if selected_id == "__camera__":
        orbit_target = shot_camera.global_position
        orbit_distance = 4.0
        _update_camera()
        _show_message("撮影カメラへ注視しました")
        return
    if not objects_by_id.has(selected_id):
        _show_message("注視するモデルを選択してください")
        return
    _focus_bbmodel(objects_by_id[selected_id])
    _show_message("注視点を %s に合わせました" % _model_title(selected_id))

func _cycle_bb_animation() -> void:
    _open_motion_picker()

func _unused_legacy_animation_switch() -> void:
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
    motion_button.text = "＋アニメを配置"
    if not bb_assets.has(selected_id):
        return
    var asset: Dictionary = bb_assets[selected_id]
    var clips: Array = asset.get("clips", [])
    var selected := int(asset.get("clip_index", -1))
    if selected >= 0 and selected < clips.size():
        motion_button.text = "＋アニメを配置"

func _sample_bb_animations() -> void:
    var sampler := BBModelImporter.new()
    for id_value in bb_assets.keys():
        var id := str(id_value)
        var asset: Dictionary = bb_assets[id]
        var available: Array = asset.get("clips", [])
        var active: Dictionary = ClipEngine.active_clip(clip_tracks.get(id, []), current_time)
        if active.is_empty():
            sampler.apply_clip(asset["groups"], {}, 0.0, bool(asset["old_format"]))
            continue
        var source_index := int(active.get("animation_index", -1))
        if source_index < 0 or source_index >= available.size():
            sampler.apply_clip(asset["groups"], {}, 0.0, bool(asset["old_format"]))
            continue
        var source_time := ClipEngine.source_time(active, current_time)
        sampler.apply_clip(asset["groups"], available[source_index], source_time,
            bool(asset["old_format"]), active.get("enabled_groups", null) if bool(active.get("limit_bones", false)) else null)

func _animation_duration(source: Dictionary) -> float:
    var declared := float(source.get("length", 0.0))
    if declared > 0.0:
        return declared
    var max_time := 0.0
    for value in source.get("animators", {}).values():
        if value is Dictionary:
            for frame in value.get("keyframes", []):
                if frame is Dictionary:
                    max_time = maxf(max_time, float(frame.get("time", 0.0)))
    return maxf(0.05, max_time)

func _add_animation_clip(model_id: String, animation_index: int, at: float) -> void:
    if not bb_assets.has(model_id):
        return
    var asset: Dictionary = bb_assets[model_id]
    var animations: Array = asset.get("clips", [])
    if animation_index < 0 or animation_index >= animations.size():
        return
    var group_ids: Array = []
    for uuid in (asset["groups"] as Dictionary).keys():
        group_ids.append(str(uuid))
    var uid := "clip_%d" % next_clip_id
    next_clip_id += 1
    var new_clip: Dictionary = ClipEngine.new_clip(uid, animation_index,
        _animation_duration(animations[animation_index]), at, group_ids)
    var rows: Array = clip_tracks.get(model_id, [])
    rows.append(new_clip)
    clip_tracks[model_id] = rows
    asset["clip_index"] = animation_index
    bb_assets[model_id] = asset
    _refresh_timeline()
    _seek(current_time)
    _show_message("動作を配置: %s" % _short_text(str(animations[animation_index].get("name", "Animation")), 19))
    _mark_dirty()

func _find_clip_index(model_id: String, uid: String) -> int:
    var rows: Array = clip_tracks.get(model_id, [])
    for i in range(rows.size()):
        if str(rows[i].get("uid", "")) == uid:
            return i
    return -1

func _on_clip_dragged(model_id: String, uid: String, at: float, finished: bool) -> void:
    var index := _find_clip_index(model_id, uid)
    if index < 0:
        return
    _set_playing(false)
    var rows: Array = clip_tracks[model_id]
    var clip: Dictionary = rows[index]
    var previous_start := float(clip.get("start", 0.0))
    clip["start"] = snappedf(clampf(at, 0.0, maxf(0.0, DURATION - ClipEngine.clip_length(clip))), 0.01)
    if bool(clip.get("loop", false)):
        clip["loop_end"] = minf(DURATION, float(clip.get("loop_end", previous_start + ClipEngine.source_span(clip))) + float(clip["start"]) - previous_start)
    rows[index] = clip
    clip_tracks[model_id] = rows
    _refresh_timeline()
    _seek(current_time)
    if finished:
        _mark_dirty()

func _on_loop_end_dragged(model_id: String, uid: String, seconds: float, finished: bool) -> void:
    var index := _find_clip_index(model_id, uid)
    if index < 0:
        return
    var rows: Array = clip_tracks[model_id]
    var clip: Dictionary = rows[index]
    _set_playing(false)
    # The loop grip is available even for a new, non-looping clip.
    # Dragging it enables repeat playback and expands by whole cycles.
    if not bool(clip.get("loop", false)):
        clip["loop"] = true
    clip["loop_end"] = ClipEngine.snap_loop_end(clip, seconds, DURATION)
    if editing_clip_model == model_id and editing_clip_uid == uid and clip_loop_check != null:
        clip_loop_check.set_pressed_no_signal(true)
    rows[index] = clip
    clip_tracks[model_id] = rows
    _refresh_timeline()
    _seek(current_time)
    if finished:
        _mark_dirty()

func _open_motion_picker() -> void:
    if not bb_assets.has(selected_id):
        _show_message("動作を配置するBBモデルを選択してください")
        return
    picker_mode = "animation"
    picker_title.text = "追加するモーション"
    for child in picker_list.get_children():
        picker_list.remove_child(child)
        child.queue_free()
    var animations: Array = bb_assets[selected_id]["clips"]
    for i in range(animations.size()):
        var animation: Dictionary = animations[i]
        var button := Button.new()
        button.text = _short_text(str(animation.get("name", "Animation")), 26)
        button.custom_minimum_size.y = 54.0
        button.clip_text = true
        button.pressed.connect(_pick_animation.bind(selected_id, i))
        picker_list.add_child(button)
    picker_overlay.show()

func _pick_animation(model_id: String, animation_index: int) -> void:
    _close_picker()
    _add_animation_clip(model_id, animation_index, current_time)


func _build_clip_editor() -> void:
    clip_overlay = Control.new()
    clip_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    clip_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(clip_overlay)
    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.04, 0.07, 0.85)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_overlay.add_child(shade)
    var outside := Button.new()
    outside.flat = true
    outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outside.pressed.connect(_close_clip_editor)
    clip_overlay.add_child(outside)
    var sheet := PanelContainer.new()
    sheet.anchor_left = 0.04
    sheet.anchor_top = 0.15
    sheet.anchor_right = 0.96
    sheet.anchor_bottom = 0.97
    sheet.mouse_filter = Control.MOUSE_FILTER_STOP
    clip_overlay.add_child(sheet)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 7)
    sheet.add_child(layout)
    var title_row := HBoxContainer.new()
    layout.add_child(title_row)
    clip_title = Label.new()
    clip_title.text = "アニメーション詳細"
    clip_title.clip_text = true
    clip_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title_row.add_child(clip_title)
    _make_button(title_row, "閉じる", _close_clip_editor)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_child(scroll)
    var settings := VBoxContainer.new()
    settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings.add_theme_constant_override("separation", 6)
    scroll.add_child(settings)
    for field in [
        {"key":"start", "label":"TL開始（秒）"},
        {"key":"in", "label":"元動作IN（秒）"},
        {"key":"out", "label":"元動作OUT（秒）"},
        {"key":"speed", "label":"再生速度（倍）"}
    ]:
        var row := HBoxContainer.new()
        settings.add_child(row)
        var caption := Label.new()
        caption.text = str(field["label"])
        caption.custom_minimum_size.x = 128
        row.add_child(caption)
        var number := SpinBox.new()
        number.min_value = 0.0 if str(field["key"]) != "speed" else 0.1
        number.max_value = 120.0 if str(field["key"]) != "speed" else 4.0
        number.step = 0.05
        number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        number.value_changed.connect(_update_clip_field.bind(str(field["key"])))
        row.add_child(number)
        clip_fields[str(field["key"])] = number
    clip_loop_check = CheckBox.new()
    clip_loop_check.text = "アニメーションをループする"
    clip_loop_check.custom_minimum_size.y = 50.0
    clip_loop_check.toggled.connect(_toggle_clip_loop)
    settings.add_child(clip_loop_check)
    var loop_hint := Label.new()
    loop_hint.text = "TL上の丸いループアイコンをドラッグすると自動的にループをONにし、1回分の動き単位で再生範囲を延ばせます"
    loop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    settings.add_child(loop_hint)
    clip_limit_check = CheckBox.new()
    clip_limit_check.text = "再生する関節を限定する"
    clip_limit_check.custom_minimum_size.y = 50.0
    clip_limit_check.toggled.connect(_toggle_clip_joint_limit)
    settings.add_child(clip_limit_check)
    clip_scope_controls = VBoxContainer.new()
    settings.add_child(clip_scope_controls)
    var explanation := Label.new()
    explanation.text = "選択した関節と、その子関節だけにモーションを適用します"
    explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    clip_scope_controls.add_child(explanation)
    var toolbar := HBoxContainer.new()
    clip_scope_controls.add_child(toolbar)
    _make_button(toolbar, "全関節ON", func(): _set_all_bones(true))
    _make_button(toolbar, "全関節OFF", func(): _set_all_bones(false))
    var caption := Label.new()
    caption.text = "関節一覧（親を選ぶと子も変更）"
    clip_scope_controls.add_child(caption)
    clip_bone_list = VBoxContainer.new()
    clip_scope_controls.add_child(clip_bone_list)
    clip_scope_controls.hide()
    _make_button(layout, "このクリップを削除", _delete_editing_clip)
    clip_overlay.hide()

func _open_clip_editor(model_id: String, uid: String) -> void:
    var index := _find_clip_index(model_id, uid)
    if index < 0 or not bb_assets.has(model_id):
        return
    _set_playing(false)
    editing_clip_model = model_id
    editing_clip_uid = uid
    var active: Dictionary = clip_tracks[model_id][index]
    var asset: Dictionary = bb_assets[model_id]
    var source_index := int(active.get("animation_index", -1))
    var animations: Array = asset.get("clips", [])
    if source_index < 0 or source_index >= animations.size():
        return
    var animation: Dictionary = animations[source_index]
    clip_title.text = _short_text(str(animation.get("name", "Animation")), 25)
    for field_name in ["start", "in", "out", "speed"]:
        var control: SpinBox = clip_fields[field_name]
        control.set_value_no_signal(float(active.get(field_name, 0.0)))
    clip_loop_check.set_pressed_no_signal(bool(active.get("loop", false)))
    clip_limit_check.set_pressed_no_signal(bool(active.get("limit_bones", false)))
    clip_scope_controls.visible = clip_limit_check.button_pressed
    var source_duration := _animation_duration(animation)
    (clip_fields["in"] as SpinBox).max_value = source_duration
    (clip_fields["out"] as SpinBox).max_value = source_duration
    for child in clip_bone_list.get_children():
        clip_bone_list.remove_child(child)
        child.queue_free()
    var groups: Dictionary = asset["groups"]
    for group_id_value in groups.keys():
        var group_id := str(group_id_value)
        var state: Dictionary = groups[group_id]
        var group_node: Node3D = state["node"]
        var label := CheckBox.new()
        label.text = _short_text(group_node.name, 24)
        label.custom_minimum_size.y = 40.0
        label.set_meta("group_uuid", group_id)
        label.set_pressed_no_signal(ClipEngine.includes_group(active, group_id))
        label.toggled.connect(_toggle_clip_bone.bind(model_id, uid, group_id))
        clip_bone_list.add_child(label)
    clip_overlay.show()

func _toggle_clip_loop(enabled: bool) -> void:
    var clip := _current_edit_clip()
    if clip.is_empty():
        return
    clip["loop"] = enabled
    if enabled:
        # Default to two complete cycles, limited by the movie duration.
        var start := float(clip.get("start", 0.0))
        var cycle := ClipEngine.source_span(clip)
        clip["loop_end"] = ClipEngine.snap_loop_end(clip, start + 2.0 * cycle, DURATION)
    _save_edit_clip(clip)

func _toggle_clip_joint_limit(enabled: bool) -> void:
    if clip_scope_controls != null:
        clip_scope_controls.visible = enabled
    var clip := _current_edit_clip()
    if clip.is_empty():
        return
    clip["limit_bones"] = enabled
    _save_edit_clip(clip)

func _current_edit_clip() -> Dictionary:
    var index := _find_clip_index(editing_clip_model, editing_clip_uid)
    if index < 0:
        return {}
    return clip_tracks[editing_clip_model][index]

func _save_edit_clip(clip: Dictionary) -> void:
    var index := _find_clip_index(editing_clip_model, editing_clip_uid)
    if index < 0:
        return
    var rows: Array = clip_tracks[editing_clip_model]
    rows[index] = clip
    clip_tracks[editing_clip_model] = rows
    _refresh_timeline()
    _seek(current_time)
    _mark_dirty()

func _update_clip_field(value: float, field_name: String) -> void:
    var clip := _current_edit_clip()
    if clip.is_empty():
        return
    clip[field_name] = value
    var asset: Dictionary = bb_assets[editing_clip_model]
    var animations: Array = asset["clips"]
    var index := int(clip.get("animation_index", -1))
    if index < 0 or index >= animations.size():
        return
    clip = ClipEngine.validate(clip, _animation_duration(animations[index]), DURATION)
    if ClipEngine.clip_length(clip) < DURATION:
        clip["start"] = minf(float(clip["start"]), DURATION - ClipEngine.clip_length(clip))
    _save_edit_clip(clip)
    # Keep numerical UI in sync if a source boundary was clamped.
    for key in ["start", "in", "out", "speed"]:
        (clip_fields[key] as SpinBox).set_value_no_signal(float(clip[key]))

func _toggle_clip_bone(enabled: bool, model_id: String, uid: String, group_id: String) -> void:
    var clip := _current_edit_clip()
    if clip.is_empty() or model_id != editing_clip_model or uid != editing_clip_uid:
        return
    var groups: Dictionary = bb_assets[model_id]["groups"]
    if not groups.has(group_id):
        return
    var selected_parent: Node3D = groups[group_id]["node"]
    var enabled_list: Array = clip.get("enabled_groups", []).duplicate()
    for key in groups.keys():
        var uuid := str(key)
        var child: Node3D = groups[uuid]["node"]
        var cursor: Node = child
        var within := false
        while cursor != null:
            if cursor == selected_parent:
                within = true
                break
            cursor = cursor.get_parent()
        if not within:
            continue
        if enabled and not enabled_list.has(uuid):
            enabled_list.append(uuid)
        elif not enabled:
            enabled_list.erase(uuid)
    clip["enabled_groups"] = enabled_list
    clip["limit_bones"] = true
    if clip_limit_check != null:
        clip_limit_check.set_pressed_no_signal(true)
        clip_scope_controls.show()
    _save_edit_clip(clip)
    _sync_bone_checks()

func _sync_bone_checks() -> void:
    var clip := _current_edit_clip()
    if clip.is_empty():
        return
    for child in clip_bone_list.get_children():
        if child is CheckBox and child.has_meta("group_uuid"):
            var uuid := str(child.get_meta("group_uuid"))
            (child as CheckBox).set_pressed_no_signal(ClipEngine.includes_group(clip, uuid))

func _set_all_bones(enabled: bool) -> void:
    var clip := _current_edit_clip()
    if clip.is_empty():
        return
    var ids: Array = []
    if enabled:
        for key in (bb_assets[editing_clip_model]["groups"] as Dictionary).keys():
            ids.append(str(key))
    clip["enabled_groups"] = ids
    clip["limit_bones"] = true
    if clip_limit_check != null:
        clip_limit_check.set_pressed_no_signal(true)
        clip_scope_controls.show()
    _save_edit_clip(clip)
    _sync_bone_checks()

func _delete_editing_clip() -> void:
    var index := _find_clip_index(editing_clip_model, editing_clip_uid)
    if index >= 0:
        var rows: Array = clip_tracks[editing_clip_model]
        rows.remove_at(index)
        clip_tracks[editing_clip_model] = rows
        _refresh_timeline()
        _seek(current_time)
    _close_clip_editor()

func _close_clip_editor() -> void:
    if clip_overlay != null:
        clip_overlay.hide()
    editing_clip_model = ""
    editing_clip_uid = ""

func _make_button(parent: Control, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(48, 48)
    button.clip_text = true
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

    shot_camera = Camera3D.new()
    shot_camera.name = "ShotCamera"
    shot_camera.current = false
    shot_camera.fov = 54.0
    scene_root.add_child(shot_camera)
    shot_camera.global_transform = editor_camera.global_transform
    camera_marker = MeshInstance3D.new()
    camera_marker.name = "ShotCameraMarker"
    var marker_mesh := BoxMesh.new()
    marker_mesh.size = Vector3(0.30, 0.22, 0.36)
    camera_marker.mesh = marker_mesh
    var camera_material := StandardMaterial3D.new()
    camera_material.albedo_color = Color("#f4cf75")
    camera_marker.material_override = camera_material
    shot_camera.add_child(camera_marker)
    camera_keys = [_capture_camera_key(0.0)]
    gizmo = TransformGizmo.new()
    gizmo.name = "TransformGizmo"
    scene_root.add_child(gizmo)
    gizmo.visible = false

func _update_camera() -> void:
    var direction := Vector3(
        sin(orbit_yaw) * cos(orbit_pitch),
        sin(orbit_pitch),
        cos(orbit_yaw) * cos(orbit_pitch))
    editor_camera.position = orbit_target + direction * orbit_distance
    editor_camera.look_at(orbit_target, Vector3.UP)
    # Refresh size/orientation when zooming and orbiting while paused.
    _update_gizmo()

func _get_camera_tracks() -> Dictionary:
    var tracks_all: Dictionary = camera_tracks.duplicate(true)
    tracks_all["camera_1"] = camera_keys.duplicate(true)
    return tracks_all

func _get_camera_keys(camera_id: String) -> Array:
    if camera_id == "camera_1":
        return camera_keys
    return camera_tracks.get(camera_id, [])

func _set_camera_keys(camera_id: String, keys: Array) -> void:
    if camera_id == "camera_1":
        camera_keys = keys
    else:
        camera_tracks[camera_id] = keys

func _active_camera_id() -> String:
    var camera_id: String = CameraCuts.active_camera(camera_cuts, current_time)
    if not _get_camera_tracks().has(camera_id):
        return "camera_1"
    return camera_id

func _build_camera_menu() -> void:
    camera_menu = PopupPanel.new()
    add_child(camera_menu)
    var content := VBoxContainer.new()
    content.custom_minimum_size.x = 260
    camera_menu.add_child(content)
    _make_button(content, "＋ 新しい撮影カメラ", func():
        camera_menu.hide()
        _new_camera_and_cut())
    _make_button(content, "✕ 現在のカットを削除", func():
        camera_menu.hide()
        _remove_current_camera_cut())
    _make_button(content, "カメラ一覧を更新", _open_camera_menu)

func _open_camera_menu() -> void:
    # Rebuild only temporary camera-entry buttons; persistent menu controls
    # are always the first three, so their taps remain stable.
    var content: VBoxContainer = camera_menu.get_child(0)
    while content.get_child_count() > 3:
        var last_child: Node = content.get_child(content.get_child_count() - 1)
        content.remove_child(last_child)
        last_child.queue_free()
    for camera_id_value in _get_camera_tracks().keys():
        var camera_id := str(camera_id_value)
        var button := _make_button(content,
            "🎬 ここからCam %s" % camera_id.trim_prefix("camera_"),
            _insert_camera_cut.bind(camera_id))
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    camera_menu.popup_centered()

func _new_camera_and_cut() -> void:
    _set_playing(false)
    var camera_id := "camera_%d" % next_camera_id
    next_camera_id += 1
    var frame := {
        "time": 0.0,
        "position": [editor_camera.position.x, editor_camera.position.y, editor_camera.position.z],
        "rotation": [editor_camera.rotation.x, editor_camera.rotation.y, editor_camera.rotation.z],
        "fov": editor_camera.fov
    }
    camera_tracks[camera_id] = [frame]
    _insert_camera_cut(camera_id)

func _insert_camera_cut(camera_id: String) -> void:
    if not _get_camera_tracks().has(camera_id):
        return
    _set_playing(false)
    var uid := "cut_%d" % next_cut_id
    next_cut_id += 1
    camera_cuts = CameraCuts.insert_cut(camera_cuts, uid, camera_id, current_time, DURATION)
    if camera_menu != null:
        camera_menu.hide()
    _refresh_timeline()
    _seek(current_time)
    _mark_dirty()
    _show_message("%.2f秒から%sを撮影に使用" % [current_time, camera_id])

func _remove_current_camera_cut() -> void:
    var winner := ""
    var chosen_time := -INF
    for entry in camera_cuts:
        var t := float(entry.get("time", 0.0))
        if t <= current_time and t >= chosen_time:
            winner = str(entry.get("uid", ""))
            chosen_time = t
    if winner.is_empty():
        _show_message("削除するカットがありません")
        return
    camera_cuts = CameraCuts.remove_cut(camera_cuts, winner)
    _refresh_timeline()
    _seek(current_time)
    _mark_dirty()
    _show_message("撮影カットを削除しました")

func _timeline_bar_tapped(model_id: String, uid: String) -> void:
    if model_id != "__cuts__":
        _open_clip_editor(model_id, uid)
        return
    for cut in camera_cuts:
        if str(cut.get("uid", "")) == uid:
            _seek(float(cut.get("time", 0.0)))
            _show_message("カット: %s" % str(cut.get("camera_id", "camera_1")))
            return
    _show_message("デフォルトカメラ（Cam 1）")

func _timeline_bar_dragged(model_id: String, uid: String, seconds: float, finished: bool) -> void:
    if model_id != "__cuts__":
        _on_clip_dragged(model_id, uid, seconds, finished)
        return
    if uid == "implicit":
        return
    camera_cuts = CameraCuts.move_cut(camera_cuts, uid, seconds, DURATION)
    _refresh_timeline()
    _seek(current_time)
    if finished:
        _mark_dirty()

func _capture_camera_key(at: float) -> Dictionary:
    return {
        "time": snappedf(at, 0.01),
        "position": [shot_camera.position.x, shot_camera.position.y, shot_camera.position.z],
        "rotation": [shot_camera.rotation.x, shot_camera.rotation.y, shot_camera.rotation.z],
        "fov": shot_camera.fov
    }

func _insert_camera_key() -> void:
    _set_playing(false)
    if shot_camera == null:
        return
    var camera_id := _active_camera_id()
    var keys: Array = _get_camera_keys(camera_id).duplicate(true)
    var key := _capture_camera_key(current_time)
    var replaced := false
    for i in range(keys.size()):
        if absf(float(keys[i].get("time", 0.0)) - current_time) < 0.03:
            keys[i] = key
            replaced = true
            break
    if not replaced:
        keys.append(key)
    keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    _set_camera_keys(camera_id, keys)
    _refresh_timeline()
    _show_message("Cam %s %.2f秒 ◆%s" % [camera_id.trim_prefix("camera_"), current_time, "更新" if replaced else "追加"])
    _mark_dirty()


func _toggle_camera_view() -> void:
    if not shot_preview:
        # Store both the controller parameters and the actual camera matrix.
        # Shot-camera animation and timeline scrubbing must never overwrite
        # the editing viewpoint that existed before this toggle.
        edit_view_snapshot = {
            "target": orbit_target,
            "yaw": orbit_yaw,
            "pitch": orbit_pitch,
            "distance": orbit_distance,
            "transform": editor_camera.global_transform,
            "fov": editor_camera.fov
        }
        shot_preview = true
        shot_camera.make_current()
        camera_view_button.text = "編集視点"
        camera_view_button.tooltip_text = "元の編集視点に戻す"
        camera_marker.visible = false
        part_label.hide()
        for tool_button in transform_buttons:
            tool_button.hide()
    else:
        shot_preview = false
        if not edit_view_snapshot.is_empty():
            orbit_target = edit_view_snapshot["target"]
            orbit_yaw = float(edit_view_snapshot["yaw"])
            orbit_pitch = float(edit_view_snapshot["pitch"])
            orbit_distance = float(edit_view_snapshot["distance"])
            _update_camera()
            editor_camera.global_transform = edit_view_snapshot["transform"]
            editor_camera.fov = float(edit_view_snapshot["fov"])
            edit_view_snapshot.clear()
        editor_camera.make_current()
        camera_view_button.text = "カメラ視点"
        camera_view_button.tooltip_text = "カメラ視点へ切り替え"
        camera_marker.visible = true
        part_label.show()
        for tool_button in transform_buttons:
            tool_button.show()
    _update_gizmo()

func _copy_editor_to_shot() -> void:
    _set_playing(false)
    shot_camera.transform = editor_camera.transform
    shot_camera.fov = editor_camera.fov
    _insert_camera_key()

func _sample_camera() -> void:
    var selected_id := _active_camera_id()
    var values: Dictionary = CameraCuts.sample_keys(_get_camera_keys(selected_id), current_time)
    if values.is_empty():
        return
    shot_camera.position = values["position"]
    shot_camera.quaternion = values["orientation"]
    shot_camera.fov = float(values.get("fov", 54.0))


func _on_preview_input(event: InputEvent) -> void:
    if shot_preview:
        return
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
    drag_handle_axis = 0
    drag_part_path = ""
    drag_target_node = null
    # Gizmo handles have precedence so a part can be moved even when its
    # pivot is outside the visible mesh. Otherwise tap the actual surface.
    if mode_index != 3 and gizmo != null and gizmo.visible:
        drag_handle_axis = gizmo.pick_axis(_viewport_position(at), editor_camera)
    if drag_handle_axis > 0:
        drag_target_id = selected_id
        if selected_part_model == selected_id:
            drag_part_path = selected_part_path
    else:
        drag_target_id = _hit_object_id(at)
        if not drag_target_id.is_empty():
            _set_selection(drag_target_id)
            if bb_assets.has(drag_target_id):
                _set_part_selection(drag_target_id, last_hit_part_path)
                drag_part_path = selected_part_path
    if not drag_target_id.is_empty():
        _set_playing(false)
        drag_target_node = _get_selected_target()
        if drag_target_node == null:
            drag_target_id = ""
            return
        drag_position_start = drag_target_node.position
        drag_rotation_start = drag_target_node.rotation_degrees
        drag_initial_scale = drag_target_node.scale
        drag_existing_offset = _get_part_offset(drag_target_id, drag_part_path)
        var anchor := _gizmo_anchor_world(drag_target_node)
        drag_grab_point = _world_on_level(at, anchor.y, anchor)

func _move_pointer(at: Vector2) -> void:
    if not pointer_active:
        return
    var motion := at - pointer_last
    pointer_last = at
    if not drag_moved:
        if at.distance_to(pointer_origin) < 14.0:
            return
        drag_moved = true
        # Discard the first large movement event so a tap/jitter cannot snap
        # the camera view or move a distant model.
        if drag_target_id.is_empty():
            return
    if drag_target_id.is_empty():
        _orbit(motion)
        return
    _apply_model_drag(at)

func _finish_pointer(at: Vector2) -> void:
    if not pointer_active:
        return
    if drag_moved and not drag_target_id.is_empty() and mode_index != 3:
        _apply_model_drag(at)
        if not drag_part_path.is_empty() and drag_target_node != null:
            _commit_part_edit(drag_target_node, drag_position_start, drag_rotation_start, drag_initial_scale, drag_existing_offset)
            _show_message("部位の調整を保存しました")
        elif drag_target_id == "__camera__":
            _insert_camera_key()
        else:
            _insert_key()
    if drag_moved:
        _mark_dirty()
    pointer_active = false
    drag_moved = false
    drag_target_id = ""
    drag_part_path = ""
    drag_target_node = null

func _apply_model_drag(at: Vector2) -> void:
    if mode_index == 3 or drag_target_node == null:
        return
    var node := drag_target_node
    var axis := drag_handle_axis if drag_handle_axis > 0 else axis_index
    if mode_index == 1:
        var angle := drag_rotation_start
        var rotate_axis: int = 1 if axis == 0 else axis - 1
        angle[rotate_axis] += (at.x - pointer_origin.x) * 0.55
        node.rotation_degrees = angle
        _update_gizmo()
        return
    if mode_index == 2:
        var factor := clampf(exp((pointer_origin.y - at.y) * 0.009), 0.05, 20.0)
        var scale_value := drag_initial_scale
        if axis == 0:
            scale_value *= Vector3.ONE * factor
        else:
            scale_value[axis - 1] *= factor
        node.scale = scale_value
        _update_gizmo()
        return

    var position := drag_position_start
    if axis > 0:
        # Use the actual 2D projection of the rotated part's LOCAL axis.
        # Previously gizmo's line pointed in one direction but parent-local
        # translation took the element in another direction.
        var pivot: Vector3 = _gizmo_anchor_world(node)
        var basis: Basis = node.global_basis.orthonormalized()
        var axis_vectors := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
        var world_axis: Vector3 = basis * axis_vectors[axis - 1]
        var p0: Vector2 = editor_camera.unproject_position(pivot)
        var p1: Vector2 = editor_camera.unproject_position(pivot + world_axis)
        var on_screen: Vector2 = p1 - p0
        if on_screen.length_squared() > 0.00001:
            var cursor_delta: Vector2 = _viewport_position(at) - _viewport_position(pointer_origin)
            var world_distance: float = clampf(cursor_delta.dot(on_screen) / on_screen.length_squared(), -100.0, 100.0)
            var world_delta: Vector3 = world_axis * world_distance
            var parent: Node3D = node.get_parent_node_3d()
            position += parent.global_basis.inverse() * world_delta if parent != null else world_delta
    else:
        var hit := _world_on_level(at, drag_grab_point.y, drag_grab_point)
        var world_delta: Vector3 = hit - drag_grab_point
        var parent: Node3D = node.get_parent_node_3d()
        # Free drag stays on the global ground plane, including when a
        # Blockbench part has a rotated parent; never discard parent-local Y.
        var local_delta: Vector3 = parent.global_basis.inverse() * world_delta if parent != null else world_delta
        position += local_delta
    node.position = position
    _update_gizmo()

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
    # Guard against a sudden Android touch pointer jump when pinching.
    world_per_pixel = minf(world_per_pixel, 0.09)
    midpoint_motion = midpoint_motion.limit_length(24.0)
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
    # Recursive mesh hit test returns the nearest Blockbench element.
    last_hit_part_path = ""
    var screen_pos := _viewport_position(local)
    var ray_origin := editor_camera.project_ray_origin(screen_pos)
    var ray_dir := editor_camera.project_ray_normal(screen_pos)
    var closest_id := ""
    var closest_distance := INF
    if camera_marker != null and camera_marker.visible and camera_marker.global_position.distance_to(editor_camera.global_position) > 0.8:
        var local_inv := camera_marker.global_transform.affine_inverse()
        var ray_start: Vector3 = local_inv * ray_origin
        var ray_axis: Vector3 = local_inv.basis * ray_dir
        var camera_hit: Variant = camera_marker.get_aabb().intersects_ray(ray_start, ray_axis)
        if camera_hit is Vector3:
            closest_id = "__camera__"
            closest_distance = ray_origin.distance_to(camera_marker.global_transform * (camera_hit as Vector3))
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
                            last_hit_part_path = ""
                            var editable_parent: Node = mesh.get_parent()
                            if editable_parent is Node3D and editable_parent != root_node:
                                last_hit_part_path = str(root_node.get_path_to(editable_parent))
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
    _mark_dirty()

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
    if selected_id != id:
        selected_part_path = ""
        selected_part_model = ""
    if id == "__camera__":
        selected_id = id
        selection.text = "撮影カメラ ▾"
    elif objects_by_id.has(id):
        selected_id = id
        selection.text = "%s ▾" % _model_title(id)
    else:
        return
    for object_id in objects_by_id.keys():
        var object_node: Node3D = objects_by_id[object_id]
        var frame: Node3D = object_node.get_node_or_null("SelectionFrame")
        if frame != null:
            # A huge bounding wireframe obstructed imported character models.
            frame.visible = str(object_id) == selected_id and str(object_node.get_meta("kind", "")) != "bbmodel"
    _refresh_motion_button()
    _update_gizmo()
    _refresh_timeline()
    _show_message("選択中: %s" % ("撮影カメラ" if id == "__camera__" else _model_title(id)))

func _refresh_selector() -> void:
    if selection == null:
        return
    if selected_id == "__camera__":
        selection.text = "撮影カメラ ▾"
    elif objects_by_id.has(selected_id):
        selection.text = "%s ▾" % _model_title(selected_id)
    elif not objects_by_id.is_empty():
        _set_selection(str(objects_by_id.keys()[0]))
    else:
        selection.text = "モデル選択 ▾"

func _cycle_mode() -> void:
    _set_transform_mode((mode_index + 1) % 3)

func _get_selected_target() -> Node3D:
    if selected_id == "__camera__":
        return shot_camera
    if not objects_by_id.has(selected_id):
        return null
    var root_node: Node3D = objects_by_id[selected_id]
    if selected_part_model == selected_id and not selected_part_path.is_empty():
        var part: Node3D = root_node.get_node_or_null(NodePath(selected_part_path)) as Node3D
        if part != null:
            return part
    return root_node

func _set_part_selection(model_id: String, path: String) -> void:
    if not objects_by_id.has(model_id):
        return
    selected_id = model_id
    selected_part_model = model_id
    selected_part_path = path
    _set_selection(model_id)
    _update_gizmo()
    _refresh_timeline()
    var target := _get_selected_target()
    if target != null:
        _show_message("要素: %s" % _short_text(target.name, 28))

func _gizmo_anchor_world(target: Node3D) -> Vector3:
    # Imported Blockbench roots often have their origin far from any visible
    # geometry. Store a body-centered anchor in MODEL-LOCAL space once;
    # unlike a per-frame bounding-box center, it will not jump when limbs
    # animate. Individual joints/mesh elements still use their actual pivot.
    if selected_part_model == selected_id and not selected_part_path.is_empty():
        return target.global_position
    if str(target.get_meta("kind", "")) != "bbmodel":
        return target.global_position
    if not target.has_meta("editor_gizmo_anchor"):
        var bounds := _bbmodel_bounds(target)
        var anchor := target.to_local(bounds.get_center()) if bounds.size.length_squared() > 0.000001 else Vector3.ZERO
        target.set_meta("editor_gizmo_anchor", anchor)
    return target.to_global(target.get_meta("editor_gizmo_anchor"))

func _update_gizmo() -> void:
    if gizmo == null or editor_camera == null:
        return
    var target := _get_selected_target()
    gizmo.visible = target != null and mode_index != 3 and not shot_preview
    if target == null:
        part_label.text = "対象: なし"
        return
    var label := target.name
    if selected_part_model != selected_id or selected_part_path.is_empty():
        label = "撮影カメラ" if selected_id == "__camera__" else _model_title(selected_id)
    part_label.text = "対象: %s" % _short_text(label, 11)
    var pivot := _gizmo_anchor_world(target)
    # Match the selected part's local orientation (without inheriting scale).
    # Keeping the axes in parent space gives misleading handles once a model
    # or a Blockbench group has rotated.
    var orientation := target.global_basis.orthonormalized()
    var depth := maxf(editor_camera.global_position.distance_to(pivot), 0.05)
    var world_units_per_pixel := 2.0 * depth * tan(deg_to_rad(editor_camera.fov) * 0.5) / maxf(float(preview.size.y), 1.0)
    var size_world := clampf(world_units_per_pixel * 74.0, 0.04, 12.0)
    gizmo.global_transform = Transform3D(orientation.scaled(Vector3.ONE * size_world), pivot)
    if gizmo.mode != mode_index:
        gizmo.set_mode(mode_index)

func _set_transform_mode(tool: int) -> void:
    mode_index = tool
    for index in range(transform_buttons.size()):
        var button: Button = transform_buttons[index]
        var button_mode: int = [3, 0, 1, 2][index]
        button.modulate = Color("#8ecaff") if button_mode == mode_index else Color.WHITE
    _update_gizmo()

func _open_part_picker() -> void:
    if not objects_by_id.has(selected_id):
        _show_message("先にモデルを選択してください")
        return
    picker_mode = "part"
    picker_title.text = "階層・パーツを選択"
    for child in picker_list.get_children():
        picker_list.remove_child(child)
        child.queue_free()
    var full_button := Button.new()
    full_button.text = "◉ モデル全体"
    full_button.custom_minimum_size.y = 52
    full_button.pressed.connect(_choose_part.bind(selected_id, ""))
    picker_list.add_child(full_button)
    var model: Node3D = objects_by_id[selected_id]
    _fill_part_picker(model, model, 0)
    picker_overlay.show()

func _fill_part_picker(root_node: Node3D, current: Node, depth: int) -> void:
    if depth > 96:
        return
    for child in current.get_children():
        if not (child is Node3D) or child.name in ["SelectionFrame", "EditableMesh", "BBFaceMesh", "ShotCameraMarker", "TransformGizmo"]:
            continue
        if child is StaticBody3D:
            continue
        var part: Node3D = child
        var path := str(root_node.get_path_to(part))
        var button := Button.new()
        button.text = ("  ".repeat(mini(depth, 6))) + _short_text(part.name, 23)
        button.custom_minimum_size.y = 46
        button.clip_text = true
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.pressed.connect(_choose_part.bind(selected_id, path))
        picker_list.add_child(button)
        _fill_part_picker(root_node, child, depth + 1)

func _choose_part(model_id: String, path: String) -> void:
    _close_picker()
    _set_part_selection(model_id, path)

func _toggle_pose_record() -> void:
    pose_record_mode = not pose_record_mode
    pose_record_button.text = "◆ポーズON" if pose_record_mode else "◆ポーズOFF"
    pose_record_button.modulate = Color("#ffda83") if pose_record_mode else Color.WHITE
    if pose_record_mode:
        _show_message("ポーズ記録ON：関節を動かすと現在時刻に◆を登録")
    else:
        _show_message("ポーズ記録OFF：全時刻共通の関節調整")

func _pose_keys(model_id: String, part_path: String) -> Array:
    var by_model: Dictionary = part_pose_tracks.get(model_id, {})
    var keys: Variant = by_model.get(part_path, [])
    return keys if keys is Array else []

func _get_static_part_offset(model_id: String, path: String) -> Dictionary:
    var per_model: Dictionary = element_offsets.get(model_id, {})
    if per_model.has(path):
        return (per_model[path] as Dictionary).duplicate(true)
    return PoseTrack.identity()

func _sample_pose(model_id: String, path: String, time: float) -> Dictionary:
    return PoseTrack.sample(_pose_keys(model_id, path), time)

func _read_part_history_state(model_id: String, part_path: String) -> Dictionary:
    return {
        "base": _get_static_part_offset(model_id, part_path),
        "keys": _pose_keys(model_id, part_path).duplicate(true)
    }

func _write_part_history_state(model_id: String, part_path: String, state: Dictionary) -> void:
    var base_by_model: Dictionary = element_offsets.get(model_id, {})
    base_by_model[part_path] = state.get("base", PoseTrack.identity()).duplicate(true)
    element_offsets[model_id] = base_by_model
    var track_by_model: Dictionary = part_pose_tracks.get(model_id, {})
    var keys: Array = state.get("keys", [])
    if keys.is_empty():
        track_by_model.erase(part_path)
    else:
        track_by_model[part_path] = keys.duplicate(true)
    part_pose_tracks[model_id] = track_by_model

func _remember_part_edit(model_id: String, part_path: String, before: Dictionary) -> void:
    var after := _read_part_history_state(model_id, part_path)
    if JSON.stringify(before) == JSON.stringify(after):
        return
    undo_stack.append({
        "model": model_id,
        "path": part_path,
        "before": before.duplicate(true),
        "after": after.duplicate(true)
    })
    if undo_stack.size() > 40:
        undo_stack.pop_front()
    redo_stack.clear()
    _mark_dirty()

func _undo_part_edit() -> void:
    _set_playing(false)
    if undo_stack.is_empty():
        _show_message("取り消す部位編集がありません")
        return
    var action: Dictionary = undo_stack.pop_back()
    _write_part_history_state(str(action["model"]), str(action["path"]), action["before"])
    redo_stack.append(action)
    _refresh_timeline()
    _seek(current_time)
    _show_message("部位編集を取り消しました")
    _mark_dirty()

func _redo_part_edit() -> void:
    _set_playing(false)
    if redo_stack.is_empty():
        _show_message("やり直す部位編集がありません")
        return
    var action: Dictionary = redo_stack.pop_back()
    _write_part_history_state(str(action["model"]), str(action["path"]), action["after"])
    undo_stack.append(action)
    _refresh_timeline()
    _seek(current_time)
    _show_message("部位編集をやり直しました")
    _mark_dirty()

func _store_pose_key(model_id: String, part_path: String, time: float, pose: Dictionary) -> void:
    var by_model: Dictionary = part_pose_tracks.get(model_id, {})
    by_model[part_path] = PoseTrack.upsert(_pose_keys(model_id, part_path), time, pose)
    part_pose_tracks[model_id] = by_model

func _insert_selected_part_key() -> void:
    if selected_part_model != selected_id or selected_part_path.is_empty():
        _show_message("関節・パーツを選択してください")
        return
    _set_playing(false)
    var before := _read_part_history_state(selected_id, selected_part_path)
    _store_pose_key(selected_id, selected_part_path, current_time,
        _sample_pose(selected_id, selected_part_path, current_time))
    _remember_part_edit(selected_id, selected_part_path, before)
    _refresh_timeline()
    _seek(current_time)
    _show_message("%.2f秒に関節ポーズ◆を記録" % current_time)
    _mark_dirty()

func _get_part_offset(model_id: String, path: String) -> Dictionary:
    # The current pose delta is included in what the user sees and edits.
    return PoseTrack.combine(
        _get_static_part_offset(model_id, path),
        _sample_pose(model_id, path, current_time))

func _capture_static_element_rest(model_id: String) -> void:
    if not bb_assets.has(model_id) or not objects_by_id.has(model_id):
        return
    var root_node: Node3D = objects_by_id[model_id]
    var groups: Dictionary = bb_assets[model_id]["groups"]
    var animated_nodes: Array[Node] = []
    for group_data in groups.values():
        if group_data is Dictionary:
            animated_nodes.append(group_data["node"])
    var baseline: Dictionary = {}
    var stack: Array[Node] = [root_node]
    while not stack.is_empty():
        var item: Node = stack.pop_back()
        if item is Node3D and item != root_node and not animated_nodes.has(item):
            if item.name not in ["BBFaceMesh", "SelectionFrame"]:
                var part: Node3D = item
                baseline[str(root_node.get_path_to(part))] = {
                    "position": _vec_array(part.position),
                    "rotation": _vec_array(part.rotation_degrees),
                    "scale": _vec_array(part.scale)
                }
        for child in item.get_children():
            stack.append(child)
    static_element_rest[model_id] = baseline

func _reset_static_elements() -> void:
    for model_id_value in static_element_rest.keys():
        var model_id := str(model_id_value)
        if not objects_by_id.has(model_id):
            continue
        var root_node: Node3D = objects_by_id[model_id]
        var records: Dictionary = static_element_rest[model_id]
        for path_value in records.keys():
            var path := str(path_value)
            var part: Node3D = root_node.get_node_or_null(NodePath(path)) as Node3D
            if part == null:
                continue
            var baseline: Dictionary = records[path]
            part.position = _array_to_vec(baseline.get("position", [0, 0, 0]))
            part.rotation_degrees = _array_to_vec(baseline.get("rotation", [0, 0, 0]))
            part.scale = _array_to_vec(baseline.get("scale", [1, 1, 1]))

func _apply_element_offsets() -> void:
    _reset_static_elements()
    # Both static corrections and timed pose keys must be applied once, after
    # the original Blockbench animation has reset its own group transforms.
    var model_ids: Dictionary = {}
    for model_id in element_offsets.keys():
        model_ids[str(model_id)] = true
    for model_id in part_pose_tracks.keys():
        model_ids[str(model_id)] = true
    for id_value in model_ids.keys():
        var model_id := str(id_value)
        if not objects_by_id.has(model_id):
            continue
        var root_node: Node3D = objects_by_id[model_id]
        var paths: Dictionary = {}
        for path in (element_offsets.get(model_id, {}) as Dictionary).keys():
            paths[str(path)] = true
        for path in (part_pose_tracks.get(model_id, {}) as Dictionary).keys():
            paths[str(path)] = true
        for path_value in paths.keys():
            var path := str(path_value)
            var node: Node3D = root_node.get_node_or_null(NodePath(path)) as Node3D
            if node == null:
                continue
            var offset := _get_part_offset(model_id, path)
            node.position += _array_to_vec(offset.get("position", [0, 0, 0]))
            node.rotation_degrees += _array_to_vec(offset.get("rotation", [0, 0, 0]))
            node.scale *= _array_to_vec(offset.get("scale", [1, 1, 1]))


func _commit_part_edit(node: Node3D, start_position: Vector3, start_rotation: Vector3, start_scale: Vector3, previous: Dictionary) -> void:
    if selected_part_model != selected_id or selected_part_path.is_empty():
        return
    var model_id := selected_id
    var path := selected_part_path
    var before := _read_part_history_state(model_id, path)
    var start_scale_safe := Vector3(
        maxf(absf(start_scale.x), 0.00001),
        maxf(absf(start_scale.y), 0.00001),
        maxf(absf(start_scale.z), 0.00001))
    var edit_delta := {
        "position": _vec_array(node.position - start_position),
        "rotation": _vec_array(node.rotation_degrees - start_rotation),
        "scale": _vec_array(node.scale / start_scale_safe)
    }
    var effective := PoseTrack.combine(previous, edit_delta)
    if pose_record_mode:
        # Keyframes are authored as DELTAS over the immutable static correction,
        # not absolute Blockbench bone positions; this preserves source motion.
        var pose := PoseTrack.relative(effective, _get_static_part_offset(model_id, path))
        _store_pose_key(model_id, path, current_time, pose)
    else:
        # Static editing does not bake the animated pose into all frames.
        var base := PoseTrack.relative(effective, _sample_pose(model_id, path, current_time))
        var offsets: Dictionary = element_offsets.get(model_id, {})
        offsets[path] = base
        element_offsets[model_id] = offsets
    _remember_part_edit(model_id, path, before)
    _refresh_timeline()
    _seek(current_time)
    _update_gizmo()
    _mark_dirty()

func _vec_array(vec: Vector3) -> Array:
    return [vec.x, vec.y, vec.z]

func _reset_selected_transform() -> void:
    var target := _get_selected_target()
    if target == null:
        return
    _set_playing(false)
    if selected_part_model == selected_id and not selected_part_path.is_empty():
        var before := _read_part_history_state(selected_id, selected_part_path)
        if pose_record_mode:
            var by_model: Dictionary = part_pose_tracks.get(selected_id, {})
            var remaining := PoseTrack.remove_at(_pose_keys(selected_id, selected_part_path), current_time)
            if remaining.is_empty():
                by_model.erase(selected_part_path)
            else:
                by_model[selected_part_path] = remaining
            part_pose_tracks[selected_id] = by_model
        else:
            var per_model: Dictionary = element_offsets.get(selected_id, {})
            per_model.erase(selected_part_path)
            element_offsets[selected_id] = per_model
        _remember_part_edit(selected_id, selected_part_path, before)
        _refresh_timeline()
        _seek(current_time)
    elif selected_id == "__camera__":
        shot_camera.transform = editor_camera.transform
        _insert_camera_key()
    else:
        target.position = Vector3.ZERO
        target.rotation_degrees = Vector3.ZERO
        target.scale = Vector3.ONE
        _insert_key()
    _update_gizmo()
    _show_message("選択対象の調整をリセットしました")
    _mark_dirty()

func _build_transform_inspector() -> void:
    transform_overlay = Control.new()
    transform_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    transform_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(transform_overlay)
    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.04, 0.07, 0.82)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    transform_overlay.add_child(shade)
    var outside := Button.new()
    outside.flat = true
    outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outside.pressed.connect(_close_transform_inspector)
    transform_overlay.add_child(outside)
    var sheet := PanelContainer.new()
    sheet.anchor_left = 0.04
    sheet.anchor_right = 0.96
    sheet.anchor_top = 0.30
    sheet.anchor_bottom = 0.96
    sheet.mouse_filter = Control.MOUSE_FILTER_STOP
    transform_overlay.add_child(sheet)
    var container := VBoxContainer.new()
    container.add_theme_constant_override("separation", 8)
    sheet.add_child(container)
    var title_row := HBoxContainer.new()
    container.add_child(title_row)
    transform_title = Label.new()
    transform_title.text = "要素の数値編集"
    transform_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    transform_title.clip_text = true
    title_row.add_child(transform_title)
    _make_button(title_row, "閉じる", _close_transform_inspector)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    container.add_child(scroll)
    var fields := VBoxContainer.new()
    fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(fields)
    for group_data in [
        {"key": "position", "title": "位置（m）", "step": 0.05},
        {"key": "rotation", "title": "回転（°）", "step": 1.0},
        {"key": "scale", "title": "拡縮（倍率）", "step": 0.05}
    ]:
        var label := Label.new()
        label.text = str(group_data["title"])
        fields.add_child(label)
        var row := HBoxContainer.new()
        fields.add_child(row)
        for axis in range(3):
            var caption := Label.new()
            caption.text = ["X", "Y", "Z"][axis]
            row.add_child(caption)
            var field := SpinBox.new()
            field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            field.min_value = 0.01 if str(group_data["key"]) == "scale" else -10000.0
            field.max_value = 100.0 if str(group_data["key"]) == "scale" else 10000.0
            field.step = float(group_data["step"])
            field.value_changed.connect(_set_numeric_transform.bind(str(group_data["key"]), axis))
            row.add_child(field)
            transform_field_controls["%s_%d" % [str(group_data["key"]), axis]] = field
    _make_button(container, "選択要素をリセット", _reset_selected_transform)
    transform_overlay.hide()

func _open_transform_inspector() -> void:
    var node := _get_selected_target()
    if node == null:
        _show_message("先に編集対象を選択してください")
        return
    _set_playing(false)
    transform_title.text = "数値編集: %s" % _short_text(node.name, 17)
    var values := {
        "position": node.position,
        "rotation": node.rotation_degrees,
        "scale": node.scale
    }
    for key in values.keys():
        var vector: Vector3 = values[key]
        for axis in range(3):
            var field: SpinBox = transform_field_controls["%s_%d" % [str(key), axis]]
            field.set_value_no_signal(vector[axis])
    transform_overlay.show()

func _close_transform_inspector() -> void:
    if transform_overlay != null:
        transform_overlay.hide()

func _set_numeric_transform(value: float, channel: String, axis: int) -> void:
    var node := _get_selected_target()
    if node == null:
        return
    var before_pos := node.position
    var before_rot := node.rotation_degrees
    var before_scale := node.scale
    var previous := _get_part_offset(selected_id, selected_part_path)
    match channel:
        "position":
            var next := node.position
            next[axis] = value
            node.position = next
        "rotation":
            var next := node.rotation_degrees
            next[axis] = value
            node.rotation_degrees = next
        "scale":
            var next := node.scale
            next[axis] = maxf(0.01, value)
            node.scale = next
        _:
            return
    if selected_part_model == selected_id and not selected_part_path.is_empty():
        _commit_part_edit(node, before_pos, before_rot, before_scale, previous)
    elif selected_id == "__camera__":
        _insert_camera_key()
    else:
        _insert_key()
    _update_gizmo()

func _cycle_axis() -> void:
    axis_index = (axis_index + 1) % 4
    axis_option.text = ["自由", "X", "Y", "Z"][axis_index]
    _update_gizmo()

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
    picker_title = Label.new()
    picker_title.text = "モデルを選択"
    picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    picker_title.add_theme_font_size_override("font_size", 20)
    title_row.add_child(picker_title)
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
    picker_mode = "model"
    picker_title.text = "モデルを選択"
    _refresh_picker_list()
    picker_overlay.show()

func _refresh_picker_list() -> void:
    for child in picker_list.get_children():
        picker_list.remove_child(child)
        child.queue_free()
    var camera_button := Button.new()
    camera_button.text = "🎥 撮影カメラ"
    camera_button.custom_minimum_size.y = 56.0
    camera_button.pressed.connect(_choose_model.bind("__camera__"))
    picker_list.add_child(camera_button)
    for id_value in objects_by_id.keys():
        var item_id := str(id_value)
        var button := Button.new()
        button.text = ("✓ " if item_id == selected_id else "　") + _short_text((objects_by_id[item_id] as Node3D).name, 24)
        button.clip_text = true
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
        if transform_overlay != null and transform_overlay.visible:
            _close_transform_inspector()
            get_viewport().set_input_as_handled()
        elif picker_overlay != null and picker_overlay.visible:
            _close_picker()
            get_viewport().set_input_as_handled()

func _nudge(direction: float) -> void:
    var node := _get_selected_target()
    if node == null:
        _show_message("編集する要素を選択してください")
        return
    _set_playing(false)
    var original_position := node.position
    var original_rotation := node.rotation_degrees
    var original_scale := node.scale
    var previous := _get_part_offset(selected_id, selected_part_path)
    var axis: int = 1 if axis_index == 0 and mode_index == 1 else maxi(0, axis_index - 1)
    if mode_index == 2:
        var value := 1.1 if direction > 0.0 else 1.0 / 1.1
        if axis_index == 0:
            node.scale *= Vector3.ONE * value
        else:
            var v := node.scale
            v[axis] *= value
            node.scale = v
    elif mode_index == 1:
        var angles := node.rotation_degrees
        angles[axis] += direction * 10.0
        node.rotation_degrees = angles
    elif mode_index == 0:
        var pos := node.position
        pos[axis] += direction * 0.25
        node.position = pos
    else:
        return
    if selected_part_model == selected_id and not selected_part_path.is_empty():
        _commit_part_edit(node, original_position, original_rotation, original_scale, previous)
    elif selected_id == "__camera__":
        _insert_camera_key()
    else:
        _insert_key()
    _update_gizmo()

func _capture_key(node: Node3D, at: float) -> Dictionary:
    return {
        "time": snappedf(at, 0.01),
        "position": [node.position.x, node.position.y, node.position.z],
        "rotation": [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z],
        "scale": [node.scale.x, node.scale.y, node.scale.z]
    }

func _insert_key() -> void:
    if pose_record_mode and selected_part_model == selected_id and not selected_part_path.is_empty():
        _insert_selected_part_key()
        return
    if selected_id == "__camera__":
        _insert_camera_key()
        return
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
    _mark_dirty()

func _on_key_dragged(id: String, index: int, new_time: float, finished: bool) -> void:
    if id == "__pose__":
        if selected_part_model != selected_id or selected_part_path.is_empty():
            return
        var keys := _pose_keys(selected_id, selected_part_path).duplicate(true)
        if index < 0 or index >= keys.size():
            return
        _set_playing(false)
        # Retain the original order until release to avoid changing which key
        # a finger is currently dragging across other keyframes.
        keys[index]["time"] = snappedf(clampf(new_time, 0.0, DURATION), 0.01)
        if finished:
            keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
        var by_model: Dictionary = part_pose_tracks.get(selected_id, {})
        by_model[selected_part_path] = keys
        part_pose_tracks[selected_id] = by_model
        _refresh_timeline()
        _seek(new_time)
        if finished:
            _mark_dirty()
        return
    if id == "__camera__":
        var camera_id := _active_camera_id()
        var keys: Array = _get_camera_keys(camera_id).duplicate(true)
        if index < 0 or index >= keys.size():
            return
        _set_playing(false)
        keys[index]["time"] = snappedf(clampf(new_time, 0.0, DURATION), 0.01)
        if finished:
            keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
        _set_camera_keys(camera_id, keys)
        _refresh_timeline()
        _seek(new_time)
        if finished:
            _mark_dirty()
        return
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
    if finished:
        _mark_dirty()

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
        node.scale = _array_to_vec(before.get("scale", [1, 1, 1])).lerp(
            _array_to_vec(after.get("scale", [1, 1, 1])), weight)
    _sample_bb_animations()
    _apply_element_offsets()
    _sample_camera()
    _update_gizmo()

func _array_to_vec(data: Variant) -> Vector3:
    if data is Array and data.size() >= 3:
        return Vector3(float(data[0]), float(data[1]), float(data[2]))
    return Vector3.ZERO

func _refresh_timeline() -> void:
    if timeline == null:
        return
    var rows: Array[Dictionary] = []
    var camera_times: Array = []
    var camera_id := _active_camera_id()
    for key in _get_camera_keys(camera_id):
        camera_times.append(float(key.get("time", 0.0)))
    rows.append({"id": "__camera__", "label": "🎥Cam %s" % camera_id.trim_prefix("camera_"), "times": camera_times})
    var camera_bars := CameraCuts.bars(camera_cuts, DURATION, _get_camera_tracks())
    rows.append({"id": "__cuts__", "kind": "clips", "label": "🎬カット", "clips": camera_bars})
    for id_value in objects_by_id.keys():
        var id := str(id_value)
        var node: Node3D = objects_by_id[id]
        var times: Array = []
        for key in tracks.get(id, []):
            times.append(float(key.get("time", 0.0)))
        rows.append({"id": id, "label": _model_title(id), "times": times})
        if bb_assets.has(id):
            var bars: Array = []
            var asset: Dictionary = bb_assets[id]
            var animations: Array = asset.get("clips", [])
            for bar in clip_tracks.get(id, []):
                var which := int(bar.get("animation_index", -1))
                if which < 0 or which >= animations.size():
                    continue
                bars.append({
                    "uid": str(bar.get("uid", "")),
                    "start": float(bar.get("start", 0.0)),
                    "end": ClipEngine.end_time(bar),
                    "label": _short_text(str(animations[which].get("name", "Motion")), 12),
                    "loop": bool(bar.get("loop", false)),
                    "loop_handle": true,
                    "cycle": ClipEngine.source_span(bar)
                })
            rows.append({"id": id, "kind": "clips", "label": "↳動作", "clips": bars})
    if selected_part_model == selected_id and not selected_part_path.is_empty() and objects_by_id.has(selected_id):
        var chosen: Node3D = (objects_by_id[selected_id] as Node3D).get_node_or_null(NodePath(selected_part_path))
        if chosen != null:
            var times: Array = []
            for key in _pose_keys(selected_id, selected_part_path):
                times.append(float(key.get("time", 0.0)))
            rows.append({"id": "__pose__", "label": "↳%s◆" % _short_text(chosen.name, 6), "times": times})
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
            "display_name": node.name,
            "keyframes": tracks.get(id, []),
            "animation_clips": clip_tracks.get(id, []),
            "element_offsets": element_offsets.get(id, {}).duplicate(true),
            "part_pose_tracks": part_pose_tracks.get(id, {}).duplicate(true),
            "bb_source": str(bb_assets[id]["source"]) if bb_assets.has(id) else "",
            "bb_clip_index": int(bb_assets[id]["clip_index"]) if bb_assets.has(id) else -1
        })
    return {"version": 6, "duration": DURATION,
        "camera_keys": camera_keys.duplicate(true),
        "camera_tracks": camera_tracks.duplicate(true),
        "camera_cuts": camera_cuts.duplicate(true),
        "objects": records}

func _save_project() -> void:
    _set_playing(false)
    if autosave_timer != null:
        autosave_timer.stop()
    if _write_project_text(JSON.stringify(_serialize_project(), "\t")):
        _show_message("保存しました（バックアップ保持）")
    else:
        _show_message("保存できません。空き容量を確認してください")

func _load_project() -> void:
    _set_playing(false)
    var loaded: Dictionary = MovieProjectStorage.read_with_backup(SAVE_PATH, BACKUP_PATH)
    if not bool(loaded.get("ok", false)):
        _show_message("保存データを読み込めません。バックアップも確認してください")
        return
    var parsed: Variant = JSON.parse_string(str(loaded["text"]))
    is_project_loading = true
    DURATION = clampf(float(parsed.get("duration", 15.0)), 1.0, 600.0)
    time_slider.max_value = DURATION
    timeline.duration = DURATION
    timeline.zoom = 1.0
    timeline.view_start = 0.0
    for node in objects_by_id.values():
        (node as Node3D).queue_free()
    objects_by_id.clear()
    tracks.clear()
    bb_assets.clear()
    clip_tracks.clear()
    camera_tracks.clear()
    camera_cuts.clear()
    next_camera_id = 2
    next_cut_id = 1
    element_offsets.clear()
    part_pose_tracks.clear()
    static_element_rest.clear()
    undo_stack.clear()
    redo_stack.clear()
    selected_part_model = ""
    selected_part_path = ""
    next_clip_id = 1
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
            model.name = _safe_model_name(str(bb_result.get("model_name", "")), str(record.get("display_name", "BBモデル")), id)
            model.set_meta("movie_id", id)
            model.set_meta("kind", "bbmodel")
            model.set_meta("tint", "#ffffff")
            scene_root.add_child(model)
            _add_bbmodel_selection_frame(model)
            objects_by_id[id] = model
            var clips: Array = bb_result.get("animations", [])
            bb_assets[id] = {
                "source": source, "groups": bb_result["groups"], "clips": clips,
                "clip_index": clampi(int(record.get("bb_clip_index", -1)), -1, clips.size() - 1),
                "old_format": int(str(model.get_meta("bb_format", "5")).get_slice(".", 0)) < 5
            }
            _capture_static_element_rest(id)
            element_offsets[id] = (record.get("element_offsets", {}) as Dictionary).duplicate(true)
            # Reject missing/invalid paths and malformed keys rather than
            # trusting JSON loaded from an old project.
            var loaded_pose: Dictionary = {}
            var original_pose: Variant = record.get("part_pose_tracks", {})
            if original_pose is Dictionary:
                for path_value in original_pose.keys():
                    var part_path := str(path_value)
                    if model.get_node_or_null(NodePath(part_path)) == null:
                        continue
                    var raw_pose: Variant = original_pose[path_value]
                    if not (raw_pose is Array):
                        continue
                    var validated: Array = []
                    for key_value in raw_pose:
                        if key_value is Dictionary and key_value.has("time") and key_value.has("position") and key_value.has("rotation") and key_value.has("scale"):
                            validated.append(key_value.duplicate(true))
                    validated.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
                    if not validated.is_empty():
                        loaded_pose[part_path] = validated
            part_pose_tracks[id] = loaded_pose
            var restored: Array = []
            for clip_value in record.get("animation_clips", []):
                if not (clip_value is Dictionary):
                    continue
                var stored: Dictionary = clip_value
                var animation_index := int(stored.get("animation_index", -1))
                if animation_index < 0 or animation_index >= clips.size():
                    continue
                var safe: Dictionary = ClipEngine.validate(stored,
                    _animation_duration(clips[animation_index]), DURATION)
                # Earlier projects only stored the list, without the opt-in switch.
                if not stored.has("limit_bones") and stored.get("enabled_groups", null) is Array:
                    safe["limit_bones"] = (stored["enabled_groups"] as Array).size() < (bb_assets[id]["groups"] as Dictionary).size()
                if not (safe.get("enabled_groups", null) is Array):
                    var all_groups: Array = []
                    for uuid in (bb_assets[id]["groups"] as Dictionary).keys():
                        all_groups.append(str(uuid))
                    safe["enabled_groups"] = all_groups
                if str(safe.get("uid", "")).is_empty():
                    safe["uid"] = "clip_%d" % next_clip_id
                    next_clip_id += 1
                else:
                    var name := str(safe.get("uid", ""))
                    if name.begins_with("clip_") and name.substr(5).is_valid_int():
                        next_clip_id = maxi(next_clip_id, int(name.substr(5)) + 1)
                restored.append(safe)
            clip_tracks[id] = restored
            if restored.is_empty() and int(parsed.get("version", 1)) == 1 and not clips.is_empty():
                var legacy_index := clampi(int(record.get("bb_clip_index", 0)), 0, clips.size() - 1)
                var group_ids: Array = []
                for uuid in (bb_assets[id]["groups"] as Dictionary).keys():
                    group_ids.append(str(uuid))
                clip_tracks[id].append(ClipEngine.new_clip("clip_%d" % next_clip_id,
                    legacy_index, _animation_duration(clips[legacy_index]), 0.0, group_ids))
                next_clip_id += 1
        else:
            _create_object(id, kind, pos, angles, str(record.get("tint", "#ffffff")))
    var loaded_camera: Variant = parsed.get("camera_keys", null)
    if loaded_camera is Array and not loaded_camera.is_empty():
        var cleaned: Array = []
        for record in loaded_camera:
            if record is Dictionary and record.has("time") and record.has("position") and record.has("rotation"):
                cleaned.append(record.duplicate(true))
        if not cleaned.is_empty():
            cleaned.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
            camera_keys = cleaned
    var extra_tracks: Variant = parsed.get("camera_tracks", {})
    if extra_tracks is Dictionary:
        for id_value in extra_tracks.keys():
            var cam_id := str(id_value)
            if not cam_id.begins_with("camera_") or cam_id == "camera_1" or not (extra_tracks[id_value] is Array):
                continue
            var cleaned_keys: Array = []
            for entry in extra_tracks[id_value]:
                if entry is Dictionary and entry.has("time") and entry.has("position") and entry.has("rotation"):
                    cleaned_keys.append(entry.duplicate(true))
            if cleaned_keys.is_empty():
                continue
            cleaned_keys.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
            camera_tracks[cam_id] = cleaned_keys
            var numeric_part := cam_id.trim_prefix("camera_")
            if numeric_part.is_valid_int():
                next_camera_id = maxi(next_camera_id, int(numeric_part) + 1)
    var loaded_cuts: Variant = parsed.get("camera_cuts", [])
    if loaded_cuts is Array:
        for entry in loaded_cuts:
            if not (entry is Dictionary):
                continue
            var cam_id := str(entry.get("camera_id", "camera_1"))
            var uid := str(entry.get("uid", ""))
            if not _get_camera_tracks().has(cam_id):
                continue
            if uid.is_empty():
                uid = "cut_%d" % next_cut_id
                next_cut_id += 1
            elif uid.begins_with("cut_") and uid.substr(4).is_valid_int():
                next_cut_id = maxi(next_cut_id, int(uid.substr(4)) + 1)
            camera_cuts.append({"uid": uid, "camera_id": cam_id,
                "time": clampf(float(entry.get("time", 0.0)), 0.0, DURATION)})
        camera_cuts.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    _refresh_selector()
    _refresh_timeline()
    _seek(0.0)
    if bb_assets.has(selected_id):
        # Only reframe after the restore has completed, never on selection taps.
        _focus_bbmodel(objects_by_id[selected_id])
    is_project_loading = false
    if autosave_timer != null:
        autosave_timer.stop()
    _show_message("バックアップから復元しました（保存すると確定）" if bool(loaded.get("recovered", false)) else "プロジェクトを読み込みました")

func _show_message(message: String) -> void:
    if status_label != null:
        status_label.text = _short_text(message, 45)
        status_label.tooltip_text = message
