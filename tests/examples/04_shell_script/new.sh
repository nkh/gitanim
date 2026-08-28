#!/bin/bash
set -euo pipefail

APP_NAME="myapp"
APP_PORT="${APP_PORT:-8080}"
APP_HOST="${APP_HOST:-0.0.0.0}"
LOG_FILE="${LOG_FILE:-/var/log/myapp.log}"
PID_FILE="/tmp/${APP_NAME}.pid"

log() {
    local level="$1"; shift
    echo "[$(date -Iseconds)] [$level] $*" | tee -a "$LOG_FILE"
}

start() {
    log INFO "Starting $APP_NAME on ${APP_HOST}:${APP_PORT}"
    "$APP_NAME" --host "$APP_HOST" --port "$APP_PORT" &
    echo $! > "$PID_FILE"
    log INFO "Started with PID $(cat "$PID_FILE")"
}

stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log INFO "Stopped PID $pid"
        else
            log WARN "PID $pid not running, removing stale pid file"
        fi
        rm -f "$PID_FILE"
    else
        log WARN "No PID file found at $PID_FILE"
    fi
}

status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        log INFO "$APP_NAME is running (PID $(cat "$PID_FILE"))"
        return 0
    else
        log INFO "$APP_NAME is not running"
        return 1
    fi
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    status)  status ;;
    *)       echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
