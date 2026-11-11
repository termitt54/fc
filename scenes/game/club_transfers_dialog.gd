extends WeModal
const Transfers = preload("res://scenes/game/transfers_view.gd")
var transfer_view: VBoxContainer
signal player_requested(player_id: int)

func _ready() -> void:
	super._ready()
	cancelled.connect(close)
	closed.connect(queue_free)
	_confirm_button.hide()
	set_cancel_text("Закрыть")

func show_club(club_id: int, club_name: String) -> void:
	set_title("Трансферы · " + club_name)
	var viewport := get_viewport_rect().size
	set_card_size(minf(1500, viewport.x - 48), minf(860, viewport.y - 48))
	transfer_view = Transfers.new()
	transfer_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	get_body().add_child(transfer_view)
	transfer_view.closed.connect(close)
	transfer_view.club_requested.connect(func(_id: int): close())
	transfer_view.player_requested.connect(func(id: int):
		close()
		player_requested.emit(id))
	transfer_view.set_club(club_id)
	GameSession.session_changed.connect(_refresh_history)
	open()

func _refresh_history() -> void:
	if is_instance_valid(transfer_view) and transfer_view._club_log_size != GameSession.transfer_log.size():
		transfer_view.refresh()
