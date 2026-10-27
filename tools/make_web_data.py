# The website's copy of the data: only what the MOE dictionary itself states.
#  - local (腔口) readings: only the places MOE gives for that word (語音差異 / 詞彙比較);
#    readings the app works out by rule (guesses) are left out
#  - app-only helpers (reading statistics) are left out
#   python3 make_web_data.py data_app.json data_web.json
import json, sys
d = json.load(open(sys.argv[1]))
dex = d.get("dex", {})
dia = {}
for k, places in d["dia"].items():
    keep = {p: c for p, c in places.items() if p in dex.get(k, "")}
    if keep: dia[k] = keep
print("local readings kept:", sum(len(v) for v in dia.values()), "of", sum(len(v) for v in d["dia"].values()))
d["dia"] = dia
for f in ("ctx", "dex"): d.pop(f, None)
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False, separators=(",", ":"))
