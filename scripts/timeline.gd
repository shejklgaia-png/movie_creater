extends Control
## Portrait timeline: keyframe diamonds + moveable animation bars.
## Tapping a bar opens clip detail; dragging moves it on the timeline.

signal seek_requested(time_seconds: float)
signal key_dragged(object_id: String, key_index: int, time_seconds: float, finished: bool)
signal clip_tapped(model_id: String, clip_uid: String)
signal clip_dragged(model_id: String, clip_uid: String, seconds: float, finished: bool)

const LEFT_MARGIN := 85.0
const ROW_HEIGHT := 38.0
const HEADER_HEIGHT := 27.0
const TOUCH_SLOP := 11.0

var duration := 15.0
var playhead := 0.0
var tracks: Array[Dictionary] = []
var drag_kind := ""
var drag_id := ""
var drag_index := -1
var drag_uid := ""
var drag_start_x := 0.0
var drag_original_time := 0.0
var drag_moved := false

func set_tracks(data: Array[Dictionary]) -> void:
    tracks = data
    custom_minimum_size.y = maxf(164.0, HEADER_HEIGHT + ROW_HEIGHT * float(tracks.size()) + 6.0)
    queue_redraw()

func set_playhead(seconds: float) -> void:
    playhead = seconds
    queue_redraw()

func _time_width() -> float:
    return maxf(size.x - LEFT_MARGIN - 12.0, 1.0)

func _time_at(x: float) -> float:
    return clampf((x - LEFT_MARGIN) / _time_width() * duration, 0.0, duration)

func _x_at(t: float) -> float:
    return LEFT_MARGIN + _time_width() * clampf(t / duration, 0.0, 1.0)

func _draw() -> void:
    var w := size.x
    var h := size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color("#18202b"), true)
    draw_line(Vector2(LEFT_MARGIN, 0), Vector2(LEFT_MARGIN, h), Color("#445065"))
    for step in range(6):
        var t := duration * float(step) / 5.0
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
                if end <= 0.0 or start >= duration:
                    continue
                var x1 := _x_at(start)
                var x2 := _x_at(end)
                var rect := Rect2(x1, y + 6.0, maxf(7.0, x2 - x1), ROW_HEIGHT - 12.0)
                draw_rect(rect, Color("#438fbe"), true)
                draw_rect(rect, Color("#a0d8f6"), false, 1.5)
                draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 18), str(clip.get("label", "Motion")), HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, rect.size.x - 10.0), 12, Color.WHITE)
        else:
            var times: Array = entry.get("times", [])
            for t_value in times:
                var px := _x_at(float(t_value))
                var cy := y + ROW_HEIGHT * 0.5
                draw_colored_polygon(PackedVector2Array([
                    Vector2(px, cy - 7), Vector2(px + 7, cy),
                    Vector2(px, cy + 7), Vector2(px - 7, cy)]), Color("#6ee7bf"))
    var head_x := _x_at(playhead)
    draw_line(Vector2(head_x, 0), Vector2(head_x, h), Color("#ffca67"), 2.0)
    draw_circle(Vector2(head_x, 19), 5.0, Color("#ffca67"))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            _start_interaction(event.position)
        else:
            _finish_interaction(event.position)
        accept_event()
    elif event is InputEventScreenDrag:
        _move_interaction(event.position)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _start_interaction(event.position)
        else:
            _finish_interaction(event.position)
        accept_event()
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        _move_interaction(event.position)
        accept_event()

func _start_interaction(at: Vector2) -> void:
    drag_kind = ""
    drag_id = ""
    drag_index = -1
    drag_uid = ""
    drag_start_x = at.x
    drag_moved = false
    var row := int(floorf((at.y - HEADER_HEIGHT) / ROW_HEIGHT))
    if row >= 0 and row < tracks.size() and at.x >= LEFT_MARGIN:
        var entry: Dictionary = tracks[row]
        if str(entry.get("kind", "keys")) == "clips":
            var clips: Array = entry.get("clips", [])
            for i in range(clips.size() - 1, -1, -1):
                var clip: Dictionary = clips[i]
                if at.x >= _x_at(float(clip.get("start", 0.0))) - 3.0 and at.x <= _x_at(float(clip.get("end", 0.0))) + 3.0:
                    drag_kind = "clip"
                    drag_id = str(entry.get("id", ""))
                    drag_uid = str(clip.get("uid", ""))
                    drag_original_time = float(clip.get("start", 0.0))
                    return
        else:
            var times: Array = entry.get("times", [])
            for i in range(times.size()):
                if absf(at.x - _x_at(float(times[i]))) <= 13.0:
                    drag_kind = "key"
                    drag_id = str(entry.get("id", ""))
                    drag_index = i
                    drag_original_time = float(times[i])
                    seek_requested.emit(drag_original_time)
                    return
    seek_requested.emit(_time_at(at.x))

func _move_interaction(at: Vector2) -> void:
    if drag_kind == "":
        seek_requested.emit(_time_at(at.x))
        return
    if not drag_moved and absf(at.x - drag_start_x) < TOUCH_SLOP:
        return
    drag_moved = true
    var new_time := clampf(drag_original_time + (at.x - drag_start_x) * duration / _time_width(), 0.0, duration)
    if drag_kind == "clip":
        clip_dragged.emit(drag_id, drag_uid, new_time, false)
    elif drag_kind == "key":
        key_dragged.emit(drag_id, drag_index, new_time, false)

func _finish_interaction(at: Vector2) -> void:
    if drag_kind == "clip":
        if drag_moved:
            var t := clampf(drag_original_time + (at.x - drag_start_x) * duration / _time_width(), 0.0, duration)
            clip_dragged.emit(drag_id, drag_uid, t, true)
        else:
            clip_tapped.emit(drag_id, drag_uid)
    elif drag_kind == "key" and drag_moved:
        var time_value := clampf(drag_original_time + (at.x - drag_start_x) * duration / _time_width(), 0.0, duration)
        key_dragged.emit(drag_id, drag_index, time_value, true)
    drag_kind = ""
    drag_id = ""
    drag_index = -1
    drag_uid = ""
    drag_moved = false
