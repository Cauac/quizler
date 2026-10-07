#!/usr/bin/env bash
# Signs in to the private AWS account in the browser and checks the identity.
source "$(dirname "$0")/_common.sh"

aws login --profile "$AWS_PROFILE"
check_identity
