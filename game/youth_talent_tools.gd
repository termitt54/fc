extends RefCounted
## Pure editor operations: no world, player or runtime-configuration mutation.
const Config := preload("res://game/youth_generation_config.gd")
static var _summary_means: Array = []

static func normalise(weights: Array, total: int = Config.BIRTH_WEIGHT_TOTAL) -> Array:
	var sum := 0.0
	for value in weights:
		sum += maxf(0.0, float(value))
	if sum <= 0.0:
		return []
	var result := []
	var remainders := []
	var assigned := 0
	for i in weights.size():
		var exact := maxf(0.0, float(weights[i])) / sum * total
		var rounded := int(floor(exact))
		result.append(rounded)
		assigned += rounded
		remainders.append({"index":i,"fraction":exact-rounded})
	remainders.sort_custom(func(a, b): return a.fraction>b.fraction if a.fraction!=b.fraction else a.index<b.index)
	for i in total-assigned:
		result[int(remainders[i % remainders.size()].index)] += 1
	return result

static func interpolate(a: Array, b: Array, fraction: float) -> Array:
	var weights := []
	for i in a.size():
		weights.append(lerpf(float(a[i]),float(b[i]),clampf(fraction,0.0,1.0)))
	return normalise(weights)

static func forecast(row: Array, count: int) -> Dictionary:
	var result := {"mean":Config.row_mean_potential(row),"count":count,"thresholds":{}}
	for threshold in [70,75,80,85,90,95,100]:
		var probability := Config.row_probability(row,threshold)
		result.thresholds[threshold] = {"probability":probability,"expected":count*probability}
	var genius := Config.row_probability(row,100)
	result["genius_one_in"] = 1.0/genius if genius>0 else 0.0
	return result

static func band_means() -> Array:
	var means := []
	for i in Config.BIRTH_BANDS.size():
		var row := []
		row.resize(Config.BIRTH_BANDS.size())
		row.fill(0)
		row[i] = Config.BIRTH_WEIGHT_TOTAL
		means.append(Config.row_mean_potential(row))
	return means

## Reweight an existing profile without making PA100 an accidental Gaussian tail.
## Mean is fitted after spread/elite adjustments; impossible means are reported.
static func reshape(row: Array, target: float, spread: float, elite: float, one_in: float) -> Dictionary:
	var means := band_means()
	var source := normalise(row)
	if source.is_empty():
		return {"ok":false,"error":"Нельзя построить профиль из пустой строки."}
	var genius_units := 0 if one_in<=0 else clampi(roundi(float(Config.BIRTH_WEIGHT_TOTAL)/one_in),0,Config.BIRTH_WEIGHT_TOTAL)
	var remaining := Config.BIRTH_WEIGHT_TOTAL-genius_units
	var source_mean := Config.row_mean_potential(source)
	var base := []
	for i in range(means.size()-1):
		# A tiny floor lets an absent band become editable without overflowing.
		var distance := (float(means[i])-source_mean)/15.0
		var scale := exp(clampf(0.5*distance*distance*(1.0-1.0/(spread*spread)),-30.0,30.0))
		base.append(maxf(float(source[i]),0.001)*scale*(elite if i>=8 else 1.0))
	var low := -4.0
	var high := 4.0
	var fitted := []
	for iteration in 64:
		var tilt := (low+high)*0.5
		var weights := []
		for i in base.size():
			weights.append(float(base[i])*exp(clampf(tilt*(float(means[i])-target),-250.0,250.0)))
		fitted = normalise(weights,remaining)
		fitted.append(genius_units)
		if Config.row_mean_potential(fitted)<target:
			low = tilt
		else:
			high = tilt
	var actual := Config.row_mean_potential(fitted)
	if absf(actual-target)>0.05:
		return {"ok":false,"error":"Такое среднее недостижимо с выбранной частотой PA 100 и диапазонами потенциала."}
	return {"ok":true,"row":fitted,"mean":actual}

static func progression_warnings(rows: Array) -> Array:
	var warnings := []
	for talent in range(1,rows.size()):
		if Config.row_mean_potential(rows[talent])+0.01 < Config.row_mean_potential(rows[talent-1]):
			warnings.append(talent)
	return warnings


## Mean/PA70+/PA80+ preserve PA90–100; PA90+ preserves PA100.
## PA100 changes only when its own probability is explicitly edited.
## The real within-band expectations from Config, rather than band midpoints,
## are used so editor targets agree with the generation forecast.
static func adjust_summary(row: Array, metric: String, target: float) -> Dictionary:
	if row.size() != Config.BIRTH_BANDS.size() or metric not in ["mean", "pa70", "pa80", "pa90", "pa100"] or not is_finite(target):
		return {"ok": false, "error": "Некорректное значение показателя."}
	var total := 0
	for weight in row:
		if float(weight) < 0 or not is_finite(float(weight)):
			return {"ok": false, "error": "Исправьте вероятности строки перед изменением показателя."}
		total += int(weight)
	if total != Config.BIRTH_WEIGHT_TOTAL:
		return {"ok": false, "error": "Сначала доведите сумму выбранной строки до 100%."}
	if _summary_means.is_empty():
		_summary_means = band_means()
	var means := _summary_means
	if metric == "pa100":
		var requested := clampf(target, 0.0, 100.0)
		var units := clampi(roundi(requested * Config.PERCENT_SCALE), 0, Config.BIRTH_WEIGHT_TOTAL)
		var result := _summary_scale(row.slice(0, 10), Config.BIRTH_WEIGHT_TOTAL - units, 7)
		result.append(units)
		return {"ok": true, "row": result, "actual": float(units) / Config.PERCENT_SCALE, "clamped": target < 0 or target > 100, "min": 0.0, "max": 100.0}
	var locked_from := 10 if metric == "pa90" else 8
	var split := {"pa70": 4, "pa80": 6, "pa90": 8}.get(metric, 0) as int
	var rare := 0
	var tail_mean := 0.0
	for i in range(locked_from, row.size()):
		rare += int(row[i])
		tail_mean += float(row[i]) * float(means[i]) / Config.BIRTH_WEIGHT_TOTAL
	var remaining := Config.BIRTH_WEIGHT_TOTAL - rare
	var lo := float(rare) / Config.PERCENT_SCALE if metric != "mean" else tail_mean + float(remaining) * float(means[0]) / Config.BIRTH_WEIGHT_TOTAL
	var hi := 100.0 if metric != "mean" else tail_mean + float(remaining) * float(means[7]) / Config.BIRTH_WEIGHT_TOTAL
	var requested := clampf(target, lo, hi)
	var result := row.duplicate()
	if remaining > 0 and metric != "mean":
		var high_units := clampi(roundi(requested * Config.PERCENT_SCALE) - rare, 0, remaining)
		var low := _summary_scale(row.slice(0, split), remaining - high_units, split - 1)
		var high := _summary_scale(row.slice(split, locked_from), high_units, 0)
		for i in split:
			result[i] = low[i]
		for i in locked_from - split:
			result[i + split] = high[i]
	elif remaining > 0:
		var lower := -4.0
		var upper := 4.0
		for iteration in 64:
			var tilt := (lower + upper) * 0.5
			var weights := []
			for i in 8:
				weights.append(maxf(float(row[i]), 0.001) * exp(clampf(tilt * (float(means[i]) - requested), -250.0, 250.0)))
			var ordinary := normalise(weights, remaining)
			for i in 8:
				result[i] = ordinary[i]
			if Config.row_mean_potential(result) < requested:
				lower = tilt
			else:
				upper = tilt
	var actual := Config.row_mean_potential(result) if metric == "mean" else Config.row_probability(result, {"pa70": 70, "pa80": 80, "pa90": 90}[metric]) * 100.0
	return {"ok": true, "row": result, "actual": actual, "clamped": target < lo or target > hi, "min": lo, "max": hi}


static func _summary_scale(source: Array, total: int, fallback: int) -> Array:
	var weights := source.duplicate()
	if weights.reduce(func(a, b): return a + b, 0) == 0:
		weights[fallback] = 1
	return normalise(weights, total)


static func summary_limits(row: Array, metric: String) -> Dictionary:
	if metric == "pa100":
		return {"min": 0.0, "max": 100.0}
	if _summary_means.is_empty():
		_summary_means = band_means()
	var rare := 0
	var tail := 0.0
	for i in range(10 if metric == "pa90" else 8, row.size()):
		rare += int(row[i])
		tail += float(row[i]) * float(_summary_means[i]) / Config.BIRTH_WEIGHT_TOTAL
	var remaining := Config.BIRTH_WEIGHT_TOTAL - rare
	return {"min": float(rare) / Config.PERCENT_SCALE, "max": 100.0} if metric != "mean" else {
		"min": tail + float(remaining) * float(_summary_means[0]) / Config.BIRTH_WEIGHT_TOTAL,
		"max": tail + float(remaining) * float(_summary_means[7]) / Config.BIRTH_WEIGHT_TOTAL}
