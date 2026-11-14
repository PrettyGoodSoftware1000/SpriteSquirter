class_name Firebolt
extends Node3D
## A wizard's tiny firebolt. It homes in on a goblin, hurts it and may set
## it alight. Call launch() right after adding it to the tree.

const SPEED := 28.0
const IGNITE_CHANCE := 0.3

var _target: Villager
var _caster: Node3D
var _trail: CPUParticles3D
var _life := 2.5


func launch(from: Vector3, target: Villager, caster: Node3D) -> void:
	global_position = from
	_target = target
	_caster = caster


func _ready() -> void:
	var core := SphereMesh.new()
	core.radius = 0.16
	core.height = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(4.0, 2.2, 0.6)
	core.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = core
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_trail = Game.effects.make_flames(0.35)
	_trail.amount = 16
	_trail.lifetime = 0.35
	add_child(_trail)


func _process(delta: float) -> void:
	_life -= delta
	if not is_instance_valid(_target) or not _target.is_alive() or _life <= 0.0:
		_fizzle()
		return
	var aim := _target.global_position + Vector3.UP * 0.9 * _target.scale.y
	var to := aim - global_position
	var step := SPEED * delta
	if to.length() <= step + 0.3:
		_target.take_hit(Villager.FIREBOLT_DAMAGE, _caster if is_instance_valid(_caster) else null)
		if _target.is_alive() and randf() < IGNITE_CHANCE:
			_target.catch_fire()
		Game.effects.spawn_dust(aim, 0.3)
		_fizzle()
		return
	global_position += to.normalized() * step


func _fizzle() -> void:
	_trail.emitting = false
	_trail.reparent(Game.effects, true)
	get_tree().create_timer(0.6).timeout.connect(_trail.queue_free)
	queue_free()
