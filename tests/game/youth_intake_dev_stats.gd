extends Node
## Headless balancer for youth generation. Not part of the player UI.
## Run: godot --headless --path . res://tests/game/youth_intake_dev_stats.tscn

const YouthIntakeScript := preload("res://game/youth_intake.gd")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

const INTAKES := 1000
const SLOTS_PER_CLUB := 6


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	YouthGenerationConfigScript.reset_to_defaults(false)
	var clubs: Array = []
	var countries: Dictionary = {
		1: {"id": 1, "name": "Strong", "youth_talent": 90},
		2: {"id": 2, "name": "Mid", "youth_talent": 50},
		3: {"id": 3, "name": "Weak", "youth_talent": 20},
	}
	var club_id := 1
	for country_id in [1, 2, 3]:
		for i in 4:
			clubs.append({
				"id": club_id,
				"country_id": country_id,
				"name": "C%d-%d" % [country_id, i],
				"reputation": 400 + i * 150,
				"youth_academy": 8 + i * 3,
				"training_level": 10,
				"scouting_level": 10,
				"youth_search": 6 + i * 4,
			})
			club_id += 1

	var all_rows: Array = []
	var country_strong := {1: 0, 2: 0, 3: 0}
	var club_strong: Dictionary = {}
	for n in INTAKES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 50000 + n
		var rows: Array = YouthIntakeScript.plan_intake(
			clubs,
			countries,
			rng,
			{"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": SLOTS_PER_CLUB}
		)
		all_rows.append_array(rows)
		for row in rows:
			if int(row.get("potential_ability", 0)) < 85:
				continue
			var cid := int(row.get("country_id", 0))
			country_strong[cid] = int(country_strong.get(cid, 0)) + 1
			var club := int(row.get("club_id", 0))
			club_strong[club] = int(club_strong.get(club, 0)) + 1

	var stats: Dictionary = YouthIntakeScript.collect_stats(all_rows)
	print("=== Youth intake balancer (%d intakes) ===" % INTAKES)
	print("players: %d" % int(stats.get("count", 0)))
	print("mean PA: %.3f" % float(stats.get("mean_pa", 0.0)))
	print("median PA: %.3f" % float(stats.get("median_pa", 0.0)))
	print("PA 80+: %d" % int(stats.get("pa_80", 0)))
	print("PA 85+: %d" % int(stats.get("pa_85", 0)))
	print("PA 90+: %d" % int(stats.get("pa_90", 0)))
	print("PA 95+: %d" % int(stats.get("pa_95", 0)))
	print("distribution: %s" % str(stats.get("distribution", {})))
	print("PA 85+ by country: Strong=%d Mid=%d Weak=%d" % [
		int(country_strong.get(1, 0)),
		int(country_strong.get(2, 0)),
		int(country_strong.get(3, 0)),
	])
	print("PA 85+ by club: %s" % str(club_strong))
	get_tree().quit(0)
