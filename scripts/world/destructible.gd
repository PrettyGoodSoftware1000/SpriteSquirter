class_name Destructible
extends Node3D
## Anything that can burn and be blown apart: buildings and trees.
##
## Visible pieces are MeshInstance3D children tagged with the "debris" meta.
## When the object is destroyed, each tagged piece turns into a physics body.

const CHAR_COLOR := Color(0.06, 0.05, 0.05)

var max_hp := 100.0
var hp := 100.0
## Chance (0..1) to catch fire when flames are nearby.
var flammability := 0.4
## Rough radius of the object on the ground, in metres.
var footprint := 3.0
var height := 6.0
## Seconds of burning before it collapses.
var burn_duration := 20.0
var is_building := true
## Ghosts are placement previews: no groups, no burning, no damage.
var is_ghost := false

var burning := false
var destroyed := false

var _burn_time := 0.0
var _spread_timer := 0.0
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _fires: Array[FireEmitter] = []


func _ready() -> void:
	set_process(false)
	if is_ghost:
		return
	add_to_group("destructibles")
	add_to_group("buildings" if is_building else "trees")


## Materials registered here get charred while the object burns.
func register_material(mat: StandardMaterial3D) -> void:
	_materials.append(mat)
	_base_colors.append(mat.albedo_color)


func damage(amount: float, from: Vector3, force: float) -> void:
	if destroyed or is_ghost:
		return
	hp -= amount
	if hp <= 0.0:
		shatter(from, force)
	elif amount > 15.0 and randf() < flammability + 0.5:
		ignite()


## Crushed by a giant foot.
func stomp(at: Vector3) -> void:
	damage(max_hp * 3.0, at, 7.0)


func ignite() -> void:
	if burning or destroyed or is_ghost:
		return
	burning = true
	_burn_time = 0.0
	_spread_timer = randf_range(1.0, 2.0)
	set_process(true)
	var count := 1
	if is_building:
		count = 3 if footprint > 3.0 else 2
	for k in count:
		var f := FireEmitter.new()
		f.size = clampf(footprint * 0.45, 0.7, 2.0) if is_building else 0.9
		f.with_light = is_building and k == 0
		add_child(f)
		f.position = Vector3(randf_range(-0.4, 0.4) * footprint, height * randf_range(0.45, 0.9),
			randf_range(-0.4, 0.4) * footprint)
		_fires.append(f)
	Game.alarm(global_position, 12.0)


func _process(delta: float) -> void:
	_burn_time += delta
	var t := clampf(_burn_time / burn_duration, 0.0, 1.0)
	for k in _materials.size():
		_materials[k].albedo_color = _base_colors[k].lerp(CHAR_COLOR, t)
	_spread_timer -= delta
	if _spread_timer <= 0.0:
		_spread_timer = randf_range(1.0, 2.0)
		Game.fire.spread_from(self)
	if _burn_time >= burn_duration:
		collapse()


## Burnt out: crumble in place.
func collapse() -> void:
	shatter(global_position + Vector3.UP * height, 3.0)


## Breaks into physics debris and removes itself.
func shatter(from: Vector3, force: float) -> void:
	if destroyed:
		return
	destroyed = true
	remove_from_group("destructibles")
	remove_from_group("buildings")
	remove_from_group("trees")
	for f in _fires:
		if is_instance_valid(f):
			f.reparent(Game.fire, true)
			f.extinguish()
	_fires.clear()
	var parts: Array[MeshInstance3D] = []
	_collect_parts(self, parts)
	for p in parts:
		Game.effects.spawn_debris(p, from, force, burning)
	Game.terrain.add_scorch(global_position, footprint + 1.5, 0.5 if burning else 0.2)
	Game.effects.spawn_dust(global_position, clampf(footprint * 0.5, 0.6, 2.5))
	if burning:
		for k in 2:
			var a := randf() * TAU
			Game.fire.start_fire(global_position + Vector3(cos(a), 0.0, sin(a)) * footprint, 2)
	Game.alarm(global_position, 20.0)
	queue_free()


func _collect_parts(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.get_meta("debris", false):
			out.append(child)
		else:
			_collect_parts(child, out)
