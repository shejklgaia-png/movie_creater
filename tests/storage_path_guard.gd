extends SceneTree

func _initialize() -> void:
	var path := "user://storage_guard.json"
	var payload := '{"version":6,"objects":[]}'
	var existing := FileAccess.open(path, FileAccess.WRITE)
	assert(existing != null)
	existing.store_string(payload)
	existing.close()
	assert(not MovieProjectStorage.write_safe(payload, path, path, path + ".tmp"))
	assert(not MovieProjectStorage.write_safe(payload, path, path + ".backup", path))
	assert(not MovieProjectStorage.write_safe(payload, path, path + ".backup", path + ".backup"))
	assert(MovieProjectStorage.read_valid(path).get("ok", false))
	assert(MovieProjectStorage.read_valid(path).get("text", "") == payload)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)
