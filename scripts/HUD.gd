extends CanvasLayer
## 화면 UI 전부: 체력 바, 스킬 칸 3개, 웨이브 표시, 웨이브 안내, 피격 비네트, 결과 화면. 모두 코드로 만든다.
## 플레이어와 WaveManager의 신호만 듣는다. R 키 재시작도 여기서 처리한다.

@export var player: Node
@export var wave_manager: Node
@export var banner_time := 1.5
@export var vignette_time := 0.2
@export var vignette_strength := 0.7
@export var defeat_result_delay := 1.0
@export var victory_result_delay := 0.6

const SKILL_KEYS: Array[String] = ["우클릭", "Q", "Space"]
const SKILL_NAMES: Array[String] = ["근접", "미사일", "순간이동"]
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.414;
	COLOR = vec4(0.9, 0.05, 0.05, smoothstep(0.6, 1.05, d) * intensity);
}
"""

var _root: Control
var _hp_fill: ColorRect
var _hp_label: Label
var _hp_bar_width := 300.0
var _last_health := -1.0
var _skill_slots: Array[Control] = []
var _skill_timers: Array[Label] = []
var _wave_label: Label
var _banner: Label
var _banner_tween: Tween
var _vignette_mat: ShaderMaterial
var _vignette_tween: Tween
var _result: Control
var _result_title: Label
var _result_detail: Label
var _result_shown := false


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_vignette()
	_build_health_bar()
	_build_skill_slots()
	_build_wave_labels()
	_build_result()
	if player:
		player.health_changed.connect(_on_health_changed)
		player.died.connect(_on_player_died)
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
		wave_manager.remaining_changed.connect(_on_remaining_changed)
		wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if player == null:
		return
	var cooldowns: Array[Vector2] = player.get_skill_cooldowns()
	for i in cooldowns.size():
		var left := cooldowns[i].x
		_skill_slots[i].modulate = Color(0.45, 0.45, 0.45) if left > 0.0 else Color.WHITE
		_skill_timers[i].text = "%.1f" % left if left > 0.0 else ""


# --- 신호 ---

func _on_health_changed(current: float, maximum: float) -> void:
	_hp_fill.size.x = _hp_bar_width * clampf(current / maximum, 0.0, 1.0)
	_hp_label.text = "%d / %d" % [ceili(current), maximum]
	if _last_health >= 0.0 and current < _last_health:
		_flash_vignette()
	_last_health = current


func _on_wave_started(wave_number: int, _total: int) -> void:
	_banner.text = "웨이브 %d" % wave_number
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner.visible = true
	_banner_tween = create_tween()
	_banner_tween.tween_interval(banner_time - 0.3)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(_banner.hide)


func _on_remaining_changed(remaining: int) -> void:
	_wave_label.text = "웨이브 %d / %d · 남은 적 %d" % [wave_manager.current_wave, wave_manager.waves.size(), remaining]


func _on_all_waves_cleared() -> void:
	get_tree().create_timer(victory_result_delay).timeout.connect(_show_result.bind(true))


func _on_player_died() -> void:
	get_tree().create_timer(defeat_result_delay).timeout.connect(_show_result.bind(false))


func _show_result(victory: bool) -> void:
	if _result_shown:
		return
	_result_shown = true
	_result_title.text = "승리!" if victory else "쓰러졌다…"
	_result_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if victory else Color(0.9, 0.3, 0.3))
	var kills: int = wave_manager.kills if wave_manager else 0
	var seconds: int = int(wave_manager.elapsed) if wave_manager else 0
	_result_detail.text = "처치 %d · 걸린 시간 %d:%02d\n\nR 키로 다시 시작" % [kills, seconds / 60, seconds % 60]
	_result.visible = true


func _flash_vignette() -> void:
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette_mat.set_shader_parameter("intensity", vignette_strength)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(func(v: float): _vignette_mat.set_shader_parameter("intensity", v), vignette_strength, 0.0, vignette_time)


# --- 만들기 ---

## 한글이 나오도록 시스템 폰트를 기본 폰트로 쓴다.
func _make_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("outline_size", "Label", 6)
	return theme


func _build_vignette() -> void:
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = shader
	var rect := ColorRect.new()
	rect.material = _vignette_mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 처음부터 그려 두어(세기 0) 첫 피격 때 셰이더 컴파일로 멈추지 않게 한다.
	_root.add_child(rect)


func _build_health_bar() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -56)
	_root.add_child(box)
	var back := _rect(Color(0.1, 0.1, 0.1, 0.8), Vector2(_hp_bar_width + 6, 34))
	back.position = Vector2(-3, -3)
	box.add_child(back)
	_hp_fill = _rect(Color(0.85, 0.15, 0.15), Vector2(_hp_bar_width, 28))
	box.add_child(_hp_fill)
	_hp_label = _label("", 20)
	_hp_label.size = Vector2(_hp_bar_width, 28)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_hp_label)


func _build_skill_slots() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_root.add_child(row)
	for i in SKILL_KEYS.size():
		var slot := _rect(Color(0.12, 0.16, 0.3, 0.85), Vector2(92, 84))
		slot.custom_minimum_size = slot.size
		row.add_child(slot)
		var key := _label(SKILL_KEYS[i], 18)
		key.position = Vector2(6, 2)
		slot.add_child(key)
		var name_label := _label(SKILL_NAMES[i], 16)
		name_label.position = Vector2(6, 58)
		slot.add_child(name_label)
		var timer := _label("", 26)
		timer.size = slot.size
		timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(timer)
		_skill_slots.append(slot)
		_skill_timers.append(timer)
	# 칸을 다 넣어 최소 크기가 정해진 뒤 아래 가운데에 붙인다.
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)


func _build_wave_labels() -> void:
	_wave_label = _label("", 24)
	_wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.position.y = 16
	_root.add_child(_wave_label)

	_banner = _label("", 64)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.visible = false
	_root.add_child(_banner)


func _build_result() -> void:
	_result = _rect(Color(0, 0, 0, 0.55), Vector2.ZERO)
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	_root.add_child(_result)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_result.add_child(column)
	_result_title = _label("", 72)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_constant_override("outline_size", 12)
	column.add_child(_result_title)
	_result_detail = _label("", 28)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_detail)


func _rect(color: Color, rect_size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = rect_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label
