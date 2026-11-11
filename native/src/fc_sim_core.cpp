#include "lineup_assignment.h"
#include "fc_sim_core.h"
#include <cstring>
#include <vector>
namespace godot {
static double number(const Dictionary& d, const char* key, double fallback = 0) {
    return double(d.get(key, fallback));
}
static int integer(const Dictionary& d, const char* key, int fallback = 0) {
    return int(int64_t(d.get(key, fallback)));
}
static Dictionary dict(const Variant& v) {
    return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary();
}
static int clip(int v, int a, int b) {
    return std::clamp(v, a, b);
}
void FCSimCore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("planner_shortlist", "candidates", "need", "buyer", "nation", "cap", "excluded", "skill", "rng", "limit"), &FCSimCore::planner_shortlist);
    ClassDB::bind_method(D_METHOD("planner_index", "candidates"), &FCSimCore::planner_index);
    ClassDB::bind_method(D_METHOD("agent_index", "agents", "world_top"), &FCSimCore::agent_index);
    ClassDB::bind_method(D_METHOD("choose_agent", "agents", "index", "selection", "rng"),
                         &FCSimCore::choose_agent);
    ClassDB::bind_method(D_METHOD("api_version"), &FCSimCore::api_version);
    ClassDB::bind_method(D_METHOD("national_roster", "candidates", "style", "error", "rng"),
                         &FCSimCore::national_roster);
    ClassDB::bind_method(
        D_METHOD("preview_playoff", "divisions", "clubs", "count", "per_division", "national", "rng"),
        &FCSimCore::preview_playoff);
    ClassDB::bind_method(D_METHOD("reputation_calc", "operation", "args"), &FCSimCore::reputation_calc);
    ClassDB::bind_method(D_METHOD("contract_chance", "player", "club", "negotiations", "context"),
                         &FCSimCore::contract_chance);
    ClassDB::bind_method(D_METHOD("preview_table", "clubs", "rng"), &FCSimCore::preview_table);
    ClassDB::bind_method(D_METHOD("preview_knockout", "clubs", "rng", "seeded", "single"),
                         &FCSimCore::preview_knockout);
    ClassDB::bind_method(D_METHOD("score_transfer", "club", "player", "skill", "needed", "rng"),
                         &FCSimCore::score_transfer);
    ClassDB::bind_method(D_METHOD("roll_attributes", "rng", "position", "target", "aptitudes"),
                         &FCSimCore::roll_attributes);
    ClassDB::bind_method(D_METHOD("roll_birth", "weights", "count", "rng", "cohort"), &FCSimCore::roll_birth);
    ClassDB::bind_method(D_METHOD("develop_player", "player", "setup", "rng", "playing_share", "season"),
                         &FCSimCore::develop_player);
    ClassDB::bind_method(D_METHOD("market_amount", "operation", "args"), &FCSimCore::market_amount);
    ClassDB::bind_method(D_METHOD("offer_profile", "player", "world_top"), &FCSimCore::offer_profile);
    ClassDB::bind_method(D_METHOD("evaluate_offer", "player", "club", "negotiations", "context"),
                         &FCSimCore::evaluate_offer);
    ClassDB::bind_method(D_METHOD("fit_attributes", "attributes", "position", "target", "prefer_group", "aptitudes"),
                         &FCSimCore::fit_attributes);
    ClassDB::bind_method(D_METHOD("less_weight", "a", "b"), &FCSimCore::less_weight);
    ClassDB::bind_method(D_METHOD("apply_entry_stats", "player", "entry", "season", "club_id"),
                         &FCSimCore::apply_entry_stats);
    ClassDB::bind_method(D_METHOD("apply_match_load", "player", "minutes", "intensity"),
                         &FCSimCore::apply_match_load);
    ClassDB::bind_method(D_METHOD("simulate", "config", "rng", "fingerprint"), &FCSimCore::simulate);
    ClassDB::bind_method(D_METHOD("less_shootout", "a", "b"), &FCSimCore::less_shootout);
    ClassDB::bind_method(D_METHOD("select_lineup", "spec", "opponent", "rng", "primary"),
                         &FCSimCore::select_lineup);
    ClassDB::bind_method(D_METHOD("coaching_profile", "style", "mode", "conserve"),
                         &FCSimCore::coaching_profile);
    ClassDB::bind_method(D_METHOD("review_coaching", "team", "opponent", "minute"),
                         &FCSimCore::review_coaching);
    ClassDB::bind_method(D_METHOD("build_lineup", "squad", "youth", "coach", "plan", "rng", "include_bench"),
                         &FCSimCore::build_lineup);
    ClassDB::bind_method(D_METHOD("finish_bench", "lineup"), &FCSimCore::finish_bench);
    ClassDB::bind_method(D_METHOD("less_ability", "a", "b"), &FCSimCore::less_ability);
    ClassDB::bind_method(D_METHOD("less_rest", "a", "b"), &FCSimCore::less_rest);
    ClassDB::bind_method(D_METHOD("metrics", "reset"), &FCSimCore::metrics);
    ClassDB::bind_method(D_METHOD("version"), &FCSimCore::version);
    ClassDB::bind_method(D_METHOD("configure", "data"), &FCSimCore::configure);
    ClassDB::bind_method(D_METHOD("set_knobs", "knobs"), &FCSimCore::set_knobs);
    ClassDB::bind_method(D_METHOD("build_ratings", "player"), &FCSimCore::build_ratings);
    ClassDB::bind_method(D_METHOD("ability_exact", "attributes", "position"), &FCSimCore::ability_exact);
    ClassDB::bind_method(D_METHOD("set_attraction_settings", "settings"), &FCSimCore::set_attraction_settings);
    ClassDB::bind_method(D_METHOD("club_attraction", "club"), &FCSimCore::club_attraction);
    ClassDB::bind_method(D_METHOD("role_value", "ratings", "slot", "style"), &FCSimCore::role_value);
    ClassDB::bind_method(D_METHOD("rate_pool", "pool", "slots", "style"), &FCSimCore::rate_pool);
    ClassDB::bind_method(D_METHOD("recover_players", "players", "played"), &FCSimCore::recover_players);
    ClassDB::bind_method(D_METHOD("recover_player", "player", "played"), &FCSimCore::recover_player);
}
String FCSimCore::version() const {
    return "fc-native-5-planner-20261112";
}
void FCSimCore::configure(Dictionary p_data) {
    data = p_data;
    role_weights = data["role_weights"];
    style_weights = data["style_weights"];
}
void FCSimCore::set_knobs(Dictionary p_knobs) {
    knobs = p_knobs;
    auto fill = [&](std::array<double, 21>& table, const char* prefix) {
        String key = prefix;
        double a = double(knobs.get(key + "1", 0.0)), b = double(knobs.get(key + "10", 0.0)),
               c = double(knobs.get(key + "20", 0.0));
        for (int attr = 1; attr <= 20; ++attr) {
            double x = attr;
            table[attr] = x <= 10 ? a + (b - a) * ((x - 1.0) / 9.0) : b + (c - b) * ((x - 10.0) / 10.0);
        }
    };
    fill(recovery_curve, "recovery_share_");
    fill(condition_curve, "condition_after_stamina_");
    fill(fresh_curve, "fresh_after_stamina_");
    double play_floor = std::clamp(number(knobs, "condition_play_floor"), 0.0, 1.0),
           select_floor = std::clamp(number(knobs, "condition_select_floor"), 0.0, 1.0),
           rest = std::clamp(number(knobs, "lineup_rest_below"), 1.0, 100.0),
           weight = number(knobs, "rotation_fatigue_weight", 1);
    for (int c = 0; c <= 100; ++c) {
        double x = c;
        play_curve[c] = play_floor + (1 - play_floor) * (x / 100.0);
        double v = select_floor + (1 - select_floor) * (x / 100.0);
        selection_curve[c] = std::pow(x >= rest ? v : v * (x / rest), weight);
    }
}
String FCSimCore::position_of(const Dictionary& p) {
 String pos=p.get("position","CM");
 if(pos=="GK") return "GK";
 if(pos=="CB" || pos=="FB" || pos=="DF" || pos=="DEF") return "CB";
 if(pos=="ST" || pos=="WF" || pos=="W" || pos=="FW" || pos=="ATT") return "ST";
 return "CM";
}
int FCSimCore::condition_of(const Dictionary& p) {
    return clip(integer(p, "condition", 100), 0, 100);
}
int FCSimCore::attribute(const Dictionary& p, const char* name, int fallback) {
    Variant raw = p.get("attributes", Variant());
    if (raw.get_type() != Variant::DICTIONARY)
        return fallback;
    Dictionary attrs = raw;
    Variant physical = attrs.get("physical", Dictionary());
    if (physical.get_type() != Variant::DICTIONARY)
        return 0;
    return clip(integer(Dictionary(physical), name, 1), 1, 20);
}
double FCSimCore::curve(int attr, const char* prefix) const {
    if (std::strcmp(prefix, "recovery_share_") == 0)
        return recovery_curve[clip(attr, 1, 20)];
    if (std::strcmp(prefix, "condition_after_stamina_") == 0)
        return condition_curve[clip(attr, 1, 20)];
    if (std::strcmp(prefix, "fresh_after_stamina_") == 0)
        return fresh_curve[clip(attr, 1, 20)];
    String key = prefix;
    double a = double(knobs.get(key + "1", 0.0)), b = double(knobs.get(key + "10", 0.0)),
           c = double(knobs.get(key + "20", 0.0));
    double x = clip(attr, 1, 20);
    return x <= 10 ? a + (b - a) * ((x - 1.0) / 9.0) : b + (c - b) * ((x - 10.0) / 10.0);
}
double FCSimCore::play_mult(int c) const {
    return play_curve[clip(c, 0, 100)];
}
double FCSimCore::select_mult(int c) const {
    return selection_curve[clip(c, 0, 100)];
}

double FCSimCore::weighted(const Dictionary& ratings, const Dictionary& weights) const {
    double total = 0;
    Array keys = weights.keys();
    for (int i = 0; i < keys.size(); ++i)
        total += double(ratings.get(keys[i], 0.5)) * double(weights[keys[i]]);
    return total;
}
double FCSimCore::role_rating(Dictionary ratings, const String& slot) {
    if (!ratings.has("_selection_roles"))
        ratings["_selection_roles"] = Dictionary();
    Dictionary values = ratings["_selection_roles"];
    if (!values.has(slot))
        values[slot] = weighted(ratings, role_weights.get(slot, role_weights["CM"]));
    return double(values[slot]);
}
double FCSimCore::style_rating(Dictionary ratings, const String& style) {
    if (!ratings.has("_selection_styles"))
        ratings["_selection_styles"] = Dictionary();
    Dictionary values = ratings["_selection_styles"];
    if (!values.has(style))
        values[style] = weighted(ratings, style_weights.get(style, style_weights["attacking"]));
    return double(values[style]);
}
double FCSimCore::role_value(Dictionary ratings, String slot, String style) { return 100.0*role_rating(ratings,slot);
}
double FCSimCore::mix(const Dictionary& attrs, const Array& terms) const {
    double sum = 0, total = 0;
    for (int i = 0; i < terms.size(); ++i) {
        Array term = terms[i];
        Variant raw = attrs.get(term[0], Variant());
        int v = 10;
        if (raw.get_type() == Variant::DICTIONARY)
            v = clip(int(int64_t(Dictionary(raw).get(term[1], 10))), 1, 20);
        double w = term[2];
        sum += double(v) * w;
        total += w;
    }
    return total > 0 ? std::clamp((sum / total) / 20.0, 0.02, 1.0) : 0.5;
}
double FCSimCore::ability_exact(Dictionary attrs, String pos) const {
    Dictionary p;
    p["position"] = pos;
    pos = position_of(p);
    Dictionary all = data["ability_terms"];
    Array terms = all.get(pos, Array());
    if (terms.is_empty())
        return 50;
    double sum = 0, total = 0;
    for (int i = 0; i < terms.size(); ++i) {
        Array term = terms[i];
        Variant group = attrs.get(term[0], Variant());
        int value = 1;
        if (group.get_type() == Variant::DICTIONARY)
            value = clip(int(int64_t(Dictionary(group).get(term[1], 1))), 1, 20);
        double w = term[2];
        sum += double(value) * w;
        total += w;
    }
    return total > 0 ? std::clamp((sum / total) / 20.0 * 100.0, 0.0, 100.0) : 50;
}
Dictionary FCSimCore::build_ratings(Dictionary p) {
    int stamp = integer(p, "current_ability") * 1000 + integer(p, "age");
    Dictionary cached = dict(p.get("_match_ratings", Variant()));
    if (!cached.is_empty() && integer(cached, "stamp", -1) == stamp)
        return cached;
    Dictionary attrs = dict(p.get("attributes", Variant()));
    String pos = position_of(p);
    bool gk = pos == "GK";
    Dictionary out;
    out["stamp"] = stamp;
    out["position"] = pos;
    out["is_gk"] = gk;
    for (const char* group : {"mix", "gk_mix"}) {
        Dictionary specs = data[group];
        Array keys = specs.keys();
        for (int i = 0; i < keys.size(); ++i)
            out[keys[i]] = String(group) == "gk_mix" && !gk ? 0.05 : mix(attrs, specs[keys[i]]);
    }
    Array valid = data["characters"];
    Array characters;
    Variant raw = p.get("characters", Variant());
    if (raw.get_type() == Variant::ARRAY) {
        Array values = raw;
        for (int i = 0; i < values.size(); ++i) {
            String value = values[i];
            if (valid.has(value) && !characters.has(value))
                characters.append(value);
            if (!characters.is_empty())
                break;
        }
    }
    if (characters.is_empty()) {
        String legacy = String(p.get("archetype", "")).strip_edges();
        if (valid.has(legacy))
            characters.append(legacy);
    }
    Dictionary flags = data["character_flags"];
    Array flag_keys = flags.keys();
    for (int i = 0; i < flag_keys.size(); ++i)
        out[flag_keys[i]] = characters.has(flags[flag_keys[i]]);
    out["pressure"] = 0.5;
    out["ego"] = 0.5;
    out["foul_risk"] = bool(out["hot_head"]) ? 0.85 : 0.3;
    double variance = 0.10 + (bool(out["inconsistent"]) ? 0.11 : 0.0);
    out["variance"] = std::clamp(variance, 0.03, 0.28);
    out["recovery"] = std::clamp(attribute(p, "recovery") / 20.0, 0.0, 1.0);
    double ability = attrs.is_empty() ? clip(integer(p, "current_ability", integer(p, "overall")), 0, 100)
                                      : clip(int(std::round(ability_exact(attrs, pos))), 0, 100);
    out["ability"] = std::clamp(ability / 100.0, 0.01, 1.0);
    p["_match_ratings"] = out;
    return out;
}
Dictionary FCSimCore::rate_pool(Array pool, Array slots, String style) {
    Dictionary scores;
    for (int i = 0; i < slots.size(); ++i)
        scores[slots[i]] = Variant();
    PackedStringArray positions;
    std::vector<Dictionary> ratings;
    std::vector<double> selected, morales, common, bonuses;
    std::vector<bool> national;
    for (int i = 0; i < pool.size(); ++i) {
        Dictionary player = pool[i];
        Dictionary r = build_ratings(player);
        ratings.push_back(r);
        selected.push_back(select_mult(condition_of(player)));
        morales.push_back(0.94 + 0.12 * (clip(integer(player, "morale", 60), 0, 100) / 100.0));
        positions.append(r.get("position", "CM"));
        common.push_back((4.0/13.0) * style_rating(r, style));
        national.push_back(bool(player.get("_national_selection", false)));
        bonuses.push_back(number(player, "_national_form_bonus"));
    }
    Array keys = scores.keys();
    for (int s = 0; s < keys.size(); ++s) {
        String slot = keys[s];
        PackedFloat32Array values;
        for (int i = 0; i < pool.size(); ++i) {
            double value = slot == "GK" ? role_value(ratings[i], slot, style)
                                        : role_value(ratings[i], slot, style);
            if (national[i])
                value += bonuses[i];
            values.append(value * selected[i] * morales[i]);
        }
        scores[slot] = values;
    }
    Dictionary result;
    result["positions"] = positions;
    result["scores"] = scores;
    return result;
}
void FCSimCore::recover_player(Dictionary p, bool played) {
    const char* names[] = {"condition",          "morale",        "injury_rounds", "injury_grade",
                           "suspension_matches", "yellow_running"};
    const Variant defaults[] = {100, 60, 0, "", 0, 0};
    for (int i = 0; i < 6; ++i)
        if (!p.has(names[i]))
            p[names[i]] = defaults[i];
    double c = condition_of(p);
    if (c < 100) {
        double rate = curve(attribute(p, "recovery"), "recovery_share_");
        if (!played)
            rate *= number(knobs, "recovery_idle_factor");
        if (integer(p, "injury_rounds") > 0)
            rate *= 0.5;
        if (integer(p, "age", 25) >= 33)
            rate *= 0.92;
        double regain = number(knobs, "recovery_floor") + (100.0 - c) * rate;
        p["condition"] = clip(int(std::round(c + regain)), 0, 100);
    } else
        p["condition"] = 100;
    int injury = integer(p, "injury_rounds");
    if (injury > 0) {
        p["injury_rounds"] = injury - 1;
        if (injury - 1 <= 0)
            p["injury_grade"] = "";
    }
    double morale = clip(integer(p, "morale", 60), 0, 100);
    if (std::abs(morale - 55.0) > 0.5)
        p["morale"] = clip(int(std::round(morale + 0.12 * (55.0 - morale))), 0, 100);
}
void FCSimCore::recover_players(Array players, Dictionary played) {
    for (int i = 0; i < players.size(); ++i)
        if (players[i].get_type() == Variant::DICTIONARY) {
            Dictionary p = players[i];
            recover_player(p, played.has(integer(p, "id")));
        }
}

Array FCSimCore::available_pool(const Array& players) {
    Array result;
    for (int i = 0; i < players.size(); ++i) {
        if (players[i].get_type() != Variant::DICTIONARY)
            continue;
        Dictionary p = players[i];
        const char* names[] = {"condition",          "morale",        "injury_rounds", "injury_grade",
                               "suspension_matches", "yellow_running"};
        const Variant defaults[] = {100, 60, 0, "", 0, 0};
        for (int j = 0; j < 6; ++j)
            if (!p.has(names[j]))
                p[names[j]] = defaults[j];
        if (integer(p, "injury_rounds") <= 0 && integer(p, "suspension_matches") <= 0)
            result.append(p);
    }
    return result;
}
double FCSimCore::fit(const String& slot, const String& position) const {
    Dictionary fits = data["fits"];
    return double(Dictionary(fits[slot])[position]);
}
bool FCSimCore::less_ability(Dictionary a, Dictionary b) {
    return role_value(build_ratings(a), a.get("position", "CM"), "attacking") > role_value(build_ratings(b), b.get("position", "CM"), "attacking");
}
bool FCSimCore::less_rest(int64_t a, int64_t b) {
    return double(sort_scores[a]) > double(sort_scores[b]);
}
Dictionary FCSimCore::build_lineup(Array squad, Array youth, Dictionary coach, Dictionary plan,
                                   Ref<RandomNumberGenerator> rng, bool include_bench) {
    Dictionary tactics = data["tactic_constants"];
    Array formations = tactics["FORMATIONS"];
    String formation = plan.get("formation", "3-2-2");
    if (!formations.has(formation))
        formation = "3-2-2";
    Dictionary metadata = tactics["FORMATION_META"];
    Array slots;
    slots.append("GK");
    slots.append_array(Dictionary(metadata[formation])["slots"]);
    Array pool = available_pool(squad);
    int used_youth = 0, keepers = 0;
    for (int i = 0; i < pool.size(); ++i) {
        if (position_of(pool[i]) == "GK")
            ++keepers;
        if (keepers >= 2)
            break;
    }
    if (pool.size() < slots.size() || keepers < 2) {
        Dictionary selected;
        for (int i = 0; i < pool.size(); ++i)
            selected[integer(pool[i], "id")] = true;
        Array reserves = available_pool(youth);
        reserves.sort_custom(Callable(this, "less_ability"));
        for (int i = 0; i < reserves.size(); ++i) {
            if (keepers >= 2)
                break;
            Dictionary p = reserves[i];
            int id = integer(p, "id");
            if (selected.has(id) || position_of(p) != "GK")
                continue;
            pool.append(p);
            selected[id] = true;
            ++keepers;
            ++used_youth;
        }
        for (int i = 0; i < reserves.size(); ++i) {
            if (pool.size() >= slots.size())
                break;
            Dictionary p = reserves[i];
            int id = integer(p, "id");
            if (selected.has(id))
                continue;
            pool.append(p);
            selected[id] = true;
            ++used_youth;
        }
    }
    double noise = 0;
    if (bool(coach.get("national_selection", false))) {
        double weakness =
            double(20 -
                   clip(integer(dict(coach.get("attributes", Dictionary())), "professionalism", 10), 1, 20)) /
            19.0;
        noise = weakness * weakness * 0.20;
    }
    String style = plan.get("style", "attacking");
    Array styles = tactics["STYLES"];
    if (!styles.has(style))
        style = "attacking";
    Dictionary rated = rate_pool(pool, slots, style);
    PackedStringArray positions = rated["positions"];
    Dictionary scores = rated["scores"];
    int count=pool.size(),outfield=0;
    Array taken; taken.resize(count); taken.fill(false);
    for(int j=0;j<count;++j) if(positions[j]!="GK") ++outfield;
    std::vector<std::vector<double>> weights;
    for(int row=0;row<slots.size();++row) {
        String slot=slots[row]; PackedFloat32Array values=scores[slot];
        std::vector<double> values_row;
        for(int j=0;j<std::max(count,int(slots.size()));++j) {
            double value=0;
            if(j<count) {
                value=std::max(0.0001,double(values[j])*fit(slot,positions[j]));
                if(slot!="GK" && positions[j]=="GK" && outfield>=slots.size()-1) value=-1000000;
                else if(noise>0) value*=1.0+rng->randf_range(-noise,noise);
            } else if(slot=="GK" && count>0) value=-1000000;
            values_row.push_back(value);
        }
        weights.push_back(std::move(values_row));
    }
    auto assigned=fc_assignment::solve(weights);
    Array starters;
    for(int row=0;row<slots.size();++row) {
        int selected=assigned[row]; if(selected<0 || selected>=count) continue;
        taken[selected]=true; Dictionary record;
        record["player"]=pool[selected]; record["slot"]=slots[row];
        record["fit"]=fit(slots[row],positions[selected]); record["selection_score"]=weights[row][selected];
        starters.append(record);
    }
    Dictionary context;
    context["pool"] = pool;
    context["positions"] = positions;
    context["taken"] = taken;
    context["scores"] = scores;
    Dictionary lineup;
    lineup["formation"] = formation;
    lineup["style"] = style;
    lineup["starters"] = starters;
    lineup["bench"] = Array();
    lineup["short"] = starters.size() < slots.size();
    lineup["used_youth"] = used_youth;
    lineup["_bench_context"] = context;
    return include_bench ? finish_bench(lineup) : lineup;
}
Dictionary FCSimCore::finish_bench(Dictionary lineup) {
    Dictionary context = dict(lineup.get("_bench_context", Dictionary()));
    if (context.is_empty())
        return lineup;
    Array pool = context["pool"], taken = context["taken"];
    PackedStringArray positions = context["positions"];
    Dictionary scores = context["scores"];
    Array keys = scores.keys();
    Array bench;
    const int bench_limit=int64_t(Dictionary(data["tactic_constants"])["MATCH_BENCH"]);
    auto cover = [&](const String& slot) {
        int best = -1;
        double best_score = -1;
        PackedFloat32Array values = scores[slot];
        for (int i = 0; i < pool.size(); ++i) {
            if (bool(taken[i]) || positions[i] != slot)
                continue;
            double score = double(values[i]) * fit(slot, positions[i]);
            if (score > best_score) {
                best_score = score;
                best = i;
            }
        }
        return best;
    };
    int keeper = cover("GK");
    if (keeper >= 0) {
        taken[keeper] = true;
        bench.append(pool[keeper]);
    }
    for (int i = 0; i < keys.size(); ++i) {
        String slot = keys[i];
        if (slot == "GK")
            continue;
        int best = cover(slot);
        if (best >= 0) {
            taken[best] = true;
            bench.append(pool[best]);
        }
    }
    Array rest;
    sort_scores = Dictionary();
    for (int i = 0; i < pool.size(); ++i) {
        if (bool(taken[i]))
            continue;
        double best_score = 0;
        for (int j = 0; j < keys.size(); ++j) {
            String slot = keys[j];
            if ((slot == "GK") == (positions[i] == "GK")) {
                PackedFloat32Array values = scores[slot];
                best_score = std::max(best_score, double(values[i]) * fit(slot, positions[i]));
            }
        }
        rest.append(i);
        sort_scores[i] = best_score;
    }
    rest.sort_custom(Callable(this, "less_rest"));
    for (int i = 0; i < rest.size(); ++i) {
        if (bench.size() >= bench_limit)
            break;
        bench.append(pool[int64_t(rest[i])]);
    }
    lineup["bench"] = bench;
    lineup.erase("_bench_context");
    return lineup;
}

Dictionary FCSimCore::select_lineup(Dictionary spec, Dictionary opponent, Ref<RandomNumberGenerator> rng, Dictionary primary) {
 Dictionary lineup=build_lineup(spec.get("squad",Array()),spec.get("youth",Array()),spec.get("coach",Dictionary()),primary,rng,false);
 lineup["plan_source"]="fixed"; lineup["plan_reason"]="fixed_322";
 return finish_bench(lineup);
}

Dictionary FCSimCore::coaching_profile(String style, String mode, bool conserve) {
 Dictionary mc=data["match_constants"], profiles=mc["STYLE_PROFILE"];
 Dictionary result=Dictionary(profiles.get(style,mc["STYLE_FALLBACK"])).duplicate();
 Array keys=result.keys();
 for(int j=0;j<keys.size();++j) result[keys[j]]=1.0+(double(result[keys[j]])-1.0)*number(knobs,"tactics_influence",1);
 return result;
}
Dictionary FCSimCore::review_coaching(Dictionary team, Dictionary opponent, int64_t minute) { return Dictionary(); }


} // namespace godot

namespace godot {
Dictionary FCSimCore::metrics(bool reset) {
    Dictionary result = timings.duplicate();
    if (reset)
        timings.clear();
    return result;
}
} // namespace godot
