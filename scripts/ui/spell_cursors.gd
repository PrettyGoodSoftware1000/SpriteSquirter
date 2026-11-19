class_name SpellCursors
extends RefCounted
## The mouse pointers for aiming spells, drawn in code (SIZE pixels square,
## the hot spot in the middle): a flame for Fireball, sparks for Chain
## Lightning, a cloud dripping water for Rain, a tangle of roots for Roots,
## a skull dripping blood for Blood Sacrifice, a golden or a red star for
## Bless and Condemn, and a gnome's hat and beard for Gnomish
## Subcontractors. Each is drawn once and kept.

const SIZE := 48
const OUTLINE := Color(0.07, 0.05, 0.05)

static var _made := {}


## The pointer for spell `id`.
static func image(id: String) -> Image:
	if not _made.has(id):
		_made[id] = _draw(id)
	return _made[id]


static func hotspot() -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5


static func _draw(id: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match id:
		"fireball":
			_shape(img, func(p: Vector2) -> float: return _flame(p, Vector2(24, 36), 12.0, 1.0, 30.0), Color(0.95, 0.35, 0.08))
			_shape(img, func(p: Vector2) -> float: return _flame(p, Vector2(24, 38), 7.0, 0.5, 18.0), Color(1.0, 0.78, 0.2), false)
			_shape(img, func(p: Vector2) -> float: return _flame(p, Vector2(24, 39), 3.5, 0.3, 9.0), Color(1.0, 0.97, 0.75), false)
		"lightning":
			var bolt := [Vector2(29, 4), Vector2(18, 22), Vector2(27, 23), Vector2(15, 44)]
			_shape(img, func(p: Vector2) -> float: return _polyline(p, bolt) - 2.6, Color(1.0, 0.95, 0.55))
			_shape(img, func(p: Vector2) -> float: return _polyline(p, bolt) - 1.0, Color(1.0, 1.0, 1.0), false)
			for spark: Vector3 in [Vector3(9, 14, 2.2), Vector3(38, 15, 1.8), Vector3(36, 34, 2.4), Vector3(8, 33, 1.6), Vector3(40, 26, 1.4)]:
				_shape(img, func(p: Vector2) -> float: return _star(p, Vector2(spark.x, spark.y), spark.z * 2.4, spark.z * 0.7), Color(0.75, 0.9, 1.0))
		"rain":
			var puffs := [Vector3(14, 18, 8.0), Vector3(24, 13, 10.0), Vector3(34, 18, 8.0), Vector3(24, 21, 8.0)]
			var cloud := func(p: Vector2) -> float:
				var d := INF
				for c: Vector3 in puffs:
					d = minf(d, p.distance_to(Vector2(c.x, c.y)) - c.z)
				return d
			_shape(img, cloud, Color(0.92, 0.94, 0.98))
			for drop: Vector2 in [Vector2(14, 34), Vector2(24, 40), Vector2(34, 33)]:
				_shape(img, func(p: Vector2) -> float: return _flame(p, drop, 3.2, 0.4, 7.0), Color(0.3, 0.58, 1.0))
		"roots":
			var strands := [
				[Vector2(24, 4), Vector2(24, 16), Vector2(18, 26), Vector2(10, 32), Vector2(5, 42)],
				[Vector2(24, 16), Vector2(27, 28), Vector2(24, 38), Vector2(26, 45)],
				[Vector2(24, 12), Vector2(33, 22), Vector2(40, 30), Vector2(43, 42)],
				[Vector2(18, 26), Vector2(14, 38)],
				[Vector2(33, 22), Vector2(32, 34)],
			]
			for k in strands.size():
				var strand: Array = strands[k]
				var thick := 3.0 if k < 3 else 2.0
				_shape(img, func(p: Vector2) -> float: return _polyline(p, strand) - thick, Color(0.55, 0.36, 0.2))
			_shape(img, func(p: Vector2) -> float: return _leaf(p, Vector2(24, 7), Vector2(15, 4)), Color(0.35, 0.8, 0.3))
			_shape(img, func(p: Vector2) -> float: return _leaf(p, Vector2(24, 7), Vector2(33, 3)), Color(0.45, 0.88, 0.35))
		"blood":
			var skull := func(p: Vector2) -> float:
				return minf(p.distance_to(Vector2(24, 18)) - 13.0, _box(p, Vector2(24, 30), Vector2(7.5, 5.0)) - 1.5)
			_shape(img, skull, Color(0.94, 0.92, 0.84))
			for eye: Vector2 in [Vector2(19, 19), Vector2(29, 19)]:
				_shape(img, func(p: Vector2) -> float: return p.distance_to(eye) - 3.6, Color(0.12, 0.02, 0.03), false)
			_shape(img, func(p: Vector2) -> float: return _flame(p, Vector2(24, 26), 1.8, 0.6, 3.5), Color(0.12, 0.02, 0.03), false)
			for tooth in 3:
				var x := 20.0 + tooth * 4.0
				_shape(img, func(p: Vector2) -> float: return _segment(p, Vector2(x, 30), Vector2(x, 34)) - 0.6, OUTLINE, false)
			for drip: Vector3 in [Vector3(18, 41, 7.0), Vector3(26, 44, 10.0), Vector3(32, 39, 5.0)]:
				var trickle := func(p: Vector2) -> float:
					return minf(_segment(p, Vector2(drip.x, 33), Vector2(drip.x, drip.y - 3.0)) - 1.6, _flame(p, Vector2(drip.x, drip.y), 2.6, 0.5, 5.0))
				_shape(img, trickle, Color(0.82, 0.05, 0.08))
		"gnomes":
			# A gnome's tall red hat over a white beard.
			var hat := func(p: Vector2) -> float: return _flame(Vector2(p.x, p.y), Vector2(24, 26), 13.0, 1.0, 22.0)
			_shape(img, hat, Color(0.85, 0.12, 0.1))
			var brim := func(p: Vector2) -> float: return _box(p, Vector2(24, 27), Vector2(15.0, 2.5)) - 1.0
			_shape(img, brim, Color(0.7, 0.08, 0.08))
			var beard := func(p: Vector2) -> float: return _flame(Vector2(p.x, 2.0 * 30.0 - p.y), Vector2(24, 30), 11.0, 1.0, 16.0)
			_shape(img, beard, Color(0.97, 0.97, 0.97))
			var nose := func(p: Vector2) -> float: return p.distance_to(Vector2(24, 32)) - 3.5
			_shape(img, nose, Color(0.98, 0.7, 0.6))
		"bless":
			_shape(img, func(p: Vector2) -> float: return _star(p, Vector2(24, 24), 20.0, 5.0), Color(1.0, 0.85, 0.25))
			_shape(img, func(p: Vector2) -> float: return _star(p, Vector2(24, 24), 9.0, 3.0), Color(1.0, 0.98, 0.8), false)
		"hammer":
			# A builder's hammer: a wooden handle and an iron head.
			_shape(img, func(p: Vector2) -> float: return _segment(p, Vector2(14, 41), Vector2(30, 17)) - 3.2, Color(0.72, 0.5, 0.28))
			var head := func(p: Vector2) -> float:
				var q := (p - Vector2(30, 15)).rotated(-0.98)
				return _box(q, Vector2.ZERO, Vector2(12.0, 5.0)) - 1.0
			_shape(img, head, Color(0.62, 0.64, 0.7))
		"charm":
			# A pink heart with a shine on it.
			_shape(img, func(p: Vector2) -> float: return _heart(p, Vector2(24, 25), 1.0), Color(1.0, 0.42, 0.7))
			_shape(img, func(p: Vector2) -> float: return p.distance_to(Vector2(17, 17)) - 3.2, Color(1.0, 0.85, 0.93), false)
		"condemn":
			_shape(img, func(p: Vector2) -> float: return _star(p, Vector2(24, 24), 20.0, 5.0), Color(0.75, 0.06, 0.1))
			_shape(img, func(p: Vector2) -> float: return p.distance_to(Vector2(24, 24)) - 4.5, Color(0.2, 0.0, 0.05), false)
	return img


## Paints one shape given by its signed distance (in pixels, negative
## inside), smoothed at the edge, over a dark outline unless `outlined` is
## false.
static func _shape(img: Image, sdf: Callable, fill: Color, outlined := true) -> void:
	for y in SIZE:
		for x in SIZE:
			var d: float = sdf.call(Vector2(x + 0.5, y + 0.5))
			var c := img.get_pixel(x, y)
			if outlined:
				var o := clampf(0.5 - (d - 1.8), 0.0, 1.0)
				if o > 0.0:
					c = c.blend(Color(OUTLINE, o))
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				c = c.blend(Color(fill, a * fill.a))
			img.set_pixel(x, y, c)


## A flame or a drop: round at `base` (radius `r1`), drawn up to a point
## `tall` pixels above (radius `r2`).
static func _flame(p: Vector2, base: Vector2, r1: float, r2: float, tall: float) -> float:
	var q := Vector2(absf(p.x - base.x), base.y - p.y)
	var b := (r1 - r2) / tall
	var a := sqrt(maxf(0.0, 1.0 - b * b))
	var k := q.dot(Vector2(-b, a))
	if k < 0.0:
		return q.length() - r1
	if k > a * tall:
		return q.distance_to(Vector2(0.0, tall)) - r2
	return q.dot(Vector2(a, b)) - r1


## A heart centred on `c`, about 36 pixels across at `s` 1: two round lobes
## over a point.
static func _heart(p: Vector2, c: Vector2, s: float) -> float:
	var q := (p - c) / s
	var lobes := minf(q.distance_to(Vector2(-7.5, -6.0)) - 9.5, q.distance_to(Vector2(7.5, -6.0)) - 9.5)
	var point := (absf(q.x) + absf(q.y - 1.0)) / sqrt(2.0) - 11.5
	return minf(lobes, maxf(point, -q.y - 6.0)) * s


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _polyline(p: Vector2, points: Array) -> float:
	var d := INF
	for k in points.size() - 1:
		d = minf(d, _segment(p, points[k], points[k + 1]))
	return d


static func _box(p: Vector2, centre: Vector2, half: Vector2) -> float:
	var q := (p - centre).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


## A four-pointed star: `reach` to each tip, `waist` wide at the middle.
static func _star(p: Vector2, centre: Vector2, reach: float, waist: float) -> float:
	var q := (p - centre).abs()
	return minf(_flame(Vector2(q.x, -q.y), Vector2.ZERO, waist, 0.3, reach), _flame(Vector2(q.y, -q.x), Vector2.ZERO, waist, 0.3, reach))


## A leaf from `a` to `b`.
static func _leaf(p: Vector2, a: Vector2, b: Vector2) -> float:
	var mid := (a + b) * 0.5
	var along := (b - a).normalized()
	var half := a.distance_to(b) * 0.5
	var local := Vector2((p - mid).dot(along), (p - mid).dot(Vector2(-along.y, along.x)))
	return Vector2(local.x / half, local.y / (half * 0.45)).length() * half * 0.45 - half * 0.45
