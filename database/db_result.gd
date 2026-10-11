class_name DbResult
extends RefCounted


static func ok(data: Variant = null) -> Dictionary:
	return {
		"success": true,
		"data": data if data != null else {},
		"error": "",
	}


static func ok_list(items: Array = []) -> Dictionary:
	return {
		"success": true,
		"data": items,
		"error": "",
	}


static func fail(error: String, data: Variant = null) -> Dictionary:
	return {
		"success": false,
		"data": data if data != null else {},
		"error": error,
	}
