#!/usr/bin/env bash
# Live driver: real fm-spawn.sh, real tmux (private lab socket), real treehouse,
# real git commit in the spawned pane. Usage: live-spawn.sh <keep|default> <harness>
set -u
MODE=$1 HARNESS=$2
WT_SRC=$(pwd -P)
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/user-home" "$LAB/treehouse"
touch "$LAB/state/.last-watcher-beat"
[ "$MODE" = keep ] && : > "$LAB/config/keep-ai-trailers"
[ "$MODE" = dir ] && mkdir "$LAB/config/keep-ai-trailers"
[ "$MODE" = dangling ] && ln -s "$LAB/nowhere" "$LAB/config/keep-ai-trailers"
PROJ="$LAB/proj"; git init -q -b main "$PROJ"
git -C "$PROJ" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
git init -q --bare -b main "$PROJ.origin.git"; git -C "$PROJ" remote add origin "$PROJ.origin.git"; git -C "$PROJ" push -q origin main; git -C "$PROJ" fetch -q origin; git -C "$PROJ" remote set-head origin main
ID="lab-trailers-$MODE"
mkdir -p "$LAB/data/$ID"
cat > "$LAB/data/$ID/brief.md" <<B
# Task
## Captain's intent
live keep-ai-trailers check

## Firstmate spec
Exercise the spawn behavior under test.
B
export HOME="$LAB/user-home" TREEHOUSE_ROOT="$LAB/treehouse" CLAUDE_CONFIG_DIR=
T="env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR=$LAB/tmux"
TM() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab "$@"; }
echo "== LAB=$LAB mode=$MODE harness=$HARNESS"
echo "== config/: $(ls -A "$LAB/config")"
TM new-session -d -s primary -x 200 -y 50 -c "$WT_SRC" -e FM_HOME="$LAB" -e HOME="$HOME" -e TREEHOUSE_ROOT="$TREEHOUSE_ROOT" bash --norc
sleep 1
TM send-keys -t primary "$T FM_SPAWN_NO_GUARD=1 CLAUDE_CONFIG_DIR= bin/fm-spawn.sh $ID $PROJ --mode local-only --yolo off --harness '$HARNESS' > $LAB/spawn.out 2>&1; echo SPAWN_EXIT=\$? >> $LAB/spawn.out" Enter
for i in $(seq 1 120); do grep -q SPAWN_EXIT "$LAB/spawn.out" 2>/dev/null && break; sleep 1; done
echo "== spawn output"; cat "$LAB/spawn.out"
echo "== state hooks dir present?"; ls -d "$LAB/state/$ID.git-hooks" 2>&1
WIN=$(grep '^window=' "$LAB/state/$ID.meta" | cut -d= -f2-)
WTP=$(grep '^worktree=' "$LAB/state/$ID.meta" | cut -d= -f2-)
echo "== window=$WIN worktree=$WTP"
if [ -z "$WIN" ]; then TM kill-server; chmod -R u+w "$LAB"; rm -rf "$LAB"; echo ABORT; exit 1; fi
PANEPID=$(TM display -p -t "$WIN" '#{pane_pid}')
echo "== pane process tree argv"
desc() { local c; for c in $(pgrep -P "$1"); do echo "$c"; desc "$c"; done; }
sleep 3
for p in $PANEPID $(desc "$PANEPID"); do tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null; echo; done
echo "== pane env GIT_CONFIG_*"
for p in $(desc "$PANEPID"); do tr '\0' '\n' < /proc/$p/environ | grep '^GIT_CONFIG' ; done | sort -u
if [ "$HARNESS" = "bash -i" ]; then
  sleep 2
  TM send-keys -t "$WIN" "cd $WTP && printf 'x\n' > f && git add f && git -c user.name=t -c user.email=t@e commit -q -m 'feat: live commit' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>' && echo COMMITTED" Enter
  for i in $(seq 1 30); do TM capture-pane -p -t "$WIN" | grep -q '^COMMITTED' && break; sleep 1; done
  echo "== commit object message from pane commit"
  git -C "$WTP" log -1 --format='%B'
  echo "== pane capture"; TM capture-pane -p -t "$WIN" | grep -v '^$' | tail -8
fi
if [ "$HARNESS" = claude ]; then sleep 5; echo "== claude pane capture"; TM capture-pane -p -t "$WIN" | grep -v '^$' | head -15; fi
TM kill-server
git -C "$PROJ" worktree prune 2>/dev/null
chmod -R u+w "$LAB" 2>/dev/null; rm -rf "$LAB"
echo "== lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
