## Autoload: persists run state across Menu → Map → Combat → Reward.
## No character specialties — only shared stats and deck composition.
extends Node

signal run_started
signal run_ended(won: bool)

const HAND_LIMIT_BASE := 5
const START_HP := 4
const START_MAX_HP := 4

## Map nodes: 0..n-2 normal fights, last is boss
var map_nodes: Array[Dictionary] = []
var current_node_index: int = 0
var run_active: bool = false

## Shared combatant stats (player only persists between fights)
var player_max_hp: int = START_MAX_HP
var player_hp: int = START_HP
## Bonus cards drawn at start of each combat
var extra_draw_at_start: int = 0
## Deck as array of CardData resource paths (or CardData instances rebuilt each fight)
var deck_card_ids: Array[String] = []

var last_combat_won: bool = false
var last_message: String = ""

func _ready() -> void:
	_reset_deck_to_basic()

func start_new_run() -> void:
	player_max_hp = START_MAX_HP
	player_hp = START_HP
	extra_draw_at_start = 0
	_reset_deck_to_basic()
	current_node_index = 0
	run_active = true
	last_combat_won = false
	last_message = ""
	_build_map(4)  # 3 normal + 1 boss
	run_started.emit()

func _reset_deck_to_basic() -> void:
	## Basic generation deck — same pool for everyone, no specialties
	deck_card_ids = [
		"sha", "sha", "sha", "sha", "sha", "sha",
		"shan", "shan", "shan", "shan",
		"tao", "tao",
		"guohe", "wuzhong",
	]

func _build_map(total: int) -> void:
	map_nodes.clear()
	for i in range(total):
		var is_boss := i == total - 1
		map_nodes.append({
			"id": i,
			"label": "Boss" if is_boss else "Fight %d" % (i + 1),
			"is_boss": is_boss,
			"enemy_name": "董卓" if is_boss else ["山贼", "伏兵", "黄巾"][i % 3],
			"enemy_max_hp": 6 if is_boss else (3 + i),
			"enemy_deck_size": 14 if is_boss else (10 + i),
			"cleared": false,
		})

func get_current_node() -> Dictionary:
	if current_node_index < 0 or current_node_index >= map_nodes.size():
		return {}
	return map_nodes[current_node_index]

func mark_current_cleared() -> void:
	if current_node_index >= 0 and current_node_index < map_nodes.size():
		map_nodes[current_node_index]["cleared"] = true

func advance_after_reward() -> String:
	## Returns next scene path hint: "map", "win"
	mark_current_cleared()
	current_node_index += 1
	if current_node_index >= map_nodes.size():
		run_active = false
		run_ended.emit(true)
		return "win"
	return "map"

func lose_run() -> void:
	run_active = false
	run_ended.emit(false)

func add_card_to_deck(card_id: String) -> void:
	deck_card_ids.append(card_id)

func bump_max_hp(amount: int = 1) -> void:
	player_max_hp += amount
	player_hp = mini(player_hp + amount, player_max_hp)

func heal_between_fights(amount: int = 1) -> void:
	player_hp = mini(player_hp + amount, player_max_hp)

func add_extra_draw(amount: int = 1) -> void:
	extra_draw_at_start += amount

## Load CardData by id from resources/cards/
func load_card(card_id: String) -> CardData:
	var path := "res://resources/cards/%s.tres" % card_id
	var res := load(path)
	if res is CardData:
		return res
	push_error("Missing card resource: %s" % path)
	return null

func build_deck_from_ids(ids: Array) -> Array[CardData]:
	var deck: Array[CardData] = []
	for cid in ids:
		var c := load_card(str(cid))
		if c:
			deck.append(c)
	return deck

func make_enemy_deck(size: int) -> Array[CardData]:
	## Same basic generation rules as player — weighted random from basic pool
	var pool := ["sha", "sha", "sha", "shan", "shan", "tao", "guohe", "wuzhong"]
	var ids: Array[String] = []
	for i in range(size):
		ids.append(pool[randi() % pool.size()])
	return build_deck_from_ids(ids)
