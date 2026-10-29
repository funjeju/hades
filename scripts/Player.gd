extends CharacterBody3D
## 마법사. 좌클릭(누르고 있으면 계속 따라감) 또는 WASD(화면 기준)로 걷는다.

@export var move_speed := 5.0
@export var turn_speed := 15.0
@export var stop_distance := 0.2
## 맵 반쪽 크기(40 m 맵이면 20). 클릭 목표를 이 안쪽으로 자른다.
@export var map_half_size := 20.0
## 나무에 정면으로 막혔다고 보는 기준(충돌면 법선과 진행 방향의 내적 절댓값).
@export var head_on_threshold := 0.9
@export var click_marker_time := 0.3

var _target := Vector3.ZERO
var _has_target := false
var _marker: MeshInstance3D
var _marker_tween: Tween

@onready var _radius: float = ($CollisionShape3D.shape as CapsuleShape3D).radius


func _ready() -> void:
	_marker = _make_click_marker()
	add_child(_marker)
	_prewarm_marker()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move"):
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)
			_show_click_marker(_target)


func _physics_process(delta: float) -> void:
	var dir := _get_wasd_direction()
	if dir != Vector3.ZERO:
		_has_target = false
	elif _has_target:
		if Input.is_action_pressed("move"):
			var point = get_mouse_ground_point()
			if point != null:
				_set_target(point)
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() <= stop_distance:
			_has_target = false
		else:
			dir = to_target.normalized()

	if dir != Vector3.ZERO:
		dir = _avoid_obstacle(dir, delta)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)
	velocity = dir * move_speed
	move_and_slide()
	global_position.y = 0.0


## 카메라에서 마우스 위치로 광선을 쏴 바닥 평면(y = 0)과 만나는 점. 못 찾으면 null.
func get_mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, normal)


func _set_target(point: Vector3) -> void:
	var limit := map_half_size - 0.5 - _radius
	_target = Vector3(clampf(point.x, -limit, limit), 0.0, clampf(point.z, -limit, limit))
	_has_target = true


## WASD를 카메라 기준으로 바꾼다. W = 화면 위쪽, D = 화면 오른쪽.
func _get_wasd_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0.0
	forward.y = 0.0
	return (right.normalized() * input.x - forward.normalized() * input.y).normalized()


## 나무에 정면으로 부딪히면 미끄러질 방향이 없으니 옆으로 살짝 틀어 비켜간다.
func _avoid_obstacle(dir: Vector3, delta: float) -> Vector3:
	var hit := move_and_collide(dir * move_speed * delta, true)
	if hit == null or not (hit.get_collider() as Node).is_in_group("trees"):
		return dir
	var normal := hit.get_normal()
	normal.y = 0.0
	normal = normal.normalized()
	if absf(normal.dot(dir)) < head_on_threshold:
		return dir
	var side := Vector3(-normal.z, 0.0, normal.x)
	if side.dot(dir) < 0.0:
		side = -side
	return (dir + side).normalized()


func _make_click_marker() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.22
	mesh.outer_radius = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.95, 1.0)
	mesh.material = mat
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.top_level = true
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	return marker


## 처음 그릴 때의 셰이더 컴파일 멈춤을 없애려고, 시작할 때 땅 밑에 한 프레임 그려 둔다.
func _prewarm_marker() -> void:
	_marker.global_position = Vector3(0.0, -2.0, 0.0)
	_marker.transparency = 0.5
	_marker.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_marker.visible = false


func _show_click_marker(point: Vector3) -> void:
	if _marker_tween:
		_marker_tween.kill()
	_marker.global_position = point + Vector3(0.0, 0.03, 0.0)
	_marker.reset_physics_interpolation()
	_marker.transparency = 0.0
	_marker.visible = true
	_marker_tween = create_tween()
	_marker_tween.tween_property(_marker, "transparency", 1.0, click_marker_time)
	_marker_tween.tween_callback(_marker.hide)
