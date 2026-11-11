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
Dictionary dict(const Variant& v) {
    return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary();
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
} // namespace
Array FCSimCore::secondary_terms(const String& position) const {
    Dictionary specs = data["generation"];
    return Dictionary(specs.get(position, specs["CM"])).get("secondary", Array());
}
static int secondary_target(const Array& term, double aptitude, double ability) {
    double level = term[2];
    return std::clamp(int(std::round(ability / 5.0 * level * std::sqrt(aptitude))), 1, 20);
}
Dictionary FCSimCore::roll_attributes(Ref<RandomNumberGenerator> rng, String position, int64_t target,
                                      Dictionary aptitudes) {
    Dictionary specs = data["generation"], spec = specs.get(position, specs["CM"]), groups = spec["groups"],
               bias = spec["bias"], out;
    int base =
        std::clamp(int(std::round(double(std::min(int(target), int(int64_t(data["general_profile_ca"])))) /
                                  100.0 * 20.0)),
                   1, 20);
    Array group_keys = groups.keys();
    for (int j = 0; j < group_keys.size(); ++j) {
        String group = group_keys[j];
        Array keys = groups[group];
        Dictionary values;
        for (int k = 0; k < keys.size(); ++k) {
            String key = keys[k], path = group + "." + key;
            int offset = 0;
            if (bias.has(path))
                offset = int(int64_t(bias[path])) >= 3 ? 1 : (rng->randf() < 0.45 ? 1 : 0);
            else
                offset = -rng->randi_range(0, 1);
            if(position=="CB" && path=="technical.finishing") offset-=3;
            if (position == "GK" && group != "goalkeeping" && group != "mental" && group != "physical")
                --offset;
            if (position != "GK" && group == "set_pieces")
                --offset;
            values[key] = std::clamp(base + offset + int(rng->randi_range(-1, 1)), 1, 20);
        }
        out[group] = values;
    }
    fit_attributes(out, position, double(std::clamp(int(target), 0, 100)), "", aptitudes);
    Array secondary = secondary_terms(position);
    for (int j = 0; j < secondary.size(); ++j) {
        Array term = secondary[j];
        String group = term[0], key = term[1];
        Variant raw = out.get(group, Variant());
        if (raw.get_type() != Variant::DICTIONARY || !Dictionary(raw).has(key))
            continue;
        Dictionary values = raw;
        int level = secondary_target(term, aptitude(aptitudes, group + "." + key), double(target));
        values[key] = std::clamp(level + int(rng->randi_range(-1, 1)), 1, 20);
    }
    return out;
}
Array FCSimCore::roll_birth(Array weights, int64_t count, Ref<RandomNumberGenerator> rng, bool cohort) {
    Array bands = data["birth_bands"];
    Dictionary elite = data["elite_weights"];
    std::vector<int> w;
    int total = 0, regular = 0;
    for (int j = 0; j < weights.size(); ++j) {
        int value = int64_t(weights[j]);
        w.push_back(value);
        total += value;
        if (j < 8)
            regular += value;
    }
    auto rating = [&](int band, bool rare) {
        Array limits = bands[band];
        int lo = int64_t(limits[0]);
        if (elite.has(band)) {
            Array conditional = elite[band];
            int sum = 0;
            for (int j = 0; j < conditional.size(); ++j)
                sum += int64_t(conditional[j]);
            int roll = rng->randi_range(1, sum), acc = 0;
            for (int j = 0; j < conditional.size(); ++j) {
                acc += int64_t(conditional[j]);
                if (roll <= acc)
                    return lo + j;
            }
            return lo + int(conditional.size()) - 1;
        }
        return rare ? lo : int(rng->randi_range(lo, int64_t(limits[1])));
    };
    Array result;
    if (!cohort) {
        if (total <= 0) {
            result.append(20);
            return result;
        }
        int roll = rng->randi_range(1, total), acc = 0, index = w.size() - 1;
        for (int j = 0; j < int(w.size()); ++j) {
            acc += w[j];
            if (roll <= acc) {
                index = j;
                break;
            }
        }
        result.append(rating(index, false));
        return result;
    }
    for (int j = 0; j < count; ++j) {
        int roll = rng->randi_range(1, total);
        if (roll > regular) {
            int acc = regular;
            for (int band = 8; band < int(w.size()); ++band) {
                acc += w[band];
                if (roll <= acc) {
                    result.append(rating(band, true));
                    break;
                }
            }
        }
    }
    int remaining = count - result.size();
    for (int j = 0; j < remaining; ++j) {
        int roll =
                std::min(regular, int((double(j) + rng->randf()) * double(regular) / double(remaining)) + 1),
            acc = 0;
        for (int band = 0; band < 8; ++band) {
            acc += w[band];
            if (roll <= acc) {
                result.append(rating(band, false));
                break;
            }
        }
    }
    for (int j = int(result.size()) - 1; j > 0; --j) {
        int k = rng->randi_range(0, j);
        Variant value = result[j];
        result[j] = result[k];
        result[k] = value;
    }
    return result;
}
void FCSimCore::develop_player(Dictionary player, Dictionary setup, Ref<RandomNumberGenerator> rng,
                               double playing_share, int64_t season) {
    if (player.is_empty())
        return;
    Variant raw = player.get("attributes", Variant());
    if (raw.get_type() != Variant::DICTIONARY)
        return;
    Dictionary attrs = raw;
    if (attrs.is_empty())
        return;
    Dictionary dc = data["development_constants"];
    auto d = [&](const char* key) { return double(dc[key]); };
    String position = player.get("position", "");
    double exact = ability_exact(attrs, position);
    int before_ca = std::clamp(int(std::round(exact)), 0, 100);
    Dictionary before = attrs.duplicate(true);
    int age = iv(player, "age", 20);
    double target = exact;
    if (age >= int(d("DECLINE_START_AGE"))) {
        double loss = d("DECLINE_PER_YEAR") * double(age - int(d("DECLINE_START_AGE")) + 1) *
                      rng->randf_range(d("DECLINE_NOISE_MIN"), d("DECLINE_NOISE_MAX"));
        if (characters(player, data["characters"]).has("PROFESSIONAL"))
            loss *= d("DECLINE_PROFESSIONAL_FACTOR");
        target -= std::max(loss, 0.0);
    } else {
        double share = 0;
        Array bands = dc["GROWTH_GAP_SHARES"];
        for (int j = 0; j < bands.size(); ++j) {
            Dictionary band = bands[j];
            if (age <= iv(band, "max_age")) {
                share = dv(band, "share");
                break;
            }
        }
        if (share > 0) {
            int pa = std::clamp(iv(player, "potential_ability", iv(player, "current_ability", 50)), 0, 100);
            double factor = dv(player, "development_factor", 0.92);
            int ceiling =
                factor >= 1 ? pa : int(UtilityFunctions::clampi(int(std::round(pa * factor)), 1, pa));
            double gap = std::max(double(ceiling) - exact, 0.0);
            if (gap > 0) {
                double minutes = d("MINUTES_GROWTH_FLOOR") +
                                 (1.0 - d("MINUTES_GROWTH_FLOOR")) *
                                     UtilityFunctions::sqrt(std::clamp(playing_share, 0.0, 1.0));
                double facility = std::clamp(
                           double(iv(setup, "facility", int(d("LEVEL_NEUTRAL")))) / d("LEVEL_MAX"), 0.0, 1.0),
                       coaching = std::clamp(
                           double(iv(setup, "coaching", int(d("LEVEL_NEUTRAL")))) / d("LEVEL_MAX"), 0.0, 1.0);
                double quality = d("FACILITY_WEIGHT") * facility + d("COACHING_WEIGHT") * coaching;
                double training = double(data["training_floor"]) + double(data["training_span"]) * quality,
                       drive = 1;
                drive = characters(player, data["characters"]).has("PROFESSIONAL") ? d("PROFESSIONAL_GROWTH_FACTOR") : 1.0;
                target += gap * share * training * drive * minutes *
                          rng->randf_range(d("GROWTH_NOISE_MIN"), d("GROWTH_NOISE_MAX"));
            }
        }
    }
    int pa = std::clamp(iv(player, "potential_ability", 100), 0, 100);
    target = UtilityFunctions::clampf(target, 1.0, double(pa));
    Dictionary profile = data["attribute_profile"];
    Dictionary aptitudes = dict(player.get(profile["aptitudes_key"], Variant()));
    fit_attributes(attrs, position, target, target < exact ? "physical" : "", aptitudes);
    if (age < int(d("DECLINE_START_AGE"))) {
        double ability = ability_exact(attrs, position), share = profile["secondary_share"];
        Array secondary = secondary_terms(position_of(player));
        for (int j = 0; j < secondary.size(); ++j) {
            Array term = secondary[j];
            String group = term[0], key = term[1];
            Variant raw = attrs.get(group, Variant());
            if (raw.get_type() != Variant::DICTIONARY || !Dictionary(raw).has(key))
                continue;
            Dictionary values = raw;
            int value = int(int64_t(values[key]));
            int level = secondary_target(term, aptitude(aptitudes, group + "." + key), ability);
            if (value >= level)
                continue;
            int step = int(std::floor(double(level - value) * share + rng->randf()));
            if (step > 0)
                values[key] = std::clamp(std::min(value + step, level), 1, 20);
        }
    }
    int next = std::min(std::clamp(int(std::round(ability_exact(attrs, position))), 0, 100), pa);
    player["current_ability"] = next;
    player["overall"] = next;
    player.erase("_match_ratings");
    if (season < 1)
        return;
    Dictionary deltas;
    Array groups = before.keys();
    for (int j = 0; j < attrs.keys().size(); ++j) {
        Variant key = attrs.keys()[j];
        if (!groups.has(key))
            groups.append(key);
    }
    for (int j = 0; j < groups.size(); ++j) {
        Variant group = groups[j];
        Dictionary old = dict(before.get(group, Dictionary())), now = dict(attrs.get(group, Dictionary())),
                   delta;
        Array keys = old.keys();
        Array new_keys = now.keys();
        for (int k = 0; k < new_keys.size(); ++k)
            if (!keys.has(new_keys[k]))
                keys.append(new_keys[k]);
        for (int k = 0; k < keys.size(); ++k) {
            int change = int(int64_t(now.get(keys[k], 0))) - int(int64_t(old.get(keys[k], 0)));
            if (change != 0)
                delta[keys[k]] = change;
        }
        if (!delta.is_empty())
            deltas[group] = delta;
    }
    Variant history_raw = player.get("development_history", Variant());
    Array history = history_raw.get_type() == Variant::ARRAY ? Array(history_raw) : Array();
    if (history.is_empty() && season > 1) {
        Dictionary entry;
        entry["season"] = season - 1;
        entry["ca"] = before_ca;
        history.append(entry);
    }
    if (!history.is_empty() && iv(Dictionary(history.back()), "season") == season) {
        Dictionary entry = history.back();
        entry["ca"] = next;
    } else {
        Dictionary entry;
        entry["season"] = season;
        entry["ca"] = next;
        history.append(entry);
    }
    player["development_history"] = history;
    player["development_deltas"] = deltas;
}
} // namespace godot
