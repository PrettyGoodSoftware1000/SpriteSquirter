class_name WorldPopulator
extends RefCounted
## Fills a terrain with things: villages, villagers, goblin caves, trees,
## boulder fields and a few small islands drifting nearby.
##
## Random worlds use populate(). Maps from the editor use populate_nature()
## when they are first made and populate_from_map() when loaded. Every tree
## and rock gets its own seed (the "seed" meta) so a map file can rebuild it.

const START_CLEARING := 7.0
## Trees per square metre of island: the same on every map size.
const TREE_DENSITY := 0.0038
const CAVE_CLEARING := 22.0


## A complete random world. Returns {"starts": PackedVector2Array, "caves":
## Array} where each start is a village site (the player picks one) and
## every building and villager remembers its site in the "site" meta.
static func populate(parent: Node3D, terrain: Terrain, world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1234
	_place_villages(parent, terrain, rng)
	var avoid: Array[Vector3] = []
	for site in terrain.village_sites:
		var r: float = site.radius
		avoid.append(Vector3(site.pos.x, site.pos.y, r + 3.0))
	var caves: Array = []
	# One cave on a small island, two on a medium one, three on a large one.
	for k in clampi(roundi(Terrain.SCALE), 1, 3):
		var spot := _find_cave_spot(terrain, rng, caves)
		var facing := atan2(-spot.x, -spot.y)
		place_cave(parent, terrain, spot, facing, rng, true, true)
		caves.append({"pos": spot, "facing": facing})
		avoid.append(Vector3(spot.x, spot.y, CAVE_CLEARING))
	avoid.append_array(_place_rocks(parent, terrain, rng, avoid))
	_place_trees(parent, terrain, rng, avoid)
	_place_sky_islands(parent, rng)
	var starts := PackedVector2Array()
	for site in terrain.village_sites:
		starts.append(site.pos)
	return {"starts": starts, "caves": caves}


## Trees, rocks and sky islands only: the start of a new editor map.
static func populate_nature(parent: Node3D, terrain: Terrain, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1234
	_place_trees(parent, terrain, rng, _place_rocks(parent, terrain, rng, []))
	_place_sky_islands(parent, rng)


## Rebuilds a saved map. Goblins are left out in the editor.
static func populate_from_map(parent: Node3D, terrain: Terrain, data: Dictionary, with_goblins: bool) -> void:
	for t in data.trees:
		spawn_tree(parent, terrain, t[0], t[1], t[2], t[3])
	for r in data.rocks:
		var rock := spawn_rock(parent, terrain, r[0], r[1], r[2])
		# Boulders saved since map version 2 remember their size.
		if r.size() > 3:
			rock.scale = Vector3(r[3], r[3] * rock.scale.y / rock.scale.x, r[3])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed) + 77
	for c in data.caves:
		place_cave(parent, terrain, c.pos, c.facing, rng, false, with_goblins)
	var sky := RandomNumberGenerator.new()
	sky.seed = int(data.seed) + 1234
	_place_sky_islands(parent, sky)


static func _place_villages(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator) -> void:
	for site_index in terrain.village_sites.size():
		var site: Dictionary = terrain.village_sites[site_index]
		var c: Vector2 = site.pos
		var r: float = site.radius
		var placed: Array[Vector2] = []
		var wanted := rng.randi_range(6, 10)
		var attempts := 0
		while placed.size() < wanted and attempts < 200:
			attempts += 1
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(5.0, r)
			var free := true
			for other in placed:
				if other.distance_to(p) < 9.5:
					free = false
					break
			if not free:
				continue
			var b := BuildingFactory.create_building(rng)
			b.set_meta("site", site_index)
			parent.add_child(b)
			b.position = Vector3(p.x, terrain.get_height(p.x, p.y), p.y)
			# Doors face the middle of the village.
			b.rotation.y = atan2(c.x - p.x, c.y - p.y)
			terrain.add_bare(b.position, b.footprint + 1.5, 0.9)
			placed.append(p)
		# Every village starts with Balance "start_villagers". (The old
		# random number is still drawn, so the worlds come out as before.)
		rng.randi_range(14, 22)
		for k in roundi(Balance.num("start_villagers")):
			var v := spawn_villager(parent, terrain, Vector3(c.x, 0.0, c.y), r)
			v.set_meta("site", site_index)


## Open ground well away from every village and from other caves.
static func _find_cave_spot(terrain: Terrain, rng: RandomNumberGenerator, caves: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1000.0
	var reach := 95.0 * Terrain.SCALE
	for attempt in 300:
		var p := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		if not terrain.is_inside(p.x, p.y) or p.length() > reach - 7.0:
			continue
		var h := terrain.get_height(p.x, p.y)
		if h < 1.2 or h > 12.0 or terrain._river_distance(p) < 22.0 or terrain._relief(p, 12.0) > 6.0:
			continue
		var nearest := 1000.0
		for site in terrain.village_sites:
			nearest = minf(nearest, p.distance_to(site.pos))
		for c in caves:
			nearest = minf(nearest, p.distance_to(c.pos))
		var score := minf(nearest, 90.0) + rng.randf() * 10.0
		if nearest > 45.0 and score > best_score:
			best_score = score
			best = p
	return best


## Puts a cave at `spot` with its mouth facing `facing`, levelling the
## ground in front. Goblin huts are optional (maps never have buildings).
static func place_cave(parent: Node3D, terrain: Terrain, spot: Vector2, facing: float, rng: RandomNumberGenerator,
		huts: bool, goblins: bool) -> Node3D:
	var centre := Vector3(spot.x, terrain.get_height(spot.x, spot.y), spot.y)
	var front := Vector3(sin(facing), 0, cos(facing))
	var side := Vector3(front.z, 0, -front.x)
	terrain.apply_brush(centre + front * 6.0, 16.0, Terrain.Brush.FLATTEN, 1.0, centre.y, 0.6)
	var cave := BuildingFactory.create_cave(rng)
	cave.add_to_group("caves")
	cave.set_meta("facing", facing)
	parent.add_child(cave)
	cave.position = Vector3(centre.x, terrain.get_height(centre.x, centre.z), centre.z)
	cave.rotation.y = facing
	terrain.add_bare(centre + front * 8.0, 13.0, 0.85)
	if huts:
		for s in [-1.0, 1.0]:
			var p: Vector3 = centre + front * 11.0 + side * s * 13.0
			var hut := BuildingFactory.create("goblin_hut", rng)
			parent.add_child(hut)
			hut.position = Vector3(p.x, terrain.get_height(p.x, p.z), p.z)
			hut.rotation.y = facing - s * 0.6
			terrain.add_bare(hut.position, hut.footprint + 1.0, 0.9)
	if goblins:
		var camp := centre + front * 10.0
		for k in rng.randi_range(9, 13):
			var g := spawn_villager(parent, terrain, camp, 9.0, true)
			g.rotation.y = rng.randf() * TAU
	return cave


## Set `owned` for the player's villagers and `child` for a newborn.
static func spawn_villager(parent: Node3D, terrain: Terrain, home: Vector3, radius: float, goblin := false,
		owned := false, child := false) -> Villager:
	var v := Villager.new()
	v.goblin = goblin
	v.owned = owned
	v.child = child
	v.home = home
	v.home_radius = radius
	parent.add_child(v)
	var a := randf() * TAU
	var d := randf() * radius * 0.8
	var x := home.x + cos(a) * d
	var z := home.z + sin(a) * d
	v.position = Vector3(x, terrain.get_height(x, z), z)
	return v


static func spawn_tree(parent: Node3D, terrain: Terrain, x: float, z: float, rot: float, seed_value: int) -> Destructible:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tree := FloraFactory.create_tree(rng)
	tree.set_meta("seed", seed_value)
	parent.add_child(tree)
	tree.position = Vector3(x, terrain.get_height(x, z), z)
	tree.rotation.y = rot
	return tree


static func spawn_rock(parent: Node3D, terrain: Terrain, x: float, z: float, seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rock := FloraFactory.create_rock(rng)
	rock.set_meta("seed", seed_value)
	rock.add_to_group("rocks")
	parent.add_child(rock)
	rock.position = Vector3(x, terrain.get_height(x, z), z)
	return rock


## True where trees grow well: dry, not too high and not too steep.
static func good_tree_spot(terrain: Terrain, x: float, z: float) -> bool:
	var h := terrain.get_height(x, z)
	return terrain.is_inside(x, z) and h > 0.8 and h < 24.0 and terrain.get_normal(x, z).y > 0.82


static func _blocked(avoid: Array, x: float, z: float) -> bool:
	for a in avoid:
		var c: Vector3 = a
		if Vector2(x - c.x, z - c.y).length() < c.z:
			return true
	return false


## `avoid` holds Vector3(x, z, radius) circles to keep clear.
static func _place_trees(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator, avoid: Array) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.02
	var reach := 118.0 * Terrain.SCALE
	var wanted := roundi(TREE_DENSITY * PI * Terrain.ISLAND_RADIUS * Terrain.ISLAND_RADIUS)
	var count := 0
	for attempt in wanted * 16:
		if count >= wanted:
			break
		var x := rng.randf_range(-reach, reach)
		var z := rng.randf_range(-reach, reach)
		var tree_seed := rng.randi()
		var rot := rng.randf() * TAU
		if not good_tree_spot(terrain, x, z) or _blocked(avoid, x, z):
			continue
		# Trees clump into woods, with a few loners in between.
		if forest.get_noise_2d(x, z) < 0.05 and rng.randf() > 0.06:
			continue
		spawn_tree(parent, terrain, x, z, rot, tree_seed)
		count += 1


## Stone comes as boulder fields: a few small areas crowded with boulders,
## scattered at random over the island, with one in walking distance of
## every village site. Villagers break the boulders up for stone. Returns
## a Vector3(x, z, radius) circle for each field, so trees keep out.
static func _place_rocks(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator, avoid: Array) -> Array[Vector3]:
	var reach := 108.0 * Terrain.SCALE
	var centres: Array[Vector2] = []
	for site in terrain.village_sites:
		for attempt in 40:
			var a := rng.randf() * TAU
			var c: Vector2 = site.pos + Vector2(cos(a), sin(a)) * (site.radius + rng.randf_range(14.0, 34.0))
			if _boulder_spot(terrain, c, centres, avoid):
				centres.append(c)
				break
	var wanted := centres.size() + roundi(7 * Terrain.SCALE * Terrain.SCALE)
	for attempt in wanted * 30:
		if centres.size() >= wanted:
			break
		var c := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		if _boulder_spot(terrain, c, centres, avoid):
			centres.append(c)
	var circles: Array[Vector3] = []
	for c in centres:
		var spread := rng.randf_range(5.0, 9.0)
		circles.append(Vector3(c.x, c.y, spread + 1.5))
		for k in rng.randi_range(7, 12):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * spread
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			var rock_seed := rng.randi()
			var big := rng.randf_range(1.2, 1.9)
			if not terrain.is_inside(x, z) or terrain.get_height(x, z) < 0.3 or _blocked(avoid, x, z):
				continue
			var rock := spawn_rock(parent, terrain, x, z, rock_seed)
			rock.scale *= big
	return circles


## True if a boulder field can be centred on `c`: dry, fairly level ground
## away from villages, caves and other boulder fields.
static func _boulder_spot(terrain: Terrain, c: Vector2, others: Array[Vector2], avoid: Array) -> bool:
	if not terrain.is_inside(c.x, c.y) or terrain.get_height(c.x, c.y) < 0.8 or terrain.get_normal(c.x, c.y).y < 0.8:
		return false
	if c.length() > Terrain.ISLAND_RADIUS - 14.0:
		return false
	for a in avoid:
		var circle: Vector3 = a
		if Vector2(c.x - circle.x, c.y - circle.y).length() < circle.z + 9.0:
			return false
	for other in others:
		if other.distance_to(c) < 30.0:
			return false
	return true


## Little chunks of land hanging in the sky around the main island.
static func _place_sky_islands(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.25, 0.25)
		var dist := rng.randf_range(150.0, 230.0) * Terrain.SCALE
		var size := rng.randf_range(6.0, 16.0)
		var rock := MeshBuilder.new()
		var under := func(u: float, v: float) -> Vector3:
			var r := size * pow(1.0 - v, 0.7) * (1.0 + 0.25 * noise.get_noise_2d(u * 40.0, v * 20.0))
			return Vector3(cos(u * TAU) * r, -size * 1.7 * pow(v, 1.2), sin(u * TAU) * r)
		rock.add_grid(20, 6, under)
		var island := MeshInstance3D.new()
		island.mesh = rock.commit()
		island.material_override = Art.nature("rock")
		parent.add_child(island)
		island.position = Vector3(cos(a) * dist, rng.randf_range(-25.0, 30.0), sin(a) * dist)
		var turf := MeshBuilder.new()
		turf.add_blob(Vector3(size * 1.04, size * 0.22, size * 1.04), Transform3D.IDENTITY, noise, 0.2, 6, 20)
		var top := MeshInstance3D.new()
		top.mesh = turf.commit()
		top.material_override = Art.nature("turf")
		island.add_child(top)
		for t in rng.randi_range(1, 3):
			var tree := FloraFactory.create_tree(rng)
			tree.is_ghost = true
			island.add_child(tree)
			tree.position = Vector3(rng.randf_range(-0.5, 0.5) * size, size * 0.15, rng.randf_range(-0.5, 0.5) * size)
