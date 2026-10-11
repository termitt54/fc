class_name PlayoffBracketView
extends Control
## Mirrored playoff tree. Structure is built once; scores sync in place.


const CARD_W := 216.0
const CARD_H := 80.0
const COL_GAP := 56.0
const ROW_GAP := 28.0
const PAD_X := 16.0
const PAD_Y := 18.0
const TITLE_H := 24.0
const GOLD := Color(0.98, 0.82, 0.42, 1.0)

var _unit: Dictionary = {}
var _playoff: Dictionary = {}
var _make_series: Callable
var _apply_series: Callable

var _left_slots: Dictionary = {}
var _right_slots: Dictionary = {}
var _final_card: Control
var _third_card: Control
var _title_labels: Array[Label] = []
var _total_rounds: int = 1
var _built := false
var _pulse := 0.0
var _card_w := CARD_W
var _card_h := CARD_H
var _col_gap := COL_GAP
var _row_gap := ROW_GAP


func setup(
	unit: Dictionary,
	playoff: Dictionary,
	make_series: Callable,
	apply_series: Callable
) -> void:
	_unit = unit
	_playoff = playoff
	_make_series = make_series
	_apply_series = apply_series
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_meta("unit_id", int(unit.get("id", 0)))
	_rebuild()


func sync(unit: Dictionary, playoff: Dictionary) -> void:
	if not _built:
		setup(unit, playoff, _make_series, _apply_series)
		return
	_unit = unit
	_playoff = playoff
	set_meta("unit_id", int(unit.get("id", 0)))
	for card in _all_cards():
		if card == null:
			continue
		var series := _series_for_card(card)
		if _apply_series.is_valid():
			_apply_series.call(card, _unit, _playoff, series)
		_stamp_card(card, series)
	_refresh_title_colors()
	queue_redraw()


func matches_unit(unit: Dictionary) -> bool:
	return is_inside_tree() and int(get_meta("unit_id", 0)) == int(unit.get("id", 0))


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_left_slots.clear()
	_right_slots.clear()
	_title_labels.clear()
	_final_card = null
	_third_card = null
	_built = false
	_pulse = 0.0

	var by_round: Dictionary = _series_by_round()
	var teams: int = maxi(int(_playoff.get("teams", 2)), 2)
	_total_rounds = _rounds_for(teams)
	var wing_rounds := maxi(_total_rounds - 1, 0)

	for round_no in range(1, _total_rounds + 1):
		var series_list: Array = _sorted_series(by_round.get(round_no, []))
		var expected := int(ceil(float(teams) / pow(2.0, float(round_no))))
		expected = maxi(expected, 1)

		if round_no == _total_rounds:
			_final_card = _make_slot_card(
				series_list[0] if not series_list.is_empty() else {},
				round_no, 0, false
			)
			add_child(_final_card)
			continue

		var left_count := int(ceil(float(expected) / 2.0))
		var right_count := expected - left_count
		_left_slots[round_no] = []
		_right_slots[round_no] = []

		for i in left_count:
			var series: Dictionary = series_list[i] if i < series_list.size() else {}
			var card := _make_slot_card(series, round_no, i, false)
			add_child(card)
			(_left_slots[round_no] as Array).append(card)

		for i in right_count:
			var idx := left_count + i
			var series: Dictionary = series_list[idx] if idx < series_list.size() else {}
			var card := _make_slot_card(series, round_no, idx, true)
			add_child(card)
			(_right_slots[round_no] as Array).append(card)

	if bool(_playoff.get("third_place", false)):
		_third_card = _make_slot_card(_third_series(), _total_rounds, -1, false)
		add_child(_third_card)
		_add_title("3-е место", "T")

	for round_no in range(1, maxi(wing_rounds, 0) + 1):
		_add_title(_round_title(round_no, _total_rounds), "L%d" % round_no)
		_add_title(_round_title(round_no, _total_rounds), "R%d" % round_no)
	_add_title("Финал", "F")

	_built = true
	set_process(true)
	queue_redraw()
	call_deferred("_layout_and_redraw")


func _make_slot_card(series: Dictionary, round_no: int, slot: int, mirrored: bool) -> Control:
	var card: Control = _make_series.call(_unit, _playoff, series, mirrored)
	card.custom_minimum_size = Vector2(120, 64)
	_stamp_card(card, series)
	card.set_meta("round", round_no)
	card.set_meta("slot", slot)
	card.set_meta("mirrored", mirrored)
	return card


func _stamp_card(card: Control, series: Dictionary) -> void:
	card.set_meta("series", series)
	card.set_meta("winner_id", int(series.get("winner_id", 0)))
	card.set_meta("home_id", int(series.get("home_id", 0)))
	card.set_meta("away_id", int(series.get("away_id", 0)))
	card.set_meta("complete", bool(series.get("complete", false)))
	var current := not series.is_empty() \
		and int(series.get("round", 0)) == int(_playoff.get("current_round", 0)) \
		and not bool(series.get("complete", false))
	card.set_meta("current", current)


func _series_for_card(card: Control) -> Dictionary:
	var slot: int = int(card.get_meta("slot", 0))
	if slot < 0:
		return _third_series()
	var round_no: int = int(card.get_meta("round", 1))
	for series in _playoff.get("series", []):
		if bool(series.get("is_third_place", false)):
			continue
		if int(series.get("round", 0)) != round_no:
			continue
		if int(series.get("slot", int(series.get("id", 0)) - 1)) == slot:
			return series
	return {}


func _third_series() -> Dictionary:
	for series in _playoff.get("series", []):
		if bool(series.get("is_third_place", false)):
			return series
	return {}


func _series_by_round() -> Dictionary:
	var by_round: Dictionary = {}
	for series in _playoff.get("series", []):
		if bool(series.get("is_third_place", false)):
			continue
		var round_no: int = int(series.get("round", 1))
		if not by_round.has(round_no):
			by_round[round_no] = []
		(by_round[round_no] as Array).append(series)
	return by_round


func _sorted_series(series_list: Array) -> Array:
	var rows: Array = series_list.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get("slot", int(a.get("id", 0))))
		var sb := int(b.get("slot", int(b.get("id", 0))))
		if sa == sb:
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return sa < sb
	)
	return rows


func _rounds_for(teams: int) -> int:
	var n := maxi(teams, 2)
	var rounds := 0
	while n > 1:
		n = int(ceil(float(n) / 2.0))
		rounds += 1
	return maxi(rounds, 1)


func _add_title(text: String, key: String) -> void:
	var label := Label.new()
	label.text = text
	label.set_meta("title_key", key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := WeTokens.font_semibold()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_title_labels.append(label)


func _round_title(round_no: int, max_round: int) -> String:
	var steps_left := max_round - round_no
	match steps_left:
		0:
			return "Финал"
		1:
			return "Полуфинал"
		2:
			return "1/4 финала"
		3:
			return "1/8 финала"
		_:
			return "Раунд %d" % round_no


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout_and_redraw()


func _process(delta: float) -> void:
	if not _built or not is_visible_in_tree():
		return
	_pulse += delta
	var pulse := 0.5 + 0.5 * sin(_pulse * 2.4)
	var live := false
	for card in _all_cards():
		if card == null:
			continue
		if bool(card.get_meta("current", false)):
			live = true
			var glow := 0.92 + pulse * 0.08
			card.self_modulate = Color(glow, glow, 1.0, 1.0)
		else:
			card.self_modulate = Color.WHITE
	if live:
		queue_redraw()


func _all_cards() -> Array:
	var cards: Array = []
	for round_no in _left_slots.keys():
		cards.append_array(_left_slots[round_no])
	for round_no in _right_slots.keys():
		cards.append_array(_right_slots[round_no])
	if _final_card != null:
		cards.append(_final_card)
	if _third_card != null:
		cards.append(_third_card)
	return cards


func _layout_and_redraw() -> void:
	if not _built:
		return
	_layout_cards()
	queue_redraw()


func _compute_metrics(area_w: float, area_h: float) -> void:
	var wing_rounds := maxi(_total_rounds - 1, 0)
	var cols := wing_rounds * 2 + 1
	if wing_rounds == 0:
		cols = 1
	var r1_slots := int(ceil(float(maxi(int(_playoff.get("teams", 2)), 2)) / 2.0))
	var left_r1 := int(ceil(float(r1_slots) / 2.0))
	var extra_third := CARD_H + TITLE_H + 56.0 if _third_card != null else 0.0
	var base_w := PAD_X * 2.0 + cols * CARD_W + maxi(cols - 1, 0) * COL_GAP
	var base_h := PAD_Y * 2.0 + TITLE_H + left_r1 * CARD_H + maxi(left_r1 - 1, 0) * ROW_GAP + extra_third
	var scale := 1.0
	if area_w > 80.0 and base_w > area_w:
		scale = minf(scale, area_w / base_w)
	if area_h > 80.0 and base_h > area_h:
		scale = minf(scale, area_h / base_h)
	scale = clampf(scale, 0.7, 1.0)
	_card_w = CARD_W * scale
	_card_h = CARD_H * scale
	_col_gap = COL_GAP * scale
	_row_gap = ROW_GAP * scale


func _layout_cards() -> void:
	var wing_rounds := maxi(_total_rounds - 1, 0)
	var area_w := size.x
	var area_h := size.y
	if area_w < 8.0 or area_h < 8.0:
		return
	_compute_metrics(area_w, area_h)

	var left_cols: Array = []
	for round_no in range(1, wing_rounds + 1):
		left_cols.append(round_no)

	var col_count := left_cols.size() * 2 + 1
	if wing_rounds == 0:
		col_count = 1
	var total_w := col_count * _card_w + maxi(col_count - 1, 0) * _col_gap
	var start_x := (area_w - total_w) * 0.5
	if start_x < PAD_X:
		start_x = PAD_X

	var xs: Dictionary = {}
	for i in left_cols.size():
		var round_no: int = int(left_cols[i])
		xs["L%d" % round_no] = start_x + i * (_card_w + _col_gap)
	var final_x := start_x + left_cols.size() * (_card_w + _col_gap)
	xs["F"] = final_x
	for i in left_cols.size():
		var round_no: int = int(left_cols[left_cols.size() - 1 - i])
		xs["R%d" % round_no] = final_x + (i + 1) * (_card_w + _col_gap)

	var content_top := PAD_Y + TITLE_H
	var third_gap := 48.0
	var bottom_reserve := (TITLE_H + _card_h + third_gap + 12.0) if _third_card != null else 0.0
	var content_h := area_h - content_top - PAD_Y - bottom_reserve

	if wing_rounds >= 1:
		_place_slot_column(_left_slots.get(1, []), float(xs["L1"]), content_top, content_h)
		_place_slot_column(_right_slots.get(1, []), float(xs["R1"]), content_top, content_h)
		for round_no in range(2, wing_rounds + 1):
			_place_from_parents(
				_left_slots.get(round_no, []),
				_left_slots.get(round_no - 1, []),
				float(xs["L%d" % round_no])
			)
			_place_from_parents(
				_right_slots.get(round_no, []),
				_right_slots.get(round_no - 1, []),
				float(xs["R%d" % round_no])
			)

	if _final_card != null:
		var fy := content_top + (content_h - _card_h) * 0.5
		if wing_rounds >= 1:
			var left_sf: Array = _left_slots.get(wing_rounds, [])
			var right_sf: Array = _right_slots.get(wing_rounds, [])
			if not left_sf.is_empty() and not right_sf.is_empty():
				var a: Control = left_sf[0]
				var b: Control = right_sf[0]
				fy = (a.position.y + a.size.y * 0.5 + b.position.y + b.size.y * 0.5) * 0.5 - _card_h * 0.5
		_final_card.position = Vector2(float(xs["F"]), fy)
		_final_card.size = Vector2(_card_w, _card_h)

	if _third_card != null and _final_card != null:
		_third_card.position = Vector2(float(xs["F"]), _final_card.position.y + _card_h + third_gap)
		_third_card.size = Vector2(_card_w, _card_h)

	_place_titles(xs)


func _place_titles(xs: Dictionary) -> void:
	var current := int(_playoff.get("current_round", 0))
	for label in _title_labels:
		var key := str(label.get_meta("title_key", ""))
		if key == "T":
			if _third_card == null:
				label.visible = false
				continue
			label.visible = true
			label.position = Vector2(_third_card.position.x, _third_card.position.y - TITLE_H - 2.0)
			label.size = Vector2(_card_w, TITLE_H)
			_paint_title(label, false)
			continue
		var x := float(xs.get(key, -999.0))
		if x < -100.0:
			label.visible = false
			continue
		label.visible = true
		label.position = Vector2(x, PAD_Y - 4.0)
		label.size = Vector2(_card_w, TITLE_H)
		var live := false
		if key == "F":
			live = current == _total_rounds
		elif key.begins_with("L") or key.begins_with("R"):
			live = current == int(key.substr(1))
		_paint_title(label, live)


func _refresh_title_colors() -> void:
	var current := int(_playoff.get("current_round", 0))
	for label in _title_labels:
		var key := str(label.get_meta("title_key", ""))
		var live := false
		if key == "F":
			live = current == _total_rounds
		elif key.begins_with("L") or key.begins_with("R"):
			live = current == int(key.substr(1))
		_paint_title(label, live)


func _paint_title(label: Label, live: bool) -> void:
	label.add_theme_color_override("font_color", WeTokens.ACCENT if live else WeTokens.TEXT_MUTED)


func _place_slot_column(cards: Array, x: float, top: float, height: float) -> void:
	if cards.is_empty():
		return
	var count := cards.size()
	var block_h := count * _card_h + (count - 1) * _row_gap
	var y0 := top + (height - block_h) * 0.5
	for i in count:
		var card: Control = cards[i]
		card.position = Vector2(x, y0 + i * (_card_h + _row_gap))
		card.size = Vector2(_card_w, _card_h)


func _place_from_parents(children: Array, parents: Array, x: float) -> void:
	if children.is_empty():
		return
	if parents.is_empty():
		_place_slot_column(children, x, PAD_Y + TITLE_H, size.y)
		return
	for i in children.size():
		var card: Control = children[i]
		var i0 := i * 2
		var i1 := mini(i0 + 1, parents.size() - 1)
		var a: Control = parents[mini(i0, parents.size() - 1)]
		var b: Control = parents[i1]
		var mid := (a.position.y + a.size.y * 0.5 + b.position.y + b.size.y * 0.5) * 0.5
		card.position = Vector2(x, mid - _card_h * 0.5)
		card.size = Vector2(_card_w, _card_h)


func _draw() -> void:
	if not _built:
		return
	var wing_rounds := maxi(_total_rounds - 1, 0)
	var current := int(_playoff.get("current_round", 0))
	var pulse := 0.55 + 0.45 * sin(_pulse * 2.4)

	for round_no in range(1, wing_rounds + 1):
		var sources: Array = _left_slots.get(round_no, [])
		var targets: Array
		if round_no + 1 < _total_rounds:
			targets = _left_slots.get(round_no + 1, [])
		else:
			targets = [_final_card] if _final_card != null else []
		_draw_links(sources, targets, true, round_no == current, pulse)

	for round_no in range(1, wing_rounds + 1):
		var sources: Array = _right_slots.get(round_no, [])
		var targets: Array
		if round_no + 1 < _total_rounds:
			targets = _right_slots.get(round_no + 1, [])
		else:
			targets = [_final_card] if _final_card != null else []
		_draw_links(sources, targets, false, round_no == current, pulse)

	if _final_card != null and _third_card != null:
		var a := _final_card.position + Vector2(_final_card.size.x * 0.5, _final_card.size.y)
		var b := _third_card.position + Vector2(_third_card.size.x * 0.5, 0.0)
		_draw_elbow(a, b, Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 2.0, true)


func _draw_links(sources: Array, targets: Array, from_left: bool, live_round: bool, pulse: float) -> void:
	if sources.is_empty() or targets.is_empty():
		return
	var champion_id: int = int(_playoff.get("champion_id", 0))
	for i in sources.size():
		var src: Control = sources[i]
		if src == null:
			continue
		var t_index := mini(int(i / 2), targets.size() - 1)
		var dst: Control = targets[t_index]
		if dst == null:
			continue
		var a := _anchor(src, from_left)
		var b: Vector2
		if dst == _final_card:
			b = _final_card.position + Vector2(0.0 if from_left else _final_card.size.x, _final_card.size.y * 0.5)
		else:
			b = _anchor(dst, not from_left)
		var winner_id: int = int(src.get_meta("winner_id", 0))
		var advances := winner_id > 0 and _card_has_club(dst, winner_id)
		var on_champion := champion_id > 0 and winner_id == champion_id and advances
		var color: Color
		var width := 2.2
		if on_champion:
			color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
			width = 3.4
		elif advances:
			color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.82)
			width = 2.8
		elif live_round:
			color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.28 + pulse * 0.22)
			width = 2.4
		else:
			color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.16)
		_draw_elbow(a, b, Color(color.r, color.g, color.b, color.a * 0.22), width + 6.0, false)
		_draw_elbow(a, b, color, width, false)


func _card_has_club(card: Control, club_id: int) -> bool:
	if card == null or club_id < 1:
		return false
	return int(card.get_meta("home_id", 0)) == club_id or int(card.get_meta("away_id", 0)) == club_id


func _anchor(card: Control, exit_right: bool) -> Vector2:
	if exit_right:
		return card.position + Vector2(card.size.x, card.size.y * 0.5)
	return card.position + Vector2(0.0, card.size.y * 0.5)


func _draw_elbow(from: Vector2, to: Vector2, color: Color, width: float, vertical: bool) -> void:
	var points := PackedVector2Array()
	if vertical:
		var mid_y := (from.y + to.y) * 0.5
		points.append(from)
		points.append(Vector2(from.x, mid_y))
		points.append(Vector2(to.x, mid_y))
		points.append(to)
	else:
		var mid_x := (from.x + to.x) * 0.5
		var dx := to.x - from.x
		var dy := to.y - from.y
		var chamfer := minf(18.0, minf(absf(dx), absf(dy)) * 0.35)
		if chamfer < 3.0:
			points.append(from)
			points.append(Vector2(mid_x, from.y))
			points.append(Vector2(mid_x, to.y))
			points.append(to)
		else:
			var sx := 1.0 if dx >= 0.0 else -1.0
			var sy := 1.0 if dy >= 0.0 else -1.0
			points.append(from)
			points.append(Vector2(mid_x - chamfer * sx, from.y))
			points.append(Vector2(mid_x, from.y + chamfer * sy))
			points.append(Vector2(mid_x, to.y - chamfer * sy))
			points.append(Vector2(mid_x + chamfer * sx, to.y))
			points.append(to)
	if points.size() >= 2:
		draw_polyline(points, color, width, true)
		draw_circle(from, width * 0.55, color)
		draw_circle(to, width * 0.55, color)
