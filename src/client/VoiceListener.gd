class_name MeatNetVoiceListener extends Node

var __audio_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	__audio_player = AudioStreamPlayer.new()
	__audio_player.bus = "VoiceOutput"
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = 48000
	__audio_player.stream = stream
	
	add_child(__audio_player)
	__audio_player.play()
	playback = __audio_player.get_stream_playback()

func msg_process(data: Dictionary) -> void:
	var audio_bytes: PackedByteArray = data["bytes"]
	var mono_samples: PackedFloat32Array = MeatNetVoice.bytes_to_mono_samples(audio_bytes)
	print("mono_samples: ", mono_samples)
	var stereo_buffer = PackedVector2Array()
	stereo_buffer.resize(mono_samples.size())
	for i in mono_samples.size():
		var val = mono_samples[i]
		stereo_buffer[i] = Vector2(val, val)
	
	var can_fit = playback.get_frames_available()
	print("can_fit: ", can_fit, " buffer_size: ", stereo_buffer.size())
	if can_fit >= stereo_buffer.size():
		playback.push_buffer(stereo_buffer)
