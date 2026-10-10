#!/usr/bin/env bash
# Starts the game server and waits until https://quizler.app/health answers.
# Safe to re-run while the service is up, e.g. to repair DNS after ECS replaced a crashed task.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

HEALTH_URL="https://$DOMAIN/health"
HEALTH_TIMEOUT=300

check_identity

started=$SECONDS

echo "Starting $SERVICE..."
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 1 >/dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

CLUSTER=$CLUSTER SERVICE=$SERVICE "$SCRIPT_DIR/sync-origin-dns.sh"

echo "Waiting for $HEALTH_URL..."
health_started=$SECONDS
while ! curl -fsS -o /dev/null --max-time 5 "$HEALTH_URL" 2>/dev/null; do
  if (( SECONDS - health_started > HEALTH_TIMEOUT )); then
    echo "Timed out after ${HEALTH_TIMEOUT}s waiting for $HEALTH_URL" >&2
    exit 1
  fi
  sleep 3
done

echo "Up: https://$DOMAIN (took $((SECONDS - started)) s)"
