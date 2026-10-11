class_name WeMessageDialog
extends WeModal
## Confirm / info dialog on the custom modal shell.


enum Kind { INFO, CONFIRM }

var _kind: Kind = Kind.INFO
var _message: Label


func _ready() -> void:
	super._ready()
	close_on_dim = true
	card_width = 440.0
	_card.custom_minimum_size.x = card_width

	_message = get_node_or_null("%Message") as Label
	if _message == null:
		_message = Label.new()
		_message.name = "Message"
		_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		get_body().add_child(_message)

	_message.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_message.add_theme_font_size_override("font_size", 14)
	confirmed.connect(_on_confirmed_internal)
	cancelled.connect(func(): close())


func open_info(title_text: String, message: String) -> void:
	_kind = Kind.INFO
	set_title(title_text)
	_message.text = message
	set_confirm_text("Понятно")
	set_cancel_text("Закрыть")
	_cancel_button.visible = false
	_confirm_button.kind = WeButton.Kind.PRIMARY
	open()


func open_confirm(title_text: String, message: String, confirm_text: String = "Удалить") -> void:
	_kind = Kind.CONFIRM
	set_title(title_text)
	_message.text = message
	set_confirm_text(confirm_text)
	set_cancel_text("Отмена")
	_cancel_button.visible = true
	_confirm_button.kind = WeButton.Kind.DANGER
	open()


func _on_confirmed_internal() -> void:
	if _kind == Kind.INFO:
		close()
