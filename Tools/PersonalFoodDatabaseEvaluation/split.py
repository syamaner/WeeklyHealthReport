"""The seeded Part B split into development and held-out sets. Pure.

Negative queries divide evenly (an odd one goes to development); the rest go about 60 per cent to
development and 40 per cent to held-out, both in seeded SHA-256 order.
"""
from sample import seeded_order

DEV_SHARE_NUM, DEV_SHARE_DEN = 3, 5


def split(query_set: dict, seed: int):
    qs = {q["query_id"]: q for q in query_set["queries"]}
    neg = seeded_order(seed, [i for i, q in qs.items() if q["negative"]])
    pos = seeded_order(seed, [i for i, q in qs.items() if not q["negative"]])
    dev_ids = set(neg[:(len(neg) + 1) // 2]) | set(pos[:(len(pos) * DEV_SHARE_NUM + DEV_SHARE_DEN // 2) // DEV_SHARE_DEN])
    out = {}
    for name, keep in (("development", lambda i: i in dev_ids), ("held-out", lambda i: i not in dev_ids)):
        out[name] = {"schema": "pfd-query-set-v1", "release_id": query_set["release_id"], "set": name,
                     "queries": [qs[i] for i in sorted(qs) if keep(i)]}
    return out
