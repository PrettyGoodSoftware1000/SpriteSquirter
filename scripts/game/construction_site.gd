class_name ConstructionSite
extends Node3D
## A building the villagers are putting up. The see-through outline shows
## the finished shape while the real building rises out of the ground as
## work is done. Work is counted in villager-seconds: VILLAGER_SECONDS of
## it finishes a building, so 10 villagers take one minute.
## Call setup() before adding it to the tree.

signal completed(building: Destructible)

const VILLAGER_SECONDS := 600.0

var kind := ""
var look_seed := 0
var cost := {}
var footprint := 3.0
var progress := 0.0

var _outline: Destructible
var _outline_material := StandardMaterial3D.new()
var _rising: Destructible
var _height := 6.0
var _label: Label3D
var _dust_timer := 0.0
var _busy := 0.0


func setup(building_kind: String, seed_value: int, paid: Dictionary) -> void:
	kind = building_kind
	look_seed = seed_value
	cost = paid


func _ready() -> void:
	add_to_group("construction_sites")
	add_to_group("grounded")
	_outline = _make_building()
	_outline.is_ghost = true
	add_child(_outline)
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = Color(0.75, 0.9, 1.0, 0.28)
	BuildingFactory.make_ghost(_outline, _outline_material)
	footprint = _outline.footprint
	_height = _outline.height

	_rising = _make_building()
	_rising.is_ghost = true
	add_child(_rising)
	_strip_colliders(_rising)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 56
	_label.outline_size = 14
	_label.pixel_size = 0.02
	_label.position.y = _height + 2.0
	add_child(_label)
	_update_visual()


func _make_building() -> Destructible:
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
	progress = minf(1.0, progress + villager_seconds / VILLAGER_SECONDS)
	_busy = 0.5
	_update_visual()
	if progress >= 1.0:
		_complete()


func _process(delta: float) -> void:
	_busy -= delta
	_dust_timer -= delta
	if _busy > 0.0 and _dust_timer <= 0.0:
		_dust_timer = randf_range(0.8, 1.6)
		var a := randf() * TAU
		Game.effects.spawn_dust(global_position + Vector3(cos(a), 0.0, sin(a)) * footprint * 0.7, 0.5)


func _update_visual() -> void:
	_rising.position.y = -(_height + BuildingFactory.SINK) * (1.0 - progress)
	_outline_material.albedo_color.a = lerpf(0.3, 0.08, progress)
	_label.text = "%s  %d%%" % [BuildingCatalog.find(kind).get("name", kind.capitalize()), floori(progress * 100.0)]


func _complete() -> void:
	var b := _make_building()
	get_parent().add_child(b)
	b.global_position = global_position
	b.rotation.y = rotation.y
	b.add_to_group("player_buildings")
	Game.terrain.add_bare(b.global_position, footprint + 1.5, 0.9)
	Game.effects.spawn_dust(b.global_position, clampf(footprint * 0.6, 0.8, 2.5))
	completed.emit(b)
	queue_free()
