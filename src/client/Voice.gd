class_name MeatNetVoice extends Node

var is_active: bool = false

# Параметры
var target_sample_rate: int = 8000          # целевая частота после сжатия
var update_interval: float = 0.1            # отправляем пакет каждые 0.1 сек
var vad_threshold: float = 0.01             # порог VAD

# Внутренние
var _mix_rate: int                          # частота микса (обычно 48000)
var _input_buffer: PackedVector2Array = []  # накопленные сэмплы с микрофона
var _accumulated_time: float = 0.0          # сколько времени накоплено

# Для активации микрофона (иногда нужно на Windows)
var _mic_player: AudioStreamPlayer

func _ready() -> void:
	_mix_rate = AudioServer.get_mix_rate()
	print("Mix rate: ", _mix_rate)
	
	# Включаем захват аудио
	#AudioServer.set_enable_input(true)
	
	# Для надёжности создаём плеер с микрофоном, чтобы активировать устройство
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VoiceInput"   # можно любой, лишь бы был
	add_child(_mic_player)
	_mic_player.play()
	

# ---------- Кодирование μ‑law ----------
static func linear_to_mulaw(sample: int) -> int:
	const MAX = 32767
	const BIAS = 33
	var sign = 0 if sample >= 0 else 1
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
	var mulaw = ~(sign << 7 | exponent << 4 | mantissa) & 0xFF
	return mulaw

static func buffer_to_mulaw_bytes(buffer: PackedVector2Array) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(buffer.size())
	for i in buffer.size():
		var mono = (buffer[i].x + buffer[i].y) * 0.5
		var sample = clamp(int(mono * 32767.0), -32768, 32767)
		data[i] = linear_to_mulaw(sample)
	return data

# ---------- Обновление (вызывать из _process) ----------
func update(client: MeatNetClient, delta: float) -> void:
	# 1. Читаем новые сэмплы с микрофона (сколько доступно)
	var available = AudioServer.get_input_frames_available()
	if available > 0:
		var new_frames = AudioServer.get_input_frames(available)
		_input_buffer.append_array(new_frames)
	
	# 2. Накопили достаточно времени для отправки?
	_accumulated_time += delta
	if _accumulated_time < update_interval:
		return
	
	# 3. У нас есть данные для отправки
	var total_frames = _input_buffer.size()
	if total_frames == 0:
		_accumulated_time = 0.0
		return
	
	# 4. Применяем VAD (проверяем RMS по всему буферу)
	var rms = 0.0
	for v in _input_buffer:
		rms += v.x * v.x + v.y * v.y
	rms = sqrt(rms / total_frames)
	if rms < vad_threshold:
		# Тишина — ничего не отправляем, но буфер очищаем
		_input_buffer.clear()
		_accumulated_time = 0.0
		return
	
	# 5. Децимация до target_sample_rate с усреднением
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
	
	# 6. Кодируем в μ‑law
	var audio_bytes = buffer_to_mulaw_bytes(decimated)
	
	# 7. Отправляем пакет
	var packet = {
		"type": "voice",
		"bytes": audio_bytes,
		"sample_rate": target_sample_rate,
		"channels": 1
	}
	client.send(var_to_bytes(packet), false)
	
	# 8. Очищаем буфер и сбрасываем таймер
	_input_buffer.clear()
	_accumulated_time = 0.0
