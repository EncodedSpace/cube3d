#Breathing负责控制静息状态的呼吸起伏

extends Node3D

#呼吸起伏幅度
@export var breath_amount := 0.06
#一次呼吸所需秒数
@export var breath_cycle := 2.5

var breathing := true
var phase := 0.0
var breath_weight := 1.0


func _process(delta: float) -> void:
	phase += delta * TAU / breath_cycle

	var target_weight := 1.0 if breathing else 0.0
	breath_weight = move_toward(
		breath_weight,
		target_weight,
		delta * 5.0
	)

	var wave := sin(phase) * breath_amount * breath_weight
	var scale_y := 1.0 + wave
	var scale_xz := 1.0 - wave * 0.10

	scale = Vector3(scale_xz, scale_y, scale_xz)

	# 保持方块底部基本不动
	position.y = (scale_y - 1.0) * 0.5
