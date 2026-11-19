class_name FeyTryst
extends Node3D
## The Kinky Fey Stuff spell, once cast on a villager: a pixie flies from
## the top of the nearest tree to the villager, whose eyes turn a glowing
## green; then the two go off into the nearest building (PlayerVillage
## start_tryst() takes it from there: when the villager comes out, births
## come twice as fast for a while, and every child is fey).

const SPEED := 10.0

var _villager: Villager
var _pixie: Pixie
var _met := false


## Sends a pixie to `villager` (add this to the world first).
func begin(villager: Villager) -> void:
	_villager = villager
	_pixie = Pixie.new()
	_pixie.free_flying = true
	add_child(_pixie)
	var from := villager.global_position + Vector3(8, 10, 8)
	var best := INF
	for node in get_tree().get_nodes_in_group("trees") + get_tree().get_nodes_in_group("magic_trees"):
		var t := node as Node3D
		var d := t.global_position.distance_to(villager.global_position)
		if d < best:
			best = d
			var tall: float = t.get("height") if t.get("height") != null else 12.0
			from = t.global_position + Vector3.UP * tall
	_pixie.global_position = from


func _process(delta: float) -> void:
	if not is_instance_valid(_villager) or not _villager.is_alive():
		queue_free()
		return
	if not is_instance_valid(_pixie):
		# Gone in with the villager (see PlayerVillage._tryst()).
		queue_free()
		return
	var head := _villager.global_position + Vector3.UP * 1.9 * _villager.scale.y
	if not _met:
		var to := head - _pixie.global_position
		if to.length() > 0.6:
			_pixie.global_position += to.normalized() * minf(SPEED * delta, to.length())
			return
		_met = true
		_villager.set_eye_glow(Color(0.45, 1.0, 0.45))
		if is_instance_valid(Game.village):
			Game.village.start_tryst(_villager, _pixie)
		return
	# Then it flutters about the villager's head on the way in.
	var t := Time.get_ticks_msec() * 0.004
	_pixie.global_position = head + Vector3(cos(t) * 0.6, 0.3 + 0.15 * sin(t * 2.3), sin(t) * 0.6)
