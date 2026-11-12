class_name WorldPopulator
extends RefCounted
## Fills a freshly generated terrain with villages, villagers and trees.


static func populate(parent: Node3D, terrain: Terrain, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1234
	_place_villages(parent, terrain, rng)
	_place_trees(parent, terrain, rng)


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
				if other.distance_to(p) < 8.5:
					free = false
					break
			if not free:
				continue
			var b := BuildingFactory.create_building(rng)
			parent.add_child(b)
			b.position = Vector3(p.x, terrain.get_height(p.x, p.y), p.y)
			# Doors face the middle of the village.
			b.rotation.y = atan2(c.x - p.x, c.y - p.y)
			placed.append(p)
		for k in rng.randi_range(14, 22):
			spawn_villager(parent, terrain, Vector3(c.x, 0.0, c.y), r)


static func spawn_villager(parent: Node3D, terrain: Terrain, home: Vector3, radius: float) -> Villager:
	var v := Villager.new()
	v.home = home
	v.home_radius = radius
	parent.add_child(v)
	var a := randf() * TAU
	var d := randf() * radius * 0.8
	var x := home.x + cos(a) * d
	var z := home.z + sin(a) * d
	v.position = Vector3(x, terrain.get_height(x, z), z)
	return v


static func _place_trees(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator) -> void:
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
		if h < 0.8 or h > 24.0 or terrain.get_normal(x, z).y < 0.82:
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
		var tree := BuildingFactory.create_tree(rng)
		parent.add_child(tree)
		tree.position = Vector3(x, h, z)
		tree.rotation.y = rng.randf() * TAU
		count += 1
