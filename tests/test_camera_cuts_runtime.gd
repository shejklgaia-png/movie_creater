extends SceneTree
## End-to-end coverage for camera cut lane + portable Godot playback runtime.
const Cuts = preload("res://scripts/camera_cuts.gd")
const MoviePlayer = preload("res://addons/movie_creator_runtime/movie_player.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ROADMAP CAMERA TEST FAILED: " + message)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    editor.call("_set_project_duration", 30.0)
    var editor_camera: Camera3D = editor.get("editor_camera")
    var preview_camera: Camera3D = editor.get("shot_camera")

    editor.call("_seek", 5.0)
    editor_camera.position = Vector3(7, 4, 5)
    editor.call("_new_camera_and_cut")
    var cuts: Array = editor.get("camera_cuts")
    if cuts.size() != 1 or str(cuts[0]["camera_id"]) != "camera_2":
        _fail("Creating a camera did not add a cut at current time")
        return
    if str(editor.call("_active_camera_id")) != "camera_2":
        _fail("New camera is not selected at its cut")
        return
    if preview_camera.position.distance_to(editor_camera.position) > 0.01:
        _fail("New camera failed to inherit the edit camera's actual pose")
        return

    editor.call("_seek", 2.0)
    if str(editor.call("_active_camera_id")) != "camera_1":
        _fail("Camera 1 does not cover period before the cut")
        return
    var before_cut: Vector3 = preview_camera.position
    editor.call("_seek", 5.0)
    if preview_camera.position.distance_to(before_cut) < 1.0:
        _fail("Shot preview did not switch camera at exact cut boundary")
        return

    var events: Array = editor.get("camera_cuts")
    editor.call("_timeline_bar_dragged", "__cuts__", str(events[0]["uid"]), 10.0, true)
    editor.call("_seek", 9.99)
    if str(editor.call("_active_camera_id")) != "camera_1":
        _fail("Repositioned camera cut began too early")
        return
    editor.call("_seek", 10.0)
    if str(editor.call("_active_camera_id")) != "camera_2":
        _fail("Repositioned camera cut does not begin at 10 seconds")
        return
    var tracks: Array = (editor.get("timeline") as Control).get("tracks")
    var cut_bar_count := -1
    for row in tracks:
        if str(row.get("id", "")) == "__cuts__":
            cut_bar_count = (row.get("clips", []) as Array).size()
    if cut_bar_count != 2:
        _fail("Cut lane does not display implicit Camera 1 and Camera 2")
        return

    editor_camera.position = Vector3(-9, 2, 6)
    editor.call("_copy_editor_to_shot")
    var extras: Dictionary = editor.get("camera_tracks")
    if (extras["camera_2"] as Array).size() != 2:
        _fail("Camera 2 keyframe track was not edited independently")
        return
    if (editor.get("camera_keys") as Array).size() != 1:
        _fail("Editing Camera 2 accidentally changed Camera 1 keys")
        return

    var data: Dictionary = editor.call("_serialize_project")
    if int(data["version"]) != 5 or (data["camera_cuts"] as Array).size() != 1:
        _fail("Camera cut data not serialized in project v5")
        return
    editor.call("_save_project")
    editor.call("_load_project")
    var restored: Dictionary = editor.call("_serialize_project")
    if (restored["camera_cuts"] as Array).size() != 1 or not (restored["camera_tracks"] as Dictionary).has("camera_2"):
        _fail("Saved camera cut and track not restored")
        return
    editor.call("_seek", 10.0)
    if str(editor.call("_active_camera_id")) != "camera_2":
        _fail("Loaded cut did not return Camera 2")
        return

    var payload: Dictionary = editor.call("_serialize_runtime_data")
    if str(payload.get("schema", "")) != "movie_creator_runtime_v1" or payload.has("version"):
        _fail("Exported scene is not a portable runtime document")
        return
    for record in payload["objects"]:
        if record.has("bb_source"):
            _fail("Portable runtime export still contains large private Blockbench meshes")
            return

    var output_camera := Camera3D.new()
    root.add_child(output_camera)
    var player = MoviePlayer.new()
    root.add_child(player)
    if not player.configure(payload, output_camera):
        _fail("Standalone runtime rejected editor export")
        return
    player.seek(9.5)
    var runtime_cam_1 := output_camera.position
    player.seek(10.0)
    if output_camera.position.distance_to(runtime_cam_1) < 1.0:
        _fail("Runtime player did not switch camera on cut")
        return
    var sample: Dictionary = Cuts.sample_keys(extras["camera_2"], 10.0)
    if output_camera.position.distance_to(sample["position"]) > 0.01:
        _fail("Game runtime camera position differs from preview camera")
        return

    # Runtime scene models are supplied by the game, not auto-imported.
    var model: Node3D = Node3D.new()
    root.add_child(model)
    player.bind_model("99", model)
    player.play(8.0)
    player.pause()
    if not is_equal_approx(player.time, 8.0):
        _fail("Pause/seek state is inconsistent")
        return
    player.skip(true)
    if player.playing or not is_equal_approx(player.time, 30.0):
        _fail("Game skip failed to finish and release playback")
        return
    print("ROADMAP CAMERA TEST PASSED: camera cut lanes, independent camera keys, boundary preview, v5 migration, Godot runtime export, seek/pause/skip")
    quit(0)
