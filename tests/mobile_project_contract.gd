extends SceneTree

# Android portrait / touch configuration regression.
# Run: godot --headless --path . --script res://tests/mobile_project_contract.gd
func _initialize() -> void:
    var failures: Array[String] = []
    var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
    var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
    if width <= 0 or height <= width:
        failures.append("Viewport must be portrait and have positive dimensions")
    if int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) != 1:
        failures.append("Android orientation must be portrait (1)")
    var renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
    if renderer != "gl_compatibility":
        failures.append("Expected GL Compatibility renderer for Android support")
    var scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
    if scene.is_empty() or not ResourceLoader.exists(scene):
        failures.append("Main scene missing: " + scene)
    var parent := Node3D.new()
    var child := Node3D.new()
    get_root().add_child(parent)
    parent.add_child(child)
    parent.position = Vector3(2, 3, 4)
    parent.rotation = Vector3(0, PI / 3.0, 0)
    child.position = Vector3(1, 0, -2)
    var expected := parent.global_transform * child.transform
    if child.global_transform.origin.distance_to(expected.origin) > 0.0001:
        failures.append("Parent-child global transform mismatch")
    parent.queue_free()
    if failures.is_empty():
        print("PASS: mobile project and transform contract")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)
