#include "fc_sim_core.h"
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <unordered_map>
namespace godot {
Array FCSimCore::national_roster(Array candidates, String style, double error,
                                 Ref<RandomNumberGenerator> rng) {
    struct Group {
        String position;
        std::vector<int64_t> ids;
    };
    std::vector<Group> groups;
    std::unordered_map<int64_t, double> scores;
    std::unordered_map<int64_t, String> positions;
    for (int j = 0; j < candidates.size(); ++j) {
        Dictionary p = candidates[j];
        if (int64_t(p.get("injury_rounds", 0)) > 0)
            continue;
        String position = position_of(p);
        int index = -1;
        for (int k = 0; k < int(groups.size()); ++k)
            if (groups[k].position == position) {
                index = k;
                break;
            }
        if (index < 0) {
            index = groups.size();
            groups.push_back({position, {}});
        }
        int64_t id = p["id"];
        positions[id]=position;
        groups[index].ids.push_back(id);
        double value = role_value(build_ratings(p), position, style), bonus = 0;
        Array recent = p.get("recent_ratings", Array());
        if (!recent.is_empty()) {
            double total = 0;
            for (int k = 0; k < recent.size(); ++k)
                total += double(recent[k]);
            bonus = std::clamp((total / recent.size() - 6.5) * 3.0, -4.0, 4.0) *
                    std::min(double(recent.size()) / 5.0, 1.0);
        } else {
            Dictionary stats = p.get("season_stats", Dictionary());
            int games = int64_t(stats.get("matches", 0));
            if (games > 0) {
                double average =
                    UtilityFunctions::snappedf(double(stats.get("rating_sum", 0.0)) / games, 0.01);
                bonus = std::clamp((average - 6.5) * 3.0, -4.0, 4.0) * std::min(double(games) / 5.0, 1.0);
            }
        }
        value += bonus;
        value *= 0.65 + 0.35 * condition_of(p) / 100.0;
        scores[id] = value + (error > 0 ? rng->randf_range(-error, error) : 0.0);
    }
    struct Compare {
        const std::unordered_map<int64_t, double>* scores;
        bool operator()(int64_t a, int64_t b) const {
            return scores->at(a) > scores->at(b);
        }
    };
    auto sort = [&](std::vector<int64_t>& ids) {
        SortArray<int64_t, Compare> sorter;
        sorter.compare.scores = &scores;
        sorter.sort(ids.data(), ids.size());
    };
    Dictionary quotas = data["national_quotas"];
    Dictionary counts, maxima=data["national_maxima"];
    Array picked;
    std::vector<int64_t> rest;
    for (auto& group : groups) {
        sort(group.ids);
        int quota = int64_t(quotas.get(group.position, 0));
        for (int j = 0; j < int(group.ids.size()); ++j)
            if (j < quota) {
                picked.append(group.ids[j]);
                counts[group.position]=int64_t(counts.get(group.position,0))+1;
            }
            else
                rest.push_back(group.ids[j]);
    }
    sort(rest);
    int count = int64_t(data["national_squad_size"]);
    for (int64_t id : rest) {
        if (picked.size() >= count)
            break;
        String pos=positions[id];
        if(int64_t(counts.get(pos,0))>=int64_t(maxima.get(pos,0))) continue;
        picked.append(id);
        counts[pos]=int64_t(counts.get(pos,0))+1;
    }
    return picked;
}
} // namespace godot
