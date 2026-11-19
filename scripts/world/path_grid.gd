class_name PathGrid
extends RefCounted
## Finds the quickest way over the island on foot. The ground is cut into
## CELL-metre squares, and each is given a cost from how steep it is, so
## routes go round slopes unless there is no other way. Squares steeper
## than Balance "cliff_grade" (a sheer cliff), off the island, or (for
## those who cannot swim) under water are not walked at all.
##
## Buildings stand in the way too: each one blocks the squares under it
## (add_building(), which every building does for itself), so routes go
## round them, and building_in_way() lets a walker step round one it is
## about to bump into.
##
## It keeps itself up to date as the terrain is reshaped. Get it from
## Game.path_grid().

const CELL := 2.0
## How much of a building's footprint (Destructible.footprint, a rough
## radius drawn generously) is solid wall that nobody walks through.
const WALL_SHARE := 0.62

var terrain: Terrain

## For villagers (water is in the way) and for goblins (who wade and swim).
var _land := AStarGrid2D.new()
var _swim := AStarGrid2D.new()
var _w := 0
var _dirty := Rect2i()
var _has_dirty := false
## Square -> how many buildings' walls stand on it (it is not walked);
## square -> the buildings whose walls come near it (for building_at());
## building -> {"solid": its walled squares, "near": the squares near it}.
var _walled := {}
var _walls := {}
var _blocks := {}


func setup(t: Terrain) -> void:
	terrain = t
	_w = ceili(Terrain.SIZE / CELL)
	for grid: AStarGrid2D in [_land, _swim]:
		grid.region = Rect2i(0, 0, _w, _w)
		grid.cell_size = Vector2(CELL, CELL)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
	_refresh(Rect2i(0, 0, _w, _w))
	t.changed.connect(_on_changed)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group("buildings"):
			if node is Destructible and node.is_inside_tree():
				add_building(node)


func _on_changed(center: Vector3, radius: float) -> void:
	var lo := _cell(center - Vector3(radius + CELL, 0, radius + CELL))
	var hi := _cell(center + Vector3(radius + CELL, 0, radius + CELL))
	var r := Rect2i(lo, hi - lo + Vector2i.ONE)
	_dirty = _dirty.merge(r) if _has_dirty else r
	_has_dirty = true


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int((p.x + Terrain.HALF) / CELL), 0, _w - 1), clampi(int((p.z + Terrain.HALF) / CELL), 0, _w - 1))


func _centre(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL - Terrain.HALF, 0.0, (c.y + 0.5) * CELL - Terrain.HALF)


## Works out the cost of every square in `r` again.
func _refresh(r: Rect2i) -> void:
	var n := Terrain.N
	var size := Terrain.SIZE
	var heights := terrain.heights
	var island := terrain.island
	var water := terrain.water
	var slow_from := Balance.num("slope_slow_from")
	var cliff := Balance.num("cliff_grade")
	for cj in range(maxi(r.position.y, 0), mini(r.end.y, _w)):
		for ci in range(maxi(r.position.x, 0), mini(r.end.x, _w)):
			var id := Vector2i(ci, cj)
			# The sample in the middle of the square, and its neighbours.
			var i := mini(ci * 2 + 1, size - 1)
			var j := mini(cj * 2 + 1, size - 1)
			var k := j * n + i
			var solid := island[k] == 0 or i < 3 or j < 3 or i > size - 3 or j > size - 3
			if not solid:
				solid = island[k - 2] == 0 or island[k + 2] == 0 or island[k - 2 * n] == 0 or island[k + 2 * n] == 0
			if solid:
				_land.set_point_solid(id, true)
				_swim.set_point_solid(id, true)
				continue
			var h := heights[k]
			var grade := maxf(maxf(absf(heights[k - 1] - h), absf(heights[k + 1] - h)), maxf(absf(heights[k - n] - h), absf(heights[k + n] - h)))
			var weight := 1.0 + clampf((grade - slow_from) * 8.0, 0.0, 9.0)
			# A grey rock slope (as Terrain.is_steep() sees it) is not walked.
			var across := Vector2(heights[k - 1] - heights[k + 1], heights[k - n] - heights[k + n]).length() * 0.5
			var steep := across > cliff
			var wet := water[k] != Terrain.NO_WATER and water[k] - h > 0.15
			var walled := _walled.has(id)
			_land.set_point_solid(id, steep or wet or walled)
			# Swimmers float over whatever the bottom is like.
			_swim.set_point_solid(id, (steep and not wet) or walled)
			_land.set_point_weight_scale(id, weight)
			_swim.set_point_weight_scale(id, 3.0 if wet else weight)


## How far from its middle `building`'s walls reach.
static func wall_radius(building: Destructible) -> float:
	return building.footprint * WALL_SHARE


## `building` now stands where it is: its squares are not walked.
func add_building(building: Destructible) -> void:
	if _blocks.has(building):
		remove_building(building)
	var c := building.global_position
	var r := wall_radius(building)
	var solid: Array[Vector2i] = []
	var near: Array[Vector2i] = []
	var lo := _cell(c - Vector3(r + CELL, 0, r + CELL))
	var hi := _cell(c + Vector3(r + CELL, 0, r + CELL))
	for cj in range(lo.y, hi.y + 1):
		for ci in range(lo.x, hi.x + 1):
			var id := Vector2i(ci, cj)
			var mid := _centre(id)
			var d := Vector2(mid.x - c.x, mid.z - c.z).length()
			if d < r:
				solid.append(id)
				_walled[id] = _walled.get(id, 0) + 1
				_land.set_point_solid(id, true)
				_swim.set_point_solid(id, true)
			if d < r + CELL:
				near.append(id)
				if not _walls.has(id):
					_walls[id] = []
				(_walls[id] as Array).append(building)
	_blocks[building] = {"solid": solid, "near": near}
	if not building.has_meta("path_walls"):
		building.set_meta("path_walls", true)
		building.tree_exiting.connect(func() -> void:
			building.remove_meta("path_walls")
			remove_building(building), CONNECT_ONE_SHOT)


## `building` is gone (burnt down, blown apart, taken away).
func remove_building(building: Destructible) -> void:
	if not _blocks.has(building):
		return
	var cells: Dictionary = _blocks[building]
	_blocks.erase(building)
	for id: Vector2i in cells.near:
		var list: Array = _walls.get(id, [])
		list.erase(building)
		if list.is_empty():
			_walls.erase(id)
	var first := true
	var touched := Rect2i()
	for id: Vector2i in cells.solid:
		_walled[id] = _walled.get(id, 1) - 1
		if _walled[id] <= 0:
			_walled.erase(id)
		touched = Rect2i(id, Vector2i.ONE) if first else touched.merge(Rect2i(id, Vector2i.ONE))
		first = false
	if not first:
		# Work the freed squares out again from the ground.
		_dirty = _dirty.merge(touched) if _has_dirty else touched
		_has_dirty = true


## The building whose walls `p` is inside, or null.
func building_at(p: Vector3) -> Destructible:
	for node: Variant in _walls.get(_cell(p), []):
		var b := node as Destructible
		if is_instance_valid(b) and Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < wall_radius(b):
			return b
	return null


func _flush() -> void:
	if _has_dirty:
		_has_dirty = false
		_refresh(_dirty)


## True if the straight line from `from` to `to` is easy going all the
## way: no cliff, no water (unless `swim`) and no steep ground.
func clear_line(from: Vector3, to: Vector3, swim := false) -> bool:
	_flush()
	var grid := _swim if swim else _land
	var steps := maxi(1, ceili(Vector2(to.x - from.x, to.z - from.z).length() / (CELL * 0.7)))
	for s in steps + 1:
		var c := _cell(from.lerp(to, s / float(steps)))
		if grid.is_point_solid(c) or grid.get_point_weight_scale(c) > 1.6:
			return false
	return true


## The way from `from` to `to` as a list of points to walk through, ending
## at `to` (or as near as can be reached). Empty if there is no way at all.
func find(from: Vector3, to: Vector3, swim := false) -> PackedVector3Array:
	_flush()
	var grid := _swim if swim else _land
	var a := _open_near(grid, _cell(from))
	var b := _cell(to)
	var ids := grid.get_id_path(a, b, true)
	var out := PackedVector3Array()
	if ids.size() < 2:
		return out
	# Keep the corners only.
	for k in range(1, ids.size() - 1):
		if ids[k] - ids[k - 1] != ids[k + 1] - ids[k]:
			out.append(_centre(ids[k]))
	out.append(Vector3(to.x, 0.0, to.z) if ids[ids.size() - 1] == b else _centre(ids[ids.size() - 1]))
	return out


## `c`, or the nearest square to it that can be walked.
func _open_near(grid: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not grid.is_point_solid(c):
		return c
	for ring in range(1, 5):
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				var q := c + Vector2i(di, dj)
				if q.x >= 0 and q.y >= 0 and q.x < _w and q.y < _w and not grid.is_point_solid(q):
					return q
	return c
