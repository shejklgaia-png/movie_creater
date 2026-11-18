extends RefCounted
class_name MovieProjectStorage

## Persistent JSON should never replace the only known-good backup with corrupt data.
## A bad primary file is read-only until the next explicit save; its backup is retained.

static func valid_source(source: String) -> bool:
	var data: Variant = JSON.parse_string(source)
	if not (data is Dictionary):
		return false
	if int(data.get("version", -1)) not in [1, 2, 3, 4, 5]:
		return false
	if not (data.get("objects", null) is Array):
		return false
	for entry in data["objects"]:
		if not (entry is Dictionary):
			return false
		if not (entry.get("keyframes", []) is Array):
			return false
	return true

static func read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var source := file.get_as_text()
	file.close()
	return {"ok": true, "text": source} if valid_source(source) else {"ok": false}

static func read_with_backup(save_path: String, backup_path: String) -> Dictionary:
	var primary := read_valid(save_path)
	if bool(primary.get("ok", false)):
		primary["recovered"] = false
		return primary
	var backup := read_valid(backup_path)
	if bool(backup.get("ok", false)):
		backup["recovered"] = true
		return backup
	return {"ok": false, "recovered": false}

static func write_safe(source: String, save_path: String, backup_path: String, temp_path: String) -> bool:
	if not valid_source(source):
		return false
	var staging := FileAccess.open(temp_path, FileAccess.WRITE)
	if staging == null:
		return false
	staging.store_string(source)
	staging.flush()
	staging.close()
	# Verify the staged payload before making any changes to the existing save.
	var staged := read_valid(temp_path)
	if not bool(staged.get("ok", false)) or str(staged.get("text", "")) != source:
		return false
	# Keep a valid older backup if the current primary is corrupted.
	if bool(read_valid(save_path).get("ok", false)):
		if DirAccess.copy_absolute(save_path, backup_path) != OK:
			return false
	var error := DirAccess.rename_absolute(temp_path, save_path)
	if error != OK:
		# Some Android filesystems do not support rename-over-existing.
		error = DirAccess.copy_absolute(temp_path, save_path)
		if error == OK:
			DirAccess.remove_absolute(temp_path)
	return error == OK and bool(read_valid(save_path).get("ok", false))
