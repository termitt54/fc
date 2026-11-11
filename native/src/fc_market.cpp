#include "fc_sim_core.h"
#include <godot_cpp/variant/utility_functions.hpp>
namespace godot {
namespace {
int iv(const Dictionary& d, const char* key, int fallback = 0) {
    return int(int64_t(d.get(key, fallback)));
}
double dv(const Dictionary& d, const char* key, double fallback = 0) {
    return double(d.get(key, fallback));
}
Array characters(const Dictionary& p, const Array& valid) {
    Array out;
    Variant raw = p.get("characters", Variant());
    if (raw.get_type() == Variant::ARRAY) {
        Array a = raw;
        for (int j = 0; j < a.size(); ++j)
            if (valid.has(a[j]) && !out.has(a[j]))
                out.append(a[j]);
    if (out.size() > 1)
        out.resize(1);
    }
    if (out.is_empty()) {
        String old = String(p.get("archetype", "")).strip_edges();
        if (valid.has(old))
            out.append(old);
    }
    return out;
}
double sporting(int ca) {
    return std::clamp(ca <= 50 ? double(ca) * 8.0 : 400.0 + double(ca - 50) * 14.0, 0.0, 1000.0);
}
} // namespace
int64_t FCSimCore::market_amount(String operation, Dictionary args) {
    Dictionary constants = data["market_constants"];
    auto c = [&](const char* key) { return double(constants[key]); };
    auto band = [&](const char* name, const char* tail, int age) {
        Array rows = constants[name];
        for (int j = 0; j < rows.size(); ++j) {
            Array row = rows[j];
            if (age <= int(int64_t(row[0])))
                return double(row[1]);
        }
        return c(tail);
    };
    auto rounded = [](double value, int step) {
        return value <= 0 ? int64_t(0) : int64_t(std::round(value / double(step))) * step;
    };
    auto wage = [&](double ability, int rep, int age) {
        double raw =
            c("WAGE_AT_PIVOT") *
            UtilityFunctions::pow(std::max(ability, 1.0) / c("ABILITY_PIVOT"), c("WAGE_ABILITY_EXP")) *
            UtilityFunctions::pow(double(std::max(std::clamp(rep, 0, 1000), 1)) / c("REPUTATION_PIVOT"),
                                  c("WAGE_REPUTATION_EXP")) *
            band("WAGE_AGE_BANDS", "WAGE_AGE_TAIL", age);
        return std::max(int64_t(c("WAGE_FLOOR")), rounded(raw, c("WAGE_STEP")));
    };
    int ca = iv(args, "ability"), rep = iv(args, "reputation"), age = iv(args, "age");
    if (operation == "wage")
        return wage(dv(args, "ability"), rep, age);
    if (operation == "value") {
        double current = std::clamp(ca, 0, 100),
               potential = std::clamp(std::max(iv(args, "potential"), ca), 0, 100);
        double effective =
            current + (potential - current) * band("POTENTIAL_AGE_BANDS", "POTENTIAL_AGE_TAIL", age);
        return std::max(int64_t(c("VALUE_FLOOR")), rounded(double(wage(effective, rep, age)) *
                                                               band("VALUE_AGE_BANDS", "VALUE_AGE_TAIL", age),
                                                           c("VALUE_STEP")));
    }
    if (operation == "coach_wage") {
        double raw =
            c("COACH_WAGE_AT_PIVOT") *
            UtilityFunctions::pow(std::max(double(ca), 1.0) / c("ABILITY_PIVOT"),
                                  c("COACH_WAGE_ABILITY_EXP")) *
            UtilityFunctions::pow(double(std::max(std::clamp(rep, 0, 1000), 1)) / c("REPUTATION_PIVOT"),
                                  c("COACH_WAGE_REPUTATION_EXP"));
        if (age >= c("COACH_VETERAN_AGE"))
            raw *= c("COACH_VETERAN_FACTOR");
        return std::max(int64_t(c("COACH_WAGE_FLOOR")), rounded(raw, c("WAGE_STEP")));
    }
    if (operation == "target_reputation") {
        double from = double(std::clamp(ca, 0, 100)) / 100.0 * c("REPUTATION_FROM_ABILITY"),
               club = std::clamp(rep, 0, 1000);
        return std::clamp(
            int(std::round(from * c("REPUTATION_ABILITY_WEIGHT") + club * c("REPUTATION_CLUB_WEIGHT"))), 0,
            1000);
    }
    if (operation == "move") {
        Dictionary p = args["player"], club = args["club"];
        int ability = iv(p, "current_ability", iv(p, "overall", 50)), p_rep = iv(p, "reputation"),
            p_age = iv(p, "age", 24);
        int64_t current = std::max(0, iv(p, "wage")), personal = wage(ability, p_rep, p_age);
        Dictionary target;
        target["ability"] = ability;
        target["reputation"] = iv(club, "reputation", int(c("REPUTATION_PIVOT")));
        int local = wage(ability, market_amount("target_reputation", target), p_age);
        int64_t offer = std::round(double(personal) * c("MOVE_PERSONAL_WEIGHT") +
                                   double(local) * c("MOVE_LOCAL_WEIGHT")),
                anchor = std::max(current, personal);
        double keep = bool(args.get("free_agent", false)) ? c("MOVE_FREE_KEEP_SHARE") : c("MOVE_KEEP_SHARE");
        if (characters(p, data["characters"]).has("MERCENARY"))
            keep = std::max(keep, 0.90);
        int64_t reservation =
            int64_t(std::ceil(double(anchor) * keep / c("WAGE_STEP"))) * int(c("WAGE_STEP"));
        int64_t ceiling =
            std::round(double(std::max(current, int64_t(c("WAGE_FLOOR")))) * c("MOVE_RAISE_CAP"));
        ceiling = std::max({ceiling, personal, reservation});
        return std::max(int64_t(c("WAGE_FLOOR")),
                        rounded(double(std::clamp(offer, reservation, ceiling)), c("WAGE_STEP")));
    }
    return 0;
}
Dictionary FCSimCore::offer_profile(Dictionary player, int64_t world_top) {
    Dictionary out;
    int ability = iv(player, "current_ability", iv(player, "overall", 50));
    Array chars = characters(player, data["characters"]);
    out["reputation"] = iv(player, "reputation");
    out["ability"] = ability;
    out["age"] = iv(player, "age", 24);
    out["characters"] = chars;
    out["free_years"] = iv(player, "free_agent_seasons");
    out["club_id"] = iv(player, "club_id");
    out["wage"] = iv(player, "wage");
    bool ambitious = chars.has("AMBITIOUS");
    double veteran = std::min(double(std::max(0, iv(out, "age") - 31)) * 12.0, 84.0),
           unemployment = double(std::min(iv(out, "free_years"), 3)) * 35.0;
    double flexibility = 100.0 + veteran + unemployment - (ambitious ? 40.0 : 0.0),
           desired = sporting(ability);
    if (world_top > 0)
        desired = std::min(desired, double(world_top) + 60.0);
    desired = std::max(double(iv(out, "reputation")), desired);
    out["flexibility"] = flexibility;
    out["desired"] = desired;
    out["minimum_club_reputation"] = desired - flexibility;
    out["minimum_squad_ability"] =
        double(ability) - (ambitious ? 18.0 : 25.0) - unemployment / 10.0 - veteran / 10.0;
    return out;
}
double FCSimCore::club_attraction(Dictionary club) const {
    double prestige = dv(club, "reputation", 500);
    Dictionary rating = club.get("club_elo", Dictionary());
    if (String(attraction_settings.get("mode", "BOUNDED")) == "WEIGHTS") {
        double elo = std::max(0.0, dv(rating, "elo", prestige));
        return std::max(0.0, prestige * dv(attraction_settings, "reputation_weight", 50.0) / 100.0 +
                             elo * dv(attraction_settings, "elo_weight", 50.0) / 100.0);
    }
    double matches = dv(attraction_settings, "confidence_matches", 20.0);
    double confidence = matches > 0 ? std::clamp(dv(rating, "games") / matches, 0.0, 1.0) : 1.0;
    double sporting = dv(rating, "sporting_reputation", prestige);
    double limit = dv(attraction_settings, "max_effect", 60.0);
    return std::clamp(prestige + std::clamp((sporting - prestige) * 0.25, -limit, limit) * confidence, 0.0, 1000.0);
}
Dictionary FCSimCore::evaluate_offer(Dictionary player, Dictionary club, int64_t negotiations,
                                     Dictionary context) {
    double rep = club_attraction(club);
    Array chars = player["characters"];
    bool ambitious = chars.has("AMBITIOUS"), staying = context.get("renewal", false);
    double flexibility = dv(player, "flexibility") + double(negotiations - 10) * 2.0,
           desired = dv(player, "desired");
    if (staying)
        flexibility += 100.0;
    if (staying && chars.has("LOYAL"))
        flexibility += 160.0;
    double source = dv(context, "source_reputation"), downgrade = source - rep;
    String reason;
    if (desired - rep > flexibility)
        reason = "club_prestige";
    else if (!staying && source > 0 && downgrade > flexibility + (ambitious ? 0.0 : 80.0))
        reason = "sporting_downgrade";
    double quality = dv(context, "squad_ability", -1), offer = dv(context, "offer_wage", -1),
           salary = dv(player, "wage") * (chars.has("MERCENARY") ? 0.90 : 0.70);
    if (reason.is_empty() && quality >= 0 && quality < dv(player, "minimum_squad_ability"))
        reason = "squad_level";
    if (reason.is_empty() && offer >= 0 && offer < salary)
        reason = "salary";
    Dictionary out;
    if (!reason.is_empty()) {
        out["accepted"] = false;
        out["score"] = -1.0;
        out["reason"] = reason;
        return out;
    }
    String role = context.get("role", "rotation");
    double bonus = role == "first_team" ? 20.0 : (role == "reserve" ? -20.0 : 0.0);
    out["accepted"] = true;
    out["reason"] = "acceptable";
    out["score"] = rep * 0.5 + std::max(quality, 0.0) + bonus - std::max(downgrade, 0.0) * 0.10;
    return out;
}
double FCSimCore::contract_chance(Dictionary player, Dictionary club, int64_t negotiations,
                                  Dictionary context) {
    int ability = iv(player, "current_ability", iv(player, "overall", 50));
    Dictionary args;
    args["ability"] = ability;
    args["reputation"] = iv(player, "reputation");
    args["age"] = iv(player, "age", 24);
    int64_t expected = market_amount("wage", args),
            retained = std::ceil(dv(player, "wage") * (bool(context.get("key_player", false)) ? 1.10 : 1.0));
    Dictionary offer;
    offer["renewal"] = true;
    offer["offer_wage"] = std::max(expected, retained);
    offer["world_top_reputation"] = iv(context, "world_top_reputation");
    Dictionary willingness =
        evaluate_offer(offer_profile(player, iv(context, "world_top_reputation")), club, negotiations, offer);
    if (!bool(willingness["accepted"]))
        return 0;
    double gap = double(std::clamp(iv(player, "reputation"), 0, 1000)) -
                 club_attraction(club),
           chance = 0.62 - std::clamp(gap / 400.0, -0.25, 0.45);
    Array chars = characters(player, data["characters"]);
    if (chars.has("LOYAL"))
        chance += 0.18;
    if (chars.has("AMBITIOUS") && gap > 50.0)
        chance -= 0.12;
    if (chars.has("MERCENARY") && expected > 0 &&
        double(std::max(0, iv(player, "wage"))) < double(expected) * 0.9)
        chance -= 0.12;
    chance += double(negotiations - 10) * 0.025;
    if (bool(context.get("key_player", false)))
        chance += 0.15;
    return std::clamp(chance, 0.08, 0.97);
}
double FCSimCore::reputation_calc(String operation, Dictionary args) {
    Dictionary constants = data["reputation_constants"];
    auto c = [&](const char* key) { return double(constants[key]); };
    double strength = iv(args, "strength"), current = iv(args, "current"),
           participants = dv(args, "participants", -1), reference = strength * c("LEVEL_REFERENCE_RATIO");
    if (participants >= 0)
        reference = (reference + std::clamp(participants, 0.0, 1000.0)) * 0.5;
    double headroom =
        std::clamp((std::min(1000.0, reference + c("ACHIEVEMENT_HEADROOM")) - current) / 100.0, 0.0, 1.0);
    if (operation == "headroom")
        return headroom;
    if (operation == "chance_step") {
        double chance = std::clamp(dv(args, "chance") / 100.0, 0.0, 1.0);
        return (bool(args.get("won", false)) ? 1.0 - chance : -chance) * c("SURPRISE_SPAN") *
               std::clamp(strength / 1000.0, 0.0, 1.0);
    }
    int actual = iv(args, "actual"), field = iv(args, "field");
    if (operation == "table_step") {
        if (field < 2 || actual < 1)
            return 0;
        int predicted = iv(args, "predicted");
        double surprise =
            std::clamp(double((predicted >= 1 ? predicted : actual) - actual) / double(field - 1), -1.0,
                       1.0) *
            c("SURPRISE_SPAN") * std::clamp(strength / 1000.0, 0.0, 1.0);
        return surprise > 0 ? surprise * headroom : surprise;
    }
    if (operation == "bonus") {
        double base =
            actual == 1 ? 8.0 : (actual == 2 ? 4.0 : (actual == 3 ? 2.0 : (actual == 4 ? 1.0 : 0.0)));
        return base * (0.5 + 0.5 * std::clamp(strength / 1000.0, 0.0, 1.0)) * headroom;
    }
    if (operation == "pull") {
        if (field < 2 || actual < 1)
            return 0;
        double percentile = 1.0 - double(actual - 1) / double(field - 1),
               target = std::clamp(reference + c("FINISH_SPAN") * (2.0 * percentile - 1.0), 0.0, 1000.0);
        return std::clamp(int(std::round((target - current) * c("LEVEL_RATE"))), -int(c("LEVEL_PULL")),
                          int(c("LEVEL_PULL")));
    }
    if (operation == "combine") {
        Array parts = args["parts"];
        double step = 0;
        int best_strength = -1, best_priority = -1, pull = 0;
        for (int j = 0; j < parts.size(); ++j) {
            if (parts[j].get_type() != Variant::DICTIONARY)
                continue;
            Dictionary part = parts[j];
            step += dv(part, "step");
            int s = iv(part, "strength"), priority = bool(part.get("table_anchor", false)) ? 1 : 0;
            if (priority > best_priority || (priority == best_priority && s > best_strength)) {
                best_priority = priority;
                best_strength = s;
                pull = iv(part, "pull");
            }
        }
        return std::clamp(int(std::round(step)) + pull, -int(c("CLUB_CAP")), int(c("CLUB_CAP")));
    }
    if (operation == "player") {
        int matches = iv(args, "matches");
        if (matches < 1)
            return 0;
        int minutes = iv(args, "minutes", -1), played = minutes >= 0 ? minutes : matches * 50;
        double share = std::clamp(double(played) / std::max(dv(args, "season_minutes", 1200), 1.0), 0.0, 1.0),
               expected = 6.15 + double(iv(args, "ability") - 50) * 0.025,
               gap = std::clamp(dv(args, "rating") - expected, -1.6, 1.6),
               weight = std::clamp(strength / 1000.0, 0.0, 1.0), personal = gap / 1.6 * 8.0 * share * weight,
               recognition = std::clamp(
                   double(iv(args, "ability")) * 10.0 * (0.45 + 0.55 * weight) + gap * 50.0, 0.0, 1000.0);
        int rep = iv(args, "reputation", -1);
        if (rep >= 0)
            personal += std::clamp((recognition - double(rep)) * 0.04, -10.0, 10.0) * share;
        double spill = double(iv(args, "club_delta")) * c("PLAYER_SPILL") * share;
        return std::clamp(int(std::round(personal + spill)), -int(c("PLAYER_RESULT_CAP")),
                          int(c("PLAYER_RESULT_CAP")));
    }
    return 0;
}
} // namespace godot
