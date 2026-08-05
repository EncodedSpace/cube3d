extends Node


@export_file("*.ogg", "*.mp3", "*.wav")
var stream_path: String = "res://assets/audio/bgm.mp3"

@export_range(-80.0, 6.0, 0.1)
var volume_db: float = -8.0

@export var autoplay: bool = true


var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = "Master"
	_player.volume_db = volume_db
	_player.process_mode = Node.PROCESS_MODE_ALWAYS

	add_child(_player)

	if autoplay:
		play()


# 播放背景音乐。
# 不传路径时，使用上面的 stream_path。
func play(path: String = "") -> void:
	if _player == null:
		return

	var resolved_path: String = path

	if resolved_path.is_empty():
		resolved_path = stream_path

	if resolved_path.is_empty():
		push_warning("BGM：没有设置背景音乐路径")
		return

	if not ResourceLoader.exists(resolved_path):
		push_warning(
			"BGM：找不到背景音乐文件：%s"
			% resolved_path
		)
		return

	var loaded_resource: Resource = load(
		resolved_path
	)

	var audio_stream: AudioStream = (
		loaded_resource as AudioStream
	)

	if audio_stream == null:
		push_warning(
			"BGM：文件不是有效的音频资源：%s"
			% resolved_path
		)
		return

	_enable_loop(audio_stream)

	_player.stream = audio_stream
	_player.volume_db = volume_db

	# 每次重新播放都从音乐开头开始。
	_player.play(0.0)


# 为不同音频格式开启循环。
func _enable_loop(
	audio_stream: AudioStream
) -> void:
	if audio_stream is AudioStreamOggVorbis:
		var ogg_stream: AudioStreamOggVorbis = (
			audio_stream as AudioStreamOggVorbis
		)

		ogg_stream.loop = true

	elif audio_stream is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = (
			audio_stream as AudioStreamMP3
		)

		mp3_stream.loop = true

	elif audio_stream is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = (
			audio_stream as AudioStreamWAV
		)

		wav_stream.loop_mode = (
			AudioStreamWAV.LOOP_FORWARD
		)


# 停止背景音乐。
func stop() -> void:
	if _player == null:
		return

	_player.stop()


# 判断背景音乐是否正在播放。
func is_playing() -> bool:
	if _player == null:
		return false

	return _player.playing


# 修改背景音乐音量。
func set_volume_db(
	new_volume_db: float
) -> void:
	volume_db = new_volume_db

	if _player != null:
		_player.volume_db = volume_db
