extends Camera3D

@export var world_environment: WorldEnvironment

var sky_material: ShaderMaterial

func _ready():
	if world_environment == null:
		push_error("Please assign WorldEnvironment.")
		return

	sky_material = world_environment.environment.sky.sky_material

func _process(_delta):
	if sky_material:
		sky_material.set_shader_parameter("player_pos", global_position)
