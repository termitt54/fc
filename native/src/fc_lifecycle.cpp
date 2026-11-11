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
Dictionary as_dict(const Variant& v) {
    return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary();
}
} // namespace
bool FCSimCore::less_weight(String a, String b) {
    return double(sort_weights[a]) > double(sort_weights[b]);
}
double FCSimCore::aptitude(const Dictionary& aptitudes, const String& path) const {
    Dictionary profile = data["attribute_profile"];
    return std::clamp(double(aptitudes.get(path, 1.0)), double(profile["aptitude_min"]),
                      double(profile["aptitude_max"]));
}
void FCSimCore::fit_attributes(Dictionary attrs, String position, double target, String prefer_group,
                               Dictionary aptitudes) {
    Dictionary p;
    p["position"] = position;
    position = position_of(p);
    Dictionary all = data["ability_terms"];
    Array terms = all.get(position, Array());
    if (terms.is_empty())
        return;
    double headroom = Dictionary(data["attribute_profile"])["fit_headroom"];
    struct Term {
        String group, key, path;
        Dictionary values;
        double weight, aptitude;
        int initial, value;
        bool present;
    };
    std::vector<Term> flat;
    Array paths;
    sort_weights = Dictionary();
    double total = 0;
    for (int j = 0; j < terms.size(); ++j) {
        Array t = terms[j];
        String group = t[0], key = t[1], path = group + "." + key;
        Variant raw = attrs.get(group, Variant());
        Dictionary values = as_dict(raw);
        bool present = raw.get_type() == Variant::DICTIONARY && values.has(key);
        int value = present ? int(int64_t(values[key])) : 1;
        double weight = t[2];
        flat.push_back({group, key, path, values, weight, aptitude(aptitudes, path), value, value, present});
        paths.append(path);
        sort_weights[path] = weight;
        total += weight;
    }
    paths.sort_custom(Callable(this, "less_weight"));
    std::vector<int> order, preferred;
    for (int j = 0; j < paths.size(); ++j)
        for (int k = 0; k < int(flat.size()); ++k)
            if (flat[k].path == String(paths[j])) {
                order.push_back(k);
                if (!prefer_group.is_empty() && flat[k].path.begins_with(prefer_group + "."))
                    preferred.push_back(k);
                break;
            }
    auto ability = [&]() {
        double sum = 0;
        for (const auto& term : flat)
            sum += double(std::clamp(term.value, 1, 20)) * term.weight;
        return total > 0 ? std::clamp((sum / total) / 20.0 * 100.0, 0.0, 100.0) : 50;
    };
    double goal = std::clamp(target, 0.0, 100.0);
    auto priority = [&](const Term& term, int direction) {
        double level = double(direction > 0 ? term.value : term.value - 1);
        double ratio = (headroom - level) / level;
        double score = term.weight * term.aptitude * ratio * ratio;
        return direction > 0 ? score : -score;
    };
    auto step_best = [&](const std::vector<int>& candidates, int direction, double gap) {
        int count = candidates.size();
        std::vector<bool> tried(count, false);
        for (int attempt = 0; attempt < count; ++attempt) {
            int best = -1;
            double best_score = 0;
            for (int j = 0; j < count; ++j) {
                const Term& term = flat[candidates[j]];
                if (tried[j] || !term.present || std::clamp(term.value + direction, 1, 20) == term.value)
                    continue;
                double score = priority(term, direction);
                if (best < 0 || score > best_score) {
                    best = j;
                    best_score = score;
                }
            }
            if (best < 0)
                return false;
            tried[best] = true;
            Term& term = flat[candidates[best]];
            int previous = term.value;
            term.value = std::clamp(previous + direction, 1, 20);
            if (std::abs(ability() - goal) < gap)
                return true;
            term.value = previous;
        }
        return false;
    };
    for (int step = 0; step < 96; ++step) {
        double current = ability(), gap = std::abs(current - goal);
        if (gap < 0.45)
            break;
        int direction = current < goal ? 1 : -1;
        if (step_best(preferred, direction, gap))
            continue;
        if (!step_best(order, direction, gap))
            break;
    }
    for (auto& term : flat)
        if (term.present && term.value != term.initial)
            term.values[term.key] = term.value;
}
void FCSimCore::apply_entry_stats(Dictionary player, Dictionary entry, int64_t season, int64_t club_id) {
    int minutes = iv(entry, "minutes");
    if (minutes <= 0)
        return;
    double rating = dv(entry, "rating");
    if (rating > 0) {
        Variant raw = player.get("recent_ratings", Array());
        Array recent = raw.get_type() == Variant::ARRAY ? Array(raw) : Array();
        recent.append(rating);
        if (recent.size() > 5)
            recent.pop_front();
        player["recent_ratings"] = recent;
    }
    Array fields = data["stat_fields"];
    auto blank = [&](int s, int club) {
        Dictionary row;
        row["season"] = s;
        row["club_id"] = club;
        row["rating_sum"] = 0.0;
        for (int j = 0; j < fields.size(); ++j)
            row[fields[j]] = 0;
        return row;
    };
    Dictionary row = as_dict(player.get("season_stats", Variant()));
    if (player.get("season_stats", Variant()).get_type() != Variant::DICTIONARY) {
        row = blank(0, iv(player, "club_id"));
        player["season_stats"] = row;
    }
    if (iv(row, "season") != season && season > 0)
        row["season"] = season;
    int previous_club = iv(row, "club_id");
    if (previous_club > 0 && previous_club != club_id && iv(row, "matches") > 0) {
        Variant raw = player.get("career_stats", Array());
        Array career = raw.get_type() == Variant::ARRAY ? Array(raw) : Array();
        Dictionary closed;
        closed["season"] = iv(row, "season");
        closed["club_id"] = iv(row, "club_id");
        closed["rating_sum"] = UtilityFunctions::snappedf(dv(row, "rating_sum"), 0.1);
        for (int j = 0; j < fields.size(); ++j) {
            int value = int64_t(row.get(fields[j], 0));
            if (value != 0)
                closed[fields[j]] = value;
        }
        if (row.has("transfer_fee"))
            closed["transfer_fee"] = std::max(0, iv(row, "transfer_fee"));
        career.append(closed);
        player["career_stats"] = career;
        row = blank(season, club_id);
        player["season_stats"] = row;
    } else if (previous_club != club_id)
        row["club_id"] = club_id;
    row["matches"] = iv(row, "matches") + 1;
    if (bool(entry.get("started", false)))
        row["starts"] = iv(row, "starts") + 1;
    row["minutes"] = iv(row, "minutes") + minutes;
    for (const char* key : {"goals", "assists", "saves", "conceded", "shots", "on_target", "passes", "completed_passes", "receipts", "miscontrols", "dribbles", "successful_dribbles", "tackles", "interceptions", "blocks", "crosses", "completed_crosses", "aerial_wins", "distance_metres", "catches", "parries"})
        row[key] = iv(row, key) + iv(entry, key);
    if (bool(entry.get("clean_sheet", false)))
        row["clean_sheets"] = iv(row, "clean_sheets") + 1;
    for (const char* key : {"yellow", "red"})
        row[key] = iv(row, key) + iv(entry, key);
    if (iv(entry, "injury_rounds") > 0)
        row["injuries"] = iv(row, "injuries") + 1;
    for (const char* key : {"pen_scored", "pen_missed", "pen_saved"})
        row[key] = iv(row, key) + iv(entry, key);
    if (bool(entry.get("motm", false)))
        row["motm"] = iv(row, "motm") + 1;
    row["rating_sum"] = dv(row, "rating_sum") + rating;
}
void FCSimCore::apply_match_load(Dictionary player, int64_t minutes, double intensity) {
    if (minutes < 1)
        return;
    Dictionary r = build_ratings(player);
    double remaining = curve(attribute(player, "stamina"), "condition_after_stamina_"),
           base = 100.0 - remaining;
    double share = std::clamp(double(minutes) / 50.0, 0.0, 1.6),
           age = 1.0 + 0.012 * std::max(iv(player, "age", 25) - 31, 0);
    double cost = base * share * intensity * age *
                  (position_of(player) == "GK"
                       ? double(Dictionary(data["match_constants"])["GOALKEEPER_WORKLOAD_FACTOR"])
                       : 1.0);
    player["condition"] = std::clamp(int(std::round(double(condition_of(player)) - cost)), 0, 100);
}
} // namespace godot
