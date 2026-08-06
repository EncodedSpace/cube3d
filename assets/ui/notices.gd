extends Control


@export var display_duration: float = 2.0
@export var slide_distance: float = 45.0

@onready var notice_label: Label = $NoticeLabel

var _notice_tween: Tween
var _shown_position: Vector2


func _ready() -> void:
	_shown_position = notice_label.position

	notice_label.visible = false
	notice_label.modulate.a = 0.0


func show_notice(message: String) -> void:
	if message.is_empty():
		return

	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()

	notice_label.text = message
	notice_label.visible = true

	# 从右侧稍微滑入。
	notice_label.position = _shown_position + Vector2(slide_distance, 0.0)
	notice_label.modulate.a = 0.0

	_notice_tween = create_tween()

	_notice_tween.set_parallel(true)
	_notice_tween.set_trans(Tween.TRANS_QUAD)
	_notice_tween.set_ease(Tween.EASE_OUT)

	_notice_tween.tween_property(
		notice_label,
		"position",
		_shown_position,
		0.25
	)

	_notice_tween.tween_property(
		notice_label,
		"modulate:a",
		1.0,
		0.20
	)

	_notice_tween.set_parallel(false)

	# 停留。
	_notice_tween.tween_interval(display_duration)

	# 渐隐。
	_notice_tween.set_trans(Tween.TRANS_QUAD)
	_notice_tween.set_ease(Tween.EASE_IN)

	_notice_tween.tween_property(
		notice_label,
		"modulate:a",
		0.0,
		0.35
	)

	_notice_tween.tween_callback(_hide_notice)


func _hide_notice() -> void:
	notice_label.visible = false
	notice_label.position = _shown_position

func show_notice_from_label(label_name: StringName) -> void:
	var source_label := get_node_or_null(
		NodePath(String(label_name))
	) as Label

	if source_label == null:
		push_warning(
			"找不到 Notice 文字节点：" + String(label_name)
		)
		return

	show_notice(source_label.text)
