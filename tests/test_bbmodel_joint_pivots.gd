extends SceneTree
## .bbmodel folder hierarchy must remain a genuine, editable articulated rig:
## every Blockbench group stores a stable ID/pivot, selecting a child mesh in
## rotate mode resolves to its owning folder joint, and the entire subtree
## rotates around the joint without translating its pivot or a parent bone.
func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("BBMODEL JOINT PIVOT FAILED: " + reason)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    var source := FileAccess.get_file_as_string("res://tests/fixtures/simple_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Joint Hierarchy"):
        _fail("Could not import group fixture")
        return
    var model_id: String = editor.get("selected_id")
    var asset: Dictionary = (editor.get("bb_assets") as Dictionary)[model_id]
    var root_node: Node3D = (editor.get("objects_by_id") as Dictionary)[model_id]
    var joints: Dictionary = asset.get("joints", {})
    if not joints.has("body") or not joints.has("arm"):
        _fail("Blockbench joint IDs are not retained in imported asset")
        return
    var body: Node3D = asset["groups"]["body"]["node"]
    var arm: Node3D = asset["groups"]["arm"]["node"]
    var cube: Node3D = arm.get_node_or_null("arm")
    if cube == null or cube.get_parent() != arm or arm.get_parent() != body:
        _fail("Folder-to-joint parent/child hierarchy is broken")
        return
    var arm_info: Dictionary = joints["arm"]
    if str(arm_info.get("parent_uuid", "")) != "body" or not (arm_info.get("origin", []) is Array):
        _fail("Joint parent UUID and source pivot not preserved")
        return
    if str(arm.get_meta("bb_joint_uuid", "")) != "arm":
        _fail("Joint marker is missing from the actual pivot node")
        return
    var origin: Array = arm_info["origin"]
    if origin != [16, 12, 8]:
        _fail("Blockbench joint pivot coordinates changed: " + str(origin))
        return
    if arm.position.distance_to(Vector3(0.5, 0.25, 0.0)) > 0.00001:
        _fail("Joint pivot is not parent-relative")
        return
    if str(arm_info.get("path", "")) != str(root_node.get_path_to(arm)):
        _fail("Stable folder path is not preserved")
        return

    # The hierarchy list includes distinguished joint labels; groups are not
    # flattened into individual geometry in the picker.
    editor.call("_open_part_picker")
    var picker: VBoxContainer = editor.get("picker_list")
    var found_joint := false
    for child in picker.get_children():
        if child is Button and child.text.contains("関節") and child.text.contains("Arm"):
            found_joint = true
    editor.call("_close_picker")
    if not found_joint:
        _fail("Part hierarchy does not distinguish a joint folder")
        return

    # Existing mesh-only editing must remain available for moving a part.
    var mesh_path := str(root_node.get_path_to(cube))
    editor.call("_set_transform_mode", 0)
    editor.call("_set_part_selection", model_id, mesh_path)
    if editor.call("_get_selected_target") != cube:
        _fail("Move mode should still be able to select the child mesh itself")
        return

    # Switching to rotate must use the closest ancestor folder joint, not the
    # mesh element origin. The gizmo follows that joint pivot.
    editor.call("_set_transform_mode", 1)
    if editor.call("_get_selected_target") != arm:
        _fail("Rotation mode did not resolve selected mesh to parent joint")
        return
    if str(editor.get("selected_part_path")) != str(root_node.get_path_to(arm)):
        _fail("Rotation selection path differs from the joint folder path")
        return
    var gizmo: Node3D = editor.get("gizmo")
    if gizmo.global_position.distance_to(arm.global_position) > 0.01:
        _fail("Rotation ring is not centered on the Blockbench joint pivot")
        return
    editor.call("_seek", 0.0)
    var body_before := body.global_transform
    var joint_before := arm.global_position
    var child_before := cube.global_position
    var initial_rotation := arm.rotation_degrees
    editor.set("drag_target_node", arm)
    editor.set("drag_rotation_start", initial_rotation)
    editor.set("drag_handle_axis", 2)
    editor.set("pointer_origin", Vector2(100, 200))
    editor.call("_apply_model_drag", Vector2(190, 200))
    var child_after := cube.global_position
    if absf(arm.rotation_degrees.y - initial_rotation.y) < 40.0:
        _fail("Touch rotation did not turn the joint")
        return
    if joint_before.distance_to(arm.global_position) > 0.001:
        _fail("Joint pivot translated during rotation")
        return
    if child_before.distance_to(child_after) < 0.05:
        _fail("Rotating joint did not bend its child mesh")
        return
    if (body.global_transform.origin - body_before.origin).length() > 0.001:
        _fail("Parent folder shifted when rotating child joint")
        return
    editor.call("_commit_part_edit", arm, arm.position, initial_rotation, arm.scale,
        editor.call("_get_part_offset", model_id, str(root_node.get_path_to(arm))))
    editor.call("_seek", 0.0)
    if absf(arm.rotation_degrees.y - initial_rotation.y) < 40.0:
        _fail("Manual joint rotation did not persist after timeline evaluation")
        return

    var saved: Dictionary = editor.call("_serialize_project")
    var stored := false
    for record in saved["objects"]:
        if str(record.get("id", "")) == model_id:
            var saved_joints: Dictionary = record.get("joint_hierarchy", {})
            if not saved_joints.has("arm") or str(saved_joints["arm"].get("parent_uuid", "")) != "body":
                _fail("Saved project lost .bbmodel folder joint metadata")
                return
            stored = true
    if not stored:
        _fail("Imported model absent from project export")
        return
    editor.call("_save_project")
    editor.call("_load_project")
    editor.call("_seek", 0.0)
    var restored_asset: Dictionary = (editor.get("bb_assets") as Dictionary).get(model_id, {})
    if not (restored_asset.get("joints", {}) as Dictionary).has("arm"):
        _fail("Joint hierarchy was lost on reopening project")
        return
    var restored_arm: Node3D = restored_asset["groups"]["arm"]["node"]
    if not restored_arm.has_meta("bb_joint_uuid") or str(restored_arm.get_meta("bb_joint_uuid")) != "arm":
        _fail("Restored joint no longer retains its UUID")
        return
    if absf(restored_arm.rotation_degrees.y - initial_rotation.y) < 40.0:
        _fail("Joint bend disappeared after reopening")
        return
    print("BBMODEL JOINT PIVOT PASSED: folder UUIDs, parent pivots, closest-joint rotate, subtree bend, selected hierarchy, project reload")
    quit(0)
