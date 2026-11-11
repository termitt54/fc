class_name ActionRules
extends RefCounted
## Skill units are 1..20. These functions describe individual actions, never teams.
const PITCH_LENGTH := 60.0
const PITCH_WIDTH := 40.0
const GOAL_WIDTH := 5.0
const GOAL_HEIGHT := 2.0
const PENALTY_DISTANCE := 8.0
const OFFSIDE := false
const DUEL_SLOPE := 0.15
# These alter the choice to shoot, never the outcome of a shot.
const STYLE_SHOT_PREFERENCE := {"attacking":0.65,"defensive":0.59}
const MIDFIELD_ATTACK_DEPTH_BASE := 0.505
const MIDFIELD_ATTACK_DEPTH_SPAN := 0.39
const DEFENDER_ATTACK_RUN_SPAN := 0.86

static func duel(own: float, opposing: float, influence: float = 1.0) -> float:
	return 1.0 / (1.0 + exp(clampf((opposing - own) * DUEL_SLOPE * influence, -12.0, 12.0)))

static func running_speed(skill: float, freshness: float = 1.0) -> float:
	return (3.0 + 0.2 * skill) * (0.5 + 0.5 * freshness)

static func reaction_delay(skill: float) -> float:
	return 0.48 - 0.017 * skill

static func trap_time(skill: float) -> float:
	return 0.08 + (21.0 - skill) * 0.035

static func shot_sigma(skill: float, distance: float, penalty: bool = false) -> float:
	if penalty:
		return 0.12 + 0.007 * pow(20.0 - skill,2)
	return (0.18 + 2.6 * pow(maxf(0.0, 1.0 - skill / 20.0), 1.3)) * maxf(0.5, distance / 12.0)

## 0 = off target, 1 = saved, 2 = goal. Dimensions and flight decide the result.
static func penalty_trial(penalties: float, reflexes: float, positioning: float, rng: RandomNumberGenerator, accuracy: float = 1.0, has_keeper: bool = true) -> int:
	var sigma := shot_sigma(penalties,PENALTY_DISTANCE,true)/maxf(accuracy,0.1)
	var target := (-1.0 if rng.randf()<0.5 else 1.0)*(1.6+0.03*penalties)*GOAL_WIDTH/5.0+rng.randfn(0,sigma)
	var height := 0.25+rng.randf()*1.5+rng.randfn(0,sigma*0.15)
	if absf(target)>GOAL_WIDTH/2 or height<0 or height>GOAL_HEIGHT: return 0
	if not has_keeper: return 2
	var available := maxf(0.0,PENALTY_DISTANCE/(14+0.4*penalties)-reaction_delay(reflexes))
	var stance := (-1.0 if rng.randf()<0.5 else 1.0)*(0.9+0.025*positioning)
	return 1 if absf(target-stance)<=0.45+4*available and height<=1.2+1.8*available else 2
