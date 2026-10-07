# Infrastructure and delivery

Decided stack is in [TECH_CONSTRAINTS.md](TECH_CONSTRAINTS.md). This document describes how it is built and shipped.

## Decisions
* One environment: `production`. No staging.
* Terraform lives in `infra/`. It is planned and applied from the owner's machine.
* Terraform state is in the S3 bucket `quizler-terraform` (eu-north-1) with native locking (`use_lockfile`). The bucket was created by hand, is not managed by Terraform, and has versioning, encryption and a public access block enabled.
* No domain at this stage. Public HTTPS comes from a CloudFront distribution on its default `*.cloudfront.net` name, in front of the ALB. A domain can be attached later.
* The application is deployed by GitHub Actions on push to `main`: build the image, push it to ECR, register a new ECS task definition revision and update the service.
  * GitHub authenticates to AWS with OIDC. No AWS keys are stored in GitHub.
  * The deploy role (defined in `infra/`) can only push to the ECR repository and update the ECS service, and is trusted only for `main` of this repository.
  * Terraform owns the ECS service and ignores `task_definition` changes, so local applies do not roll back a release.
* The database is an Aurora DSQL cluster, managed by Terraform in `infra/`. It uses IAM authentication only; the ECS task role gets `dsql:DbConnect` on the cluster. The database role and its `AWS IAM GRANT` are created once by hand with an `admin` token (see [TECH_CONSTRAINTS.md](TECH_CONSTRAINTS.md)). It is reached over its public endpoint, so no VPC endpoint is created.
* Media files are in the S3 bucket `quizler-media`, managed by Terraform (`infra/media.tf`). It is private (public access block, bucket-owner-enforced ownership, SSE-S3 encryption); clients read through presigned URLs only. IAM access for the ECS task role is added together with the server code that uses it.
* The repository is public, so workflow logs are public. Secret values are never managed by Terraform; it creates the secret containers only.

## Running Terraform
Scripts in `infra/scripts/` (they refuse to run as any identity other than the Quizler IAM user):
* `get-credentials.sh` signs in to the private AWS account.
* `plan.sh` shows the changes.
* `apply.sh` applies them after confirmation.
