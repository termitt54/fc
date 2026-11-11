#pragma once
#include <limits>
#include <vector>
namespace fc_assignment {
inline std::vector<int> solve(const std::vector<std::vector<double>> &weights) {
    int rows = int(weights.size());
    if (!rows)
        return {};
    int columns = int(weights[0].size());
    if (columns < rows)
        return std::vector<int>(rows, -1);
    std::vector<double> u(rows + 1), v(columns + 1);
    std::vector<int> matched(columns + 1), way(columns + 1);
    for (int row = 1; row <= rows; ++row) {
        matched[0] = row;
        int column = 0;
        std::vector<double> minimum(columns + 1, std::numeric_limits<double>::infinity());
        std::vector<bool> used(columns + 1);
        do {
            used[column] = true;
            int active = matched[column], next = 0;
            double delta = std::numeric_limits<double>::infinity();
            for (int j = 1; j <= columns; ++j)
                if (!used[j]) {
                    double cost = -weights[active - 1][j - 1] - u[active] - v[j];
                    if (cost < minimum[j]) {
                        minimum[j] = cost;
                        way[j] = column;
                    }
                    if (minimum[j] < delta) {
                        delta = minimum[j];
                        next = j;
                    }
                }
            for (int j = 0; j <= columns; ++j) {
                if (used[j]) {
                    u[matched[j]] += delta;
                    v[j] -= delta;
                } else
                    minimum[j] -= delta;
            }
            column = next;
        } while (matched[column] != 0);
        do {
            int previous = way[column];
            matched[column] = matched[previous];
            column = previous;
        } while (column != 0);
    }
    std::vector<int> result(rows, -1);
    for (int j = 1; j <= columns; ++j)
        if (matched[j] > 0)
            result[matched[j] - 1] = j - 1;
    return result;
}
} // namespace fc_assignment
