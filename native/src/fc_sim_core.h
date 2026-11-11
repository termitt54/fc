#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <vector>
namespace godot {
class FCSimCore : public RefCounted {
    GDCLASS(FCSimCore, RefCounted)
    friend class FCMatchKernel;
    Dictionary timings;
    std::array<double, 21> recovery_curve{}, condition_curve{}, fresh_curve{};
    std::array<double, 101> play_curve{}, selection_curve{};
    Dictionary data, knobs, attraction_settings;
    double curve(int attr, const char* prefix) const;
    double play_mult(int c) const;
    double select_mult(int c) const;
    double weighted(const Dictionary& ratings, const Dictionary& weights) const;
    Dictionary role_weights, style_weights;
    Dictionary sort_scores;
    Dictionary sort_weights;
    Array available_pool(const Array& players);
    double fit(const String& slot, const String& position) const;
    double role_rating(Dictionary ratings, const String& slot);
    double style_rating(Dictionary ratings, const String& style);
    static int attribute(const Dictionary& p, const char* name, int fallback = 10);
    static String position_of(const Dictionary& p);
    static int condition_of(const Dictionary& p);
    double mix(const Dictionary& attrs, const Array& terms) const;
    double aptitude(const Dictionary& aptitudes, const String& path) const;
    Array secondary_terms(const String& position) const;

  protected:
    static void _bind_methods();

  public:
    int64_t api_version() const {
        return 5;
    }
    String version() const;
    double club_attraction(Dictionary club) const;
    void set_attraction_settings(Dictionary settings) { attraction_settings = settings.duplicate(); }
    Dictionary metrics(bool reset);
    void configure(Dictionary p_data);
    void set_knobs(Dictionary p_knobs);
    Dictionary build_ratings(Dictionary player);
    double ability_exact(Dictionary attrs, String position) const;
    double role_value(Dictionary ratings, String slot, String style);
    Array planner_shortlist(Array candidates, Dictionary need, int64_t buyer, int64_t nation,
                            int64_t cap, Array excluded, int64_t skill,
                            Ref<RandomNumberGenerator> rng, int64_t limit);
    Dictionary planner_index(Array candidates);
    Dictionary rate_pool(Array pool, Array slots, String style);
    void recover_players(Array players, Dictionary played);
    void recover_player(Dictionary player, bool played);
    Dictionary build_lineup(Array squad, Array youth, Dictionary coach, Dictionary plan,
                            Ref<RandomNumberGenerator> rng, bool include_bench);
    Dictionary finish_bench(Dictionary lineup);
    bool less_ability(Dictionary a, Dictionary b);
    bool less_rest(int64_t a, int64_t b);
    Dictionary roll_attributes(Ref<RandomNumberGenerator> rng, String position, int64_t target,
                               Dictionary aptitudes);
    Array roll_birth(Array weights, int64_t count, Ref<RandomNumberGenerator> rng, bool cohort);
    void develop_player(Dictionary player, Dictionary setup, Ref<RandomNumberGenerator> rng,
                        double playing_share, int64_t season);
    int64_t market_amount(String operation, Dictionary args);
    Dictionary offer_profile(Dictionary player, int64_t world_top);
    Dictionary agent_index(Array agents, int64_t world_top);
    int64_t choose_agent(Array agents, Dictionary index, Dictionary selection,
                         Ref<RandomNumberGenerator> rng);
    Dictionary evaluate_offer(Dictionary player, Dictionary club, int64_t negotiations, Dictionary context);
    Array preview_table(Array clubs, Ref<RandomNumberGenerator> rng);
    Dictionary preview_knockout(Array clubs, Ref<RandomNumberGenerator> rng, bool seeded, bool single);
    double score_transfer(Dictionary club, Dictionary player, int64_t skill, String needed,
                          Ref<RandomNumberGenerator> rng);
    double reputation_calc(String operation, Dictionary args);
    double contract_chance(Dictionary player, Dictionary club, int64_t negotiations, Dictionary context);
    Array national_roster(Array candidates, String style, double error, Ref<RandomNumberGenerator> rng);
    Array preview_playoff(Array divisions, Array clubs, int64_t count, bool per_division, bool national,
                          Ref<RandomNumberGenerator> rng);
    void fit_attributes(Dictionary attributes, String position, double target, String prefer_group,
                        Dictionary aptitudes);
    bool less_weight(String a, String b);
    void apply_entry_stats(Dictionary player, Dictionary entry, int64_t season, int64_t club_id);
    void apply_match_load(Dictionary player, int64_t minutes, double intensity);
    Dictionary simulate(Dictionary config, Ref<RandomNumberGenerator> rng, String fingerprint);
    bool less_shootout(Dictionary a, Dictionary b);
    Dictionary select_lineup(Dictionary spec, Dictionary opponent, Ref<RandomNumberGenerator> rng,
                             Dictionary primary);
    Dictionary coaching_profile(String style, String mode, bool conserve);
    Dictionary review_coaching(Dictionary team, Dictionary opponent, int64_t minute);
};
} // namespace godot
