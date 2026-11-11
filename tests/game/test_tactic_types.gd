extends Node
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1; print("FAIL: ",label)
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=422
	check(TacticTypes.FORMATIONS==["3-2-2"],"only fixed shape exists")
	check(TacticTypes.STYLES==["attacking","defensive"],"only two team mentalities")
	for old in ["control","pressing","tiki_taka","vertical","park_bus","counter","kick_rush","balanced"]:
		var coach := {"id":11,"style":old,"primary_style":old,"backup_style":"control","primary_formation":"2-4-1","backup_formation":"3-3-1"}
		var before := rng.state
		TacticTypes.ensure_coach_tactics(coach)
		check(TacticTypes.is_style(coach.style),"old mentality migrated")
		check(not coach.has("primary_style") and not coach.has("backup_formation"),"old choices removed")
		check(rng.state==before,"migration consumes no random draw")
		var snapshot: Dictionary=coach.duplicate(true)
		TacticTypes.ensure_coach_tactics(coach)
		check(snapshot==coach,"migration idempotent")
		var plan := TacticTypes.pick_match_plan(coach,rng)
		check(plan.formation=="3-2-2" and plan.style==coach.style,"fixed plan")
		check(rng.state==before,"fixed plan consumes no random draw")
	for i in 500:
		var identity := TacticTypes.roll_coach_identity(rng)
		check(identity.size()==1 and identity.style in ["attacking","defensive"],"new coaches have only a playing mentality")
	print("=== Fixed shape: ",passed," passed, ",failed," failed ===")
	get_tree().quit(1 if failed else 0)
