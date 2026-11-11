#include "fc_sim_core.h"
#include <algorithm>
#include <unordered_set>
#include <vector>
namespace godot {
namespace {
double v(const Dictionary &d,const char *key,double fallback=0) {return double(d.get(key,fallback));}
struct Target {int index;int64_t id;double score;};
}
Dictionary FCSimCore::planner_index(Array candidates) {
    Dictionary result;
    for(const char *key:{"id","owner","nation","age"}) {
        PackedInt64Array column;column.resize(candidates.size());
        for(int j=0;j<candidates.size();++j){Dictionary row=candidates[j];column.set(j,int64_t(row[key]));}
        result[key]=column;
    }
    for(const char *key:{"quality","pa","fee"}) {
        PackedFloat64Array column;column.resize(candidates.size());
        for(int j=0;j<candidates.size();++j){Dictionary row=candidates[j];column.set(j,v(row,key));}
        result[key]=column;
    }
    return result;
}
Array FCSimCore::planner_shortlist(Array candidates,Dictionary need,int64_t buyer,int64_t nation,
                                  int64_t cap,Array excluded,int64_t skill,
                                  Ref<RandomNumberGenerator> rng,int64_t limit) {
    std::unordered_set<int64_t> skipped;
    for(int j=0;j<excluded.size();++j)skipped.insert(int64_t(excluded[j]));
    std::vector<Target> ranked;
    const double baseline=v(need,"baseline"),minimum=v(need,"minimum"),out=v(need,"out_quality");
    const bool foreign=bool(need.get("allow_foreign",true)), succession=bool(need.get("succession",false));
    Dictionary packed=need.get("_native_index",Dictionary());
    bool indexed=packed.has("id");
    PackedInt64Array ids,owners,nations,ages;
    PackedFloat64Array fees,qualities,potentials;
    if(indexed){ids=packed["id"];owners=packed["owner"];nations=packed["nation"];ages=packed["age"];fees=packed["fee"];qualities=packed["quality"];potentials=packed["pa"];}
    const int64_t *ip=indexed?ids.ptr():nullptr,*op=indexed?owners.ptr():nullptr,*np=indexed?nations.ptr():nullptr,*ap=indexed?ages.ptr():nullptr;
    const double *fp=indexed?fees.ptr():nullptr,*qp=indexed?qualities.ptr():nullptr,*pp=indexed?potentials.ptr():nullptr;
    int64_t seed=int64_t(need.get("noise_seed",int64_t(0)));
    double required_pa=v(need,"ca");
    Dictionary row;
    for(int i=0;i<candidates.size();++i) {
        if(!indexed)row=candidates[i];
        int64_t id=indexed?ip[i]:int64_t(row["id"]),owner=indexed?op[i]:int64_t(row["owner"]),country=indexed?np[i]:int64_t(row["nation"]);
        double fee=indexed?fp[i]:v(row,"fee"),quality=indexed?qp[i]:v(row,"quality"),potential=indexed?pp[i]:v(row,"pa"),age=indexed?ap[i]:v(row,"age");
        if(owner==buyer || skipped.count(id) || fee>double(cap))continue;
        if(!foreign && country>0 && nation>0 && country!=nation)continue;
        bool successor=succession && age<=26 && quality>=std::max(baseline-1.0,out+2.0) && potential>=required_pa+2;
        if(quality<minimum && !successor)continue;
        double score=(quality-baseline)*8.0+std::max(0.0,potential-required_pa)*0.12-fee/std::max(1.0,double(cap))*3.0;
        if(successor)score+=3.0;
        double noise=double((id*1103515245LL+seed*12345LL)%2147483647LL)/2147483647.0*2.0-1.0;
        score+=noise*double(20-skill)*0.4;
        ranked.push_back({i,id,score});
    }
    std::sort(ranked.begin(),ranked.end(),[](const Target&a,const Target&b){return a.score!=b.score?a.score>b.score:a.id<b.id;});
    Array result;
    for(int j=0;j<std::min(int64_t(ranked.size()),std::max(int64_t(0),limit));++j)result.append(ranked[j].index);
    return result;
}
}
