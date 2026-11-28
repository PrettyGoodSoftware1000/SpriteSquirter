class_name ChainLightning
extends Node3D
## The chain lightning spell: a bolt comes down on whoever is nearest the
## point and jumps on from one to the next, up to Balance "lightning_jumps"
## of them, each within "lightning_jump_range" of the last. It hits
## villagers, gooblins, ogres, skeletons, giant bats and the Balrog alike.
## Every wet one it strikes (rained on lately, or standing in water) has a
## Balance "lightning_wet_jump_chance" of giving the bolt one jump more.
## Each jump comes "lightning_jump_seconds" after the last (whoever cast
## it: the player, the creature or a Storm Spire), so it can be seen
## going from one to the next. Use ChainLightning.cast().

const FADE := 0.45

## Everything the last bolt struck (or is about to strike), in order.
static var last_struck: Array[Node3D] = []

## The strikes still to come: [target, harm], one every _gap seconds.
var _chain: Array[Array] = []
var _gap := 0.15
var _wait := 0.0
var _from := Vector3.ZERO
var _light: OmniLight3D
var _left := FADE


## Strikes at `pos`. `friendly` is the share of the damage the player's own
## people take (1 for the player's spell, less for the creature's).
## Returns how many things it hits (the first at once, the rest a jump
## apart; last_struck lists them all).
static func cast(pos: Vector3, friendly := 1.0) -> int:
	var tree := Game.get_tree()
	var reach := Balance.num("lightning_jump_range")
	var left: Array[Node3D] = []
	for node in tree.get_nodes_in_group("villagers") + tree.get_nodes_in_group("bats") + tree.get_nodes_in_group("balrogs"):
		left.append(node as Node3D)
	var ground := Vector3(pos.x, Game.terrain.surface_height(pos.x, pos.z), pos.z)
	var from := ground
	var chain: Array[Array] = []
	last_struck.clear()
	var jumps := roundi(Balance.num("lightning_jumps"))
	var jump := 0
	while jump < jumps:
		jump += 1
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
		last_struck.append(best)
		from = best.global_position
		var harm := Balance.num("lightning_damage")
		var v := best as Villager
		if v:
			if v.is_wet() and randf() < Balance.num("lightning_wet_jump_chance"):
				# (Water carries it on: one jump more.)
				jumps += 1
			if v.owned:
				harm *= friendly
		chain.append([best, harm])
	var hits := chain.size()
	var bolt := ChainLightning.new()
	bolt._chain = chain
	bolt._gap = maxf(0.0, Balance.num("lightning_jump_seconds"))
	bolt._from = ground + Vector3(randf_range(-4.0, 4.0), 34.0, randf_range(-4.0, 4.0))
	Game.world_root.add_child(bolt)
	if chain.is_empty():
		bolt._draw_to(ground)
	else:
		bolt._strike_next()
	Game.shake(0.5, ground)
	return hits


func _init() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.8, 1.0)
	_light.light_energy = 8.0
	_light.omni_range = 22.0
	add_child(_light)


func _process(delta: float) -> void:
	if not _chain.is_empty():
		_wait -= delta
		if _wait <= 0.0:
			_strike_next()
		return
	_left -= delta
	_light.light_energy = 8.0 * maxf(0.0, _left / FADE)
	if _left <= 0.0:
		queue_free()


## The next one in the chain is struck (if it is still there) and the bolt
## jumps to it.
func _strike_next() -> void:
	_wait = _gap
	_left = FADE
	var entry: Array = _chain.pop_front()
	if not is_instance_valid(entry[0]):
		return
	var best := entry[0] as Node3D
	var harm: float = entry[1]
	var v := best as Villager
	var at: Vector3
	if v:
		at = v.global_position + Vector3.UP * 1.1 * v.scale.y
		if v.is_alive():
			v.take_hit(harm, null)
	else:
		var giant := best as Creature
		at = best.global_position + Vector3.UP * (5.0 * giant.size if giant else 0.0)
		best.call("take_hit", harm, null)
	_draw_to(at)


## Draws a jagged glowing stroke from where the bolt is to `to`, with a
## spark where it lands, and fades it.
func _draw_to(to: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(2.6, 2.7, 3.4, 1.0)
	var mb := MeshBuilder.new()
	var a := _from
	var b := to
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
	mb.color = Color(1.0, 1.0, 1.0, 1.0)
	mb.add_blob(Vector3.ONE * 0.35, Transform3D(Basis(), b), null, 0.0, 4, 6)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_light.global_position = b + Vector3.UP * 2.0
	var tw := mi.create_tween()
	tw.tween_property(material, "albedo_color:a", 0.0, FADE).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	_from = b
