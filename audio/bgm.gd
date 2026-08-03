extends Node

## Drop your track into res://audio/ and name it one of:
## bgm.ogg / bgm.mp3 / bgm.wav
## Or set stream_path below to your filename.

@export var stream_path: String = "res://audio/bgm.mp3"
@export var volume_db: float = -8.0
@export var autoplay: bool = true

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = "Master"
	_player.volume_db = volume_db
	add_child(_player)

	if autoplay:
		play(stream_path)


func play(path: String = "") -> void:
	var resolved := path if not path.is_empty() else stream_path
	if resolved.is_empty():
		return

	if not ResourceLoader.exists(resolved):
		var found := ""
		for alt in ["res://audio/bgm.ogg", "res://audio/bgm.mp3", "res://audio/bgm.wav"]:
			if alt != resolved and ResourceLoader.exists(alt):
				found = alt
				break
		if found.is_empty():
			push_warning("BGM: no audio file at %s (put bgm.ogg/mp3/wav in res://audio/)" % resolved)
			return
		resolved = found

	var stream := load(resolved) as AudioStream
	if stream == null:
		push_warning("BGM: failed to load %s" % resolved)
		return

	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	_player.stream = stream
	_player.volume_db = volume_db
	if not _player.playing:
		_player.play()


func stop() -> void:
	if _player:
		_player.stop()


func set_volume_db(db: float) -> void:
	volume_db = db
	if _player:
		_player.volume_db = db
