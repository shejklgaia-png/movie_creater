extends SceneTree
## Regression: scrolling changes the Timeline Control's local position. The
## gesture must use screen-relative motion, never the moving local coordinates.
func _initialize() -> void:
    call_deferred("_run")

func _fail(reason: String) -> void:
    push_error("TIMELINE SCROLL STABILITY FAILED: " + reason)
    quit(1)

func _run() -> void:
    var editor: Control = load("res://scenes/editor.tscn").instantiate()
    root.add_child(editor)
    editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    editor.size = Vector2(360, 800)
    await process_frame
    await process_frame

    var source := FileAccess.get_file_as_string("res://tests/fixtures/free_mesh_5.bbmodel")
    if not editor.call("_import_bbmodel_text", source, "Timeline Scroll"):
        _fail("Could not import timeline fixture")
        return
    await process_frame
    await process_frame

    var timeline: Control = editor.get("timeline")
    var scroller: ScrollContainer = editor.get("timeline_scroll")
    var bar: VScrollBar = scroller.get_v_scroll_bar()
    if bar.max_value - bar.page < 30.0:
        _fail("Test timeline did not overflow its visible height")
        return
    if scroller.scroll_deadzone < 10000:
        _fail("Built-in touch drag must not compete with timeline drag")
        return

    editor.call("_seek", 1.75)
    timeline._start_interaction(Vector2(140, 115))
    var playhead_before: float = editor.get("current_time")
    var range_before: float = bar.max_value

    # Each screen-relative drag moves UP by 12 pixels. After each scroll,
    # local event.position can move DOWN despite the finger moving UP.
    # That used to reverse the scroll direction and cause screen jitter.
    timeline._move_interaction(Vector2(140, 103), Vector2(0, -14), true)
    var first := scroller.scroll_vertical
    timeline._move_interaction(Vector2(140, 117), Vector2(0, -12), true)
    var second := scroller.scroll_vertical
    timeline._move_interaction(Vector2(140, 131), Vector2(0, -12), true)
    var third := scroller.scroll_vertical

    if not (first >= 12 and second > first and third > second):
        _fail("Upward swipe reversed/jumped as local coordinates moved: %d %d %d" % [first, second, third])
        return
    if absf(bar.max_value - range_before) > 0.01:
        _fail("Scrollbar range mutated during finger motion")
        return
    if absf(float(editor.get("current_time")) - playhead_before) > 0.001:
        _fail("Vertical scroll moved the playhead")
        return

    # Small subpixel deltas must accumulate; no reset or inverse jump.
    var before_micro: int = scroller.scroll_vertical
    for i in range(6):
        timeline._move_interaction(Vector2(140, 150 + i), Vector2(0, -0.6), true)
    if scroller.scroll_vertical < before_micro + 2:
        _fail("Fractional screen-relative drag steps were discarded")
        return

    timeline._finish_interaction(Vector2(140, 170))
    if bool(timeline.get("vertical_panning")):
        _fail("Vertical gesture state stuck after release")
        return
    print("TIMELINE SCROLL STABILITY PASSED: no dual touch scroll, monotonic finger delta, stable range, subpixel increments, playhead isolation")
    quit(0)
