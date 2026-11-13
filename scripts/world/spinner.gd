class_name Spinner
extends Node3D
## Turns steadily around its own Z axis (windmill sails).

@export var speed := 0.5


func _process(delta: float) -> void:
	rotate_object_local(Vector3.BACK, speed * delta)
