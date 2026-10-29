extends Enemy
## 근거리 졸개. 플레이어에게 곧장 달려들고, 예비 동작이 끝날 때 miss_range 안이면 때린다.


func _perform_attack() -> void:
	if _player_alive() and _distance_to_player() <= miss_range:
		player.take_damage(attack_damage, global_position)
