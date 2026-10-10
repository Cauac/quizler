#!/usr/bin/env bash
# Points origin.quizler.app back at the placeholder address (192.0.2.1, RFC 5737, same as in
# infra/dns.tf). Run after stopping the service: the task's public IP returns to the AWS pool
# and could be given to someone else, who would then receive CloudFront's requests
# (cookies, Authorization headers) and answer under our certificate.
# Uses whatever AWS credentials are already set, so it runs locally and in CI.
#
# Environment:
#   HOSTED_ZONE_ID  optional, Route 53 zone of quizler.app; looked up by name when unset
#   ORIGIN_NAME     default origin.quizler.app
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_zone.sh"
resolve_hosted_zone_id
ORIGIN_NAME=${ORIGIN_NAME:-origin.quizler.app}
PLACEHOLDER_IP=192.0.2.1

echo "Pointing $ORIGIN_NAME at the placeholder $PLACEHOLDER_IP"
change_id=$(aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$ORIGIN_NAME\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"$PLACEHOLDER_IP\"}]}}]}" \
  --query 'ChangeInfo.Id' --output text)
aws route53 wait resource-record-sets-changed --id "$change_id"
echo "DNS record is reset"
