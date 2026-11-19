extends SceneTree
## Android regression: ruler/empty-space horizontal swipes scroll time,
## while a tap seeks and vertical track scrolling and clip drags stay separate.

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TIMELINE HORIZONTAL PAN FAILED: " + message)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    editor.size = Vector2(320, 640)
    await process_frame
    await process_frame

    var timeline: Control = editor.get("timeline")
    if timeline.zoom < 2.9 or timeline._view_span() > 5.1:
        _fail("15-second project must initially expose a readable, horizontally pannable ~5-second window")
        return
    editor.call("_seek", 1.25)
    var before_time: float = editor.get("current_time")
    timeline._start_interaction(Vector2(185, 10))
    if absf(float(editor.get("current_time")) - before_time) > 0.001:
        _fail("Touch-down on ruler moved playhead before deciding tap vs pan")
        return
    timeline._move_interaction(Vector2(155, 10), Vector2(-30, 0), true)
    var first: float = timeline.view_start
    # Simulate local coordinates jumping as scroll/layout recomputes: use only
    # the physical screen-relative delta, not the local position difference.
    timeline._move_interaction(Vector2(175, 10), Vector2(-24, 0), true)
    var second: float = timeline.view_start
    if first <= 0.0 or second <= first:
        _fail("Dragging ruler left did not advance horizontal view: %s %s" % [first, second])
        return
    if absf(float(editor.get("current_time")) - before_time) > 0.001:
        _fail("Horizontal pan changed playhead")
        return
    timeline._finish_interaction(Vector2(175, 10))

    timeline._start_interaction(Vector2(160, 25))
    timeline._move_interaction(Vector2(195, 25), Vector2(35, 0), true)
    if timeline.view_start >= second:
        _fail("Dragging empty header right did not move timeline backward")
        return
    timeline._finish_interaction(Vector2(195, 25))
    timeline.pan_time(-100.0)
    if absf(float(timeline.view_start)) > 0.001:
        _fail("Horizontal time pan did not clamp to zero")
        return

    var header_title: Label = editor.find_child("AppTitle", true, false)
    var menu_button: Button = editor.find_child("FileMenuButton", true, false)
    if header_title == null or menu_button == null:
        _fail("Compact, accessible mobile app title and file menu are absent")
        return
    for element in [header_title, menu_button]:
        var rect: Rect2 = (element as Control).get_global_rect()
        if rect.position.x < -1.0 or rect.end.x > 321.0:
            _fail("Header clipped on 320px phone: " + str(rect))
            return
    if menu_button.size.x < 44.0 or menu_button.size.y < 44.0:
        _fail("Mobile file menu touch target is too small")
        return
    print("TIMELINE HORIZONTAL PAN PASSED: 5s default view, bidirectional ruler swipe, stable physical deltas, isolated playhead, compact header")
    quit(0)
