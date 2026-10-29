class_name Enemy
extends CharacterBody3D
## 적 3종 공통: 체력, 상태 머신(추적 → 예비 동작 → 공격 → 대기, 사망), 피격 깜빡임, 넉백, 사망 연출.
## 종류별 차이는 _perform_attack()와 _get_chase_velocity()를 덮어써서 만든다.

signal died(enemy: Enemy)

enum State { CHASE, WINDUP, RECOVER, DEAD }

@export var max_health := 30.0
@export var move_speed := 3.5
@export var turn_speed := 12.0
## 이 거리 안에 들어오면 예비 동작을 시작한다.
@export var attack_range := 1.2
## 예비 동작이 끝나는 순간 플레이어가 이보다 멀면 빗나간다.
@export var miss_range := 1.6
@export var attack_damage := 10.0
@export var windup_time := 0.3
## 공격과 공격 사이 간격.
@export var attack_interval := 1.0
## 공격 직후 제자리에 서 있는 시간(대기).
@export var recover_time := 0.2
@export var windup_color := Color(1.0, 0.85, 0.2)
@export var knockback_immune := false
@export var knockback_time := 0.15
@export var flash_time := 0.1
@export var death_time := 0.3
@export var head_on_threshold := 0.9

var health := 0.0
var state := State.CHASE
var player: Node3D

var _state_time := 0.0
var _cooldown := 0.0
var _flash_left := 0.0
var _knock_velocity := Vector3.ZERO
var _knock_left := 0.0

@onready var _body: MeshInstance3D = $Body

static var _white_material: StandardMaterial3D
static var _windup_materials := {}


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_cooldown -= delta
	_state_time -= delta
	_flash_left -= delta

	if _knock_left > 0.0:
		_knock_left -= delta
		velocity = _knock_velocity
	elif not _player_alive():
		velocity = Vector3.ZERO
		if state != State.CHASE:
			_enter(State.CHASE)
	else:
		velocity = Vector3.ZERO
		match state:
			State.CHASE:
				var dist := _distance_to_player()
				if dist <= attack_range:
					_face(player.global_position - global_position, delta)
					if _cooldown <= 0.0:
						_enter(State.WINDUP)
				else:
					velocity = _get_chase_velocity(delta)
			State.WINDUP:
				_face(player.global_position - global_position, delta)
				if _state_time <= 0.0:
					_perform_attack()
					_enter(State.RECOVER)
			State.RECOVER:
				if _state_time <= 0.0:
					_enter(State.CHASE)

	move_and_slide()
	global_position.y = 0.0
	_update_look()


## 공격하는 쪽이 호출한다. knockback은 밀려나는 거리(m).
func take_damage(amount: float, from_position: Vector3, knockback := 0.0) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash_left = flash_time
	if health <= 0.0:
		_die()
		return
	if knockback > 0.0 and not knockback_immune:
		var away := global_position - from_position
		away.y = 0.0
		if away.length() < 0.01:
			away = -global_basis.z
		_knock_velocity = away.normalized() * knockback / knockback_time
		_knock_left = knockback_time
		if state == State.WINDUP:
			_enter(State.CHASE)
	_update_look()


## 종류별로 덮어쓴다. 기본은 아무것도 안 한다.
func _perform_attack() -> void:
	pass


## 기본은 플레이어 쪽으로 곧장 걸어가고, 나무에 정면으로 막히면 옆으로 비켜간다.
func _get_chase_velocity(delta: float) -> Vector3:
	var dir := player.global_position - global_position
	dir.y = 0.0
	dir = _avoid_obstacle(dir.normalized(), delta)
	_face(dir, delta)
	return dir * move_speed


func _enter(new_state: State) -> void:
	state = new_state
	match new_state:
		State.WINDUP:
			_state_time = windup_time
			# 간격은 예비 동작 시작부터 잰다(공격과 공격 사이가 attack_interval).
			_cooldown = attack_interval
		State.RECOVER:
			_state_time = recover_time
		_:
			_state_time = 0.0
	_update_look()


func _distance_to_player() -> float:
	var to := player.global_position - global_position
	to.y = 0.0
	return to.length()


func _player_alive() -> bool:
	return is_instance_valid(player) and not player.get("is_dead")


func _face(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)


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


## 흰색 깜빡임 > 예비 동작 색 > 원래 색. 머티리얼은 공유해서 새로 만들지 않는다.
func _update_look() -> void:
	if _flash_left > 0.0:
		_body.material_override = _get_white_material()
	elif state == State.WINDUP:
		_body.material_override = _get_windup_material(windup_color)
	else:
		_body.material_override = null


func _die() -> void:
	_enter(State.DEAD)
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_body.material_override = _get_white_material()
	died.emit(self)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, death_time)
	tween.tween_callback(queue_free)


static func _get_white_material() -> StandardMaterial3D:
	if _white_material == null:
		_white_material = StandardMaterial3D.new()
		_white_material.albedo_color = Color.WHITE
		_white_material.emission_enabled = true
		_white_material.emission = Color.WHITE
	return _white_material


static func _get_windup_material(color: Color) -> StandardMaterial3D:
	if not _windup_materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color * 0.4
		_windup_materials[color] = mat
	return _windup_materials[color]
