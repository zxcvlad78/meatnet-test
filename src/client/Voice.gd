class_name MeatNetVoice extends Node

var is_active: bool = false

var target_sample_rate: int = 8000
var update_interval: float = 0.1
var vad_threshold: float = 0.01

var _input_buffer: PackedVector2Array = []
var _mix_rate: float
var _accumulated_time: float = 0.0

var _mic_player: AudioStreamPlayer

enum ActivationMode {
	Voice = 0,
	PushToTalk,
}

var activation_mode: ActivationMode = ActivationMode.Voice

func _ready() -> void:
	activation_mode = ProjectSettings.get_setting("voicechat/activation_mode", 0)# as ActivationMode
	_mix_rate = AudioServer.get_mix_rate()
	
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VoiceInput"
	add_child(_mic_player)
	_mic_player.play()

func _input(event: InputEvent) -> void:
	if activation_mode != ActivationMode.PushToTalk:
		return
	is_active = Input.is_action_pressed("push_to_talk")

static func linear_to_mulaw(sample: int) -> int:
	const MAX = 32767
	const BIAS = 33
	var i_sign = 0 if sample >= 0 else 1
	sample = abs(sample)
	if sample >= MAX:
		sample = MAX
	sample += BIAS
	var exponent = 0
	var temp = sample >> 8
	while temp != 0:
		exponent += 1
		temp >>= 1
	var mantissa = (sample >> (exponent + 3)) & 0xF
	var mulaw = ~(i_sign << 7 | exponent << 4 | mantissa) & 0xFF
	return mulaw

static func buffer_to_mulaw_bytes(buffer: PackedVector2Array) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(buffer.size())
	for i in buffer.size():
		var mono = (buffer[i].x + buffer[i].y) * 0.5
		var sample = clamp(int(mono * 32767.0), -32768, 32767)
		data[i] = linear_to_mulaw(sample)
	return data

func update(client: MeatNetClient, delta: float) -> void:
	var available = AudioServer.get_input_frames_available()
	if available > 0:
		var new_frames = AudioServer.get_input_frames(available)
		_input_buffer.append_array(new_frames)
	
	activation_mode = ProjectSettings.get_setting("voice/activation_mode", 0)
	_accumulated_time += delta
	if _accumulated_time < update_interval:
		return
	
	
	var total_frames = _input_buffer.size()
	if total_frames == 0:
		_accumulated_time = 0.0
		return
	
	if activation_mode != ActivationMode.PushToTalk:
		if vad_threshold > 0.0:
			var rms = 0.0
			for v in _input_buffer:
				rms += v.x * v.x + v.y * v.y
			rms = sqrt(rms / total_frames)
			if rms < vad_threshold:
				_input_buffer.clear()
				_accumulated_time = 0.0
				return
	else:
		if !is_active:
			return
	
	var decimation_factor = roundi(_mix_rate / float(target_sample_rate))
	if decimation_factor < 1:
		decimation_factor = 1
	var decimated = PackedVector2Array()
	decimated.resize(total_frames / decimation_factor)
	for i in decimated.size():
		var sum = Vector2()
		for j in range(decimation_factor):
			sum += _input_buffer[i * decimation_factor + j]
		decimated[i] = sum / decimation_factor
	
	var audio_bytes = buffer_to_mulaw_bytes(decimated)
	
	var packet = {
		"type": "voice",
		"bytes": audio_bytes,
		"sample_rate": target_sample_rate,
		"channels": 1
	}
	client.send(var_to_bytes(packet), true)
	
	_input_buffer.clear()
	_accumulated_time = 0.0
