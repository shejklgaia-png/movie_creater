extends RefCounted
## Non-destructive, per-part pose delta track evaluated over the source animation.
## Keys always store DELTAS relative to the imported Blockbench animation.
## Position/rotation are additive; scale is multiplicative.

static func identity() -> Dictionary:
    return {
        "position": [0.0, 0.0, 0.0],
        "rotation": [0.0, 0.0, 0.0],
        "scale": [1.0, 1.0, 1.0]
    }

static func vector(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
    if value is Array and value.size() >= 3:
        return Vector3(float(value[0]), float(value[1]), float(value[2]))
    return fallback

static func array_of(v: Vector3) -> Array:
    return [v.x, v.y, v.z]

static func combine(base: Dictionary, pose: Dictionary) -> Dictionary:
    return {
        "position": array_of(vector(base.get("position", [])) + vector(pose.get("position", []))),
        "rotation": array_of(vector(base.get("rotation", [])) + vector(pose.get("rotation", []))),
        "scale": array_of(vector(base.get("scale", []), Vector3.ONE) * vector(pose.get("scale", []), Vector3.ONE))
    }

static func relative(effective: Dictionary, base: Dictionary) -> Dictionary:
    var base_scale := vector(base.get("scale", []), Vector3.ONE)
    var safe_scale := Vector3(
        maxf(absf(base_scale.x), 0.00001),
        maxf(absf(base_scale.y), 0.00001),
        maxf(absf(base_scale.z), 0.00001))
    return {
        "position": array_of(vector(effective.get("position", [])) - vector(base.get("position", []))),
        "rotation": array_of(vector(effective.get("rotation", [])) - vector(base.get("rotation", []))),
        "scale": array_of(vector(effective.get("scale", []), Vector3.ONE) / safe_scale)
    }

static func sample(keys: Array, time: float) -> Dictionary:
    if keys.is_empty():
        return identity()
    var before: Dictionary = keys[0]
    var after: Dictionary = keys[keys.size() - 1]
    if time <= float(before.get("time", 0.0)):
        after = before
    elif time >= float(after.get("time", 0.0)):
        before = after
    else:
        for i in range(keys.size() - 1):
            var a: Dictionary = keys[i]
            var b: Dictionary = keys[i + 1]
            if time >= float(a.get("time", 0.0)) and time <= float(b.get("time", 0.0)):
                before = a
                after = b
                break
    var t0 := float(before.get("time", 0.0))
    var t1 := float(after.get("time", t0))
    var alpha := 0.0 if absf(t1 - t0) < 0.00001 else clampf((time - t0) / (t1 - t0), 0.0, 1.0)
    var p0 := vector(before.get("position", []))
    var p1 := vector(after.get("position", []))
    var r0 := vector(before.get("rotation", []))
    var r1 := vector(after.get("rotation", []))
    var s0 := vector(before.get("scale", []), Vector3.ONE)
    var s1 := vector(after.get("scale", []), Vector3.ONE)
    return {
        "position": array_of(p0.lerp(p1, alpha)),
        "rotation": array_of(Vector3(
            rad_to_deg(lerp_angle(deg_to_rad(r0.x), deg_to_rad(r1.x), alpha)),
            rad_to_deg(lerp_angle(deg_to_rad(r0.y), deg_to_rad(r1.y), alpha)),
            rad_to_deg(lerp_angle(deg_to_rad(r0.z), deg_to_rad(r1.z), alpha)))),
        "scale": array_of(s0.lerp(s1, alpha))
    }

static func upsert(keys: Array, time: float, delta: Dictionary) -> Array:
    var result: Array = keys.duplicate(true)
    var record := delta.duplicate(true)
    record["time"] = snappedf(time, 0.01)
    var replaced := false
    for i in range(result.size()):
        if absf(float(result[i].get("time", 0.0)) - time) < 0.025:
            result[i] = record
            replaced = true
            break
    if not replaced:
        result.append(record)
    result.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
    return result

static func remove_at(keys: Array, time: float, epsilon: float = 0.025) -> Array:
    var result: Array = []
    for record in keys:
        if absf(float(record.get("time", 0.0)) - time) >= epsilon:
            result.append(record.duplicate(true))
    return result
