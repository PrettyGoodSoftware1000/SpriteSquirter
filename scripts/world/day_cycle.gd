class_name DayCycle
extends Node
## Turns the weather moods into a day: dawn, day, evening and night, one
## after another. The daylight (dawn, daytime and evening) lasts
## Game.settings.day_minutes and the night Game.settings.night_minutes
## (each has a slider in the dev menu). Choosing a mood by hand in the dev
## menu holds only until the next part of the day.
##
## The clock runs from dawn at 6:00 am; night starts at midnight and ends at
## dawn. The clock's hours go by faster or slower to fit: the 18 hours from
## dawn to midnight take the day's minutes, the 6 from midnight to dawn the
## night's. `nightfall` and `midnight` fire as the night begins (when the
## goblins raid), and `morning` when it ends.

signal phase_changed(mood_index: int)
signal nightfall
signal midnight
signal morning

## The hour the day begins, at dawn.
const DAWN_HOUR := 6.0
## How far through the 24-hour clock (counted from dawn) the night begins:
## at midnight, 18 hours after dawn.
const NIGHT_START := 18.0 / 24.0
const MIDNIGHT := NIGHT_START
const PHASES := [
	{"start": 0.0, "mood": 2, "name": "dawn"},
	{"start": 0.1, "mood": 0, "name": "daytime"},
	{"start": 0.6, "mood": 1, "name": "evening"},
	{"start": NIGHT_START, "mood": 3, "name": "night"},
]
## The game starts in the morning.
const START_TIME := 0.12

var atmosphere: Atmosphere
## 0..1 through the current day, on the clock (0 at dawn, NIGHT_START at
## midnight).
var time := START_TIME
var day := 1

var _phase := -1


## Seconds of daylight, and of night.
static func day_seconds() -> float:
	return maxf(float(Game.settings.get("day_minutes", 10.0)), 0.1) * 60.0


static func night_seconds() -> float:
	return maxf(float(Game.settings.get("night_minutes", 8.0)), 0.1) * 60.0


## Seconds of a whole day and night: what "a day" means for things that
## take days (saplings, magic trees).
static func cycle_seconds() -> float:
	return day_seconds() + night_seconds()


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on `delta` seconds (the night's hours pass at their own
## pace), firing nightfall, midnight and morning as they come.
func advance(delta: float) -> void:
	var left := delta
	var guard := 0
	while left > 0.0 and guard < 1000:
		guard += 1
		var night := time >= NIGHT_START
		var rate := (1.0 - NIGHT_START) / night_seconds() if night else NIGHT_START / day_seconds()
		var edge := 1.0 if night else NIGHT_START
		var step := minf(left, maxf(edge - time, 0.0) / rate)
		var before := time
		time += step * rate
		left -= step
		if not night and before < NIGHT_START and time >= NIGHT_START - 0.0000001:
			time = NIGHT_START
			nightfall.emit()
			midnight.emit()
		elif night and time >= 1.0 - 0.0000001:
			time = 0.0
			day += 1
			morning.emit()
	var phase := phase_at(time)
	if phase != _phase:
		var first := _phase < 0
		_phase = phase
		var mood: int = PHASES[phase].mood
		if atmosphere != null:
			atmosphere.set_mood(mood, 0.0 if first else clampf(cycle_seconds() * 0.04, 1.5, 15.0))
		phase_changed.emit(mood)


func is_night() -> bool:
	return time >= NIGHT_START


static func phase_at(t: float) -> int:
	var found := 0
	for k in PHASES.size():
		if t >= PHASES[k].start:
			found = k
	return found


## The hour of the game's day (0..24): dawn at DAWN_HOUR, midnight as the
## night begins.
func hour() -> float:
	return fposmod(DAWN_HOUR + time * 24.0, 24.0)


func clock_text() -> String:
	return "Day %d, %s" % [day, twelve_hour(hour())]


## An hour of the day (0..24) on a 12-hour clock: 16.5 is "4:30 pm".
static func twelve_hour(h: float) -> String:
	var whole := floori(fposmod(h, 24.0))
	var minutes := floori(fmod(fposmod(h, 24.0), 1.0) * 60.0)
	var shown := whole % 12
	if shown == 0:
		shown = 12
	return "%d:%02d %s" % [shown, minutes, "am" if whole < 12 else "pm"]
