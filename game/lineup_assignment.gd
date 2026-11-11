extends RefCounted
## Rectangular maximum-weight assignment. Rows are roles, columns are players.
## Padding columns represent missing players; no team strength enters a match.
static func solve(weights: Array) -> PackedInt32Array:
	var rows := weights.size()
	if rows==0: return PackedInt32Array()
	var columns: int=weights[0].size()
	if columns<rows: return PackedInt32Array()
	var u := PackedFloat64Array()
	var v := PackedFloat64Array()
	var matched := PackedInt32Array()
	var way := PackedInt32Array()
	u.resize(rows+1)
	v.resize(columns+1)
	matched.resize(columns+1)
	way.resize(columns+1)
	for row in range(1,rows+1):
		matched[0]=row
		var column := 0
		var minimum := PackedFloat64Array()
		var used := PackedByteArray()
		minimum.resize(columns+1)
		minimum.fill(INF)
		used.resize(columns+1)
		while true:
			used[column]=1
			var active := matched[column]
			var delta := INF
			var next := 0
			for j in range(1,columns+1):
				if used[j]: continue
				var cost := -float(weights[active-1][j-1])-u[active]-v[j]
				if cost<minimum[j]:
					minimum[j]=cost
					way[j]=column
				if minimum[j]<delta:
					delta=minimum[j]
					next=j
			for j in range(columns+1):
				if used[j]:
					u[matched[j]]+=delta
					v[j]-=delta
				else: minimum[j]-=delta
			column=next
			if matched[column]==0: break
		while true:
			var previous := way[column]
			matched[column]=matched[previous]
			column=previous
			if column==0: break
	var result := PackedInt32Array()
	result.resize(rows)
	result.fill(-1)
	for j in range(1,columns+1):
		if matched[j]>0: result[matched[j]-1]=j-1
	return result
