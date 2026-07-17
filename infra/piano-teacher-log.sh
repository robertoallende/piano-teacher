#!/usr/bin/env bash
# piano-teacher-log — Beautiful real-time logger for the piano-teacher demo.
#
# Polls CloudWatch logs and formats them for presentation.
# Usage: ./piano-teacher-log.sh [OPTIONS]
#   --since DURATION   How far back to look (default: 5m). Examples: 5m, 1h, 90m
#   --fresh            Skip history, only show new events from now

set -uo pipefail

# --- Configuration ---
LOG_GROUP="/aws/lambda/piano-teacher-handler"
REGION="us-east-1"
SINCE="5m"
FRESH=false
POLL_INTERVAL=3

# Track last seen to avoid duplicates
SEEN_FILE=$(mktemp)
trap "rm -f ${SEEN_FILE}" EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --since) SINCE="$2"; shift 2 ;;
        --fresh) FRESH=true; shift ;;
        *) SINCE="$1"; shift ;;
    esac
done

# --- Colors ---
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
RED="\033[31m"
WHITE="\033[97m"
BLUE="\033[34m"

# --- Header ---
clear
echo ""
printf "${BOLD}${CYAN}"
cat << 'EOF'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║          🎹  p i a n o - t e a c h e r  🎹            ║
    ║                                                       ║
    ║       Always-On Agent • AWS Bedrock + Strands         ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
printf "${RESET}\n"
if [ "$FRESH" = true ]; then
    printf "  ${DIM}Mode: live (waiting for new events)${RESET}\n"
else
    printf "  ${DIM}Mode: replay + live (since ${SINCE} ago)${RESET}\n"
fi
printf "  ${DIM}Region: ${REGION} • Polling every ${POLL_INTERVAL}s${RESET}\n"
echo ""
printf "  ${DIM}────────────────────────────────────────────────────${RESET}\n"
echo ""

# --- Format a single log line ---
format_line() {
    local line="$1"
    local now
    now=$(date +"%H:%M:%S")

    # Skip noise
    case "$line" in
        *INIT_START*|*"END Request"*|*"REPORT Request"*|*"START Request"*|""|*LAMBDA_WARNING*)
            return
            ;;
    esac

    if [[ "$line" == *"Received event"* ]]; then
        printf "  ⚡ ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[S3]${RESET}        ${WHITE}Event received → board.md modified${RESET}\n"
    elif [[ "$line" == *"Found"*"card(s) to process"* ]]; then
        local cards
        cards=$(echo "$line" | grep -oE "\[.*\]")
        printf "  🎹 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Agent]${RESET}    ${GREEN}Matched: ${BOLD}${cards}${RESET}\n"
    elif [[ "$line" == *"Flipping card"* ]]; then
        local title
        title=$(echo "$line" | grep -oE "'[^']+'" | head -1)
        printf "  🔒 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Guard]${RESET}    ${DIM}${title} → done${RESET}\n"
    elif [[ "$line" == *"Board updated: matched cards"* ]]; then
        printf "  ✓  ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[S3]${RESET}        ${DIM}Board written (loop guard)${RESET}\n"
    elif [[ "$line" == *"Processing card:"*"docs:"* ]]; then
        local title docs
        title=$(echo "$line" | grep -oE "'[^']+'" | head -1)
        docs=$(echo "$line" | grep -oE "docs: [^ ]+" | sed 's/docs: //')
        echo ""
        printf "  🧠 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Bedrock]${RESET}  ${MAGENTA}Analyzing: ${BOLD}${title}${RESET}\n"
        printf "     ${DIM}         Reading ${docs}${RESET}\n"
    elif [[ "$line" == *"PDF read:"* ]]; then
        local size
        size=$(echo "$line" | grep -oE "[0-9]+ bytes")
        printf "  📄 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[S3]${RESET}        ${DIM}PDF loaded (${size})${RESET}\n"
        printf "  ⏱  ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Bedrock]${RESET}  ${MAGENTA}Sending to Claude Sonnet 4.5...${RESET}\n"
    elif [[ "$line" == *"Analysis complete:"* ]]; then
        local count
        count=$(echo "$line" | grep -oE "[0-9]+ lessons")
        printf "  ✨ ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Bedrock]${RESET}  ${BOLD}${MAGENTA}Complete: ${count} planned${RESET}\n"
        echo ""
    elif [[ "$line" == *"Written: lessons/"* ]]; then
        local path
        path=$(echo "$line" | grep -oE "lessons/[^ ]+" | sed 's/lessons\///')
        printf "  📖 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[S3]${RESET}        ${YELLOW}✓ ${path}${RESET}\n"
    elif [[ "$line" == *"Prepended"* ]]; then
        local info
        info=$(echo "$line" | sed 's/.*Prepended //')
        printf "  📋 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[S3]${RESET}        ${GREEN}Lessons.md updated${RESET}\n"
    elif [[ "$line" == *"Done:"*"lessons generated"* ]]; then
        local info
        info=$(echo "$line" | sed 's/.*Done: //')
        echo ""
        printf "  ✨ ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Agent]${RESET}    ${BOLD}${GREEN}${info}${RESET}\n"
        echo ""
        printf "  ${DIM}────────────────────────────────────────────────────${RESET}\n"
        echo ""
    elif [[ "$line" == *"No cards with status=doing"* ]]; then
        printf "  🔒 ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${BLUE}[Guard]${RESET}    ${DIM}No matching cards → exit${RESET}\n"
    elif [[ "$line" == *"ERROR"* ]]; then
        local msg
        msg=$(echo "$line" | sed 's/.*ERROR[: ]*//')
        printf "  ✗  ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${RED}[Error]${RESET}    ${RED}${msg}${RESET}\n"
    elif [[ "$line" == *"WARNING"* ]]; then
        local msg
        msg=$(echo "$line" | sed 's/.*WARNING[: ]*//')
        printf "  ⚠  ${BOLD}${CYAN}[${now}]${RESET} ${BOLD}${YELLOW}[Warn]${RESET}     ${YELLOW}${msg}${RESET}\n"
    fi
}

# --- Main ---

# Replay recent logs (unless --fresh)
if [ "$FRESH" = false ]; then
    aws logs tail "${LOG_GROUP}" \
        --region "${REGION}" \
        --since "${SINCE}" \
        --format short 2>/dev/null | \
    while IFS= read -r raw; do
        line="${raw#* }"
        format_line "$line"
    done
fi

printf "  ${DIM}Waiting for new events...${RESET}\n"
echo ""

# Follow: poll every N seconds for new logs
while true; do
    sleep "${POLL_INTERVAL}"
    aws logs tail "${LOG_GROUP}" \
        --region "${REGION}" \
        --since "10s" \
        --format short 2>/dev/null | \
    while IFS= read -r raw; do
        # Deduplicate by checking if we've seen this exact line
        hash=$(echo "$raw" | md5 -q 2>/dev/null || echo "$raw" | md5sum | cut -d' ' -f1)
        if grep -qF "$hash" "$SEEN_FILE" 2>/dev/null; then
            continue
        fi
        echo "$hash" >> "$SEEN_FILE"
        line="${raw#* }"
        format_line "$line"
    done
done
