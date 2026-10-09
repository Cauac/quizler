-- Quizler database schema (Aurora DSQL). Draft: covers content and results only.
-- Applied by hand in the AWS Aurora DSQL Query editor.
-- Safe to re-run: every statement is idempotent.
-- Run it in autocommit mode (no BEGIN): DSQL allows one DDL statement per transaction.
-- DSQL rules for this file: docs/TECH_CONSTRAINTS.md (Persistence).

CREATE TABLE IF NOT EXISTS game (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

--CREATE TABLE IF NOT EXISTS round (
--  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--  game_id  UUID NOT NULL REFERENCES game (id),
--  position INT NOT NULL,
--  theme    TEXT,
--  is_blitz BOOLEAN NOT NULL DEFAULT FALSE
--);
--
--CREATE TABLE IF NOT EXISTS question (
--  id             UUID PRIMARY KEY,
--  round_id       UUID NOT NULL REFERENCES round (id),
--  position       INT NOT NULL,
--  media_type     TEXT NOT NULL,
--  content        TEXT NOT NULL,
--  media_key      TEXT,
--  correct_answer TEXT NOT NULL,
--  criteria       TEXT NOT NULL
--);
--
--CREATE TABLE IF NOT EXISTS team (
--  id                UUID PRIMARY KEY,
--  game_id           UUID NOT NULL REFERENCES game (id),
--  name              TEXT NOT NULL,
--  device_token_hash TEXT NOT NULL,
--  registered_at     TIMESTAMPTZ NOT NULL
--);

--CREATE TABLE IF NOT EXISTS submission (
--  id           UUID PRIMARY KEY,
--  round_id     UUID NOT NULL REFERENCES round (id),
--  team_id      UUID NOT NULL REFERENCES team (id),
--  submitted_at TIMESTAMPTZ NOT NULL
--);

--CREATE TABLE IF NOT EXISTS answer (
--  id            UUID PRIMARY KEY,
--  submission_id UUID NOT NULL REFERENCES submission (id),
--  question_id   UUID NOT NULL REFERENCES question (id),
--  text          TEXT NOT NULL,
--  plus          BOOLEAN NOT NULL,
--  verdict       TEXT NOT NULL,
--  host_override TEXT
--);
