"""Extract the Crux operating-structure document into structured JSON.

The document is the owner's source of truth for chairs, processes, RACI,
information flow and the L1-L5 clearance ladders. Everything here is read
out of stable ids and classes; nothing is inferred.
"""
from bs4 import BeautifulSoup
import json, re, sys

SRC = "/root/.claude/uploads/3c6ed611-4ad2-5f5e-a5ff-3d2e39050bcc/2e7c8107-Crux_Operating_Structure_Recommendation_1.html"
soup = BeautifulSoup(open(SRC, encoding="utf-8").read(), "lxml")

txt = lambda n: n.get_text(" ", strip=True) if n else None
code_of = lambda href: href.split("#d-")[-1] if href and "#d-" in href else None

# ---------------------------------------------------------------- hierarchy
# The nested <ul> in #chart is the reporting structure itself.
hierarchy = {}          # child code -> parent code
blocks = {}             # chair code -> which chart block it was drawn in
for det in soup.select("#chart details.blk"):
    block = txt(det.select_one("summary .bt"))
    for li in det.select("div.tree li"):
        a = li.find("a", class_="ch", recursive=False)
        if not a:
            continue
        me = code_of(a.get("href"))
        blocks.setdefault(me, block)
        pli = li.find_parent("li")
        parent = None
        if pli:
            pa = pli.find("a", class_="ch", recursive=False)
            parent = code_of(pa.get("href")) if pa else None
        # a chair repeated in a second block must not lose its real parent
        if me not in hierarchy or (hierarchy[me] is None and parent):
            hierarchy[me] = parent

# ---------------------------------------------------------------- dossiers
def raci_items(ul):
    out = []
    for li in ul.select("li"):
        if "nil" in (li.get("class") or []):
            continue
        rf = li.find("span", class_="rf")
        ref = txt(rf)
        if rf:
            rf.extract()
        out.append({"text": li.get_text(" ", strip=True), "process_ref": ref})
    return out

def flow_items(ul):
    out = []
    for li in ul.select("li"):
        rf = li.find("span", class_="rf")
        ref = txt(rf)
        if rf: rf.extract()
        srcspan = li.find("span", class_="src")
        counterpart, cp_code = None, None
        if srcspan:
            a = srcspan.find("a")
            cp_code = code_of(a.get("href")) if a else None
            counterpart = txt(a) if a else txt(srcspan)
            srcspan.extract()
        out.append({"text": li.get_text(" ", strip=True),
                    "counterpart": counterpart, "counterpart_code": cp_code,
                    "process_ref": ref})
    return out

def section_after(article, heading_text, selector):
    """The first `selector` node that follows the given h4/h6."""
    for h in article.select("h4, h6"):
        t = txt(h)
        if t and t.startswith(heading_text):
            n = h.find_next_sibling()
            while n is not None and not n.select_one(selector) and not (
                    n.name and selector.lstrip(".") in (n.get("class") or [])):
                if n.name in ("h4", "h6"):
                    return None, t
                n = n.find_next_sibling()
            return n, t
    return None, None

chairs = []
for art in soup.select("article.dos"):
    code = art.get("id", "").replace("d-", "")
    dtag = txt(art.select_one(".dtag")) or ""
    # "Governance · SG7 Enterprise"
    parts = [p.strip() for p in dtag.split("·")]
    function = parts[0] if parts else None
    sg, band = None, None
    if len(parts) > 1:
        m = re.match(r"(SG\d)\s*(.*)", parts[1])
        if m:
            sg, band = m.group(1), (m.group(2) or None)

    meta = {}
    for d in art.select("dl.meta > div"):
        meta[txt(d.find("dt"))] = d.find("dd")
    rt_dd = meta.get("Reports to")
    rt_link = rt_dd.find("a") if rt_dd else None
    parent_from_meta = code_of(rt_link.get("href")) if rt_link else None
    reports_to = txt(rt_dd)
    direct = [{"code": code_of(a.get("href")), "title": txt(a)}
              for a in (meta.get("Direct reports").select("a.xl") if meta.get("Direct reports") else [])]

    stats = {}
    for st in art.select(".stats .st"):
        b = st.find("b")
        label = st.get_text(" ", strip=True).replace(txt(b) or "", "", 1).strip()
        stats[label] = int(txt(b))

    raci = {}
    for key, cls in (("owns", "a"), ("does", "r"), ("advises", "c"), ("informed", "i")):
        row = art.select_one(f".rblk .rrow.{cls} ul")
        raci[key] = raci_items(row) if row else []

    flow = {"receives": [], "supplies": []}
    for fc in art.select(".flow .fcol"):
        head = txt(fc.find("h6")) or ""
        items = flow_items(fc.find("ul")) if fc.find("ul") else []
        if head.startswith("Expects"): flow["receives"] = items
        elif head.startswith("Must supply"): flow["supplies"] = items

    def bullets(heading):
        for h in art.select("h4"):
            if txt(h) == heading:
                ul = h.find_next_sibling("ul")
                return [li.get_text(" ", strip=True) for li in ul.find_all("li", recursive=False)] if ul else []
        return []

    tasks = []
    for h in art.select("h4"):
        if txt(h) == "Tasks and sub-tasks":
            ul = h.find_next_sibling("ul")
            if ul:
                for li in ul.find_all("li", recursive=False):
                    b = li.find("b")
                    sub = li.find("ul")
                    tasks.append({"task": txt(b),
                                  "subtasks": [txt(x) for x in sub.find_all("li")] if sub else []})

    auth = {"can_decide": [], "must_escalate": []}
    ab = art.select_one(".auth")
    if ab:
        can = ab.select_one(".can")
        esc = ab.select_one(".esc")
        if can: auth["can_decide"] = [txt(li) for li in can.select("li")]
        if esc: auth["must_escalate"] = [txt(li) for li in esc.select("li")]

    track = None
    for h in art.select("h4"):
        t = txt(h) or ""
        if t.startswith("Clearance levels"):
            track = t.split("·", 1)[1].strip() if "·" in t else None
            if track and track.endswith(" track"):
                track = track[:-len(" track")]

    levels = []
    for step in art.select(".lad .step"):
        g = {}
        for d in step.select("dl.gate > div"):
            g[txt(d.find("dt"))] = txt(d.find("dd"))
        levels.append({
            "level": txt(step.select_one(".lv")),
            "name": txt(step.select_one(".nm")),
            "requirement": txt(step.select_one("p.req")),
            "qualification": g.get("Qualification"),
            "experience": g.get("Experience"),
            "certification": g.get("Certification"),
            "test_score": g.get("Test score"),
            "evidence": g.get("Evidence to clear the gate"),
        })

    ktest, ktopics, psych = None, [], []
    for blk in art.select(".assess > div"):
        h = txt(blk.find("h6")) or ""
        if h.startswith("Knowledge test"):
            ktest = h.split("·", 1)[1].strip() if "·" in h else None
            ktopics = [txt(li) for li in blk.select("li")]
        elif h.startswith("Psychometric"):
            for li in blk.select("li"):
                b = li.find("b"); s = li.find("span")
                psych.append({"instrument": txt(b), "standard": txt(s)})

    chairs.append({
        "code": code,
        "title": txt(art.select_one(".dt")),
        "holder_text": txt(art.select_one(".who")),
        "function": function, "sg_level": sg, "band": band,
        "chart_block": blocks.get(code),
        "parent_code": parent_from_meta or hierarchy.get(code),
        "parent_from_chart": hierarchy.get(code),
        "parent_from_meta": parent_from_meta,
        "reports_to_text": reports_to,
        "direct_reports": direct,
        "purpose": txt(art.select_one("p.pur")),
        "note": txt(art.select_one("p.note")),
        "unlock": txt(art.select_one("p.unlock")),
        "stats": stats,
        "raci": raci,
        "flow": flow,
        "accountabilities": bullets("Accountabilities"),
        "measured_on": bullets("Measured on"),
        "tasks": tasks,
        "authority": auth,
        "capability_track": track,
        "levels": levels,
        "knowledge_test": ktest,
        "knowledge_topics": ktopics,
        "psychometric": psych,
    })

# ---------------------------------------------------------------- processes
processes = []
for tbl in soup.select("#matrix table"):
    for tr in tbl.select("tbody tr"):
        cells = tr.find_all(["td", "th"])
        if len(cells) < 7:
            continue
        def names(td):
            return [txt(a) for a in td.select("a")] or (
                [p.strip() for p in txt(td).split("·")] if txt(td) and txt(td) != "—" else [])
        inputs = []
        for li in cells[6].select("span.ip"):
            a = li.find("a")
            if a:
                supplier, scode = txt(a), code_of(a.get("href"))
                a.extract()
            else:
                supplier, scode = None, None
            inputs.append({"input": li.get_text(" ", strip=True),
                           "supplier": supplier, "supplier_code": scode})
        if not inputs and txt(cells[6]) and txt(cells[6]) != "—":
            inputs.append({"input": txt(cells[6]), "supplier": None, "supplier_code": None})
        processes.append({
            "ref": txt(cells[0]),
            "name": txt(cells[1]),
            "owns": names(cells[2]),
            "does": names(cells[3]),
            "advises": names(cells[4]),
            "informed": names(cells[5]),
            "inputs": inputs,
        })

out = {"chairs": chairs, "processes": processes}
json.dump(out, open("org_structure.json", "w"), indent=1, ensure_ascii=False)

print("chairs        :", len(chairs))
print("processes     :", len(processes))
print("input links   :", sum(len(p["inputs"]) for p in processes))
print("tracks        :", len({c["capability_track"] for c in chairs if c["capability_track"]}))
print("levels        :", sum(len(c["levels"]) for c in chairs))
print("chairs w/o parent:", [c["code"] for c in chairs if not c["parent_code"]])
dis = [(c["code"], c["parent_from_meta"], c["parent_from_chart"]) for c in chairs
       if c["parent_from_meta"] and c["parent_from_chart"]
       and c["parent_from_meta"] != c["parent_from_chart"]]
print("parent disagreements (meta vs chart):", dis or "none")
print("chairs missing sg:", [c["code"] for c in chairs if not c["sg_level"]])
print("chairs missing track:", [c["code"] for c in chairs if not c["capability_track"]])
