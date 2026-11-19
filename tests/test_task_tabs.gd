extends SceneTree
## Task-based navigation must remain reachable and unclipped on phones.
func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MOVIE TASK TABS FAILED: " + message)
    quit(1)

func _run() -> void:
    var app: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(app)
    await process_frame
    var pages: Dictionary = app.get("category_pages")
    var buttons: Dictionary = app.get("category_buttons")
    var names := ["素材", "変形", "動き", "撮影", "出力"]
    if pages.size() != names.size() or buttons.size() != names.size():
        _fail("Expected five separate task tabs")
        return
    for canvas in [Vector2(320, 640), Vector2(360, 800), Vector2(432, 960)]:
        app.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
        app.size = canvas
        await process_frame
        for name in names:
            app.call("_select_category", name)
            await process_frame
            var visible_count := 0
            for item in names:
                if (pages[item] as Control).visible:
                    visible_count += 1
            if visible_count != 1 or not (pages[name] as Control).visible:
                _fail("Only the active page should occupy space: " + name)
                return
            if not (buttons[name] as Button).button_pressed:
                _fail("Selected page lacks a pressed tab: " + name)
                return
            var r: Rect2 = (buttons[name] as Button).get_global_rect()
            if r.size.x < 44.0 or r.size.y < 44.0 or r.position.x < -1.0 or r.end.x > canvas.x + 1.0:
                _fail("Task tab cannot be tapped at " + str(canvas) + ": " + name)
                return
    app.call("_select_category", "出力")
    var output_page: Control = pages["出力"]
    var labels := ""
    for node in output_page.get_children():
        for child in node.get_children():
            if child is Button:
                labels += child.text + " "
    for required in ["保存", "開く", "Godot出力"]:
        if not labels.contains(required):
            _fail("Output page missing " + required)
            return
    app.call("_toggle_workspace")
    if not (buttons["変形"] as Button).visible:
        _fail("Detailed authoring page is not available")
        return
    app.call("_select_category", "変形")
    if not (pages["変形"] as Control).visible:
        _fail("Detailed transform page cannot be opened")
        return
    print("MOVIE TASK TABS PASSED: five grouped pages, output actions, portrait navigation, authoring tools")
    quit(0)
