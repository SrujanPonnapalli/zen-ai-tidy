"""Scores tidy-helper against expected groups. Usage: python3 test/eval.py [runs]
Pair-counting: precision = of tab pairs put together, how many belong together;
recall = of pairs that belong together, how many were put together."""
import json, subprocess, sys, time, itertools, pathlib
root = pathlib.Path(__file__).parent.parent
def pairs(groups): return {frozenset(p) for g in groups for p in itertools.combinations(g, 2)}
for f in ["sample-tabs.json", "big-tabs.json"]:
    data = json.loads((root / "test" / f).read_text())
    want = {}
    for t in data["tabs"]:
        if t.get("expect"): want.setdefault(t["expect"], []).append(t["id"])
    t0 = time.time()
    r = subprocess.run([root / "bin/tidy-helper"], input=json.dumps(data), capture_output=True, text=True)
    dt = time.time() - t0
    if r.returncode: print(f, "FAILED", r.stderr); continue
    got = json.loads(r.stdout)["groups"]
    W, G = pairs(want.values()), pairs(g["ids"] for g in got)
    p = len(W & G) / len(G) if G else 0; rc = len(W & G) / len(W)
    f1 = 2 * p * rc / (p + rc) if p + rc else 0
    title = {t["id"]: t["expect"] or "-" for t in data["tabs"]}
    print(f"{f}: F1={f1:.2f} P={p:.2f} R={rc:.2f} {dt:.1f}s")
    for g in got: print(f"   {g['name']:<24} {[title[i] for i in g['ids']]}")
