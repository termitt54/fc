extends RefCounted
## Deterministic squads and coaches for match tests: no world database needed.

const PlayerGeneratorScript := preload("res://game/player_generator.gd")
const CoachGeneratorScript := preload("res://game/coach_generator.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")

## Two keepers plus cover for every outfield slot of an 8v8 formation.
const POSITIONS := [
	"GK", "GK",
	"CB", "CB", "CB",
	"FB", "FB",
	"CM", "CM", "CM", "CM",
	"WM", "WM",
	"WF", "WF",
	"ST", "ST", "ST",
]


static func squad(
	club_id: int,
	target_ca: int,
	rng: RandomNumberGenerator,
	spread: int = 8
) -> Array:
	var club := {
		"id": club_id,
		"country_id": club_id,
		"reputation": 500,
		"name": "Club %d" % club_id,
	}
	var id_state := {"next_id": club_id * 1000 + 1}
	var used_names: Dictionary = {}
	var cache: Dictionary = {}
	var players: Array = []
	for position in POSITIONS:
		var ca := clampi(target_ca + rng.randi_range(-spread, spread), 20, 95)
		players.append(PlayerGeneratorScript.create_player(
			club_id,
			club,
			rng,
			cache,
			used_names,
			id_state,
			{
				"position": position,
				"current_ability": ca,
				"potential_ability": mini(ca + 10, 99),
				"age": rng.randi_range(19, 32),
			}
		))
	for player in players:
		PlayerConditionScript.ensure_state(player)
	return players


static func coach(club_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var generated: Dictionary = CoachGeneratorScript.generate_for_clubs(
		{club_id: {"id": club_id, "country_id": club_id, "reputation": 500}},
		rng,
		{},
		{"next_id": club_id * 10 + 1},
		1
	)
	return generated.get(club_id, {})
