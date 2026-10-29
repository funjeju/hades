extends Area3D
## 매직 미사일. 직선으로 날아가 처음 맞은 적 하나에 피해를 주고 사라진다. 나무·벽에 막히고 최대 거리를 넘으면 사라진다.

@export var speed := 12.0
@export var max_distance := 12.0
@export var damage := 15.0
@export var hit_effect_time := 0.15

var direction := Vector3.FORWARD
## true면 셰이더 미리 컴파일용으로 두 프레임만 그리고 사라진다.
var prewarm := false

var _travelled := 0.0
var _done := false

static var _hit_mesh: SphereMesh


func _ready() -> void:
	if prewarm:
		monitoring = false
		set_physics_process(false)
		_spawn_hit_effect()
		await get_tree().process_frame
		await get_tree().process_frame
		queue_free()
		return
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	_travelled += step
	if _travelled >= max_distance:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	_done = true
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position - direction)
	_spawn_hit_effect()
	queue_free()


## 맞은 자리에 작게 퍼지는 구. 메시·머티리얼은 모든 미사일이 같이 쓴다.
func _spawn_hit_effect() -> void:
	var effect := MeshInstance3D.new()
	effect.mesh = _get_hit_mesh()
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(effect)
	effect.global_position = global_position
	effect.scale = Vector3.ONE * 0.4
	var tween := effect.create_tween().set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * 1.4, hit_effect_time)
	tween.tween_property(effect, "transparency", 1.0, hit_effect_time)
	tween.chain().tween_callback(effect.queue_free)


static func _get_hit_mesh() -> SphereMesh:
	if _hit_mesh == null:
		_hit_mesh = SphereMesh.new()
		_hit_mesh.radius = 0.35
		_hit_mesh.height = 0.7
		_hit_mesh.radial_segments = 12
		_hit_mesh.rings = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.7, 0.95, 1.0)
		_hit_mesh.material = mat
	return _hit_mesh
