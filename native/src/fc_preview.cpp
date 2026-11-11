#include "fc_sim_core.h"
// Use the engine's sorting algorithm so ties preserve the reference seed order.
// Forecasts use their own supplied RNG; they never replace real match simulation.
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <unordered_map>
namespace godot {
namespace {
struct PreviewClub {
    int id;
    String name;
    double regular, knockout;
    int place_sum = 0, titles = 0;
};
struct Score {
    int index;
    double score;
};
struct ScoreGreater {
    bool operator()(const Score& a, const Score& b) const {
        return a.score > b.score;
    }
};
std::vector<PreviewClub> read_clubs(Array clubs) {
    std::vector<PreviewClub> out;
    for (int j = 0; j < clubs.size(); ++j) {
        Dictionary c = clubs[j];
        out.push_back({int(int64_t(c.get("club_id", 0))), c.get("club_name", ""),
                       double(c.get("regular", 0.0)), double(c.get("knockout", 0.0))});
    }
    return out;
}
template <class T, class Compare> void godot_sort(std::vector<T>& values, Compare compare) {
    SortArray<T, Compare> sorter;
    sorter.compare = compare;
    sorter.sort(values.data(), values.size());
}
} // namespace
Array FCSimCore::preview_table(Array clubs, Ref<RandomNumberGenerator> rng) {
    Dictionary constants = data["preview_constants"];
    int sims = int64_t(constants["SIMS"]);
    double noise = constants["TABLE_NOISE"];
    auto values = read_clubs(clubs);
    if (values.empty())
        return Array();
    std::vector<Score> scores;
    scores.reserve(values.size());
    for (int trial = 0; trial < sims; ++trial) {
        scores.clear();
        for (int j = 0; j < int(values.size()); ++j)
            scores.push_back({j, values[j].regular + rng->randfn(0, noise)});
        godot_sort(scores, ScoreGreater());
        for (int j = 0; j < int(scores.size()); ++j) {
            auto& club = values[scores[j].index];
            club.place_sum += j + 1;
            if (j == 0)
                ++club.titles;
        }
    }
    struct Order {
        bool operator()(const PreviewClub& a, const PreviewClub& b) const {
            int delta = a.place_sum - b.place_sum;
            return delta != 0 ? delta < 0 : a.titles > b.titles;
        }
    };
    godot_sort(values, Order());
    Array out;
    for (int j = 0; j < int(values.size()); ++j) {
        auto& c = values[j];
        Dictionary row;
        row["club_id"] = c.id;
        row["club_name"] = c.name;
        row["place_sum"] = c.place_sum;
        row["title_chance"] = double(c.titles) * 100.0 / double(sims);
        row["place"] = j + 1;
        out.append(row);
    }
    return out;
}
Dictionary FCSimCore::preview_knockout(Array clubs, Ref<RandomNumberGenerator> rng, bool seeded,
                                       bool single) {
    Dictionary constants = data["preview_constants"];
    int sims = int64_t(constants["SIMS"]);
    double noise = constants["TABLE_NOISE"], sharp = constants["KNOCKOUT_SHARPNESS"];
    auto values = read_clubs(clubs);
    std::unordered_map<int, double> strength;
    std::unordered_map<int, int> index;
    std::vector<int> ids;
    for (int j = 0; j < int(values.size()); ++j) {
        auto& c = values[j];
        strength[c.id] = c.knockout;
        index[c.id] = j;
        ids.push_back(c.id);
    }
    auto ordered = [&](const std::vector<int>& source) {
        std::vector<Score> scores;
        for (int id : source)
            if (id > 0)
                scores.push_back({id, strength[id] + rng->randfn(0, noise * 0.65)});
        godot_sort(scores, ScoreGreater());
        std::vector<int> out;
        for (auto& s : scores)
            out.push_back(s.index);
        return out;
    };
    auto tie = [&](int home, int away) {
        if (home < 1)
            return away;
        if (away < 1)
            return home;
        double chance = 1.0 / (1.0 + UtilityFunctions::exp(-(strength[home] - strength[away]) * sharp));
        return rng->randf() < chance ? home : away;
    };
    auto once = [&]() {
        std::vector<int> alive = ids;
        Dictionary reached;
        if (seeded) {
            alive = ordered(alive);
            alive = ordered(alive);
            if (alive.empty()) {
                Dictionary result;
                result["winner"] = 0;
                result["reached"] = reached;
                return result;
            }
            int size = 1;
            while (size < int(alive.size()))
                size *= 2;
            std::vector<int> positions{1};
            int span = 1;
            while (span < size) {
                std::vector<int> next;
                for (int seed : positions) {
                    next.push_back(seed);
                    next.push_back(span * 2 + 1 - seed);
                }
                positions = next;
                span *= 2;
            }
            std::vector<int> slots(size, -1);
            for (int j = 0; j < size; ++j)
                if (positions[j] <= int(alive.size()))
                    slots[j] = alive[positions[j] - 1];
            alive = slots;
        } else {
            for (int j = int(alive.size()) - 1; j > 0; --j) {
                int k = rng->randi_range(0, j);
                std::swap(alive[j], alive[k]);
            }
            for (int id : alive)
                reached[id] = 1;
        }
        int round = 1;
        while (alive.size() > 1) {
            std::vector<int> next;
            for (int j = 0; j < int(alive.size()); j += 2) {
                int winner = j + 1 < int(alive.size()) ? tie(alive[j], alive[j + 1]) : alive[j];
                next.push_back(winner);
                if (!seeded)
                    reached[winner] = round + 1;
            }
            alive = next;
            ++round;
        }
        Dictionary result;
        result["winner"] = alive.empty() ? 0 : alive[0];
        result["reached"] = reached;
        return result;
    };
    if (single)
        return once();
    int rounds = 0, size = 1;
    while (size < std::max(int(values.size()), 2)) {
        size *= 2;
        ++rounds;
    }
    std::vector<std::unordered_map<int, int>> histograms(values.size());
    for (int trial = 0; trial < sims; ++trial) {
        Dictionary result = once();
        int winner = int64_t(result["winner"]);
        if (winner > 0 && index.count(winner))
            ++values[index[winner]].titles;
        Dictionary depth = result["reached"];
        Array keys = depth.keys();
        for (int j = 0; j < keys.size(); ++j) {
            int id = int64_t(keys[j]);
            if (index.count(id))
                ++histograms[index[id]][int(int64_t(depth[keys[j]]))];
        }
    }
    struct Row {
        Dictionary data;
        int titles;
    };
    std::vector<Row> rows;
    for (int j = 0; j < int(values.size()); ++j) {
        auto& c = values[j];
        int deepest = 1;
        for (int round = 1; round <= rounds + 1; ++round) {
            int times = 0;
            for (auto& entry : histograms[j])
                if (entry.first >= round)
                    times += entry.second;
            if (double(times) / double(sims) >= 0.5)
                deepest = round;
        }
        String stage;
        if (deepest > rounds)
            stage = String::utf8("Титул");
        else {
            int from_end = rounds - deepest;
            const char* labels[] = {"Финал", "1/2 финала", "1/4 финала", "1/8 финала", "1/16 финала"};
            stage = from_end >= 0 && from_end < 5
                        ? String::utf8(labels[from_end])
                        : String::utf8("Раунд ") + String::num_int64(std::max(deepest, 1));
        }
        Dictionary row;
        row["club_id"] = c.id;
        row["club_name"] = c.name;
        row["title_chance"] = double(c.titles) * 100.0 / double(sims);
        row["stage"] = stage;
        rows.push_back({row, c.titles});
    }
    struct Order {
        bool operator()(const Row& a, const Row& b) const {
            return a.titles > b.titles;
        }
    };
    godot_sort(rows, Order());
    Array out;
    for (int j = 0; j < int(rows.size()); ++j) {
        rows[j].data["place"] = j + 1;
        out.append(rows[j].data);
    }
    Dictionary result;
    result["rows"] = out;
    return result;
}
double FCSimCore::score_transfer(Dictionary club, Dictionary player, int64_t coach_skill, String needed,
                                 Ref<RandomNumberGenerator> rng) {
    double skill = coach_skill, club_rep = club_attraction(club),
           player_rep = int64_t(player.get("reputation", 0)),
           ca = int64_t(player.get("current_ability", player.get("overall", 0))),
           pa = int64_t(player.get("potential_ability", ca));
    double reach = club_rep + (skill - 10.0) * 28.0, overreach = std::max(0.0, player_rep - reach),
           fit = 1.0 - std::clamp(std::abs(player_rep - club_rep) / 1000.0, 0.0, 1.0),
           noise = UtilityFunctions::lerpf(6.0, 1.5, skill / 20.0);
    double bonus = String(player.get("position", "")) == needed ? 10.0 : 0.0;
    if (needed == String(data["transfer_flex"]))
        bonus = 2.0;
    return ca * 1.15 + pa * 0.22 + fit * 30.0 + skill * 0.8 - overreach * (0.12 - skill * 0.003) + bonus +
           rng->randf_range(-noise, noise);
}
Array FCSimCore::preview_playoff(Array divisions, Array clubs, int64_t count, bool per_division,
                                 bool national, Ref<RandomNumberGenerator> rng) {
    Dictionary constants = data["preview_constants"];
    int sims = int64_t(constants["SIMS"]), quota = int(count) / std::max(int(divisions.size()), 1);
    double noise = constants["TABLE_NOISE"], sharp = constants["KNOCKOUT_SHARPNESS"];
    if (per_division && quota < 1 && !national)
        return Array();
    auto values = read_clubs(clubs);
    std::vector<std::vector<PreviewClub>> pools;
    for (int j = 0; j < divisions.size(); ++j) {
        Dictionary division = divisions[j];
        pools.push_back(read_clubs(division.get("clubs", Array())));
    }
    std::unordered_map<int, double> strength;
    std::unordered_map<int, int> qualifies, titles;
    for (auto& c : values)
        strength[c.id] = c.knockout;
    auto top = [&](const std::vector<PreviewClub>& pool, int take) {
        std::vector<Score> scored;
        for (auto& c : pool)
            scored.push_back({c.id, c.regular + rng->randfn(0, noise)});
        godot_sort(scored, ScoreGreater());
        std::vector<int> ids;
        for (int j = 0; j < std::min(take, int(scored.size())); ++j)
            ids.push_back(scored[j].index);
        return ids;
    };
    auto tie = [&](int home, int away) {
        if (home < 1)
            return away;
        if (away < 1)
            return home;
        double chance = 1.0 / (1.0 + UtilityFunctions::exp(-(strength[home] - strength[away]) * sharp));
        return rng->randf() < chance ? home : away;
    };
    auto seeded = [&](const std::vector<int>& ids) {
        std::vector<Score> scored;
        for (int id : ids)
            if (id > 0)
                scored.push_back({id, strength[id] + rng->randfn(0, noise * 0.65)});
        godot_sort(scored, ScoreGreater());
        if (scored.empty())
            return 0;
        if (scored.size() == 1)
            return scored[0].index;
        int size = 1;
        while (size < int(scored.size()))
            size *= 2;
        std::vector<int> positions{1};
        int span = 1;
        while (span < size) {
            std::vector<int> next;
            for (int seed : positions) {
                next.push_back(seed);
                next.push_back(span * 2 + 1 - seed);
            }
            positions = next;
            span *= 2;
        }
        std::vector<int> alive(size, -1);
        for (int j = 0; j < size; ++j)
            if (positions[j] <= int(scored.size()))
                alive[j] = scored[positions[j] - 1].index;
        while (alive.size() > 1) {
            std::vector<int> next;
            for (int j = 0; j < int(alive.size()); j += 2)
                next.push_back(tie(alive[j], alive[j + 1]));
            alive = next;
        }
        return alive[0];
    };
    for (int trial = 0; trial < sims; ++trial) {
        std::vector<int> qualified;
        if (per_division && national) {
            std::vector<std::vector<int>> ranked;
            int longest = 0;
            for (auto& pool : pools) {
                ranked.push_back(top(pool, pool.size()));
                longest = std::max(longest, int(pool.size()));
            }
            for (int place = 0; place < longest; ++place) {
                std::vector<int> candidates;
                for (auto& rank : ranked)
                    if (place < int(rank.size()))
                        candidates.push_back(rank[place]);
                if (qualified.size() + candidates.size() <= size_t(count))
                    qualified.insert(qualified.end(), candidates.begin(), candidates.end());
                else {
                    std::vector<PreviewClub> remaining;
                    for (auto& c : values)
                        if (std::find(candidates.begin(), candidates.end(), c.id) != candidates.end())
                            remaining.push_back(c);
                    auto picked = top(remaining, int(count) - int(qualified.size()));
                    qualified.insert(qualified.end(), picked.begin(), picked.end());
                }
                if (qualified.size() >= size_t(count))
                    break;
            }
        } else if (per_division) {
            for (auto& pool : pools) {
                auto picked = top(pool, quota);
                qualified.insert(qualified.end(), picked.begin(), picked.end());
            }
        } else
            qualified = top(values, count);
        for (int id : qualified)
            ++qualifies[id];
        int winner = seeded(qualified);
        if (winner > 0)
            ++titles[winner];
    }
    struct Row {
        Dictionary data;
        double title, qualify;
    };
    std::vector<Row> rows;
    for (auto& c : values) {
        double title = double(titles[c.id]) * 100.0 / double(sims),
               qualify = double(qualifies[c.id]) * 100.0 / double(sims);
        Dictionary row;
        row["club_id"] = c.id;
        row["club_name"] = c.name;
        row["qualify_chance"] = qualify;
        row["title_chance"] = title;
        rows.push_back({row, title, qualify});
    }
    struct Compare {
        bool operator()(const Row& a, const Row& b) const {
            double delta = a.title - b.title;
            return std::abs(delta) > 0.01 ? delta > 0 : a.qualify > b.qualify;
        }
    };
    godot_sort(rows, Compare());
    Array out;
    for (int j = 0; j < int(rows.size()); ++j) {
        rows[j].data["place"] = j + 1;
        if (rows[j].qualify >= 1.0 || rows[j].title >= 0.5)
            out.append(rows[j].data);
    }
    return out;
}
} // namespace godot
