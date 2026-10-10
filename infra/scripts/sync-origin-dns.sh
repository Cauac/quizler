#!/usr/bin/env bash
# Points origin.quizler.app (CloudFront's origin) at the public IP of the running task.
# Uses whatever AWS credentials are already set, so it runs locally (from start.sh) and in CI.
# Fails unless exactly one task is running.
#
# Environment:
#   HOSTED_ZONE_ID  optional, Route 53 zone of quizler.app; looked up by name when unset
#   CLUSTER         default quizler
#   SERVICE         default quizler-server
#   ORIGIN_NAME     default origin.quizler.app
#   AWS_REGION      default eu-north-1
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_zone.sh"
resolve_hosted_zone_id
CLUSTER=${CLUSTER:-quizler}
SERVICE=${SERVICE:-quizler-server}
ORIGIN_NAME=${ORIGIN_NAME:-origin.quizler.app}
export AWS_REGION=${AWS_REGION:-eu-north-1}

task_arns=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --desired-status RUNNING --query 'taskArns' --output text)
count=$(wc -w <<<"$task_arns" | tr -d ' ')
if [[ "$count" -ne 1 ]]; then
  echo "Expected exactly one running task in $CLUSTER/$SERVICE, found $count" >&2
  exit 1
fi

# The CLI prints both values on one line, tab-separated: lastStatus, then the ENI id.
read -r status eni < <(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task_arns" \
  --query 'tasks[0].[lastStatus, attachments[?type==`ElasticNetworkInterface`].details[] | [?name==`networkInterfaceId`].value | [0]]' \
  --output text)
if [[ "$status" != "RUNNING" || -z "$eni" || "$eni" == "None" ]]; then
  echo "Task is not running yet (status $status, ENI ${eni:-none})" >&2
  exit 1
fi

ip=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
if [[ -z "$ip" || "$ip" == "None" ]]; then
  echo "Network interface $eni has no public IP" >&2
  exit 1
fi

echo "Pointing $ORIGIN_NAME at $ip"
change_id=$(aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$ORIGIN_NAME\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"$ip\"}]}}]}" \
  --query 'ChangeInfo.Id' --output text)
aws route53 wait resource-record-sets-changed --id "$change_id"
echo "DNS record is in sync"
