class_name MeshBuilder
extends RefCounted
## Builds meshes in code out of smooth, rounded shapes: lathed profiles,
## bevelled boxes, tubes, lumpy blobs, curved sheets and leaf cards. Several
## shapes can be added to one builder; commit() returns them as one mesh.
##
## Triangles are wound clockwise (Godot's front face). For a triangle
## (a, b, c) the front normal is cross(c - a, b - a).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
## Vertex colour given to everything added from now on.
var color := Color.WHITE


func is_empty() -> bool:
	return indices.is_empty()


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _v(p: Vector3, n: Vector3, uv := Vector2.ZERO) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(color)
	uvs.append(uv)
	return verts.size() - 1


func _quad(a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c, b, d, c]))


# --- Shapes -----------------------------------------------------------------

## Spins a profile of (radius, height) points around the Y axis. Repeat a
## point to get a hard edge there. `lobes` adds pumpkin-like bulges; `flat`
## gives faceted sides (use it with few segments for pyramids).
func add_lathe(profile: PackedVector2Array, segments: int, xf := Transform3D.IDENTITY,
		lobes := 0, lobe_depth := 0.0, flat := false) -> int:
	var start := verts.size()
	var n := profile.size()
	var ring_pos: Array[PackedVector3Array] = []
	var ring_nrm: Array[PackedVector3Array] = []
	for i in n:
		var a := profile[maxi(i - 1, 0)]
		var b := profile[mini(i + 1, n - 1)]
		if i > 0 and profile[i].is_equal_approx(profile[i - 1]):
			a = profile[i]
		if i < n - 1 and profile[i].is_equal_approx(profile[i + 1]):
			b = profile[i]
		var t := b - a
		t = t.normalized() if t.length_squared() > 1e-9 else Vector2(0, 1)
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		for s in segments:
			var ang := TAU * s / segments
			var r := profile[i].x
			if lobes > 0:
				r *= 1.0 + lobe_depth * cos(ang * lobes)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			pos.append(xf * (dir * r + Vector3(0.0, profile[i].y, 0.0)))
			nrm.append((xf.basis * (dir * t.y + Vector3(0.0, -t.x, 0.0))).normalized())
		ring_pos.append(pos)
		ring_nrm.append(nrm)

	if flat:
		for i in n - 1:
			for s in segments:
				var s2 := (s + 1) % segments
				var pa := ring_pos[i][s]
				var pb := ring_pos[i][s2]
				var pc := ring_pos[i + 1][s]
				var pd := ring_pos[i + 1][s2]
				var fn := (pc - pa).cross(pb - pa)
				if fn.length_squared() < 1e-10:
					fn = (pc - pb).cross(pd - pb)
				if fn.length_squared() < 1e-10:
					continue
				fn = fn.normalized()
				_quad(_v(pa, fn), _v(pb, fn), _v(pc, fn), _v(pd, fn))
		return start

	for i in n:
		for s in segments:
			_v(ring_pos[i][s], ring_nrm[i][s])
	for i in n - 1:
		if profile[i].is_equal_approx(profile[i + 1]):
			continue
		for s in segments:
			var s2 := (s + 1) % segments
			var a := start + i * segments + s
			var b := start + i * segments + s2
			_quad(a, b, a + segments, b + segments)
	return start


## A box with rounded edges. `taper` scales the top face in x and z.
func add_box(size: Vector3, bevel: float, xf := Transform3D.IDENTITY, taper := Vector2.ONE) -> int:
	var start := verts.size()
	var h := size * 0.5
	var r := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	var lim := h - Vector3(r, r, r)
	var x := Vector3.RIGHT
	var y := Vector3.UP
	var z := Vector3.BACK
	for f in [[x, z, y], [z, x, -y], [z, y, x], [y, z, -x], [y, x, z], [x, y, -z]]:
		var u: Vector3 = f[0]
		var v: Vector3 = f[1]
		var w: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var hw := absf(w.dot(h))
		var cu := [-hu, -hu + r, hu - r, hu]
		var cv := [-hv, -hv + r, hv - r, hv]
		var base := verts.size()
		for j in 4:
			for i in 4:
				var p: Vector3 = u * cu[i] + v * cv[j] + w * hw
				var inner := Vector3(clampf(p.x, -lim.x, lim.x), clampf(p.y, -lim.y, lim.y), clampf(p.z, -lim.z, lim.z))
				var nrm := (p - inner).normalized()
				var pos := inner + nrm * r
				var ty := (pos.y + h.y) / size.y
				pos.x *= lerpf(1.0, taper.x, ty)
				pos.z *= lerpf(1.0, taper.y, ty)
				_v(xf * pos, (xf.basis * nrm).normalized())
		for j in 3:
			for i in 3:
				var a := base + j * 4 + i
				_quad(a, a + 1, a + 4, a + 5)
	return start


## A round tube that follows a path, with a radius per point.
func add_tube(points: PackedVector3Array, radii: PackedFloat32Array, segments: int,
		xf := Transform3D.IDENTITY, caps := true) -> int:
	var start := verts.size()
	var n := points.size()
	var frame_x := Vector3.ZERO
	var first_along := Vector3.UP
	var last_along := Vector3.UP
	for i in n:
		var along := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		if i == 0:
			first_along = along
			frame_x = along.cross(Vector3.FORWARD)
			if frame_x.length_squared() < 0.01:
				frame_x = along.cross(Vector3.RIGHT)
		else:
			frame_x = frame_x - along * frame_x.dot(along)
		frame_x = frame_x.normalized()
		last_along = along
		var frame_z := frame_x.cross(along)
		for s in segments:
			var ang := TAU * s / segments
			var dir := frame_x * cos(ang) + frame_z * sin(ang)
			_v(xf * (points[i] + dir * radii[i]), (xf.basis * dir).normalized())
	for i in n - 1:
		for s in segments:
			var s2 := (s + 1) % segments
			var a := start + i * segments + s
			var b := start + i * segments + s2
			_quad(a, b, a + segments, b + segments)
	if caps:
		var c0 := _v(xf * points[0], (xf.basis * -first_along).normalized())
		var c1 := _v(xf * points[n - 1], (xf.basis * last_along).normalized())
		var last := start + (n - 1) * segments
		for s in segments:
			var s2 := (s + 1) % segments
			indices.append_array(PackedInt32Array([c0, start + s2, start + s, c1, last + s, last + s2]))
	return start


## A ring-shaped tube (a torus) lying in the XY plane of `xf`.
func add_ring(radius: float, thickness: float, xf := Transform3D.IDENTITY, sides := 16, segments := 8) -> int:
	var start := verts.size()
	for i in sides:
		var a := TAU * i / sides
		var centre := Vector3(cos(a), sin(a), 0.0) * radius
		var out := Vector3(cos(a), sin(a), 0.0)
		for s in segments:
			var b := TAU * s / segments
			var dir := out * cos(b) + Vector3.BACK * sin(b)
			_v(xf * (centre + dir * thickness), (xf.basis * dir).normalized())
	for i in sides:
		var i2 := (i + 1) % sides
		for s in segments:
			var s2 := (s + 1) % segments
			_quad(start + i * segments + s, start + i * segments + s2, start + i2 * segments + s, start + i2 * segments + s2)
	return start


## A squashed sphere. With `noise` it becomes a lumpy boulder.
func add_blob(radii: Vector3, xf := Transform3D.IDENTITY, noise: FastNoiseLite = null,
		amp := 0.0, rings := 10, segments := 16) -> int:
	var start := verts.size()
	for j in rings + 1:
		var phi := PI * j / rings
		for s in segments:
			var ang := TAU * s / segments
			var dir := Vector3(cos(ang) * sin(phi), -cos(phi), sin(ang) * sin(phi))
			var p := dir * radii
			if noise != null:
				p *= 1.0 + amp * noise.get_noise_3dv(p)
			var nrm := (dir / radii).normalized()
			_v(xf * p, (xf.basis * nrm).normalized())
	for j in rings:
		for s in segments:
			var s2 := (s + 1) % segments
			var a := start + j * segments + s
			var b := start + j * segments + s2
			_quad(a, b, a + segments, b + segments)
	return start


## A curved sheet: `fn` maps (u, v) in 0..1 to a point. The front side is
## cross(dv, du); pass flip = true to face the other way.
func add_grid(nu: int, nv: int, fn: Callable, xf := Transform3D.IDENTITY, flip := false) -> int:
	var start := verts.size()
	var pts := PackedVector3Array()
	for j in nv + 1:
		for i in nu + 1:
			pts.append(fn.call(float(i) / nu, float(j) / nv))
	var row := nu + 1
	for j in nv + 1:
		for i in nu + 1:
			var du := pts[j * row + mini(i + 1, nu)] - pts[j * row + maxi(i - 1, 0)]
			var dv := pts[mini(j + 1, nv) * row + i] - pts[maxi(j - 1, 0) * row + i]
			var nrm := dv.cross(du).normalized()
			if flip:
				nrm = -nrm
			_v(xf * pts[j * row + i], (xf.basis * nrm).normalized(), Vector2(float(i) / nu, float(j) / nv))
	for j in nv:
		for i in nu:
			var a := start + j * row + i
			if flip:
				_quad(a + 1, a, a + row + 1, a + row)
			else:
				_quad(a, a + 1, a + row, a + row + 1)
	return start


## A flat polygon facing `normal`.
func add_fan(points: PackedVector3Array, normal: Vector3, xf := Transform3D.IDENTITY) -> int:
	var start := verts.size()
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()
	var n := (xf.basis * normal).normalized()
	var c := _v(xf * centre, n)
	for p in points:
		_v(xf * p, n)
	for i in points.size():
		var a := c + 1 + i
		var b := c + 1 + (i + 1) % points.size()
		if (points[(i + 1) % points.size()] - centre).cross(points[i] - centre).dot(normal) > 0.0:
			indices.append_array(PackedInt32Array([c, a, b]))
		else:
			indices.append_array(PackedInt32Array([c, b, a]))
	return start


## A textured card (for leaves). All four corners share `shade_normal`.
func add_card(centre: Vector3, half_right: Vector3, half_up: Vector3, shade_normal: Vector3) -> int:
	var a := _v(centre - half_right - half_up, shade_normal, Vector2(0, 1))
	var b := _v(centre + half_right - half_up, shade_normal, Vector2(1, 1))
	var c := _v(centre - half_right + half_up, shade_normal, Vector2(0, 0))
	var d := _v(centre + half_right + half_up, shade_normal, Vector2(1, 0))
	_quad(a, b, c, d)
	return a


# --- Deformers (apply to everything added since index `from`) ----------------

## Pushes vertices sideways, more the higher they are (a curved lean).
func bend(from: int, y0: float, y1: float, offset: Vector3) -> void:
	for k in range(from, verts.size()):
		var t := clampf((verts[k].y - y0) / (y1 - y0), 0.0, 1.0)
		verts[k] += offset * t * t


## Twists vertices around the Y axis, more the higher they are.
func twist(from: int, y0: float, y1: float, angle: float) -> void:
	for k in range(from, verts.size()):
		var t := clampf((verts[k].y - y0) / (y1 - y0), 0.0, 1.0)
		var rot := Basis(Vector3.UP, angle * t)
		verts[k] = rot * verts[k]
		normals[k] = rot * normals[k]


## Darkens vertices near the bottom, faking soft shadow where things meet
## the ground.
func ground_shade(from: int, y0: float, y1: float, strength := 0.25) -> void:
	for k in range(from, verts.size()):
		var t := clampf((verts[k].y - y0) / (y1 - y0), 0.0, 1.0)
		var c := colors[k]
		var f := lerpf(1.0 - strength, 1.0, t)
		colors[k] = Color(c.r * f, c.g * f, c.b * f, c.a)
