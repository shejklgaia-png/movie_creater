extends Node3D
## Touch-friendly 3-axis gizmo. World-axis guides remain a constant on-screen
## size as the editor camera zooms. Axis lines are drawn over model geometry.

const COLORS := [Color("#ff7878"), Color("#78e4a1"), Color("#80b9ff")]
var mode := 0 # 0 move, 1 rotate, 2 scale, 3 select

func _ready() -> void:
    set_mode(0)

func set_mode(value: int) -> void:
    mode = value
    for child in get_children():
        remove_child(child)
        child.queue_free()
    if mode == 3:
        return
    for axis in range(3):
        var mesh := ImmediateMesh.new()
        mesh.surface_begin(Mesh.PRIMITIVE_LINES)
        if mode == 1:
            _add_rotation_ring(mesh, axis)
        else:
            _add_axis_line(mesh, axis)
        mesh.surface_end()
        var visual := MeshInstance3D.new()
        visual.name = ["X", "Y", "Z"][axis]
        visual.mesh = mesh
        var mat := StandardMaterial3D.new()
        mat.albedo_color = COLORS[axis]
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.no_depth_test = true
        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        visual.material_override = mat
        add_child(visual)

func _basis_axis(axis: int) -> Vector3:
    match axis:
        0: return Vector3.RIGHT
        1: return Vector3.UP
        _: return Vector3.BACK

func _add_axis_line(mesh: ImmediateMesh, axis: int) -> void:
    var vec := _basis_axis(axis)
    mesh.surface_add_vertex(Vector3.ZERO)
    mesh.surface_add_vertex(vec * 1.15)
    if mode == 0:
        for lateral in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
            if lateral == vec:
                continue
            mesh.surface_add_vertex(vec * 1.15)
            mesh.surface_add_vertex(vec * 0.94 + lateral * 0.09)
            mesh.surface_add_vertex(vec * 1.15)
            mesh.surface_add_vertex(vec * 0.94 - lateral * 0.09)
    else:
        for transverse in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
            if transverse == vec:
                continue
            mesh.surface_add_vertex(vec * 1.03 - transverse * 0.11)
            mesh.surface_add_vertex(vec * 1.03 + transverse * 0.11)

func _add_rotation_ring(mesh: ImmediateMesh, axis: int) -> void:
    for index in range(48):
        var angle_a := TAU * float(index) / 48.0
        var angle_b := TAU * float(index + 1) / 48.0
        mesh.surface_add_vertex(_circle_point(axis, angle_a))
        mesh.surface_add_vertex(_circle_point(axis, angle_b))

func _circle_point(axis: int, angle: float) -> Vector3:
    match axis:
        0: return Vector3(0.0, cos(angle), sin(angle))
        1: return Vector3(cos(angle), 0.0, sin(angle))
        _: return Vector3(cos(angle), sin(angle), 0.0)

func _pixel_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var segment := b - a
    var length_sq := segment.length_squared()
    if length_sq <= 0.0001:
        return p.distance_to(a)
    var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
    return p.distance_to(a + segment * t)

func pick_axis(pixel: Vector2, camera: Camera3D) -> int:
    if not visible or mode == 3:
        return 0
    var best := 20.0
    var axis_result := 0
    var center := camera.unproject_position(global_position)
    # Never steal a normal object tap near the common axis pivot. Fingers
    # must grab the OUTER half of a handle to activate an axis constraint.
    if pixel.distance_to(center) < 26.0:
        return 0
    for axis in range(3):
        var distance := INF
        if mode == 1:
            for step in range(48):
                var a := camera.unproject_position(global_transform * _circle_point(axis, TAU * float(step) / 48.0))
                var b := camera.unproject_position(global_transform * _circle_point(axis, TAU * float(step + 1) / 48.0))
                distance = minf(distance, _pixel_to_segment(pixel, a, b))
        else:
            var end := camera.unproject_position(global_transform * (_basis_axis(axis) * 1.15))
            var start: Vector2 = center.lerp(end, 0.45)
            distance = _pixel_to_segment(pixel, start, end)
        if distance < best:
            best = distance
            axis_result = axis + 1 # move/rotate/scale axis selector index
    return axis_result
