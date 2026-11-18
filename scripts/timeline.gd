extends Control
## Compact touch-first keyframe timeline. No scene dependency.

signal seek_requested(time_seconds: float)
signal key_dragged(object_id: String, key_index: int, time_seconds: float, finished: bool)

const LEFT_MARGIN := 88.0
const ROW_HEIGHT := 34.0
const HEADER_HEIGHT := 27.0

var duration := 15.0
var playhead := 0.0
var tracks: Array[Dictionary] = []
var dragging_key_id := ""
var dragging_key_index := -1

func set_tracks(data: Array[Dictionary]) -> void:
    tracks = data
    queue_redraw()

func set_playhead(seconds: float) -> void:
    playhead = seconds
    queue_redraw()

func _draw() -> void:
    var w := size.x
    var h := size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color("#18202b"), true)
    draw_line(Vector2(LEFT_MARGIN, 0), Vector2(LEFT_MARGIN, h), Color("#445065"))
    var time_width := maxf(w - LEFT_MARGIN - 10.0, 1.0)
    for step in range(6):
        var t := duration * float(step) / 5.0
        var x := LEFT_MARGIN + time_width * float(step) / 5.0
        draw_line(Vector2(x, 19), Vector2(x, h), Color("#354052"), 1.0)
        draw_string(ThemeDB.fallback_font, Vector2(x + 2, 14), "%.0fs" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#aebccc"))
    for index in range(tracks.size()):
        var y := HEADER_HEIGHT + float(index) * ROW_HEIGHT
        if y + ROW_HEIGHT > h:
            break
        if index % 2 == 0:
            draw_rect(Rect2(0, y, w, ROW_HEIGHT), Color(1, 1, 1, 0.035))
        var entry: Dictionary = tracks[index]
        draw_string(ThemeDB.fallback_font, Vector2(7, y + 22), str(entry.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, 78, 13, Color("#dbe7f7"))
        var times: Array = entry.get("times", [])
        for t_value in times:
            var t := float(t_value)
            var px := LEFT_MARGIN + time_width * clampf(t / duration, 0.0, 1.0)
            var cy := y + ROW_HEIGHT * 0.5
            var diamond := PackedVector2Array([
                Vector2(px, cy - 7), Vector2(px + 7, cy),
                Vector2(px, cy + 7), Vector2(px - 7, cy)])
            draw_colored_polygon(diamond, Color("#6ee7bf"))
    var head_x := LEFT_MARGIN + time_width * clampf(playhead / duration, 0.0, 1.0)
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

func _time_at(x: float) -> float:
    return clampf((x - LEFT_MARGIN) / maxf(size.x - LEFT_MARGIN - 10.0, 1.0) * duration, 0.0, duration)

func _start_interaction(at: Vector2) -> void:
    dragging_key_id = ""
    dragging_key_index = -1
    var row := int(floorf((at.y - HEADER_HEIGHT) / ROW_HEIGHT))
    if row >= 0 and row < tracks.size() and at.x >= LEFT_MARGIN:
        var entry: Dictionary = tracks[row]
        var times: Array = entry.get("times", [])
        for index in range(times.size()):
            var key_x := LEFT_MARGIN + (size.x - LEFT_MARGIN - 10.0) * float(times[index]) / duration
            if absf(at.x - key_x) <= 13.0:
                dragging_key_id = str(entry.get("id", ""))
                dragging_key_index = index
                seek_requested.emit(float(times[index]))
                return
    seek_requested.emit(_time_at(at.x))

func _move_interaction(at: Vector2) -> void:
    var seconds := _time_at(at.x)
    if not dragging_key_id.is_empty():
        key_dragged.emit(dragging_key_id, dragging_key_index, seconds, false)
    else:
        seek_requested.emit(seconds)

func _finish_interaction(at: Vector2) -> void:
    if not dragging_key_id.is_empty():
        key_dragged.emit(dragging_key_id, dragging_key_index, _time_at(at.x), true)
    dragging_key_id = ""
    dragging_key_index = -1
