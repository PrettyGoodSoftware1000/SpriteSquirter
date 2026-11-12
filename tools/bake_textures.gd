extends SceneTree
## Renders the procedural patterns in tools/bake/patterns.gdshader to PNG
## files in assets/textures/. Run it from the project folder with:
##
##   godot --path . -s tools/bake_textures.gd
##
## Tiling surfaces get two files: <name>_detail.png (R brightness, G random
## id per element, B height) and <name>_normal.png. Sprites get one RGBA file.

const SIZE := 512
const OUT_DIR := "res://assets/textures/"

## name: [pattern index, kind, normal strength]
const PATTERNS := {
	"stone": [0, "surface", 3.5],
	"rock": [1, "surface", 3.5],
	"planks": [2, "surface", 3.0],
	"shingles": [3, "surface", 3.0],
	"plaster": [4, "surface", 2.0],
	"bark": [5, "surface", 4.0],
	"thatch": [6, "surface", 3.0],
	"ground": [7, "surface", 2.0],
	"dirt": [8, "surface", 3.0],
	"hide": [9, "surface", 3.5],
	"noise": [10, "data", 0.0],
	"leaves": [11, "sprite", 0.0],
	"flame": [12, "sprite", 0.0],
	"smoke": [13, "sprite", 0.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var material := ShaderMaterial.new()
	material.shader = load("res://tools/bake/patterns.gdshader")
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	rect.material = material
	viewport.add_child(rect)

	for pattern_name in PATTERNS:
		var info: Array = PATTERNS[pattern_name]
		material.set_shader_parameter("pattern", info[0])
		material.set_shader_parameter("normal_strength", info[2])
		match info[1]:
			"surface":
				await _save(viewport, material, 0, pattern_name + "_detail.png")
				await _save(viewport, material, 1, pattern_name + "_normal.png")
			"data":
				await _save(viewport, material, 0, pattern_name + ".png")
			"sprite":
				await _save(viewport, material, 2, pattern_name + ".png")
	print("Textures baked to ", OUT_DIR)
	quit()


func _save(viewport: SubViewport, material: ShaderMaterial, mode: int, file_name: String) -> void:
	material.set_shader_parameter("mode", mode)
	for k in 3:
		await process_frame
	var image := viewport.get_texture().get_image()
	if mode != 2:
		image.convert(Image.FORMAT_RGB8)
	image.save_png(OUT_DIR + file_name)
	print("  ", file_name)
