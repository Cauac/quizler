# Quizler

Platform for running in-person, team-based trivia nights: a host, a big screen, and team captains answering from their devices.

The product concept and game rules are in @docs/CONCEPT.md. Read it before designing or changing any behavior, and keep it up to date when decisions change.

## Key points
- One event at a time. Four surfaces: admin page (content creators), host control panel, big screen, captain webapp.
- The host advances the game manually. There are no automatic state transitions or timer-driven locks, except the server-side lock on answer submission when a round ends.
- Answers are graded by an LLM against per-question criteria written by content creators. Host overrides (accept/reject) apply to a single answer only.
- Teams have no accounts. They are bound to one device. Hosts and creators use access tokens.
- Version 1 covers the core flow only.

## Docs
- `docs/CONCEPT.md` is the source of truth for game rules and platform behavior.
- `docs/TECH_CONSTRAINTS.md` lists the decided technical constraints and the open questions. Backend: Clojure on the JVM, in a container on AWS. Frontends: TypeScript, served by the server. Do not assume anything listed as open there.

## Working agreements
- If the concept is ambiguous or a change conflicts with it, ask before implementing.
- Put new design documents in `docs/` and link them from this file.
