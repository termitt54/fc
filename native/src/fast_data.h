#pragma once
// Lazy input views keep player records attached to their Godot dictionaries.
// Match actors/reports own plain C++ values; conversion happens at the boundary.
// Shared state preserves actor/entry identity when several match structures refer
// to the same player. Mutable simulation entities require unique player IDs.
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>
namespace godot {
inline std::string fast_key_string(const String& key) {
    auto bytes = key.utf8();
    return std::string(bytes.get_data(), bytes.length());
}
struct FastDictState;
struct FastArrayState;
class FastCell;
class FastDict {
    std::shared_ptr<FastDictState> state;

  public:
    FastDict();
    FastDict(const Dictionary& raw);
    FastDict(const Variant& raw);
    FastCell& operator[](const char* key);
    FastCell& operator[](const std::string& key) {
        return (*this)[key.c_str()];
    }
    FastCell& operator[](const String& key);
    FastCell& operator[](int64_t key);
    FastCell& operator[](const FastCell& key);
    FastCell get(const char* key, const FastCell& fallback) const;
    FastCell get(const String& key, const FastCell& fallback) const;
    FastCell get(const std::string& key, const FastCell& fallback) const;
    bool has(const char* key) const;
    bool has(const String& key) const;
    bool has(const std::string& key) const {
        return has(key.c_str());
    }
    bool is_empty() const;
    void erase(const char* key);
    FastDict duplicate() const;
    class FastArray keys() const;
    Dictionary to_godot() const;
    operator Dictionary() const {
        return to_godot();
    }
    bool same(const FastDict& other) const {
        return state == other.state;
    }
};
class FastArray {
    std::shared_ptr<FastArrayState> state;
    void load() const;

  public:
    FastArray();
    FastArray(const Array& raw);
    FastArray(const Variant& raw);
    int size() const;
    bool is_empty() const {
        return size() == 0;
    }
    FastCell& operator[](int index);
    const FastCell& operator[](int index) const;
    void append(const FastCell& value);
    void remove_at(int index);
    int find(const FastDict& value) const;
    void erase(const FastDict& value);
    FastCell back() const;
    FastArray duplicate() const;
    Array to_godot() const;
    operator Array() const {
        return to_godot();
    }
    std::vector<FastCell>& cells();
};
class FastCell {
    using Storage =
        std::variant<std::monostate, bool, int64_t, double, std::string, FastDict, FastArray, Variant>;
    Storage value;

  public:
    FastCell() = default;
    FastCell(bool v) : value(v) {}
    FastCell(int v) : value(int64_t(v)) {}
    FastCell(int64_t v) : value(v) {}
    FastCell(double v) : value(v) {}
    FastCell(float v) : value(double(v)) {}
    FastCell(const char* v) : value(std::string(v)) {}
    FastCell(const std::string& v) : value(v) {}
    FastCell(String v) : value(fast_key_string(v)) {}
    FastCell(FastDict v) : value(v) {}
    FastCell(FastArray v) : value(v) {}
    FastCell(const PackedFloat32Array& v) : value(Variant(v)) {}
    FastCell(const Variant& v) {
        switch (v.get_type()) {
        case Variant::NIL:
            break;
        case Variant::BOOL:
            value = bool(v);
            break;
        case Variant::INT:
            value = int64_t(v);
            break;
        case Variant::FLOAT:
            value = double(v);
            break;
        case Variant::STRING:
            value = fast_key_string(String(v));
            break;
        case Variant::STRING_NAME:
            value = fast_key_string(String(v));
            break;
        case Variant::DICTIONARY:
            value = FastDict(Dictionary(v));
            break;
        case Variant::ARRAY:
            value = FastArray(Array(v));
            break;
        default:
            value = v;
        }
    }
    double number() const {
        if (auto p = std::get_if<double>(&value))
            return *p;
        if (auto p = std::get_if<int64_t>(&value))
            return double(*p);
        if (auto p = std::get_if<bool>(&value))
            return *p ? 1.0 : 0.0;
        return 0;
    }
    operator double() const {
        return number();
    }
    operator int64_t() const {
        return int64_t(number());
    }
    operator bool() const {
        if (auto p = std::get_if<bool>(&value))
            return *p;
        if (std::holds_alternative<int64_t>(value) || std::holds_alternative<double>(value))
            return number() != 0;
        if (auto p = std::get_if<std::string>(&value))
            return !p->empty();
        return !std::holds_alternative<std::monostate>(value);
    }
    operator String() const {
        if (auto p = std::get_if<std::string>(&value))
            return String::utf8(p->c_str());
        return String();
    }
    operator std::string() const {
        if (auto p = std::get_if<std::string>(&value))
            return *p;
        return std::string();
    }
    operator FastDict() const {
        if (auto p = std::get_if<FastDict>(&value))
            return *p;
        return FastDict();
    }
    operator FastArray() const {
        if (auto p = std::get_if<FastArray>(&value))
            return *p;
        return FastArray();
    }
    operator PackedFloat32Array() const {
        if (auto p = std::get_if<Variant>(&value))
            return PackedFloat32Array(*p);
        return PackedFloat32Array();
    }
    bool is_dict() const {
        return std::holds_alternative<FastDict>(value);
    }
    Variant to_godot() const {
        if (auto p = std::get_if<bool>(&value))
            return Variant(*p);
        if (auto p = std::get_if<int64_t>(&value))
            return Variant(*p);
        if (auto p = std::get_if<double>(&value))
            return Variant(*p);
        if (auto p = std::get_if<std::string>(&value))
            return Variant(String::utf8(p->c_str()));
        if (auto p = std::get_if<FastDict>(&value))
            return Variant(p->to_godot());
        if (auto p = std::get_if<FastArray>(&value))
            return Variant(p->to_godot());
        if (auto p = std::get_if<Variant>(&value))
            return *p;
        return Variant();
    }
};
struct FastStringHash {
    using is_transparent = void;
    size_t operator()(std::string_view value) const {
        return std::hash<std::string_view>{}(value);
    }
};
struct FastDictState {
    std::optional<Dictionary> raw;
    bool has_raw = false;
    mutable std::vector<std::pair<std::string, FastCell>> fields;
    mutable std::unordered_map<std::string, size_t, FastStringHash, std::equal_to<>> lookup;
    mutable bool dirty = false;
};
struct FastArrayState {
    std::optional<Array> raw;
    bool has_raw = false;
    mutable bool loaded = true;
    mutable std::vector<FastCell> values;
};
inline std::string fast_key(const String& key) {
    auto bytes = key.utf8();
    return std::string(bytes.get_data(), bytes.length());
}
inline FastDict::FastDict() : state(std::make_shared<FastDictState>()) {}
inline FastDict::FastDict(const Dictionary& raw) : FastDict() {
    state->raw = raw;
    state->has_raw = true;
}
inline FastDict::FastDict(const Variant& raw)
    : FastDict(raw.get_type() == Variant::DICTIONARY ? Dictionary(raw) : Dictionary()) {}
inline FastCell FastDict::get(const char* key, const FastCell& fallback) const {
    auto found = state->lookup.find(key);
    if (found != state->lookup.end())
        return state->fields[found->second].second;
    if (!state->has_raw || !state->raw->has(key))
        return fallback;
    FastCell cell(state->raw->get(key, Variant()));
    state->lookup[key] = state->fields.size();
    state->fields.emplace_back(key, cell);
    return cell;
}
inline FastCell FastDict::get(const std::string& key, const FastCell& fallback) const {
    return get(key.c_str(), fallback);
}
inline FastCell FastDict::get(const String& key, const FastCell& fallback) const {
    return get(fast_key(key).c_str(), fallback);
}
inline FastCell& FastDict::operator[](const char* key) {
    auto found = state->lookup.find(key);
    if (found == state->lookup.end()) {
        FastCell v = state->has_raw ? FastCell(state->raw->get(key, Variant())) : FastCell();
        size_t index = state->fields.size();
        state->fields.emplace_back(key, v);
        state->lookup[key] = index;
        found = state->lookup.find(key);
    }
    state->dirty = true;
    return state->fields[found->second].second;
}
inline FastCell& FastDict::operator[](const String& key) {
    return (*this)[fast_key(key).c_str()];
}
inline FastCell& FastDict::operator[](int64_t key) {
    return (*this)[("@integer:" + std::to_string(key)).c_str()];
}
inline FastCell& FastDict::operator[](const FastCell& key) {
    return (*this)[std::string(key)];
}
inline bool FastDict::has(const char* key) const {
    return state->lookup.count(key) > 0 || (state->has_raw && state->raw->has(key));
}
inline bool FastDict::has(const String& key) const {
    return has(fast_key(key).c_str());
}
inline bool FastDict::is_empty() const {
    return state->fields.empty() && (!state->has_raw || state->raw->is_empty());
}
inline FastDict FastDict::duplicate() const {
    FastDict out;
    *out.state = *state;
    return out;
}
inline void FastDict::erase(const char* key) {
    if (state->has_raw) {
        state->raw = state->raw->duplicate();
        state->raw->erase(key);
    }
    auto it = state->lookup.find(key);
    if (it != state->lookup.end()) {
        state->fields.erase(state->fields.begin() + it->second);
        state->lookup.clear();
        for (size_t j = 0; j < state->fields.size(); ++j)
            state->lookup[state->fields[j].first] = j;
    }
    state->dirty = true;
}
inline Dictionary FastDict::to_godot() const {
    if (state->has_raw && !state->dirty)
        return *state->raw;
    Dictionary out = state->has_raw ? state->raw->duplicate() : Dictionary();
    for (auto& field : state->fields) {
        if (field.first.rfind("@integer:", 0) == 0)
            out[int64_t(std::stoll(field.first.substr(9)))] = field.second.to_godot();
        else
            out[String::utf8(field.first.c_str())] = field.second.to_godot();
    }
    return out;
}
inline FastArray FastDict::keys() const {
    FastArray out;
    if (state->has_raw) {
        Array keys = state->raw->keys();
        for (int j = 0; j < keys.size(); ++j) {
            String key = keys[j];
            get(key, FastCell());
            out.append(key);
        }
    }
    for (auto& field : state->fields)
        if (!state->has_raw || !state->raw->has(String::utf8(field.first.c_str())))
            out.append(String::utf8(field.first.c_str()));
    return out;
}
inline FastArray::FastArray() : state(std::make_shared<FastArrayState>()) {}
inline FastArray::FastArray(const Array& raw) : FastArray() {
    state->raw = raw;
    state->has_raw = true;
    state->loaded = false;
}
inline FastArray::FastArray(const Variant& raw)
    : FastArray(raw.get_type() == Variant::ARRAY ? Array(raw) : Array()) {}
inline void FastArray::load() const {
    if (state->loaded)
        return;
    for (int j = 0; j < state->raw->size(); ++j)
        state->values.emplace_back((*state->raw)[j]);
    state->loaded = true;
}
inline int FastArray::size() const {
    load();
    return state->values.size();
}
inline FastCell& FastArray::operator[](int index) {
    load();
    state->has_raw = false;
    return state->values[index];
}
inline const FastCell& FastArray::operator[](int index) const {
    load();
    return state->values[index];
}
inline void FastArray::append(const FastCell& value) {
    load();
    state->has_raw = false;
    state->values.push_back(value);
}
inline void FastArray::remove_at(int index) {
    load();
    state->has_raw = false;
    state->values.erase(state->values.begin() + index);
}
inline int FastArray::find(const FastDict& value) const {
    load();
    for (size_t j = 0; j < state->values.size(); ++j)
        if (FastDict(state->values[j]).same(value))
            return j;
    return -1;
}
inline void FastArray::erase(const FastDict& value) {
    int index = find(value);
    if (index >= 0)
        remove_at(index);
}
inline FastCell FastArray::back() const {
    load();
    return state->values.back();
}
inline FastArray FastArray::duplicate() const {
    load();
    FastArray out;
    out.state->values = state->values;
    return out;
}
inline Array FastArray::to_godot() const {
    load();
    Array out;
    for (auto& v : state->values)
        out.append(v.to_godot());
    return out;
}
inline std::vector<FastCell>& FastArray::cells() {
    load();
    state->has_raw = false;
    return state->values;
}
} // namespace godot
