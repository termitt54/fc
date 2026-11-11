#include "fc_sim_core.h"
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <unordered_map>
namespace godot {
namespace {
int iv(const Dictionary& d, const char* key, int fallback = 0) {
    return int(int64_t(d.get(key, fallback)));
}
Dictionary dict(const Variant& value) {
    return value.get_type() == Variant::DICTIONARY ? Dictionary(value) : Dictionary();
}
struct Own {
    int need = 0;
    std::array<int, 7> counts{};
};
struct Reserve {
    int need = 0;
    std::array<int, 7> supply{}, demand{}, capacity{};
    Own destination, zero;
};
bool blocks(const Reserve& r, const Own& own, int position, const std::array<int, 7>& minimum,
            const std::array<int, 7>& maximum, bool consume = true, bool native = true) {
    int missing = own.need > 0 ? std::max(0, minimum[position] - own.counts[position]) : 0,
        demand = r.demand[position], after = demand - int(missing > 0), available = r.supply[position];
    if (std::max(0, after - available + int(consume)) > std::max(0, demand - available))
        return true;
    int before = 0, later = 0;
    for (int code = 0; code < 7; ++code) {
        int capacity = r.capacity[code], next = capacity;
        if (own.need > 0) {
            int room = std::max(0, maximum[code] - own.counts[code]);
            next += std::min(std::max(0, room - int(code == position)), own.need - int(native)) -
                    std::min(room, own.need);
        }
        before += std::min(r.supply[code], capacity);
        later += std::min(std::max(0, r.supply[code] - int(consume && code == position)), next);
    }
    return std::max(0, r.need - int(own.need > 0 && native) - later) > std::max(0, r.need - before);
}
} // namespace
Dictionary FCSimCore::agent_index(Array agents, int64_t world_top) {
    PackedStringArray positions, raw_positions;
    PackedInt64Array nations;
    PackedFloat64Array reputations, bases, minimum_reputations, minimum_qualities;
    int count = agents.size();
    positions.resize(count);
    raw_positions.resize(count);
    nations.resize(count);
    reputations.resize(count);
    bases.resize(count);
    minimum_reputations.resize(count);
    minimum_qualities.resize(count);
    Dictionary groups;
    Array indices;
    for (int j = 0; j < count; ++j) {
        if (agents[j].get_type() != Variant::DICTIONARY)
            continue;
        Dictionary p = agents[j];
        String pos = position_of(p);
        Dictionary reservations = offer_profile(p, world_top);
        minimum_reputations[j] = double(reservations["minimum_club_reputation"]);
        minimum_qualities[j] = double(reservations["minimum_squad_ability"]);
        positions[j] = pos;
        raw_positions[j] = String(p.get("position", ""));
        nations[j] = iv(p, "nationality_country_id");
        reputations[j] = double(iv(p, "reputation"));
        double ca = iv(p, "current_ability", iv(p, "overall")), pa = iv(p, "potential_ability", int(ca));
        bases[j] = ca * 1.15 + pa * 0.22;
        if (!groups.has(pos))
            groups[pos] = Array();
        Array members = groups[pos];
        members.append(j);
        indices.append(j);
    }
    Dictionary out;
    out["world_top_reputation"] = world_top;
    out["all"] = indices;
    out["positions"] = groups;
    out["consumed"] = Dictionary();
    out["position"] = positions;
    out["raw_position"] = raw_positions;
    out["nation"] = nations;
    out["rep"] = reputations;
    out["base"] = bases;
    out["minimum_reputation"] = minimum_reputations;
    out["minimum_quality"] = minimum_qualities;
    return out;
}
int64_t FCSimCore::choose_agent(Array agents, Dictionary index, Dictionary selection,
                                Ref<RandomNumberGenerator> rng) {
    Dictionary club = selection["club"], context = selection["context"], legal = selection["legal"],
               reserves = selection["reserves"], consumed = index["consumed"];
    Array indices = selection["indices"];
    int destination_id = iv(selection, "club_id"), nation = iv(club, "country_id");
    double skill = iv(selection, "skill"), club_rep = club_attraction(club),
           talks = double(iv(selection, "negotiations") - 10) * 2.0,
           quality = context.get("squad_ability", -1.0), reach = club_rep + (skill - 10.0) * 28.0,
           noise = UtilityFunctions::lerpf(6.0, 1.5, skill / 20.0);
    bool cap = selection.get("foreign_cap", false);
    String needed = selection["needed"];
    PackedStringArray positions = index["position"], raw_positions = index["raw_position"];
    PackedInt64Array nations = index["nation"];
    PackedFloat64Array rep = index["rep"], base = index["base"], min_rep = index["minimum_reputation"],
                       min_quality = index["minimum_quality"];
    const char* codes[] = {"GK", "CB", "FB", "CM", "WM", "WF", "ST"};
    std::array<int, 7> minimum{}, maximum{};
    std::array<bool, 7> allowed{};
    Dictionary minima = data["squad_min"], maxima = data["squad_max"];
    for (int j = 0; j < 7; ++j) {
        minimum[j] = iv(minima, codes[j]);
        maximum[j] = iv(maxima, codes[j]);
        allowed[j] = bool(legal.get(codes[j], false));
    }
    std::unordered_map<int, Reserve> flat;
    Array reserve_keys = reserves.keys();
    for (int j = 0; j < reserve_keys.size(); ++j) {
        int key = int64_t(reserve_keys[j]);
        Dictionary raw = reserves[reserve_keys[j]], supply = raw["supply"], demand = raw["demand"],
                   capacity = raw["capacity"], states = raw["club_state"];
        Reserve r;
        r.need = iv(raw, "total_need");
        auto own = [&](int id) {
            Dictionary state = states.get(id, Dictionary()), counts = state.get("counts", Dictionary());
            Own out;
            out.need = iv(state, "need");
            for (int k = 0; k < 7; ++k)
                out.counts[k] = iv(counts, codes[k]);
            return out;
        };
        r.destination = own(destination_id);
        r.zero = own(0);
        for (int k = 0; k < 7; ++k) {
            r.supply[k] = iv(supply, codes[k]);
            r.demand[k] = iv(demand, codes[k]);
            r.capacity[k] = iv(capacity, codes[k]);
        }
        flat[key] = r;
    }
    std::unordered_map<int64_t, bool> reservation_cache;
    auto reserved = [&](int origin, int pos) {
        int64_t cache_key = int64_t(origin) * 8 + pos;
        auto cached = reservation_cache.find(cache_key);
        if (cached != reservation_cache.end())
            return cached->second;
        bool result = false;
        if (flat.count(0))
            result = blocks(flat[0], flat[0].destination, pos, minimum, maximum);
        if (!result && origin != nation && flat.count(nation))
            result = blocks(flat[nation], flat[nation].destination, pos, minimum, maximum, false, false);
        if (!result && origin > 0 && flat.count(origin)) {
            auto& r = flat[origin];
            result = blocks(r, origin == nation ? r.destination : r.zero, pos, minimum, maximum);
        }
        reservation_cache[cache_key] = result;
        return result;
    };
    int best = -1;
    double best_score = -99999.0;
    for (int j = 0; j < indices.size(); ++j) {
        int i = int64_t(indices[j]);
        if (consumed.has(i) || agents[i].get_type() != Variant::DICTIONARY)
            continue;
        String pos = positions[i];
        int code = 3;
        for (int k = 0; k < 7; ++k)
            if (pos == codes[k]) {
                code = k;
                break;
            }
        if (!allowed[code])
            continue;
        int origin = nations[i];
        if (cap && origin > 0 && nation > 0 && origin != nation)
            continue;
        if (reserved(origin, code))
            continue;
        if (club_rep + talks < min_rep[i] || (quality >= 0 && quality < min_quality[i]))
            continue;
        double overreach = std::max(0.0, rep[i] - reach),
               fit = 1.0 - std::clamp(std::abs(rep[i] - club_rep) / 1000.0, 0.0, 1.0),
               bonus =
                   needed == String(data["transfer_flex"]) ? 2.0 : (raw_positions[i] == needed ? 10.0 : 0.0),
               score = base[i] + fit * 30.0 + skill * 0.8 - overreach * (0.12 - skill * 0.003) + bonus +
                       rng->randf_range(-noise, noise);
        if (score > best_score) {
            Dictionary p = agents[i], money;
            money["player"] = p;
            money["club"] = club;
            money["free_agent"] = true;
            Dictionary wage_context = context.duplicate();
            wage_context["offer_wage"] = market_amount("move", money);
            Dictionary accepted = evaluate_offer(offer_profile(p, iv(context, "world_top_reputation")), club,
                                                 iv(selection, "negotiations"), wage_context);
            if (!bool(accepted["accepted"]))
                continue;
            best_score = score;
            best = i;
        }
    }
    return best;
}
} // namespace godot
