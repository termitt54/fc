extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Coaching := preload("res://game/match_coaching.gd")
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1; print("FAIL: ",label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=1788
	var squad := Fixtures.squad(1,65,rng,0)
	for mentality in ["attacking","defensive"]:
		var coach := {"style":mentality,"attributes":{"professionalism":20,"tactics":20}}
		var lineup := Coaching.select_lineup({"squad":squad,"coach":coach},{},rng)
		check(lineup.formation=="3-2-2" and lineup.style==mentality,"fixed shape preserves team mentality")
		check(lineup.plan_source=="fixed","no alternative tactical plans")
		check(lineup.starters.size()==8 and lineup.bench.size()==12,"twenty players available, eight start")
		check(lineup.starters.map(func(row):return row.slot)==["GK","CB","CB","CB","CM","CM","ST","ST"],"one keeper and seven field roles")
		for minute in [5,25,40,50,60]:
			check(Coaching.review({"style":mentality,"goals":0},{"goals":3},minute).is_empty(),"score cannot switch shape or invent tactical styles")
		check(Coaching.profile(mentality,"normal",false)==Coaching.profile(mentality,"chase",true),"old tactical modes do not modify the chosen mentality")
	var default_plan := Coaching.select_lineup({"squad":squad},{},rng)
	check(default_plan.style=="attacking" and default_plan.formation=="3-2-2","missing coach has deterministic fixed shape")
	print("=== Match coaching: ",passed," passed, ",failed," failed ===")
	get_tree().quit(1 if failed else 0)
