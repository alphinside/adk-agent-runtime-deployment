#!/usr/bin/env bash
# Runs MCP Toolbox in Cloud Shell, in the background, so one terminal is enough
# for the lab. The agent uses it until it is deployed.
#
#   scripts/toolbox.sh start | restart | stop | status
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=1.12.0
BIN=bin/toolbox
PID_FILE=.toolbox.pid
LOG=toolbox.log
PORT=5000

set -a; source .env; set +a

running() { [[ -f $PID_FILE ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

status() {
  if running; then
    echo "MCP Toolbox is running on 127.0.0.1:$PORT (PID $(cat "$PID_FILE")). Log: $LOG"
    echo "BigQuery calls run as: $(gcloud config get-value account 2>/dev/null) (your own account)"
  else
    echo "MCP Toolbox is not running. Start it with: scripts/toolbox.sh start"
  fi
}

start() {
  if running; then status; return; fi
  if [[ ! -x $BIN ]]; then
    echo "Downloading MCP Toolbox $VERSION..."
    mkdir -p bin
    curl -sSfL -o "$BIN" \
      "https://storage.googleapis.com/mcp-toolbox-for-databases/v$VERSION/linux/amd64/toolbox"
    chmod +x "$BIN"
  fi
  # setsid puts Toolbox in its own session, so it keeps running when the shell
  # that started it exits. Coding agents often kill everything a command started.
  setsid nohup "$BIN" --config mcp-toolbox/tools.yaml --address 127.0.0.1 --port "$PORT" \
    >"$LOG" 2>&1 </dev/null &
  echo $! >"$PID_FILE"
  for _ in $(seq 30); do
    if ! running; then
      echo "MCP Toolbox exited during start-up. Last lines of $LOG:" >&2
      tail -n 5 "$LOG" >&2
      rm -f "$PID_FILE"
      exit 1
    fi
    curl -s -o /dev/null "http://127.0.0.1:$PORT/" && { status; return; }
    sleep 1
  done
  echo "MCP Toolbox did not answer on port $PORT after 30 seconds. See $LOG." >&2
  exit 1
}

stop() {
  if running; then kill "$(cat "$PID_FILE")"; fi
  rm -f "$PID_FILE"
}

case "${1:-}" in
  start) start ;;
  stop) stop; echo "MCP Toolbox stopped." ;;
  restart) stop; sleep 1; start ;;
  status) status ;;
  *) echo "Usage: scripts/toolbox.sh start | restart | stop | status" >&2; exit 1 ;;
esac
