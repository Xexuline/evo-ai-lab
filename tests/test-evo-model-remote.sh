#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

FAKE_EVO_MODEL="$TEMP_DIR/evo-model"
WRAPPER="$TEMP_DIR/evo-model-remote"
ARGS_LOG="$TEMP_DIR/args.log"
MARKER="$TEMP_DIR/shell-interpreted"

cat > "$FAKE_EVO_MODEL" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$EVO_MODEL_REMOTE_TEST_ARGS"
EOF
chmod +x "$FAKE_EVO_MODEL"

# The production wrapper intentionally has a fixed absolute target. Replace it
# only in this disposable test copy so calls can be observed without services.
sed "s|^readonly EVO_MODEL_BIN=.*$|readonly EVO_MODEL_BIN=$FAKE_EVO_MODEL|" \
  "$ROOT_DIR/scripts/evo-model-remote" > "$WRAPPER"
chmod +x "$WRAPPER"

run_allowed() {
  local command=$1 expected=$2
  SSH_ORIGINAL_COMMAND="$command" EVO_MODEL_REMOTE_TEST_ARGS="$ARGS_LOG" "$WRAPPER"
  diff -u <(printf '%s\n' "$expected") "$ARGS_LOG"
}

expect_rejected() {
  local command=$1
  if SSH_ORIGINAL_COMMAND="$command" EVO_MODEL_REMOTE_TEST_ARGS="$ARGS_LOG" "$WRAPPER" >/dev/null 2>&1; then
    echo "expected command to be rejected: $command" >&2
    exit 1
  fi
  [[ ! -e $ARGS_LOG ]] || { echo "rejected command reached evo-model: $command" >&2; exit 1; }
}

run_allowed 'evo-model status' 'status'
run_allowed 'evo-model list' 'list'
run_allowed 'evo-model start worker worker-default' $'start\nworker\nworker-default'
run_allowed 'evo-model start agent worker-fast' $'start\nagent\nworker-fast'
run_allowed 'evo-model stop worker' $'stop\nworker'
run_allowed 'evo-model stop agent' $'stop\nagent'
run_allowed 'evo-model restart worker' $'restart\nworker'
run_allowed 'evo-model restart agent' $'restart\nagent'

rm -f -- "$ARGS_LOG"
expect_rejected ''
expect_rejected 'bash'
expect_rejected 'sh'
expect_rejected 'sudo evo-model status'
expect_rejected 'rm -rf /'
expect_rejected 'evo-model logs worker'
expect_rejected 'evo-model run-selected worker'
expect_rejected 'evo-model stop database'
expect_rejected 'evo-model start worker bad;profile'
expect_rejected 'evo-model start worker ../worker-default'
expect_rejected 'evo-model status worker'
expect_rejected 'evo-model stop worker extra'

# These are passed as inert text to the parser; none can cause shell execution.
expect_rejected "evo-model status; touch $MARKER"
expect_rejected "evo-model status && touch $MARKER"
expect_rejected "evo-model status | touch $MARKER"
expect_rejected 'evo-model start worker $(touch '"$MARKER"')'
expect_rejected 'evo-model start worker `touch '"$MARKER"'`'
expect_rejected "evo-model status >$MARKER"
[[ ! -e $MARKER ]] || { echo 'SSH command was interpreted by a shell' >&2; exit 1; }

echo 'evo-model remote wrapper tests passed'
