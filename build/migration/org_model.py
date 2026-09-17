"""Turn the extracted document into the canonical operating model.

The document draws 70 chairs because it draws one per region. A chair is a
seat; the region is the scope of the seating. The 70 are kept whole as the
source record and the 34 seats are built from them, mapping recorded.

Seats are grouped by the document's own code prefix (BM_P, BM_NO -> BM),
which is what the document itself uses to say "same seat, different place".
Grouping on the title would miss it: the Pune seating of the back office is
titled "Back Office / Processing Executives" and the northern one
"Back Office Executives - North".
"""
import json, re
from collections import OrderedDict, defaultdict

d = json.load(open("org_structure.json"))
ch = {c["code"]: c for c in d["chairs"]}
SPLIT = re.compile(r"\s+—\s+")

# The part after the em-dash is a place only sometimes: "— South Zone" is,
# "— Risk Operations" and "— project based" are not. Listing the places is the
# only honest test; guessing from the shape of the string is not.
PLACES = {"North", "North East & East", "South", "West", "East",
          "other West locations", "Pune", "Thane", "South Zone"}

def scope_of(t):
    p = SPLIT.split(t)
    tail = " — ".join(p[1:]) if len(p) > 1 else None
    return tail if tail in PLACES else None

def strip_place(t):
    return SPLIT.split(t)[0] if scope_of(t) else t

def singular(t):
    b = SPLIT.split(t)[0]
    for suf, sing in (("Managers","Manager"),("Executives","Executive"),
                      ("Leaders","Leader"),("Partners","Partner")):
        if b.endswith(suf):
            b = b[:-len(suf)] + sing
    return b

groups = OrderedDict()
for c in d["chairs"]:
    groups.setdefault(c["code"].split("_")[0], []).append(c)

seat_of = {m["code"]: k for k, ms in groups.items() for m in ms}

SEAT = OrderedDict()
for k, ms in groups.items():
    if len(ms) == 1:
        title = strip_place(ms[0]["title"])
    else:
        unplaced = [m for m in ms if scope_of(m["title"]) is None]
        title = unplaced[0]["title"] if unplaced else singular(ms[0]["title"])
    rep = max(ms, key=lambda m: sum(len(m["raci"][x]) for x in m["raci"]))
    # strip the "... across North." sentence the document appends per region
    purpose = re.sub(r"\s*[A-Z][^.]*\b(across|at)\s+(North East & East|other West locations|"
                     r"North|South|East|West|Pune|Thane)\.\s*$", "", rep["purpose"] or "").strip()
    counts = defaultdict(int)
    for m in ms:
        if ch[m["code"]]["parent_code"]:
            counts[seat_of[ch[m["code"]]["parent_code"]]] += 1
    SEAT[k] = {
        "code": k, "title": title,
        "sg_level": ms[0]["sg_level"], "function": rep["function"], "band": rep["band"],
        "purpose": purpose, "track": ms[0]["capability_track"],
        "parent_code": max(counts, key=counts.get) if counts else None,
        "parent_candidates": sorted(counts),
        "members": [m["code"] for m in ms], "rep": rep["code"],
    }

SEATING = [{
    "source_code": c["code"], "seat_code": seat_of[c["code"]],
    "scope_label": scope_of(c["title"]),
    "reports_to_seat": seat_of[c["parent_code"]] if c["parent_code"] else None,
    "reports_to_source": c["parent_code"],
    "holder_text": c["holder_text"], "document_title": c["title"], "note": c["note"],
} for c in d["chairs"]]

def split_scope(name):
    """A process drawn once per region carries the place after an em-dash.
    Everything else after an em-dash is part of the process name: "Financial
    statements - P&L, balance sheet and cash flow" is one process, not a
    process scoped to a balance sheet."""
    p = SPLIT.split(name)
    if len(p) > 1:
        tail = " — ".join(p[1:])
        if tail in PLACES or tail == "locations not yet registered":
            return p[0], tail
    return name, None

PROC = OrderedDict(); ref_to_proc = {}
for p in d["processes"]:
    base, scope = split_scope(p["name"])
    PROC.setdefault(base, {"ref": None, "name": base,
                           "family": re.match(r"[A-Z]+", p["ref"]).group(0), "instances": []})
    PROC[base]["instances"].append({"ref": p["ref"], "scope_label": scope, "row": p})
    ref_to_proc[p["ref"]] = base
for v in PROC.values():
    v["ref"] = sorted(v["instances"], key=lambda i: (len(i["ref"]), i["ref"]))[0]["ref"]

TRACK = OrderedDict()
for c in d["chairs"]:
    TRACK.setdefault(c["capability_track"], {
        "name": c["capability_track"], "knowledge_test": c["knowledge_test"],
        "topics": c["knowledge_topics"], "unlock": c["unlock"],
        "levels": c["levels"], "psychometric": c["psychometric"]})

json.dump({"seats": list(SEAT.values()), "seatings": SEATING,
           "processes": list(PROC.values()), "tracks": list(TRACK.values()),
           "seat_of": seat_of, "ref_to_proc": ref_to_proc},
          open("org_model.json", "w"), indent=1, ensure_ascii=False)

print(f"seats     : {len(SEAT):>4}   from {len(d['chairs'])} document chairs")
print(f"seatings  : {len(SEATING):>4}   every document chair kept")
print(f"processes : {len(PROC):>4}   from {len(d['processes'])} document rows")
print(f"instances : {sum(len(p['instances']) for p in PROC.values()):>4}")
print(f"tracks    : {len(TRACK):>4}")
print(f"levels    : {sum(len(t['levels']) for t in TRACK.values()):>4}")
assert len(SEATING) == len(d["chairs"])
assert sum(len(p["instances"]) for p in PROC.values()) == len(d["processes"])
assert len({s['code'] for s in SEAT.values()}) == len(SEAT)
print("\nroot seat:", [s["code"] for s in SEAT.values() if not s["parent_code"]])
print("seats reporting to >1 seat:",
      {s["code"]: s["parent_candidates"] for s in SEAT.values() if len(s["parent_candidates"])>1})
print("\nseat titles:")
for s in SEAT.values():
    n = len(s["members"])
    print(f"  {s['code']:<5} {s['sg_level']} {s['title']:<42} seatings={n}")
