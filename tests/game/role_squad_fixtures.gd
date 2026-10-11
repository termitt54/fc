extends RefCounted
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Ratings := preload("res://game/match_ratings.gd")

static func preparation_squad() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 58001
	var source := Fixtures.squad(1, 65, rng, 0)
	var midfield: Array = []
	for i in 12:
		var player: Dictionary = source[7].duplicate(true)
		player["id"] = 3000 + i
		player["position"] = "GK" if i < 2 else ("CB" if i < 4 else ("WM" if i < 8 else "CM"))
		for group in player["attributes"]:
			for key in player["attributes"][group]:
				player["attributes"][group][key] = 15
		player["attributes"]["technical"]["finishing"] = 1
		player["attributes"]["technical"]["dribbling"] = 1
		player["attributes"]["mental"]["off_the_ball"] = 1
		player.erase("_match_ratings")
		midfield.append(player)
	return midfield

## Actual grouped attributes, not mocked match ratings.
static func specialised_squad() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 87021
	var squad := Fixtures.squad(1, 65, rng, 0)
	for player in squad:
		player["condition"] = 100
		player["morale"] = 50
	# CM indexes 7..10. Two contrasting specialists plus ordinary cover.
	for index in [7, 8]:
		var attrs: Dictionary = squad[index]["attributes"]
		for group in attrs:
			for key in attrs[group]:
				attrs[group][key] = 10
	var maker: Dictionary = squad[7]["attributes"]
	for key in ["passing", "technique", "first_touch"]:
		maker["technical"][key] = 18
	for key in ["vision", "decisions", "composure"]:
		maker["mental"][key] = 18
	maker["mental"]["work_rate"] = 1
	maker["physical"]["stamina"] = 1
	maker["physical"]["pace"] = 1
	var winner: Dictionary = squad[8]["attributes"]
	for key in ["tackling", "marking"]:
		winner["technical"][key] = 18
	for key in ["work_rate", "anticipation", "concentration"]:
		winner["mental"][key] = 20
	for key in ["stamina", "pace", "acceleration"]:
		winner["physical"][key] = 20
	for player in squad:
		Ratings.invalidate(player)
	# Two alternatives per CM slot in the shared, legal 2-4-1 formation.
	for index in [9, 10]:
		var id: int = squad[index]["id"]
		squad[index] = squad[index - 2].duplicate(true)
		squad[index]["id"] = id
	# Wide runners keep the experiment focused on the CM choice.
	for index in [11, 12]:
		for group in squad[index]["attributes"]:
			for key in squad[index]["attributes"][group]:
				squad[index]["attributes"][group][key] = 12
		for key in ["stamina", "pace", "acceleration", "agility", "balance"]:
			squad[index]["attributes"]["physical"][key] = 20
		squad[index]["attributes"]["technical"]["dribbling"] = 20
		squad[index]["attributes"]["mental"]["work_rate"] = 20
	# Cover both starting wide midfielders and exceed the matchday limit.
	for index in 7:
		var extra: Dictionary = squad[11 if index < 2 else 15].duplicate(true)
		extra["id"] = 2001 + index
		if index < 2:
			for group in extra["attributes"]:
				for key in extra["attributes"][group]:
					extra["attributes"][group][key] = 8
		squad.append(extra)
	# Deliberately weak keeper plus many strong attackers used to squeeze him out.
	for group in squad[1]["attributes"]:
		for key in squad[1]["attributes"][group]:
			squad[1]["attributes"][group][key] = 1
	return squad


