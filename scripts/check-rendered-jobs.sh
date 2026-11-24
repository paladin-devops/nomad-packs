#!/bin/bash
# Fail if a rendered job contains a ${...} the Nomad task driver would reject,
# then run each rendered job on a local dev agent until install-cli starts.
# nomad job validate does not interpolate driver config. The driver does, at
# task start, and that is what rejected ${os_name} / ${arch_name}.
set -euo pipefail

RENDER_DIR=${1:?render dir}
NOMAD=${NOMAD:-nomad}
ADDR=http://127.0.0.1:4646
export NOMAD_ADDR="$ADDR"

scan_file() {
  python3 - "$1" << 'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
allowed = re.compile(
    r"^\$\{(NOMAD_[A-Za-z0-9_]+|attr(?:\.[A-Za-z0-9_]+)+|node(?:\.[A-Za-z0-9_]+)+|meta\.[A-Za-z0-9_]+|env\.[A-Za-z0-9_]+)\}$"
)
bad = []
for i, line in enumerate(text.splitlines(), 1):
    for match in re.finditer(r"\$\{[^{}]+\}", line):
        token = match.group(0)
        if not allowed.match(token):
            bad.append(f"{path}:{i}: {token}")
if bad:
    print("rendered job has ${...} the task driver will reject:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    print("Use $name for shell locals. $${name} still contains ${name}.", file=sys.stderr)
    sys.exit(1)
PY
}

self_check() {
  local tmp
  tmp=$(mktemp)
  printf '%s\n' 'url="${os_name}/${arch_name}"' 'also="$${CLI_VERSION}"' > "$tmp"
  if scan_file "$tmp" >/tmp/scan-self.err 2>&1; then
    echo "interpolation scanner did not reject a braced shell variable" >&2
    rm -f "$tmp"
    exit 1
  fi
  printf '%s\n' 'home = "${NOMAD_ALLOC_DIR}/home"' 'attr = "${attr.kernel.name}"' > "$tmp"
  scan_file "$tmp"
  rm -f "$tmp"
}

self_check

mapfile -t jobs < <(find "$RENDER_DIR" -name '*.nomad' | sort)
if [ "${#jobs[@]}" -eq 0 ]; then
  echo "no rendered jobs under $RENDER_DIR" >&2
  exit 1
fi

for job in "${jobs[@]}"; do
  echo "==> scan $job"
  scan_file "$job"
done

agent_dir=$(mktemp -d)
agent_pid=""
cleanup() {
  set +e
  if [ -n "${agent_pid}" ] && kill -0 "$agent_pid" 2>/dev/null; then
    kill "$agent_pid" 2>/dev/null
    wait "$agent_pid" 2>/dev/null
  fi
  # The prestart task may still be writing the CLI tree as the agent exits.
  sleep 0.5
  for _ in 1 2 3 4 5 6 7 8; do
    rm -rf "$agent_dir" 2>/dev/null && return 0
    sleep 0.4
  done
  rm -rf "$agent_dir" 2>/dev/null
  return 0
}
trap cleanup EXIT

echo "==> nomad agent -dev"
"$NOMAD" agent -dev -bind=127.0.0.1 -data-dir="$agent_dir/data" >"$agent_dir/agent.log" 2>&1 &
agent_pid=$!
ready=0
for _ in $(seq 1 40); do
  if "$NOMAD" node status >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$agent_pid" 2>/dev/null; then
    echo "dev agent exited" >&2
    cat "$agent_dir/agent.log" >&2
    exit 1
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  echo "dev agent did not become ready" >&2
  cat "$agent_dir/agent.log" >&2
  exit 1
fi

for job in "${jobs[@]}"; do
  work=$(mktemp)
  # exec does not start without root, so the driver never parses config.
  # raw_exec parses the same args. The scanned file above is the real render.
  sed 's/driver *= *"exec"/driver = "raw_exec"/g' "$job" > "$work"
  echo "==> nomad job validate (dev agent) $job"
  "$NOMAD" job validate "$work"
  echo "==> nomad job run (dev agent) $job"
  "$NOMAD" job run -detach "$work" >/dev/null
  alloc=""
  result=""
  for _ in $(seq 1 40); do
    alloc=$("$NOMAD" job allocs -t '{{range .}}{{.ID}}{{end}}' cursor_worker 2>/dev/null || true)
    if [ -z "$alloc" ]; then
      sleep 0.25
      continue
    fi
    result=$(NOMAD_ADDR="$ADDR" python3 - "$NOMAD" "$alloc" << 'PY'
import json, subprocess, sys
nomad, alloc = sys.argv[1], sys.argv[2]
raw = subprocess.check_output([nomad, "alloc", "status", "-json", alloc], text=True)
data = json.loads(raw)
states = data.get("TaskStates") or {}
state = states.get("install-cli") or {}
events = state.get("Events") or []
# Nomad returns newest first.
for event in events:
    if not isinstance(event, dict):
        continue
    message = event.get("DisplayMessage") or ""
    kind = event.get("Type") or ""
    if "Unknown variable" in message or "failed to parse config" in message:
        print("FAIL")
        print(message)
        sys.exit(0)
    if kind == "Started":
        print("STARTED")
        sys.exit(0)
print("WAIT")
print(state.get("State") or "")
PY
)
    head=$(printf '%s\n' "$result" | head -n 1)
    if [ "$head" = "FAIL" ]; then
      echo "driver rejected config in $job" >&2
      printf '%s\n' "$result" >&2
      "$NOMAD" job stop -purge -yes cursor_worker >/dev/null || true
      exit 1
    fi
    if [ "$head" = "STARTED" ]; then
      echo "install-cli started (config parsed): $job"
      "$NOMAD" job stop -purge -yes cursor_worker >/dev/null || true
      # Wait until the job is gone so the next submit is a new registration.
      for _ in $(seq 1 40); do
        if ! "$NOMAD" job status cursor_worker >/dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done
      break
    fi
    sleep 0.25
  done
  if [ "${head:-}" != "STARTED" ]; then
    echo "install-cli did not start for $job (alloc=${alloc:-none})" >&2
    if [ -n "$alloc" ]; then
      "$NOMAD" alloc status "$alloc" >&2 || true
    fi
    "$NOMAD" job stop -purge -yes cursor_worker >/dev/null || true
    exit 1
  fi
  rm -f "$work"
done

echo "driver interpolation check passed (${#jobs[@]} jobs)"
