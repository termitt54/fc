class_name Migration
extends RefCounted
## Base contract for a single schema migration.


func get_version() -> int:
	return 0


func get_migration_name() -> String:
	return ""


func up(_db: Node) -> bool:
	return false
