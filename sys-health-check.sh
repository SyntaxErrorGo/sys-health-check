#!/usr/bin/env bash

set -euo pipefail

CONFIG_PATH_DEFAULT="/etc/sys-health-check.conf"

CONFIG_PATH="${1:-$CONFIG_PATH_DEFAULT}"
if [ ! -f  "$CONFIG_PATH" ]; then
    echo "Config file not found: $CONFIG_PATH" >&2
    exit 1
fi

. "$CONFIG_PATH"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
HOSTNAME_ACTUAL="$(hostname)"
HOST_LABEL_EFFECTIVE="${HOST_LABEL:-$HOSTNAME_ACTUAL}"

OUTPUT_DIR="${OUTPUT_DIR:-/var/log/sys-health-check}"
mkdir -p "$OUTPUT_DIR"

REPORT_FILE="$OUTPUT_DIR/health-$(date '+%Y%m%d-%H%M%S').txt"

DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
MEM_THRESHOLD="${MEM_THRESHOLD:-90}"
LOAD_THRESHOLD="${LOAD_THRESHOLD:-4.0}"
CHECK_SERVICES="${CHECK_SERVICES:-}"

TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

OVERALL_STATUS="OK"

update_overall() {
    case "$OVERALL_STATUS" in 
        CRIT)
            ;;
        WARN)
            if [ "$1" = "CRIT" ]; then
                OVERALL_STATUS="CRIT"
            fi
            ;;
        OK)
            OVERALL_STATUS="$1"
            ;;
    esac

}

write_line() {
    printf '%s\n' "$1" >> "$REPORT_FILE"
}

check_load() {
    if [ -r /proc/loadavg ]; then
        load_1="$(awk '{print $1}' /proc/loadavg)"
        cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
        load_norm="$(awk "BEGIN { if ($cpu_count > 0) printf \"%.2f\", $load_1 / $cpu_count; else print 0 }")"
        load_status="OK"
        if awk "BEGIN { exit !($load_norm >= $LOAD_THRESHOLD) }"; then
            load_status="WARN"
        fi
        update_overall "$load_status"
        write_line "LOAD: $load_status (1min load: $load_1, normalized: $load_norm, CPUs: $cpu_count)"
        else
            write_line "LOAD: UNKNOWN (/proc/loadavg not readable)"
        fi
}

check_memory() {
    if grep -q '^MemTotal:' /proc/meminfo 2>/dev/null && grep -q '^MemAvailable' /proc/meminfo 2>/dev/nul; then
        mem_total_kb="$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}' )"
        mem_avail_kb="$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}' )"
        if [ "$mem_total_kb" -gt 0 ]; then
            mem_used_pct="$(awk "BEGIN { printf \"%.0f\", (1 -$mem_avail_kb / $mem_total_kb) * 100 }")"
            mem_status="OK"
            if [ "$mem_used_pct" -ge "$MEM_THRESHOLD" ]; then
                mem_status="WARN"
            fi
            update_overall "$mem_status"
            write_line "MEMORY: $mem_status ($mem_used_pct%% used)"
        else
            write_line "MEMORY: UNKNOWN (MemTotal is zero)"
        fi
    else
        write_line "MEMORY: UNKNOWN (/proc/meminfo missing fields)"    
    fi
}

check_disks() {
    if command -v df >/dev/null 2>&1; then
        write_line ""
        write_line "DISKS:"
        while IFS= read -r line; do
            mount_point="$(printf '%s\n' "$line" | awk '{print $6}')"
            used_pct_raw="$(printf '%s\n' "$line" | awk '{print $5}')"
            used_pct="${used_pct_raw%%%}"
            disk_status="OK"
            if [ "$used_pct" -ge "$DISK_THRESHOLD" ]; then
                disk_status="WARN"
            fi
            update_overall "$disk_status"
            write_line " $disk_status $mount_point ($used_pct_raw used)"
        done < <(df -P -x tmpfs -x devtmpfs | awk 'NR>1')
    else
        write_line ""
        write_line "DISKS: UNKNOWN (df not found)"
    fi
}

check_services() {
    if [ -z "$CHECK_SERVICES" ]; then
        return 0
    fi
    write_line ""
    write_line "SERVICES:"
    for svc in $CHECK_SERVICES; do
        svc_status="UNKNOWN"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet "$svc"; then
                svc_status="OK"
            else
                svc_status="CRIT"
            fi
        else
            if command -v service >/dev/null 2>&1; then
                if service "$svc" status >/dev/null 2>&1; then
                    svc_status="OK"
                else
                    svc_status="CRIT"
                fi
            fi
        fi
        update_overall "$svc_status"
        write_line " $svc_status $svc "
    done
}

send_telegram() {
    if [ "$TELEGRAM_ENABLED" != "true" ]; then
        return 0
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    text="$(printf 'Sys health on %s (%s) \n \n' "$HOST_LABEL_EFFECTIVE" "$HOSTNAME_ACTUAL"; "$REPORT_FILE")"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$text" \
        >/dev/null 2>&1 || true
}

: >"$REPORT_FILE"
write_line "System health report"
write_line "Host: $HOST_LABEL_EFFECTIVE ($HOSTNAME_ACTUAL)"
write_line "Time: $TIMESTAMP"
write_line ""

check_load
check_memory
check_disks
check_services

write_line ""
write_line "OVERALL STATUS: $OVERALL_STATUS"

send_telegram

printf '%s\n' "Report written to $REPORT_FILE"
printf '%s\n' "Overall status: $OVERALL_STATUS"