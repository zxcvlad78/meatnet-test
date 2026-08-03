class_name MeatNetVoice extends Node

var is_active: bool = false
var _capture_effect: AudioEffectCapture
var _mic_player: AudioStreamPlayer

var _send_timer: float = 0.0
var _update_interval: float = 0.1          # интервал отправки (было 0.05)
var target_sample_rate: int = 8000          # новая частота дискретизации
var decimation_factor: int = 6              # 48000 / 8000 = 6 (если микрофон 48 кГц)
var vad_threshold: float = 0.01             # порог активности речи (VAD)

func _ready() -> void:
	_capture_effect = setup_microphone()

func setup_microphone() -> AudioEffectCapture:
	var bus_idx = AudioServer.get_bus_index("VoiceInput")
	if bus_idx == -1:
		push_error("VoiceInput bus not found")
		return null
	
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VoiceInput"
	add_child(_mic_player)
	_mic_player.play()
	
	var effect: AudioEffectCapture = AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectCapture
	if effect == null:
		push_error("VoiceInput has no Capture effect")
	return effect

# ---------- Кодирование в μ‑law (8 бит) вместо 16‑бит PCM ----------
static func linear_to_mulaw(sample: int) -> int:
	const MAX = 32767
	const MULAW_BIAS = 33
	var sign = 0 if sample >= 0 else 1
	sample = abs(sample)
	if sample >= MAX:
		sample = MAX
	var exponent = 0
	var temp = sample >> 8
	while temp != 0:
		exponent += 1
		temp >>= 1
	var mantissa = (sample >> (exponent + 3)) & 0xF
	var mulaw = (~(sign << 7 | exponent << 4 | mantissa)) & 0xFF
	return mulaw

static func buffer_to_mono_bytes(buffer: PackedVector2Array) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(buffer.size())          # 1 байт на сэмпл вместо 2
	for i in buffer.size():
		var mono = (buffer[i].x + buffer[i].y) * 0.5
		var sample = clamp(int(mono * 32767.0), -32768, 32767)
		data[i] = linear_to_mulaw(sample)
	return data

# ---------- Обновление и отправка ----------
func update(client: MeatNetClient, delta: float) -> void:
	if _capture_effect == null:
		return
	
	_send_timer += delta
	if _send_timer >= _update_interval:
		var frames = _capture_effect.get_frames_available()
		if frames > 0:
			var buffer = _capture_effect.get_buffer(frames)
			_capture_effect.clear_buffer()
			
			# --- VAD: проверка активности речи ---
			var rms = 0.0
			for v in buffer:
				rms += v.x * v.x + v.y * v.y
			rms = sqrt(rms / buffer.size())
			if rms < vad_threshold:
				_send_timer = 0.0
				return
			
			# --- Прореживание (даунсэмплинг) до target_sample_rate ---
			var decimated = PackedVector2Array()
			decimated.resize(frames / decimation_factor)
			for i in decimated.size():
				decimated[i] = buffer[i * decimation_factor]
			
			var audio_bytes = buffer_to_mono_bytes(decimated)
			var packet = {
				"type": "voice",
				"bytes": audio_bytes,
				"sample_rate": target_sample_rate,
				"channels": 1
			}
			client.send(var_to_bytes(packet), false)
		_send_timer = 0.0
