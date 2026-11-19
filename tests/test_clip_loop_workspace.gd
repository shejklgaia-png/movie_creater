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
    editor.call("_open_clip_editor", model_id, uid)
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
    var timeline: Control = editor.get("timeline")
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
    print("CLIP LOOP UI PASSED: mode separation, scoped joints, loop playback, drag snap, retiming and persistence")
    quit(0)
