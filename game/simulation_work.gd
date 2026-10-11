extends RefCounted
## Cooperative main-thread work: never moves mutable session/SQLite to a worker.
var owner: Node
var budget_usec: int
var slice_started: int
var yields := 0
var max_slice_usec := 0
var max_slice_stage := ""

func _init(session: Node, budget_ms: int = 8) -> void:
	owner = session
	budget_usec = clampi(budget_ms, 1, 50) * 1000
	slice_started = Time.get_ticks_usec()

func checkpoint(stage: String, done: int = 0, total: int = 0, force: bool = false) -> void:
	var elapsed := Time.get_ticks_usec() - slice_started
	if not force and elapsed < budget_usec:
		return
	if elapsed > max_slice_usec:
		max_slice_usec = elapsed
		max_slice_stage = stage
	yields += 1
	owner.simulation_progress.emit(stage, done, total)
	await owner.get_tree().process_frame
	slice_started = Time.get_ticks_usec()

func finish() -> Dictionary:
	max_slice_usec = maxi(max_slice_usec, Time.get_ticks_usec() - slice_started)
	return {"yields": yields, "max_slice_ms": float(max_slice_usec) / 1000.0,
		"budget_ms": float(budget_usec) / 1000.0, "max_slice_stage": max_slice_stage}
