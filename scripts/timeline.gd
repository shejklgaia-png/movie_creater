extends Control
## Portrait timeline: keyframe diamonds + moveable animation bars.
## Tapping a bar opens clip detail; dragging moves it on the timeline.

signal seek_requested(time_seconds: float)
signal key_dragged(object_id: String, key_index: int, time_seconds: float, finished: bool)
signal clip_tapped(model_id: String, clip_uid: String)
signal clip_dragged(model_id: String, clip_uid: String, seconds: float, finished: bool)
signal loop_end_dragged(model_id: String, clip_uid: String, seconds: float, finished: bool)
signal vertical_pan_requested(pixels: float)

const LEFT_MARGIN := 85.0
const ROW_HEIGHT := 46.0
const HEADER_HEIGHT := 27.0
const TOUCH_SLOP := 12.0
const KEY_HIT_RADIUS := 19.0

var duration := 15.0
var playhead := 0.0
var zoom := 1.0
var view_start := 0.0
var tracks: Array[Dictionary] = []
var drag_kind := ""
var drag_id := ""
var drag_index := -1
var drag_uid := ""
var drag_start_x := 0.0
var drag_original_time := 0.0
var drag_moved := false
var drag_start_y := 0.0
var drag_last_y := 0.0
# Track physical pointer motion separately from the timeline's local position.
# Moving the ScrollContainer changes local event.position even if the finger
# stays still, so using consecutive local coordinates creates jitter/reversal.
var drag_pointer_offset := Vector2.ZERO
var drag_last_position := Vector2.ZERO
var active_touch_index := -1
var last_touch_frame := -100
var vertical_panning := false

func set_tracks(data: Array[Dictionary]) -> void:
    tracks = data
    custom_minimum_size.y = maxf(152.0, HEADER_HEIGHT + ROW_HEIGHT * float(tracks.size()) + 6.0)
    queue_redraw()

func set_playhead(seconds: float) -> void:
    playhead = seconds
    queue_redraw()

func _time_width() -> float:
    return maxf(size.x - LEFT_MARGIN - 12.0, 1.0)

func _view_span() -> float:
    return maxf(0.5, duration / maxf(zoom, 1.0))

func _time_at(x: float) -> float:
    return clampf(view_start + (x - LEFT_MARGIN) / _time_width() * _view_span(), 0.0, duration)

func _x_at(t: float) -> float:
    return LEFT_MARGIN + _time_width() * (t - view_start) / _view_span()

func zoom_to(next_zoom: float, center_time: float) -> void:
    var old_span := _view_span()
    var ratio := (center_time - view_start) / old_span
    zoom = clampf(next_zoom, 1.0, maxf(1.0, duration / 0.5))
    view_start = clampf(center_time - ratio * _view_span(), 0.0, maxf(0.0, duration - _view_span()))
    queue_redraw()

func pan_time(delta_seconds: float) -> void:
    view_start = clampf(view_start + delta_seconds, 0.0, maxf(0.0, duration - _view_span()))
    queue_redraw()

# Camera cut bars have no repeat control. Animation clips always expose one,
# including before looping is enabled; otherwise users cannot discover it.
func _has_loop_grip(clip: Dictionary) -> bool:
    return bool(clip.get("loop_handle", false)) or bool(clip.get("loop", false))

func _loop_grip_center(end_x: float, row_y: float) -> Vector2:
    var grip_x := end_x + 15.0 if end_x <= size.x - 32.0 else end_x - 13.0
    return Vector2(grip_x, row_y + ROW_HEIGHT * 0.5)

func _draw() -> void:
    var w := size.x
    var h := size.y
    draw_set_transform(Vector2.ZERO)
    draw_rect(Rect2(Vector2.ZERO, size), Color("#18202b"), true)
    draw_line(Vector2(LEFT_MARGIN, 0), Vector2(LEFT_MARGIN, h), Color("#445065"))
    for step in range(6):
        var t := view_start + _view_span() * float(step) / 5.0
        var x := _x_at(t)
        draw_line(Vector2(x, 19), Vector2(x, h), Color("#354052"), 1.0)
        draw_string(ThemeDB.fallback_font, Vector2(x + 2, 14), "%.0fs" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#aebccc"))
    for index in range(tracks.size()):
        var y := HEADER_HEIGHT + float(index) * ROW_HEIGHT
        if y >= h:
            break
        var entry: Dictionary = tracks[index]
        if index % 2 == 0:
            draw_rect(Rect2(0, y, w, ROW_HEIGHT), Color(1, 1, 1, 0.035))
        draw_string(ThemeDB.fallback_font, Vector2(6, y + 24), str(entry.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, 75, 12, Color("#dbe7f7"))
        if str(entry.get("kind", "keys")) == "clips":
            var clips: Array = entry.get("clips", [])
            for value in clips:
                var clip: Dictionary = value
                var start := float(clip.get("start", 0.0))
                var end := float(clip.get("end", start))
                if end <= view_start or start >= view_start + _view_span():
                    continue
                var x1 := _x_at(start)
                var x2 := _x_at(end)
                var rect := Rect2(maxf(LEFT_MARGIN, x1), y + 5.0, maxf(7.0, minf(w, x2) - maxf(LEFT_MARGIN, x1)), ROW_HEIGHT - 10.0)
                draw_rect(rect, Color("#438fbe"), true)
                draw_rect(rect, Color("#a0d8f6"), false, 1.5)
                var looping := bool(clip.get("loop", false))
                if looping:
                    var cycle := float(clip.get("cycle", 0.0))
                    if cycle > 0.001:
                        var tick := start + cycle
                        while tick < end - 0.001:
                            var tx := _x_at(tick)
                            if tx >= rect.position.x and tx <= rect.end.x:
                                draw_line(Vector2(tx, y + 7.0), Vector2(tx, y + ROW_HEIGHT - 7.0), Color("#d9eeff"), 1.0)
                            tick += cycle
                var text_width := maxf(1.0, rect.size.x - (32.0 if _has_loop_grip(clip) else 10.0))
                draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 18), str(clip.get("label", "Motion")), HORIZONTAL_ALIGNMENT_LEFT, text_width, 12, Color.WHITE)
                if _has_loop_grip(clip) and x2 > LEFT_MARGIN + 12.0 and x2 <= w - 1.0:
                    # Visible before the first loop. The icon is drawn as
                    # geometry so it is never lost to Android font fallback.
                    # Outside placement preserves dragging short source clips.
                    var center := _loop_grip_center(x2, y)
                    draw_circle(center, 14.0, Color("#f2c467") if looping else Color("#ffe4a2"))
                    draw_arc(center, 8.0, 0.65, 5.2, 23, Color("#1b283a"), 2.5)
                    draw_colored_polygon(PackedVector2Array([
                        center + Vector2(7.0, -6.0),
                        center + Vector2(13.0, -4.0),
                        center + Vector2(8.0, 1.0)]), Color("#1b283a"))
        else:
            var times: Array = entry.get("times", [])
            for t_value in times:
                var px := _x_at(float(t_value))
                if px < LEFT_MARGIN or px > w:
                    continue
                var cy := y + ROW_HEIGHT * 0.5
                draw_colored_polygon(PackedVector2Array([
                    Vector2(px, cy - 9), Vector2(px + 9, cy),
                    Vector2(px, cy + 9), Vector2(px - 9, cy)]), Color("#6ee7bf"))
    var head_x := _x_at(playhead)
    if head_x >= LEFT_MARGIN and head_x <= w:
        draw_line(Vector2(head_x, 0), Vector2(head_x, h), Color("#ffca67"), 2.0)
        draw_circle(Vector2(head_x, 19), 5.0, Color("#ffca67"))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and active_touch_index == -1:
            active_touch_index = event.index
            _start_interaction(event.position)
        elif not event.pressed and event.index == active_touch_index:
            _finish_interaction(event.position)
            active_touch_index = -1
        last_touch_frame = Engine.get_process_frames()
        accept_event()
    elif event is InputEventScreenDrag:
        if event.index == active_touch_index:
            # event.relative is measured from actual finger movement; unlike
            # event.position it does not jump when the track scrolls beneath it.
            _move_interaction(event.position, event.relative, true)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        # Android also synthesizes mouse events for a touch; processing both
        # caused one gesture to be restarted or completed twice.
        if active_touch_index != -1 or Engine.get_process_frames() - last_touch_frame <= 1:
            accept_event()
            return
        if event.pressed:
            _start_interaction(event.position)
        else:
            _finish_interaction(event.position)
        accept_event()
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        if active_touch_index == -1 and Engine.get_process_frames() - last_touch_frame > 1:
            _move_interaction(event.position, event.relative, true)
        accept_event()

func _start_interaction(at: Vector2) -> void:
    drag_kind = ""
    drag_id = ""
    drag_index = -1
    drag_uid = ""
    drag_start_x = at.x
    drag_start_y = at.y
    drag_last_y = at.y
    drag_last_position = at
    drag_pointer_offset = Vector2.ZERO
    vertical_panning = false
    drag_moved = false
    var row := int(floorf((at.y - HEADER_HEIGHT) / ROW_HEIGHT))
    if row >= 0 and row < tracks.size() and at.x >= LEFT_MARGIN:
        var entry: Dictionary = tracks[row]
        if str(entry.get("kind", "keys")) == "clips":
            var clips: Array = entry.get("clips", [])
            for i in range(clips.size() - 1, -1, -1):
                var clip: Dictionary = clips[i]
                var clip_end_x := _x_at(float(clip.get("end", 0.0)))
                var clip_start_x := _x_at(float(clip.get("start", 0.0)))
                var grip_center := _loop_grip_center(clip_end_x, HEADER_HEIGHT + float(row) * ROW_HEIGHT)
                var handle_hit := _has_loop_grip(clip) and clip_end_x > LEFT_MARGIN + 12.0 and clip_end_x <= size.x - 1.0 and absf(at.x - grip_center.x) <= 19.0 and at.x >= LEFT_MARGIN
                var bar_hit := at.x >= maxf(LEFT_MARGIN, clip_start_x) - 3.0 and at.x <= clip_end_x + 3.0
                if bar_hit or handle_hit:
                    drag_kind = "loop" if handle_hit else "clip"
                    drag_id = str(entry.get("id", ""))
                    drag_uid = str(clip.get("uid", ""))
                    drag_original_time = float(clip.get("end", 0.0)) if drag_kind == "loop" else float(clip.get("start", 0.0))
                    return
        else:
            var times: Array = entry.get("times", [])
            for i in range(times.size()):
                if absf(at.x - _x_at(float(times[i]))) <= KEY_HIT_RADIUS:
                    drag_kind = "key"
                    drag_id = str(entry.get("id", ""))
                    drag_index = i
                    drag_original_time = float(times[i])
                    seek_requested.emit(drag_original_time)
                    return
    seek_requested.emit(_time_at(at.x))

func _move_interaction(at: Vector2, physical_delta: Vector2 = Vector2.ZERO, has_physical_delta: bool = false) -> void:
    # Tests and programmatic callers can still pass absolute local points.
    # Real touch/mouse events use their stable relative motion exclusively.
    var motion := physical_delta if has_physical_delta else at - drag_last_position
    drag_last_position = at
    drag_pointer_offset += motion
    var horizontal := absf(drag_pointer_offset.x)
    var vertical := absf(drag_pointer_offset.y)
    if not drag_moved and maxf(horizontal, vertical) < TOUCH_SLOP:
        return
    # Vertical gestures always scroll the track list. Never seek or move a
    # clip/key while the finger is scrolling through many models.
    if not drag_moved:
        vertical_panning = vertical > horizontal * 1.25
        drag_moved = true
    if vertical_panning:
        vertical_pan_requested.emit(-motion.y)
        drag_last_y = at.y
        return
    drag_last_y = at.y
    if drag_kind == "":
        if drag_start_x + drag_pointer_offset.x >= LEFT_MARGIN:
            seek_requested.emit(_time_at(drag_start_x + drag_pointer_offset.x))
        return
    var new_time := clampf(drag_original_time + drag_pointer_offset.x * _view_span() / _time_width(), 0.0, duration)
    if drag_kind == "clip":
        clip_dragged.emit(drag_id, drag_uid, new_time, false)
    elif drag_kind == "loop":
        loop_end_dragged.emit(drag_id, drag_uid, new_time, false)
    elif drag_kind == "key":
        key_dragged.emit(drag_id, drag_index, new_time, false)

func _finish_interaction(at: Vector2) -> void:
    if vertical_panning:
        drag_kind = ""
        drag_id = ""
        drag_index = -1
        drag_uid = ""
        drag_moved = false
        vertical_panning = false
        return
    if drag_kind == "clip" or drag_kind == "loop":
        if drag_moved:
            var t := clampf(drag_original_time + drag_pointer_offset.x * _view_span() / _time_width(), 0.0, duration)
            if drag_kind == "loop":
                loop_end_dragged.emit(drag_id, drag_uid, t, true)
            else:
                clip_dragged.emit(drag_id, drag_uid, t, true)
        else:
            clip_tapped.emit(drag_id, drag_uid)
    elif drag_kind == "key" and drag_moved:
        var time_value := clampf(drag_original_time + drag_pointer_offset.x * _view_span() / _time_width(), 0.0, duration)
        key_dragged.emit(drag_id, drag_index, time_value, true)
    drag_kind = ""
    drag_id = ""
    drag_index = -1
    drag_uid = ""
    drag_moved = false
