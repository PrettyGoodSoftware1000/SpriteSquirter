class_name ChainLightning
extends Node3D
## The chain lightning spell: a bolt comes down on whoever is nearest the
## point and jumps on from one to the next, up to Balance "lightning_jumps"
## of them, each within "lightning_jump_range" of the last. It hits
## villagers, goblins, ogres, skeletons, giant bats and the Balrog alike. Anything wet
## (rained on lately, or standing in water) takes "lightning_wet_bonus"
## times the damage. Use ChainLightning.cast().

const FADE := 0.45

var _material := StandardMaterial3D.new()


## Strikes at `pos`. `friendly` is the share of the damage the player's own
## people take (1 for the player's spell, less for the creature's).
## Returns how many things it hit.
static func cast(pos: Vector3, friendly := 1.0) -> int:
	var tree := Game.get_tree()
	var reach := Balance.num("lightning_jump_range")
	var left: Array[Node3D] = []
	for node in tree.get_nodes_in_group("villagers") + tree.get_nodes_in_group("bats") + tree.get_nodes_in_group("balrogs"):
		left.append(node as Node3D)
	var ground := Vector3(pos.x, Game.terrain.surface_height(pos.x, pos.z), pos.z)
	var points := PackedVector3Array([ground + Vector3(randf_range(-4.0, 4.0), 34.0, randf_range(-4.0, 4.0))])
	var from := ground
	var hits := 0
	for jump in roundi(Balance.num("lightning_jumps")):
		var best: Node3D = null
		var best_d := reach
		for n in left:
			var d := Vector2(n.global_position.x - from.x, n.global_position.z - from.z).length()
			if d < best_d:
				best_d = d
				best = n
		if best == null:
			break
		left.erase(best)
		hits += 1
		from = best.global_position
		var harm := Balance.num("lightning_damage")
		var v := best as Villager
		if v:
			points.append(v.global_position + Vector3.UP * 1.1 * v.scale.y)
			if v.is_wet():
				harm *= Balance.num("lightning_wet_bonus")
			if v.owned:
				harm *= friendly
			v.take_hit(harm, null)
		else:
			var giant := best as Creature
			points.append(best.global_position + Vector3.UP * (5.0 * giant.size if giant else 0.0))
			best.call("take_hit", harm, null)
	if hits == 0:
		points.append(ground)
	var bolt := ChainLightning.new()
	Game.world_root.add_child(bolt)
	bolt._show(points)
	Game.shake(0.5, ground)
	return hits


## Draws the bolt through `points` as a jagged glowing line, and fades it.
func _show(points: PackedVector3Array) -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color(2.6, 2.7, 3.4, 1.0)
	var mb := MeshBuilder.new()
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var steps := clampi(int(a.distance_to(b) / 1.6), 2, 18)
		var path := PackedVector3Array([a])
		for j in range(1, steps):
			var jag := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * minf(0.9, a.distance_to(b) * 0.08)
			path.append(a.lerp(b, j / float(steps)) + jag)
		path.append(b)
		for layer in 2:
			var radii := PackedFloat32Array()
			radii.resize(path.size())
			radii.fill(0.07 if layer == 0 else 0.22)
			mb.color = Color(1.0, 1.0, 1.0, 1.0) if layer == 0 else Color(0.3, 0.45, 0.9, 0.35)
			mb.add_tube(path, radii, 5)
		# A spark where it lands.
		mb.color = Color(1.0, 1.0, 1.0, 1.0)
		mb.add_blob(Vector3.ONE * 0.35, Transform3D(Basis(), b), null, 0.0, 4, 6)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.8, 1.0)
	light.light_energy = 8.0
	light.omni_range = 22.0
	add_child(light)
	light.global_position = points[points.size() - 1] + Vector3.UP * 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_material, "albedo_color:a", 0.0, FADE).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 0.0, FADE)
	tw.chain().tween_callback(queue_free)
