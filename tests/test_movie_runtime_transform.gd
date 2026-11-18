extends SceneTree
## Standalone exported game runtime test with synthetic 3D nodes.
const Runtime = preload("res://addons/movie_creator_runtime/movie_player.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("GAME RUNTIME TEST FAILED: " + reason)
    quit(1)

func _run() -> void:
    var camera := Camera3D.new()
    root.add_child(camera)
    var model := Node3D.new()
    root.add_child(model)
    var bone := Node3D.new()
    bone.name = "Arm"
    model.add_child(bone)
    bone.position = Vector3(0.5, 0.0, 0.0)
    var player = Runtime.new()
    root.add_child(player)
    var scene := {
        "schema": "movie_creator_runtime_v1",
        "duration": 4.0,
        "camera_keys": [
            {"time": 0.0, "position": [0, 2, 8], "rotation": [0, 0, 0], "fov": 54.0},
            {"time": 4.0, "position": [0, 2, 4], "rotation": [0, 0, 0], "fov": 34.0}
        ],
        "camera_tracks": {},
        "camera_cuts": [],
        "objects": [{
            "id": "1", "name": "Test",
            "keyframes": [
                {"time": 0.0, "position": [0, 0, 0], "rotation": [0, 0, 0], "scale": [1, 1, 1]},
                {"time": 4.0, "position": [4, 0, 0], "rotation": [0, 90, 0], "scale": [2, 2, 2]}
            ],
            "animation_clips": [{
                "uid": "clip_a", "start": 0.0, "in": 0.0, "out": 2.0, "speed": 1.0,
                "animation_index": 2, "enabled_groups": ["Arm"]
            }],
            "element_offsets": {"Arm": {"position": [0.1, 0, 0], "rotation": [0, 10, 0], "scale": [1, 1, 1]}},
            "part_pose_tracks": {"Arm": [
                {"time": 0.0, "position": [0, 0, 0], "rotation": [0, 0, 0], "scale": [1, 1, 1]},
                {"time": 4.0, "position": [0.8, 0, 0], "rotation": [0, 20, 0], "scale": [2, 1, 1]}
            ]}
        }]
    }
    var events: Array = []
    player.animation_frame.connect(func(id: String, index: int, at: float, active: Array):
        events.append({"id": id, "index": index, "time": at, "groups": active}))
    if not player.configure(scene, camera):
        _fail("Exported runtime schema rejected")
        return
    player.bind_model("1", model)
    player.seek(1.0)
    if absf(model.position.x - 1.0) > 0.01:
        _fail("Model root keyframe does not interpolate at 1s")
        return
    if absf(bone.position.x - (0.5 + 0.1 + 0.2)) > 0.01:
        _fail("Static + keyframed arm correction is incorrect")
        return
    if absf(bone.rotation_degrees.y - 15.0) > 0.01:
        _fail("Arm pose rotation incorrectly blended")
        return
    if events.size() != 1 or events[0]["index"] != 2 or events[0]["groups"][0] != "Arm":
        _fail("Animation callback did not receive selected clip and bone mask")
        return
    if absf(float(events[0]["time"]) - 1.0) > 0.01:
        _fail("Clip source time mapping differs from editor")
        return
    player.seek(1.0)
    if absf(bone.position.x - 0.8) > 0.01:
        _fail("Repeated seeking accumulates arm corrections")
        return
    player.seek(3.0)
    if events.size() != 2:
        _fail("Clip callback fired outside source time range")
        return
    if absf(camera.position.z - 5.0) > 0.01 or absf(camera.fov - 39.0) > 0.01:
        _fail("Game runtime camera does not interpolate movement and FOV")
        return
    if absf(model.scale.x - 1.75) > 0.01:
        _fail("Model root scale was not interpolated")
        return
    player.skip(true)
    if player.playing:
        _fail("Skip left cutscene playing")
        return
    if model.position.length() > 0.001 or absf(bone.position.x - 0.5) > 0.001:
        _fail("Skip with restore did not return original game-model transforms")
        return
    print("GAME RUNTIME TEST PASSED: root interpolation, camera FOV, clip callbacks, masked additive poses, deterministic seeking, skip restore")
    quit(0)
