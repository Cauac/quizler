#!/usr/bin/env bash
# Shows what Terraform would change. Extra arguments are passed to terraform plan.
source "$(dirname "$0")/_common.sh"

check_identity
terraform init -input=false
terraform plan "$@"
