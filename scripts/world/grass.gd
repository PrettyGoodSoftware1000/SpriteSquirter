class_name Grass
extends Node3D
## Fills the world with instanced grass.
##
## One patch of blade clumps is generated and reused for every terrain
## chunk. The grass shader does the rest: it lifts each clump onto the
## terrain and hides it on rock, sand, snow, bare dirt and burnt ground, so
## nothing here needs rebuilding when the terrain changes.
##
## Chunks far from the camera switch to a thinner patch with wider blades,
## which looks the same from a distance and draws far fewer triangles.

## Clumps per chunk at full quality (about 5 per square metre).
const CLUMPS_PER_CHUNK := 5200
const FAR_DISTANCE := 85.0
const DENSITY_LEVELS := [1.0, 0.5, 0.25, 0.0]
const DENSITY_NAMES := ["High", "Medium", "Low", "Off"]

## Multiplier for the number of clumps: lower it on slow machines.
static var density := 1.0

var _near: MultiMesh
var _far: MultiMesh
var _chunks: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	for cz in Terrain.CHUNKS:
		for cx in Terrain.CHUNKS:
			var mi := MultiMeshInstance3D.new()
			mi.material_override = Art.grass()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(cx * Terrain.CHUNK - Terrain.HALF, 0.0, cz * Terrain.CHUNK - Terrain.HALF)
			mi.custom_aabb = AABB(Vector3(-1, Terrain.MIN_HEIGHT, -1), Vector3(Terrain.CHUNK + 2, Terrain.MAX_HEIGHT - Terrain.MIN_HEIGHT + 2, Terrain.CHUNK + 2))
			mi.visibility_range_end = 230.0
			add_child(mi)
			_chunks.append(mi)
	rebuild()


## Regenerates the grass patches after `density` changes.
func rebuild() -> void:
	visible = density > 0.0
	if not visible:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mesh := _clump_mesh(rng)
	# Fewer clumps are made wider and taller so the ground stays covered.
	_near = _patch(rng, mesh, int(CLUMPS_PER_CHUNK * density), clampf(1.0 / sqrt(density), 1.0, 2.2))
	_far = _patch(rng, mesh, int(CLUMPS_PER_CHUNK * density * 0.4), clampf(1.5 / sqrt(density), 1.0, 2.6))
	for mi in _chunks:
		mi.multimesh = _near


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var eye := cam.global_position
	var half := Terrain.CHUNK * 0.5
	for mi in _chunks:
		var centre := mi.position + Vector3(half, 0.0, half)
		centre.y = Game.terrain.get_height(centre.x, centre.z) if Game.terrain != null else 0.0
		var wanted := _far if eye.distance_to(centre) > FAR_DISTANCE + half else _near
		if mi.multimesh != wanted:
			mi.multimesh = wanted


func _patch(rng: RandomNumberGenerator, mesh: Mesh, count: int, size: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(count, 1)
	for k in mm.instance_count:
		var s := rng.randf_range(0.75, 1.3) * size
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
		mm.set_instance_transform(k, Transform3D(basis, Vector3(rng.randf() * Terrain.CHUNK, 0.0, rng.randf() * Terrain.CHUNK)))
	return mm


## A tuft of a few curved blades. Vertex colour R runs from 0 at the root to
## 1 at the tip.
func _clump_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for b in 5:
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var root := out * rng.randf_range(0.02, 0.2)
		var h := rng.randf_range(0.3, 0.62)
		var w := rng.randf_range(0.032, 0.055)
		var lean := rng.randf_range(0.08, 0.26)
		mb.color = Color(0, 0, 0)
		var l0 := mb._v(root - side * w, Vector3.UP)
		var r0 := mb._v(root + side * w, Vector3.UP)
		var mid := root + out * lean * 0.3 + Vector3(0, h * 0.55, 0)
		mb.color = Color(0.55, 0, 0)
		var l1 := mb._v(mid - side * w * 0.7, Vector3.UP)
		var r1 := mb._v(mid + side * w * 0.7, Vector3.UP)
		mb.color = Color(1, 0, 0)
		var tip := mb._v(root + out * lean + Vector3(0, h, 0), Vector3.UP)
		mb._quad(l0, r0, l1, r1)
		mb.indices.append_array(PackedInt32Array([l1, r1, tip]))
	return mb.commit()
