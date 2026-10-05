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
* Database: Aurora Serverless v2, PostgreSQL compatible.

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
