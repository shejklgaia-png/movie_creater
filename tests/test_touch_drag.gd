extends SceneTree
## Validate scene selection, direct manipulation, and automatic keyframe capture.

func _initialize() -> void:
    call_deferred("_run_test")

func _fail(message: String) -> void:
    push_error("TOUCH TEST FAILED: " + message)
    quit(1)

func _run_test() -> void:
    var scene: PackedScene = load("res://scenes/editor.tscn")
    var editor: Control = scene.instantiate()
    root.add_child(editor)
    await process_frame
    await physics_frame
    await physics_frame

    # Explicit test fixture: the end-user UI no longer creates demo shapes.
    editor.call("_new_project")
    editor.call("_add_object", "box")
    await process_frame
    await physics_frame
    var objects: Dictionary = editor.get("objects_by_id")
    if not objects.has("1"):
        _fail("Could not create isolated drag test fixture")
        return
    var node: Node3D = objects["1"]
    var camera: Camera3D = editor.get("editor_camera")
    var viewport: SubViewport = editor.get("preview")
    var container: SubViewportContainer = editor.get("preview_box")
    if container.size.x < 1.0 or container.size.y < 1.0:
        _fail("Preview has no screen space")
        return

    editor.call("_seek", 4.0)
    var start: Vector2 = camera.unproject_position(node.global_position) * container.size / Vector2(viewport.size)
    var finish: Vector2 = start + Vector2(55, 25)
    var previous_position: Vector3 = node.position
    editor.call("_begin_pointer", start)
    var dragging_id: String = editor.get("drag_target_id")
    if dragging_id != "1":
        _fail("Tapping object did not select the correct model: " + dragging_id)
        return
    editor.call("_move_pointer", finish)
    editor.call("_finish_pointer", finish)
    if node.position.distance_to(previous_position) < 0.05:
        _fail("Dragging did not move the selected object")
        return

    var tracks: Dictionary = editor.get("tracks")
    var keys: Array = tracks["1"]
    if keys.size() != 2:
        _fail("Dragging did not create a keyframe at 4 seconds")
        return

    editor.call("_cycle_mode")
    editor.call("_seek", 7.0)
    start = camera.unproject_position(node.global_position) * container.size / Vector2(viewport.size)
    finish = start + Vector2(60, 0)
    var previous_rotation: Vector3 = node.rotation_degrees
    editor.call("_begin_pointer", start)
    editor.call("_move_pointer", finish)
    editor.call("_finish_pointer", finish)
    if absf(node.rotation_degrees.y - previous_rotation.y) < 1.0:
        _fail("Rotation drag did not rotate the selected object")
        return
    keys = (editor.get("tracks") as Dictionary)["1"]
    if keys.size() != 3:
        _fail("Rotation drag did not create a second keyframe")
        return

    print("TOUCH TEST PASSED: selection, position drag, rotation drag, automatic keyframes")
    quit(0)
