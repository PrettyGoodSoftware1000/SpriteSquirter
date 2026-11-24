class_name CropField
extends Node3D
## A wheat field the player drew on the ground. Farmers sow it, the wheat
## grows by itself, and villagers reap it for food; then it starts again.
##
## Rain is magic: on a field still being sown it sprouts the whole field at
## once (sown or not) and it starts to grow; on ripe wheat it sprouts
## seedlings in the reaped ground, which count as sown when the reaping is
## done. Wet wheat grows Balance "rain_crop_growth" times as fast.
##
## The field is a rectangle `size` (metres along local X and Z) centred on
## the node. Set position and rotation and call setup() before adding it to
## the tree. Work is counted in villager-seconds per square metre.

enum Stage { SOWING, GROWING, RIPE }

const MIN_SIDE := 4.0
const MAX_SIDE := 28.0
## Lumber a field costs per square metre (fences and tools).
const LUMBER_PER_M2 := 0.1
const SPACING := 0.8
const SOW_SECONDS := 0.2
const REAP_SECONDS := 0.25
## How long sown wheat takes to ripen by itself: Balance "crop_grow_seconds".
## Rained-on wheat grows Balance "rain_crop_growth" times faster, while it
## is wet.
## Food from one square metre of ripe wheat at the default food rate.
const FOOD_PER_M2 := 0.5
const GREEN := Color(0.36, 0.62, 0.2)
const GOLD := Color(1.0, 0.78, 0.26)

static var _clump: Mesh

var size := Vector2(10.0, 10.0)
var stage := Stage.SOWING
## 0..1 through the current stage.
var progress := 0.0

var _crops: MultiMeshInstance3D
## Seedlings the rain sprouted in the reaped part of ripe wheat: the share
## of the field they cover, and how they are drawn (the same spots, from the
## reaped end).
var sprouted := 0.0
var _sprouts: MultiMeshInstance3D
var _shown_sprouts := -1
var _spots := PackedVector3Array()
var _turns := PackedFloat32Array()
var _shown_scale := -1.0
var _wet := 0.0
## Shown over the field while the mouse is on it (show_progress()).
var _label: Label3D


static func cost_for(field_size: Vector2) -> Dictionary:
	return {"lumber": ceili(field_size.x * field_size.y * LUMBER_PER_M2)}


## True if world point `p` is within `margin` of a rectangle on the ground.
static func in_rect(p: Vector3, center: Vector3, rect_size: Vector2, yaw: float, margin := 0.0) -> bool:
	var d := (p - center).rotated(Vector3.UP, -yaw)
	return absf(d.x) <= rect_size.x * 0.5 + margin and absf(d.z) <= rect_size.y * 0.5 + margin


## The four corners of a rectangle on the ground, in world space.
static func rect_corners(center: Vector3, rect_size: Vector2, yaw: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(center + Vector3(c.x * rect_size.x * 0.5, 0.0, c.y * rect_size.y * 0.5).rotated(Vector3.UP, yaw))
	return out


func setup(field_size: Vector2) -> void:
	size = field_size


func _ready() -> void:
	add_to_group("fields")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	var nx := maxi(2, int(size.x / SPACING))
	var nz := maxi(2, int(size.y / SPACING))
	for j in nz:
		for i in nx:
			var x := (float(i) + 0.5) / nx * size.x - size.x * 0.5 + rng.randf_range(-0.15, 0.15)
			var z := (float(j) + 0.5) / nz * size.y - size.y * 0.5 + rng.randf_range(-0.15, 0.15)
			_spots.append(Vector3(x, 0.0, z))
			_turns.append(rng.randf() * TAU)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _clump_mesh()
	mm.instance_count = _spots.size()
	_crops = MultiMeshInstance3D.new()
	_crops.multimesh = mm
	_crops.material_override = Art.paint("plaster", 0.0)
	add_child(_crops)
	var sprout_mm := MultiMesh.new()
	sprout_mm.transform_format = MultiMesh.TRANSFORM_3D
	sprout_mm.mesh = _clump_mesh()
	sprout_mm.instance_count = _spots.size()
	sprout_mm.visible_instance_count = 0
	_sprouts = MultiMeshInstance3D.new()
	_sprouts.multimesh = sprout_mm
	_sprouts.material_override = _crops.material_override
	add_child(_sprouts)

	# Tilled soil, and a post at each corner.
	var terrain := Game.terrain
	var step := 1.4
	for j in int(size.y / step) + 1:
		for i in int(size.x / step) + 1:
			var local := Vector3(minf(i * step, size.x) - size.x * 0.5, 0.0, minf(j * step, size.y) - size.y * 0.5)
			terrain.add_bare(to_global(local), 1.5, 1.0)
	var posts := MeshBuilder.new()
	posts.color = Art.WOOD
	for corner in rect_corners(Vector3.ZERO, size + Vector2(0.6, 0.6), 0.0):
		var world := to_global(corner)
		var y := terrain.get_height(world.x, world.z) - global_position.y
		posts.add_tube(PackedVector3Array([corner + Vector3(0, y - 0.3, 0), corner + Vector3(0, y + 1.1, 0)]),
			PackedFloat32Array([0.12, 0.09]), 6)
	var post_mesh := MeshInstance3D.new()
	post_mesh.mesh = posts.commit()
	post_mesh.material_override = Art.paint("planks", 0.5)
	add_child(post_mesh)

	_settle()
	_refresh()
	terrain.changed.connect(_on_terrain_changed)


func area() -> float:
	return size.x * size.y


## False while the wheat is growing by itself.
func needs_work() -> bool:
	return stage != Stage.GROWING


## True while there is ripe wheat to reap.
func is_ripe() -> bool:
	return stage == Stage.RIPE


func wanted_workers() -> int:
	return clampi(ceili(area() / 40.0), 1, 4)


## A random place in the field for a farmer to stand, in world space.
func work_spot() -> Vector3:
	return to_global(Vector3(randf_range(-0.45, 0.45) * size.x, 0.0, randf_range(-0.45, 0.45) * size.y))


## True while rain is making the wheat grow faster.
func is_wet() -> bool:
	return _wet > 0.0


func contains(p: Vector3, margin := 0.0) -> bool:
	return in_rect(p, global_position, size, rotation.y, margin)


## One villager working for `seconds`. Returns the food reaped.
func add_work(seconds: float) -> float:
	var food := 0.0
	match stage:
		Stage.SOWING:
			progress += seconds / (area() * SOW_SECONDS)
			if progress >= 1.0:
				stage = Stage.GROWING
				progress = 0.0
		Stage.RIPE:
			var done := minf(seconds / (area() * REAP_SECONDS), 1.0 - progress)
			progress += done
			food = done * area() * FOOD_PER_M2 * _food_rate() / Game.DEFAULT_SETTINGS.food_rate
			if progress >= 0.999:
				_reaped()
	_refresh()
	return food


## 0..1 of the way from sowing to ripe wheat (sowing counts as the first
## tenth, growing the rest); 1 once it is ripe.
func ready_share() -> float:
	match stage:
		Stage.SOWING:
			return 0.1 * progress
		Stage.GROWING:
			return 0.1 + 0.9 * progress
	return 1.0


## What the mouse-over label says: how far along it is.
func progress_text() -> String:
	match stage:
		Stage.SOWING:
			return "Wheat field: sowing, %d%% to harvest" % floori(ready_share() * 100.0)
		Stage.GROWING:
			return "Wheat field: growing, %d%% to harvest" % floori(ready_share() * 100.0)
	return "Wheat field: ripe, 100%% (reaping %d%% done)" % floori(progress * 100.0)


## Shows (or hides) how far along it is, over the field.
func show_progress(shown: bool) -> void:
	if shown and _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0011
		_label.font_size = 24
		_label.outline_size = 8
		add_child(_label)
		_label.position = Vector3(0.0, 3.0, 0.0)
	if _label != null:
		_label.visible = shown
		if shown:
			_label.text = progress_text()


## Rain: the field stays wet, and grows faster, for `seconds`. Magic rain
## sprouts a field being sown at once, and seedlings in the reaped part of
## ripe wheat.
func water(seconds: float) -> void:
	_wet = maxf(_wet, seconds)
	match stage:
		Stage.SOWING:
			stage = Stage.GROWING
			progress = 0.0
		Stage.RIPE:
			sprouted = maxf(sprouted, progress)
	_refresh()


## The creature reaps up to `amount` food from ripe wheat in one go.
## Returns what it got.
func take(amount: float) -> float:
	if stage != Stage.RIPE:
		return 0.0
	var per_field: float = area() * FOOD_PER_M2 * _food_rate() / Game.DEFAULT_SETTINGS.food_rate
	var done := minf(amount / maxf(per_field, 0.01), 1.0 - progress)
	progress += done
	if progress >= 0.999:
		_reaped()
	_refresh()
	return done * per_field


## The last of the wheat is reaped: sowing begins again, with whatever the
## rain sprouted already sown.
func _reaped() -> void:
	stage = Stage.SOWING
	progress = clampf(sprouted, 0.0, 0.999)
	sprouted = 0.0


## The village's food rate per worker (with a Windmill's bonus).
func _food_rate() -> float:
	return Game.village.food_rate() if is_instance_valid(Game.village) else float(Game.settings.food_rate)


func _process(delta: float) -> void:
	_wet = maxf(0.0, _wet - delta)
	if stage != Stage.GROWING:
		return
	progress += delta * maxf(0.0, Game.settings.crop_growth_rate) / maxf(1.0, Balance.num("crop_grow_seconds")) * (Balance.num("rain_crop_growth") if _wet > 0.0 else 1.0)
	if progress >= 1.0:
		stage = Stage.RIPE
		progress = 0.0
	_refresh()


## Shows the stage: rows appear as they are sown, grow and turn gold, and
## disappear as they are reaped.
func _refresh() -> void:
	if _label != null and _label.visible:
		_label.text = progress_text()
	var count := _spots.size()
	var grown := 1.0
	var colour := GOLD
	var shown := count
	match stage:
		Stage.SOWING:
			grown = 0.15
			colour = GREEN
			shown = int(progress * count)
		Stage.GROWING:
			grown = lerpf(0.15, 1.0, progress)
			colour = GREEN.lerp(GOLD, smoothstep(0.55, 1.0, progress))
			if _wet > 0.0:
				# Lush and dark while it drinks.
				colour = colour.lerp(Color(0.16, 0.6, 0.3), 0.35)
		Stage.RIPE:
			shown = int((1.0 - progress) * count)
	_crops.multimesh.visible_instance_count = shown
	_crops.set_instance_shader_parameter("tint", colour)
	# Seedlings in the reaped ground (drawn from the far end of the rows).
	var seedlings := int(sprouted * count) if stage == Stage.RIPE else 0
	if seedlings != _shown_sprouts:
		_shown_sprouts = seedlings
		for k in seedlings:
			var spot := count - 1 - k
			_sprouts.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, _turns[spot]).scaled(Vector3(0.55, 0.18, 0.55)), _spots[spot]))
		_sprouts.multimesh.visible_instance_count = seedlings
	_sprouts.set_instance_shader_parameter("tint", GREEN)
	# Resizing every clump is only worth it when the change can be seen.
	grown = snappedf(grown, 0.05)
	if not is_equal_approx(grown, _shown_scale):
		_shown_scale = grown
		var wide := lerpf(0.5, 1.0, grown)
		for k in count:
			var turned := Basis(Vector3.UP, _turns[k]).scaled(Vector3(wide, grown, wide))
			_crops.multimesh.set_instance_transform(k, Transform3D(turned, _spots[k]))


## Puts every clump on the ground.
func _settle() -> void:
	var terrain := Game.terrain
	for k in _spots.size():
		var world := to_global(Vector3(_spots[k].x, 0.0, _spots[k].z))
		_spots[k].y = terrain.get_height(world.x, world.z) - global_position.y
	_shown_scale = -1.0
	_shown_sprouts = -1


func _on_terrain_changed(center: Vector3, radius: float) -> void:
	if Vector2(center.x - global_position.x, center.z - global_position.z).length() < radius + size.length() * 0.5:
		_settle()
		_refresh()


## A handful of wheat stalks, shared by every field. White ears and grey
## stalks: the field's tint gives them their colour.
static func _clump_mesh() -> Mesh:
	if _clump != null:
		return _clump
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mb := MeshBuilder.new()
	for k in 5:
		var base := Vector3(rng.randf_range(-0.26, 0.26), 0.0, rng.randf_range(-0.26, 0.26))
		var lean := Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.14, 0.14))
		var h := rng.randf_range(0.95, 1.3)
		mb.color = Color(0.72, 0.72, 0.72)
		mb.add_tube(PackedVector3Array([base, base + lean * 0.4 + Vector3.UP * h * 0.6, base + lean + Vector3.UP * h]),
			PackedFloat32Array([0.035, 0.03, 0.025]), 4)
		mb.color = Color(1.0, 1.0, 1.0)
		mb.add_blob(Vector3(0.07, 0.2, 0.07), Transform3D(Basis(), base + lean * 1.1 + Vector3.UP * (h + 0.12)), null, 0.0, 4, 6)
	_clump = mb.commit()
	return _clump
