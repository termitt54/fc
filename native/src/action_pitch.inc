// Included inside FCMatchKernel. Only on_field actors enter the pitch simulation.
enum QSkill {
    Q_FINISH,
    Q_PASS,
    Q_TECH,
    Q_DRIBBLE,
    Q_DEFEND,
    Q_PACE,
    Q_STAMINA,
    Q_STRENGTH,
    Q_RECOVERY,
    Q_DELIVERY,
    Q_PENALTY,
    Q_REFLEX,
    Q_HANDS,
    Q_POSITION,
    Q_EXITS,
    Q_AIR,
    Q_SKILLS
};
struct QActor {
    FastDict unit, entry;
    std::array<double, Q_SKILLS> skill;
    std::array<int, 14> stats{};
    int side = 0, id = 0, mark = -1;
    std::string slot;
    double x = 0, y = 0, ax = 0, ay = 0, fresh = 1, drain = 0, metres = 0, delay = 0;
    bool active = true, individual = false, team_player = false, hot = false, ice = false;
};
struct QPlan {
    std::string style, approach;
    double tactical = 1, coach = 10, effort = 0.8, decision = 1.4, forward = 0.35, shooting = 1;
    double midfield_base = 0.505, midfield_span = 0.39, defender_run = 0.86;
};
std::array<QPlan, 2> q_plans;
std::unordered_map<int64_t, std::array<double, Q_SKILLS>> q_skill_cache;
const char *q_stat(int k) {
    static const char *names[] = {
        "passes",  "completed_passes", "receipts", "miscontrols", "dribbles",          "successful_dribbles",
        "tackles", "interceptions",    "blocks",   "crosses",     "completed_crosses", "aerial_wins",
        "catches", "parries"};
    return names[k];
}
double q_length = 60, q_width = 40, q_goal_width = 5, q_goal_height = 2, q_penalty_distance = 8;
bool q_offside = false, q_trace = false;
int q_second_assist=0;
double q_attr(FastDict p, const char *group, const char *key, double fallback = 10) {
    return clamp(n(sub(sub(p, "attributes"), group), key, fallback), 1, 20);
}
double q_distance(double x, double y, double xx, double yy) {
    return std::sqrt((x - xx) * (x - xx) + (y - yy) * (y - yy));
}
double q_skill(const QActor &a, int key) { return a.skill[key] * (0.55 + 0.45 * a.fresh); }
double q_progress(const QActor &a) { return a.side == 0 ? a.x : q_length - a.x; }
double q_goal_x(int side) { return side == 0 ? q_length : 0.0; }
int q_nearest(const std::vector<QActor> &a, int side, double x, double y, bool keeper_only = false) {
    int best = -1;
    double value = 1e100;
    for (int j = 0; j < int(a.size()); ++j) {
        if (!a[j].active || a[j].side != side || (keeper_only && a[j].slot != "GK"))
            continue;
        double dx=a[j].x-x, dy=a[j].y-y;
        double d=dx*dx+dy*dy;
        if (d < value) {
            value = d;
            best = j;
        }
    }
    return best;
}
void q_event(const char *type, const QActor &a, double seconds, double x, double y, int other = 0,
             bool success = true) {
    if (!q_trace)
        return;
    FastDict e = log(int(seconds / 60.0), type, a.side == 0 ? q_home : q_away, a.entry);
    e["second"] = UtilityFunctions::snappedf(seconds, 0.01);
    e["x"] = UtilityFunctions::snappedf(x, 0.01);
    e["y"] = UtilityFunctions::snappedf(y, 0.01);
    e["other_player_id"] = other;
    e["success"] = success;
}
FastDict q_home, q_away;
std::vector<QActor> q_actors(FastDict home, FastDict away, bool extra) {
    std::vector<QActor> actors;
    for (int side = 0; side < 2; ++side) {
        FastArray field = array(side == 0 ? home : away, "on_field");
        std::unordered_map<std::string, int> counts, seen;
        bool emergency = !field.is_empty();
        for (int j = 0; j < field.size(); ++j)
            if (std::string(FastDict(field[j])["slot"]) == "GK")
                emergency = false;
        for (int j = 0; j < field.size(); ++j)
            ++counts[emergency && j == 0 ? "GK" : std::string(FastDict(field[j])["slot"])];
        for (int j = 0; j < field.size(); ++j) {
            QActor a;
            a.unit = field[j];
            a.entry = a.unit["entry"];
            FastDict p = a.unit["player"], r = a.unit["ratings"];
            a.unit["phase_fouls"] = 0;
            a.id = i(p, "id");
            a.side = side;
            a.slot = emergency && j == 0 ? "GK" : std::string(a.unit["slot"]);
            const char *groups[] = {"technical",   "technical",   "technical",   "technical",
                                    "technical",   "physical",    "physical",    "physical",
                                    "physical",    "set_pieces",  "set_pieces",  "goalkeeping",
                                    "goalkeeping", "goalkeeping", "goalkeeping", "goalkeeping"};
            const char *keys[] = {"finishing", "passing",     "technique", "dribbling",
                                  "defending", "pace",        "stamina",   "strength",
                                  "recovery",  "delivery",    "penalties", "reflexes",
                                  "handling",  "positioning", "exits",     "aerial_reach"};
            const int64_t cache_key=(int64_t(side)<<32)|uint32_t(a.id);
            auto cached = q_skill_cache.find(cache_key);
            if (a.id > 0 && cached != q_skill_cache.end())
                a.skill = cached->second;
            else {
                for (int k = 0; k < Q_SKILLS; ++k)
                    a.skill[k] = q_attr(p, groups[k], keys[k], k >= Q_REFLEX && !b(r, "is_gk") ? 1 : 10);
                if (a.id > 0)
                    q_skill_cache[cache_key] = a.skill;
            }
            double depth=a.slot=="GK" ? 0.05 : a.slot=="CB" ? 0.28 : a.slot=="CM" ? 0.48 : 0.72;
            int count=counts[a.slot],number=seen[a.slot]++;
            double lane=count==1 ? 0.5 : 0.20+0.60*number/double(count-1);
            a.ax = side == 0 ? depth * q_length : (1 - depth) * q_length;
            a.ay = lane * q_width;
            a.x = n(a.unit, "pitch_x", a.ax);
            a.y = n(a.unit, "pitch_y", a.ay);
            a.fresh = n(a.unit, "fresh", 1);
            a.drain = n(a.unit, "drain") * (extra ? 1.35 : 1.0);
            a.individual = b(r, "individualist");
            a.team_player = b(r, "team_player");
            a.hot = b(r, "hot_head");
            a.ice = b(r, "ice_cold");
            actors.push_back(a);
        }
    }
    // Marking is one-to-one: several defenders cannot all abandon the same striker.
    for(int side=0;side<2;++side) {
        std::vector<int> markers,targets;
        for(int j=0;j<int(actors.size());++j) if(actors[j].slot!="GK") (actors[j].side==side?markers:targets).push_back(j);
        std::vector<std::vector<double>> weights;
        for(int marker:markers) {
            std::vector<double> row(std::max(markers.size(),targets.size()),0);
            for(int j=0;j<int(targets.size());++j) {
                const auto& m=actors[marker]; const auto& t=actors[targets[j]];
                double role=(m.slot=="CB" && t.slot=="ST")?12.0:0.0;
                if(m.slot==t.slot) role+=5;
                row[j]=100-q_distance(m.ax,m.ay,t.x,t.y)+role;
            }
            weights.push_back(std::move(row));
        }
        auto matches=fc_assignment::solve(weights);
        for(int j=0;j<int(markers.size());++j) if(matches[j]>=0 && matches[j]<int(targets.size())) actors[markers[j]].mark=targets[matches[j]];
    }
    return actors;
}
void q_move(std::vector<QActor> &a, int owner, double dt, int held = -1) {
    if (owner < 0)
        return;
    std::vector<std::pair<double, double>> before;
    before.reserve(a.size());
    for (const auto &actor : a)
        before.emplace_back(actor.x, actor.y);
    auto nearest_before = [&](int side, double x, double y) {
        int best = -1;
        double distance = 1e100;
        for (int k = 0; k < int(a.size()); ++k)
            if (a[k].active && a[k].side == side) {
                double dx = before[k].first - x, dy = before[k].second - y, d = dx * dx + dy * dy;
                if (d < distance) {
                    distance = d;
                    best = k;
                }
            }
        return best;
    };
    const int side = a[owner].side;
    const double bx = a[owner].x, by = a[owner].y;
    const int pressing_actor = nearest_before(1 - side, bx, by);
    for (int j = 0; j < int(a.size()); ++j) {
        QActor &u = a[j];
        if (!u.active)
            continue;
        double tx = u.ax, ty = u.ay;
        const QPlan &plan = q_plans[u.side];
        const std::string &style = plan.style;
        double tactical = plan.tactical, coach = plan.coach;
        if (u.slot == "GK") {
            double own_goal = q_goal_x(1 - u.side), ball_distance = std::max(std::abs(bx - own_goal), 0.5);
            tx = own_goal + (u.side == 0 ? 1 : -1) * q_length * 0.035;
            if (u.side != side && ball_distance < 12)
                tx = own_goal + (u.side == 0 ? 1 : -1) *
                                    std::min(ball_distance * 0.50, 1.0 + q_skill(u, Q_EXITS) * 0.12);
            ty = q_width / 2 + (by - q_width / 2) * std::abs(tx - own_goal) / ball_distance;
            // Poor positioning changes the intended stance, not the keeper's reaction skill.
            ty += (21 - u.skill[Q_POSITION]) * 0.04 * (u.id % 2 == 0 ? 1 : -1);
        } else if (u.side == side) {
            double advance=(u.side==0 ? bx : q_length-bx)-q_length*0.45;
            double penetration=clamp(advance/(q_length*0.40),0.0,1.0);
            bool attacking=style=="attacking";
            double depth=0.72+0.17*penetration,inward=0.50;
            if(u.slot=="CM") {depth=plan.midfield_base+plan.midfield_span*penetration; inward=0.65;}
            else if(u.slot=="CB") {
                bool runner=(u.ay<q_width*0.30 && by<q_width/2) || (u.ay>q_width*0.70 && by>=q_width/2);
                depth=0.28+(runner ? plan.defender_run*std::pow(penetration,0.70) : 0.12*penetration);
                inward=runner ? 0.80 : 0.0;
            }
            depth+=(attacking ? 0.01 : -0.025)*penetration*q_plans[u.side].tactical;
            tx=q_length*(u.side==0 ? depth : 1-depth);
            ty+=(q_width/2-ty)*inward*penetration;
        } else {
            if (j == pressing_actor) {
                tx = bx;
                ty = by;
            } else {
                int mark = u.mark;
                if (mark >= 0) {
                    double defending=q_skill(u,Q_DEFEND);
                    tx = before[mark].first +
                         (u.side == 0 ? -1 : 1) * (1.55+0.04*(10-defending)+0.012*(10-coach));
                    ty = before[mark].second +
                         ((21-defending)*0.035+(10-coach)*0.008) * (u.id % 2 == 0 ? 1 : -1);
                }
            }
        }
        tx = clamp(tx, 1, q_length - 1);
        ty = clamp(ty, 1, q_width - 1);
        double dist = q_distance(u.x, u.y, tx, ty), moved = 0;
        if (j != owner && j != held && u.delay <= 0 && dist > 0.0001) {
            double pace = fc_action::speed(u.skill[Q_PACE], u.fresh);
            double effort = plan.effort;
            moved = std::min(dist, pace * dt * effort);
            u.x += (tx - u.x) * moved / dist;
            u.y += (ty - u.y) * moved / dist;
            u.metres += moved;
        }
        u.delay = std::max(0.0, u.delay - dt);
        double effort =
            0.55 + (moved / std::max(dt, 0.001)) / std::max(fc_action::speed(u.skill[Q_PACE], u.fresh), 1.0);
        u.fresh = std::max(0.25, u.fresh - u.drain * (dt / 300.0) * effort);
    }
}
void q_restart(std::vector<QActor> &a, int &owner, int side, bool kickoff = false) {
    if (kickoff) {
        for (auto &u : a) {
            u.x = u.ax;
            u.y = u.ay;
        }
        owner = q_nearest(a, side, q_length / 2, q_width / 2);
        if(owner>=0) { a[owner].x=q_length/2; a[owner].y=q_width/2; }
    } else
        owner = q_nearest(a, side, q_goal_x(1 - side), q_width / 2, true);
    if (owner < 0)
        owner = q_nearest(a, side, q_length / 2, q_width / 2);
}
// A shot travels to a physical point in the goal mouth; keeper response uses time and reach.
int q_penalty_trial(double penalties, double reflexes, double positioning, bool has_keeper = true) {
    double sigma =
        fc_action::sigma(penalties, q_penalty_distance, true) /
        std::max(k("penalty_conversion_base", "PENALTY_CONVERSION_BASE") / c("PENALTY_CONVERSION_BASE"), 0.1);
    double target =
        (rng->randf() < 0.5 ? -1 : 1) * (1.6 + 0.03 * penalties) * q_goal_width / 5.0 + rng->randfn(0, sigma);
    double height = 0.25 + rng->randf() * 1.5 + rng->randfn(0, sigma * 0.15);
    if (std::abs(target) > q_goal_width / 2 || height < 0 || height > q_goal_height)
        return 0;
    if (!has_keeper)
        return 2;
    double available =
        std::max(0.0, q_penalty_distance / (14 + 0.4 * penalties) - fc_action::reaction(reflexes));
    double stance = (rng->randf() < 0.5 ? -1 : 1) * (0.9 + 0.025 * positioning);
    return std::abs(target - stance) <= 0.45 + 4 * available && height <= 1.2 + 1.8 * available ? 1 : 2;
}
bool q_shot(std::vector<QActor> &a, int &owner, int assist, double second, bool penalty = false) {
    QActor &u = a[owner];
    const int side = u.side;
    FastDict team = side == 0 ? q_home : q_away, opposition = side == 0 ? q_away : q_home;
    double gx = q_goal_x(side), distance = q_distance(u.x, u.y, gx, q_width / 2);
    double skill = q_skill(u, penalty ? Q_PENALTY : (b(u.unit, "free_kick") ? Q_DELIVERY : Q_FINISH));
    u.unit["free_kick"] = false;
    if (penalty && u.ice)
        skill = std::min(20.0, skill + 1.0);
    if (penalty) {
        int keeper = q_nearest(a, 1 - side, gx, q_width / 2, true);
        int outcome = q_penalty_trial(skill, keeper >= 0 ? q_skill(a[keeper], Q_REFLEX) : 1,
                                      keeper >= 0 ? q_skill(a[keeper], Q_POSITION) : 1, keeper >= 0);
        inc(team, "shots");
        inc(u.entry, "shots");
        if (outcome > 0) {
            inc(team, "on_target");
            inc(u.entry, "on_target");
        }
        if (outcome == 2) {
            goal(team, opposition, u.unit, FastDict(), int(second / 60), "PENALTY_GOAL");
            FastDict scored_event = events[events.size() - 1];
            scored_event["second"] = UtilityFunctions::snappedf(second, 0.01);
            inc(u.entry, "pen_scored");
            q_restart(a, owner, 1 - side, true);
            return true;
        }
        inc(u.entry, "pen_missed");
        if (outcome == 1 && keeper >= 0) {
            inc(a[keeper].entry, "saves");
            inc(a[keeper].entry, "pen_saved");
        }
        q_restart(a, owner, 1 - side);
        return false;
    }
    double aim = (rng->randf() < 0.5 ? -1.0 : 1.0) * (1.6 + 0.03 * skill) * q_goal_width / 5.0;
    double sigma = fc_action::sigma(skill, distance, penalty);
    sigma *=
        std::sqrt(c("SHOT_ON_TARGET_BASE") / std::max(k("shot_on_target_base", "SHOT_ON_TARGET_BASE"), 0.1));
    double target = q_width / 2 + aim + rng->randfn(0, sigma);
    double height = (0.25 + rng->randf() * 1.5) + rng->randfn(0, sigma * 0.15);
    inc(team, "shots");
    inc(u.entry, "shots");
    q_event("SHOT", u, second, u.x, u.y, 0,
            std::abs(target - q_width / 2) <= q_goal_width / 2 && height > 0 && height < q_goal_height);
    if (std::abs(target - q_width / 2) > q_goal_width / 2 || height < 0 || height > q_goal_height) {
        if (penalty)
            inc(u.entry, "pen_missed");
        q_restart(a, owner, 1 - side);
        return false;
    }
    if (!penalty) {
        for (int j = 0; j < int(a.size()); ++j) {
            auto &d = a[j];
            if (!d.active || d.side == side || d.slot == "GK")
                continue;
            double vx = gx - u.x, vy = target - u.y, norm = vx * vx + vy * vy;
            double f = norm > 0 ? ((d.x - u.x) * vx + (d.y - u.y) * vy) / norm : 0;
            if (f < 0.05 || f > 0.90)
                continue;
            double lateral = q_distance(d.x, d.y, u.x + f * vx, u.y + f * vy);
            double flight = distance * f / (14 + 0.4 * skill);
            double reach = 0.30 + 0.035 * q_skill(d, Q_DEFEND) +
                           fc_action::speed(d.skill[Q_PACE], d.fresh) *
                               std::max(0.0, flight - (0.9 - 0.035 * q_skill(d, Q_DEFEND)));
            if (lateral < reach) {
                ++d.stats[8];
                owner = j;
                q_event("BLOCK", d, second, d.x, d.y, u.id);
                return false;
            }
        }
    }
    inc(team, "on_target");
    inc(u.entry, "on_target");
    int keeper = q_nearest(a, 1 - side, gx, q_width / 2, true);
    if (keeper >= 0) {
        QActor &g = a[keeper];
        double plane = std::max(0.5, std::abs(g.x - u.x));
        double speed = (14 + 0.4 * skill) * std::sqrt(k("shot_conversion_base", "SHOT_CONVERSION_BASE") /
                                                      c("SHOT_CONVERSION_BASE"));
        double flight = plane / std::max(speed, 1.0);
        double available =
            std::max(0.0, flight + (penalty ? 0 : 0.08) - fc_action::reaction(q_skill(g, Q_REFLEX)));
        double at_keeper = u.y + (target - u.y) * clamp(plane / std::max(std::abs(gx - u.x), 0.5), 0, 1);
        double reach = 0.85 + 4.8 * available;
        double gy = g.y;
        if (penalty) {
            gy = q_width / 2 + (rng->randf() < 0.5 ? -1.2 : 1.2);
            reach = 0.45 + 4.0 * available;
        }
        if (std::abs(at_keeper - gy) <= reach && height <= (penalty ? 1.2 : 1.35) + 1.8 * available) {
            inc(g.entry, "saves");
            q_event("SAVE", g, second, g.x, g.y, u.id);
            if (penalty) {
                inc(u.entry, "pen_missed");
                inc(g.entry, "pen_saved");
            }
            if (rng->randf() < clamp(0.25 + 0.035 * q_skill(g, Q_HANDS), 0.25, 0.95) || penalty) {
                ++g.stats[12];
                owner = keeper;
            } else {
                ++g.stats[13];
                double rx = clamp(gx + (side == 0 ? -3 : 3), 1, q_length - 1),
                       ry = clamp(target + rng->randf_range(-2, 2), 1, q_width - 1);
                int near = -1;
                double time = 1e100;
                for (int j = 0; j < int(a.size()); ++j)
                    if (a[j].active) {
                        double t = q_distance(a[j].x, a[j].y, rx, ry) /
                                   fc_action::speed(a[j].skill[Q_PACE], a[j].fresh);
                        if (t < time) {
                            time = t;
                            near = j;
                        }
                    }
                owner = near;
            }
            return false;
        }
    }
    FastDict helper,helper2;
    for (auto &x : a)
        if (x.id == assist && x.side == side && x.id != u.id)
            helper = x.unit;
    for(const auto& x:a) if(x.id==q_second_assist && x.side==side && x.id!=u.id && x.id!=assist) helper2=x.unit;
    goal(team, opposition, u.unit, helper, int(second / 60), penalty ? "PENALTY_GOAL" : "GOAL",helper2);
    FastDict scored_event = events[events.size() - 1];
    scored_event["second"] = UtilityFunctions::snappedf(second, 0.01);
    if (penalty)
        inc(u.entry, "pen_scored");
    q_restart(a, owner, 1 - side, true);
    return true;
}
void q_pitch_phase(FastDict home, FastDict away, int start, bool extra) {
    q_home = home;
    q_away = away;
    for (int side = 0; side < 2; ++side) {
        FastDict team = side == 0 ? home : away;
        auto &plan = q_plans[side];
        plan.style = std::string(team["style"]);
        plan.approach = std::string(team.get("approach", "normal"));
        plan.tactical = knob("tactics_influence", 1);
        plan.coach = clamp(10 + (i(team, "tactics", 10) - 10) * n(team, "coach_influence", 1), 1, 20);
        plan.effort = clamp(0.80 + 0.005 * (n(team, "motivation", 10) - 10) * n(team, "coach_influence", 1),
                            0.65, 0.90);
        plan.decision =
            clamp(1.4 / std::max(n(sub(team, "profile"), "tempo", 1), 0.4) * c("CHANCES_PER_PHASE") /
                      std::max(k("chances_per_phase", "CHANCES_PER_PHASE"), 0.1),
                  0.4, 8.0);
        FastDict actions = core.data["action_constants"], preferences = sub(actions, "STYLE_SHOT_PREFERENCE");
        plan.midfield_base=n(actions,"MIDFIELD_ATTACK_DEPTH_BASE",0.505);
        plan.midfield_span=n(actions,"MIDFIELD_ATTACK_DEPTH_SPAN",0.39);
        plan.defender_run=n(actions,"DEFENDER_ATTACK_RUN_SPAN",0.86);
        plan.shooting = std::max(0.05, 1 + (n(preferences, plan.style.c_str(), 1) - 1) * plan.tactical);
        plan.forward=plan.style=="attacking" ? 0.30 : 0.24;
    }
    std::vector<QActor> a = q_actors(home, away, extra);
    if (a.empty())
        return;
    FastDict ball = home.get("pitch_ball", FastDict());
    int owner = -1, assist = i(ball, "assist");
    q_second_assist=i(ball,"second_assist");
    for (int j = 0; j < int(a.size()); ++j)
        if (a[j].id == i(ball, "owner") && a[j].side == i(ball, "side"))
            owner = j;
    if (start == 0 || start == 25 || start == 50 || start == 60) {
        q_restart(a, owner, start == 25 || start == 60 ? 1 : 0, true);
        assist = 0;
        q_second_assist=0;
    } else if (owner < 0)
        q_restart(a, owner, start % 10 == 0 ? 0 : 1, true);
    double elapsed = 0, home_time = 0, away_time = 0;
    const double duration = 300.0;
    while (elapsed < duration && owner >= 0) {
        int current = owner, side = a[current].side;
        QActor &u = a[current];
        FastDict team = side == 0 ? home : away;
        double second = start * 60.0 + elapsed;
        double decision = q_plans[side].decision;
        q_move(a, owner, decision);
        elapsed += decision;
        if (side == 0)
            home_time += decision;
        else
            away_time += decision;
        int defender = q_nearest(a, 1 - side, u.x, u.y);
        double close = defender < 0 ? 1e6 : q_distance(u.x, u.y, a[defender].x, a[defender].y);
        double distance = q_distance(u.x, u.y, q_goal_x(side), q_width / 2);
        bool in_box=distance<9.0 && std::abs(u.y-q_width/2)<8.0;
        double contact_caution=in_box?0.40:1.0;
        if (defender >= 0 && u.slot != "GK" && close < 1.5 &&
            rng->randf() <
                contact_caution * (0.004 + 0.002 * (21 - q_skill(a[defender], Q_DEFEND))) * (a[defender].hot ? 1.6 : 1.0)) {
            auto &d = a[defender];
            FastDict defending = d.side == 0 ? home : away;
            inc(defending, "fouls");
            inc(d.unit, "phase_fouls");
            inc(d.entry, "fouls");
            q_event("FOUL", d, second, d.x, d.y, u.id);
            if (in_box &&
                rng->randf() < std::min(1.0, k("penalty_per_phase", "PENALTY_PER_PHASE") /
                                                 std::max(c("PENALTY_PER_PHASE"), 0.001))) {
                int taker = current;
                for (int j = 0; j < int(a.size()); ++j)
                    if (a[j].active && a[j].side == side &&
                        q_skill(a[j], Q_PENALTY) > q_skill(a[taker], Q_PENALTY))
                        taker = j;
                owner = taker;
                a[taker].x = q_goal_x(side) + (side == 0 ? -q_penalty_distance : q_penalty_distance);
                a[taker].y = q_width / 2;
                q_event("PENALTY", a[taker], second, a[taker].x, a[taker].y);
                q_shot(a, owner, 0, second, true);
                assist = 0;
                q_second_assist=0;
                elapsed += 25;
            } else {
                u.unit["free_kick"] = true;
                elapsed += 8;
            }
            continue;
        }
        double combination=(assist>0 || distance<3.5)?1.0:0.01;
        if ((u.slot != "GK" || q_progress(u)>q_length*0.15) && distance < q_length * 0.32 &&
            rng->randf() < clamp((0.07 + (q_length * 0.32 - distance) * 0.025) * q_plans[side].shooting * combination *
                                     k("chance_create_base", "CHANCE_CREATE_BASE") / c("CHANCE_CREATE_BASE"),
                                 0.001, 0.45)) {
            if (defender >= 0 && close < 2.2) {
                auto &d = a[defender];
                double defence = q_skill(d, d.slot == "GK" ? Q_EXITS : Q_DEFEND);
                if (rng->randf() >
                    fc_action::duel(q_skill(u, Q_FINISH), defence, knob("duel_skill_influence", 1))) {
                    ++d.stats[d.slot == "GK" ? 6 : 8];
                    q_event("BLOCK", d, second, d.x, d.y, u.id);
                    owner = defender;
                    assist = 0;
                    q_second_assist=0;
                    elapsed += 2;
                    continue;
                }
            }
            bool scored = q_shot(a, owner, assist, second);
            if(scored || owner<0 || a[owner].side!=side) { assist=0; q_second_assist=0; }
            else if(a[owner].id!=u.id) { q_second_assist=assist; assist=u.id; }
            elapsed += scored ? 32.0 : 12.0;
            continue;
        }
        if ((u.slot != "GK" || q_progress(u)>q_length*0.15) && close < 1.3 && rng->randf() < 0.25) {
            auto &d = a[defender];
            bool held = rng->randf() < fc_action::duel(q_skill(u, Q_STRENGTH), q_skill(d, Q_STRENGTH),
                                                       knob("duel_skill_influence", 1));
            if (!held) {
                ++d.stats[6];
                owner = defender;
                assist = 0;
                q_second_assist=0;
            }
            q_event("CONTACT", u, second, u.x, u.y, d.id, held);
            if (!held)
                continue;
        }
        bool dribble = (u.slot != "GK" || q_progress(u)>q_length*0.15) && close < 5.0 &&
                       rng->randf() < (0.35 + (u.individual ? 0.16 : 0) - (u.team_player ? 0.09 : 0));
        if (dribble) {
            ++u.stats[4];
            auto &d = a[defender];
            bool won = rng->randf() < fc_action::duel(q_skill(u, Q_DRIBBLE),
                                                      q_skill(d, d.slot == "GK" ? Q_EXITS : Q_DEFEND),
                                                      knob("duel_skill_influence", 1));
            if (won) {
                ++u.stats[5];
                double step = fc_action::speed(u.skill[Q_PACE], u.fresh) * 0.65;
                u.x = clamp(u.x + (side == 0 ? step : -step), 1, q_length - 1);
                u.metres += step;
                d.delay = 1.6;
            } else {
                ++d.stats[6];
                owner = defender;
                assist = 0;
                q_second_assist=0;
            }
            q_event("DRIBBLE", u, second, u.x, u.y, d.id, won);
            q_move(a, owner, 1.0);
            elapsed += 1.0;
            continue;
        }
        int target = -1;
        double best = -1e100;
        const std::string style = team["style"];
        double forward = q_plans[side].forward;
        for (int j = 0; j < int(a.size()); ++j) {
            if (j == owner || !a[j].active || a[j].side != side || a[j].slot == "GK")
                continue;
            double d = q_distance(u.x, u.y, a[j].x, a[j].y);
            int marker = q_nearest(a, 1 - side, a[j].x, a[j].y);
            double space = marker < 0 ? 10 : q_distance(a[j].x, a[j].y, a[marker].x, a[marker].y);
            double score =
                (q_progress(a[j]) - q_progress(u)) * forward + std::min(space, 10.0) * 0.7 - d * 0.06;
            double route_risk = 0, vx = a[j].x - u.x, vy = a[j].y - u.y, norm = vx * vx + vy * vy;
            for (const auto &marker_actor : a) {
                if (!marker_actor.active || marker_actor.side == side || marker_actor.slot == "GK")
                    continue;
                double along =
                    norm > 0 ? ((marker_actor.x - u.x) * vx + (marker_actor.y - u.y) * vy) / norm : 0;
                if (along < 0.08 || along > 0.95)
                    continue;
                double lateral =
                    q_distance(marker_actor.x, marker_actor.y, u.x + along * vx, u.y + along * vy);
                double flight = d * along / (8 + 0.35 * q_skill(u, Q_PASS));
                double reach = 0.35 + 0.04 * q_skill(marker_actor, Q_DEFEND) +
                               fc_action::speed(marker_actor.skill[Q_PACE], marker_actor.fresh) *
                                   std::max(0.0, flight - (0.9 - 0.035 * q_skill(marker_actor, Q_DEFEND)));
                route_risk += std::max(0.0, reach + 0.5 - lateral);
            }
            double knowledge = q_plans[side].coach;
            score -= route_risk * (1.5 + knowledge * 0.10);
            score += rng->randf_range(-1, 1) * (21 - q_plans[side].coach) * 0.15;
            if (score > best) {
                best = score;
                target = j;
            }
        }
        if (target < 0 || (best < 1.5 && close > 3.0 && u.slot != "GK")) {
            double step =
                std::min(std::max(0.2, close - 1.5), fc_action::speed(u.skill[Q_PACE], u.fresh) * 0.75);
            u.x = clamp(u.x + (side == 0 ? step : -step), 1, q_length - 1);
            u.metres += step;
            q_event("CARRY", u, second, u.x, u.y);
            q_move(a, owner, 1.0);
            elapsed += 1.0;
            continue;
        }
        bool cross = b(u.unit, "free_kick");
        u.unit["free_kick"] = false;
        if (!cross)
            cross = u.slot != "GK" && q_progress(u) > q_length * 0.48 &&
                    (std::abs(u.y-q_width/2)>q_width*0.20) &&
                    rng->randf() < k("set_piece_share", "SET_PIECE_SHARE");
        if (q_offside && q_progress(a[target]) > q_length / 2 && q_progress(a[target]) > q_progress(u)) {
            std::vector<double> line;
            for (const auto &d : a)
                if (d.active && d.side != side)
                    line.push_back(side == 0 ? d.x : q_length - d.x);
            std::sort(line.begin(), line.end(), std::greater<double>());
            if (line.size() >= 2 && q_progress(a[target]) > line[1]) {
                q_event("OFFSIDE", a[target], second, a[target].x, a[target].y);
                q_restart(a, owner, 1 - side);
                assist = 0;
                q_second_assist=0;
                elapsed += 6.0;
                continue;
            }
        }
        ++u.stats[cross ? 9 : 0];
        double receive_x = cross ? q_goal_x(side) + (side == 0 ? -5.0 : 5.0) : a[target].x;
        double receive_y = cross ? clamp(a[target].y, q_width / 2 - 4, q_width / 2 + 4) : a[target].y;
        double d = q_distance(u.x, u.y, receive_x, receive_y),
               skill = q_skill(u, cross ? Q_DELIVERY : Q_PASS);
        double error = (21 - skill) * 0.055 * std::max(0.5, d / 10.0);
        double tx = receive_x + rng->randfn(0, error), ty = receive_y + rng->randfn(0, error);
        double vx = tx - u.x, vy = ty - u.y, norm = vx * vx + vy * vy;
        double flight = d / (8 + 0.35 * skill) + (cross ? 0.7 : 0);
        int interceptor = -1;
        double first = 1e100;
        for (int j = 0; j < int(a.size()); ++j) {
            auto &x = a[j];
            if (!x.active || x.side == side || (!cross && x.slot == "GK"))
                continue;
            double f = norm > 0 ? ((x.x - u.x) * vx + (x.y - u.y) * vy) / norm : 0;
            if (f < 0.05 || f > 1.08)
                continue;
            double lateral = q_distance(x.x, x.y, u.x + f * vx, u.y + f * vy);
            double ability = q_skill(x, x.slot == "GK" ? Q_AIR : (cross ? Q_STRENGTH : Q_DEFEND));
            double available = std::max(0.0, flight * f - (0.9 - 0.035 * ability));
            double reach = 0.35 + 0.04 * ability + fc_action::speed(x.skill[Q_PACE], x.fresh) * available;
            if (cross && x.slot != "GK" && f < 0.75)
                continue;
            if (cross && x.slot == "GK")
                reach = std::min(reach, 2.0 + 0.15 * q_skill(x, Q_EXITS));
            if (lateral < reach && f < first) {
                interceptor = j;
                first = f;
            }
        }
        if (cross && interceptor >= 0 &&
            q_distance(a[target].x, a[target].y, receive_x, receive_y) <=
                fc_action::speed(a[target].skill[Q_PACE], a[target].fresh) * flight * 0.8 + 1.2) {
            auto &contest = a[interceptor];
            if (rng->randf() >= fc_action::duel(q_skill(contest, contest.slot == "GK" ? Q_AIR : Q_STRENGTH),
                                                q_skill(a[target], Q_STRENGTH),
                                                knob("duel_skill_influence", 1))) {
                ++a[target].stats[11];
                q_event("AERIAL_DUEL", a[target], second, a[target].x, a[target].y, contest.id);
                interceptor = -1;
            }
        }
        if (tx < 0 || tx > q_length || ty < 0 || ty > q_width) {
            q_event("OUT", u, second, clamp(tx, 0, q_length), clamp(ty, 0, q_width));
            owner = q_nearest(a, 1 - side, clamp(tx, 1, q_length - 1), clamp(ty, 1, q_width - 1));
            if (owner >= 0) {
                a[owner].x = clamp(tx, 1, q_length - 1);
                a[owner].y = clamp(ty, 1, q_width - 1);
            }
            assist = 0;
            q_second_assist=0;
            elapsed += flight + 8;
            continue;
        }
        q_move(a, owner, flight, target);
        elapsed += flight;
        if (cross) {
            auto &receiver = a[target];
            double distance = q_distance(receiver.x, receiver.y, receive_x, receive_y);
            double run =
                std::min(distance, fc_action::speed(receiver.skill[Q_PACE], receiver.fresh) * flight * 0.8);
            if (distance > 0.0001) {
                receiver.x += (receive_x - receiver.x) * run / distance;
                receiver.y += (receive_y - receiver.y) * run / distance;
                receiver.metres += run;
            }
        }
        if (side == 0)
            home_time += flight;
        else
            away_time += flight;
        if (interceptor >= 0) {
            ++a[interceptor].stats[cross ? 11 : 7];
            q_event("INTERCEPTION", a[interceptor], second, a[interceptor].x, a[interceptor].y, u.id);
            owner = interceptor;
            assist = 0;
            q_second_assist=0;
            continue;
        }
        double catch_radius = 0.7 + 0.06 * q_skill(a[target], Q_TECH);
        bool received = q_distance(a[target].x, a[target].y, tx, ty) <= catch_radius;
        if (received) {
            ++u.stats[cross ? 10 : 1];
            ++a[target].stats[2];
            owner = target;
            q_second_assist=assist;
            assist = u.id;
            q_move(a, owner, fc_action::trap(q_skill(a[target], Q_TECH)));
            elapsed += fc_action::trap(q_skill(a[target], Q_TECH));
        } else {
            ++a[target].stats[3];
            owner = q_nearest(a, 1 - side, tx, ty);
            assist = 0;
            q_second_assist=0;
        }
        q_event(cross ? "CROSS" : "PASS", u, second, tx, ty, a[target].id, received);
    }
    for (auto &x : a) {
        x.unit["pitch_x"] = x.x;
        x.unit["pitch_y"] = x.y;
        x.unit["fresh"] = x.fresh;
        x.entry["final_freshness"] = int(std::round(x.fresh*100));
        inc(x.entry, "distance_metres", int(std::round(x.metres)));
        for (int k = 0; k < 14; ++k)
            inc(x.entry, q_stat(k), x.stats[k]);
        x.entry["intensity_minutes"] =
            n(x.entry, "intensity_minutes") + 5 * n(x.side == 0 ? home : away, "intensity");
    }
    if (owner >= 0) {
        ball["owner"] = a[owner].id;
        ball["side"] = a[owner].side;
        ball["assist"] = assist;
        ball["second_assist"]=q_second_assist;
        home["pitch_ball"] = ball;
    }
    double total = std::max(home_time + away_time, 0.001);
    home["possession_sum"] = n(home, "possession_sum") + home_time / total;
    away["possession_sum"] = n(away, "possession_sum") + away_time / total;
}
