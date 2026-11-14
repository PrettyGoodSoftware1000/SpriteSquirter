class_name PlayerVillage
extends Node
## The player's village: its resources, its people and their work.
##
## Grown-up villagers gather lumber (felling trees), stone (breaking up
## boulders) and food (foraging round the village, or sowing and reaping
## wheat fields) at the rates set in Game.settings, in units per worker per
## minute. What they gather only counts once they have carried it to the
## nearest Storehouse (or to the village centre while there is none).
## Every grown-up also adds a trickle of magicko. While a building is under
## construction every worker drops their work to help build it, oldest site
## first.
##
## A new child is born every `birth_seconds` while there is housing for it
## (Homes add housing) and food in store, and grows up in Villager.GROW_SECONDS.
##
## Grown-ups are workers unless the player asks for warriors or wizards
## (the jobs panel). Each Town guard trains one warrior at a time, taking
## WARRIOR_SECONDS, up to WARRIORS_PER_GUARD; each Singing rocks trains one
## wizard at a time, taking WIZARD_SECONDS, up to WIZARDS_PER_ROCKS.
## Buildings train side by side. A warrior or wizard sent back to work
## must train from the start to return.
##
## Everyone eats: villagers FOOD_PER_VILLAGER a minute, warriors
## FOOD_PER_WARRIOR and wizards FOOD_PER_WIZARD. With no food, no children
## are born; after STARVE_AFTER seconds without food, someone starves every
## STARVE_EVERY seconds until there is food again.

const RESOURCES := ["lumber", "stone", "food", "magicko"]
const START_RESOURCES := {"lumber": 80.0, "stone": 50.0, "food": 40.0, "magicko": 30.0}
const START_VILLAGERS := 8
const HOME_RADIUS := 16.0
## Buildings may go up this far from the village centre...
const TERRITORY := 45.0
## ...or this close to one of the village's buildings.
const NEAR_BUILDING := 24.0
## How far workers walk to reach trees and rocks.
const WORK_REACH := 65.0
const JOB_SHARE := {"lumber": 0.4, "food": 0.35, "stone": 0.25}
const MAX_PER_TARGET := 2
const TREE_WOOD := 30.0
const BUSH_WOOD := 10.0
const ROCK_STONE := 35.0
const WARRIORS_PER_GUARD := 4
const WARRIOR_SECONDS := 60.0
const WIZARDS_PER_ROCKS := 2
const WIZARD_SECONDS := 180.0
## Magicko each wizard makes per minute.
const WIZARD_MAGICKO := 5.0
## Food eaten per minute.
const FOOD_PER_VILLAGER := 1.0
const FOOD_PER_WARRIOR := 3.0
const FOOD_PER_WIZARD := 2.0
const STARVE_AFTER := 60.0
const STARVE_EVERY := 30.0
## role -> [building role in the catalog, per building, seconds to train]
const ARMY := {
	"warrior": ["guard", WARRIORS_PER_GUARD, WARRIOR_SECONDS],
	"wizard": ["wizard", WIZARDS_PER_ROCKS, WIZARD_SECONDS],
}

var founded := false
var center := Vector3.ZERO
var resources := {}
## Seconds towards the next birth.
var birth_progress := 0.0

## How many warriors and wizards the player asked for.
var wanted := {"warrior": 0, "wizard": 0}
## Seconds with no food, and towards the next death from hunger.
var hungry_for := 0.0

var _assign_timer := 0.0
var _army_timer := 0.0
var _starve_timer := 0.0
## Training building -> {"v": the trainee, "t": seconds trained, "role": ...}
var _training := {}


func _ready() -> void:
	for res in RESOURCES:
		resources[res] = START_RESOURCES[res]


## Starts the village at `pos`. In a random world, `site` is the village
## site there: its buildings and villagers join the player. Otherwise the
## village starts with a few villagers and no buildings.
func found(pos: Vector3, site := -1) -> void:
	founded = true
	center = pos
	var tree := get_tree()
	if site >= 0:
		for node in tree.get_nodes_in_group("buildings"):
			if node.get_meta("site", -1) == site:
				node.add_to_group("player_buildings")
		for node in tree.get_nodes_in_group("villagers"):
			var v := node as Villager
			if v.get_meta("site", -1) == site and not v.goblin:
				v.owned = true
				v.add_to_group("people")
				v.home = center
				v.home_radius = HOME_RADIUS
	if people().is_empty():
		Game.terrain.add_bare(center, 9.0, 0.7)
		for k in START_VILLAGERS:
			WorldPopulator.spawn_villager(Game.world_root, Game.terrain, center, 6.0, false, true)
		for v in people():
			v.home_radius = HOME_RADIUS


func people() -> Array[Villager]:
	var out: Array[Villager] = []
	for node in get_tree().get_nodes_in_group("people"):
		out.append(node as Villager)
	return out


func population() -> int:
	return get_tree().get_nodes_in_group("people").size()


func adults() -> int:
	var count := 0
	for v in people():
		if v.is_adult():
			count += 1
	return count


func housing() -> int:
	var total := BuildingCatalog.BASE_HOUSING
	for node in get_tree().get_nodes_in_group("player_buildings"):
		total += BuildingCatalog.housing(node.get_meta("kind", ""))
	return total


func amount(res: String) -> int:
	return floori(resources.get(res, 0.0))


func soldiers() -> int:
	return get_tree().get_nodes_in_group("soldiers").size()


func wizards() -> int:
	return get_tree().get_nodes_in_group("wizards").size()


func count(role: String) -> int:
	return soldiers() if role == "warrior" else wizards()


## The most warriors (or wizards) the village's buildings can train.
func max_count(role: String) -> int:
	return _training_buildings(role).size() * ARMY[role][1]


## Grown-ups that are not warriors, wizards or in training.
func workers() -> int:
	var n := 0
	for v in people():
		if v.can_work() and v.job != "train":
			n += 1
	return n


## Sets how many warriors or wizards the player wants (clamped to what the
## buildings allow).
func set_wanted(role: String, value: int) -> void:
	wanted[role] = clampi(value, 0, max_count(role))
	_army_timer = 0.0


## Progress (0..1) of each recruit now training for `role`.
func training_progress(role: String) -> Array[float]:
	var out: Array[float] = []
	for b in _training:
		var entry: Dictionary = _training[b]
		if entry.role == role:
			out.append(clampf(entry.t / ARMY[role][2], 0.0, 1.0))
	return out


## Food eaten per minute by everyone in the village.
func food_upkeep() -> float:
	var total := 0.0
	for v in people():
		total += FOOD_PER_WARRIOR if v.soldier else (FOOD_PER_WIZARD if v.wizard else FOOD_PER_VILLAGER)
	return total


## Where a worker standing at `from` takes what it gathered: the door of
## the nearest Storehouse, or the middle of the village if there is none.
func drop_point(from: Vector3) -> Vector3:
	var best := center
	var best_d := INF
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) != "store":
			continue
		var d := b.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			var out := from - b.global_position
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.RIGHT
			best = b.global_position + out * (b.footprint + 0.6)
	return best


func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if amount(res) < cost[res]:
			return false
	return true


## What is still needed, e.g. "12 lumber, 3 stone". Empty if affordable.
func shortfall(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in RESOURCES:
		if cost.has(res) and amount(res) < cost[res]:
			parts.append("%d %s" % [cost[res] - amount(res), res])
	return ", ".join(parts)


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		resources[res] -= cost[res]
	return true


func give(res: String, value: float) -> void:
	resources[res] = resources.get(res, 0.0) + value


## True where the village may put up a building.
func in_territory(p: Vector3) -> bool:
	if Vector2(p.x - center.x, p.z - center.z).length() < TERRITORY:
		return true
	for group in ["player_buildings", "construction_sites"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			if Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length() < NEAR_BUILDING:
				return true
	return false


## Seconds until the next child, or -1 when the village is out of housing.
func next_birth_in() -> float:
	if population() >= housing() or amount("food") <= 0:
		return -1.0
	return maxf(0.0, Game.settings.birth_seconds - birth_progress)


func _process(delta: float) -> void:
	if not founded:
		return
	var grown := adults() - wizards()
	give("magicko", (grown * Game.settings.magicko_rate + wizards() * WIZARD_MAGICKO) / 60.0 * delta)
	_eat(delta)
	if population() < housing() and amount("food") > 0:
		birth_progress += delta
		if birth_progress >= Game.settings.birth_seconds:
			birth_progress = 0.0
			_spawn_child()
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.5
		_assign_jobs()
	_army_timer -= delta
	if _army_timer <= 0.0:
		_army_timer = 0.5
		_manage_army()


func _eat(delta: float) -> void:
	give("food", -food_upkeep() / 60.0 * delta)
	if resources.food > 0.0:
		hungry_for = 0.0
		_starve_timer = 0.0
		return
	resources.food = 0.0
	hungry_for += delta
	if hungry_for < STARVE_AFTER:
		return
	_starve_timer -= delta
	if _starve_timer <= 0.0:
		_starve_timer = STARVE_EVERY
		var all := people()
		if not all.is_empty():
			all[randi() % all.size()].starve()


func _spawn_child() -> void:
	var spot := center
	var homes := get_tree().get_nodes_in_group("player_buildings")
	if not homes.is_empty():
		var b := homes[randi() % homes.size()] as Destructible
		var a := randf() * TAU
		spot = b.global_position + Vector3(cos(a), 0.0, sin(a)) * (b.footprint + 1.0)
	var v := WorldPopulator.spawn_villager(Game.world_root, Game.terrain, spot, 1.0, false, true, true)
	v.home = center
	v.home_radius = HOME_RADIUS
	Game.effects.spawn_dust(v.global_position, 0.4)


# --- Work ---------------------------------------------------------------------

## Called every frame by a villager that is at its job.
func work(v: Villager, delta: float) -> void:
	match v.job:
		"build":
			var site := v.job_target as ConstructionSite
			if site:
				site.add_work(delta)
		"train":
			var post := v.job_target as Node3D
			var entry: Dictionary = _training.get(post, {})
			if entry.is_empty() or entry.v != v:
				v.clear_job()
				return
			entry.t += delta
			if entry.t >= ARMY[entry.role][2]:
				_training.erase(post)
				if entry.role == "warrior":
					v.guard = post
					v.become_soldier(post.global_position)
				else:
					v.become_wizard(post.global_position)
		"food":
			v.gather("food", Game.settings.food_rate / 60.0 * delta)
		"farm":
			var field := v.job_target as CropField
			if field == null or not field.needs_work():
				v.clear_job()
			else:
				var reaped := field.add_work(delta)
				if reaped > 0.0:
					v.gather("food", reaped)
		"lumber":
			var gained: float = Game.settings.lumber_rate / 60.0 * delta
			v.gather("lumber", gained)
			var tree := v.job_target as Destructible
			if tree and not tree.destroyed:
				var left: float = tree.get_meta("wood", TREE_WOOD if tree.footprint > 1.6 else BUSH_WOOD) - gained
				tree.set_meta("wood", left)
				if left <= 0.0:
					tree.fell()
		"stone":
			var gained: float = Game.settings.stone_rate / 60.0 * delta
			v.gather("stone", gained)
			var rock := v.job_target as Node3D
			if rock and rock.is_in_group("rocks"):
				var left: float = rock.get_meta("stone", ROCK_STONE * rock.scale.x) - gained
				rock.set_meta("stone", left)
				if left <= 0.0:
					_break_rock(rock)


func _break_rock(rock: Node3D) -> void:
	rock.remove_from_group("rocks")
	rock.remove_from_group("grounded")
	Game.effects.spawn_dust(rock.global_position, clampf(rock.scale.x, 0.5, 2.0))
	var tw := rock.create_tween()
	tw.tween_property(rock, "scale", rock.scale * 0.05, 0.6)
	tw.tween_callback(rock.queue_free)


func _assign_jobs() -> void:
	var workers: Array[Villager] = []
	for v in people():
		if v.can_work() and v.job != "train":
			workers.append(v)
	if workers.is_empty():
		return
	var sites := get_tree().get_nodes_in_group("construction_sites")
	if not sites.is_empty():
		# Everyone grown up helps finish the oldest building first.
		var site := sites[0] as ConstructionSite
		for k in workers.size():
			var v := workers[k]
			if v.job != "build" or not is_instance_valid(v.job_target) or v.job_target != site:
				v.assign_job("build", site.work_spot(k, workers.size()), site)
		return

	var counts := {"lumber": 0, "stone": 0, "food": 0}
	var per_target := {}
	for v in workers:
		if v.job == "build":
			v.clear_job()
		elif counts.has(v.job):
			counts[v.job] += 1
			if is_instance_valid(v.job_target):
				per_target[v.job_target] = per_target.get(v.job_target, 0) + 1
	# Fields that want sowing or reaping come first: foragers move to them.
	var farmers := {}
	for v in workers:
		if v.job == "farm" and is_instance_valid(v.job_target):
			farmers[v.job_target] = farmers.get(v.job_target, 0) + 1
	for node in get_tree().get_nodes_in_group("fields"):
		var field := node as CropField
		if not field.needs_work():
			continue
		var have: int = farmers.get(field, 0)
		while have < field.wanted_workers():
			var v := _spare_worker(workers)
			if v == null:
				break
			if counts.has(v.job):
				counts[v.job] -= 1
			v.assign_job("farm", field.work_spot(), field)
			have += 1
	for v in workers:
		if v.job != "":
			continue
		var kinds: Array = JOB_SHARE.keys()
		# Most-needed job first.
		kinds.sort_custom(func(a: String, b: String) -> bool:
			return JOB_SHARE[a] * workers.size() - counts[a] > JOB_SHARE[b] * workers.size() - counts[b])
		for kind: String in kinds:
			if _give_job(v, kind, per_target):
				counts[kind] += 1
				break


## A worker that can be moved to a field: idle first, then foragers, then
## whoever else is not farming already.
func _spare_worker(workers: Array[Villager]) -> Villager:
	for wanted: String in ["", "food", "lumber", "stone"]:
		for v in workers:
			if v.job == wanted:
				return v
	return null


func _training_buildings(role: String) -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) == ARMY[role][0] and not b.destroyed:
			out.append(b)
	return out


## Trains or stands down warriors and wizards until each matches what the
## player asked for. Each training building takes one recruit at a time.
func _manage_army() -> void:
	# Forget recruits who died, were stood down or lost their building.
	for b in _training.keys():
		var entry: Dictionary = _training[b]
		var v: Villager = entry.v
		if not is_instance_valid(b) or (b as Destructible).destroyed or not is_instance_valid(v) \
				or not v.is_alive() or v.job != "train" or v.job_target != b:
			if is_instance_valid(v) and v.is_alive() and v.job == "train":
				v.clear_job()
			_training.erase(b)
	for role: String in ARMY:
		wanted[role] = mini(wanted[role], max_count(role))
		var training := training_progress(role).size()
		var have := count(role)
		# Too many: stop training first, then send the rest back to work.
		while have + training > wanted[role]:
			if training > 0:
				for b in _training.keys():
					if _training[b].role == role:
						(_training[b].v as Villager).clear_job()
						_training.erase(b)
						break
				training -= 1
			else:
				for v in people():
					if (v.soldier and role == "warrior") or (v.wizard and role == "wizard"):
						v.become_worker()
						break
				have -= 1
		if have + training >= wanted[role]:
			continue
		# Too few: each free training building with room takes a recruit.
		for b in _training_buildings(role):
			if have + training >= wanted[role]:
				break
			if _training.has(b):
				continue
			var recruit := _nearest_worker(b.global_position)
			if recruit == null:
				break
			var out := recruit.global_position - b.global_position
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.RIGHT
			recruit.assign_job("train", b.global_position + out * (b.footprint + 0.8), b)
			_training[b] = {"v": recruit, "t": 0.0, "role": role}
			training += 1


func _nearest_worker(to: Vector3) -> Villager:
	var best: Villager = null
	var best_d := INF
	for v in people():
		if not v.can_work() or v.job == "train":
			continue
		var d := v.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = v
	return best


func _give_job(v: Villager, kind: String, per_target: Dictionary) -> bool:
	match kind:
		"food":
			for attempt in 8:
				var a := randf() * TAU
				var d := randf_range(8.0, 22.0)
				var p := center + Vector3(cos(a) * d, 0.0, sin(a) * d)
				var t := Game.terrain
				if t.is_dry(p.x, p.z) and t.get_normal(p.x, p.z).y > 0.85:
					v.assign_job("food", p, self)
					return true
		"lumber", "stone":
			var target := _nearest_free(v.global_position, "trees" if kind == "lumber" else "rocks", per_target)
			if target == null:
				return false
			var to_center := center - target.global_position
			to_center.y = 0.0
			var dir := to_center.normalized() if to_center.length_squared() > 0.01 else Vector3.RIGHT
			var reach := 1.1 if kind == "lumber" else 1.3 * target.scale.x + 0.5
			v.assign_job(kind, target.global_position + dir * reach, target)
			per_target[target] = per_target.get(target, 0) + 1
			return true
	return false


func _nearest_free(from: Vector3, group: String, per_target: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node3D
		if per_target.get(n, 0) >= MAX_PER_TARGET:
			continue
		var d := Vector2(n.global_position.x - center.x, n.global_position.z - center.z).length()
		if d > WORK_REACH:
			continue
		var tree := n as Destructible
		if tree and (tree.burning or tree.destroyed):
			continue
		var score := n.global_position.distance_to(from) + d * 0.5
		if score < best_d:
			best_d = score
			best = n
	return best
