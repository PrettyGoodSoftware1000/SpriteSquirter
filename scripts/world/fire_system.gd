class_name FireSystem
extends Node3D
## Ground fires that burn for a while, spread across grass and ignite nearby
## buildings, trees and villagers. Each fire remembers its "generation" so a
## wildfire burns out after a few hops instead of eating the whole map.

const MAX_GROUND_FIRES := 80
const MAX_GENERATION := 3

var _fires: Array[Dictionary] = []
## Places soaked by rain, where nothing can catch fire for a while:
## {"pos": Vector3, "radius": float, "time": float}.
var _wet: Array[Dictionary] = []


func count() -> int:
	return _fires.size()


func start_fire(pos: Vector3, generation := 0, size := 1.0) -> void:
	if _fires.size() >= MAX_GROUND_FIRES:
		return
	var terrain := Game.terrain
	if not terrain.is_inside(pos.x, pos.z):
		return
	var h := terrain.get_height(pos.x, pos.z)
	if terrain.water_depth(pos.x, pos.z) > 0.0 or is_wet(pos):
		return
	var ground := Vector3(pos.x, h, pos.z)
	for f in _fires:
		var other: Vector3 = f.pos
		if other.distance_to(ground) < 2.2:
			return
	var emitter := FireEmitter.new()
	emitter.size = size * randf_range(0.7, 1.0)
	emitter.with_light = randf() < 0.35
	add_child(emitter)
	emitter.global_position = ground
	_fires.append({"node": emitter, "pos": ground, "life": randf_range(6.0, 12.0),
		"gen": generation, "timer": randf_range(0.6, 1.4)})
	terrain.add_scorch(ground, 2.5, 0.4)


## Soaks an area: puts out every fire in it and keeps it from burning
## for `duration` seconds.
func soak(pos: Vector3, radius: float, duration: float) -> void:
	var found := false
	for w in _wet:
		if (w.pos as Vector3).distance_to(pos) < 1.0:
			w.time = maxf(w.time, duration)
			w.radius = maxf(w.radius, radius)
			found = true
	if not found:
		_wet.append({"pos": pos, "radius": radius, "time": duration})
	extinguish_in(pos, radius)


## Puts out ground fires, burning buildings and trees, and burning villagers.
func extinguish_in(pos: Vector3, radius: float) -> void:
	for k in range(_fires.size() - 1, -1, -1):
		var f := _fires[k]
		if _flat_distance(f.pos, pos) < radius:
			var node: FireEmitter = f.node
			if is_instance_valid(node):
				node.extinguish()
				Game.effects.spawn_steam(f.pos, 0.8)
			_fires.remove_at(k)
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		if d and d.burning and _flat_distance(d.global_position, pos) < radius + d.footprint:
			d.extinguish()
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v and _flat_distance(v.global_position, pos) < radius:
			v.douse()


func is_wet(pos: Vector3) -> bool:
	for w in _wet:
		if _flat_distance(w.pos, pos) < w.radius:
			return true
	return false


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _process(delta: float) -> void:
	for k in range(_wet.size() - 1, -1, -1):
		_wet[k].time -= delta
		if _wet[k].time <= 0.0:
			_wet.remove_at(k)
	for k in range(_fires.size() - 1, -1, -1):
		var f := _fires[k]
		f.life -= delta
		f.timer -= delta
		var pos: Vector3 = f.pos
		if f.timer <= 0.0:
			f.timer = randf_range(1.2, 2.2)
			ignite_near(pos, 3.5, 1.0)
			var gen: int = f.gen
			if gen < MAX_GENERATION and randf() < 0.45:
				var a := randf() * TAU
				var next := pos + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.5, 4.5)
				if _is_burnable_ground(next):
					start_fire(next, gen + 1)
		if f.life <= 0.0:
			var node: FireEmitter = f.node
			if is_instance_valid(node):
				node.extinguish()
			_fires.remove_at(k)


## A burning structure tries to set its neighbours on fire.
func spread_from(source: Destructible) -> void:
	var pos := source.global_position
	ignite_near(pos, source.footprint + 5.0, 0.35, source)
	if randf() < 0.25:
		var a := randf() * TAU
		var r := source.footprint + randf_range(0.5, 3.0)
		var p := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if _is_burnable_ground(p):
			start_fire(p, MAX_GENERATION - 1, 0.8)


func ignite_near(pos: Vector3, radius: float, chance: float, exclude: Node = null) -> void:
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		if d == null or d == exclude or d.burning:
			continue
		var flat := Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length()
		if flat < radius + d.footprint and randf() < d.flammability * chance:
			d.ignite()
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v == null:
			continue
		var dist := v.global_position.distance_to(pos)
		if dist < radius * 0.6 and randf() < 0.3 * chance:
			v.catch_fire()
		elif dist < radius * 3.0:
			v.flee(pos)


func _is_burnable_ground(p: Vector3) -> bool:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z):
		return false
	var h := terrain.get_height(p.x, p.z)
	return terrain.is_dry(p.x, p.z) and h < 22.0 and terrain.get_normal(p.x, p.z).y > 0.85
