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
	"tortoise_health": 1200.0,
	"creature_stomp_damage": 60.0, "creature_gather_amount": 25.0, "resurrect_animus": 5.0,
	"fireball_damage": 150.0, "fireball_building_damage": 160.0, "creature_friendly_fire": 0.1,
	"building_health": 70.0, "building_health_per_metre": 5.0,
	"knowledge_per_watch": 25.0, "stored_per_lesson": 100.0, "knowledge_per_lesson": 25.0,
	"knowledge_fireball": 100.0, "knowledge_rain": 100.0, "knowledge_roots": 100.0, "knowledge_blood": 100.0,
	"knowledge_lumber": 100.0, "knowledge_stone": 100.0, "knowledge_food": 100.0,
	"cooldown_fireball": 30.0, "cooldown_rain": 30.0, "cooldown_roots": 30.0, "cooldown_blood": 60.0,
	"affinity_start": 0.0, "bless_points": 10.0, "condemn_points": 10.0, "affinity_spread": 25.0,
	"judge_cooldown": 60.0, "judge_cooldown_30": 180.0, "judge_cooldown_60": 360.0, "judge_cooldown_80": 720.0,
	"wander_weight": 1.0, "explore_weight": 0.25, "spell_hold_weight": 1.0, "mischief_weight": 0.0005,
	"rain_enemies_weight": 0.3, "creature_blood_magicko": 25.0, "gnome_count": 5.0, "gnome_distance": 50.0, "gnome_speed": 9.0, "gnome_work": 1.0,
	"flee_chance_unharmed": 0.05, "flee_chance_slightly": 0.1, "flee_chance_badly": 0.2, "flee_chance_near_death": 0.4,
	"explore_least": 40.0,
	"build_work_per_resource": 5.0,
	"cost_home_lumber": 40.0, "cost_home_stone": 15.0,
	"cost_storehouse_lumber": 35.0, "cost_storehouse_stone": 10.0,
	"cost_town_guard_lumber": 30.0, "cost_town_guard_stone": 40.0, "cost_town_guard_food": 20.0,
	"cost_blacksmith_lumber": 50.0, "cost_blacksmith_stone": 40.0,
	"cost_cottage_lumber": 15.0, "cost_cottage_stone": 5.0, "cost_cottage_food": 30.0,
	"cost_decoration_lumber": 30.0, "cost_decoration_stone": 30.0,
	"cost_wizardry_tower_lumber": 20.0, "cost_wizardry_tower_stone": 50.0, "cost_shrine_stone": 50.0,
	"cost_granary_lumber": 40.0, "cost_granary_stone": 20.0,
	"home_housing": 6.0, "cottage_housing": 3.0, "storehouse_housing": 25.0, "start_villagers": 20.0, "builders_per_building": 5.0,
	"storehouse_holds": 300.0, "granary_holds": 300.0, "animus_per_shrine": 1.0,
	"cost_necromancer_tower_lumber": 20.0, "cost_necromancer_tower_stone": 60.0, "cost_necromancer_tower_bones": 20.0,
	"cost_bridge_lumber_per_metre": 1.0, "bridge_max_length": 35.0,
	"bones_min": 2.0, "bones_max": 4.0,
	"necromancer_training_seconds": 75.0,
	"warrior_training_seconds": 15.0, "archer_training_seconds": 22.5, "wizard_training_seconds": 45.0, "necromancers_per_tower": 2.0,
	"skeleton_seconds": 180.0, "skeleton_share": 0.5, "raise_bones": 2.0,
	"goblin_build_minutes": 5.0, "goblin_buildings_max": 20.0, "goblin_rate_per_building": 0.5,
	"goblin_tent_resources": 40.0, "goblin_war_hut_resources": 60.0, "goblin_forge_resources": 80.0,
	"goblin_potion_hut_resources": 60.0, "goblin_watchtower_resources": 100.0,
	"lightning_damage": 40.0, "lightning_jumps": 12.0, "lightning_jump_range": 9.0, "lightning_wet_bonus": 2.0, "wet_seconds": 20.0,
	"knowledge_lightning": 100.0, "cooldown_lightning": 30.0,
	"ogres_per_war_hut": 1.0, "bats_per_watchtower": 1.0, "bats_from_night": 3.0, "bat_health": 80.0, "bat_speed": 11.0,
	"creature_stamina": 100.0, "creature_stamina_regen": 6.0, "creature_magicko": 100.0, "creature_magicko_regen": 1.0,
	"fly_stamina_per_second": 5.0, "run_stamina_per_second": 5.0, "squirrel_run_speed": 1.5, "squirrel_run_distance": 20.0,
	"level_points": 100.0, "level_points_most": 1000.0, "level_max_gain": 0.1, "level_regen_gain": 0.2, "tortoise_walk_stamina": 1.0,
	"shell_damage_share": 0.2, "shell_think_seconds": 8.0, "shell_calm_seconds": 5.0, "shell_max_seconds": 15.0,
	"creature_cost_fireball": 25.0, "creature_cost_rain": 30.0, "creature_cost_roots": 35.0, "creature_cost_lightning": 35.0,
	"creature_cost_blood": 20.0,
	"squirrel_health": 600.0,
	"slope_slow_from": 0.3, "slope_slowest": 0.3, "cliff_grade": 1.6,
	"farmer_speed": 2.0, "rock_stone": 120.0, "rock_crumble_seconds": 4.0,
	"spell_recent_seconds": 10.0, "spell_recent_extra": 0.5,
	"creature_shrink_on_knockout": 0.25, "creature_getup_health": 1.0, "creature_young_appetite": 0.5,
	"raven_health": 800.0, "raven_fly_distance": 30.0, "raven_fly_height": 9.0, "raven_fly_speed": 2.5,
	"creature_strike_damage": 70.0,
	"balrogs": 1.0, "balrog_health": 2000.0, "balrog_speed": 2.3, "balrog_guard_radius": 40.0,
	"balrog_fireball_size": 0.5, "balrog_fireball_seconds": 20.0, "balrog_fireball_power": 0.5,
	"balrog_building_damage": 40.0, "balrog_respawn_minutes": 10.0, "balrog_bones": 12.0,
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
