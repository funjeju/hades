extends Node
## 웨이브 구성표대로 스폰 지점에서 적을 하나씩 내보낸다. 전멸하면 쉬었다가 다음 웨이브, 마지막 웨이브를 넘기면 승리 신호.
## 처치 수(kills)와 경과 시간(elapsed)은 결과 화면이 읽는다.

signal wave_started(wave_number: int, total_waves: int)
signal remaining_changed(remaining: int)
signal all_waves_cleared

enum Phase { WAITING, SPAWNING, FIGHTING, DONE }

## 웨이브마다 (근거리, 원거리, 덩치) 마릿수.
@export var waves: Array[Vector3i] = [Vector3i(6, 0, 0), Vector3i(6, 3, 0), Vector3i(6, 4, 2)]
@export var melee_scene: PackedScene
@export var ranged_scene: PackedScene
@export var brute_scene: PackedScene
@export var player: Node3D
@export var spawn_points: Node3D
@export var enemy_parent: Node3D
@export var first_wave_delay := 1.0
@export var spawn_interval := 0.5
@export var rest_time := 3.0
## 플레이어와 이보다 가까운 스폰 지점은 쓰지 않는다.
@export var min_spawn_distance := 10.0

var kills := 0
var elapsed := 0.0
## 1부터 센다. 0이면 아직 시작 전.
var current_wave := 0
var phase := Phase.WAITING

var _queue: Array[PackedScene] = []
var _alive := 0
var _timer := 0.0


func _ready() -> void:
	_timer = first_wave_delay


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	if player and player.get("is_dead"):
		# 쓰러지면 시간도 스폰도 멈춘다.
		phase = Phase.DONE
		return
	elapsed += delta
	_timer -= delta
	match phase:
		Phase.WAITING:
			if _timer <= 0.0:
				_start_wave()
		Phase.SPAWNING:
			if _timer <= 0.0:
				_spawn(_queue.pop_front())
				_timer = spawn_interval
				if _queue.is_empty():
					phase = Phase.FIGHTING


func get_remaining() -> int:
	return _alive + _queue.size()


func _start_wave() -> void:
	current_wave += 1
	var counts := waves[current_wave - 1]
	_queue.clear()
	for i in counts.x:
		_queue.append(melee_scene)
	for i in counts.y:
		_queue.append(ranged_scene)
	for i in counts.z:
		_queue.append(brute_scene)
	# 종류를 섞어서 내보낸다.
	_queue.shuffle()
	phase = Phase.SPAWNING
	_timer = 0.0
	wave_started.emit(current_wave, waves.size())
	remaining_changed.emit(get_remaining())


func _spawn(scene: PackedScene) -> void:
	var enemy: Node3D = scene.instantiate()
	enemy_parent.add_child(enemy)
	enemy.global_position = _pick_spawn_position()
	enemy.reset_physics_interpolation()
	enemy.died.connect(_on_enemy_died)
	_alive += 1


## 플레이어와 min_spawn_distance 이상 떨어진 스폰 지점 중 무작위. 하나도 없으면 가장 먼 곳.
func _pick_spawn_position() -> Vector3:
	var far: Array[Vector3] = []
	var farthest := Vector3.ZERO
	var best := -1.0
	for marker: Node3D in spawn_points.get_children():
		var d := marker.global_position.distance_to(player.global_position)
		if d >= min_spawn_distance:
			far.append(marker.global_position)
		if d > best:
			best = d
			farthest = marker.global_position
	return far.pick_random() if not far.is_empty() else farthest


func _on_enemy_died(_enemy: Node) -> void:
	kills += 1
	_alive -= 1
	remaining_changed.emit(get_remaining())
	if get_remaining() > 0 or phase != Phase.FIGHTING:
		return
	if current_wave >= waves.size():
		phase = Phase.DONE
		all_waves_cleared.emit()
	else:
		phase = Phase.WAITING
		_timer = rest_time
