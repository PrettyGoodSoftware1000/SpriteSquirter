class_name WorldPopulator
extends RefCounted
## Fills a freshly generated terrain with villages, villagers, a goblin
## cave, trees, rocks and a few small islands drifting nearby.


static func populate(parent: Node3D, terrain: Terrain, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1234
	_place_villages(parent, terrain, rng)
	var cave := _place_cave(parent, terrain, rng)
	_place_trees(parent, terrain, rng, cave)
	_place_rocks(parent, terrain, rng)
	_place_sky_islands(parent, rng)


static func _place_villages(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator) -> void:
	for site in terrain.village_sites:
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
			parent.add_child(b)
			b.position = Vector3(p.x, terrain.get_height(p.x, p.y), p.y)
			# Doors face the middle of the village.
			b.rotation.y = atan2(c.x - p.x, c.y - p.y)
			terrain.add_bare(b.position, b.footprint + 1.5, 0.9)
			placed.append(p)
		for k in rng.randi_range(14, 22):
			spawn_villager(parent, terrain, Vector3(c.x, 0.0, c.y), r)


## Puts a cave on open ground well away from every village, with goblin
## huts and goblins around it. Returns the cave's position.
static func _place_cave(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator) -> Vector3:
	var best := Vector2.ZERO
	var best_score := -1000.0
	for attempt in 300:
		var p := Vector2(rng.randf_range(-95.0, 95.0), rng.randf_range(-95.0, 95.0))
		if not terrain.is_inside(p.x, p.y) or p.length() > 88.0:
			continue
		var h := terrain.get_height(p.x, p.y)
		if h < 1.2 or h > 12.0 or terrain._river_distance(p) < 22.0 or terrain._relief(p, 12.0) > 6.0:
			continue
		var nearest := 1000.0
		for site in terrain.village_sites:
			nearest = minf(nearest, p.distance_to(site.pos))
		# Far from the villages, and backing onto higher ground if possible.
		var score := minf(nearest, 90.0) + rng.randf() * 10.0
		if nearest > 45.0 and score > best_score:
			best_score = score
			best = p
	var centre := Vector3(best.x, terrain.get_height(best.x, best.y), best.y)
	# The cave mouth faces the middle of the island.
	var facing := atan2(-best.x, -best.y)
	var front := Vector3(sin(facing), 0, cos(facing))
	var side := Vector3(front.z, 0, -front.x)
	terrain.apply_brush(centre + front * 6.0, 16.0, Terrain.Brush.FLATTEN, 1.0, centre.y, 0.6)
	var cave := BuildingFactory.create_cave(rng)
	parent.add_child(cave)
	cave.position = Vector3(centre.x, terrain.get_height(centre.x, centre.z), centre.z)
	cave.rotation.y = facing
	terrain.add_bare(centre + front * 8.0, 13.0, 0.85)
	for s in [-1.0, 1.0]:
		var p: Vector3 = centre + front * 11.0 + side * s * 13.0
		var hut := BuildingFactory.create("goblin_hut", rng)
		parent.add_child(hut)
		hut.position = Vector3(p.x, terrain.get_height(p.x, p.z), p.z)
		hut.rotation.y = facing - s * 0.6
		terrain.add_bare(hut.position, hut.footprint + 1.0, 0.9)
	var camp := centre + front * 10.0
	for k in rng.randi_range(9, 13):
		var g := spawn_villager(parent, terrain, camp, 9.0, true)
		g.rotation.y = rng.randf() * TAU
	return centre


static func spawn_villager(parent: Node3D, terrain: Terrain, home: Vector3, radius: float, goblin := false) -> Villager:
	var v := Villager.new()
	v.goblin = goblin
	v.home = home
	v.home_radius = radius
	parent.add_child(v)
	var a := randf() * TAU
	var d := randf() * radius * 0.8
	var x := home.x + cos(a) * d
	var z := home.z + sin(a) * d
	v.position = Vector3(x, terrain.get_height(x, z), z)
	return v


static func _place_trees(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator, cave: Vector3) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.02
	var count := 0
	for attempt in 5000:
		if count >= 320:
			break
		var x := rng.randf_range(-118.0, 118.0)
		var z := rng.randf_range(-118.0, 118.0)
		var h := terrain.get_height(x, z)
		if h < 0.8 or h > 24.0 or terrain.get_normal(x, z).y < 0.82 or not terrain.is_inside(x, z):
			continue
		if Vector2(x - cave.x, z - cave.z).length() < 22.0:
			continue
		# Trees clump into woods, with a few loners in between.
		if forest.get_noise_2d(x, z) < 0.05 and rng.randf() > 0.06:
			continue
		var in_village := false
		for site in terrain.village_sites:
			var r: float = site.radius
			if Vector2(x, z).distance_to(site.pos) < r + 3.0:
				in_village = true
				break
		if in_village:
			continue
		var tree := FloraFactory.create_tree(rng)
		parent.add_child(tree)
		tree.position = Vector3(x, h, z)
		tree.rotation.y = rng.randf() * TAU
		count += 1


static func _place_rocks(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator) -> void:
	var count := 0
	for attempt in 2000:
		if count >= 110:
			break
		var x := rng.randf_range(-120.0, 120.0)
		var z := rng.randf_range(-120.0, 120.0)
		var h := terrain.get_height(x, z)
		if h < -0.5 or not terrain.is_inside(x, z):
			continue
		# Boulders gather on slopes and shores, with a few strays in the fields.
		var steep := terrain.get_normal(x, z).y < 0.9
		if not steep and h > 1.2 and rng.randf() > 0.08:
			continue
		var near_village := false
		for site in terrain.village_sites:
			var r: float = site.radius
			if Vector2(x, z).distance_to(site.pos) < r:
				near_village = true
				break
		if near_village:
			continue
		var rock := FloraFactory.create_rock(rng)
		parent.add_child(rock)
		rock.position = Vector3(x, h, z)
		count += 1


## Little chunks of land hanging in the sky around the main island.
static func _place_sky_islands(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.25, 0.25)
		var dist := rng.randf_range(150.0, 230.0)
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
