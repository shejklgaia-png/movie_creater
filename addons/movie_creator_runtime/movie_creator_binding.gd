extends RefCounted
class_name MovieCreatorBinding

## Runtime-side binding for Movie Creator JSON object IDs.
## Explicit IDs take priority over names to avoid accidentally binding duplicate models.
static func index_scene(root: Node) -> Dictionary:
	var result: Dictionary = {}
	_visit(root, result)
	return result

static func _visit(node: Node, result: Dictionary) -> void:
	if node is Node3D:
		var object_id := str(node.get_meta("movie_creator_id", ""))
		if not object_id.is_empty() and not result.has(object_id):
			result[object_id] = node
	for child in node.get_children():
		_visit(child, result)

static func bind(root: Node, object_id: String, explicit_path: NodePath = NodePath("")) -> Node3D:
	if not str(explicit_path).is_empty():
		var explicit_node := root.get_node_or_null(explicit_path)
		if explicit_node is Node3D:
			return explicit_node
	var matches: Dictionary = index_scene(root)
	return matches.get(object_id) as Node3D

## All values are Godot local-space transforms, never global-space offsets.
## Return false rather than silently applying a malformed transform.
static func apply_local(node: Node3D, position: Array, rotation_xyzw: Array, scale_xyz: Array) -> bool:
	if node == null or position.size() != 3 or rotation_xyzw.size() != 4 or scale_xyz.size() != 3:
		return false
	for value in position + rotation_xyzw + scale_xyz:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	var q := Quaternion(float(rotation_xyzw[0]), float(rotation_xyzw[1]), float(rotation_xyzw[2]), float(rotation_xyzw[3]))
	if q.length_squared() < 0.000001:
		return false
	node.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	node.quaternion = q.normalized()
	node.scale = Vector3(float(scale_xyz[0]), float(scale_xyz[1]), float(scale_xyz[2]))
	return true
