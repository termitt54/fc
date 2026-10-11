class_name FixtureGenerator
extends RefCounted
## Builds regular-season fixtures from DIVISIONS unit rules.
## Each meeting index is a separate circle. Home/away is balanced and
## alternated inside a circle; the next circle reverses venues.


static func build_regular_season(
	club_ids: Array,
	divisions_count: int,
	teams_per_division: int,
	matches_vs_own: int,
	matches_vs_other: int,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var div_count: int = maxi(divisions_count, 1)
	var per_div: int = maxi(teams_per_division, 1)
	var divisions: Array = _assign_divisions(club_ids, div_count, per_div)
	var specs: Array = []
	specs.append_array(_own_division_specs(divisions, matches_vs_own))
	specs.append_array(_cross_division_specs(divisions, matches_vs_other))
	return {
		"divisions": divisions,
		"matches": _pack_circles(specs, rng),
	}


static func _assign_divisions(club_ids: Array, div_count: int, per_div: int) -> Array:
	var divisions: Array = []
	for d in div_count:
		divisions.append({"index": d, "club_ids": []})

	var ordered: Array = club_ids.duplicate()
	var capacity := div_count * maxi(per_div, 1)
	for i in ordered.size():
		var club_id: int = int(ordered[i])
		if club_id < 1:
			continue
		var div_index: int
		if ordered.size() <= capacity:
			div_index = mini(int(i / maxi(per_div, 1)), div_count - 1)
		else:
			# Extra clubs: spread evenly so every team still plays.
			div_index = i % div_count
		(divisions[div_index]["club_ids"] as Array).append(club_id)
	return divisions


static func _own_division_specs(divisions: Array, meetings: int) -> Array:
	var specs: Array = []
	if meetings < 1:
		return specs
	for division in divisions:
		var clubs: Array = division.get("club_ids", [])
		for i in clubs.size():
			for j in range(i + 1, clubs.size()):
				specs.append({
					"a": int(clubs[i]),
					"b": int(clubs[j]),
					"meetings": meetings,
				})
	return specs


static func _cross_division_specs(divisions: Array, meetings: int) -> Array:
	var specs: Array = []
	if meetings < 1 or divisions.size() < 2:
		return specs
	for a in divisions.size():
		for b in range(a + 1, divisions.size()):
			var clubs_a: Array = divisions[a].get("club_ids", [])
			var clubs_b: Array = divisions[b].get("club_ids", [])
			for club_a in clubs_a:
				for club_b in clubs_b:
					specs.append({
						"a": int(club_a),
						"b": int(club_b),
						"meetings": meetings,
					})
	return specs


static func _pack_circles(specs: Array, rng: RandomNumberGenerator) -> Array:
	var max_meetings := 0
	for spec in specs:
		max_meetings = maxi(max_meetings, int(spec.get("meetings", 0)))

	var matches: Array = []
	var match_id := 1
	var matchday := 1
	var prev_last_day: Array = []
	var prev_pair_key := ""
	var prev_days: Array = []

	for meeting_i in max_meetings:
		var pairs: Array = []
		for spec in specs:
			if meeting_i >= int(spec.get("meetings", 0)):
				continue
			var club_a := int(spec.get("a", 0))
			var club_b := int(spec.get("b", 0))
			if club_a < 1 or club_b < 1 or club_a == club_b:
				continue
			pairs.append({"home_id": club_a, "away_id": club_b})

		var pair_key := _pair_set_key(pairs)
		var days: Array
		if meeting_i > 0 and pair_key == prev_pair_key and not prev_days.is_empty():
			days = _reverse_days(prev_days)
		else:
			days = _pack_round(pairs, rng)
			_assign_venues(days)
		_avoid_adjacent_rematches(prev_last_day, days)
		prev_pair_key = pair_key
		prev_days = days
		for day in days:
			for pair in day:
				matches.append({
					"id": match_id,
					"matchday": matchday,
					"season_day": matchday,
					"circle": meeting_i + 1,
					"home_id": int(pair.get("home_id", 0)),
					"away_id": int(pair.get("away_id", 0)),
					"home_goals": -1,
					"away_goals": -1,
					"played": false,
					"stage": "REGULAR",
				})
				match_id += 1
			if not day.is_empty():
				prev_last_day = day
			matchday += 1
			if matchday > 500:
				return matches

	return matches


static func _pack_round(pairs: Array, rng: RandomNumberGenerator) -> Array:
	if pairs.is_empty():
		return []
	var components := _connected_components(pairs)
	var component_days: Array = []
	var max_len := 0
	for component in components:
		var days := _factorize_component(component, rng)
		component_days.append(days)
		max_len = maxi(max_len, days.size())

	var merged: Array = []
	for i in max_len:
		var day: Array = []
		for days in component_days:
			if i < days.size():
				day.append_array(days[i])
		if day.is_empty():
			continue
		_shuffle(day, rng)
		merged.append(day)
	return merged


static func _factorize_component(component: Dictionary, rng: RandomNumberGenerator) -> Array:
	var vertices: Array = component.get("vertices", [])
	var edges: Array = component.get("edges", [])
	if _is_complete_graph(vertices, edges):
		return _circle_days(vertices, rng)
	var parts := _bipartition(vertices, edges)
	if bool(parts.get("ok", false)) \
		and int(edges.size()) == int(parts["left"].size()) * int(parts["right"].size()):
		return _bipartite_days(parts["left"], parts["right"], rng)
	return _matching_factorization(edges, rng)


static func _circle_days(club_ids: Array, rng: RandomNumberGenerator) -> Array:
	var teams: Array = []
	for club_id in club_ids:
		var id := int(club_id)
		if id > 0:
			teams.append(id)
	if teams.size() < 2:
		return []
	_shuffle(teams, rng)
	if teams.size() % 2 == 1:
		teams.append(0)
	var n := teams.size()
	var half := n / 2
	var ring: Array = teams.duplicate()
	var days: Array = []
	for _round_i in n - 1:
		var day: Array = []
		for i in half:
			var club_a := int(ring[i])
			var club_b := int(ring[n - 1 - i])
			if club_a > 0 and club_b > 0:
				day.append({"home_id": club_a, "away_id": club_b})
		if not day.is_empty():
			days.append(day)
		var last: Variant = ring[n - 1]
		for k in range(n - 1, 1, -1):
			ring[k] = ring[k - 1]
		ring[1] = last
	return days


static func _bipartite_days(left_raw: Array, right_raw: Array, rng: RandomNumberGenerator) -> Array:
	var left: Array = left_raw.duplicate()
	var right: Array = right_raw.duplicate()
	_shuffle(left, rng)
	_shuffle(right, rng)
	if left.is_empty() or right.is_empty():
		return []
	if left.size() > right.size():
		var swap: Array = left
		left = right
		right = swap
	var days: Array = []
	for offset in right.size():
		var day: Array = []
		for i in left.size():
			var club_a := int(left[i])
			var club_b := int(right[(i + offset) % right.size()])
			day.append({"home_id": club_a, "away_id": club_b})
		days.append(day)
	return days


static func _matching_factorization(edges: Array, rng: RandomNumberGenerator) -> Array:
	var remaining: Array = edges.duplicate()
	_shuffle(remaining, rng)
	var days: Array = []
	while not remaining.is_empty():
		var matching := _maximum_matching(remaining)
		if matching.is_empty():
			matching.append(remaining[0])
		days.append(matching)
		var used := _pair_keys(matching)
		var leftover: Array = []
		for pair in remaining:
			if not used.has(_pair_key(pair)):
				leftover.append(pair)
		remaining = leftover
	return days


static func _maximum_matching(edges: Array) -> Array:
	var teams: Dictionary = {}
	for pair in edges:
		teams[_club_a(pair)] = true
		teams[_club_b(pair)] = true
	var target := teams.size() / 2
	var best: Array = []
	_search_matching(edges, 0, {}, [], best, target)
	return best


static func _search_matching(
	edges: Array,
	start_idx: int,
	used: Dictionary,
	current: Array,
	best: Array,
	target: int
) -> bool:
	if current.size() > best.size():
		best.clear()
		best.append_array(current)
	if current.size() == target:
		return true
	if current.size() + (edges.size() - start_idx) <= best.size():
		return false
	for i in range(start_idx, edges.size()):
		var pair: Dictionary = edges[i]
		var club_a := _club_a(pair)
		var club_b := _club_b(pair)
		if club_a < 1 or club_b < 1 or used.has(club_a) or used.has(club_b):
			continue
		used[club_a] = true
		used[club_b] = true
		current.append(pair)
		if _search_matching(edges, i + 1, used, current, best, target):
			return true
		current.pop_back()
		used.erase(club_a)
		used.erase(club_b)
	return false


static func _assign_venues(days: Array) -> void:
	var last: Dictionary = {}
	var homes: Dictionary = {}
	for day in days:
		for i in day.size():
			var club_a := _club_a(day[i])
			var club_b := _club_b(day[i])
			if club_a < 1 or club_b < 1:
				continue
			var a_home := _prefer_home(club_a, club_b, last, homes)
			if a_home:
				day[i] = {"home_id": club_a, "away_id": club_b}
				_mark_venue(club_a, true, last, homes)
				_mark_venue(club_b, false, last, homes)
			else:
				day[i] = {"home_id": club_b, "away_id": club_a}
				_mark_venue(club_b, true, last, homes)
				_mark_venue(club_a, false, last, homes)
	_improve_venues(days)


static func _prefer_home(club_a: int, club_b: int, last: Dictionary, homes: Dictionary) -> bool:
	var score_a := 0
	var score_b := 0
	var last_a := str(last.get(club_a, ""))
	var last_b := str(last.get(club_b, ""))
	if last_a == "A":
		score_a += 4
	elif last_a == "H":
		score_a -= 4
	if last_b == "A":
		score_b += 4
	elif last_b == "H":
		score_b -= 4
	var homes_a := int(homes.get(club_a, 0))
	var homes_b := int(homes.get(club_b, 0))
	if homes_a < homes_b:
		score_a += 2
	elif homes_b < homes_a:
		score_b += 2
	return score_a >= score_b


static func _mark_venue(club_id: int, is_home: bool, last: Dictionary, homes: Dictionary) -> void:
	last[club_id] = "H" if is_home else "A"
	if is_home:
		homes[club_id] = int(homes.get(club_id, 0)) + 1


static func _improve_venues(days: Array) -> void:
	var best := _venue_cost(days)
	for _pass in 48:
		var improved := false
		for d in days.size():
			var day: Array = days[d]
			for i in day.size():
				var pair: Dictionary = day[i]
				day[i] = {
					"home_id": int(pair.get("away_id", 0)),
					"away_id": int(pair.get("home_id", 0)),
				}
				var next_cost := _venue_cost(days)
				if next_cost < best:
					best = next_cost
					improved = true
				else:
					day[i] = pair
		if not improved:
			break


static func _venue_cost(days: Array) -> int:
	var seq: Dictionary = {}
	for day in days:
		for pair in day:
			var home_id := int(pair.get("home_id", 0))
			var away_id := int(pair.get("away_id", 0))
			if home_id < 1 or away_id < 1:
				continue
			if not seq.has(home_id):
				seq[home_id] = []
			if not seq.has(away_id):
				seq[away_id] = []
			(seq[home_id] as Array).append(true)
			(seq[away_id] as Array).append(false)
	var cost := 0
	for club_id in seq.keys():
		var series: Array = seq[club_id]
		var home_count := 0
		for is_home in series:
			if bool(is_home):
				home_count += 1
		var away_count := series.size() - home_count
		var diff := absi(home_count - away_count)
		cost += diff * diff * 15
		var run := 1
		for i in range(1, series.size()):
			if series[i] == series[i - 1]:
				run += 1
				if run >= 2:
					cost += 8
				if run >= 3:
					cost += 50
			else:
				run = 1
	return cost


static func _reverse_days(days: Array) -> Array:
	var out: Array = []
	for day in days:
		var flipped: Array = []
		for pair in day:
			flipped.append({
				"home_id": int(pair.get("away_id", 0)),
				"away_id": int(pair.get("home_id", 0)),
			})
		out.append(flipped)
	return out


static func _pair_set_key(pairs: Array) -> String:
	var keys: Array = []
	for pair in pairs:
		keys.append(_pair_key(pair))
	keys.sort()
	return "|".join(keys)


static func _connected_components(pairs: Array) -> Array:
	var parent: Dictionary = {}
	for pair in pairs:
		var club_a := _club_a(pair)
		var club_b := _club_b(pair)
		if club_a < 1 or club_b < 1:
			continue
		if not parent.has(club_a):
			parent[club_a] = club_a
		if not parent.has(club_b):
			parent[club_b] = club_b
		_uf_union(parent, club_a, club_b)

	var groups: Dictionary = {}
	for pair in pairs:
		var club_a := _club_a(pair)
		var club_b := _club_b(pair)
		if club_a < 1 or club_b < 1:
			continue
		var root := _uf_find(parent, club_a)
		if not groups.has(root):
			groups[root] = {"vertices": {}, "edges": []}
		groups[root]["vertices"][club_a] = true
		groups[root]["vertices"][club_b] = true
		(groups[root]["edges"] as Array).append(pair)

	var components: Array = []
	for root in groups.keys():
		components.append({
			"vertices": (groups[root]["vertices"] as Dictionary).keys(),
			"edges": groups[root]["edges"],
		})
	return components


static func _is_complete_graph(vertices: Array, edges: Array) -> bool:
	var n := vertices.size()
	if n < 2:
		return false
	return edges.size() == n * (n - 1) / 2


static func _bipartition(vertices: Array, edges: Array) -> Dictionary:
	var adj: Dictionary = {}
	for club_id in vertices:
		adj[int(club_id)] = []
	for pair in edges:
		var club_a := _club_a(pair)
		var club_b := _club_b(pair)
		if not adj.has(club_a) or not adj.has(club_b):
			continue
		(adj[club_a] as Array).append(club_b)
		(adj[club_b] as Array).append(club_a)

	var color: Dictionary = {}
	for start in vertices:
		var seed := int(start)
		if color.has(seed):
			continue
		color[seed] = 0
		var queue: Array = [seed]
		while not queue.is_empty():
			var node: int = int(queue.pop_front())
			for next_id in adj.get(node, []):
				var other := int(next_id)
				if not color.has(other):
					color[other] = 1 - int(color[node])
					queue.append(other)
				elif int(color[other]) == int(color[node]):
					return {"ok": false}

	var left: Array = []
	var right: Array = []
	for club_id in vertices:
		var id := int(club_id)
		if int(color.get(id, 0)) == 0:
			left.append(id)
		else:
			right.append(id)
	return {"ok": true, "left": left, "right": right}


static func _uf_find(parent: Dictionary, x: int) -> int:
	var p := int(parent.get(x, x))
	if p != x:
		p = _uf_find(parent, p)
		parent[x] = p
	return p


static func _uf_union(parent: Dictionary, a: int, b: int) -> void:
	var root_a := _uf_find(parent, a)
	var root_b := _uf_find(parent, b)
	if root_a != root_b:
		parent[root_b] = root_a


static func _club_a(pair: Dictionary) -> int:
	return int(pair.get("home_id", pair.get("a", 0)))


static func _club_b(pair: Dictionary) -> int:
	return int(pair.get("away_id", pair.get("b", 0)))


static func _avoid_adjacent_rematches(prev_day: Array, days: Array) -> void:
	if prev_day.is_empty() or days.is_empty():
		return
	var prev_keys := _pair_keys(prev_day)
	var first: Array = days[0]
	for i in first.size():
		var key := _pair_key(first[i])
		if not prev_keys.has(key):
			continue
		for d in range(1, days.size()):
			var later: Array = days[d]
			var swapped := false
			for j in later.size():
				if prev_keys.has(_pair_key(later[j])):
					continue
				var tmp: Dictionary = first[i]
				first[i] = later[j]
				later[j] = tmp
				swapped = true
				break
			if swapped:
				break


static func _pair_keys(pairs: Array) -> Dictionary:
	var keys: Dictionary = {}
	for pair in pairs:
		keys[_pair_key(pair)] = true
	return keys


static func _pair_key(pair: Dictionary) -> String:
	var a := int(pair.get("home_id", 0))
	var b := int(pair.get("away_id", 0))
	return "%d-%d" % [mini(a, b), maxi(a, b)]


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
