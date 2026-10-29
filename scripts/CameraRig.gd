extends Node3D
## 쿼터뷰 카메라 리그. 플레이어 위치를 부드럽게 따라간다(물리 보간 때문에 _physics_process에서 움직인다).

@export var target: Node3D
@export var follow_speed := 8.0


func _ready() -> void:
	if target:
		global_position = target.global_position
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target:
		global_position = global_position.lerp(target.global_position, 1.0 - exp(-follow_speed * delta))
