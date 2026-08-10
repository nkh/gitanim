#!/bin/bash
set -e

APP_NAME="myapp"
APP_PORT=8080
LOG_FILE="/var/log/myapp.log"

start() {
    echo "Starting $APP_NAME on port $APP_PORT"
    $APP_NAME --port $APP_PORT &
    echo $! > /tmp/$APP_NAME.pid
}

stop() {
    if [ -f /tmp/$APP_NAME.pid ]; then
        kill $(cat /tmp/$APP_NAME.pid)
        rm /tmp/$APP_NAME.pid
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    *)       echo "Usage: $0 {start|stop|restart}"; exit 1 ;;
esac
