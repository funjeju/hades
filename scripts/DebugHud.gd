extends CanvasLayer
## 확인용 임시 표시(체력, 웨이브, 승리). 7단계에서 HUD를 만들면 지운다.

@export var player: Node
@export var wave_manager: Node

var _label := Label.new()
var _hp_text := ""
var _wave_text := ""
var _end_text := ""


func _ready() -> void:
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	if player:
		player.health_changed.connect(_on_health_changed)
		player.died.connect(func(): _set_end("쓰러짐"))
	if wave_manager:
		wave_manager.remaining_changed.connect(_on_remaining_changed)
		wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)


func _on_remaining_changed(remaining: int) -> void:
	_wave_text = "웨이브 %d / %d · 남은 적 %d" % [wave_manager.current_wave, wave_manager.waves.size(), remaining]
	_refresh()


func _on_all_waves_cleared() -> void:
	_set_end("승리! 처치 %d · %.1f초" % [wave_manager.kills, wave_manager.elapsed])


func _on_health_changed(current: float, maximum: float) -> void:
	_hp_text = "HP %d / %d" % [current, maximum]
	_refresh()


func _set_end(text: String) -> void:
	_end_text = text
	_refresh()


func _refresh() -> void:
	_label.text = "\n".join([_hp_text, _wave_text, _end_text]).strip_edges()
