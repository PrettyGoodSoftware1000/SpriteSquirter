class_name DayCycle
extends Node
## Turns the weather moods into a day: dawn, day, evening and night, one
## after another. A full day lasts Game.settings.day_minutes. Choosing a
## mood by hand in the dev menu holds only until the next part of the day.
##
## The night is half as long as the daylight (dawn + daytime + evening):
## one third of the cycle. `nightfall` fires as it begins (when the goblins
## raid), `midnight` halfway through it, and `morning` when the night ends.

signal phase_changed(mood_index: int)
signal nightfall
signal midnight
signal morning

const NIGHT_START := 2.0 / 3.0
const MIDNIGHT := (NIGHT_START + 1.0) * 0.5
const PHASES := [
	{"start": 0.0, "mood": 2, "name": "dawn"},
	{"start": 0.09, "mood": 0, "name": "daytime"},
	{"start": 0.53, "mood": 1, "name": "evening"},
	{"start": NIGHT_START, "mood": 3, "name": "night"},
]
## The game starts in the morning.
const START_TIME := 0.12

var atmosphere: Atmosphere
## 0..1 through the current day.
var time := START_TIME
var day := 1

var _phase := -1


func _process(delta: float) -> void:
	var length: float = maxf(Game.settings.day_minutes, 0.1) * 60.0
	var before := time
	time += delta / length
	if before < NIGHT_START and time >= NIGHT_START:
		nightfall.emit()
	if before < MIDNIGHT and time >= MIDNIGHT:
		midnight.emit()
	if time >= 1.0:
		time -= 1.0
		day += 1
		morning.emit()
	var phase := phase_at(time)
	if phase != _phase:
		var first := _phase < 0
		_phase = phase
		var mood: int = PHASES[phase].mood
		atmosphere.set_mood(mood, 0.0 if first else clampf(length * 0.04, 1.5, 15.0))
		phase_changed.emit(mood)


func is_night() -> bool:
	return time >= NIGHT_START


static func phase_at(t: float) -> int:
	var found := 0
	for k in PHASES.size():
		if t >= PHASES[k].start:
			found = k
	return found


func clock_text() -> String:
	var part: String = PHASES[phase_at(time)].name
	if time >= MIDNIGHT:
		part = "after midnight"
	return "Day %d: %s" % [day, part]
