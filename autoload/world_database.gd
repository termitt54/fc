extends Node
## Service for the global world template database (user://database/world.db).

const WORLD_DB_DIR := "user://database"
const WORLD_DB_PATH := "user://database/world.db"

## Only the destructive database test may repoint these, and only at a scratch
## directory. Everything in the real world lives under WORLD_DB_DIR: countries,
## clubs, competitions and the flag/logo files next to them.
var db_dir: String = WORLD_DB_DIR
var db_path: String = WORLD_DB_PATH
const MIGRATION_016_DIVISIONS_RULES := preload(
	"res://database/migrations/world_migration_016_divisions_rules.gd"
)
const MIGRATION_017_DIVISIONS_MOVEMENT := preload(
	"res://database/migrations/world_migration_017_divisions_movement.gd"
)
const MIGRATION_018_RANKING_ORDER := preload(
	"res://database/migrations/world_migration_018_ranking_order.gd"
)
const MIGRATION_019_REGULAR_SEASON := preload(
	"res://database/migrations/world_migration_019_regular_season.gd"
)
const MIGRATION_020_MOVEMENT_SCOPE := preload(
	"res://database/migrations/world_migration_020_movement_scope.gd"
)
const MIGRATION_021_PLAYOFF_RULES := preload(
	"res://database/migrations/world_migration_021_playoff_rules.gd"
)
const MIGRATION_022_COUNTRY_NAMES := preload(
	"res://database/migrations/world_migration_022_country_names.gd"
)
const MIGRATION_023_COUNTRY_YOUTH_TALENT := preload(
	"res://database/migrations/world_migration_023_country_youth_talent.gd"
)
const MIGRATION_024_DISCIPLINE_RULES := preload(
	"res://database/migrations/world_migration_024_discipline_rules.gd"
)
const MIGRATION_025_PRIZE_RULES := preload(
	"res://database/migrations/world_migration_025_prize_rules.gd"
)
const MIGRATION_026_YOUTH_TALENT_SCALE := preload(
	"res://database/migrations/world_migration_026_youth_talent_scale.gd"
)
const MIGRATION_027_DIVISION_STRENGTH := preload(
	"res://database/migrations/world_migration_027_division_strength.gd"
)

enum State {
	CLOSED,
	OPEN,
	MIGRATED,
	READY,
	ERROR,
}

var _state: State = State.CLOSED
var _last_error: String = ""
var _migration_manager := MigrationManager.new()


func _ready() -> void:
	initialize()


func initialize() -> bool:
	_last_error = ""
	_state = State.CLOSED

	if not _ensure_database_directory():
		_state = State.ERROR
		return false

	if not DatabaseManager.open_database(db_path):
		_last_error = DatabaseManager.get_last_error()
		_state = State.ERROR
		push_error("[WorldDatabase] %s" % _last_error)
		return false

	_state = State.OPEN
	print("[WorldDatabase] Database opened: %s" % db_path)

	var migrations: Array = [
		WorldMigration001System.new(),
		WorldMigration002Geography.new(),
		WorldMigration003Clubs.new(),
		WorldMigration004Competitions.new(),
		WorldMigration005SeedContinents.new(),
		WorldMigration006CountriesV2.new(),
		WorldMigration007YouthRatingDistribution.new(),
		WorldMigration008CountryYouthDistribution.new(),
		WorldMigration009YouthWeightDecimals.new(),
		WorldMigration010ClubsFacilities.new(),
		WorldMigration011ClubReputation.new(),
		WorldMigration012CompetitionCard.new(),
		WorldMigration013CompetitionUnits.new(),
		WorldMigration014UnitClubs.new(),
		WorldMigration015UnitLogo.new(),
		MIGRATION_016_DIVISIONS_RULES.new(),
		MIGRATION_017_DIVISIONS_MOVEMENT.new(),
		MIGRATION_018_RANKING_ORDER.new(),
		MIGRATION_019_REGULAR_SEASON.new(),
		MIGRATION_020_MOVEMENT_SCOPE.new(),
		MIGRATION_021_PLAYOFF_RULES.new(),
		MIGRATION_022_COUNTRY_NAMES.new(),
		MIGRATION_023_COUNTRY_YOUTH_TALENT.new(),
		MIGRATION_024_DISCIPLINE_RULES.new(),
		MIGRATION_025_PRIZE_RULES.new(),
		MIGRATION_026_YOUTH_TALENT_SCALE.new(),
		MIGRATION_027_DIVISION_STRENGTH.new(),
	]

	if not _migration_manager.migrate(DatabaseManager, migrations):
		_last_error = DatabaseManager.get_last_error()
		if _last_error.is_empty():
			_last_error = "Migration failed"
		_state = State.ERROR
		push_error("[WorldDatabase] Initialization failed during migrations")
		return false

	_state = State.MIGRATED

	if not _validate_world_meta():
		_state = State.ERROR
		return false

	_state = State.READY
	print("[WorldDatabase] World database is ready")
	return true


func is_ready() -> bool:
	return _state == State.READY and DatabaseManager.is_open()


func is_open() -> bool:
	return DatabaseManager.is_open() and (
		_state == State.OPEN
		or _state == State.MIGRATED
		or _state == State.READY
	)


func are_migrations_applied() -> bool:
	return _state == State.MIGRATED or _state == State.READY


func has_error() -> bool:
	return _state == State.ERROR


func get_state() -> State:
	return _state


func get_last_error() -> String:
	return _last_error


func get_database_path() -> String:
	return db_path


func get_world_name() -> String:
	if not DatabaseManager.is_open():
		return ""
	var rows: Array = DatabaseManager.query_rows(
		"SELECT world_name FROM world_meta WHERE id = 1 LIMIT 1;"
	)
	if rows.is_empty():
		return ""
	return str(rows[0].get("world_name", ""))


func get_status_text() -> String:
	match _state:
		State.READY:
			return "База готова"
		State.ERROR:
			return "Ошибка базы"
		State.OPEN, State.MIGRATED:
			return "База открыта"
		_:
			return "База не открыта"


func close() -> void:
	DatabaseManager.close_database()
	_state = State.CLOSED


func _ensure_database_directory() -> bool:
	if DirAccess.dir_exists_absolute(db_dir):
		return true

	var err := DirAccess.make_dir_recursive_absolute(db_dir)
	if err != OK:
		_last_error = "Failed to create directory '%s' (error %d)" % [db_dir, err]
		push_error("[WorldDatabase] %s" % _last_error)
		return false

	return true


func _validate_world_meta() -> bool:
	var rows: Array = DatabaseManager.query_rows(
		"SELECT id, world_name FROM world_meta WHERE id = 1 LIMIT 1;"
	)
	if rows.is_empty():
		_last_error = "world_meta row with id = 1 is missing"
		push_error("[WorldDatabase] %s" % _last_error)
		return false
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if DatabaseManager != null and DatabaseManager.is_open():
			DatabaseManager.close_database()
