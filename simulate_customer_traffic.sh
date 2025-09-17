#!/bin/bash

# Simulate continuous traffic against the backend /api/customers endpoint.
# Usage: ./simulate_customer_traffic.sh <api-host-or-url>
#   <api-host-or-url>  Hostname (e.g. backend-api.x.y.azurecontainerapps.io) OR full base URL (https://...)
# Description:
#   Continuously performs HTTP GET requests to /api/customers with a randomized
#   delay strictly less than 3 seconds between calls to mimic light organic traffic.
#   Press Ctrl+C to stop. A small summary will be printed on exit.
#
# Notes:
#   - Defaults to https if you only provide a host.
#   - Ensures each randomized sleep is < 3 seconds (uses high precision).
#   - Exits non-zero if no host/URL is provided.

set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "❌ Missing required argument: <api-host-or-url>" >&2
  echo "Usage: $0 <api-host-or-url>" >&2
  exit 1
fi

INPUT="$1"
# If the user did not include scheme, assume https
if [[ "$INPUT" =~ ^https?:// ]]; then
  BASE_URL="${INPUT%/}"
else
  BASE_URL="https://${INPUT%/}"
fi

TARGET_URL="${BASE_URL}/api/customers"

SUCCESS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

cleanup() {
  END_TIME=$(date +%s)
  DURATION=$((END_TIME-START_TIME))
  echo ""
  echo "────────────────────────────────────────"
  echo "📊 Traffic simulation summary"
  echo "   Target:    $TARGET_URL"
  echo "   Duration:  ${DURATION}s"
  echo "   Total:     $TOTAL"
  echo "   Success:   $SUCCESS"
  echo "   Failures:  $FAIL"
  echo "────────────────────────────────────────"
}

trap cleanup INT TERM

echo "🚀 Starting customer traffic simulation against: $TARGET_URL"
echo "🔁 Randomized delay (<3s) between requests. Press Ctrl+C to stop."

while true; do
  TOTAL=$((TOTAL+1))
  TS=$(date -Iseconds)
  # Measure latency using nanoseconds (if available) or fallback to ms approximation
  START_NS=$(date +%s%N 2>/dev/null || date +%s000000000)
  # Capture response body and HTTP status together
  RAW_RESPONSE=$(curl -s -w "HTTP_STATUS:%{http_code}" "$TARGET_URL" || echo "HTTP_STATUS:000")
  HTTP_CODE="${RAW_RESPONSE##*HTTP_STATUS:}"
  BODY="${RAW_RESPONSE%HTTP_STATUS:*}"

  # Attempt to extract query_time from JSON response
  QUERY_TIME=""
  if command -v jq >/dev/null 2>&1; then
    QUERY_TIME=$(echo "$BODY" | jq -r 'try .query_time // empty' 2>/dev/null || true)
  fi
  if [ -z "$QUERY_TIME" ]; then
    # Fallback simple regex extraction if jq not present
    QUERY_TIME=$(echo "$BODY" | grep -o '"query_time"[[:space:]]*:[[:space:]]*[^,}]*' | head -n1 | cut -d: -f2 | tr -d ' "')
  fi
  [ -z "$QUERY_TIME" ] && QUERY_TIME="n/a"
  END_NS=$(date +%s%N 2>/dev/null || date +%s000000000)
  # Compute latency in milliseconds with 3 decimal places
  LATENCY_MS=$(awk -v start="$START_NS" -v end="$END_NS" 'BEGIN{printf "%.3f", (end-start)/1000000}')

  if [ "$HTTP_CODE" = "200" ]; then
    SUCCESS=$((SUCCESS+1))
    echo "[$TS] ✅ 200 OK net_latency=${LATENCY_MS}ms query_time=${QUERY_TIME} (total=$TOTAL success=$SUCCESS fail=$FAIL)"
  else
    FAIL=$((FAIL+1))
    echo "[$TS] ❌ $HTTP_CODE net_latency=${LATENCY_MS}ms query_time=${QUERY_TIME} (total=$TOTAL success=$SUCCESS fail=$FAIL)"
  fi

  # Generate a random fractional delay strictly less than 3 seconds.
  # rand() returns [0,1); multiply by 3 to stay <3. Format to 3 decimals.
  DELAY=$(awk 'BEGIN{srand(); printf("%.3f", rand()*3)}')
  # Edge-case guard: if awk somehow gives 3.000, shave a tiny amount
  if awk "BEGIN{exit !($DELAY >= 3)}"; then
    DELAY=2.999
  fi
  sleep "$DELAY"
done
