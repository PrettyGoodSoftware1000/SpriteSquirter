class_name Balance
extends RefCounted
## The numbers the player can tune: health, damage, what buildings cost and
## how long they take, what the creature has to learn and how often it casts. They are read from balancing.txt in the
## project folder when the game starts (Game calls load_file()), so they
## can be changed with a text editor. Balance.num("goblin_health") returns
## one. A name missing from the file falls back to the default here.

const PATH := "res://balancing.txt"
const DEFAULTS := {
	"villager_health": 30.0, "villager_damage": 6.0, "villager_attack_seconds": 1.0,
	"warrior_health": 120.0, "warrior_damage": 12.0, "sharper_swords_bonus": 1.5,
	"archer_health": 45.0, "archer_arrow_damage": 12.0, "archer_arrow_seconds": 1.5,
	"wizard_firebolt_damage": 11.0, "wizard_firebolt_seconds": 0.7,
	"goblin_health": 30.0, "goblin_damage": 6.0, "goblin_attack_seconds": 1.0,
	"ogre_health": 300.0, "ogre_damage": 18.0,
	"tortoise_health": 1200.0, "tiger_health": 600.0,
	"creature_stomp_damage": 60.0, "creature_knockout_seconds": 45.0, "creature_gather_amount": 25.0,
	"fireball_damage": 150.0, "fireball_building_damage": 160.0, "creature_friendly_fire": 0.1,
	"building_health": 70.0, "building_health_per_metre": 5.0,
	"knowledge_per_watch": 25.0, "stored_per_lesson": 100.0, "knowledge_per_lesson": 25.0,
	"knowledge_fireball": 100.0, "knowledge_rain": 100.0, "knowledge_roots": 100.0, "knowledge_blood": 100.0,
	"knowledge_lumber": 100.0, "knowledge_stone": 100.0, "knowledge_food": 100.0,
	"cooldown_fireball": 180.0, "cooldown_rain": 180.0, "cooldown_roots": 180.0, "cooldown_blood": 180.0,
	"behavior_start": 50.0, "bless_points": 10.0, "curse_points": 10.0,
	"build_work_per_resource": 10.0,
	"cost_home_lumber": 40.0, "cost_home_stone": 15.0,
	"cost_storehouse_lumber": 35.0, "cost_storehouse_stone": 10.0,
	"cost_town_guard_lumber": 30.0, "cost_town_guard_stone": 40.0, "cost_town_guard_food": 20.0,
	"cost_blacksmith_lumber": 50.0, "cost_blacksmith_stone": 40.0,
	"cost_mushroom_cottage_lumber": 15.0, "cost_mushroom_cottage_stone": 5.0, "cost_mushroom_cottage_food": 30.0,
	"cost_windmill_lumber": 45.0, "cost_windmill_stone": 20.0,
	"cost_crystal_tower_lumber": 20.0, "cost_crystal_tower_stone": 45.0,
	"cost_singing_rocks_stone": 50.0,
	"cost_necromancer_tower_lumber": 20.0, "cost_necromancer_tower_stone": 60.0, "cost_necromancer_tower_bones": 20.0,
	"cost_bridge_lumber_per_metre": 1.0, "bridge_max_length": 40.0,
	"bones_min": 2.0, "bones_max": 4.0,
	"necromancer_training_seconds": 300.0, "necromancers_per_tower": 2.0,
	"skeleton_seconds": 180.0, "skeleton_share": 0.5, "raise_bones": 2.0,
	"goblin_build_minutes": 5.0, "goblin_buildings_max": 20.0,
	"goblin_tent_resources": 40.0, "goblin_war_hut_resources": 60.0, "goblin_forge_resources": 80.0,
	"goblin_potion_hut_resources": 60.0, "goblin_watchtower_resources": 100.0,
}

static var values := {}


static func num(key: String) -> float:
	return values.get(key, DEFAULTS.get(key, 0.0))


## Reads balancing.txt. Lines look like "goblin_health = 30  # note".
static func load_file() -> void:
	values = DEFAULTS.duplicate()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("balancing.txt not found: using the built-in numbers")
		return
	while not file.eof_reached():
		var line := file.get_line().split("#")[0].strip_edges()
		if line == "":
			continue
		var parts := line.split("=")
		var key := parts[0].strip_edges()
		var text := parts[1].strip_edges() if parts.size() == 2 else ""
		if key.begins_with("cost_") and text.is_valid_float():
			# Any building can be given a cost in any resource.
			values[key] = text.to_float()
		elif not DEFAULTS.has(key):
			push_warning("balancing.txt: there is nothing called '%s'" % key)
		elif not text.is_valid_float():
			push_warning("balancing.txt: '%s' needs a number, so the built-in %s is used" % [key, DEFAULTS[key]])
		else:
			values[key] = text.to_float()
