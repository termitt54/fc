extends Node

var failed := 0
var passed := 0

func _ready() -> void:
	var star := {"id": 901, "position": "GK", "age": 25, "current_ability": 90, "reputation": 900, "wage": 1000000, "club_id": 0, "nationality_country_id": 1, "characters": []}
	var weak := {"id": 1, "country_id": 1, "reputation": 200}
	var strong := {"id": 1, "country_id": 1, "reputation": 900}
	var coach := {"attributes": {"negotiations": 20, "transfers": 20}}
	check(not PlayerOffer.evaluate(star, weak, coach)["accepted"], "an elite free agent refuses a weak club even with an expert coach")
	check(PlayerOffer.evaluate(star, strong, coach, {"squad_ability": 80})["accepted"], "a strong suitable club remains attractive")
	check(not PlayerOffer.evaluate(star, strong, coach, {"squad_ability": 50})["accepted"], "prestige cannot conceal a weak squad")
	check(not PlayerOffer.evaluate(star, strong, coach, {"offer_wage": 100000})["accepted"], "underpayment is rejected")
	var ordinary := star.duplicate(true)
	ordinary["current_ability"] = 50
	ordinary["reputation"] = 350
	check(PlayerOffer.evaluate(ordinary, {"reputation": 300}, coach)["accepted"], "ordinary players can still join ordinary clubs")
	check(not PlayerOffer.evaluate(ordinary, weak, coach, {"source_reputation": 900})["accepted"], "a large sporting downgrade is rejected")
	var forgotten := star.duplicate(true)
	forgotten["free_agent_seasons"] = 3
	check(PlayerOffer.evaluate(forgotten, {"reputation": 780}, coach, {"squad_ability": 80})["accepted"], "long unemployment permits a reasonable concession")
	check(not PlayerOffer.evaluate(forgotten, weak, coach)["accepted"], "unemployment does not permit an absurd prestige gap")
	var rising := star.duplicate(true)
	rising["current_ability"] = 88
	rising["reputation"] = 503
	check(not PlayerOffer.evaluate(rising, {"reputation": 586}, coach)["accepted"], "high ability prevents low-fame elite players joining weak clubs")
	check(PlayerOffer.evaluate(rising, {"reputation": 903}, coach)["accepted"], "a rising elite player accepts a leading club")
	ordinary["characters"] = [PlayerTypes.CHAR_MERCENARY]
	var wage := PlayerMarket.wage_for_move(ordinary, weak, true)
	check(wage >= 900000, "the signed salary respects mercenary reservation")
	for indexed in [false, true]:
		GameSession.clear()
		GameSession.players_by_club[1] = []
		GameSession.free_agents = [star.duplicate(true)]
		GameSession.coaches_by_club[1] = coach
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var index := TransferMarket._build_agent_index(GameSession.free_agents) if indexed else {}
		check(not TransferMarket._try_sign(GameSession, rng, 1, weak, [], "GK", false, false, index), "free-agent recruitment rejects star, indexed=%s" % indexed)
		check(GameSession.get_club_players(1).is_empty(), "refusal leaves the destination unchanged")
		check(TransferMarket._try_sign(GameSession, rng, 1, strong, [], "GK", false, false, index), "same star can sign at a suitable club")
		check(int(GameSession.get_club_players(1)[0]["wage"]) >= 700000, "actual signing preserves the salary floor")
	GameSession.clear()
	GameSession.coaches_by_club = {1: {"attributes": {"transfers": 20}}, 2: {"attributes": {"transfers": 4}}}
	var order_rng := RandomNumberGenerator.new()
	order_rng.seed = 42
	var other_rng := RandomNumberGenerator.new();other_rng.seed=order_rng.seed
	check(TransferMarket._club_pick_order(GameSession, {1: {"reputation": 200}, 2: {"reputation": 900}}, order_rng)==TransferMarket._club_pick_order(GameSession, {1: {"reputation":900},2:{"reputation":200}},other_rng),"club prestige does not grant first access to a shared player pool")
	var low_fame_star := star.duplicate(true)
	low_fame_star["current_ability"] = 92
	low_fame_star["reputation"] = 530
	check(PlayerOffer.evaluate(low_fame_star, {"reputation": 820}, coach, {"world_top_reputation": 820, "squad_ability": 79})["accepted"], "CA92 player can join an actual world leader without three idle years")
	check(not PlayerOffer.evaluate(low_fame_star, {"reputation": 500}, coach, {"world_top_reputation": 820, "squad_ability": 79})["accepted"], "world calibration still rejects an ordinary club")
	check(not PlayerOffer.evaluate(low_fame_star, {"reputation": 820}, coach, {"world_top_reputation": 820, "squad_ability": 50})["accepted"], "world leader must have a sufficiently strong squad")
	check(not PlayerOffer.evaluate(star, {"reputation": 650}, coach, {"world_top_reputation": 650, "squad_ability": 80})["accepted"], "public fame is not lowered to manufacture agreement")
	GameSession.clear()
	print("PLAYER OFFER: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("PASS: " if ok else "FAIL: ") + label)
