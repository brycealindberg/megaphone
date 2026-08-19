#!/usr/bin/env bash
# Read back the prompt-prefix prewarm hit rate from the unified log.
#
# The prewarm is the one measured latency lever on the cleanup path (-182 ms
# when it lands), and it is gated on `screenVocabularySettled` — an
# accessibility read of the frontmost window with its own 1.2s budget. The open
# question is whether a short utterance ends before that read settles, so the
# hit rate is reported SPLIT BY how long the utterance ran. An average over long
# and short dictations together would hide exactly that case.
#
# Requires `latency_marks` to be on:
#   defaults write com.kuberwastaken.megaphone latency_marks -bool true
#
# Usage:
#   scripts/prewarm-hit-rate.sh          # last 24 hours
#   scripts/prewarm-hit-rate.sh 72       # last 72 hours

set -euo pipefail

HOURS="${1:-24}"
SUBSYSTEM="com.kuberwastaken.megaphone"

if ! START=$(date -v-"${HOURS}"H '+%Y-%m-%d %H:%M:%S' 2>/dev/null); then
  START=$(date -d "-${HOURS} hours" '+%Y-%m-%d %H:%M:%S')
fi

/usr/bin/log show --predicate "subsystem == \"${SUBSYSTEM}\"" \
                  --start "$START" --style compact 2>/dev/null \
  | grep 'prewarm ' \
  | python3 -c '
import sys, re, collections

# prewarm <outcome> spoke <n> ms screenVocabularySettled=<yes|no>
pat = re.compile(r"prewarm (hit \d+ chars|MISS|n/a \([^)]*\)) spoke (-?\d+) ms screenVocabularySettled=(yes|no)")
rows = []
for line in sys.stdin:
    m = pat.search(line)
    if m:
        rows.append((m.group(1), int(m.group(2)), m.group(3)))

if not rows:
    print("No prewarm lines found.")
    print("Check: latency_marks is on, the installed build has the instrumentation,")
    print("and the window covers real use.")
    sys.exit(0)

eligible = [r for r in rows if not r[0].startswith("n/a")]
skipped  = [r for r in rows if r[0].startswith("n/a")]

print(f"{len(rows)} recordings, {len(eligible)} eligible for prewarm, {len(skipped)} not attempted")
for reason, n in collections.Counter(r[0] for r in skipped).most_common():
    print(f"    {n:4d}  {reason}")

if not eligible:
    sys.exit(0)

hits = [r for r in eligible if r[0].startswith("hit")]
print(f"\nOVERALL HIT RATE: {len(hits)}/{len(eligible)} = {100*len(hits)/len(eligible):.0f}%")

buckets = [(0, 500), (500, 1000), (1000, 1500), (1500, 2500), (2500, 10**9)]
labels  = ["< 0.5 s", "0.5 - 1 s", "1 - 1.5 s", "1.5 - 2.5 s", "> 2.5 s"]
print("\nutterance        n   hit    rate   (the 1.2s screen-read budget sits in here)")
for (lo, hi), label in zip(buckets, labels):
    b = [r for r in eligible if lo <= r[1] < hi]
    if not b:
        continue
    h = sum(1 for r in b if r[0].startswith("hit"))
    print(f"{label:<12} {len(b):>5} {h:>5} {100*h/len(b):>6.0f}%")

# A miss with the read already settled is a different defect from a miss caused
# by waiting on it, so do not let the two average together.
unsettled = sum(1 for r in eligible if not r[0].startswith("hit") and r[2] == "no")
settled   = sum(1 for r in eligible if not r[0].startswith("hit") and r[2] == "yes")
print(f"\nmisses waiting on the screen read : {unsettled}")
print(f"misses with the read already settled: {settled}   (if non-zero, the gate is not the whole story)")
'
