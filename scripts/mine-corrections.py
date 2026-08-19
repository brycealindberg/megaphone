#!/usr/bin/env python3
"""Propose `word_corrections` rules from the app's own transcript corpus.

The promotion path from a learned mishearing to a deterministic rule already
ships (`misheardCount`, the Settings suggestion card). It is not missing, it is
*starved*: it only ever sees a mishearing the 25-second read-back happened to
catch, which on this Mac is two in sixteen days. `TranscriptLog` was built to be
the corpus that answers the gates, so this reads it directly.

The method is the one that produced the existing hand-mined rules — three
filters in series, each killing a class the previous one let through:

  1. PHONETIC  a real mishear sounds like its correction; consonant skeletons
               differ by at most one. Without this the top hits are grammar
               edits, and a rule like `there's -> there are` wrecks real text.
  2. TERM      the written side must be a proper noun or carry an internal
               capital. This is what removes the remaining `is -> are` class.
  3. CORPUS    for every surviving candidate, count how often the corpus
               CONTRADICTS it. Require >= 2 fires and zero contradictions.
               Frequency ranks candidates; validation decides them.

And the check that matters most, which no corpus can perform: a corpus only
shows a rule was never wrong *before*. Any heard-side that is ordinary English
is refused as a bare rule and must be anchored on BOTH sides, because
`for cloud -> for Claude` validated 8/8 and still corrupts "a plan for cloud
migration".

Nothing is written. The output is a review list; you decide.

Usage:
    scripts/mine-corrections.py
    scripts/mine-corrections.py --min-fires 3
"""

import argparse
import collections
import difflib
import json
import os
import plistlib
import re
import subprocess
import sys

CORPUS = os.path.expanduser(
    "~/Library/Application Support/Megaphone/transcripts.jsonl"
)
DOMAIN = "com.kuberwastaken.megaphone"
WORDS = "/usr/share/dict/words"

# Same phonetic model as SpokenNameRepair.skeleton, deliberately: a candidate
# this rejects is one the app's own repair pass would also never make.
_MERGE = {
    "a": None, "e": None, "i": None, "o": None, "u": None,
    "y": None, "h": None, "w": None,
    "c": "k", "k": "k", "q": "k", "g": "k", "x": "k",
    "s": "s", "z": "s", "f": "f", "v": "f",
    "d": "t", "t": "t", "b": "p", "p": "p", "m": "n", "n": "n",
}


def normalize(value):
    out = []
    for ch in value.lower():
        if ch.isalnum() and (not out or out[-1] != ch):
            out.append(ch)
    return "".join(out)


def skeleton(normalized):
    out = []
    for ch in normalized:
        mapped = _MERGE.get(ch, ch)
        if mapped and (not out or out[-1] != mapped):
            out.append(mapped)
    return "".join(out)


def edit_distance(a, b):
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                         prev[j - 1] + (ca != cb))
        prev = cur
    return prev[len(b)]


def read_pref(key):
    try:
        raw = subprocess.run(
            ["defaults", "export", DOMAIN, "-"],
            capture_output=True, check=True,
        ).stdout
        return plistlib.loads(raw).get(key)
    except Exception:
        return None


def load_corpus():
    if not os.path.exists(CORPUS):
        sys.exit(f"No corpus at {CORPUS}. TranscriptLog writes it on delivery.")
    rows = []
    with open(CORPUS) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def load_vocabulary():
    """The written side comes from the app's own dictionary.

    Using it as the source of truth satisfies the term gate by construction —
    these are already the proper nouns the user cares about — and means a
    proposal can never invent a spelling the user has not already endorsed.
    """
    blob = read_pref("dictionary_entries_v1")
    if not blob:
        return []
    try:
        entries = json.loads(bytes(blob))
    except Exception:
        return []
    return [e["term"] for e in entries
            if e.get("term") and e.get("status") != "rejected"]


def load_existing_rules():
    text = read_pref("word_corrections") or ""
    rules = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "->" not in line:
            continue
        rules.add(line.split("->", 1)[0].strip().lower())
    return rules


def load_english():
    if not os.path.exists(WORDS):
        return set()
    with open(WORDS, encoding="utf-8", errors="ignore") as handle:
        return {w.strip().lower() for w in handle if w.strip()}


# `/usr/share/dict/words` is web2: base forms, so "message" is present and
# "messages" is not. Looking a token up raw let `messages -> iMessage` and
# `things -> Thanks` past the gate that exists precisely to stop them.
_SUFFIXES = ("'s", "’s", "s", "es", "ed", "ing", "ly", "er", "est", "'ll", "'re", "'ve")


def is_english(word, english):
    w = word.lower().strip("'’.")
    if w in english:
        return True
    for suffix in _SUFFIXES:
        if w.endswith(suffix) and len(w) > len(suffix) + 2:
            stem = w[: -len(suffix)]
            if stem in english:
                return True
            # "using" -> "use", "carries" -> "carry"
            if stem + "e" in english or (stem[:-1] + "y") in english:
                return True
    return False


def is_term_like(word):
    """Gate 2: a proper noun, or something carrying an internal capital."""
    if not word or not word[0].isalpha():
        return False
    if word[0].isupper():
        return True
    return any(c.isupper() for c in word[1:])


TOKEN = re.compile(r"[A-Za-z][A-Za-z'’.]*")


def tokenize(text):
    return [t.strip("'’.") for t in TOKEN.findall(text)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-fires", type=int, default=2,
                    help="corpus occurrences required (default 2)")
    ap.add_argument("--max-show", type=int, default=25)
    ap.add_argument("--self-test", action="store_true",
                    help="inject a known mishear and confirm it is surfaced")
    args = ap.parse_args()

    rows = load_corpus()
    if args.self_test:
        # An empty result and a silently broken miner look identical from the
        # outside, and "0 candidates" is the answer this tool most often gives.
        # So plant a mishearing that must survive all three gates, plus one
        # that must be killed by each gate in turn, and check both directions.
        rows = rows + [
            {"app": "test", "t": "", "raw": "push the Ledgerique update tonight", "out": "push the Ledgerique update tonight"},
            {"app": "test", "t": "", "raw": "push the LedgerIQ update tonight", "out": "push the LedgerIQ update tonight"},
            {"app": "test", "t": "", "raw": "ask Ledgerique about the invoice", "out": "ask Ledgerique about the invoice"},
            {"app": "test", "t": "", "raw": "ask LedgerIQ about the invoice", "out": "ask LedgerIQ about the invoice"},
        ]
    vocab = load_vocabulary()
    existing = load_existing_rules()
    english = load_english()

    print(f"corpus {len(rows)} dictations · vocabulary {len(vocab)} terms · "
          f"{len(existing)} rules already configured\n")

    # Counted over `out`, the delivered text — the same side the candidates are
    # derived from. Counting `raw` instead makes `counterexamples` go NEGATIVE
    # whenever cleanup rewrote the token, and a negative count matched none of
    # the report's buckets, so the candidate vanished with no line anywhere.
    # The self-test exists because that failure is invisible: an empty result
    # and a broken miner print the same thing.
    occurrences = collections.defaultdict(list)
    for row in rows:
        for tok in tokenize(row.get("out", "")):
            occurrences[tok.lower()].append(row)

    # --- candidate generation -------------------------------------------
    #
    # Candidates come from RE-DICTATIONS, not from phonetic proximity to the
    # vocabulary. That distinction is the whole design. Matching every corpus
    # token against every dictionary term by sound alone proposes
    # `messages -> iMessage` at 85 fires and `looks -> Aleks` at 19, because in
    # English an ordinary word sounding like a proper noun is unremarkable and
    # is not evidence that anything was ever misheard.
    #
    # A re-dictation is evidence: the user said something, did not accept it,
    # and said it again within two minutes. The second utterance is what they
    # meant. That is the closest thing to the hand-edited ground truth the
    # original mining pass had, and it is the only such signal in this corpus.
    pairs = []
    for first, second in zip(rows, rows[1:]):
        if first.get("app") != second.get("app"):
            continue
        a, b = first.get("out", ""), second.get("out", "")
        if not a or not b or a == b or min(len(a), len(b)) < 12:
            continue
        if difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio() < 0.62:
            continue
        pairs.append((a, b))

    corrections = collections.Counter()
    evidence = collections.defaultdict(list)
    for a, b in pairs:
        wa, wb = tokenize(a), tokenize(b)
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
            None, [w.lower() for w in wa], [w.lower() for w in wb]
        ).get_opcodes():
            if tag != "replace" or (i2 - i1) != 1 or (j2 - j1) != 1:
                continue
            heard, written = wa[i1], wb[j1]
            corrections[(heard.lower(), written)] += 1
            evidence[(heard.lower(), written)].append((a, b))

    candidates = {}
    rejected = collections.Counter()

    for (heard, written), n_corrections in corrections.items():
        if heard in existing:
            rejected["already a rule"] += 1
            continue
        if heard == written.lower():
            continue
        n_heard, n_written = normalize(heard), normalize(written)
        if len(n_heard) < 3 or len(n_written) < 3:
            rejected["too short to fingerprint"] += 1
            continue
        skel_h, skel_w = skeleton(n_heard), skeleton(n_written)
        if len(skel_h) < 3 or len(skel_w) < 3:
            rejected["skeleton too short (acronym-shaped)"] += 1
            continue
        if edit_distance(skel_h, skel_w) > 1:
            rejected["not a mishear (sounds different — a rewrite)"] += 1
            continue                                   # GATE 1: phonetic
        if not is_term_like(written):
            rejected["written side is not a proper noun"] += 1
            continue                                   # GATE 2: term

        # GATE 3, the one that earns its keep. Every OTHER time the heard form
        # appears in the corpus and was NOT re-dictated, the user accepted it —
        # that is a counterexample, and the rule would have corrupted it.
        total_uses = len(occurrences.get(heard, []))
        counterexamples = max(0, total_uses - n_corrections)
        candidates[(heard, written)] = {
            "heard": heard,
            "written": written,
            "corrections": n_corrections,
            "counterexamples": counterexamples,
            "total_uses": total_uses,
            "anchored_only": is_english(heard, english),
            "evidence": evidence[(heard, written)][:3],
        }

    print(f"{len(pairs)} re-dictations found "
          f"({100 * len(pairs) / max(len(rows), 1):.1f}% of the corpus)\n")

    passing = [c for c in candidates.values()
               if c["corrections"] >= args.min_fires
               and c["counterexamples"] == 0
               and not c["anchored_only"]]
    contradicted = [c for c in candidates.values() if c["counterexamples"] > 0]
    thin = [c for c in candidates.values()
            if c["counterexamples"] == 0
            and c["corrections"] < args.min_fires
            and not c["anchored_only"]]
    unsafe = [c for c in candidates.values()
              if c["anchored_only"] and c["counterexamples"] == 0]

    ranked = sorted(passing, key=lambda c: -c["corrections"])
    print(f"=== {len(ranked)} candidate(s) passing all three gates ===")
    if not ranked:
        print("None. That is a normal and honest result: no mishearing in this")
        print("corpus was both repeated and never accepted somewhere else.\n")
    for c in ranked[:args.max_show]:
        print(f"  {c['heard']!r} -> {c['written']!r}   "
              f"corrected {c['corrections']}x, "
              f"{c['counterexamples']} counterexamples in "
              f"{c['total_uses']} uses")
        for a, b in c["evidence"]:
            print(f"        said : {a[:100]}")
            print(f"        again: {b[:100]}")
        print()

    if thin:
        print(f"=== {len(thin)} clean, but seen only once (need >= {args.min_fires}) ===")
        print("Not rejected, just not yet evidence. Re-run as the corpus grows.\n")
        for c in sorted(thin, key=lambda c: c["heard"])[:args.max_show]:
            print(f"  {c['heard']!r} -> {c['written']!r}   "
                  f"({c['total_uses']} use(s) in corpus)")
        print()

    if unsafe:
        print(f"=== {len(unsafe)} refused: heard side is ordinary English ===")
        print("A bare rule here corrupts sentences not yet spoken. Anchor BOTH")
        print('sides ("cloud code -> Claude Code", never "cloud -> Claude").\n')
        for c in sorted(unsafe, key=lambda c: -c["corrections"])[:args.max_show]:
            print(f"  {c['heard']!r} -> {c['written']!r}   corrected {c['corrections']}x")
        print()

    if contradicted:
        print(f"=== {len(contradicted)} rejected by the corpus ===")
        print("The heard form was kept elsewhere, so the rule would have")
        print("corrupted real text. This is the gate that earns its keep.\n")
        for c in sorted(contradicted, key=lambda c: -c["counterexamples"])[:args.max_show]:
            print(f"  {c['heard']!r} -> {c['written']!r}   "
                  f"corrected {c['corrections']}x but kept {c['counterexamples']}x")
        print()

    print("=== gate rejections ===")
    for reason, n in rejected.most_common():
        print(f"  {n:5d}  {reason}")
    if args.self_test:
        found = any(c["heard"] == "ledgerique" for c in ranked)
        print(f"\nSELF-TEST: planted 'Ledgerique' -> 'LedgerIQ' "
              f"{'SURFACED — the miner works' if found else 'LOST — the miner is broken'}")
        if not found:
            sys.exit(1)

    print("\nNothing was written. A corpus can only show a rule was never wrong")
    print("BEFORE. Run any accepted rule on a plausible sentence it has never")
    print("seen, then the real-voice regression set, before trusting it.")


if __name__ == "__main__":
    main()
