class_name Fireball
extends Node3D
## A glowing projectile that arcs to its target and explodes on impact with
## the ground or a structure. Call launch() right after adding it to the tree.

const BLAST_RADIUS := 9.0

## Share of the blast's damage the player's own villagers and buildings
## take (1 = all of it; the creature's fireballs use less).
var friendly := 1.0
## True for the Balrog's fireball, which burns the village and spares goblins.
var hostile := false
## Share of the usual damage it does.
var power := 1.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _duration := 1.0
var _arc := 5.0
var _t := 0.0
var _trail: CPUParticles3D
var _glow: MeshInstance3D


func launch(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var d := from.distance_to(to)
	_duration = clampf(d / 75.0, 0.25, 1.6)
	_arc = clampf(d * 0.04, 0.4, 5.0)
	global_position = from


func _ready() -> void:
	var core := SphereMesh.new()
	core.radius = 1.0
	core.height = 2.0
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(4.0, 3.0, 1.0)
	core.material = core_mat
	var core_node := MeshInstance3D.new()
	core_node.mesh = core
	core_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core_node)

	var glow := SphereMesh.new()
	glow.radius = 1.8
	glow.height = 3.6
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color = Color(2.5, 0.9, 0.1, 0.6)
	glow.material = glow_mat
	_glow = MeshInstance3D.new()
	_glow.mesh = glow
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)

	_trail = Game.effects.make_flames(1.8)
	_trail.amount = 60
	_trail.lifetime = 0.6
	_trail.gravity = Vector3(0, 1.5, 0)
	add_child(_trail)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 4.0
	light.omni_range = 14.0
	add_child(light)


func _process(delta: float) -> void:
	_t += delta / _duration
	var t := minf(_t, 1.0)
	var pos := _from.lerp(_to, t) + Vector3.UP * _arc * 4.0 * t * (1.0 - t)
	global_position = pos
	_glow.scale = Vector3.ONE * (1.0 + sin(_t * 40.0) * 0.12)
	var below_ground := t > 0.1 and pos.y < Game.terrain.get_height(pos.x, pos.z)
	if t >= 1.0 or below_ground or _hits_structure(pos):
		_explode(pos)


func _hits_structure(pos: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		var base := d.global_position
		if pos.y > base.y + d.height or pos.y < base.y - 1.0:
			continue
		if Vector2(base.x - pos.x, base.z - pos.z).length() < d.footprint * 0.85:
			return true
	return false


func _explode(pos: Vector3) -> void:
	# Let the trail fade out instead of vanishing with the fireball.
	_trail.emitting = false
	_trail.reparent(Game.effects, true)
	get_tree().create_timer(1.0).timeout.connect(_trail.queue_free)
	Explosion.detonate(pos, BLAST_RADIUS, friendly, hostile, power)
	queue_free()
