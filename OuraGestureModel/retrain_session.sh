#!/usr/bin/env bash
# Full retrain pipeline for a freshly completed labeling session:
#   ./retrain_session.sh <capture-dir>
# analyze → archive trace → build events → merged CV train → export →
# parity → end-to-end evaluate. Exits non-zero on any failed stage or if
# the new model regresses below 90% on any session.
set -euo pipefail
CAP="$1"
cd "$(dirname "$0")"
CAL="../Tools/oura-calibration"

python3 - "$CAP" <<'EOF'
import json, sys
from pathlib import Path
cap = Path(sys.argv[1])
events = [json.loads(l) for l in (cap / "targets.ndjson").read_text().splitlines() if l.strip()]
ts = [float(e["wallTimeUnix"]) for e in events if e.get("type") in ("session:start", "session:end")]
lo, hi = min(ts) - 30, max(ts) + 30
n = 0
with (cap / "motion-trace.ndjson").open("w") as out:
	for line in open("/tmp/controllerkeys-oura-motion-trace.ndjson"):
		try: t = json.loads(line).get("t")
		except Exception: continue
		if t and lo <= t <= hi:
			out.write(line); n += 1
print(f"archived {n} trace lines")
EOF

python3 "$CAL/analyze_gestures.py" "$CAP" --trace "$CAP/motion-trace.ndjson"
python3 build_dataset.py "$CAP"
EVENTS=$(ls "$CAL"/captures/*/events.ndjson)
python3 train.py $EVENTS
python3 export.py
python3 verify_coreml.py "$CAP/events.ndjson"
python3 evaluate.py
echo "RETRAIN PIPELINE COMPLETE — copy exported/OuraGestureClassifier.mlpackage to Resources and reinstall"
