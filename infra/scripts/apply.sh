#!/usr/bin/env bash
# Applies Terraform changes after showing the plan and asking for confirmation.
# Extra arguments are passed to terraform apply.
source "$(dirname "$0")/_common.sh"

check_identity
terraform init -input=false
terraform apply "$@"
