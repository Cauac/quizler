#!/usr/bin/env bash
# Stops the game server, waits until no tasks are running and resets the origin DNS record.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

check_identity

echo "Stopping $SERVICE..."
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 0 >/dev/null

# Right away, before the task's IP is released to AWS. Also repairs a stop that failed halfway.
"$SCRIPT_DIR/reset-origin-dns.sh"

aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

running=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].runningCount' --output text)
echo "Stopped ($running tasks running)"
