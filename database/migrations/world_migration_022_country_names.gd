class_name WorldMigration022CountryNames
extends Migration
## Per-country first/last name pools for player generation.


const KIND_FIRST := "FIRST"
const KIND_LAST := "LAST"

## Seed for RUS if present (same pool that was hardcoded in PlayerGenerator).
const SEED_FIRST := [
	"Алекс", "Борис", "Виктор", "Глеб", "Даниил", "Егор", "Илья", "Кирилл",
	"Лев", "Максим", "Никита", "Олег", "Павел", "Роман", "Сергей", "Тимур",
	"Фёдор", "Юрий", "Антон", "Денис", "Игорь", "Артём", "Матвей", "Степан",
]

const SEED_LAST := [
	"Иванов", "Смирнов", "Кузнецов", "Попов", "Васильев", "Петров", "Соколов",
	"Михайлов", "Новиков", "Фёдоров", "Морозов", "Волков", "Алексеев", "Лебедев",
	"Семёнов", "Егоров", "Павлов", "Козлов", "Степанов", "Николаев", "Орлов",
	"Андреев", "Макаров", "Захаров",
]


func get_version() -> int:
	return 22


func get_migration_name() -> String:
	return "country_names"


func up(db: Node) -> bool:
	var create_sql := """
	CREATE TABLE IF NOT EXISTS country_names (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		country_id INTEGER NOT NULL,
		kind TEXT NOT NULL
			CHECK (kind IN ('FIRST', 'LAST')),
		name TEXT NOT NULL,
		UNIQUE (country_id, kind, name),
		FOREIGN KEY (country_id) REFERENCES countries(id) ON DELETE CASCADE
	);
	"""
	if not db.execute(create_sql):
		return false

	if not db.execute("""
		CREATE INDEX IF NOT EXISTS idx_country_names_country_kind
		ON country_names(country_id, kind);
	"""):
		return false

	return _seed_rus_if_empty(db)


func _seed_rus_if_empty(db: Node) -> bool:
	var rows: Array = db.query_rows(
		"""
		SELECT id FROM countries
		WHERE abbreviation = 'RUS'
		LIMIT 1;
		"""
	)
	if rows.is_empty():
		return true

	var country_id := int(rows[0].get("id", 0))
	if country_id < 1:
		return true

	var existing: Array = db.query_rows(
		"""
		SELECT COUNT(*) AS cnt
		FROM country_names
		WHERE country_id = ?;
		""",
		[country_id]
	)
	if not existing.is_empty() and int(existing[0].get("cnt", 0)) > 0:
		return true

	for name in SEED_FIRST:
		if not db.execute_with_bindings(
			"""
			INSERT INTO country_names (country_id, kind, name)
			VALUES (?, ?, ?);
			""",
			[country_id, KIND_FIRST, name]
		):
			return false

	for name in SEED_LAST:
		if not db.execute_with_bindings(
			"""
			INSERT INTO country_names (country_id, kind, name)
			VALUES (?, ?, ?);
			""",
			[country_id, KIND_LAST, name]
		):
			return false

	return true
