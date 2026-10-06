#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)
TOKENS=$(echo "$input" | jq -r '
  (.context_window.current_usage.input_tokens // 0)
  + (.context_window.current_usage.cache_read_input_tokens // 0)
  + (.context_window.current_usage.cache_creation_input_tokens // 0)
')
MAX=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

if [ "$PCT" -ge 90 ]; then
  COLOR='\033[31m'; WARN=' !!'
elif [ "$PCT" -ge 70 ]; then
  COLOR='\033[33m'; WARN=' !'
else
  COLOR='\033[32m'; WARN=''
fi
RESET='\033[0m'

FILLED=$((PCT * 10 / 100))
[ "$FILLED" -lt 0 ] && FILLED=0
[ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))

BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf '▓%.0s' $(seq 1 "$FILLED"))
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf '░%.0s' $(seq 1 "$EMPTY"))"

fmt_k() { awk -v v="$1" 'BEGIN{s=sprintf("%.1f", v/1000); sub(/\.0$/, "", s); printf "%sk", s}'; }
TOKENS_K=$(fmt_k "$TOKENS")
MAX_K=$(fmt_k "$MAX")

printf "${COLOR}[%s]${RESET} %s ${COLOR}%s%%${RESET}%s | %s/%s | %s%% left" \
  "$MODEL" "$BAR" "$PCT" "$WARN" "$TOKENS_K" "$MAX_K" "$REMAINING"
