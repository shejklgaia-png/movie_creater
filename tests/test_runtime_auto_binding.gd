extends SceneTree
## Roadmap v0.8: bind game models by stable ID, resolve native animations by
## source name, and preserve per-Blockbench-UUID joint masks on seeking.
const Runtime = preload("res://addons/movie_creator_runtime/movie_player.gd")
const Binding = preload("res://addons/movie_creator_runtime/movie_creator_binding.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("RUNTIME AUTO BIND FAILED: " + message)
    quit(1)

func _near(a: float, b: float) -> bool:
    return absf(a - b) < 0.02

func _run() -> void:
    var game := Node3D.new()
    game.name = "Game"
    root.add_child(game)
    var character := Node3D.new()
    character.name = "Character"
    character.set_meta("movie_creator_id", "actor_1")
    game.add_child(character)
    var arm := Node3D.new()
    arm.name = "Arm"
    arm.position = Vector3(0.25, 0.0, 0.0)
    character.add_child(arm)
    var leg := Node3D.new()
    leg.name = "Leg"
    leg.position = Vector3(0.0, 0.3, 0.0)
    character.add_child(leg)
    var animator := AnimationPlayer.new()
    animator.name = "AnimationPlayer"
    character.add_child(animator)
    var library := AnimationLibrary.new()
    var wave := Animation.new()
    wave.length = 2.0
    var arm_track := wave.add_track(Animation.TYPE_POSITION_3D)
    wave.track_set_path(arm_track, NodePath("Arm"))
    wave.position_track_insert_key(arm_track, 0.0, Vector3(0.25, 0.0, 0.0))
    wave.position_track_insert_key(arm_track, 2.0, Vector3(2.25, 0.0, 0.0))
    var leg_track := wave.add_track(Animation.TYPE_POSITION_3D)
    wave.track_set_path(leg_track, NodePath("Leg"))
    wave.position_track_insert_key(leg_track, 0.0, Vector3(0.0, 0.3, 0.0))
    wave.position_track_insert_key(leg_track, 2.0, Vector3(0.0, 2.3, 0.0))
    if library.add_animation("Wave", wave) != OK:
        _fail("Could not construct native test animation")
        return
    if animator.add_animation_library("", library) != OK:
        _fail("Could not bind native animation library")
        return

    var project := {
        "schema": "movie_creator_runtime_v1",
        "duration": 4.0,
        "camera_keys": [],
        "objects": [{
            "id": "actor_1", "keyframes": [],
            "animation_names": ["Wave"],
            "group_paths": {"arm_uuid": "Arm", "leg_uuid": "Leg"},
            "animation_clips": [{
                "uid": "arm_clip", "animation_index": 0, "start": 0.0,
                "in": 0.0, "out": 2.0, "speed": 1.0,
                "enabled_groups": ["arm_uuid"]
            }],
            "part_pose_tracks": {}, "element_offsets": {}
        }]
    }
    var player = Runtime.new()
    game.add_child(player)
    if not player.configure(project):
        _fail("Runtime refused the exported schema")
        return
    var report: Dictionary = player.auto_bind_scene(game)
    if (report["bound"] as Array).size() != 1 or not (report["missing"] as Array).is_empty():
        _fail("Scene ID auto-binding did not find exactly the tagged model")
        return
    player.seek(1.0)
    if not _near(arm.position.x, 1.25):
        _fail("Named native animation did not seek to source time")
        return
    if not _near(leg.position.y, 0.3):
        _fail("Native animation modified a disabled Blockbench joint")
        return
    player.seek(1.0)
    if not _near(arm.position.x, 1.25) or not _near(leg.position.y, 0.3):
        _fail("Repeated native seeking accumulated transforms")
        return
    player.seek(3.0)
    if not _near(arm.position.x, 0.25) or not _near(leg.position.y, 0.3):
        _fail("Native joint did not return to rest after clip end")
        return
    player.seek(2.0)
    player.restore()
    if not _near(arm.position.x, 0.25) or not _near(leg.position.y, 0.3):
        _fail("Restore did not recover the original joint rest pose")
        return

    # Conflicting IDs must be rejected rather than bound by scene order.
    var duplicate := Node3D.new()
    duplicate.name = "Duplicate"
    duplicate.set_meta("movie_creator_id", "actor_1")
    game.add_child(duplicate)
    if Binding.bind(game, "actor_1") != null:
        _fail("Duplicate model IDs were bound ambiguously")
        return
    player.unbind_model("actor_1")
    print("RUNTIME AUTO BIND PASS: explicit IDs, native source-name animations, masked joints, deterministic seek, restore, duplicate rejection")
    quit(0)
