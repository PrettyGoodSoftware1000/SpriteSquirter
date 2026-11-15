class_name Arrow
extends Node3D
## An archer's arrow. It flies at a goblin and hurts it. Call launch()
## right after adding it to the tree.

const SPEED := 36.0

var _target: Villager
var _caster: Node3D
var _damage := 0.0
var _life := 2.5


func launch(from: Vector3, target: Villager, caster: Node3D, damage: float) -> void:
	global_position = from
	_target = target
	_caster = caster
	_damage = damage


func _ready() -> void:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.035, 0.035, 0.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.88, 0.72)
	shaft.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = shaft
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_life -= delta
	if not is_instance_valid(_target) or not _target.is_alive() or _life <= 0.0:
		queue_free()
		return
	var aim := _target.global_position + Vector3.UP * 0.9 * _target.scale.y
	var to := aim - global_position
	var step := SPEED * delta
	if to.length() <= step + 0.3:
		_target.take_hit(_damage, _caster if is_instance_valid(_caster) else null)
		queue_free()
		return
	global_position += to.normalized() * step
	look_at(aim)
