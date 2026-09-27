#!/usr/bin/env bash
# Live lab: real fm-spawn (fake tmux only for the spawn's pane creation, as the repo's own live e2e does),
# then run the emitted launch command in a real private tmux pane that makes a real git commit.
set -u
ROOT=$PWD
. "$ROOT/tests/fixtures.sh" 2>/dev/null || { echo "fixtures load failed"; exit 1; }
fail() { echo "FAIL: $*"; exit 1; }
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); trap 'TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null; rm -rf "$LAB"' EXIT
mkdir -p "$LAB/tmux"
run_case() {  # <label> <keep 0|1>
  local label=$1 keep=$2; local H="$LAB/$label/home" PROJ="$LAB/$label/proj" WT="$LAB/$label/wt" ID="trailer-$label-z1" fakebin out
  "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null || fail "lab home"
  fm_test_spawn_home "$H" claude
  fm_git_worktree "$PROJ" "$WT" "fm/$ID"
  # a project-owned commit-msg hook via core.hooksPath (husky style) that tags the message
  mkdir -p "$LAB/$label/husky"; printf '#!/bin/sh\necho "Project-Hook: ran" >> "$1"\n' > "$LAB/$label/husky/commit-msg"; chmod +x "$LAB/$label/husky/commit-msg"
  git -C "$WT" config core.hooksPath "$LAB/$label/husky"
  git -C "$WT" config user.name 'Lab Captain'; git -C "$WT" config user.email lab@example.invalid
  [ "$keep" = 1 ] && : > "$H/config/keep-ai-trailers"
  fm_test_spawn_brief "$H" "$ID"
  fakebin=$(make_spawn_fakebin "$LAB/$label/fake" claude)
  out=$(FM_FAKE_LAUNCH_LOG="$LAB/$label/launch.sh" fm_test_run_spawn "$H" "$WT" "$fakebin" "$ID" "$PROJ" \
    "git commit -q --allow-empty --trailer 'Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>' --trailer 'Co-authored-by: Cursor <cursoragent@cursor.com>' -m 'feat: lab commit ($label)'" --mode local-only --yolo off) \
    || fail "spawn failed: $out"
  echo "== [$label] keep-ai-trailers=$keep  spawn: $(printf '%s' "$out" | grep -m1 spawned)"
  echo "-- emitted pane launch command:"; cat "$LAB/$label/launch.sh"; echo
  echo "-- state/$ID.git-hooks present? $([ -e "$H/state/$ID.git-hooks" ] && echo yes || echo no)"
  TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -s "$label" -x 120 -y 30 -c "$WT" \
    "env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 bash -c \"\$(cat '$LAB/$label/launch.sh')\"; echo PANE-EXIT=\$?; sleep 30"
  for _ in $(seq 1 40); do TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t "$label" | grep -q PANE-EXIT && break; sleep 0.25; done
  echo "-- pane: $(TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t "$label" | grep -v '^$')"
  echo "-- resulting commit message (git log -1 --format=%B):"; git -C "$WT" log -1 --format=%B; echo
}
run_case default 0
run_case keep 1
# adversarial: an uninspectable config dir must refuse rather than silently choose a policy
H="$LAB/deny/home"; "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null; fm_test_spawn_home "$H" claude
fm_git_worktree "$LAB/deny/proj" "$LAB/deny/wt" "fm/deny-z1"; fm_test_spawn_brief "$H" deny-z1
fb=$(make_spawn_fakebin "$LAB/deny/fake" claude); chmod 000 "$H/config"
out=$(FM_FAKE_LAUNCH_LOG="$LAB/deny/launch.sh" fm_test_run_spawn "$H" "$LAB/deny/wt" "$fb" deny-z1 "$LAB/deny/proj" "true" --mode local-only --yolo off); st=$?
chmod 755 "$H/config"
echo "== [unreadable-config] exit=$st launched=$([ -e "$LAB/deny/launch.sh" ] && echo yes || echo no)"; printf '%s\n' "$out" | tail -3
