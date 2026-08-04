extends Node
## Global autoload: persists level completion state to user://progress.cfg

const SAVE_PATH := "user://progress.cfg"

var completed: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for key in cfg.get_section_keys("completed"):
			completed[key] = cfg.get_value("completed", key, false)

func _save() -> void:
	var cfg := ConfigFile.new()
	for key in completed:
		cfg.set_value("completed", key, completed[key])
	cfg.save(SAVE_PATH)

func mark_completed(level: String) -> void:
	completed[level] = true
	_save()

func is_completed(level: String) -> bool:
	return completed.get(level, false)
