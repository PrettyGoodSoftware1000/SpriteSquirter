class_name Gnome
extends Node3D
## One of the Gnomish Subcontractors (the spell): a little bearded builder
## in a tall red hat, a third of a villager's height. Gnome.summon() brings
## Balance "gnome_count" of them to a building site: each pops up in a
## shower of sparkles "gnome_distance" metres away, runs to the site at
## "gnome_speed", bouncing as it goes, and hammers away at it, adding
## "gnome_work" villager-seconds of work a second (like one villager). Every
## 1 to 3 seconds it hops to another spot round the building. When the
## building is finished (or the site is gone) it vanishes in a puff.

enum State { RUN, BUILD }

const HEIGHT := 0.62
const SKIN := Color(0.98, 0.78, 0.66)

static var _body_mesh: ArrayMesh
static var _arm_mesh: ArrayMesh

var site: ConstructionSite
var state := State.RUN

var _spot := Vector3.ZERO
var _angle := 0.0
var _timer := 0.0
var _phase := randf() * TAU
var _body: Node3D
var _arm: Node3D


## Sends the gnomes to `target` (a building under construction). Returns them.
static func summon(target: ConstructionSite) -> Array[Gnome]:
	var out: Array[Gnome] = []
	var terrain := Game.terrain
	var count := roundi(Balance.num("gnome_count"))
	var start_angle := randf() * TAU
	for k in count:
		var gnome := Gnome.new()
		gnome.site = target
		var from := target.global_position
		for attempt in 12:
			var a := start_angle + TAU * k / maxf(count, 1.0) + randf_range(-0.4, 0.4) + attempt * 0.7
			var p := target.global_position + Vector3(cos(a), 0.0, sin(a)) * Balance.num("gnome_distance") * randf_range(0.9, 1.1)
			if terrain.is_inside(p.x, p.z) and terrain.is_dry(p.x, p.z):
				from = p
				break
		Game.world_root.add_child(gnome)
		gnome.global_position = Vector3(from.x, terrain.get_height(from.x, from.z), from.z)
		Game.effects.spawn_judgement(gnome.global_position + Vector3.UP * 0.4, 0.25, true)
		out.append(gnome)
	return out


func _ready() -> void:
	add_to_group("gnomes")
	if _body_mesh == null:
		_build_meshes()
	_body = Node3D.new()
	add_child(_body)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = Art.cloth()
	_body.add_child(body)
	_arm = Node3D.new()
	_arm.position = Vector3(0.11, 0.33, 0.0)
	_body.add_child(_arm)
	var arm := MeshInstance3D.new()
	arm.mesh = _arm_mesh
	arm.material_override = Art.cloth()
	_arm.add_child(arm)
	_pick_spot()


func _process(delta: float) -> void:
	if not is_instance_valid(site) or site.is_queued_for_deletion() or site.progress >= 1.0:
		_vanish()
		return
	_phase += delta
	var terrain := Game.terrain
	match state:
		State.RUN:
			var to := _spot - global_position
			to.y = 0.0
			var step := Balance.num("gnome_speed") * delta
			if to.length() <= step:
				global_position = Vector3(_spot.x, terrain.get_height(_spot.x, _spot.z), _spot.z)
				state = State.BUILD
				_timer = randf_range(1.0, 3.0)
			else:
				var p := global_position + to.normalized() * step
				global_position = Vector3(p.x, terrain.get_height(p.x, p.z), p.z)
				rotation.y = atan2(to.x, to.z)
			# Bouncing along: a hop every stride, and a little lean.
			_body.position.y = absf(sin(_phase * 13.0)) * 0.22
			_body.rotation.x = 0.25
			_arm.rotation.x = sin(_phase * 13.0) * 0.9
		State.BUILD:
			var to := site.global_position - global_position
			rotation.y = atan2(to.x, to.z)
			_body.position.y = 0.0
			_body.rotation.x = 0.1
			# The hammer comes up and down on the work.
			_arm.rotation.x = -1.6 + 1.3 * (0.5 + 0.5 * sin(_phase * 16.0))
			site.add_work(delta * Balance.num("gnome_work"))
			_timer -= delta
			if _timer <= 0.0:
				_pick_spot()


## Off to another spot on the ring round the building.
func _pick_spot() -> void:
	_angle = randf() * TAU
	var r := site.footprint + 0.8
	_spot = site.global_position + Vector3(cos(_angle), 0.0, sin(_angle)) * r
	state = State.RUN


func _vanish() -> void:
	Game.effects.spawn_dust(global_position, 0.4)
	Game.effects.spawn_judgement(global_position + Vector3.UP * 0.3, 0.2, true)
	queue_free()


## A round little body in a blue tunic, boots, a big white beard, a round
## nose and a tall floppy red hat; the arm holds a hammer.
static func _build_meshes() -> void:
	var mb := MeshBuilder.new()
	var tunic := Color(0.25, 0.42, 0.78)
	mb.color = Color(0.3, 0.2, 0.12)
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.045, 0.04, 0.07), Transform3D(Basis(), Vector3(sx * 0.06, 0.035, 0.02)), null, 0.0, 5, 8)
		mb.color = Color(0.32, 0.25, 0.2)
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.06, 0.05, 0.0), Vector3(sx * 0.06, 0.16, 0.0)]), PackedFloat32Array([0.035, 0.04]), 8)
		mb.color = Color(0.3, 0.2, 0.12)
	mb.color = tunic
	mb.add_lathe(PackedVector2Array([Vector2(0.0, 0.13), Vector2(0.13, 0.13), Vector2(0.14, 0.2), Vector2(0.12, 0.33),
		Vector2(0.07, 0.38), Vector2(0.0, 0.39)]), 16)
	mb.color = Color(0.35, 0.22, 0.1)
	mb.add_lathe(PackedVector2Array([Vector2(0.137, 0.2), Vector2(0.142, 0.215), Vector2(0.137, 0.23)]), 16)
	mb.color = Color(0.95, 0.8, 0.3)
	mb.add_box(Vector3(0.04, 0.035, 0.02), 0.006, Transform3D(Basis(), Vector3(0, 0.215, 0.14)))
	mb.color = Color(0.25, 0.42, 0.78).darkened(0.2)
	mb.add_blob(Vector3(0.035, 0.05, 0.035), Transform3D(Basis(), Vector3(-0.12, 0.27, 0.02)), null, 0.0, 5, 8)
	# Head, nose and beard.
	mb.color = SKIN
	mb.add_blob(Vector3(0.1, 0.1, 0.1), Transform3D(Basis(), Vector3(0, 0.45, 0.0)), null, 0.0, 10, 14)
	mb.color = SKIN.darkened(0.08).lerp(Color(1.0, 0.5, 0.45), 0.25)
	mb.add_blob(Vector3(0.035, 0.03, 0.035), Transform3D(Basis(), Vector3(0, 0.44, 0.1)), null, 0.0, 6, 8)
	mb.color = Color(0.96, 0.96, 0.96)
	mb.add_blob(Vector3(0.09, 0.11, 0.06), Transform3D(Basis(), Vector3(0, 0.36, 0.07)), null, 0.0, 8, 12)
	mb.add_blob(Vector3(0.05, 0.02, 0.025), Transform3D(Basis(Vector3.BACK, 0.3), Vector3(-0.035, 0.415, 0.095)), null, 0.0, 4, 6)
	mb.add_blob(Vector3(0.05, 0.02, 0.025), Transform3D(Basis(Vector3.BACK, -0.3), Vector3(0.035, 0.415, 0.095)), null, 0.0, 4, 6)
	mb.color = Color(0.05, 0.04, 0.06)
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.012, 0.016, 0.01), Transform3D(Basis(), Vector3(sx * 0.035, 0.47, 0.088)), null, 0.0, 4, 6)
	# The hat: a brim and a tall cone flopping over at the top.
	mb.color = Color(0.85, 0.12, 0.1)
	mb.add_lathe(PackedVector2Array([Vector2(0.0, 0.48), Vector2(0.115, 0.48), Vector2(0.11, 0.5)]), 16)
	var cone := mb.add_lathe(PackedVector2Array([Vector2(0.11, 0.5), Vector2(0.085, 0.56), Vector2(0.05, 0.64), Vector2(0.0, 0.73)]), 14)
	mb.bend(cone, 0.5, 0.73, Vector3(0.0, -0.03, -0.09))
	_body_mesh = mb.commit()
	var arm := MeshBuilder.new()
	arm.color = Color(0.25, 0.42, 0.78)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0.0, -0.12, 0.0)]), PackedFloat32Array([0.032, 0.028]), 8)
	arm.color = SKIN
	arm.add_blob(Vector3(0.028, 0.028, 0.028), Transform3D(Basis(), Vector3(0.0, -0.14, 0.0)), null, 0.0, 5, 8)
	# A hammer pointing forwards out of the fist.
	arm.color = Art.WOOD
	arm.add_tube(PackedVector3Array([Vector3(0.0, -0.14, -0.02), Vector3(0.0, -0.14, 0.13)]), PackedFloat32Array([0.01, 0.01]), 6)
	arm.color = Color(0.62, 0.64, 0.68)
	arm.add_box(Vector3(0.03, 0.08, 0.035), 0.006, Transform3D(Basis(), Vector3(0.0, -0.14, 0.14)))
	_arm_mesh = arm.commit()
