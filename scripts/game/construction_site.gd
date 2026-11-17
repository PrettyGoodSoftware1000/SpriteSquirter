class_name ConstructionSite
extends Node3D
## A building going up. The see-through outline shows the finished shape
## while the real building rises out of the ground as work is done (a rope
## bridge grows out from its first Home instead). Work is counted in
## villager-seconds, and a building needs Balance "build_work_per_resource"
## of them for every unit of resource it costs, so dear buildings take
## longer: a Home costing 55 is 550, under a minute for 10 villagers.
##
## The goblins' buildings (`goblin`) work the same way, but only goblins
## build them and they join the "goblin_sites" group instead.
## Call setup() before adding it to the tree.

signal completed(building: Destructible)

var kind := ""
var look_seed := 0
var cost := {}
var footprint := 3.0
var progress := 0.0
## Villager-seconds of work the building takes.
var work_needed := 600.0
var goblin := false
## A rope bridge only: its length and end heights, and the two Homes.
var spec := {}
var ends: Array = []

var _outline: Destructible
var _outline_material := StandardMaterial3D.new()
var _rising: Destructible
var _pivot: Node3D
var _height := 6.0
var _label: Label3D
var _dust_timer := 0.0
var _busy := 0.0


func setup(building_kind: String, seed_value: int, paid: Dictionary, for_goblins := false) -> void:
	kind = building_kind
	look_seed = seed_value
	cost = paid
	goblin = for_goblins
	var total := 0.0
	for res in paid:
		total += paid[res]
	work_needed = maxf(total * Balance.num("build_work_per_resource"), 20.0)


func _ready() -> void:
	add_to_group("goblin_sites" if goblin else "construction_sites")
	if kind != "bridge":
		add_to_group("grounded")
	_outline = _make_building()
	_outline.is_ghost = true
	add_child(_outline)
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = Color(1.0, 0.5, 0.4, 0.28) if goblin else Color(0.75, 0.9, 1.0, 0.28)
	BuildingFactory.make_ghost(_outline, _outline_material)
	footprint = _outline.footprint
	_height = _outline.height

	_rising = _make_building()
	_rising.is_ghost = true
	if kind == "bridge":
		# Stretched out from the first Home's end as it is built.
		_pivot = Node3D.new()
		_pivot.position.x = -_rising.get("length") * 0.5
		add_child(_pivot)
		_pivot.add_child(_rising)
		_rising.position.x = _rising.get("length") * 0.5
	else:
		add_child(_rising)
	_strip_colliders(_rising)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 56
	_label.outline_size = 14
	_label.pixel_size = 0.02
	_label.position.y = _height + 2.0
	if goblin:
		_label.modulate = Color(1.0, 0.7, 0.6)
	add_child(_label)
	_update_visual()


func _make_building() -> Destructible:
	if kind == "bridge":
		return BuildingFactory.create_bridge(spec.length, spec.ya, spec.yb)
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	return BuildingFactory.create(kind, rng)


func _strip_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			child.queue_free()
		else:
			_strip_colliders(child)


## Where builder number `index` of `count` stands, around the outline.
func work_spot(index: int, count: int) -> Vector3:
	var a := TAU * index / maxf(count, 1.0) + look_seed % 7
	var r := footprint + 1.0
	return global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)


func add_work(villager_seconds: float) -> void:
	if progress >= 1.0:
		return
	if goblin:
		villager_seconds *= Game.settings.goblin_build_speed
	else:
		villager_seconds *= Game.settings.construction_rate
	progress = minf(1.0, progress + villager_seconds / work_needed)
	_busy = 0.5
	_update_visual()
	if progress >= 1.0:
		_complete()


## Knocked down before it was finished (a fireball on a goblin building).
func wreck() -> void:
	Game.effects.spawn_dust(global_position, clampf(footprint * 0.6, 0.8, 2.5))
	queue_free()


func _process(delta: float) -> void:
	_busy -= delta
	_dust_timer -= delta
	if _busy > 0.0 and _dust_timer <= 0.0:
		_dust_timer = randf_range(0.8, 1.6)
		var a := randf() * TAU
		Game.effects.spawn_dust(global_position + Vector3(cos(a), 0.0, sin(a)) * footprint * 0.7, 0.5)
	if kind == "bridge" and ends.size() == 2:
		for home: Variant in ends:
			if not is_instance_valid(home) or (home as Destructible).destroyed:
				queue_free()
				return


func _update_visual() -> void:
	if _pivot:
		_pivot.scale.x = maxf(progress, 0.02)
	else:
		_rising.position.y = -(_height + BuildingFactory.SINK) * (1.0 - progress)
	_outline_material.albedo_color.a = lerpf(0.3, 0.08, progress)
	_label.text = "%s  %d%%" % [BuildingCatalog.find(kind).get("name", kind.capitalize()), floori(progress * 100.0)]


func _complete() -> void:
	var b := _make_building()
	var bridge := b as RopeBridge
	if bridge:
		bridge.a = ends[0]
		bridge.b = ends[1]
	get_parent().add_child(b)
	b.global_position = global_position
	b.rotation.y = rotation.y
	b.add_to_group("goblin_buildings" if goblin else "player_buildings")
	b.set_meta("kind", kind)
	if bridge == null:
		Game.terrain.add_bare(b.global_position, footprint + 1.5, 0.9)
	Game.effects.spawn_dust(b.global_position, clampf(footprint * 0.6, 0.8, 2.5))
	completed.emit(b)
	queue_free()
