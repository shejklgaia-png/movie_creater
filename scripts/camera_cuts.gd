extends RefCounted
## Camera cut track: each cut selects a camera from its exact start time.
## The implicit default camera (camera_1) covers time before the first cut.
## Cuts are instantaneous; interpolation happens only WITHIN a camera track.

static func active_camera(cuts: Array, seconds: float) -> String:
    var selected := "camera_1"
    var start := -INF
    for record in cuts:
        if not (record is Dictionary):
            continue
        var t := float(record.get("time", 0.0))
        if t <= seconds and t >= start:
            selected = str(record.get("camera_id", "camera_1"))
            start = t
    return selected

static func insert_cut(cuts: Array, uid: String, camera_id: String, seconds: float, duration: float) -> Array:
    var results: Array = cuts.duplicate(true)
    # At the same frame a new cut replaces the older choice.
    var moment := snappedf(clampf(seconds, 0.0, duration), 0.01)
    for idx in range(results.size() - 1, -1, -1):
        if absf(float(results[idx].get("time", 0.0)) - moment) < 0.015:
            results.remove_at(idx)
    results.append({"uid": uid, "camera_id": camera_id, "time": moment})
    results.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    return results

static func move_cut(cuts: Array, uid: String, seconds: float, duration: float) -> Array:
    var results: Array = cuts.duplicate(true)
    for cut in results:
        if str(cut.get("uid", "")) == uid:
            cut["time"] = snappedf(clampf(seconds, 0.0, duration), 0.01)
            break
    results.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    return results

static func remove_cut(cuts: Array, uid: String) -> Array:
    var result: Array = []
    for entry in cuts:
        if str(entry.get("uid", "")) != uid:
            result.append(entry.duplicate(true))
    return result

static func bars(cuts: Array, duration: float, known_tracks: Dictionary) -> Array:
    var ordered: Array = []
    for cut in cuts:
        if not (cut is Dictionary):
            continue
        if not known_tracks.has(str(cut.get("camera_id", "camera_1"))):
            continue
        ordered.append(cut.duplicate(true))
    ordered.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    var events: Array = [{"uid": "implicit", "time": 0.0, "camera_id": "camera_1"}]
    for record in ordered:
        if float(record.get("time", 0.0)) < duration:
            if not events.is_empty() and is_equal_approx(float(events.back()["time"]), float(record["time"])):
                events.pop_back()
            events.append(record)
    var bars: Array = []
    for i in range(events.size()):
        var cut: Dictionary = events[i]
        var begin: float = float(cut.get("time", 0.0))
        var until := duration
        if i + 1 < events.size():
            until = float(events[i + 1]["time"])
        if until - begin < 0.01:
            continue
        var camera_id := str(cut.get("camera_id", "camera_1"))
        bars.append({"uid": str(cut.get("uid", "")),
            "start": begin, "end": until,
            "label": "Cam " + camera_id.trim_prefix("camera_")})
    return bars

static func sample_keys(keys: Array, at: float) -> Dictionary:
    if keys.is_empty():
        return {}
    var before: Dictionary = keys[0]
    var after: Dictionary = keys[keys.size() - 1]
    if at <= float(before.get("time", 0.0)):
        after = before
    elif at >= float(after.get("time", 0.0)):
        before = after
    else:
        for i in range(keys.size() - 1):
            var key_a: Dictionary = keys[i]
            var key_b: Dictionary = keys[i + 1]
            if at >= float(key_a["time"]) and at <= float(key_b["time"]):
                before = key_a
                after = key_b
                break
    var t0 := float(before.get("time", 0.0))
    var t1 := float(after.get("time", t0))
    var weight := 0.0 if absf(t1 - t0) < 0.00001 else clampf((at - t0) / (t1 - t0), 0.0, 1.0)
    var pos0 := Vector3(float(before["position"][0]), float(before["position"][1]), float(before["position"][2]))
    var pos1 := Vector3(float(after["position"][0]), float(after["position"][1]), float(after["position"][2]))
    var rot0 := Vector3(float(before["rotation"][0]), float(before["rotation"][1]), float(before["rotation"][2]))
    var rot1 := Vector3(float(after["rotation"][0]), float(after["rotation"][1]), float(after["rotation"][2]))
    var q0 := Quaternion(Basis.from_euler(rot0, EULER_ORDER_YXZ))
    var q1 := Quaternion(Basis.from_euler(rot1, EULER_ORDER_YXZ))
    return {
        "position": pos0.lerp(pos1, weight),
        "orientation": q0.slerp(q1, weight),
        "fov": lerpf(float(before.get("fov", 54.0)), float(after.get("fov", 54.0)), weight)
    }
