class_name MeatNetVoiceListener extends Node

var __audio_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

# Джиттер-буфер для сглаживания задержек
var jitter_buffer: Array = []
var min_buffered_packets: int = 2          # накапливаем минимум 2 пакета перед стартом

func _ready() -> void:
	__audio_player = AudioStreamPlayer.new()
	__audio_player.bus = "VoiceOutput"
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = 8000                  # частота воспроизведения 8 кГц
	__audio_player.stream = stream
	
	add_child(__audio_player)
	__audio_player.play()
	playback = __audio_player.get_stream_playback()

# ---------- Декодирование μ‑law в линейные сэмплы ----------
static func mulaw_to_linear(mulaw: int) -> float:
	var biased = ~mulaw & 0xFF
	var sign = (biased & 0x80) >> 7
	var exponent = (biased & 0x70) >> 4
	var mantissa = biased & 0x0F
	var sample = ((mantissa << 3) + 0x84) << exponent
	if sign:
		sample = -sample
	return sample / 32767.0

static func bytes_to_mono_samples(bytes: PackedByteArray) -> PackedFloat32Array:
	var samples = PackedFloat32Array()
	samples.resize(bytes.size())
	for i in bytes.size():
		samples[i] = mulaw_to_linear(bytes[i])
	return samples

# ---------- Обработка входящего пакета ----------
func msg_process(data: Dictionary) -> void:
	# Помещаем пакет в джиттер-буфер
	jitter_buffer.append(data)
	
	# Если накопили достаточно пакетов — начинаем воспроизведение
	if jitter_buffer.size() < min_buffered_packets:
		return
	
	# Извлекаем первый пакет из буфера (FIFO)
	var packet = jitter_buffer.pop_front()
	var audio_bytes: PackedByteArray = packet["bytes"]
	var mono_samples: PackedFloat32Array = bytes_to_mono_samples(audio_bytes)
	
	# Преобразуем моно в стерео (PackedVector2Array)
	var stereo_buffer = PackedVector2Array()
	stereo_buffer.resize(mono_samples.size())
	for i in mono_samples.size():
		var val = mono_samples[i]
		stereo_buffer[i] = Vector2(val, val)
	
	var can_fit = playback.get_frames_available()
	if can_fit >= stereo_buffer.size():
		playback.push_buffer(stereo_buffer)
	else:
		# Если буфер переполнен — пропускаем (или можно частично)
		pass
