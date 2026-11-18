extends Node3D
## Standalone cutscene playback for Godot 4.x projects.
## A game binds its existing Node3D characters to Movie Creator object IDs.
## No Blockbench meshes are embedded in runtime exports. Animation clips are
## delivered through the animation_frame signal so the game can play them.
##
## Typical setup:
##   var player = preload("res://addons/movie_creator_runtime/movie_player.gd").new()
##   add_child(player)
##   player.configure(JSON.parse_string(FileAccess.get_file_as_string("res://intro.movie.json")), $Camera3D)
##   player.bind_model("1", $BitTaran)
##   player.animation_frame.connect(_apply_movie_animation)
##   player.play()

signal finished
signal animation_frame(model_id: String, animation_index: int, source_time: float, enabled_groups: Array)

const Cuts = preload("res://addons/movie_creator_runtime/camera_cuts.gd")
const Clips = preload("res://addons/movie_creator_runtime/clip_engine.gd")
const Poses = preload("res://addons/movie_creator_runtime/pose_track.gd")
const Binding = preload("res://addons/movie_creator_runtime/movie_creator_binding.gd")

var project: Dictionary = {}
var camera_node: Camera3D
var bound_models: Dictionary = {}
var original_transforms: Dictionary = {}
var part_baselines: Dictionary = {}
var animation_bindings: Dictionary = {}
var time := 0.0
var duration := 0.0
var playing := false

func configure(data: Dictionary, movie_camera: Camera3D = null) -> bool:
    if str(data.get("schema", "")) != "movie_creator_runtime_v1":
        push_warning("Movie Creator: invalid runtime project schema")
        return false
    if not (data.get("objects") is Array):
        return false
    project = data.duplicate(true)
    duration = maxf(0.0, float(project.get("duration", 0.0)))
    camera_node = movie_camera
    time = 0.0
    playing = false
    return true

## Bind all models carrying an explicit movie_creator_id in the supplied scene.
## No name guessing: duplicate or missing IDs are reported, not silently misbound.
func auto_bind_scene(scene_root: Node) -> Dictionary:
    var connected: Array[String] = []
    var missing: Array[String] = []
    for value in project.get("objects", []):
        if not (value is Dictionary):
            continue
        var model_id := str(value.get("id", ""))
        if model_id.is_empty():
            continue
        var node: Node3D = Binding.bind(scene_root, model_id)
        if node == null:
            missing.append(model_id)
            continue
        bind_model(model_id, node)
        connected.append(model_id)
    return {"bound": connected, "missing": missing}

func bind_model(model_id: String, node: Node3D) -> void:
    if bound_models.has(model_id):
        unbind_model(model_id)
    bound_models[model_id] = node
    original_transforms[model_id] = node.transform
    var parts: Dictionary = {}
    var record := _record_for(model_id)
    var selected_paths: Dictionary = {}
    var static_parts: Variant = record.get("element_offsets", {})
    if static_parts is Dictionary:
        for path in static_parts.keys():
            selected_paths[str(path)] = true
    var animated_parts: Variant = record.get("part_pose_tracks", {})
    if animated_parts is Dictionary:
        for path in animated_parts.keys():
            selected_paths[str(path)] = true
    # Native AnimationPlayer tracks must also have rest-pose baselines.
    # Exported group UUID -> NodePath mapping is used for joint masking.
    var group_paths: Dictionary = record.get("group_paths", {})
    for path_value in group_paths.values():
        selected_paths[str(path_value)] = true
    for path in selected_paths.keys():
        var child: Node3D = node.get_node_or_null(NodePath(str(path))) as Node3D
        if child != null:
            parts[path] = {
                "position": child.position,
                "rotation": child.rotation_degrees,
                "scale": child.scale
            }
    part_baselines[model_id] = parts
    var candidates: Array[Node] = node.find_children("*", "AnimationPlayer", true, false)
    if candidates.size() == 1:
        bind_animation_player(model_id, candidates[0] as AnimationPlayer)
    elif candidates.size() > 1:
        push_warning("Movie Creator: multiple AnimationPlayers on '%s'; use bind_animation_player explicitly" % model_id)

## A native AnimationPlayer with matching animation names is sought automatically.
## For unusual scene layouts, bind an AnimationPlayer explicitly instead.
func bind_animation_player(model_id: String, animator: AnimationPlayer) -> bool:
    if animator == null or not bound_models.has(model_id):
        return false
    _release_animation_player(model_id)
    var record: Dictionary = _record_for(model_id)
    var names: Array = record.get("animation_names", [])
    if names.is_empty() and bound_models[model_id].has_meta("movie_creator_animation_names"):
        var named: Variant = bound_models[model_id].get_meta("movie_creator_animation_names")
        if named is Array:
            names = named
    if names.is_empty():
        return false
    animation_bindings[model_id] = {
        "player": animator,
        "names": names.duplicate(),
        "original_mode": animator.callback_mode_process,
        "last_animation": ""
    }
    # Deterministic cutscene seeking: gameplay clock must not independently
    # advance the AnimationPlayer between our explicit sampled frames.
    animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    return true

func _release_animation_player(model_id: String) -> void:
    if not animation_bindings.has(model_id):
        return
    var bound: Dictionary = animation_bindings[model_id]
    var animator: AnimationPlayer = bound["player"]
    if is_instance_valid(animator):
        animator.stop()
        animator.callback_mode_process = int(bound["original_mode"])
    animation_bindings.erase(model_id)

func _resolve_native_animation(animator: AnimationPlayer, wanted: String) -> String:
    if animator.has_animation(wanted):
        return wanted
    var matches: Array[String] = []
    for name_value in animator.get_animation_list():
        var name := str(name_value)
        if name.get_file() == wanted:
            matches.append(name)
    return matches[0] if matches.size() == 1 else ""

func _apply_native_animation(model_id: String, record: Dictionary, active: Dictionary) -> void:
    if not animation_bindings.has(model_id):
        return
    var binding: Dictionary = animation_bindings[model_id]
    var animator: AnimationPlayer = binding["player"]
    if not is_instance_valid(animator):
        animation_bindings.erase(model_id)
        return
    if active.is_empty():
        if str(binding["last_animation"]) != "":
            animator.stop(true)
            binding["last_animation"] = ""
            animation_bindings[model_id] = binding
        return
    var index := int(active.get("animation_index", -1))
    var names: Array = binding["names"]
    if index < 0 or index >= names.size():
        return
    var selected := _resolve_native_animation(animator, str(names[index]))
    if selected.is_empty():
        return # Keep the signal-driven adapter fallback intact.
    var group_paths: Dictionary = record.get("group_paths", {})
    var enabled: Variant = active.get("enabled_groups", null)
    # A masked clip without UUID-to-node paths cannot be reproduced safely.
    if enabled is Array and group_paths.is_empty() and not enabled.is_empty():
        return
    if str(binding["last_animation"]) != selected:
        animator.play(selected)
    var source_time := Clips.source_time(active, time)
    var animation: Animation = animator.get_animation(selected)
    animator.seek(clampf(source_time, 0.0, animation.length), true, true)
    binding["last_animation"] = selected
    animation_bindings[model_id] = binding
    if enabled is Array:
        var model: Node3D = bound_models[model_id]
        var baselines: Dictionary = part_baselines.get(model_id, {})
        for group_value in group_paths.keys():
            if enabled.has(str(group_value)):
                continue
            var path := str(group_paths[group_value])
            if not baselines.has(path):
                continue
            var part: Node3D = model.get_node_or_null(NodePath(path)) as Node3D
            if part == null:
                continue
            var base: Dictionary = baselines[path]
            part.position = base["position"]
            part.rotation_degrees = base["rotation"]
            part.scale = base["scale"]

func unbind_model(model_id: String) -> void:
    _release_animation_player(model_id)
    bound_models.erase(model_id)
    original_transforms.erase(model_id)
    part_baselines.erase(model_id)

func _process(delta: float) -> void:
    if not playing:
        return
    seek(minf(duration, time + delta))
    if time >= duration:
        playing = false
        finished.emit()

func play(from_time: float = -1.0) -> void:
    if from_time >= 0.0:
        seek(from_time)
    playing = true

func pause() -> void:
    playing = false

func skip(restore_scene: bool = false) -> void:
    seek(duration)
    playing = false
    finished.emit()
    if restore_scene:
        restore()

func restore() -> void:
    playing = false
    for model_id in animation_bindings.keys():
        var binding: Dictionary = animation_bindings[model_id]
        var animator: AnimationPlayer = binding["player"]
        if is_instance_valid(animator):
            animator.stop(true)
        binding["last_animation"] = ""
        animation_bindings[model_id] = binding
    for model_id in bound_models.keys():
        var node: Node3D = bound_models[model_id]
        if not is_instance_valid(node):
            continue
        node.transform = original_transforms.get(model_id, node.transform)
        for path_value in (part_baselines.get(model_id, {}) as Dictionary).keys():
            var path := str(path_value)
            var child: Node3D = node.get_node_or_null(NodePath(path)) as Node3D
            if child == null:
                continue
            var base: Dictionary = part_baselines[model_id][path]
            child.position = base["position"]
            child.rotation_degrees = base["rotation"]
            child.scale = base["scale"]

func seek(seconds: float) -> void:
    if project.is_empty():
        return
    time = clampf(seconds, 0.0, duration)
    var records: Array = project.get("objects", [])
    for value in records:
        if not (value is Dictionary):
            continue
        var record: Dictionary = value
        var model_id := str(record.get("id", ""))
        if not bound_models.has(model_id):
            continue
        var node: Node3D = bound_models[model_id]
        if not is_instance_valid(node):
            continue
        var root_keys: Array = record.get("keyframes", [])
        var root_pose := _sample_root_keys(root_keys, time)
        if not root_pose.is_empty():
            node.position = root_pose["position"]
            node.quaternion = root_pose["rotation"]
            node.scale = root_pose["scale"]

        # Restore the baseline BEFORE external animation or additive pose
        # overrides. Seeking 100 times to the same time is deterministic.
        var bases: Dictionary = part_baselines.get(model_id, {})
        for path_value in bases.keys():
            var path := str(path_value)
            var child: Node3D = node.get_node_or_null(NodePath(path)) as Node3D
            if child == null:
                continue
            var base: Dictionary = bases[path]
            child.position = base["position"]
            child.rotation_degrees = base["rotation"]
            child.scale = base["scale"]

        var active: Dictionary = Clips.active_clip(record.get("animation_clips", []), time)
        _apply_native_animation(model_id, record, active)
        if not active.is_empty():
            var included: Array = active.get("enabled_groups", [])
            animation_frame.emit(model_id, int(active.get("animation_index", -1)),
                Clips.source_time(active, time), included.duplicate())

        var correction_paths: Dictionary = {}
        var offsets: Dictionary = record.get("element_offsets", {})
        var pose_tracks: Dictionary = record.get("part_pose_tracks", {})
        for path in offsets.keys():
            correction_paths[str(path)] = true
        for path in pose_tracks.keys():
            correction_paths[str(path)] = true
        for path in correction_paths.keys():
            var child: Node3D = node.get_node_or_null(NodePath(str(path))) as Node3D
            if child == null:
                continue
            var static_offset: Dictionary = offsets.get(path, Poses.identity())
            var pose_keys: Array = pose_tracks.get(path, [])
            var combined: Dictionary = Poses.combine(static_offset, Poses.sample(pose_keys, time))
            child.position += Poses.vector(combined["position"])
            child.rotation_degrees += Poses.vector(combined["rotation"])
            child.scale *= Poses.vector(combined["scale"], Vector3.ONE)

    if camera_node != null and is_instance_valid(camera_node):
        var cuts: Array = project.get("camera_cuts", [])
        var camera_id := Cuts.active_camera(cuts, time)
        var cameras: Dictionary = project.get("camera_tracks", {})
        var keys: Array = project.get("camera_keys", []) if camera_id == "camera_1" else cameras.get(camera_id, [])
        var sample: Dictionary = Cuts.sample_keys(keys, time)
        if not sample.is_empty():
            camera_node.position = sample["position"]
            camera_node.quaternion = sample["orientation"]
            camera_node.fov = float(sample["fov"])

func _exit_tree() -> void:
    for model_id in animation_bindings.keys():
        _release_animation_player(str(model_id))

func _record_for(id: String) -> Dictionary:
    for record in project.get("objects", []):
        if record is Dictionary and str(record.get("id", "")) == id:
            return record
    return {}

func _sample_root_keys(keys: Array, seconds: float) -> Dictionary:
    if keys.is_empty():
        return {}
    var a: Dictionary = keys[0]
    var b: Dictionary = keys[keys.size() - 1]
    if seconds <= float(a.get("time", 0.0)):
        b = a
    elif seconds >= float(b.get("time", 0.0)):
        a = b
    else:
        for i in range(keys.size() - 1):
            var candidate_a: Dictionary = keys[i]
            var candidate_b: Dictionary = keys[i + 1]
            if seconds >= float(candidate_a["time"]) and seconds <= float(candidate_b["time"]):
                a = candidate_a
                b = candidate_b
                break
    var first_time := float(a.get("time", 0.0))
    var last_time := float(b.get("time", first_time))
    var alpha := 0.0 if absf(last_time - first_time) < 0.00001 else clampf((seconds - first_time) / (last_time - first_time), 0.0, 1.0)
    var pos0 := Poses.vector(a.get("position", []))
    var pos1 := Poses.vector(b.get("position", []))
    var rot0 := Poses.vector(a.get("rotation", []))
    var rot1 := Poses.vector(b.get("rotation", []))
    var basis_a := Basis.from_euler(Vector3(deg_to_rad(rot0.x), deg_to_rad(rot0.y), deg_to_rad(rot0.z)), EULER_ORDER_YXZ)
    var basis_b := Basis.from_euler(Vector3(deg_to_rad(rot1.x), deg_to_rad(rot1.y), deg_to_rad(rot1.z)), EULER_ORDER_YXZ)
    return {
        "position": pos0.lerp(pos1, alpha),
        "rotation": Quaternion(basis_a).slerp(Quaternion(basis_b), alpha),
        "scale": Poses.vector(a.get("scale", []), Vector3.ONE).lerp(
            Poses.vector(b.get("scale", []), Vector3.ONE), alpha)
    }
