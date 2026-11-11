#pragma once
#include <algorithm>
#include <cmath>
namespace fc_action {
inline double duel(double own, double opposing, double influence = 1.0) {
    return 1.0 / (1.0 + std::exp(std::clamp((opposing - own) * 0.15 * influence, -12.0, 12.0)));
}
inline double speed(double skill, double freshness = 1.0) {
    return (3.0 + 0.2 * skill) * (0.5 + 0.5 * freshness);
}
inline double reaction(double skill) { return 0.48 - 0.017 * skill; }
inline double trap(double skill) { return 0.08 + (21.0 - skill) * 0.035; }
inline double sigma(double skill, double distance, bool penalty = false) {
    return penalty ? 0.12 + 0.007 * std::pow(20.0 - skill, 2)
                   : (0.18 + 2.6 * std::pow(std::max(0.0, 1.0 - skill / 20.0), 1.3)) *
                         std::max(0.5, distance / 12.0);
}
} // namespace fc_action
