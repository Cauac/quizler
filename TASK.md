# Task: ECS stack with a hello-world container

Goal: build and deploy a minimal container to ECS Fargate, reachable at `https://quizler.app`, that costs close to nothing while idle. The real game server replaces the container later; the infrastructure stays.

## Decisions

* **No ALB.** CloudFront sends traffic straight to the Fargate task's public IP. An ALB can be added later if needed.
* **Manual start and stop.** The owner runs `start.sh` before the game and `stop.sh` after it. The service's desired count is 0 the rest of the time. A scheduled GitHub Actions workflow stops the service at midnight in case `stop.sh` is forgotten.
* **DNS on Route 53.** Terraform creates a hosted zone for `quizler.app`; the nameservers are switched at Namecheap once.
* **Hostnames:** `quizler.app` and `www.quizler.app` point to CloudFront. `origin.quizler.app` is an A record holding the current task's public IP; it is CloudFront's origin.
* **The scripts keep DNS pointed at the task.** `sync-origin-dns.sh` points `origin.quizler.app` at the running task's public IP. `start.sh` and the deploy workflow run it after the service is stable. There is no Lambda or EventBridge. If ECS replaces a crashed task, the site stays down until `start.sh` is run again; it is safe to re-run.
* **CloudFront → task is plain HTTP**, on port 8080. The task's security group accepts traffic only from the AWS-managed CloudFront origin-facing prefix list. There is no secret origin header: someone with their own CloudFront distribution could reach the origin. This is accepted for now.
* **One task at a time.** Deployment config: minimum healthy 0%, maximum 100%. The old task stops before the new one starts, so there are never two servers. A deploy causes a short outage, so do not push to `main` during a game.
* **Hello world is a minimal Clojure app**, so the real build path (deps.edn, uberjar, JVM image) and JVM cold start are tested.
* **ARM64 (Graviton) Fargate**, 0.5 vCPU / 1 GB. It is cheaper than x86, and GitHub provides free ARM runners for public repositories.
* **The CI/CD deploy pipeline is in scope**, as described in `docs/INFRA.md` (GitHub Actions, OIDC, push to `main`).

## Expected cost

| Item | Idle | Per game night (~3 h) |
|---|---|---|
| Fargate task + public IPv4 | $0 | ~$0.10 |
| Route 53 hosted zone | $0.50/month | – |
| CloudFront, ACM, ECR, logs | ~$0 | ~$0 |

About $1/month in total, plus the domain renewal.

## Work items

### 1. Hello-world app (`server/`)
* `deps.edn`, a minimal HTTP server (e.g. http-kit or ring-jetty) on port 8080.
  * `GET /` returns "Hello from Quizler" with the build's git SHA (read from an env var).
  * `GET /health` returns 200.
* `build.clj` (tools.build) to produce an uberjar.
* `Dockerfile`, multi-stage: build with the official Clojure tools-deps image, run on `eclipse-temurin:21-jre` (arm64). Runs as a non-root user.
* Check: `docker build` and `docker run` locally, then `curl localhost:8080/health`.

### 2. Networking (`infra/network.tf`)
* A dedicated VPC with 2 public subnets in 2 AZs and an internet gateway. No NAT gateway and no private subnets.
* Task security group:
  * Ingress: TCP 8080 from the prefix list `com.amazonaws.global.cloudfront.origin-facing` only. This prefix list uses about 55 of the 60 default rules per security group, so the group holds nothing else.
  * Egress: all. Needed for ECR, CloudWatch Logs, and later DSQL and Bedrock over public endpoints.

### 3. Container registry (`infra/ecr.tf`)
* ECR repository `quizler-server`: immutable tags, scan on push, and a lifecycle policy that keeps the last 10 images.

### 4. ECS (`infra/ecs.tf`)
* Cluster `quizler`, Fargate only, with Container Insights off.
* CloudWatch log group `/ecs/quizler-server`, 14-day retention.
* Task execution role: pull from ECR, write logs.
* Task role: empty for now. `dsql:DbConnect`, S3 and Bedrock are added with the code that needs them.
* Task definition: ARM64, 0.5 vCPU / 1 GB, port 8080, awslogs driver. The image is `quizler-server:bootstrap`; CI replaces it.
* Service `quizler-server`:
  * Desired count 0, public subnets, `assign_public_ip = true`.
  * Deployment: minimum 0%, maximum 100%, circuit breaker with rollback.
  * `lifecycle.ignore_changes = [task_definition, desired_count]`, so Terraform does not roll back releases or stop a running game.

### 5. DNS and TLS (`infra/dns.tf`)
* Route 53 hosted zone `quizler.app`. Output its nameservers.
* ACM certificate in `us-east-1` (required by CloudFront) for `quizler.app` and `www.quizler.app`, validated through DNS. Needs a second, aliased `aws` provider for `us-east-1`.
* Alias A and AAAA records for `quizler.app` and `www.quizler.app` → CloudFront.
* `origin.quizler.app` A record, TTL 60, created with a placeholder IP. Terraform ignores changes to its value; `sync-origin-dns.sh` owns it.

### 6. DNS sync script (`infra/scripts/sync-origin-dns.sh`)
* Finds the running task (`ecs:ListTasks`, `ecs:DescribeTasks`) and reads its ENI's public IP (`ec2:DescribeNetworkInterfaces`).
* UPSERTs `origin.quizler.app` (`route53:ChangeResourceRecordSets`) and waits for the change to reach `INSYNC`.
* Fails if there is not exactly one running task.
* It uses whatever AWS credentials are already set and does not source `_common.sh`, so it runs both locally (called from `start.sh` after the identity check) and in CI.
* The hosted zone ID, cluster and service names are passed as arguments or env vars. They are not secrets.

### 7. CloudFront (`infra/cdn.tf`)
* Origin `origin.quizler.app`, HTTP only, port 8080. Origin read timeout 60 s, keep-alive 60 s. SSE will need a heartbeat more often than every 60 s.
* Aliases `quizler.app` and `www.quizler.app`, with the ACM certificate. Viewer protocol: redirect to HTTPS. HTTP/2 and HTTP/3.
* All methods allowed. Managed policies: `CachingDisabled` and `AllViewerExceptHostHeader`. Price class 100.

### 8. Safety stop (`.github/workflows/stop.yml`)
* A scheduled workflow (`cron: "0 0 * * *"`, midnight UTC) plus `workflow_dispatch` for manual runs and testing.
* It assumes the deploy role through OIDC (scheduled runs use `main`, so the existing trust applies) and calls `aws ecs update-service --desired-count 0`. It is a no-op when the service is already stopped.
* Caveats:
  * GitHub can delay scheduled runs, sometimes by tens of minutes.
  * GitHub disables scheduled workflows in a public repository after 60 days without repository activity. The workflow must be re-enabled if that happens.

### 9. Start and stop scripts (`infra/scripts/`)
Both scripts use the existing `_common.sh` identity check.
* `start.sh`:
  1. Set the desired count to 1.
  2. Run `aws ecs wait services-stable`.
  3. Run `sync-origin-dns.sh`.
  4. Poll `https://quizler.app/health` until it returns 200, with a timeout.
  5. Print the URL and the time it took.
* `start.sh` is safe to re-run while the service is up, for example to repair DNS after ECS replaced a task.
* `stop.sh`: set the desired count to 0 and wait until no tasks are running.

### 10. CI/CD (`infra/github.tf`, `.github/workflows/deploy.yml`)
* GitHub OIDC identity provider (`token.actions.githubusercontent.com`).
* Deploy role, trusted only for `repo:Cauac/quizler:ref:refs/heads/main`. Allowed actions:
  * ECR push to `quizler-server`
  * `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`
  * `ecs:UpdateService` and `ecs:DescribeServices` on this service
  * `iam:PassRole` on the task and execution roles
  * For the DNS sync: `ecs:ListTasks`, `ecs:DescribeTasks`, `ec2:DescribeNetworkInterfaces`, and `route53:ChangeResourceRecordSets` / `route53:GetChange` on this zone only
* Workflow triggered by pushes to `main` that touch `server/**` or the workflow file. It runs on `ubuntu-24.04-arm`:
  1. Assume the role through OIDC.
  2. Build and push the image tagged with the git SHA.
  3. Render a new task definition with that image and the `GIT_SHA` env var.
  4. Update the service.
  5. If the service's desired count is 1: wait for it to be stable, then run `sync-origin-dns.sh`. When the service is stopped (desired count 0), skip this step.
* The role ARN is a GitHub Actions repository variable. It is not a secret.

### 11. Docs
* `docs/INFRA.md`: replace the ALB description with this design (no ALB, Route 53, DNS sync script (and the manual recovery after a task crash), start/stop scripts, the midnight safety-stop workflow and its 60-day inactivity caveat, HTTP origin with the prefix-list restriction and no secret header). Mark the domain as attached.
* `docs/TECH_CONSTRAINTS.md`: record the new decisions. Running a single task for now does not settle the open question "number of server tasks"; that stays open.

## Rollout order
1. Apply only the hosted zone: `terraform apply -target=aws_route53_zone.main`.
2. **Manual:** at Namecheap, set the nameservers to the zone's NS records. Wait for propagation (`dig NS quizler.app`).
3. Full `apply.sh`. ACM validation completes once DNS is delegated. The service exists with 0 tasks.
4. Set the repository variable with the deploy role ARN. Push to `main` (or re-run the workflow) to build and deploy the first image.
5. Run `start.sh` and open `https://quizler.app`. Check the redirect from HTTP to HTTPS, `www`, and `/health`.
6. Run `stop.sh`, then start again. Confirm the DNS record follows the new IP.
7. Push a trivial change while the service is running. Confirm the deploy rolls the task and the site comes back.

## Done when
* `start.sh` brings `https://quizler.app` up from zero, and the script reports the cold-start time.
* `stop.sh` brings it back to zero tasks, and running the safety-stop workflow manually (`workflow_dispatch`) against a running service stops it.
* A push to `main` deploys a new image without Terraform drift (`plan.sh` shows no changes afterwards).
* The task port is unreachable except through CloudFront. A direct `curl` to the task IP times out.

## Out of scope
* ALB, a secret origin header, TLS on the task.
* Idle detection inside the app (scaling down when there are no SSE connections). Add it with the real server.
* DSQL, S3 media and Bedrock permissions for the task role.
* Container health checks in the task definition (the JRE image has no curl). Revisit with the real server.

## Risks
* **A crashed task is not recovered automatically:** ECS starts a replacement with a new IP, but DNS still points at the old one. Recovery: re-run `start.sh`. If this happens in practice, add the EventBridge + Lambda updater back.
* **CloudFront caching the origin DNS:** after a task change, CloudFront may keep using the old IP briefly. TTL is 60 s; `start.sh` polls the public URL, so it waits this out.
* **A deploy during a game** drops all connections and any in-memory state. Don't push to `main` on game night.
* **A non-ALB origin** limits CloudFront features (no VPC origin, plain HTTP). Adding an ALB later only changes the origin and the security group.

## Implementation notes

Status: all work items are written. Nothing is applied to AWS, pushed or committed yet. The rollout steps and the "Done when" checks are still to be done by the owner.

### Verified locally
* Hello-world app: the uberjar builds, `docker build` works, `docker run` serves `/` (hello text plus `GIT_SHA`) and `/health` (200), and the container runs as UID 10001.
* `terraform fmt -check` and `terraform validate` pass. `terraform plan` was not run (needs the owner's AWS login).
* Workflow YAML parses. The JMESPath query in `sync-origin-dns.sh` and the jq transform in `deploy.yml` were tested on sample data.
* Not tested: anything that talks to AWS or GitHub (scripts, workflows, Terraform apply).

### Files
| Item | Files |
|---|---|
| 1. App | `server/deps.edn`, `server/build.clj`, `server/src/quizler/server.clj`, `server/Dockerfile`, `server/.dockerignore` |
| 2. Networking | `infra/network.tf` |
| 3. ECR | `infra/ecr.tf` |
| 4. ECS | `infra/ecs.tf` |
| 5. DNS and TLS | `infra/dns.tf`, `infra/versions.tf` (aliased `us_east_1` provider) |
| 6. DNS sync | `infra/scripts/sync-origin-dns.sh` |
| 7. CloudFront | `infra/cdn.tf` |
| 8. Safety stop | `.github/workflows/stop.yml` |
| 9. Start and stop | `infra/scripts/start.sh`, `infra/scripts/stop.sh`, `infra/scripts/reset-origin-dns.sh`, `infra/scripts/_zone.sh` (zone lookup), `infra/scripts/_common.sh` |
| 10. CI/CD | `infra/github.tf`, `.github/workflows/deploy.yml` |
| 11. Docs | `docs/INFRA.md`, `docs/TECH_CONSTRAINTS.md` |

### Details by item

**1. App.** Clojure 1.12.0, http-kit 2.8.0, tools.build 0.10.5. `quizler.server` listens on 8080 and stops the server from a shutdown hook, which ECS triggers with SIGTERM. The hook waits (up to 10 s) on the promise returned by http-kit's `server-stop!`, so in-flight requests get the 5 s drain before the JVM exits; without the `deref` the hook returns at once. Unknown routes return 404. `build.clj` AOT-compiles `quizler.server` and writes `target/quizler-server.jar`. The Dockerfile copies `deps.edn` first and prefetches dependencies, so the dependency layer is cached. The runtime image is `eclipse-temurin:21-jre` and runs with `-XX:MaxRAMPercentage=75`, because the default heap (25% of 1 GB) is too small.

**2. Networking.** VPC `10.0.0.0/16` with DNS hostnames, two `/24` public subnets in the first two available AZs, an internet gateway and one route table. The security group `quizler-task` has one ingress rule (TCP 8080 from the CloudFront origin-facing prefix list, read with a data source) and an all-traffic egress rule. Rules are separate `aws_vpc_security_group_*_rule` resources.

**3. ECR.** Immutable tags, scan on push, lifecycle rule "expire when more than 10 images".

**4. ECS.** The cluster has Container Insights disabled and `FARGATE` as its only capacity provider. The execution role uses the AWS-managed `AmazonECSTaskExecutionRolePolicy`; the task role has no policies. The task definition (family `quizler-server`, container `server`, ARM64, 512 CPU / 1024 MB) points to `quizler-server:bootstrap`, which does not exist in ECR. This is harmless while the desired count is 0 and CI registers a real revision before the first start. The service ignores `task_definition` and `desired_count`. CI's later task definition revisions do not cause drift, because Terraform only compares its own revision.

**5. DNS and TLS.** The ACM certificate (apex plus `www`) is validated through records in the zone; `aws_acm_certificate_validation` blocks `apply` until the nameservers are switched at Namecheap. Alias A and AAAA records for both names point to CloudFront. `origin.quizler.app` is created with `192.0.2.1` (RFC 5737 documentation address), TTL 60, and `ignore_changes = [records]`. Outputs: `name_servers`, `hosted_zone_id`.

**6. DNS sync.** `HOSTED_ZONE_ID` is optional (looked up by name when unset, see "Review improvements"). `CLUSTER`, `SERVICE`, `ORIGIN_NAME` and `AWS_REGION` have defaults. Steps: list the service's tasks with desired status RUNNING (exactly one required), check `lastStatus` is `RUNNING`, read the ENI id from the task attachments, read the public IP from the ENI, UPSERT the A record, and wait with `aws route53 wait resource-record-sets-changed`. It does not source `_common.sh` (it sources the small `_zone.sh`, which has no side effects).

**7. CloudFront.** Origin `origin.quizler.app` (via the record's `fqdn`, which orders creation correctly), `http-only` on 8080, read and keep-alive timeouts 60 s. Managed policies are looked up by name (`Managed-CachingDisabled`, `Managed-AllViewerExceptHostHeader`). Viewer certificate: SNI only, `TLSv1.2_2021`. IPv6 is enabled so the AAAA records work.

**8. Safety stop.** `stop.yml` reads the desired count first and sets it to 0 only when it is not 0. It then always runs `infra/scripts/reset-origin-dns.sh` (see "Review fix" below), so it checks out the repository. The script finds the hosted zone itself, so no `HOSTED_ZONE_ID` variable is needed.

**9. Scripts.** `_common.sh` now also sets `AWS_REGION=eu-north-1`, `CLUSTER`, `SERVICE` and `DOMAIN`. `start.sh` updates the service, waits with `services-stable`, runs the sync script, then polls `https://quizler.app/health` every 3 s for at most 300 s (the timeout counts from the end of the sync, not from the start of the script). It prints the total elapsed time. `stop.sh` sets the count to 0, runs `reset-origin-dns.sh`, waits with `services-stable` and prints `runningCount`. The hosted zone is looked up inside `sync-origin-dns.sh` and `reset-origin-dns.sh`. `services-stable` waits up to 10 minutes.

**10. CI/CD.**
* `github.tf` creates the OIDC provider and the role `quizler-deploy`, trusted for `repo:Cauac/quizler:ref:refs/heads/main` with audience `sts.amazonaws.com`. Its inline policy has one statement per need:
  * ECR login, push and `ecr:DescribeImages`
  * task definition register and describe (no resource-level permissions exist for these two)
  * service update and describe
  * `iam:PassRole` limited to the two task roles and to `ecs-tasks.amazonaws.com`
  * `ecs:ListTasks` limited to the cluster (condition), `ecs:DescribeTasks` limited to the cluster's tasks
  * `ec2:DescribeNetworkInterfaces`
  * Route 53: `ListHostedZonesByName`, `GetChange`, and record changes on the zone limited by conditions to UPSERT of A records named `origin.quizler.app`
* `deploy.yml` runs on pushes to `main` touching `server/**` or itself, and on `workflow_dispatch` (added so the first image can be built without a dummy push). Concurrent runs are serialised. The task definition is rendered with jq from the latest revision, keeping only fields that `register-task-definition` accepts and setting the image and `GIT_SHA` (the full commit SHA, also the image tag). Actions used: `actions/checkout@v7`, `aws-actions/configure-aws-credentials@v6`, `aws-actions/amazon-ecr-login@v2`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`.
* Repository variable to set by hand (not a secret): `AWS_DEPLOY_ROLE_ARN` (Terraform output `deploy_role_arn`).

### Review fix: dangling origin record
Problem: after a stop, `origin.quizler.app` kept the task's old public IP. AWS can give that IP to another customer, and CloudFront would send `quizler.app` requests (with cookies and `Authorization` headers) to their server on port 8080, which would answer under our certificate.

Fix: `infra/scripts/reset-origin-dns.sh` UPSERTs the record back to the placeholder `192.0.2.1` (the same value as in `dns.tf`) and waits for `INSYNC`. `stop.sh` and `stop.yml` run it right after setting the desired count to 0, before the task's IP is released, and also when the service was already stopped, so a half-finished stop is repaired. The deploy role already had permission to change the record. Remaining window: a task that crashes or is replaced by ECS keeps its old IP in DNS until `start.sh` is run (documented in `docs/INFRA.md`).

### Review fix: re-running the deploy
Problem: ECR tags are immutable and the tag is the git SHA, so "Re-run jobs" or `workflow_dispatch` on the same commit failed at `docker push`.

Fix: `deploy.yml` runs `aws ecr describe-images --image-ids imageTag=$GITHUB_SHA` first. If the image exists, build and push are skipped and the rest of the workflow (task definition, service update, DNS sync) runs. Only `ImageNotFoundException` means "not there, build it"; any other error (for example missing permission) fails the step instead of falling through to a push. The deploy role got `ecr:DescribeImages` on the repository in `github.tf`.

### Review fixes: shutdown drain and rolled-back deploys
* Shutdown hook: `server-stop!` only signals the server and returns a promise (checked in the http-kit 2.8.0 source). The hook now derefs it (10 s cap). Tested with a scratch server with a 3 s handler: a request in flight when SIGTERM arrived still completed with 200.
* Rolled-back deploy shown as green: when the circuit breaker rolls back, `services-stable` succeeds on the old revision. After the wait, `deploy.yml` reads the PRIMARY deployment and fails the job unless its `taskDefinition` equals the one just registered and `rolloutState` is `COMPLETED`. It fails at once on a different task definition or on `FAILED`, and polls up to 60 s for `COMPLETED` since the state can lag behind `services-stable`. The DNS sync runs only after this check. Not tested against real ECS; the JMESPath query was checked on sample data.

### Review improvements
* **Route 53 scope of the deploy role.** The `OriginRecord` statement in `github.tf` has `ForAllValues:StringEquals` conditions: `route53:ChangeResourceRecordSetsNormalizedRecordNames = ["origin.quizler.app"]`, `...RecordTypes = ["A"]`, `...Actions = ["UPSERT"]`. A compromised workflow on `main` can no longer change the apex, `www` or the ACM validation records. All three keys are multi-valued, so `ForAllValues` is the right operator. The conditions are not checked against real IAM (no `plan` or apply yet), so confirm that `reset-origin-dns.sh` still works after the first apply.
* **No `HOSTED_ZONE_ID` variable.** The deploy role gets `route53:ListHostedZonesByName` (read-only, `Resource = "*"`). The lookup moved from `start.sh` into the new `infra/scripts/_zone.sh`, sourced by `sync-origin-dns.sh` and `reset-origin-dns.sh`, so `stop.sh` and `stop.yml` get it too. `HOSTED_ZONE_ID` in the environment still overrides the lookup. Tested with a stubbed `aws`: found, not found, preset. The workflows no longer pass the variable, and only `AWS_DEPLOY_ROLE_ARN` is set by hand.
* **Action versions.** Latest releases checked with `gh`: checkout v7.0.1, configure-aws-credentials v6.3.0, amazon-ecr-login v2.1.7 (already current), setup-buildx-action v4.4.1, build-push-action v7.4.0. The major tags used (`@v7`, `@v6`, `@v2`, `@v4`, `@v7`) all exist and declare `using: node24`. These are newer than the v5 suggested in the review.
* **Docker build cache.** `deploy.yml` is split into a check step (outputs `exists`), then `docker/setup-buildx-action` and `docker/build-push-action` (both only when the image is not in ECR yet) with `cache-from: type=gha` and `cache-to: type=gha,mode=max`. `provenance: false` keeps a single plain image manifest instead of an index with attestation entries. The caching itself can only be seen on the second run.
* **Task definition shipping.** Documented in `docs/INFRA.md` (Terraform changes apply at the next deploy, fields outside the jq list are dropped, CI revisions lack the default tags). The jq filter was not extended.

### Review fix: pipefail in workflow steps
GitHub runs `run` steps with `bash -e` unless a shell is set, so a failing `aws ecs describe-task-definition` in the `aws ... | jq ... > task-definition.json` pipeline was hidden and showed up later as a confusing `register-task-definition` error. Both workflows now set `defaults.run.shell: bash` at the top level, which GitHub runs as `bash --noprofile --norc -eo pipefail`.

### Review fix: OIDC subject claim format
Found while checking that the repository can assume the role: `gh api repos/Cauac/quizler/actions/oidc/customization/sub` returns `use_immutable_subject: true` with the prefix `repo:Cauac@2319804/quizler@1406286552`. GitHub issues the immutable form (`repo:<owner>@<owner id>/<repo>@<repo id>:ref:refs/heads/main`) for repositories created after 15 July 2026, so the trust condition `repo:Cauac/quizler:ref:refs/heads/main` from the task would have rejected every run with "Not authorized to perform sts:AssumeRoleWithWebIdentity". `github.tf` now builds the condition from the owner and repository IDs (checked with `gh api repos/Cauac/quizler`). The classic form is not accepted any more, which is stricter; a rename, transfer or re-creation of the repository requires updating the IDs.

### Review fix: ECR permissions for BuildKit
First real deploy run (after the OIDC fix): role assumption, ECR login and the image-exists check passed, but `docker/build-push-action` failed at the push with `not authorized to perform: ecr:BatchGetImage`. BuildKit reads the manifest and layers it pushes, which plain `docker push` does not. `github.tf` now also allows `ecr:BatchGetImage` and `ecr:GetDownloadUrlForLayer` on the repository (needs `apply.sh`, then re-run the failed job).

### Open points
* The owner's IAM user (`quizler-terraform`) must be allowed to update ECS services, change Route 53 records and describe ENIs for `start.sh`, `stop.sh` and the sync script. Not checked.
* GitHub Actions versions are pinned by major tag, not by commit SHA.
* The IAM condition keys on the Route 53 statement are written from the documented key names and are untested against AWS; if the owner's first `stop.sh` or deploy gets `AccessDenied` on the record change, check them first.
* The ACM certificate and CloudFront distribution can take several minutes to create on the first full apply.
