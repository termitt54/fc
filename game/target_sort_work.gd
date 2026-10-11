extends RefCounted
## Worker owns only immutable numeric keys and index output, never session
## dictionaries, Nodes, players, RNG, or SQLite. The main thread joins it.
var _reputations := PackedInt64Array()
var _abilities := PackedInt64Array()
var _thread := Thread.new()
var _started := false
var _fallback: Array = []

func _init(players: Array) -> void:
	for player in players:
		_reputations.append(int(player.get("reputation", 0)))
		_abilities.append(int(player.get("current_ability", 0)))
	_started = _thread.start(_sort_indices) == OK
	if not _started:
		_fallback = _sort_indices()

func _sort_indices() -> Array:
	var reputations := _reputations
	var abilities := _abilities
	var indices: Array = range(reputations.size())
	indices.sort_custom(func(a: int, b: int) -> bool:
		return reputations[a] > reputations[b] if reputations[a] != reputations[b] else abilities[a] > abilities[b])
	return indices

func is_ready() -> bool:
	return not _started or not _thread.is_alive()

func take() -> Array:
	if _started:
		_started = false
		return _thread.wait_to_finish()
	return _fallback

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread.is_started():
		_thread.wait_to_finish()
