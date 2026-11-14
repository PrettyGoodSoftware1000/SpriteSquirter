class_name Explosion
extends RefCounted
## Gameplay side of a blast: craters, damage, flung villagers and new fires.
## The visuals live in Effects.spawn_explosion().


static func detonate(pos: Vector3, radius: float) -> void:
	var tree := Game.get_tree()
	var terrain := Game.terrain
	Game.effects.spawn_explosion(pos, radius)
	Game.shake(1.2, pos)

	# Dig a crater only when the blast is close to the ground.
	var ground := terrain.get_height(pos.x, pos.z)
	if pos.y - ground < 2.5:
		terrain.apply_brush(Vector3(pos.x, ground, pos.z), radius * 0.45, Terrain.Brush.LOWER, 1.6, 0.0, 0.25)
		# The crater is bare stone. It only fills up if it breaks into water
		# nearby (the terrain lets connected water flow in).
		terrain.add_rock(pos, radius * 0.5, 0.9)
	terrain.add_scorch(pos, radius * 0.9, 0.85)

	for node in tree.get_nodes_in_group("destructibles"):
		var d := node as Destructible
		if d == null or d.destroyed:
			continue
		var center := d.global_position + Vector3.UP * minf(d.height * 0.4, 3.0)
		var dist := maxf(0.0, center.distance_to(pos) - d.footprint * 0.6)
		if dist >= radius:
			continue
		var falloff := 1.0 - dist / radius
		d.damage(160.0 * falloff, pos, 16.0 * falloff + 4.0)
		if not d.destroyed and randf() < 0.5 + 0.5 * falloff:
			d.ignite()

	for node in tree.get_nodes_in_group("villagers"):
		var v := node as Villager
		if v == null:
			continue
		var dist := v.global_position.distance_to(pos)
		if dist < radius * 0.75:
			v.fling(pos, 14.0 * (1.0 - dist / radius) + 6.0)
		elif dist < radius * 1.3 and randf() < 0.3:
			v.catch_fire()

	Game.alarm(pos, radius * 4.0)
	Game.effects.push_debris(pos, radius * 1.5, 14.0)
	for k in randi_range(4, 7):
		var a := randf() * TAU
		var r := randf_range(1.0, radius * 0.8)
		Game.fire.start_fire(pos + Vector3(cos(a) * r, 0.0, sin(a) * r), 0)
