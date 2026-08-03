class_name MeatNetVoice extends Node

var is_active: bool = false
var _capture_effect: AudioEffectCapture
var _mic_player: AudioStreamPlayer

var _send_timer = 0.0
var _update_interval = 0.05

func _ready() -> void:
	_capture_effect = setup_microphone()

func setup_microphone() -> AudioEffectCapture:
	var bus_idx = AudioServer.get_bus_index("VoiceInput")
	if bus_idx == -1:
		push_error("suka VoiceInput no faut")
		return null
	
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VoiceInput"
	add_child(_mic_player)
	_mic_player.play()
	
	var effect: AudioEffectCapture = AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectCapture
	if effect == null:
		push_error("VoiceInput has nononoon!! Capture")
	return effect

static func buffer_to_mono_bytes(buffer: PackedVector2Array) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(buffer.size() * 2)
	var idx = 0
	for v in buffer:
		var mono = (v.x + v.y) * 0.5
		var s = clamp(int(mono * 32767.0), -32768, 32767)
		data[idx] = s & 0xFF
		data[idx+1] = (s >> 8) & 0xFF
		idx += 2
	return data

static func bytes_to_mono_samples(bytes: PackedByteArray) -> PackedFloat32Array:
	var samples = PackedFloat32Array()
	samples.resize(bytes.size() / 2)
	for i in samples.size():
		var val = bytes[i*2] | (bytes[i*2+1] << 8)
		if val >= 32768: val -= 65536
		samples[i] = val / 32768.0
	return samples


func update(client: MeatNetClient, delta: float) -> void:
	if _capture_effect == null:
		return
	
	_send_timer += delta
	if _send_timer >= _update_interval:
		var frames = _capture_effect.get_frames_available()
		if frames > 0:
			var buffer = _capture_effect.get_buffer(frames)
			_capture_effect.clear_buffer()
			var audio_bytes = buffer_to_mono_bytes(buffer)
			var packet = {
				"type": "voice",
				"bytes": audio_bytes,
				"sample_rate": 48000,
				"channels": 1
			}
			client.send(var_to_bytes(packet), false)
		_send_timer = 0.0
