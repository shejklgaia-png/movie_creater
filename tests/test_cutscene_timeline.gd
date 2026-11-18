extends SceneTree
## End-to-end cutscene timeline and camera validation on a generated Blockbench
## grouped 3D model. Runs without an Android device.

const ClipEngine = preload("res://scripts/clip_engine.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CUTSCENE TEST FAILED: " + message)
    quit(1)

func _near(a: float, b: float, tolerance: float = 0.15) -> bool:
    return absf(a - b) < tolerance

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    var source := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Test Motion"):
        _fail("BB model import failed")
        return
    var id: String = editor.get("selected_id")
    var clip_tracks: Dictionary = editor.get("clip_tracks")
    if not clip_tracks.has(id) or (clip_tracks[id] as Array).size() != 1:
        _fail("Import must create a default motion bar")
        return
    var clip: Dictionary = clip_tracks[id][0]
    var uid := str(clip["uid"])
    var duration := ClipEngine.clip_length(clip)
    if not _near(duration, 2.0, 0.01):
        _fail("Wrong clip duration")
        return
    var timeline: Control = editor.get("timeline")
    var rows: Array = timeline.get("tracks")
    var has_camera := false
    var has_bar := false
    for row in rows:
        if str(row.get("id", "")) == "__camera__":
            has_camera = true
        if str(row.get("kind", "")) == "clips" and (row.get("clips", []) as Array).size() == 1:
            has_bar = true
    if not has_camera or not has_bar:
        _fail("Timeline missing camera keyframes or animation bars")
        return
    editor.call("_open_clip_editor", id, uid)
    var overlay: Control = editor.get("clip_overlay")
    if not overlay.visible:
        _fail("Bar detail panel did not open")
        return
    editor.call("_update_clip_field", 3.0, "start")
    editor.call("_update_clip_field", 0.25, "in")
    editor.call("_update_clip_field", 1.25, "out")
    editor.call("_update_clip_field", 1.5, "speed")
    clip = (editor.get("clip_tracks") as Dictionary)[id][0]
    if not _near(ClipEngine.clip_length(clip), 1.0 / 1.5, 0.01):
        _fail("Source IN/OUT or playback speed was not preserved")
        return
    if not _near(ClipEngine.source_time(clip, 3.5), 1.0, 0.02):
        _fail("Timeline time did not map to source trim")
        return
    editor.call("_set_all_bones", false)
    clip = (editor.get("clip_tracks") as Dictionary)[id][0]
    if not (clip["enabled_groups"] as Array).is_empty():
        _fail("Disable all bone channels did not work")
        return
    var group_states: Dictionary = (editor.get("bb_assets") as Dictionary)[id]["groups"]
    var arm: Node3D = group_states["arm"]["node"]
    editor.call("_seek", 3.5)
    if not _near(arm.rotation_degrees.y, 0.0, 0.05):
        _fail("Disabled bone still animates")
        return
    editor.call("_toggle_clip_bone", true, id, uid, "arm")
    editor.call("_seek", 3.5)
    if not _near(arm.rotation_degrees.y, 90.0, 0.1):
        _fail("Enabled arm channel did not animate at trimmed source time")
        return
    editor.call("_on_clip_dragged", id, uid, 5.0, true)
    clip = (editor.get("clip_tracks") as Dictionary)[id][0]
    if not _near(float(clip["start"]), 5.0, 0.01):
        _fail("Dragging bar did not update placement")
        return
    editor.call("_seek", 3.5)
    if not _near(arm.rotation_degrees.y, 0.0, 0.1):
        _fail("Bone does not reset outside active bar")
        return
    editor.call("_close_clip_editor")

    var camera: Camera3D = editor.get("shot_camera")
    var editor_camera: Camera3D = editor.get("editor_camera")
    editor.call("_seek", 6.0)
    editor_camera.position += Vector3(3, 1, 1)
    editor.call("_copy_editor_to_shot")
    var cameras: Array = editor.get("camera_keys")
    if cameras.size() != 2:
        _fail("Camera keyframe not added")
        return
    var shot_end: Vector3 = camera.position
    editor.call("_seek", 3.0)
    var shot_middle: Vector3 = camera.position
    if shot_middle.distance_to(shot_end) < 0.5:
        _fail("Shot camera does not interpolate between keys")
        return
    editor.call("_toggle_camera_view")
    if not bool(editor.get("shot_preview")) or not camera.current:
        _fail("Shot preview did not become active")
        return
    editor.call("_toggle_camera_view")
    if bool(editor.get("shot_preview")) or not editor_camera.current:
        _fail("Edit camera did not return")
        return
    var saved: Dictionary = editor.call("_serialize_project")
    if int(saved.get("version", 0)) != 2 or (saved["camera_keys"] as Array).size() != 2:
        _fail("Camera keys were not serialized")
        return
    var found := false
    for record in saved["objects"]:
        if str(record.get("id", "")) == id:
            var imported_clips: Array = record.get("animation_clips", [])
            if imported_clips.size() != 1 or not _near(float(imported_clips[0]["start"]), 5.0, 0.01):
                _fail("Clips were not serialized")
                return
            if not (imported_clips[0]["enabled_groups"] as Array).has("arm"):
                _fail("Per-bone clip mask was not serialized")
                return
            found = true
    if not found:
        _fail("Model missing from serialized cutscene")
        return
    print("CUTSCENE TEST PASSED: clip bars, trim, speed, mask, drag, camera keyframes, preview, serialization")
    quit(0)
