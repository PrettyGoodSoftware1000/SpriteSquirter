class_name RopeBridge
extends Destructible
## A rope bridge hung between the decks of two treehouse Homes (`a` and
## `b`). Villagers climb a Home's ladder, cross and climb down the other
## side: route() gives them the way. It is modelled along its own X axis
## about its middle (see BuildingFactory.create_bridge) and falls if either
## Home is lost.

var a: Destructible
var b: Destructible
var length := 10.0
## Heights of the two ends above the bridge's own origin.
var ya := 4.5
var yb := 4.5
var sag := 0.5


func _ready() -> void:
	super._ready()
	if is_ghost:
		return
	# Not a tree to fell, and it does not follow the ground.
	remove_from_group("trees")
	remove_from_group("grounded")
	add_to_group("bridges")
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_check_ends)
	add_child(timer)


## A point on the walkway, `t` from 0 (the `a` end) to 1, in the bridge's
## own space.
func local_at(t: float) -> Vector3:
	return Vector3(lerpf(-length * 0.5, length * 0.5, t), lerpf(ya, yb, t) - sag * 4.0 * t * (1.0 - t), 0.0)


func point_at(t: float) -> Vector3:
	return global_transform * local_at(t)


func usable() -> bool:
	return not destroyed and is_instance_valid(a) and is_instance_valid(b) and not a.destroyed and not b.destroyed


func joins(first: Node, second: Node) -> bool:
	return (a == first and b == second) or (a == second and b == first)


## The whole walk from the ground at one Home to the ground at the other:
## ladder, round the deck, over the bridge, round the deck and down.
func route(from_a: bool) -> PackedVector3Array:
	var start := a if from_a else b
	var end := b if from_a else a
	var out := PackedVector3Array([ladder_foot(start), ladder_top(start)])
	_add_arc(out, start, start.rotation.y, _angle(start, end.global_position))
	var steps := maxi(2, ceili(length / 2.0))
	for k in steps + 1:
		var t := k / float(steps)
		out.append(point_at(t if from_a else 1.0 - t) + Vector3.UP * 0.06)
	_add_arc(out, end, _angle(end, start.global_position), end.rotation.y)
	out.append(ladder_top(end))
	out.append(ladder_foot(end))
	return out


## Where a Home's ladder meets the ground.
static func ladder_foot(home: Destructible) -> Vector3:
	var r: float = home.get_meta("deck_r", 3.5)
	var p := home.global_position + Basis(Vector3.UP, home.rotation.y) * Vector3(0, 0, r + 1.1)
	return Vector3(p.x, Game.terrain.get_height(p.x, p.z), p.z)


static func ladder_top(home: Destructible) -> Vector3:
	var r: float = home.get_meta("deck_r", 3.5)
	return home.global_position + Basis(Vector3.UP, home.rotation.y) * Vector3(0, home.get_meta("deck_h", 4.7), r - 0.7)


## The edge of a Home's deck on the side facing `toward`: where a bridge ties on.
static func deck_edge(home: Destructible, toward: Vector3) -> Vector3:
	var a := _angle(home, toward)
	var r: float = home.get_meta("deck_r", 3.5)
	return home.global_position + Vector3(sin(a) * (r - 0.15), home.get_meta("deck_h", 4.7), cos(a) * (r - 0.15))


static func _angle(home: Destructible, toward: Vector3) -> float:
	return atan2(toward.x - home.global_position.x, toward.z - home.global_position.z)


## Adds the way round a Home's deck from one compass angle to another.
static func _add_arc(out: PackedVector3Array, home: Destructible, from: float, to: float) -> void:
	var turn := angle_difference(from, to)
	var steps := ceili(absf(turn) / 0.6)
	var r: float = home.get_meta("deck_r", 3.5) - 0.7
	for k in range(1, steps + 1):
		var a := from + turn * k / steps
		out.append(home.global_position + Vector3(sin(a) * r, home.get_meta("deck_h", 4.7), cos(a) * r))


func _check_ends() -> void:
	if not destroyed and not usable():
		shatter(global_position + Vector3.UP * ya, 2.0)
