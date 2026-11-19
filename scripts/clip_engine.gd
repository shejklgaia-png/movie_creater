extends RefCounted
## Deterministic cutscene clip data; UI and playback use the same interval rules.
## A clip occupies [start, start + (out-in)/speed] on the timeline.
## The source animation itself is never modified.
const MIN_SOURCE_SPAN := 0.05
const MIN_SPEED := 0.1

static func new_clip(id: String, animation_index: int, source_length: float, at: float, groups: Array) -> Dictionary:
    var span := clampf(source_length, MIN_SOURCE_SPAN, 120.0)
    return {
        "uid": id, "animation_index": animation_index,
        "start": maxf(0.0, at), "in": 0.0, "out": span,
        "speed": 1.0, "enabled_groups": groups.duplicate(),
        "limit_bones": false, "loop": false, "loop_end": maxf(0.0, at) + span
    }

static func source_span(clip: Dictionary) -> float:
    return maxf(0.0, float(clip.get("out", 0.0)) - float(clip.get("in", 0.0))) / maxf(float(clip.get("speed", 1.0)), MIN_SPEED)

static func clip_length(clip: Dictionary) -> float:
    if bool(clip.get("loop", false)):
        return maxf(0.0, float(clip.get("loop_end", float(clip.get("start", 0.0)) + source_span(clip))) - float(clip.get("start", 0.0)))
    return source_span(clip)

## Loop handles snap to complete source-animation cycles, never arbitrary frames.
static func snap_loop_end(clip: Dictionary, requested_end: float, movie_duration: float) -> float:
    var start := float(clip.get("start", 0.0))
    var cycle := maxf(MIN_SOURCE_SPAN, source_span(clip))
    var available := maxf(0.0, movie_duration - start)
    if available <= cycle:
        return snappedf(start + available, 0.01)
    var cycles := clampi(roundi((requested_end - start) / cycle), 1, maxi(1, floori(available / cycle)))
    return snappedf(start + float(cycles) * cycle, 0.01)

static func end_time(clip: Dictionary) -> float:
    return float(clip.get("start", 0.0)) + clip_length(clip)

static func active_clip(clips: Array, seconds: float) -> Dictionary:
    # When clips overlap, the latest start wins. At exact ties, the later
    # inserted clip wins. Outside an interval, bones reset to their rest pose.
    var best: Dictionary = {}
    var best_start := -INF
    for raw in clips:
        if not (raw is Dictionary):
            continue
        var clip: Dictionary = raw
        var start := float(clip.get("start", 0.0))
        if seconds < start or seconds > end_time(clip) or clip_length(clip) <= 0.0:
            continue
        if start >= best_start:
            best = clip
            best_start = start
    return best

static func source_time(clip: Dictionary, seconds: float) -> float:
    var in_point := float(clip.get("in", 0.0))
    var out_point := float(clip.get("out", in_point))
    var speed := maxf(MIN_SPEED, float(clip.get("speed", 1.0)))
    var elapsed := maxf(0.0, seconds - float(clip.get("start", 0.0)))
    if bool(clip.get("loop", false)):
        var cycle := maxf(MIN_SOURCE_SPAN, source_span(clip))
        # Keep the source's last frame at the exact end of the final iteration.
        if seconds >= end_time(clip) - 0.0001 and absf(fposmod(elapsed, cycle)) < 0.0001:
            return out_point
        elapsed = fposmod(elapsed, cycle)
    return clampf(in_point + elapsed * speed, in_point, out_point)

static func validate(clip: Dictionary, source_length: float, timeline_length: float) -> Dictionary:
    var fixed := clip.duplicate(true)
    var full_length := maxf(MIN_SOURCE_SPAN, source_length)
    fixed["start"] = clampf(float(clip.get("start", 0.0)), 0.0, maxf(0.0, timeline_length - MIN_SOURCE_SPAN))
    fixed["speed"] = clampf(float(clip.get("speed", 1.0)), MIN_SPEED, 4.0)
    fixed["in"] = clampf(float(clip.get("in", 0.0)), 0.0, full_length - MIN_SOURCE_SPAN)
    fixed["out"] = clampf(float(clip.get("out", full_length)), float(fixed["in"]) + MIN_SOURCE_SPAN, full_length)
    fixed["loop"] = bool(clip.get("loop", false))
    fixed["limit_bones"] = bool(clip.get("limit_bones", false))
    var start := float(fixed["start"])
    var default_end := start + source_span(fixed)
    fixed["loop_end"] = clampf(float(clip.get("loop_end", default_end)), start + minf(MIN_SOURCE_SPAN, maxf(0.0, timeline_length - start)), timeline_length)
    return fixed

static func includes_group(clip: Dictionary, group_uuid: String) -> bool:
    var active: Variant = clip.get("enabled_groups", null)
    return active == null or (active is Array and active.has(group_uuid))
