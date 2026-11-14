class_name DayCycle
extends Node
## Turns the weather moods into a day: dawn, day, evening and night, one
## after another. A full day lasts Game.settings.day_minutes. Choosing a
## mood by hand in the dev menu holds only until the next part of the day.

signal phase_changed(mood_index: int)

const PHASES := [
	{"start": 0.0, "mood": 2, "name": "dawn"},
	{"start": 0.1, "mood": 0, "name": "daytime"},
	{"start": 0.55, "mood": 1, "name": "evening"},
	{"start": 0.7, "mood": 3, "name": "night"},
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
	time += delta / length
	if time >= 1.0:
		time -= 1.0
		day += 1
	var phase := phase_at(time)
	if phase != _phase:
		var first := _phase < 0
		_phase = phase
		var mood: int = PHASES[phase].mood
		atmosphere.set_mood(mood, 0.0 if first else clampf(length * 0.04, 1.5, 15.0))
		phase_changed.emit(mood)


static func phase_at(t: float) -> int:
	var found := 0
	for k in PHASES.size():
		if t >= PHASES[k].start:
			found = k
	return found


func clock_text() -> String:
	return "Day %d: %s" % [day, PHASES[phase_at(time)].name]
