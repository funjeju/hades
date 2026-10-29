extends Area3D
## 궁수의 화살. 쏜 순간의 방향으로 직선으로 날아가 플레이어에게 피해를 준다. 나무·벽에 닿거나 최대 거리를 넘으면 사라진다.

@export var speed := 7.0
@export var max_distance := 20.0
@export var damage := 8.0

var direction := Vector3.FORWARD
## true면 셰이더 미리 컴파일용으로 두 프레임만 그리고 사라진다.
var prewarm := false

var _travelled := 0.0
var _done := false


func _ready() -> void:
	rotation.y = atan2(-direction.x, -direction.z)
	if prewarm:
		monitoring = false
		set_physics_process(false)
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
	queue_free()
