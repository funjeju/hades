extends "res://scripts/MeleeEnemy.gd"
## 털 거미 졸개. 싸우는 방식은 근거리 졸개와 같고, 빠르고 약하다.
## 블렌더에서 만든 모델(spider.glb)에 셸 털을 입히고, 움직일 때는 Walk, 서 있을 때는 Idle을 튼다.

const FUR_SHADER := preload("res://assets/characters/spider/spider_fur.gdshader")
## 털 껍질 장수. 많을수록 촘촘하지만 그만큼 더 그린다.
const FUR_SHELLS := 10
## Walk 한 바퀴(1초)에 해당하는 이동 속도(m/s). 발이 미끄러져 보이면 조절한다.
const WALK_CYCLE_SPEED := 1.8
const ANIM_BLEND := 0.15

static var _fur_material: ShaderMaterial

@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _mesh: MeshInstance3D = $Model/SpiderGameRig/Skeleton3D/SpiderGame


func _ready() -> void:
	super()
	_mesh.set_surface_override_material(0, _get_fur_material())
	for anim_name in ["Idle", "Walk"]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")


func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.DEAD:
		_anim.pause()
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.1:
		if _anim.current_animation != "Walk":
			_anim.play("Walk", ANIM_BLEND)
		_anim.speed_scale = speed / WALK_CYCLE_SPEED
	else:
		if _anim.current_animation != "Idle":
			_anim.play("Idle", ANIM_BLEND)
		_anim.speed_scale = 1.0


## 몸 표면 + 털 껍질 FUR_SHELLS장을 next_pass로 이은 머티리얼. 모든 거미가 같이 쓴다.
static func _get_fur_material() -> ShaderMaterial:
	if _fur_material == null:
		_fur_material = ShaderMaterial.new()
		_fur_material.shader = FUR_SHADER
		_fur_material.set_shader_parameter("layer", 0.0)
		var last := _fur_material
		for i in range(1, FUR_SHELLS + 1):
			var shell := ShaderMaterial.new()
			shell.shader = FUR_SHADER
			shell.set_shader_parameter("layer", float(i) / FUR_SHELLS)
			last.next_pass = shell
			last = shell
	return _fur_material
