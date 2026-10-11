class_name ListPage
extends RefCounted
## A fixed window over an already sorted list. The screen builds one page.


const SIZE := 100


static func count(total: int) -> int:
	if total <= 0:
		return 1
	return int(ceili(float(total) / float(SIZE)))


static func clamp_index(page: int, total: int) -> int:
	return clampi(page, 0, count(total) - 1)


static func slice_of(rows: Array, page: int) -> Array:
	if rows.is_empty():
		return []
	var index := clamp_index(page, rows.size())
	var start := index * SIZE
	var end := mini(start + SIZE, rows.size())
	return rows.slice(start, end)


static func label(page: int, total: int) -> String:
	if total <= 0:
		return "0"
	var index := clamp_index(page, total)
	var start := index * SIZE + 1
	var end := mini((index + 1) * SIZE, total)
	return "%d–%d из %d" % [start, end, total]
