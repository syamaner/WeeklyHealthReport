#!/usr/bin/env python3
"""Synthetic tests for private_config.py and the code that reads it (no network, no private data).

Usage: python3 -I test_private_config.py <scripts_dir>
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

S = Path(sys.argv[1]).resolve()
EXAMPLE = S.parent / "references" / "private-config-example.json"
results = []


def probe(code, config=None):
    """Run code in a fresh interpreter with PFC_CONFIG set (or unset), returning (rc, stdout+stderr)."""
    env = {k: v for k, v in os.environ.items() if k != "PFC_CONFIG"}
    if config is not None:
        env["PFC_CONFIG"] = str(config)
    r = subprocess.run([sys.executable, "-I", "-c", f"import sys; sys.path.insert(0, {str(S)!r}); {code}"],
                       capture_output=True, text=True, env=env)
    return r.returncode, (r.stdout + r.stderr).strip()


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    os.chmod(tmp, 0o700)
    good = tmp / "config.json"
    good.write_text(EXAMPLE.read_text(encoding="utf-8"), encoding="utf-8")
    os.chmod(good, 0o600)

    rc, out = probe("import private_config as C; print(C.CONFIG == C.EMPTY)")
    results.append(("unset PFC_CONFIG gives the empty, strictest config", rc == 0 and out == "True"))

    rc, out = probe("import extract_items as X; from pathlib import Path; print(X.classify(Path('a.pdf'), 'Your Example Grocer receipt'))")
    results.append(("no config: every layout is unknown", rc == 0 and out == "('unknown', None, None)"))

    rc, out = probe("import http_client as H; H.FOOD_WORDS = {'bakewell'}; H.safe_query('Mr Sample Bakewells')")
    results.append(("no config: a brand that looks like a name is refused", rc != 0 and "refused" in out))

    rc, out = probe("import http_client as H; H.FOOD_WORDS = {'bakewell'}; print(H.safe_query('Mr Sample Bakewells'))", good)
    results.append(("config: the exact brand exception is allowed", rc == 0 and out == "Mr Sample Bakewells"))

    rc, out = probe("import http_client as H; H.FOOD_WORDS = {'bakewell'}; H.safe_query('Mr Other Bakewells')", good)
    results.append(("config: any other honorific is still refused", rc != 0 and "refused" in out))

    rc, out = probe("import extract_items as X; from pathlib import Path; "
                    "print([X.classify(Path(n), t)[0] for n, t in ["
                    "('r.pdf', 'Your Example Grocer receipt'), ('o.pdf', 'Order reference: 1 Example Grocer'), "
                    "('i.pdf', 'thanks from EXAMPLEHEALTH.TEST'), ('Example Online 3.pdf', ''), "
                    "('Oat bar - Example Chemist.pdf', ''), ('x.pdf', 'Order reference: only')]])", good)
    results.append(("config: each layout matches only its own markers",
                    rc == 0 and out == "['example_grocer_receipt', 'example_grocer_order_page', 'example_health_invoice', "
                                       "'example_online_order', 'example_chemist_product_page', 'unknown']"))

    rc, out = probe("import assemble as A; print(A.norm_brand('Alpha and Beta Food'), A.norm_brand('Other Brand'), "
                    "A.score_off('A&B Greek Yogurt', None, {'product_name': 'Greek Yogurt', 'brands': ['Alpha & Beta']})[1])", good)
    results.append(("config: brand aliases normalise and match", rc == 0 and out == "a&b other brand True"))

    rc, out = probe("import assemble as A; print(A.norm_brand('Not Alpha Beta'), '|', A.score_off('A&B Greek Yogurt', None, "
                    "{'product_name': 'Greek Yogurt', 'brands': ['Not Alpha Beta']})[1])", good)
    results.append(("config: a spelling inside another brand is not that brand", rc == 0 and out == "not alpha beta | False"))

    rc, out = probe("import assemble as A; print(A.score_off('Oats', None, {'product_name': 'Alpha Beta Oats', 'brands': ['Other']})[0], "
                    "A.name_coverage('Oats', {'product_name': 'Alpha Beta Oats', 'brands': ['Other']}))", good)
    results.append(("config: alias words are kept for an unrelated brand", rc == 0 and out == "0.8 0.3333333333333333"))

    rc, out = probe("import assemble as A; print(A.score_off('A & B Greek Yogurt', None, "
                    "{'product_name': 'Greek Yogurt', 'brands': ['Alpha and Beta']})[1])", good)
    results.append(("config: a spaced spelling at the start of a title is that brand", rc == 0 and out == "True"))

    rc, out = probe("import assemble as A; print(A.norm_brand('ALPHA & BETA'))", good)
    results.append(("config: spellings are normalised like brands ('and' and '&')", rc == 0 and out == "a&b"))

    rc, out = probe("import extract_items as X; "
                    "r = [{'doc_id': 'd', 'line_no': 1, 'name': 'Favourites Oat Bar'}, {'doc_id': 'd', 'line_no': 2, 'name': 'Favourites Jones note'}]; "
                    "print(X.gate(r, {'d': {'Favourites', 'Favourites Jones note'}}))", good)
    results.append(("config: a chrome word exempts only itself, never a longer header fragment",
                    rc == 0 and out == "[('d', 2, 'name', 'header_fragment')]"))

    rc, out = probe("import assemble as A; print(A.score_off('A&B Greek Yogurt', None, "
                    "{'product_name': 'Greek Yogurt', 'brands': ['Alpha & Beta']})[1])")
    results.append(("no config: an unlisted spelling is not the same brand", rc == 0 and out == "False"))

    rc, out = probe("import build_unique as B; print(bool(B.SUPPLEMENT.search('Examplecaps 60')), sorted(B.SUPPLEMENT_RETAILERS))", good)
    results.append(("config: private supplement words and shops", rc == 0 and out.startswith("True ['Example Chemist'")))

    rc, out = probe("import fetch_off_pass2 as P; print(P.BRAND_PREFIX.sub('', 'Example Grocer Oat Bar'), '|', "
                    "P.BRAND_PREFIX.sub('', 'Oat Bar'))", good)
    results.append(("config: shop prefixes are stripped, others untouched", rc == 0 and out == "Oat Bar | Oat Bar"))

    for name, doc in [("unknown key", {"schema": "pfc-private-config-v1", "extra": []}),
                      ("wrong schema", {"schema": "pfc-private-config-v0"}),
                      ("unknown parser", {"schema": "pfc-private-config-v1", "layouts": [
                          {"id": "a", "retailer": "b", "parser": "guess", "match": {"file_name_contains": "x"}}]}),
                      ("layout with no markers", {"schema": "pfc-private-config-v1", "layouts": [
                          {"id": "a", "retailer": "b", "parser": "order_page", "match": {}}]}),
                      ("product page without a suffix", {"schema": "pfc-private-config-v1", "layouts": [
                          {"id": "a", "retailer": "b", "parser": "product_page_title", "match": {"file_name_contains": "x"}}]}),
                      ("non-string list entry", {"schema": "pfc-private-config-v1", "brand_honorifics": [3]}),
                      ("a layout with an empty marker list", {"schema": "pfc-private-config-v1", "layouts": [
                          {"id": "a", "retailer": "b", "parser": "order_page", "match": {"text_contains_all": []}}]}),
                      ("a bare title as a brand exception", {"schema": "pfc-private-config-v1", "brand_honorifics": ["Mr"]}),
                      ("a full name as a brand exception", {"schema": "pfc-private-config-v1", "brand_honorifics": ["Mrs Sample Jones"]}),
                      ("a one-letter chrome prefix", {"schema": "pfc-private-config-v1", "site_chrome_prefixes": ["D"]}),
                      ("a chrome prefix of several words", {"schema": "pfc-private-config-v1", "site_chrome_prefixes": ["Delivery to"]})]:
        bad = tmp / "bad.json"
        bad.write_text(json.dumps(doc), encoding="utf-8")
        os.chmod(bad, 0o600)
        rc, out = probe("import private_config", bad)
        results.append((f"refused: {name}", rc != 0 and "refused" in out))

    r = subprocess.run([sys.executable, "-I", str(S / "extract_items.py"), str(tmp), str(tmp / "o")], capture_output=True,
                       text=True, env={k: v for k, v in os.environ.items() if k != "PFC_CONFIG"})
    results.append(("extractor refuses to run without PFC_CONFIG", r.returncode != 0 and "PFC_CONFIG" in r.stderr
                    and not (tmp / "o").exists()))
    r = subprocess.run([sys.executable, "-I", str(S / "build.py"), str(tmp), str(tmp)], capture_output=True,
                       text=True, env={k: v for k, v in os.environ.items() if k != "PFC_CONFIG"})
    results.append(("rebuild refuses to run without PFC_CONFIG", r.returncode != 0 and "PFC_CONFIG" in r.stderr))

    shared = tmp / "shared"
    shared.mkdir(mode=0o755)
    os.chmod(shared, 0o755)
    (shared / "config.json").write_text(EXAMPLE.read_text(encoding="utf-8"), encoding="utf-8")
    os.chmod(shared / "config.json", 0o600)
    rc, out = probe("import private_config", shared / "config.json")
    results.append(("refused: a config in a folder others can read", rc != 0 and "readable by other users" in out))
    os.chmod(good, 0o644)
    rc, out = probe("import private_config", good)
    results.append(("refused: a config file others can read", rc != 0 and "readable by other users" in out))
    os.chmod(good, 0o600)

    for script, args in [("assemble.py", [tmp, tmp, tmp, tmp]), ("build_unique.py", [tmp / "x.jsonl", tmp]),
                         ("fetch_off.py", [tmp]), ("fetch_off_pass2.py", [tmp, tmp]),
                         ("fetch_off_products.py", [tmp, tmp]), ("intake.py", [tmp, "status"]),
                         ("receipts_to_intake.py", [tmp, tmp / "x.jsonl", "receipts-x", tmp / "o.json"]),
                         ("assemble_extras.py", [tmp, tmp, tmp])]:
        r = subprocess.run([sys.executable, "-I", str(S / script), *map(str, args)], capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != "PFC_CONFIG"})
        results.append((f"{script} refuses to run without PFC_CONFIG", r.returncode != 0 and "PFC_CONFIG" in r.stderr))

    r = subprocess.run([sys.executable, "-I", "-c", "import importlib.util as u, sys; "
                        f"s = u.spec_from_file_location('http_client', {str(S / 'http_client.py')!r}); "
                        "m = u.module_from_spec(s); s.loader.exec_module(m); print('ok')"],
                       capture_output=True, text=True, env={k: v for k, v in os.environ.items() if k != "PFC_CONFIG"})
    results.append(("http_client imports with only its own folder to find", r.returncode == 0 and r.stdout.strip() == "ok"))

    rc, out = probe("import private_config", tmp / "missing.json")
    results.append(("refused: a named file that does not exist", rc != 0 and "not a file" in out))

    repo = tmp / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    (repo / "config.json").write_text(EXAMPLE.read_text(encoding="utf-8"), encoding="utf-8")
    rc, out = probe("import private_config", repo / "config.json")
    results.append(("refused: a config inside a git working tree", rc != 0 and "git working tree" in out))

ok = sum(1 for _, passed in results if passed)
print(f"private config: {ok} of {len(results)} cases correct")
for name, passed in results:
    if not passed:
        print("WRONG:", name)
sys.exit(0 if ok == len(results) else 1)
