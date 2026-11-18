extends SceneTree
## 0.6: source animation remains intact while pose overrides are authored
## as independent, keyframed joint deltas. Includes redo and project roundtrip.

const PoseTrack = preload("res://scripts/pose_track.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("POSE TIMELINE TEST FAILED: " + message)
    quit(1)

func _near(a: float, b: float, epsilon: float = 0.25) -> bool:
    return absf(a - b) <= epsilon

func _run() -> void:
    # Pure sampler: shortened angle path + multiplicative scale.
    var keys: Array = [
        {"time": 0.0, "position": [0.0, 0.0, 0.0], "rotation": [0.0, 170.0, 0.0], "scale": [1.0, 1.0, 1.0]},
        {"time": 2.0, "position": [2.0, 4.0, 0.0], "rotation": [0.0, -170.0, 0.0], "scale": [2.0, 2.0, 2.0]}
    ]
    var half: Dictionary = PoseTrack.sample(keys, 1.0)
    if not _near(float(half["position"][0]), 1.0, 0.001) or not _near(float(half["scale"][1]), 1.5, 0.001):
        _fail("Position/scale interpolation incorrect")
        return
    if absf(absf(float(half["rotation"][1])) - 180.0) > 0.001:
        _fail("Rotation does not follow shortest angular path")
        return

    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    var source := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Pose Fixture"):
        _fail("Could not import grouped test character")
        return
    var model_id: String = editor.get("selected_id")
    var assets: Dictionary = editor.get("bb_assets")
    var arm: Node3D = assets[model_id]["groups"]["arm"]["node"]
    var model: Node3D = (editor.get("objects_by_id") as Dictionary)[model_id]
    var arm_path := str(model.get_path_to(arm))
    editor.call("_set_part_selection", model_id, arm_path)

    # Activate keyframe mode; explicit 0s key keeps the unedited rest pose.
    editor.call("_toggle_pose_record")
    if not bool(editor.get("pose_record_mode")):
        _fail("Pose record button did not enable")
        return
    editor.call("_seek", 0.0)
    editor.call("_insert_key")
    editor.call("_seek", 2.0)
    var before_position := arm.position
    var before_rotation := arm.rotation_degrees
    var before_scale := arm.scale
    arm.position += Vector3(0.2, 0.0, 0.0)
    arm.rotation_degrees.y += 60.0
    arm.scale = Vector3(1.0, 1.2, 1.0)
    editor.call("_commit_part_edit", arm, before_position, before_rotation, before_scale,
        editor.call("_get_part_offset", model_id, arm_path))
    var pose_map: Dictionary = editor.get("part_pose_tracks")
    var pose_keys: Array = pose_map[model_id][arm_path]
    if pose_keys.size() != 2:
        _fail("Per-arm timeline must contain two pose keyframes")
        return
    var timeline: Control = editor.get("timeline")
    var has_pose_track := false
    for row in timeline.get("tracks"):
        if str(row.get("id", "")) == "__pose__" and (row.get("times", []) as Array).size() == 2:
            has_pose_track = true
    if not has_pose_track:
        _fail("Selected arm's keyframe diamonds are missing from timeline")
        return

    editor.call("_seek", 1.0)
    # BB source wave animation at 1s is +90 degrees; 30deg manual delta is
    # interpolated on top of it, NOT used as an absolute global bone rotation.
    if not _near(arm.rotation_degrees.y, 120.0, 0.3):
        _fail("Pose interpolation did not overlay Blockbench source animation")
        return
    if not _near(arm.position.x - before_position.x, 0.1, 0.02):
        _fail("Pose translation did not interpolate")
        return
    if not _near(arm.scale.y, 1.1, 0.02):
        _fail("Pose scale did not interpolate")
        return
    for n in range(4):
        editor.call("_seek", 1.0)
    if not _near(arm.rotation_degrees.y, 120.0, 0.3):
        _fail("Joint pose accumulates on repeated timeline sampling")
        return

    editor.call("_undo_part_edit")
    editor.call("_seek", 2.0)
    if not _near(arm.rotation_degrees.y, 0.0, 0.2):
        _fail("Undo failed to restore original BB animation")
        return
    editor.call("_redo_part_edit")
    editor.call("_seek", 2.0)
    if not _near(arm.rotation_degrees.y, 60.0, 0.2):
        _fail("Redo failed to restore pose key")
        return

    # Drag the second pose diamond from 2 -> 3 seconds.
    editor.call("_on_key_dragged", "__pose__", 1, 3.0, true)
    pose_map = editor.get("part_pose_tracks")
    pose_keys = pose_map[model_id][arm_path]
    if not _near(float(pose_keys[1]["time"]), 3.0, 0.001):
        _fail("Dragging the pose diamond did not retime it")
        return
    editor.call("_seek", 1.5)
    if not _near(float(PoseTrack.sample(pose_keys, 1.5)["rotation"][1]), 30.0, 0.3):
        _fail("Pose timing was corrupted after retime")
        return

    # A static adjustment should not accidentally absorb an animated pose.
    editor.call("_toggle_pose_record")
    editor.call("_seek", 1.5)
    before_position = arm.position
    before_rotation = arm.rotation_degrees
    before_scale = arm.scale
    arm.position += Vector3(0, 0.15, 0)
    editor.call("_commit_part_edit", arm, before_position, before_rotation, before_scale,
        editor.call("_get_part_offset", model_id, arm_path))
    editor.call("_seek", 0.0)
    if not _near(arm.position.y - before_position.y, 0.15, 0.02):
        _fail("Static adjustment lost when pose keys also exist")
        return

    var serialized: Dictionary = editor.call("_serialize_project")
    if int(serialized.get("version", -1)) != 5:
        _fail("Project did not switch to v5")
        return
    editor.call("_save_project")
    editor.call("_load_project")
    editor.call("_seek", 2.0)
    var restored: Dictionary = editor.get("part_pose_tracks")
    if not restored.has(model_id) or not (restored[model_id] as Dictionary).has(arm_path):
        _fail("Saved pose tracks not restored")
        return
    var restored_arm: Node3D = (editor.get("bb_assets") as Dictionary)[model_id]["groups"]["arm"]["node"]
    if not _near(restored_arm.rotation_degrees.y, 40.0, 0.3):
        _fail("Pose and original animation combined incorrectly after reopening")
        return

    print("POSE TIMELINE TEST PASSED: arm keys, source-overlay interpolation, scale, scrub, undo/redo, retime, v4 save/load")
    quit(0)
