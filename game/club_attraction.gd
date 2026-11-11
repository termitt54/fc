extends RefCounted
## Recruitment-only projection. Never changes saved prestige or match attributes.
const Config = preload("res://game/club_attraction_config.gd")
const ELO_WEIGHT := 0.25
const MAX_EFFECT := 60.0
const CONFIDENCE_MATCHES := 20.0

static func value(club: Dictionary) -> float:
	return value_with_settings(club, Config.runtime_values())

static func value_with_settings(club: Dictionary, settings: Dictionary) -> float:
	var prestige := float(club.get("reputation", 500))
	var rating: Dictionary = club.get("club_elo", {})
	if str(settings.get("mode", Config.MODE_BOUNDED)) == Config.MODE_WEIGHTS:
		var elo := maxf(0.0, float(rating.get("elo", prestige)))
		return maxf(0.0, prestige * float(settings.get("reputation_weight", 50.0)) / 100.0 + elo * float(settings.get("elo_weight", 50.0)) / 100.0)
	var matches := float(settings.get("confidence_matches", CONFIDENCE_MATCHES))
	var confidence := clampf(float(rating.get("games", 0)) / matches, 0.0, 1.0) if matches > 0 else 1.0
	var sporting := float(rating.get("sporting_reputation", prestige))
	var limit := float(settings.get("max_effect", MAX_EFFECT))
	return clampf(prestige + clampf((sporting - prestige) * ELO_WEIGHT, -limit, limit) * confidence, 0.0, 1000.0)

static func description() -> String:
	var settings := Config.runtime_values()
	if str(settings.mode) == Config.MODE_WEIGHTS:
		return "Репутация %.0f%% + Elo %.0f%%. Зарплата, роль и качество состава учитываются отдельно." % [float(settings.reputation_weight), float(settings.elo_weight)]
	return "Репутация с поправкой Elo до ±%.0f. Полное влияние после %.0f отслеженных матчей (0 — сразу)." % [float(settings.max_effect), float(settings.confidence_matches)]
