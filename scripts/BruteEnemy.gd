extends Enemy
## 덩치. 느리게 쫓아오다 attack_range 안에 들면 바닥에 경고 원을 깔고, 예비 동작이 끝나면 slam_radius 안을 내려찍는다.
## 넉백을 받지 않는다. 경고 원 밖에 있으면 맞지 않는다.

@export var slam_radius := 2.5
@export var warning_color := Color(1.0, 0.15, 0.1, 0.25)
@export var fill_color := Color(1.0, 0.15, 0.1, 0.55)

var _slam_center := Vector3.ZERO
var _warning: MeshInstance3D
var _fill: MeshInstance3D

static var _disc_mesh: CylinderMesh
static var _materials := {}
static var _warning_prewarmed := false


func _ready() -> void:
	super()
	_warning = _make_disc(warning_color, 0.02)
	_fill = _make_disc(fill_color, 0.03)
	if not _warning_prewarmed:
		_warning_prewarmed = true
		_prewarm_discs()


func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.WINDUP:
		# 안쪽 원이 예비 동작 동안 0에서 반경 전체로 차오른다.
		var r := slam_radius * clampf(1.0 - _state_time / windup_time, 0.02, 1.0)
		_fill.scale = Vector3(r, 1.0, r)


func _on_enter_state(new_state: State) -> void:
	if _warning == null:
		return
	if new_state == State.WINDUP:
		_slam_center = Vector3(global_position.x, 0.0, global_position.z)
		_place_disc(_warning, slam_radius, 0.02)
		_place_disc(_fill, 0.05, 0.03)
		_warning.visible = true
		_fill.visible = true
	else:
		_warning.visible = false
		_fill.visible = false


func _perform_attack() -> void:
	if not _player_alive():
		return
	var to := player.global_position - _slam_center
	to.y = 0.0
	if to.length() <= slam_radius:
		player.take_damage(attack_damage, _slam_center)


func _place_disc(disc: MeshInstance3D, radius: float, height: float) -> void:
	disc.global_position = _slam_center + Vector3(0.0, height, 0.0)
	disc.scale = Vector3(radius, 1.0, radius)
	disc.reset_physics_interpolation()


## 반지름 1짜리 납작한 원판을 scale로 키운다. 메시와 색별 머티리얼은 모든 덩치가 같이 쓴다.
func _make_disc(color: Color, height: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	disc.mesh = _get_disc_mesh()
	disc.material_override = _get_disc_material(color)
	disc.top_level = true
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = false
	add_child(disc)
	disc.global_position = Vector3(0.0, height, 0.0)
	return disc


func _prewarm_discs() -> void:
	for disc in [_warning, _fill]:
		disc.global_position = Vector3(0.0, -3.0, 0.0)
		disc.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if state != State.WINDUP:
		_warning.visible = false
		_fill.visible = false


static func _get_disc_mesh() -> CylinderMesh:
	if _disc_mesh == null:
		_disc_mesh = CylinderMesh.new()
		_disc_mesh.top_radius = 1.0
		_disc_mesh.bottom_radius = 1.0
		_disc_mesh.height = 0.01
		_disc_mesh.radial_segments = 40
		_disc_mesh.rings = 1
	return _disc_mesh


static func _get_disc_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]
