class_name BuildingPreview
extends SubViewportContainer
## A small picture of a building's model, for the build menu: the model
## stands in a little world of its own (a SubViewport), lit from the side
## so it shows its shape, and is drawn once when the menu first opens.

var _viewport: SubViewport
var _drawn := false


## A picture of building `kind`, `size` pixels.
static func make(kind: String, size: Vector2i) -> BuildingPreview:
	var p := BuildingPreview.new()
	p.custom_minimum_size = size
	p.stretch = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	p.add_child(vp)
	p._viewport = vp
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := BuildingFactory.create(kind, rng)
	b.is_ghost = true # (so it joins no groups and never burns)
	vp.add_child(b)
	for child in b.get_children():
		if child is StaticBody3D or child is CPUParticles3D:
			child.queue_free()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-50.0), 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	vp.add_child(sun)
	# Framed from a little above and to one side, the whole model in view.
	var cam := Camera3D.new()
	cam.fov = 30.0
	var tall := maxf(b.height, 2.0)
	var wide := maxf(b.footprint * 2.2, 3.0)
	var reach := maxf(tall * 1.1, wide * float(size.y) / float(size.x) * 1.1)
	var distance := reach * 0.5 / tan(deg_to_rad(cam.fov * 0.5)) + b.footprint
	var yaw := deg_to_rad(35.0)
	var pitch := deg_to_rad(22.0)
	var look := Vector3(0.0, tall * 0.45, 0.0)
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, look)
	return p


## Draws the picture, the first time it is asked for.
func draw_once() -> void:
	if _drawn or _viewport == null:
		return
	_drawn = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
