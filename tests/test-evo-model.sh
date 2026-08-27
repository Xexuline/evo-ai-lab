#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

PROFILE_DIR="$TEMP_DIR/profiles"
STATE_DIR="$TEMP_DIR/state"
FAKE_BIN="$TEMP_DIR/bin"
mkdir -p "$PROFILE_DIR"
MODEL_FILE="$TEMP_DIR/model.gguf"
touch "$MODEL_FILE"

write_profile() {
  local name=$1
  sed "s|@MODEL@|$MODEL_FILE|" > "$PROFILE_DIR/$name.conf"
}

write_profile good <<'EOF'
PROFILE_NAME=good
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=65536
GPU_LAYERS=999
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=2
SPEC_DRAFT_P_MIN=0.8
HOST=127.0.0.1
PORT=8080
EOF

run_manager() { EVO_MODEL_PROFILE_DIR="$PROFILE_DIR" EVO_MODEL_STATE_DIR="$STATE_DIR" "$ROOT_DIR/scripts/evo-model" "$@"; }

run_manager --validate-profile good >/dev/null

write_profile bad-key <<'EOF'
PROFILE_NAME=bad-key
MODEL_PATH=@MODEL@
UNSAFE=$(printf should-not-run)
EOF
if run_manager --validate-profile bad-key >/dev/null 2>&1; then
  echo "expected unknown profile key to fail" >&2
  exit 1
fi

write_profile missing-model <<'EOF'
PROFILE_NAME=missing-model
MODEL_PATH=/does/not/exist.gguf
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if run_manager --validate-profile missing-model >/dev/null 2>&1; then
  echo "expected missing model to fail" >&2
  exit 1
fi

mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/distrobox" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "list" ]]; then
  cat <<'TABLE'
ID | NAME | STATUS | IMAGE
abc123 | llama-vulkan-radv | Up | example/radv
def456 | llama-vulkan | Up | example/vulkan
TABLE
fi
EOF
chmod +x "$FAKE_BIN/distrobox"

cat > "$FAKE_BIN/ss" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${EVO_MODEL_TEST_SS_ARGS:-}" ]]; then
  printf '%s\n' "$*" > "$EVO_MODEL_TEST_SS_ARGS"
fi
case "${EVO_MODEL_TEST_SS_MODE:-free}" in
  free) ;;
  occupied) printf 'LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:*\n' ;;
  similar) printf 'LISTEN 0 4096 0.0.0.0:18080 0.0.0.0:*\n' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$FAKE_BIN/ss"

PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime good >/dev/null
EVO_MODEL_TEST_SS_MODE=free PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
EVO_MODEL_TEST_SS_MODE=similar PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
if EVO_MODEL_TEST_SS_MODE=occupied PATH="$FAKE_BIN:$PATH" run_manager --check-port good >"$TEMP_DIR/port-error" 2>&1; then
  echo "expected an occupied port to fail" >&2
  exit 1
fi
grep -q 'port 8080 is already in use' "$TEMP_DIR/port-error"
EVO_MODEL_TEST_SS_MODE=free EVO_MODEL_TEST_SS_ARGS="$TEMP_DIR/ss-args" PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
grep -Fq 'sport = :8080' "$TEMP_DIR/ss-args"

write_profile partial-container <<'EOF'
PROFILE_NAME=partial-container
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-ra
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime partial-container >/dev/null 2>&1; then
  echo "expected a partial container name to fail" >&2
  exit 1
fi

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" show "* ]]; then
  printf '123\n'
  exit 0
fi
if [[ " $* " == *" is-active "* ]]; then
  printf 'active\n'
fi
exit 0
EOF
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/curl"
mkdir -p "$STATE_DIR"
printf 'good\n' > "$STATE_DIR/selected-profile"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: ready"* ]]
[[ "$status_output" == *"Listen: 127.0.0.1:8080"* ]]
[[ "$status_output" == *"Health endpoint: http://127.0.0.1:8080/v1/models"* ]]

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"another-model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/curl"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: not ready"* ]]

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"model.gguf"}]}'
EOF
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
counter_file="${EVO_MODEL_TEST_COUNTER:?}"
if [[ "$*" == *"is-active"* ]]; then
  count=0
  [[ -f "$counter_file" ]] && count=$(<"$counter_file")
  count=$((count + 1))
  printf '%s\n' "$count" > "$counter_file"
  # start: inactive; wait loop: active; health before curl: active;
  # health after curl: inactive.
  [[ "$count" -lt 4 ]]
  exit
fi
exit 0
EOF
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/curl"
if EVO_MODEL_TEST_COUNTER="$TEMP_DIR/systemctl-count" PATH="$FAKE_BIN:$PATH" EVO_MODEL_HEALTH_TIMEOUT=5 run_manager start good >"$TEMP_DIR/health-output" 2>&1; then
  echo "expected health check to fail after the service becomes inactive" >&2
  exit 1
fi
if grep -q 'API ready' "$TEMP_DIR/health-output"; then
  echo "health check accepted an API after service shutdown" >&2
  exit 1
fi

echo "evo-model profile validation tests passed"
