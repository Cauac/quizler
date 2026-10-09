# Technical Constraints

Technical constraints for Quizler. Game rules and behavior are in [CONCEPT.md](CONCEPT.md).
This document lists only decisions that have been made, plus open questions that still need an answer.

## Decided

### Backend (game server)
* Language: Clojure.
* Runtime: JVM application.
* Build system: Clojure deps (`deps.edn`).
* Deployment: runs in a container on AWS ECS with Fargate, region `eu-north-1`.

### Persistence
* Database: Amazon Aurora DSQL (serverless, PostgreSQL compatible). It scales to zero with no cost for compute when idle and no wake-up delay, which suits one game night a week.
* The cluster runs in `eu-north-1`, next to the server.
* The server and the owner's laptop both use the cluster's public endpoint (TLS, IAM auth). There is no PrivateLink VPC endpoint. ECS tasks need outbound internet access (a public IP or NAT) to reach it.
* Access is by IAM only; there are no database passwords.
  * The app connects as a custom database role (not `admin`) mapped to the ECS task role with `AWS IAM GRANT`. The task role needs `dsql:DbConnect` on the cluster.
  * The connection pool must generate a fresh auth token for every new connection. Connections are closed by the server after 60 minutes, so the pool's max lifetime must be shorter (about 50 minutes).
  * The owner connects from a laptop over the cluster's public endpoint with an `admin` token (`dsql:DbConnectAdmin`). No VPC access is needed.
* Isolation is fixed at Repeatable Read with optimistic concurrency control. Conflicting commits fail with a serialization error, so every write transaction must be idempotent and retried.
  * Write skew is possible. The round-end lock on answer submission must force a conflict between a submission and the host ending the round, for example by having submissions lock or write the round row (`SELECT ... FOR UPDATE`).
  * Keep rows that many requests write to as few as possible. Use UUID primary keys.
* DSQL limits that shape the code:
  * No triggers, PL/pgSQL, extensions, temporary tables or `TRUNCATE`. Logic lives in the Clojure server.
  * One transaction mutates at most 3,000 rows or 10 MiB, and runs at most 5 minutes. DDL and DML must be in separate transactions, with one DDL statement per transaction. Indexes are created with `CREATE INDEX ASYNC`.
  * Collation is `C` only. Do not rely on case-insensitive comparison in the database.
  * Do not use `LISTEN/NOTIFY` for pushing updates. Real-time updates go through the server over SSE.
  * No advisory locks (`pg_advisory_lock`) and no `serial` columns. Foreign keys are supported and enforced.
  * `ALTER TABLE ... ADD COLUMN` accepts no constraints, so `NOT NULL DEFAULT` is rejected. Add the column plain and backfill separately.
  * A DDL statement can fail with `OC001` ("schema has been updated by another transaction") while an async index job is running. Create tables before indexes and retry.
* Schema changes: no migration tool. The schema is `db/schema.sql`, applied by hand in the AWS web console as `admin`, one statement per transaction. Every statement is idempotent, so the file can be re-run. Changes that are not idempotent (dropping or retyping a column, backfills) are run by hand and then reflected in the file.
* Server connection: `software.amazon.dsql/aurora-dsql-jdbc-connector` (`jdbc:aws-dsql:postgresql://<endpoint>/postgres?user=<role>`) behind HikariCP and `next.jdbc` creates a fresh IAM token per connection. For local runs, the Java SDK does not read `aws login` profiles unless `software.amazon.awssdk/signin` is on the classpath; alternatively export credentials with `aws configure export-credentials --format env`.

### Frontend
* Four apps: admin page, host control panel, big screen and captain webapp.
* Each app is a separate codebase.
* Stack for every app: pnpm, TypeScript, Tailwind CSS, Preact.
* The frontend apps are served by the game server. There is no separate frontend hosting.

### Real-time updates
* The server pushes updates to clients with Server-Sent Events (SSE).

### LLM grading
* Provider: AWS Bedrock.
* The model is not chosen yet. It will be picked later, based on how well it does the grading task.

### Media storage
* All media files (images, audio, etc.) are stored on AWS S3.
* Clients load media directly from S3 through presigned URLs. It is not proxied through the game server.

### Infrastructure and delivery
* Infrastructure as code: Terraform.
* CI/CD: GitHub Actions.

### Source repository
* The GitHub repository is public. The source code is open to read; this is intentional.
* Only the owner can push. Outside contributions are not accepted, so PRs from others are closed unaccepted.
* Secrets are never committed. They are supplied to the server at runtime (for example from AWS Secrets Manager) and to CI through GitHub Actions secrets.
* `.gitignore` excludes IDE files, local env files (`.env*`) and build output.
* Repository settings to keep enabled: secret scanning with push protection, branch protection on `main` (no force-push, no deletion), and approval required before workflows run for outside collaborators' fork PRs.

## Open questions

Not decided yet. Do not assume answers until they are recorded here.

* What lives in the database versus in server memory, and whether live game state must survive a server restart. The platform runs one event at a time.
* Number of server tasks. SSE connections and the single live game suggest one task, but this is not decided.
* Bedrock model for answer grading, and how a failed check becomes a "pending" answer.
* Access token issuance and storage for hosts and content creators.
