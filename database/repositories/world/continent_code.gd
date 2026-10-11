class_name ContinentCode
extends RefCounted
## Normalization helpers for continent system codes.


static func normalize(raw_value: String) -> String:
	var value := raw_value.strip_edges().to_upper()
	value = value.replace("-", "_").replace(" ", "_")

	var result := ""
	var previous_underscore := false
	for i in value.length():
		var ch := value[i]
		var is_letter := ch >= "A" and ch <= "Z"
		var is_digit := ch >= "0" and ch <= "9"
		if is_letter or is_digit:
			result += ch
			previous_underscore = false
		elif ch == "_":
			if result.is_empty() or previous_underscore:
				continue
			result += "_"
			previous_underscore = true

	while result.begins_with("_"):
		result = result.substr(1)
	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)

	return result


static func is_valid(code: String) -> bool:
	if code.is_empty():
		return false
	if code[0] >= "0" and code[0] <= "9":
		return false
	for i in code.length():
		var ch := code[i]
		var is_letter := ch >= "A" and ch <= "Z"
		var is_digit := ch >= "0" and ch <= "9"
		if not (is_letter or is_digit or ch == "_"):
			return false
	return true
