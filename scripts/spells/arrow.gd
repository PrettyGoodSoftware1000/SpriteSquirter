class_name Arrow
extends Node3D
## An arrow (an archer's, a Fey Archer's, a gooblin archer's). It flies at
## its target and hurts it: a villager or gooblin, a giant, a giant bat, a
## building, or a gooblin cave. Call launch() right after adding it to the
## tree. It leaves a short bright streak behind it (unlit, so it shows at
## night too).

const SPEED := 36.0
## How long the streak behind it is (seconds of flight), and how wide.
const TRAIL_SECONDS := 0.12
const TRAIL_WIDTH := 0.16

## A Villager, a Creature, a GiantBat, a Destructible or a cave.
var _target: Node3D
var _caster: Node3D
var _damage := 0.0
var _life := 2.5
var _trail := ImmediateMesh.new()
var _trail_node: MeshInstance3D
## Where it has been lately: [position, age].
var _behind: Array[Array] = []

static var _trail_material: StandardMaterial3D


func launch(from: Vector3, target: Node3D, caster: Node3D, damage: float) -> void:
	global_position = from
	_target = target
	_caster = caster
	_damage = damage


func _ready() -> void:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.05, 0.05, 0.85)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.96, 0.8)
	shaft.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = shaft
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if _trail_material == null:
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_material.vertex_color_use_as_albedo = true
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail
	_trail_node.material_override = _trail_material
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_node.top_level = true
	add_child(_trail_node)


func _process(delta: float) -> void:
	_life -= delta
	if not is_instance_valid(_target) or not _alive() or _life <= 0.0:
		queue_free()
		return
	var aim := _aim()
	var to := aim - global_position
	var step := SPEED * delta
	if to.length() <= step + _slack():
		_hit()
		queue_free()
		return
	global_position += to.normalized() * step
	look_at(aim)
	_draw_trail(delta)


## Where it flies to on its target.
func _aim() -> Vector3:
	var giant := _target as Creature
	if giant:
		return _target.global_position + Vector3.UP * 5.0 * giant.size
	if _target.is_in_group("caves"):
		return _target.global_position + Vector3.UP * 3.0
	var building := _target as Destructible
	if building:
		return _target.global_position + Vector3.UP * building.height * 0.4
	return _target.global_position + Vector3.UP * 0.9 * _target.scale.y


## How close counts as a hit.
func _slack() -> float:
	var giant := _target as Creature
	if giant:
		return 0.3 + 1.5 * giant.size
	if _target.is_in_group("caves"):
		return Villager.CAVE_REACH * 0.8
	var building := _target as Destructible
	if building:
		return building.footprint * 0.7
	return 0.3


func _hit() -> void:
	var by := _caster if is_instance_valid(_caster) else null
	if _target.is_in_group("caves"):
		GoblinRaids.hurt_cave(_target, _damage)
	elif _target is Destructible:
		# (Buildings are tough: an arrow only chips at one, as a blade does.)
		(_target as Destructible).damage(_damage * 0.5, global_position, 2.0)
	else:
		_target.call("take_hit", _damage, by)


func _alive() -> bool:
	if _target is GiantBat:
		return (_target as GiantBat).is_alive()
	if _target.is_in_group("caves"):
		return GoblinRaids.cave_standing(_target)
	if _target is Destructible:
		return not (_target as Destructible).destroyed
	var giant := _target as Creature
	return not giant.knocked_out if giant else (_target as Villager).is_alive()


## The streak: a ribbon through where it has been, turned to the camera,
## bright at the arrow and fading behind it.
func _draw_trail(delta: float) -> void:
	for b in _behind:
		b[1] += delta
	_behind.push_front([global_position, 0.0])
	while _behind.size() > 2 and float(_behind[-1][1]) > TRAIL_SECONDS:
		_behind.pop_back()
	_trail.clear_surfaces()
	if _behind.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else global_position + Vector3.UP * 10.0
	_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in _behind.size():
		var p: Vector3 = _behind[k][0]
		var along: Vector3 = (_behind[maxi(k - 1, 0)][0] as Vector3) - (_behind[mini(k + 1, _behind.size() - 1)][0] as Vector3)
		var side := (eye - p).cross(along)
		side = side.normalized() if side.length_squared() > 1e-8 else Vector3.UP
		var fade := 1.0 - float(k) / float(_behind.size() - 1)
		var color := Color(1.6, 1.45, 0.9, 0.9 * fade)
		_trail.surface_set_color(color)
		_trail.surface_add_vertex(p + side * TRAIL_WIDTH * 0.5 * (0.3 + 0.7 * fade))
		_trail.surface_set_color(color)
		_trail.surface_add_vertex(p - side * TRAIL_WIDTH * 0.5 * (0.3 + 0.7 * fade))
	_trail.surface_end()
