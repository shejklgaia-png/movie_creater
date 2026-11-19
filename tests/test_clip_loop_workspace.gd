extends SceneTree
## Loop grip snapping, opt-in bone scope, and basic/authoring workspace regression.
const ClipEngine = preload("res://scripts/clip_engine.gd")
const RuntimeClips = preload("res://addons/movie_creator_runtime/clip_engine.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CLIP LOOP UI TEST FAILED: " + message)
    quit(1)

func _near(a: float, b: float) -> bool:
    return absf(a - b) < 0.04

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    if bool(editor.get("motion_workspace")):
        _fail("Default view must be basic editing")
        return
    var categories: Dictionary = editor.get("category_buttons")
    if (categories["変形"] as Button).visible or (editor.get("pose_record_button") as Button).visible:
        _fail("Advanced transform and pose controls must start hidden")
        return
    editor.call("_toggle_workspace")
    if not bool(editor.get("motion_workspace")) or not (categories["変形"] as Button).visible:
        _fail("Authoring workspace did not expose transform editing")
        return
    editor.call("_toggle_workspace")
    if bool(editor.get("motion_workspace")):
        _fail("Returning to basic editing failed")
        return

    var source := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Loop Test"):
        _fail("Fixture import failed")
        return
    var model_id: String = editor.get("selected_id")
    var rows: Array = (editor.get("clip_tracks") as Dictionary)[model_id]
    if rows.size() != 1:
        _fail("Default animation clip was not created")
        return
    var clip: Dictionary = rows[0]
    var uid := str(clip.get("uid", ""))
    # A newly imported (non-looping) animation must still show a loop handle.
    var timeline: Control = editor.get("timeline")
    var animation_row := -1
    var animation_bar: Dictionary = {}
    for track_index in range((timeline.get("tracks") as Array).size()):
        var row: Dictionary = (timeline.get("tracks") as Array)[track_index]
        if str(row.get("id", "")) != model_id or str(row.get("kind", "")) != "clips":
            continue
        animation_row = track_index
        for candidate in row.get("clips", []):
            if str(candidate.get("uid", "")) == uid:
                animation_bar = candidate
                break
    if animation_row < 0 or bool(clip.get("loop", false)) or not bool(animation_bar.get("loop_handle", false)):
        _fail("New animation bar does not advertise a loop grip before activation")
        return
    if not bool(timeline.call("_has_loop_grip", animation_bar)):
        _fail("Timeline will not draw an initial loop handle")
        return
    var cycle: float = ClipEngine.source_span(clip)
    var from_x: float = timeline.call("_x_at", ClipEngine.end_time(clip))
    var grip: Vector2 = timeline.call("_loop_grip_center", from_x,
        float(timeline.get("HEADER_HEIGHT")) + float(animation_row) * float(timeline.get("ROW_HEIGHT")))
    var target_x: float = timeline.call("_x_at", float(clip["start"]) + 3.0 * cycle)
    timeline.call("_start_interaction", grip)
    if str(timeline.get("drag_kind")) != "loop":
        _fail("Visible grip does not receive finger hit detection")
        return
    var moved: Vector2 = grip + Vector2(target_x - from_x, 0.0)
    timeline.call("_move_interaction", moved)
    timeline.call("_finish_interaction", moved)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if not bool(clip.get("loop", false)) or not _near(ClipEngine.clip_length(clip), 3.0 * cycle):
        _fail("Dragging an initially unlooped bar did not enable repeated playback")
        return
    editor.call("_open_clip_editor", model_id, uid)
    editor.call("_toggle_clip_loop", false)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if bool(clip.get("loop", false)):
        _fail("Turning loop back off did not restore single-play editing")
        return
    if not bool(timeline.call("_has_loop_grip", animation_bar)):
        _fail("Turning repeat off must not hide the discoverable handle")
        return
    var scope_controls: VBoxContainer = editor.get("clip_scope_controls")
    if scope_controls.visible:
        _fail("Bone list should not appear before enabling restriction")
        return
    editor.call("_toggle_clip_joint_limit", true)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if not scope_controls.visible or not bool(clip.get("limit_bones", false)):
        _fail("Enabling joint restriction did not reveal the list")
        return
    editor.call("_toggle_clip_joint_limit", false)
    if scope_controls.visible:
        _fail("Joint list should collapse when restriction is off")
        return
    editor.call("_toggle_clip_loop", true)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if not bool(clip.get("loop", false)) or not _near(ClipEngine.clip_length(clip), 4.0):
        _fail("Loop should initially occupy two source cycles")
        return
    if not _near(ClipEngine.source_time(clip, 0.5), ClipEngine.source_time(clip, 2.5)) or not _near(RuntimeClips.source_time(clip, 0.5), RuntimeClips.source_time(clip, 2.5)):
        _fail("Source animation did not repeat with timeline time")
        return
    editor.call("_on_loop_end_dragged", model_id, uid, 5.88, true)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if not _near(ClipEngine.end_time(clip), 6.0):
        _fail("Loop grip should snap to end of the third cycle")
        return
    editor.call("_on_clip_dragged", model_id, uid, 3.0, true)
    clip = (editor.get("clip_tracks") as Dictionary)[model_id][0]
    if not _near(float(clip["start"]), 3.0) or not _near(ClipEngine.end_time(clip), 9.0):
        _fail("Moving the bar must preserve the loop extent")
        return
    var has_repeat_bar := false
    for track in (timeline.get("tracks") as Array):
        if str(track.get("kind", "")) != "clips":
            continue
        for bar in (track.get("clips", []) as Array):
            if str(bar.get("uid", "")) == uid and bool(bar.get("loop", false)) and _near(float(bar.get("end", 0)), 9.0):
                has_repeat_bar = true
    if not has_repeat_bar:
        _fail("Loop bar and handle metadata missing in timeline")
        return

    var saved: Dictionary = editor.call("_serialize_project")
    if int(saved.get("version", 0)) != 6:
        _fail("New project version must preserve loop and scope fields")
        return
    var saved_loop := false
    for record in saved["objects"]:
        if str(record.get("id", "")) == model_id:
            var saved_clips: Array = record.get("animation_clips", [])
            if not saved_clips.is_empty():
                saved_loop = bool(saved_clips[0].get("loop", false)) and _near(float(saved_clips[0].get("loop_end", 0)), 9.0)
    if not saved_loop:
        _fail("Loop playback boundary was not serialized")
        return
    editor.call("_close_clip_editor")
    print("CLIP LOOP UI PASSED: default visible grip, direct drag activation, mode separation, scoped joints, loop playback, drag snap, retiming and persistence")
    quit(0)
