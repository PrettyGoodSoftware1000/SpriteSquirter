class_name Sapling
extends Node
## A young tree. It is an ordinary tree (FloraFactory) that starts small
## and grows to full size over Balance "sapling_grow_days" days (each day
## is a day and a night: DayCycle.cycle_seconds()). Until then it is in the "saplings"
## group instead of "trees", so nobody chops it down or carries it off.
## Villagers plant them (see PlayerVillage), and so does the magic tree.

## How big it starts, as a share of its full size.
const SMALL := 0.12

var _tree: Destructible
var _full_scale := Vector3.ONE
var _age := 0.0
var _tick := 0.0


## Plants a sapling at `pos` (on the ground) and returns its tree.
static func plant(pos: Vector3) -> Destructible:
	var terrain := Game.terrain
	var tree := WorldPopulator.spawn_tree(Game.world_root, terrain, pos.x, pos.z, randf() * TAU, randi())
	var grower := Sapling.new()
	grower.name = "Sapling"
	tree.add_child(grower)
	return tree


func _ready() -> void:
	_tree = get_parent() as Destructible
	_full_scale = _tree.scale
	_tree.scale = _full_scale * SMALL
	# (After the tree's own _ready, which puts it among the trees.)
	_settle.call_deferred()


func _settle() -> void:
	if not is_instance_valid(_tree):
		return
	_tree.remove_from_group("trees")
	_tree.add_to_group("saplings")


## How far grown it is, 0..1.
func share() -> float:
	var days := maxf(0.01, Balance.num("sapling_grow_days")) * DayCycle.cycle_seconds()
	return clampf(_age / days, 0.0, 1.0)


func _process(delta: float) -> void:
	_age += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if not is_instance_valid(_tree) or _tree.destroyed:
		queue_free()
		return
	var grown := share()
	_tree.scale = _full_scale * lerpf(SMALL, 1.0, grown)
	if grown >= 1.0:
		_tree.remove_from_group("saplings")
		_tree.add_to_group("trees")
		queue_free()
