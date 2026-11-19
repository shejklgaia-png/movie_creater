extends SceneTree
## Screenshot-based usability contract: active tabs must visually join their
## content panel, inactive tabs must recede without becoming unreadable,
## operation modes and preview modes must expose persistent selection.
func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("VISUAL HIERARCHY TEST FAILED: " + reason)
    quit(1)

func _style(control: Control, name: String = "normal") -> StyleBoxFlat:
    return control.get_theme_stylebox(name) as StyleBoxFlat

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    await process_frame
    await process_frame
    var tabs: Dictionary = editor.get("category_buttons")
    var panel: PanelContainer = editor.get("category_panel")
    if panel == null or _style(panel, "panel") == null:
        _fail("Category content has no visible connected surface")
        return
    var panel_color: Color = _style(panel, "panel").bg_color
    var expected_order := ["素材", "変形", "動き", "撮影", "出力"]
    editor.call("_toggle_workspace")
    for screen in [Vector2(320, 640), Vector2(360, 800), Vector2(432, 960)]:
        editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
        editor.size = screen
        await process_frame
        for current in expected_order:
            editor.call("_select_category", current)
            await process_frame
            var active: Button = tabs[current]
            if not active.button_pressed:
                _fail("Category selection not reflected by toggle state: " + current)
                return
            if _style(active) == null or not _style(active).bg_color.is_equal_approx(panel_color):
                _fail("Selected tab background differs from panel: " + current)
                return
            if absf(active.get_global_rect().end.y - panel.get_global_rect().position.y) > 1.1:
                _fail("A gap separates active tab from its content surface")
                return
            var dim_count := 0
            for key in expected_order:
                var other: Button = tabs[key]
                if key == current:
                    continue
                if other.button_pressed:
                    _fail("Multiple tabs appear active")
                    return
                if _style(other) == null or _style(other).bg_color.is_equal_approx(panel_color):
                    _fail("Inactive tab has same background as panel: " + key)
                    return
                if other.get_theme_color("font_color").is_equal_approx(active.get_theme_color("font_color")):
                    _fail("Inactive tab is not visually de-emphasized: " + key)
                    return
                dim_count += 1
            if dim_count != 4:
                _fail("Missing inactive tab choices")
                return
            for button in tabs.values():
                if not (button as Button).visible:
                    continue
                var box := (button as Button).get_global_rect()
                if box.position.x < -1.0 or box.end.x > screen.x + 1.0 or box.size.y < 44.0:
                    _fail("Tabs overflow or lost their touch targets: " + str(screen))
                    return

    var modes: Array = editor.get("transform_buttons")
    for mode_index in [3, 0, 1, 2]:
        editor.call("_set_transform_mode", mode_index)
        for button_index in range(modes.size()):
            var button: Button = modes[button_index]
            var selected: bool = [3, 0, 1, 2][button_index] == mode_index
            if button.button_pressed != selected:
                _fail("Transform mode does not expose selected state")
                return
    var camera_button: Button = editor.get("camera_view_button")
    if camera_button.button_pressed:
        _fail("Camera toggle defaults to shot mode")
        return
    editor.call("_toggle_camera_view")
    if not camera_button.button_pressed:
        _fail("Camera mode does not show selected state")
        return
    editor.call("_toggle_camera_view")
    if camera_button.button_pressed:
        _fail("Camera mode did not restore inactive styling")
        return

    var menu_button: Button = editor.get("file_menu_button")
    var file_popup: PopupPanel = editor.get("file_menu")
    var menu_scroll: ScrollContainer = file_popup.find_child("FileMenuScroll", true, false)
    if menu_button == null or menu_scroll == null:
        _fail("The file menu or its scrollable grouped actions is absent")
        return
    editor.call("_open_file_menu")
    await process_frame
    if not menu_button.button_pressed:
        _fail("Open file menu is not visually marked in the header")
        return
    file_popup.hide()
    await process_frame
    if menu_button.button_pressed:
        _fail("Closing file menu leaves header control selected")
        return

    var picker: Control = editor.get("picker_overlay")
    var inspector: Control = editor.get("clip_overlay")
    var properties: Control = editor.get("transform_overlay")
    for overlay in [picker, inspector, properties]:
        var sheet: PanelContainer = overlay.get_child(2) as PanelContainer
        if sheet == null or _style(sheet, "panel") == null:
            _fail("Overlay sheet is not a visually distinct surface")
            return
        if _style(sheet, "panel").bg_color.is_equal_approx(Color.BLACK):
            _fail("Overlay sheet uses an unstyled default surface")
            return
    print("VISUAL HIERARCHY PASSED: connected active tab/page, muted inactive tabs, mode states, styled sheets, 320-432px reachability")
    quit(0)
