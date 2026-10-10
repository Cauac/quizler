# Sourced by sync-origin-dns.sh and reset-origin-dns.sh. Uses the AWS credentials already set.
# Sets HOSTED_ZONE_ID (exported) unless it is already set: the Route 53 zone of $DOMAIN.
resolve_hosted_zone_id() {
  if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
    return 0
  fi
  local domain=${DOMAIN:-quizler.app} id
  id=$(aws route53 list-hosted-zones-by-name --dns-name "$domain" --max-items 1 \
    --query "HostedZones[?Name=='$domain.'].Id | [0]" --output text)
  if [[ -z "$id" || "$id" == "None" ]]; then
    echo "Hosted zone for $domain not found" >&2
    return 1
  fi
  export HOSTED_ZONE_ID=${id##*/}
}
