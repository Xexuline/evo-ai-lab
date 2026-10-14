#!/usr/bin/env bash
# Explicit opt-in: uses a temporary rootless container and transient user unit.
# No GPU devices or model mounts; the image must already be present locally.
set -euo pipefail
[[ ${EVO_MODEL_INTEGRATION_IMAGE:-} ]] || { echo 'Set EVO_MODEL_INTEGRATION_IMAGE to a local image with /bin/sh and sleep.'; exit 77; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP=$(mktemp -d)
INSTANCE=evo-test-$(cat /proc/sys/kernel/random/uuid)
UNIT=$INSTANCE.service
TOKEN=$(cat /proc/sys/kernel/random/uuid)
export EVO_MODEL_STATE_DIR=$TEMP/state
mkdir -p "$EVO_MODEL_STATE_DIR/$INSTANCE"
cleanup() {
  systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
  "$ROOT/scripts/evo-model" cleanup-runtime "$INSTANCE"
  systemctl --user reset-failed "$UNIT" >/dev/null 2>&1 || true
  rm -rf -- "$TEMP"
}
trap cleanup EXIT
podman image exists "$EVO_MODEL_INTEGRATION_IMAGE"
for mode in stop kill; do
  printf '%s\n' "$TOKEN" > "$EVO_MODEL_STATE_DIR/$INSTANCE/gufo-owner"
  systemd-run --user --unit="$UNIT" \
    --property=Type=exec --property=KillMode=control-group --property=TimeoutStopSec=15 \
    --property="ExecStopPost=$ROOT/scripts/evo-model cleanup-runtime $INSTANCE" \
    --setenv="EVO_MODEL_STATE_DIR=$EVO_MODEL_STATE_DIR" \
    podman run --rm --pull=never --name "$INSTANCE" \
      --cidfile "$EVO_MODEL_STATE_DIR/$INSTANCE/gufo.cid" \
      --label "org.evo-model.owner=$TOKEN" --label "org.evo-model.instance=$INSTANCE" \
      --entrypoint /bin/sh "$EVO_MODEL_INTEGRATION_IMAGE" -c 'sleep 300 & wait'
  cid=
  for ((n=0;n<100;n++)); do
    if [[ -s $EVO_MODEL_STATE_DIR/$INSTANCE/gufo.cid ]]; then
      cid=$(cat "$EVO_MODEL_STATE_DIR/$INSTANCE/gufo.cid")
      [[ $(podman inspect --format '{{.State.Running}}' "$cid") == true ]] && break
    fi
    sleep .1
  done
  [[ $cid =~ ^[a-f0-9]{64}$ ]]
  [[ $(podman inspect --format '{{.State.Running}}' "$cid") == true ]]
  if [[ $mode == stop ]]; then
    systemctl --user stop "$UNIT"
  else
    systemctl --user kill --kill-whom=main --signal=SIGKILL "$UNIT"
  fi
  for ((n=0;n<400;n++)); do
    [[ -f $EVO_MODEL_STATE_DIR/$INSTANCE/gufo-owner ]] || break
    sleep .1
  done
  [[ ! -e $EVO_MODEL_STATE_DIR/$INSTANCE/gufo-owner ]]
  if podman container exists "$cid"; then echo "Orphan container: $cid" >&2; exit 1; else rc=$?; [[ $rc == 1 ]]; fi
  [[ -z $(podman ps --all --quiet --filter "label=org.evo-model.owner=$TOKEN") ]]
  "$ROOT/scripts/evo-model" cleanup-runtime "$INSTANCE"
  systemctl --user reset-failed "$UNIT" >/dev/null 2>&1 || true
  echo "PASS: $mode removes the container, repeated cleanup succeeds"
done
