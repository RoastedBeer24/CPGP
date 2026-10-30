class_name RewardPool
extends Resource
## 보상 후보 전체. 방을 깰 때마다 플레이어마다 세 개를 골라 보여 준다.

@export var rewards: Array[RewardData] = []


func find(reward_id: StringName) -> RewardData:
	for reward in rewards:
		if reward.id == reward_id:
			return reward
	return null


## 시드로 서로 다른 보상 count개를 고른다. 같은 시드면 어느 피어에서 골라도 같다.
func offer(seed_value: int, count: int) -> Array[RewardData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var picked: Array[RewardData] = []
	var pool := rewards.duplicate()
	while picked.size() < count and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index] as RewardData)
		pool.remove_at(index)
	return picked
