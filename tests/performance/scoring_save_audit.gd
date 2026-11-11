extends Node
const Config := preload("res://game/match_simulation_config.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var reports: Array = []
	for variant in fixture.variants:
		Config.apply_values(variant.knobs,false)
		var engine: Variant = load(variant.engine)
		var row := {"label":variant.label,"matches":0,"goals":0,"six_margin":0,"eight_plus":0,"clubs":{}}
		for i in fixture.matches.size():
			var match_row: Dictionary = fixture.matches[i]
			var rng := RandomNumberGenerator.new()
			rng.seed = 438100+i
			var result: Dictionary = engine.simulate({"home":fixture.teams[str(int(match_row.home_id))],"away":fixture.teams[str(int(match_row.away_id))],"neutral":false,"allow_draw":true,"discipline":{"enabled":false}},rng)
			var h := int(result.home_goals)
			var a := int(result.away_goals)
			row.matches += 1
			row.goals += h+a
			row.six_margin += int(absi(h-a)>=6)
			row.eight_plus += int(maxi(h,a)>=8)
			for side in ["home","away"]:
				var cid := str(int(match_row[side+"_id"]))
				var gf := h if side=="home" else a
				var ga := a if side=="home" else h
				if not row.clubs.has(cid):
					row.clubs[cid] = {"name":fixture.teams[cid].name,"wins":0,"draws":0,"losses":0,"gf":0,"ga":0}
				row.clubs[cid]["wins" if gf>ga else "losses" if gf<ga else "draws"] += 1
				row.clubs[cid].gf += gf
				row.clubs[cid].ga += ga
		row["goals_per_match"] = float(row.goals)/row.matches
		reports.append(row)
		print("SCORING AUDIT ",row.label," goals=",row.goals_per_match," six=",row.six_margin," eight=",row.eight_plus," CSKA=",row.clubs["33"])
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
	get_tree().quit()
