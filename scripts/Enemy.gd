class_name Enemy
extends CharacterBody3D
## 적 3종 공통: 체력, 상태 머신(추적 → 예비 동작 → 공격 → 대기, 사망), 피격 깜빡임, 넉백, 사망 연출.
## 종류별 차이는 _can_start_attack(), _get_chase_velocity(), _perform_attack(), _on_enter_state()를 덮어써서 만든다.

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

@export_group("체력 바")
@export var health_bar_height := 1.8
@export var health_bar_width := 1.0

var health := 0.0
var state := State.CHASE
var player: Node3D
## 몸(캡슐) 반지름. 플레이어 근접 판정이 쓴다.
var body_radius := 0.0

var _state_time := 0.0
var _cooldown := 0.0
var _flash_left := 0.0
var _knock_velocity := Vector3.ZERO
var _knock_left := 0.0
var _bar_back: Sprite3D
var _bar_fill: Sprite3D

@onready var _body: MeshInstance3D = $Body

static var _white_material: StandardMaterial3D
static var _windup_materials := {}
static var _bar_texture: ImageTexture
static var _bar_prewarmed := false

const BAR_PIXELS := 64


func _ready() -> void:
	health = max_health
	body_radius = ($CollisionShape3D.shape as CapsuleShape3D).radius
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as Node3D
	_make_health_bar()


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
				if _cooldown <= 0.0 and _can_start_attack(dist):
					_enter(State.WINDUP)
				else:
					velocity = _get_chase_velocity(dist, delta)
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
	_update_health_bar()
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


## 상태가 바뀔 때 종류별 연출(덩치의 경고 원 등)을 붙이는 곳.
func _on_enter_state(_new_state: State) -> void:
	pass


## 쿨다운이 끝났을 때 예비 동작을 시작해도 되는 거리인지.
func _can_start_attack(dist: float) -> bool:
	return dist <= attack_range


## 기본은 공격 거리 안이면 제자리에서 플레이어를 보고, 밖이면 곧장 걸어간다.
func _get_chase_velocity(dist: float, delta: float) -> Vector3:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if dist <= attack_range:
		_face(to_player, delta)
		return Vector3.ZERO
	return _walk(to_player.normalized(), delta)


## 그 방향으로 걷되 나무에 정면으로 막히면 옆으로 비켜간다.
func _walk(dir: Vector3, delta: float) -> Vector3:
	dir = _avoid_obstacle(dir, delta)
	_face(dir, delta)
	return dir * move_speed


func _get_projectile_parent() -> Node:
	var scene := get_tree().current_scene
	var container := scene.get_node_or_null("Projectiles")
	return container if container else scene


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
	_on_enter_state(new_state)
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
	_bar_back.visible = false
	_bar_fill.visible = false
	died.emit(self)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, death_time)
	tween.tween_callback(queue_free)


## 머리 위 체력 바: 빌보드 Sprite3D 두 장(배경, 채움)이 흰 텍스처 하나를 같이 쓴다. 첫 피해 뒤부터 보인다.
func _make_health_bar() -> void:
	_bar_back = _make_bar_sprite(Color(0.08, 0.08, 0.08, 0.85), 0)
	_bar_fill = _make_bar_sprite(Color(0.95, 0.25, 0.2), 1)
	_bar_fill.region_enabled = true
	_update_health_bar()
	_bar_back.visible = false
	_bar_fill.visible = false
	# 처음 그릴 때의 멈춤을 없애려고 첫 적 하나만 땅 밑에서 두 프레임 그려 둔다.
	if not _bar_prewarmed:
		_bar_prewarmed = true
		_prewarm_health_bar()


func _make_bar_sprite(color: Color, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _get_bar_texture()
	sprite.pixel_size = health_bar_width / BAR_PIXELS
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = priority
	sprite.modulate = color
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = Vector3(0.0, health_bar_height, 0.0)
	add_child(sprite)
	return sprite


func _update_health_bar() -> void:
	var ratio := clampf(health / max_health, 0.0, 1.0)
	var w := BAR_PIXELS * ratio
	_bar_fill.region_rect = Rect2(0, 0, w, _get_bar_texture().get_height())
	# 가운데 정렬이라 줄어든 만큼 왼쪽으로 밀어 왼쪽 끝을 맞춘다.
	_bar_fill.offset = Vector2(-(BAR_PIXELS - w) * 0.5, 0.0)
	var show := health < max_health and health > 0.0
	_bar_back.visible = show
	_bar_fill.visible = show


func _prewarm_health_bar() -> void:
	for sprite in [_bar_back, _bar_fill]:
		sprite.position.y = -3.0
		sprite.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for sprite in [_bar_back, _bar_fill]:
		sprite.position.y = health_bar_height
	_update_health_bar()


static func _get_bar_texture() -> ImageTexture:
	if _bar_texture == null:
		var image := Image.create(BAR_PIXELS, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_bar_texture = ImageTexture.create_from_image(image)
	return _bar_texture


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
