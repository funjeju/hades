extends CharacterBody3D
## 마법사. 좌클릭(누르고 있으면 계속 따라감) 또는 WASD(화면 기준)로 걷고, 우클릭으로 커서 방향 근접 공격.

signal died
signal health_changed(current: float, maximum: float)

@export_group("이동")
@export var move_speed := 5.0
@export var turn_speed := 15.0
@export var stop_distance := 0.2
## 맵 반쪽 크기(40 m 맵이면 20). 클릭 목표를 이 안쪽으로 자른다.
@export var map_half_size := 20.0
## 나무에 정면으로 막혔다고 보는 기준(충돌면 법선과 진행 방향의 내적 절댓값).
@export var head_on_threshold := 0.9
@export var click_marker_time := 0.3

@export_group("체력")
@export var max_health := 100.0
@export var hit_invuln_time := 0.5
@export var blink_interval := 0.08

@export_group("근접 공격")
@export var melee_damage := 20.0
@export var melee_range := 1.8
@export var melee_angle := 90.0
@export var melee_knockback := 1.0
@export var melee_cooldown := 0.4
## 공격 순간 제자리에 서 있는 시간.
@export var attack_lock_time := 0.15
@export var slash_time := 0.1

@export_group("매직 미사일")
@export var missile_scene: PackedScene
@export var missile_cooldown := 0.6
## 몸 중심에서 앞으로 얼마나, 얼마나 높이에서 나가는지.
@export var missile_forward_offset := 0.5
@export var missile_height := 1.0

@export_group("순간이동")
@export var teleport_distance := 4.0
@export var teleport_invuln_time := 0.3
@export var teleport_cooldown := 3.0
@export var teleport_effect_time := 0.3

var health := 0.0
var is_dead := false

var _target := Vector3.ZERO
var _has_target := false
## 공격으로 멈춘 뒤에는 누르고 있던 좌클릭을 무시하고, 새로 클릭해야 다시 걷는다.
var _ignore_held_move := false
var _melee_cooldown_left := 0.0
var _missile_cooldown_left := 0.0
var _teleport_cooldown_left := 0.0
var _action_lock_left := 0.0
var _invuln_left := 0.0
var _blink_left := 0.0
var _marker: MeshInstance3D
var _marker_tween: Tween
var _slash: MeshInstance3D
var _slash_tween: Tween
var _teleport_from_fx: MeshInstance3D
var _teleport_to_fx: MeshInstance3D
var _teleport_from_tween: Tween
var _teleport_to_tween: Tween

@onready var _shape_node: CollisionShape3D = $CollisionShape3D
@onready var _radius: float = (_shape_node.shape as CapsuleShape3D).radius
@onready var _body: MeshInstance3D = $Body
@onready var _nose: MeshInstance3D = $Nose


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_marker = _make_click_marker()
	add_child(_marker)
	_slash = _make_slash()
	add_child(_slash)
	var ring := _make_teleport_ring()
	_teleport_from_fx = _make_effect(ring)
	_teleport_to_fx = _make_effect(ring)
	add_child(_teleport_from_fx)
	add_child(_teleport_to_fx)
	_prewarm([_marker, _slash, _teleport_from_fx])
	_prewarm_missile.call_deferred()
	health_changed.emit.call_deferred(health, max_health)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event.is_action_pressed("teleport"):
		_try_teleport()
	elif event.is_action_pressed("move"):
		_ignore_held_move = false
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)
			_show_click_marker(_target)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_melee_cooldown_left -= delta
	_missile_cooldown_left -= delta
	_teleport_cooldown_left -= delta
	_action_lock_left -= delta
	_invuln_left -= delta
	_update_blink(delta)

	if Input.is_action_pressed("attack_melee") and _melee_cooldown_left <= 0.0:
		_melee_attack()
	if Input.is_action_pressed("cast_missile") and _missile_cooldown_left <= 0.0:
		_cast_missile()

	velocity = Vector3.ZERO
	if _action_lock_left <= 0.0:
		var dir := _get_move_direction()
		if dir != Vector3.ZERO:
			dir = _avoid_obstacle(dir, delta)
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)
		velocity = dir * move_speed
	move_and_slide()
	global_position.y = 0.0


## 공격하는 쪽이 호출한다. 적과 같은 이름의 함수.
func take_damage(amount: float, _from_position: Vector3, _knockback := 0.0) -> void:
	if is_dead or _invuln_left > 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	_invuln_left = hit_invuln_time
	_blink_left = hit_invuln_time


## HUD 스킬 칸용: 근접, 미사일, 순간이동 순서로 (남은 초, 전체 쿨다운).
func get_skill_cooldowns() -> Array[Vector2]:
	return [
		Vector2(maxf(_melee_cooldown_left, 0.0), melee_cooldown),
		Vector2(maxf(_missile_cooldown_left, 0.0), missile_cooldown),
		Vector2(maxf(_teleport_cooldown_left, 0.0), teleport_cooldown),
	]


## 카메라에서 마우스 위치로 광선을 쏴 바닥 평면(y = 0)과 만나는 점. 못 찾으면 null.
func get_mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, normal)


func _get_move_direction() -> Vector3:
	var dir := _get_wasd_direction()
	if dir != Vector3.ZERO:
		_has_target = false
		return dir
	if not _has_target:
		return Vector3.ZERO
	if Input.is_action_pressed("move") and not _ignore_held_move:
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() <= stop_distance:
		_has_target = false
		return Vector3.ZERO
	return to_target.normalized()


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


## 커서 방향(바닥 기준). 커서를 못 찾으면 지금 바라보는 방향.
func _get_aim_direction() -> Vector3:
	var point = get_mouse_ground_point()
	if point != null:
		var to: Vector3 = point - global_position
		to.y = 0.0
		if to.length() > 0.05:
			return to.normalized()
	return -global_basis.z


## 공격을 쏘는 순간: 이동을 멈추고 커서 쪽으로 몸을 돌린 뒤 잠깐 제자리에 선다.
func _begin_action(aim: Vector3) -> void:
	rotation.y = atan2(-aim.x, -aim.z)
	_has_target = false
	_ignore_held_move = true
	_action_lock_left = attack_lock_time


## 거리·각도 계산만으로 부채꼴 안의 적 전부에게 피해 + 넉백.
func _melee_attack() -> void:
	_melee_cooldown_left = melee_cooldown
	var aim := _get_aim_direction()
	_begin_action(aim)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0.0
		# 사거리는 적 몸 가장자리까지 잰다(덩치처럼 큰 적도 붙으면 맞게).
		if to.length() - enemy.body_radius > melee_range:
			continue
		if to.length() < 0.01 or rad_to_deg(aim.angle_to(to)) <= melee_angle * 0.5:
			enemy.take_damage(melee_damage, global_position, melee_knockback)
	_show_slash()


func _cast_missile() -> void:
	if missile_scene == null:
		return
	_missile_cooldown_left = missile_cooldown
	var aim := _get_aim_direction()
	_begin_action(aim)
	var missile := missile_scene.instantiate()
	missile.direction = aim
	_get_projectile_parent().add_child(missile)
	missile.global_position = global_position + aim * missile_forward_offset + Vector3.UP * missile_height
	missile.reset_physics_interpolation()


## 커서 방향 최대 teleport_distance 지점(커서가 더 가까우면 커서 지점)으로 순간이동.
## 도착점이 나무·벽과 겹치거나 맵 밖이면 발동하지 않고 쿨다운도 쓰지 않는다.
func _try_teleport() -> void:
	if _teleport_cooldown_left > 0.0:
		return
	var point = get_mouse_ground_point()
	if point == null:
		return
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		return
	offset = offset.limit_length(teleport_distance)
	var dest := global_position + offset
	if not _is_free_spot(dest):
		return

	var from := global_position
	_teleport_cooldown_left = teleport_cooldown
	_has_target = false
	_ignore_held_move = true
	global_position = dest
	rotation.y = atan2(-offset.x, -offset.z)
	reset_physics_interpolation()
	_invuln_left = maxf(_invuln_left, teleport_invuln_time)
	_teleport_from_tween = _flash_effect(_teleport_from_fx, _teleport_from_tween, from + Vector3(0.0, 0.04, 0.0), 0.0, teleport_effect_time)
	_teleport_to_tween = _flash_effect(_teleport_to_fx, _teleport_to_tween, dest + Vector3(0.0, 0.04, 0.0), 0.0, teleport_effect_time)


## 플레이어 몸(캡슐)을 그 자리에 놓아 보고 나무·벽과 겹치는지 검사한다.
func _is_free_spot(dest: Vector3) -> bool:
	var limit := map_half_size - 0.5 - _radius
	if absf(dest.x) > limit or absf(dest.z) > limit:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape_node.shape
	# 바닥과 닿아서 겹침으로 잡히지 않게 살짝 띄운다.
	query.transform = Transform3D(Basis(), dest + _shape_node.position + Vector3(0.0, 0.05, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _get_projectile_parent() -> Node:
	var scene := get_tree().current_scene
	var container := scene.get_node_or_null("Projectiles")
	return container if container else scene


## 첫 발사 때 셰이더 컴파일로 멈추지 않게 미사일과 맞는 효과를 땅 밑에서 한 번 그린다.
func _prewarm_missile() -> void:
	if missile_scene == null:
		return
	var missile := missile_scene.instantiate()
	missile.prewarm = true
	_get_projectile_parent().add_child(missile)
	missile.global_position = Vector3(0.0, -3.0, 0.0)


func _update_blink(delta: float) -> void:
	if _blink_left <= 0.0:
		return
	_blink_left -= delta
	var on := _blink_left <= 0.0 or fmod(_blink_left, blink_interval * 2.0) < blink_interval
	_body.visible = on
	_nose.visible = on


func _die() -> void:
	is_dead = true
	_has_target = false
	velocity = Vector3.ZERO
	_body.visible = true
	_nose.visible = true
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.32, 0.32, 0.34)
	_body.material_override = gray
	_nose.material_override = gray
	died.emit()
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(self, "rotation:z", deg_to_rad(90.0), 0.4)
	tween.tween_property(self, "position:y", _radius, 0.4)


func _make_click_marker() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.22
	mesh.outer_radius = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.95, 1.0)
	mesh.material = mat
	return _make_effect(mesh)


## 근접 공격 부채꼴. 메시는 한 번만 만들고 매번 재사용한다.
func _make_slash() -> MeshInstance3D:
	var segments := 16
	var half := deg_to_rad(melee_angle * 0.5)
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := -half + 2.0 * half * i / segments
		var a1 := -half + 2.0 * half * (i + 1) / segments
		verts.append(Vector3.ZERO)
		verts.append(Vector3(-sin(a1), 0.0, -cos(a1)) * melee_range)
		verts.append(Vector3(-sin(a0), 0.0, -cos(a0)) * melee_range)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.75, 0.9, 1.0, 0.55)
	mesh.surface_set_material(0, mat)
	return _make_effect(mesh)


## 순간이동 출발점·도착점에 뜨는 파란 원. 두 효과가 같은 메시를 쓴다.
func _make_teleport_ring() -> Mesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.45
	mesh.outer_radius = 0.65
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.55, 1.0)
	mesh.material = mat
	return mesh


func _make_effect(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.top_level = true
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	return node


## 처음 그릴 때의 셰이더 컴파일 멈춤을 없애려고, 시작할 때 땅 밑에 한 번 그려 둔다.
func _prewarm(effects: Array) -> void:
	for effect: MeshInstance3D in effects:
		effect.global_position = Vector3(0.0, -2.0, 0.0)
		effect.transparency = 0.5
		effect.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for effect: MeshInstance3D in effects:
		effect.visible = false


func _show_click_marker(point: Vector3) -> void:
	_marker_tween = _flash_effect(_marker, _marker_tween, point + Vector3(0.0, 0.03, 0.0), 0.0, click_marker_time)


func _show_slash() -> void:
	_slash_tween = _flash_effect(_slash, _slash_tween, global_position + Vector3(0.0, 0.05, 0.0), rotation.y, slash_time)


## 이펙트를 그 자리에 보여 주고 transparency로 서서히 지운다.
func _flash_effect(effect: MeshInstance3D, tween: Tween, pos: Vector3, yaw: float, duration: float) -> Tween:
	if tween:
		tween.kill()
	effect.global_position = pos
	effect.rotation = Vector3(0.0, yaw, 0.0)
	effect.reset_physics_interpolation()
	effect.transparency = 0.0
	effect.visible = true
	tween = create_tween()
	tween.tween_property(effect, "transparency", 1.0, duration)
	tween.tween_callback(effect.hide)
	return tween
