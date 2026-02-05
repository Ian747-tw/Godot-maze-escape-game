extends Node
class_name Soundbus

signal sound_emitted(pos: Vector2, loudness: float, kind: String, source: Node)

func emit_sound(pos: Vector2, loudness: float, kind: String, source: Node = null) -> void:
	print("Sound:", kind, " loud=", loudness)
	emit_signal("sound_emitted", pos, loudness, kind, source)
