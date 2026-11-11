#include "fc_sim_core.h"
// Individual spatial engine. The independent GDScript implementation has the
// same action order, random draws and reports for deterministic save/replay tests.
#include "fast_data.h"
#include "action_math.h"
#include "lineup_assignment.h"
#include <array>
#include <chrono>
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <limits>
namespace godot {
namespace {
double n(const Dictionary& d, const char* key, double fallback = 0) {
    return double(d.get(key, fallback));
}
int i(const Dictionary& d, const char* key, int fallback = 0) {
    return int(int64_t(d.get(key, fallback)));
}
bool b(const Dictionary& d, const char* key, bool fallback = false) {
    return bool(d.get(key, fallback));
}
Dictionary sub(const Dictionary& d, const char* key) {
    Variant v = d.get(key, Dictionary());
    return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary();
}
Array array(const Dictionary& d, const char* key) {
    return d.get(key, Array());
}
void inc(Dictionary d, const char* key, int delta = 1) {
    d[key] = i(d, key) + delta;
}
double clamp(double value, double low, double high) {
    return std::clamp(value, low, high);
}
} // namespace
namespace {
double n(const FastDict& d, const char* key, double fallback = 0) {
    return double(d.get(key, fallback));
}
int i(const FastDict& d, const char* key, int fallback = 0) {
    return int(int64_t(d.get(key, fallback)));
}
bool b(const FastDict& d, const char* key, bool fallback = false) {
    return bool(d.get(key, fallback));
}
FastDict sub(const FastDict& d, const char* key) {
    FastCell value = d.get(key, FastCell());
    return value.is_dict() ? FastDict(value) : FastDict();
}
FastArray array(const FastDict& d, const char* key) {
    return FastArray(d.get(key, FastCell()));
}
void inc(FastDict d, const char* key, int delta = 1) {
    d[key] = i(d, key) + delta;
}
} // namespace
class FCMatchKernel {
    FCSimCore& core;
    Ref<RandomNumberGenerator> rng;
    FastDict mc, discipline, kv, role_weights, style_weights, fits, compatible;
    struct RatingRecord { FastDict player, value; };
    std::unordered_map<int, std::vector<RatingRecord>> rating_cache;
    FastArray events;
    double importance = 1;
    double c(const char* key) {
        return double(mc[key]);
    }
    double k(const char* key, const char* fallback) {
        return double(kv.get(key, mc[fallback]));
    }
    double knob(const char* key, double fallback) {
        return n(kv, key, fallback);
    }
    FastDict ratings(FastDict p) {
        int id = i(p, "id");
        auto it = rating_cache.find(id);
        if (id > 0 && it != rating_cache.end())
            for(const auto& record:it->second)
                if(p.same(record.player)) return record.value;
        FastDict r(core.build_ratings(p));
        if (id > 0)
            rating_cache[id].push_back({p,r});
        return r;
    }
    int pick(PackedFloat32Array weights, double total) {
        if (total <= 0 || weights.is_empty())
            return -1;
        double ticket = rng->randf() * total, acc = 0;
        for (int j = 0; j < weights.size(); ++j) {
            acc += weights[j];
            if (ticket <= acc)
                return j;
        }
        return weights.size() - 1;
    }
    FastDict log(int minute, const std::string& type, FastDict team, FastDict entry) {
        FastDict e;
        e["minute"] = minute;
        e["type"] = type;
        e["side"] = std::string(team.get("side", ""));
        e["club_id"] = i(team, "club_id");
        e["player_id"] = i(entry, "player_id");
        e["player"] = std::string(entry.get("name", ""));
        events.append(e);
        return e;
    }
    FastDict keeper(FastDict t) {
        FastArray field = array(t, "on_field");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j];
            if (b(sub(u, "ratings"), "is_gk"))
                return u;
        }
        return field.is_empty() ? FastDict() : FastDict(field[0]);
    }
    int cond(FastDict p) {
        return std::clamp(i(p, "condition", 100), 0, 100);
    }
    std::string position(FastDict p) {
        std::string v=p.get("position","CM");
        if(v=="GK") return "GK";
        if(v=="CB" || v=="FB" || v=="DF" || v=="DEF") return "CB";
        if(v=="ST" || v=="WF" || v=="W" || v=="FW" || v=="ATT") return "ST";
        return "CM";
    }
    int attribute(FastDict p, const char* key, int fallback = 10) {
        FastCell raw = p.get("attributes", FastCell());
        if (!raw.is_dict())
            return fallback;
        FastDict attrs = raw;
        FastCell phys = attrs.get("physical", FastCell());
        if (!phys.is_dict())
            return 0;
        return std::clamp(i(FastDict(phys), key, 1), 1, 20);
    }
    double curve(int attr, const char* prefix) {
        return core.curve(attr, prefix);
    }
    double play(int condition) {
        return core.play_mult(condition);
    }
    double fit(std::string slot, std::string pos) {
        FastDict row = fits[slot];
        return double(row[pos]);
    }
    double weighted(FastDict r, FastDict weights) {
        double value = 0;
        FastArray keys = weights.keys();
        for (int j = 0; j < keys.size(); ++j) {
            std::string key = keys[j];
            value += double(r.get(key, 0.5)) * double(weights[key]);
        }
        return value;
    }
    double style_value(FastDict r, std::string style) {
        if (!r.has("_selection_styles"))
            r["_selection_styles"] = FastDict();
        FastDict values = r["_selection_styles"];
        if (!values.has(style))
            values[style] = weighted(r, style_weights.get(style, style_weights["attacking"]));
        return double(values[style]);
    }
    double role_value(FastDict r, std::string slot, std::string style) {
        if (!r.has("_selection_values"))
            r["_selection_values"] = FastDict();
        FastDict values = r["_selection_values"];
        if (!values.has(style))
            values[style] = FastDict();
        FastDict slots = values[style];
        if (slots.has(slot))
            return double(slots[slot]);
        if (!r.has("_selection_roles"))
            r["_selection_roles"] = FastDict();
        FastDict roles = r["_selection_roles"];
        if (!roles.has(slot))
            roles[slot] = weighted(r, role_weights.get(slot, role_weights["CM"]));
        double role = roles[slot];
        double result=100.0*role;
        slots[slot] = result;
        return result;
    }
    FastDict profile(std::string style,std::string mode,bool conserve) {
        FastDict profiles=mc["STYLE_PROFILE"];
        FastDict result=FastDict(profiles.get(style,mc["STYLE_FALLBACK"])).duplicate();
        Array keys=result.keys();
        for(int j=0;j<keys.size();++j) result[String(keys[j])]=1.0+(double(result[String(keys[j])])-1.0)*knob("tactics_influence",1);
        return result;
    }
    FastDict coach_review(FastDict t,FastDict o,int minute) { return FastDict(); }
    void sort_takers(FastArray takers) {
        struct Compare {
            FCMatchKernel* kernel;
            bool operator()(const FastCell& a, const FastCell& b) const {
                return kernel->shootout_score(a) > kernel->shootout_score(b);
            }
        };
        auto& values = takers.cells();
        SortArray<FastCell, Compare> sorter;
        sorter.compare.kernel = this;
        sorter.sort(values.data(), values.size());
    }
    double drain(FastDict p, FastDict t) {
        double remain = clamp(curve(attribute(p, "stamina"), "fresh_after_stamina_"), 0, 1);
        double base = (1 - remain) / c("REGULAR_PHASES"), condition = double(cond(p)) / c("CONDITION_MAX");
        double age = 1.0 + 0.010 * std::max(i(p, "age", 25) - 30, 0);
        return base * n(t, "intensity") * (1.35 - 0.35 * condition) * age *
               (position(p) == "GK" ? c("GOALKEEPER_WORKLOAD_FACTOR") : 1.0);
    }
    FastDict new_entry(FastDict p, std::string slot, bool started) {
        FastDict e;
        e["player_id"] = i(p, "id");
        e["name"] = std::string(p.get("name", ""));
        e["slot"] = slot;
        e["position"] = position(p);
        e["started"] = started;
        e["minutes"] = 0;
        e["intensity_minutes"] = 0.0;
        for (const char* key : {"goals", "assists", "saves", "conceded"})
            e[key] = 0;
        e["clean_sheet"] = false;
        for (const char* key : {"yellow", "red", "suspension"})
            e[key] = 0;
        e["injury_grade"] = "";
        for (const char* key :
             {"injury_rounds", "pen_scored", "pen_missed", "pen_saved", "shootout_scored", "shootout_missed"})
            e[key] = 0;
        e["rating"] = c("RATING_BASE");
        e["motm"] = false;
        e["is_gk"] = position(p) == "GK";
        return e;
    }

    FastDict make_unit(FastDict p, std::string slot, double fit, FastDict t, double gap, int minute) {
        FastDict r = ratings(p), entry = new_entry(p, slot, minute == 0);
        array(t, "entries").append(entry);
        FastDict by_id = t["by_id"];
        by_id[i(p, "id")] = entry;
        FastDict roles = mc["SLOT_ROLE"], role = roles.get(slot, roles["CM"]);
        double ra = n(role, "att");
        FastDict u;
        u["player"] = p;
        u["entry"] = entry;
        u["ratings"] = r;
        u["slot"] = slot;
        u["role"] = role;
        u["role_att"] = ra;
        u["fit"] = fit;
        u["fresh"] = play(cond(p));
        u["drain"] = drain(p, t);
        u["on_since"] = minute;
        u["yellow"] = 0;
        u["off"] = false;
        return u;
    }
    FastDict build_team(std::string side, FastDict spec, FastDict lineup, double ability, double opposing) {
        FastDict coach = sub(spec, "coach");
        std::string style = lineup.get("style", "attacking");
        FastDict profile = this->profile(style, "normal", false);
        FastDict attrs = sub(coach, "attributes");
        FastDict t;
        t["side"] = side;
        t["club_id"] = i(spec, "club_id");
        t["reputation"] = i(spec, "reputation", 500);
        t["coach_id"] = i(coach, "id");
        t["form"] = 1.0;
        t["style"] = style;
        t["initial_style"] = style;
        t["primary_style"] = std::string(coach.get("primary_style", style));
        t["backup_style"] = std::string(coach.get("backup_style", style));
        t["plan_source"] = std::string(lineup.get("plan_source", "primary"));
        t["plan_reason"] = std::string(lineup.get("plan_reason", "preferred_plan"));
        t["plan_scores"] = lineup.get("plan_scores", FastDict());
        t["approach"] = "normal";
        t["conserve"] = false;
        t["last_review"] = 0;
        t["last_style_change"] = -20;
        t["decisions"] = FastArray();
        t["intensity_sum"] = 0.0;
        t["formation"] = std::string(lineup.get("formation", "3-2-2"));
        t["profile"] = profile;
        t["intensity"] = n(profile, "intensity", 1);
        t["motivation"] = std::clamp(i(attrs, "motivation", 10), 1, 20);
        t["coach_influence"] = knob("coach_influence", 1);
        t["tactics"] = std::clamp(i(attrs, "tactics", 10), 1, 20);
        t["ability"] = 0.0;
        t["starting_ability"] = 0.0;
        t["starting_condition"] = 0.0;
        t["starting_keeper"] = FastDict();
        t["discipline_skill"] = std::clamp(i(attrs, "discipline", 10), 1, 20);
        t["on_field"] = FastArray();
        t["bench"] = lineup.get("bench", FastArray());
        t["subs_left"] = int(knob("subs_max", c("SUBS_MAX")));
        t["entries"] = FastArray();
        t["by_id"] = FastDict();
        for (const char* key :
             {"goals", "shots", "on_target", "fouls", "yellow", "red", "phases", "men_down"})
            t[key] = 0;
        t["possession_sum"] = 0.0;
        double gap = 0.0;
        FastArray starters = array(lineup, "starters");
        for (int j = 0; j < starters.size(); ++j) {
            FastDict row = starters[j], p = row["player"];
            std::string slot = row["slot"];
            FastDict u = make_unit(p, slot, n(row, "fit"), t, gap, 0);
            array(t, "on_field").append(u);
            t["starting_condition"] = n(t, "starting_condition") + cond(p);
            if (slot == "GK") {
                FastDict start;
                start["player_id"] = i(p, "id");
                start["ability"] = 0.0;
                start["condition"] = cond(p);
                start["native"] = b(sub(u, "ratings"), "is_gk");
                t["starting_keeper"] = start;
            }
        }
        t["starting_condition"] = n(t, "starting_condition") / std::max(int(array(t, "on_field").size()), 1);
        return t;
    }
    void goal(FastDict t, FastDict o, FastDict scorer, FastDict assistant, int minute, std::string type, FastDict secondary=FastDict()) {
        inc(t, "goals");
        FastDict entry = sub(scorer, "entry");
        inc(entry, "goals");
        std::string assist;
        FastArray ids,names;
        for(auto helper : {assistant,secondary}) {
            if(helper.is_empty()) continue;
            FastDict ae=sub(helper,"entry");
            int id=i(ae,"player_id");
            if(id==i(entry,"player_id")) continue;
            bool duplicate=false;
            for(int j=0;j<ids.size();++j) if(int64_t(ids[j])==id) duplicate=true;
            if(duplicate) continue;
            inc(ae,"assists"); ids.append(id); names.append(ae["name"]);
            if(!assist.empty()) assist+=", ";
            assist+=std::string(ae["name"]);
        }
        FastDict keeper_u = keeper(o);
        if (!keeper_u.is_empty())
            inc(sub(keeper_u, "entry"), "conceded");
        FastDict e = log(minute, type, t, entry);
        if (!assist.empty())
            e["assist"] = assist;
        e["assist_ids"]=ids;
        e["assist_names"]=names;
    }
    void close(FastDict u, int minute) {
        if (b(u, "off"))
            return;
        u["off"] = true;
        FastDict e = sub(u, "entry");
        inc(e, "minutes", std::max(minute - i(u, "on_since"), 0));
    }
    double remaining(FastDict u, FastDict t, int minute) {
        int end = minute < 50 ? 50 : 70;
        double phases = std::max(1.0, double(end - minute) / 5.0), fresh = n(u, "fresh");
        return role_value(sub(u, "ratings"), u["slot"], t["style"]) * n(u, "fit") *
               (fresh + std::max(0.42, fresh - n(u, "drain") * phases)) * 0.5;
    }
    double incoming_value(FastDict p, std::string slot, FastDict t, int minute) {
        FastDict r = ratings(p);
        if ((slot == "GK") != b(r, "is_gk"))
            return -1;
        int end = minute < 50 ? 50 : 70;
        double phases = std::max(1.0, double(end - minute) / 5.0), fresh = play(cond(p));
        return role_value(r, slot, t["style"]) * fit(slot, std::string(r.get("position", "CM"))) *
               (fresh + std::max(0.42, fresh - drain(p, t) * phases)) * 0.5;
    }
    bool acceptable(FastDict u, FastDict p, std::string slot, FastDict t, double incoming, double current) {
        if (incoming <= current * (1 + knob("subs_min_gain", 0.02)))
            return false;
        double original = role_value(sub(u, "ratings"), slot, t["style"]) * n(u, "fit");
        FastDict r = ratings(p);
        double replacement =
            role_value(r, slot, t["style"]) * fit(slot, std::string(r.get("position", "CM")));
        return replacement >= original * knob("subs_min_quality", 0.85);
    }
    bool substitute(FastDict t, FastDict u, int minute, bool forced, std::string reason = "fatigue",
                    std::string override_slot = "", int preferred_id = 0, bool refresh = true) {
        FastArray bench = array(t, "bench");
        if (bench.is_empty() || i(t, "subs_left") < 1)
            return false;
        if (!forced) {
            if (minute < int(knob("subs_first_minute", 25)) || minute == 50 || minute >= 70)
                return false;
            if (i(t, "subs_left") == 1 && minute < int(knob("subs_reserve_until", 40)))
                return false;
        }
        std::string slot = override_slot.empty() ? std::string(u["slot"]) : override_slot;
        bool need_gk = slot == "GK";
        int best = -1;
        double best_score = -1;
        for (int j = 0; j < bench.size(); ++j) {
            FastDict p = bench[j];
            if (preferred_id > 0 && i(p, "id") != preferred_id)
                continue;
            FastDict r = ratings(p);
            if (need_gk != b(r, "is_gk"))
                continue;
            double score = incoming_value(p, slot, t, minute);
            if (!forced && !acceptable(u, p, slot, t, score, remaining(u, t, minute)))
                continue;
            if (score > best_score) {
                best_score = score;
                best = j;
            }
        }
        if (best < 0)
            return false;
        FastDict p = bench[best];
        bench.remove_at(best);
        inc(t, "subs_left", -1);
        close(u, minute);
        FastArray field = array(t, "on_field");
        int index = field.find(u);
        FastDict fresh =
            make_unit(p, slot, fit(slot, std::string(ratings(p).get("position", "CM"))), t, 0.0, minute);
        if (index >= 0)
            field[index] = fresh;
        else
            field.append(fresh);
        if (refresh)
            ;
        FastDict e = log(minute, "SUB", t, sub(fresh, "entry"));
        e["out"] = std::string(sub(u, "entry")["name"]);
        e["forced"] = forced;
        e["reason"] = forced && reason == "fatigue" ? std::string("injury") : reason;
        return true;
    }
    void fatigue_sub(FastDict t, FastDict o, int minute) {
        if (i(t, "subs_left") < 1 || array(t, "bench").is_empty())
            return;
        if (i(t, "subs_left") == 1 && minute < int(knob("subs_reserve_until", 40)))
            return;
        FastDict best;
        int best_id = 0;
        double best_gain = -std::numeric_limits<double>::infinity();
        int end = minute < 50 ? 50 : 70;
        double phases = std::max(1.0, double(end - minute) / 5.0),
               gain_required = 1 + knob("subs_min_gain", 0.02),
               quality_required = knob("subs_min_quality", 0.85);
        FastArray field = array(t, "on_field"), bench = array(t, "bench");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j];
            if (b(sub(u, "ratings"), "is_gk") || minute - i(u, "on_since") < 10)
                continue;
            if (n(u, "fresh") > knob("subs_freshness_threshold", 0.94))
                continue;
            std::string slot = u["slot"];
            double original = role_value(sub(u, "ratings"), slot, t["style"]) * n(u, "fit"),
                   current = original *
                             (n(u, "fresh") + std::max(0.42, n(u, "fresh") - n(u, "drain") * phases)) * 0.5;
            for (int q = 0; q < bench.size(); ++q) {
                FastDict p = bench[q], r = ratings(p);
                if ((slot == "GK") != b(r, "is_gk"))
                    continue;
                double raw =
                    role_value(r, slot, t["style"]) * fit(slot, std::string(r.get("position", "CM")));
                if (raw < original * quality_required)
                    continue;
                double fresh = play(cond(p)),
                       incoming = raw * (fresh + std::max(0.42, fresh - drain(p, t) * phases)) * 0.5;
                if (incoming <= current * gain_required)
                    continue;
                double gain = incoming - current;
                if (gain > best_gain) {
                    best = u;
                    best_id = i(p, "id");
                    best_gain = gain;
                }
            }
        }
        if (!best.is_empty()) {
            std::string reason = i(t, "goals") < i(o, "goals")
                                     ? "chasing_score"
                                     : (i(t, "goals") > i(o, "goals") ? "protect_lead" : "fatigue");
            substitute(t, best, minute, false, reason, "", best_id, false);
        }
    }
    void tactical_sub(FastDict t, int minute) {
        if (i(t, "subs_left") <= 1)
            return;
        FastDict target;
        double largest_gain = 0;
        FastArray field = array(t, "on_field"), bench = array(t, "bench");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j];
            if (b(sub(u, "ratings"), "is_gk") || n(u, "role_att") < 0.5)
                continue;
            std::string slot = u["slot"];
            double current = role_value(sub(u, "ratings"), slot, t["style"]) * n(u, "fit") * n(u, "fresh");
            for (int q = 0; q < bench.size(); ++q) {
                FastDict p = bench[q], r = ratings(p);
                if (b(r, "is_gk"))
                    continue;
                double incoming = role_value(r, slot, t["style"]) * fit(slot, r["position"]) * play(cond(p));
                if (incoming > current * 1.02 && incoming - current > largest_gain) {
                    largest_gain = incoming - current;
                    target = u;
                }
            }
        }
        if (!target.is_empty()) {
            int count = events.size();
            substitute(t, target, minute, false, "chasing_score");
            if (events.size() > count)
                array(t, "decisions").append(FastDict(events.back()).duplicate());
        }
    }
    void review(FastDict t, FastDict o, int minute) {
        FastDict decision = coach_review(t, o, minute);
        if (decision.is_empty())
            return;
        t["style"] = decision["style"];
        t["approach"] = decision["approach"];
        t["conserve"] = decision["conserve"];
        FastDict profile = this->profile(t["style"], t["approach"], b(t, "conserve"));
        t["profile"] = profile;
        t["intensity"] = n(profile, "intensity");
        FastArray field = array(t, "on_field");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j];
            u["drain"] = drain(u["player"], t);
        }
        array(t, "decisions").append(decision);
        FastDict e = decision.duplicate();
        e["type"] = "TACTICAL_CHANGE";
        e["club_id"] = t["club_id"];
        e["side"] = t["side"];
        events.append(e);
        if (std::string(decision["approach"]) == "chase" && i(t, "tactics") >= 7)
            tactical_sub(t, minute);
    }
    void replace_dismissed_keeper(FastDict t, int minute) {
        if (i(t, "subs_left") <= 0)
            return;
        FastArray bench = array(t, "bench");
        bool has_keeper = false;
        for (int j = 0; j < bench.size(); ++j)
            if (b(ratings(bench[j]), "is_gk")) {
                has_keeper = true;
                break;
            }
        if (!has_keeper)
            return;
        FastDict outgoing;
        double value = std::numeric_limits<double>::infinity();
        FastArray field = array(t, "on_field");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j];
            double v = n(sub(u,"ratings"),"defend",0.5)*n(sub(u,"role"),"def")*n(u,"fresh");
            if (v < value) {
                value = v;
                outgoing = u;
            }
        }
        if (!outgoing.is_empty())
            substitute(t, outgoing, minute, true, "goalkeeper_dismissal", "GK");
    }
    void send_off(FastDict t, FastDict u, int minute) {
        log(minute, "RED", t, sub(u, "entry"));
        close(u, minute);
        array(t, "on_field").erase(u);
        inc(t, "men_down");

        if (std::string(u["slot"]) == "GK")
            replace_dismissed_keeper(t, minute);
    }
    void discipline_roll(FastDict t, int minute) {
        if (!b(discipline, "enabled", true))
            return;
        double coach = 1.15 - 0.30 * (n(t, "discipline_skill") / 20.0),
               expect = k("yellow_per_phase", "YELLOW_PER_PHASE") * n(discipline, "strictness", 1) * coach *
                        importance;
        if (rng->randf() >= expect)
            return;
        PackedFloat32Array weights;
        double total = 0;
        FastArray field = array(t, "on_field");
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j], r = sub(u, "ratings");
            double risk = n(r, "foul_risk", 0.6);
            if (b(r, "is_gk"))
                risk *= 0.2;
            risk *= 1.0 + 0.5 * (1.0 - n(u, "fresh"));
            risk *= n(u,"phase_fouls");
            weights.append(risk);
            total += risk;
        }
        int index = pick(weights, total);
        if (index < 0)
            return;
        FastDict offender = field[index], e = sub(offender, "entry");
        if (rng->randf() < k("red_direct_share", "RED_DIRECT_SHARE")) {
            e["red"] = 1;
            e["suspension"] = i(discipline, "red_ban", 2);
            inc(t, "red");
            send_off(t, offender, minute);
            return;
        }
        inc(e, "yellow");
        inc(offender, "yellow");
        inc(t, "yellow");
        log(minute, "YELLOW", t, e);
        if (b(discipline, "double_yellow_red", true) && i(offender, "yellow") >= 2) {
            e["red"] = 1;
            e["suspension"] = std::max(1, i(discipline, "red_ban", 2) - 1);
            inc(t, "red");
            send_off(t, offender, minute);
        }
    }
    void injuries(FastDict t, int minute, double scale) {
        if (rng->randf() >= k("injury_per_phase", "INJURY_PER_PHASE") * scale)
            return;
        FastArray field = array(t, "on_field");
        PackedFloat32Array weights;
        double total = 0;
        for (int j = 0; j < field.size(); ++j) {
            FastDict u = field[j], p = sub(u, "player");
            double risk = 0.5 + 1.4 * (1.0 - n(u, "fresh"));
            risk += 0.04 * std::max(i(p, "age", 25) - 29, 0);
            weights.append(risk);
            total += risk;
        }
        int index = pick(weights, total);
        if (index < 0)
            return;
        FastDict victim = field[index], entry = sub(victim, "entry");
        FastDict grades = mc["INJURY_GRADES"];
        FastArray keys = grades.keys();
        int sum = 0;
        for (int j = 0; j < keys.size(); ++j)
            sum += i(grades[keys[j]], "weight");
        int ticket = rng->randi_range(1, std::max(sum, 1)), acc = 0;
        std::string grade = mc["INJURY_GRADE_LIGHT"];
        for (int j = 0; j < keys.size(); ++j) {
            acc += i(grades[keys[j]], "weight");
            if (ticket <= acc) {
                grade = std::string(keys[j]);
                break;
            }
        }
        FastDict meta = grades[grade];
        int base = rng->randi_range(i(meta, "min", 1), i(meta, "max", 1));
        FastDict r = ratings(sub(victim, "player"));
        double factor = 1.13 - 0.28 * n(r, "recovery", 0.5);
        entry["injury_grade"] = grade;
        entry["injury_rounds"] = std::max(1, int(std::round(double(base) * factor)));
        log(minute, "INJURY", t, entry);
        bool replaced = false;
        if (i(t, "subs_left") > 0)
            replaced = substitute(t, victim, minute, true);
        if (!replaced) {
            close(victim, minute);
            field.erase(victim);
            inc(t, "men_down");
            ;
        }
    }
    #include "action_pitch.inc"
    void phase(FastDict home, FastDict away, int start, bool extra, double home_bonus) {
        review(home, away, start);
        review(away, home, start);
        q_pitch_phase(home, away, start, extra);
        inc(home, "phases"); inc(away, "phases");
        home["intensity_sum"] = n(home, "intensity_sum") + n(home, "intensity");
        away["intensity_sum"] = n(away, "intensity_sum") + n(away, "intensity");
        discipline_roll(home, start+5);
        discipline_roll(away, start+5);
        double fatigue_scale = extra ? 1.35 : 1.0;
        injuries(home, start+5, fatigue_scale);
        injuries(away, start+5, fatigue_scale);

        int end = start + 5;
        if (end >= int(knob("subs_first_minute", 25)) && end != 50 && end < 70) {
            fatigue_sub(home, away, end);
            fatigue_sub(away, home, end);
        }
    }

    bool shoot(FastArray takers, FastDict opponent, int round, int minute) {
        FastDict u = takers[round % takers.size()], r = sub(u, "ratings"), ku = keeper(opponent);
        double skill=q_attr(sub(u,"player"),"set_pieces","penalties")*(0.55+0.45*n(u,"fresh",1));
        if(b(r,"ice_cold")) skill=std::min(20.0,skill+1);
        FastDict kp=sub(ku,"player"); double fresh=0.55+0.45*n(ku,"fresh",1);
        int outcome=q_penalty_trial(skill,q_attr(kp,"goalkeeping","reflexes",b(sub(ku,"ratings"),"is_gk")?10:1)*fresh,q_attr(kp,"goalkeeping","positioning",b(sub(ku,"ratings"),"is_gk")?10:1)*fresh,!ku.is_empty());
        FastDict e = sub(u, "entry");
        if (outcome == 2) {
            inc(e, "shootout_scored");
            return true;
        }
        inc(e, "shootout_missed");
        if (!ku.is_empty() && outcome==1)
            inc(sub(ku, "entry"), "pen_saved");
        FastDict side;
        side["side"] = "";
        log(minute, "SHOOTOUT", side, e);
        return false;
    }
    double shootout_score(FastDict u) {
        FastDict r = sub(u, "ratings");
        double score = n(r, "penalty", 0.4);
        if (b(r, "is_gk"))
            score *= 0.25;
        if (b(r, "ice_cold"))
            score += 0.08;
        return score;
    }
    FastDict shootout(FastDict home, FastDict away, int minute) {
        FastArray ht = array(home, "on_field").duplicate(), at = array(away, "on_field").duplicate();
        sort_takers(ht);
        sort_takers(at);
        int hs = 0, as = 0, round = 0;
        if (ht.is_empty() || at.is_empty()) {
            hs = ht.size() >= at.size() ? 1 : 0;
            as = hs == 1 ? 0 : 1;
        } else {
            while (round < int(c("SHOOTOUT_MAX_ROUNDS"))) {
                bool sudden = round >= int(c("SHOOTOUT_ROUNDS"));
                if (shoot(ht, away, round, minute))
                    ++hs;
                if (shoot(at, home, round, minute))
                    ++as;
                ++round;
                if (sudden) {
                    if (hs != as)
                        break;
                } else {
                    int left = int(c("SHOOTOUT_ROUNDS")) - round;
                    if (std::abs(hs - as) > left)
                        break;
                    if (round >= int(c("SHOOTOUT_ROUNDS")) && hs != as)
                        break;
                }
            }
            if (hs == as) {
                if (shootout_score(ht[0]) >= shootout_score(at[0]))
                    ++hs;
                else
                    ++as;
            }
        }
        FastDict result;
        result["home"] = hs;
        result["away"] = as;
        return result;
    }
    void finalize(FastDict t, int conceded, int outcome, int minutes) {
        double bonus = outcome > 0 ? 0.28 : (outcome < 0 ? -0.22 : 0.0);
        FastArray entries = array(t, "entries");
        for (int j = 0; j < entries.size(); ++j) {
            FastDict e = entries[j];
            double played = n(e, "minutes") / double(std::max(minutes, 1)), rating = c("RATING_BASE");
            rating += 0.95 * n(e, "goals");
            rating += 0.55 * n(e, "assists");
            rating += 0.07 * n(e, "saves");
            rating += 0.30 * n(e, "pen_scored") + 0.45 * n(e, "pen_saved");
            rating -= 0.45 * n(e, "pen_missed");
            rating -= 0.35 * n(e, "yellow");
            rating -= 1.40 * n(e, "red");
            rating += bonus * played;
            if (b(e, "is_gk") && n(e, "minutes") > 0) {
                if (conceded == 0)
                    rating += 0.45;
                else
                    rating -= 0.22 * std::max(conceded - 1, 0);
            }
            if (n(e, "minutes") <= 0)
                rating = 0;
            e["rating"] =
                rating > 0 ? UtilityFunctions::snappedf(clamp(rating, c("RATING_MIN"), c("RATING_MAX")), 0.1)
                           : 0.0;
            e["clean_sheet"] = b(e, "is_gk") && conceded == 0 && i(e, "minutes") > 0;
        }
    }
    FastDict report(FastDict t) {
        int phases = std::max(i(t, "phases"), 1);
        FastDict result;
        for (const char* key : {"club_id", "coach_id", "starting_ability", "starting_condition"})
            result[key] = t[key];
        result["starting_keeper"] = sub(t, "starting_keeper").duplicate();
        for (const char* key :
             {"style", "initial_style", "plan_source", "plan_reason", "plan_scores", "decisions", "formation",
              "goals", "shots", "on_target", "fouls", "yellow", "red"})
            result[key] = t[key];
        result["possession"] = UtilityFunctions::snappedf(n(t, "possession_sum") / double(phases), 0.001);
        result["intensity"] = n(t, "intensity_sum") / phases;
        result["players"] = t["entries"];
        FastDict actions; FastArray entries=array(t,"entries");
        for(const char* key : {"passes", "completed_passes", "dribbles", "successful_dribbles", "interceptions", "blocks", "crosses", "completed_crosses", "distance_metres"}) {
            int total=0; for(int j=0;j<entries.size();++j) total+=i(entries[j],key);
            actions[key]=total;
        }
        result["actions"] = actions;
        return result;
    }

  public:
    FCMatchKernel(FCSimCore& p_core, Ref<RandomNumberGenerator> p_rng)
        : core(p_core), rng(p_rng), mc(core.data["match_constants"]), kv(core.knobs),
          role_weights(core.role_weights), style_weights(core.style_weights), fits(core.data["fits"]),
          compatible(core.data["compatible"]) {}
    FastDict run(FastDict config, std::string fingerprint) {
        auto started = std::chrono::steady_clock::now();
        auto mark = [&](const char* key) {
            auto now = std::chrono::steady_clock::now();
            core.timings[key] = double(core.timings.get(key, 0.0)) +
                                std::chrono::duration<double, std::milli>(now - started).count();
            started = now;
        };
        core.timings["matches"] = int64_t(core.timings.get("matches", 0)) + 1;
        if (rng.is_null()) {
            rng.instantiate();
            rng->randomize();
        }
        FastDict hs = sub(config, "home"), as = sub(config, "away");
        bool neutral = b(config, "neutral"), allow_draw = b(config, "allow_draw", true);
        importance = n(config, "importance", 1);
        discipline = config.get("discipline", core.data["discipline_defaults"]);
        FastDict primary_h, primary_a;
        FastDict hc = sub(hs, "coach"), ac = sub(as, "coach");
        primary_h["style"] = hc.get("style", "attacking");
        primary_h["formation"] = "3-2-2";
        primary_a["style"] = ac.get("style", "attacking");
        primary_a["formation"] = "3-2-2";
        FastDict hl = core.select_lineup(hs, as, rng, primary_h),
                 al = core.select_lineup(as, hs, rng, primary_a);
        double ha = 0, aa = 0;
        q_trace = b(config, "trace_actions");
        FastDict home = build_team("home", hs, hl, ha, aa), away = build_team("away", as, al, aa, ha);
        mark("setup_ms");
        double home_bonus = 0.0;
        for (int j = 0; j < int(c("REGULAR_PHASES")); ++j)
            phase(home, away, j * int(c("PHASE_MINUTES")), false, home_bonus);
        int minute = int(c("REGULAR_MINUTES"));
        bool extra = false;
        FastDict penalties;
        if (!allow_draw && i(home, "goals") == i(away, "goals")) {
            extra = true;
            for (int j = 0; j < int(c("ET_PHASES")); ++j)
                phase(home, away, int(c("REGULAR_MINUTES")) + int(c("PHASE_MINUTES")) * j, true, home_bonus);
            minute = int(c("REGULAR_MINUTES") + c("ET_MINUTES"));
            if (i(home, "goals") == i(away, "goals"))
                penalties = shootout(home, away, minute);
        }
        for (FastDict t : {home, away}) {
            FastArray field = array(t, "on_field");
            for (int j = 0; j < field.size(); ++j)
                close(field[j], minute);
        }
        int hg = i(home, "goals"), ag = i(away, "goals"), winner = hg != ag ? (hg > ag ? 1 : -1) : 0;
        if (hg == ag && !penalties.is_empty())
            winner = i(penalties, "home") > i(penalties, "away") ? 1 : -1;
        finalize(home, ag, winner, minute);
        finalize(away, hg, -winner, minute);
        FastDict motm;
        double best_rating = -1;
        for (FastDict t : {home, away}) {
            FastArray entries = array(t, "entries");
            for (int j = 0; j < entries.size(); ++j) {
                FastDict e = entries[j];
                double rating = n(e, "rating");
                if (rating > best_rating) {
                    best_rating = rating;
                    motm = e;
                }
            }
        }
        if (!motm.is_empty() && best_rating > 0)
            motm["motm"] = true;
        mark("play_ms");
        FastDict result;
        result["engine"] = "individual-spatial-v3";
        FastDict pitch; pitch["length_m"]=60.0; pitch["width_m"]=40.0; pitch["goal_width_m"]=5.0; pitch["goal_height_m"]=2.0; pitch["offside"]=false;
        result["pitch"] = pitch;
        result["home_goals"] = hg;
        result["settings_version"] = core.data["settings_version"];
        result["settings_fingerprint"] = fingerprint;
        result["away_goals"] = ag;
        result["winner"] = winner;
        result["extra_time"] = extra;
        result["shootout"] = penalties;
        result["minutes_played"] = minute;
        result["home_team"] = report(home);
        result["away_team"] = report(away);
        result["events"] = events;
        mark("report_ms");
        return result;
    }
};
Dictionary FCSimCore::simulate(Dictionary config, Ref<RandomNumberGenerator> rng, String fingerprint) {
    FCMatchKernel kernel(*this, rng);
    return kernel.run(config, fast_key_string(fingerprint));
}
bool FCSimCore::less_shootout(Dictionary a, Dictionary second) {
    auto score = [](Dictionary u) {
        Dictionary r = sub(u, "ratings");
        double value = n(r, "penalty", 0.4);
        if (b(r, "is_gk"))
            value *= 0.25;
        if (b(r, "ice_cold"))
            value += 0.08;
        return value;
    };
    return score(a) > score(second);
}
} // namespace godot
