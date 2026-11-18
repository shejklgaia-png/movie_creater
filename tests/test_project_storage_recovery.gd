extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var save_path := "user://movie_storage_regression.json"
	var backup_path := "user://movie_storage_regression.backup.json"
	var temp_path := "user://movie_storage_regression.tmp.json"
	for path in [save_path, backup_path, temp_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var first := JSON.stringify({"version": 5, "objects": [{"id": "1", "keyframes": []}], "duration": 10})
	var second := JSON.stringify({"version": 5, "objects": [{"id": "2", "keyframes": []}], "duration": 20})
	var third := JSON.stringify({"version": 5, "objects": [{"id": "3", "keyframes": []}], "duration": 30})
	if not MovieProjectStorage.write_safe(first, save_path, backup_path, temp_path):
		_fail("first save failed")
		return
	if not MovieProjectStorage.write_safe(second, save_path, backup_path, temp_path):
		_fail("second save failed")
		return
	var backup := MovieProjectStorage.read_valid(backup_path)
	if not bool(backup.get("ok", false)) or str(backup.get("text", "")) != first:
		_fail("backup did not preserve previous valid project")
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string("{broken JSON")
	file.close()
	var recovered := MovieProjectStorage.read_with_backup(save_path, backup_path)
	if not bool(recovered.get("ok", false)) or not bool(recovered.get("recovered", false)) or str(recovered.get("text", "")) != first:
		_fail("invalid primary did not recover last valid backup")
		return
	if not MovieProjectStorage.write_safe(third, save_path, backup_path, temp_path):
		_fail("saving after primary corruption failed")
		return
	if str(MovieProjectStorage.read_valid(backup_path).get("text", "")) != first:
		_fail("corrupted primary erased the good backup")
		return
	if str(MovieProjectStorage.read_valid(save_path).get("text", "")) != third:
		_fail("new primary was not committed")
		return
	if MovieProjectStorage.write_safe("{invalid", save_path, backup_path, temp_path):
		_fail("invalid data was accepted")
		return
	if str(MovieProjectStorage.read_valid(save_path).get("text", "")) != third:
		_fail("invalid write modified primary")
		return
	DirAccess.remove_absolute(save_path)
	var backup_only := MovieProjectStorage.read_with_backup(save_path, backup_path)
	if not bool(backup_only.get("ok", false)) or not bool(backup_only.get("recovered", false)):
		_fail("missing primary did not recover backup")
		return
	for path in [save_path, backup_path, temp_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("MOVIE STORAGE RECOVERY PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
