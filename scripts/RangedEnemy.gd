extends Enemy
## 원거리 궁수. 플레이어와 min_distance~max_distance를 유지하며, 조준(예비 동작)이 끝나는 순간의 방향으로 화살을 쏜다.
## min_distance − 1 m보다 가까우면 쏘지 않고 먼저 물러난다.

@export var min_distance := 7.0
@export var max_distance := 9.0
@export var arrow_scene: PackedScene
@export var arrow_forward_offset := 0.5
@export var arrow_height := 0.8

static var _arrow_prewarmed := false


func _ready() -> void:
	super()
	if not _arrow_prewarmed and arrow_scene:
		_arrow_prewarmed = true
		_spawn_arrow.call_deferred(Vector3.FORWARD, Vector3(0.0, -3.0, 0.0), true)


func _can_start_attack(dist: float) -> bool:
	return dist >= min_distance - 1.0 and dist <= max_distance


func _get_chase_velocity(dist: float, delta: float) -> Vector3:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if dist < min_distance:
		return _walk(-to_player.normalized(), delta)
	if dist > max_distance:
		return _walk(to_player.normalized(), delta)
	_face(to_player, delta)
	return Vector3.ZERO


func _perform_attack() -> void:
	if arrow_scene == null:
		return
	var aim := player.global_position - global_position
	aim.y = 0.0
	aim = aim.normalized()
	rotation.y = atan2(-aim.x, -aim.z)
	_spawn_arrow(aim, global_position + aim * arrow_forward_offset + Vector3.UP * arrow_height, false)


func _spawn_arrow(dir: Vector3, pos: Vector3, is_prewarm: bool) -> void:
	var arrow := arrow_scene.instantiate()
	arrow.direction = dir
	arrow.prewarm = is_prewarm
	_get_projectile_parent().add_child(arrow)
	arrow.global_position = pos
	arrow.reset_physics_interpolation()
