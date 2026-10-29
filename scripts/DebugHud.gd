extends CanvasLayer
## 3단계 확인용 임시 체력 표시. 7단계에서 HUD를 만들면 지운다.

@export var player: Node

var _label := Label.new()


func _ready() -> void:
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	if player:
		player.health_changed.connect(_on_health_changed)
		player.died.connect(func(): _label.text += "  (쓰러짐)")


func _on_health_changed(current: float, maximum: float) -> void:
	_label.text = "HP %d / %d" % [current, maximum]
