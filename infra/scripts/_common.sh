# Sourced by the other scripts. Runs terraform in infra/ as the quizler-terraform IAM user.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export AWS_PROFILE=quizler
EXPECTED_USER=quizler-terraform

check_identity() {
  local arn
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || {
    echo "Not logged in. Run infra/scripts/get-credentials.sh" >&2
    return 1
  }
  if [[ "$arn" != *":user/$EXPECTED_USER" ]]; then
    echo "Wrong AWS identity: $arn (expected user $EXPECTED_USER)" >&2
    return 1
  fi
  echo "AWS identity: $arn"
}
