## Overview

Quizler is a platform for running in-person, team-based trivia nights.

The main game objective is to score the highest total points 
by delivering correct answers to varied questions within strict time limits.

The platform runs a single event at a time.

## The Game Rules

### Game Structure & Mechanics

Team Size: Typically played in teams of 2 to 10 players.

Total Duration: 4-7 rounds, consisting of 7 questions per round (up to 49 total questions).

Answering Format: Teams discuss questions silently and submit digital answer sheets at the end of each round.

Using internet search and external references is strictly forbidden.

### Standard Round Workflow

The platform announces each question sequentially on the big screen.

Teams get 100 seconds per question to discuss and record an answer.
The timer is a guide only: it does not lock answers and does not advance the game.

After question 7, all 7 questions are shown back rapidly without extra pause (recap).

Teams get 60 seconds to finalize and submit their answer sheet. Late submissions are not possible and result in a zero score for that round.

Each correct answer earns 1 point. There are no penalties for incorrect answers or blank responses.

### (Optional) Blitz Round Mechanics

A round can be marked as a blitz round (typically the 7th round). It introduces a high-risk, fast-paced mechanic designed to shift leaderboard rankings:

* Questions are read back-to-back with only 15–20 seconds per question.

* No Recap. Questions are read once only. There is no recap at the end.

* The answer sheet is submitted the same way as in other rounds, including the 60-second window at the end of the round.

* Point Gambling System. Each answer can optionally be marked with a plus sign (+). A team may mark any number of answers, including all 7.

    - A correct answer marked with a plus sign (+) earns 2 points.

    - An incorrect answer marked with a plus sign (+) results in a penalty of -2 points.

    - A correct answer without a plus sign earns the standard 1 point.

    - An incorrect answer without a plus sign incurs 0 points.

    - A blank response incurs 0 points, with or without a plus sign.

### Winning Condition

After all rounds, all points from all rounds are tallied. The team with the highest aggregate score wins.

Teams with equal scores share the same place in the scoring table. There is no tie-breaker.

### Question Categories & Media Types

Rounds rotate through distinct formats to test different skill sets.
The media type is configured per question. Round themes are nominal and do not impose technical limits on the questions in them.

* Text / General Knowledge: Traditional factual trivia covering history, science, geography, literature, and pop culture.

* Visual: Questions based on cropped images, modified logos, obscure photographs, or visual puzzles displayed on screen.

* Audio / Music: Excerpts of songs, movie dialogue, soundtrack snippets, or reversed audio tracks played over the sound system.

* Themed / Logic: Mechanics like matching, fill-in-the-blank text chains, or deduction puzzles where answers fit a specific overarching theme.

## Playing the game via Quizler platform

### Requirements

* A big room to physically fit all people that want to play the game.
* At least one big screen with a sound system.
* Each team needs an electronic device with a web browser (smartphone, laptop, tablet).

### Roles

* The big screen shows questions, media, progress and scores. Questions and media are shown on the big screen only.
* Each team's captain is the only person using a phone, and submits answers. The captain's device is used only to submit answers and does not show the questions.
* The game host controls the game flow and resolves appeals.
* Content creators prepare the game content in an admin page ahead of time.

### Access

* Hosts and content creators sign in with access tokens.
* Teams have no accounts. A captain registers the team using the registration link and a team name.
* A team is bound to the device it registered on. Switching to another device is not possible.
* Registration closes when the game starts. Teams cannot join a game in progress.

### The game flow

* Creators upload content and settings.
* The host activates the game and shows a registration link on the big screen.
* Captains register their teams.
* During play, captains see a 7-field form per round, the platform auto-grades with tolerance for typos and alternative answers.
* The host shows the correct answers at the end of each round.
* Teams can appeal, and the host can manually accept or reject answers.
* The leaderboard shows between rounds and at the end.

### Game content

Content creators define the number of rounds, mark blitz rounds and set other game settings.

For each question the content creator provides:
* The question content and its media type (text, image, audio, etc.).
* The correct answer shown on the big screen at the end of the round.
* Matching criteria used to check team answers, written in plain language. For example: "accept dog, labrador, labrador retriever".

### Game progress and navigation

The host advances the game manually through every step: each question, the recap, the submission window, the answers reveal and the scoring table.
There are no automatic state transitions.

The host can navigate back and forward:

* Soft back (default) - only changes what the big screen shows, for example to show a previous question again.
  If the target is a question, its timer restarts.
  The game state is not changed: closed rounds stay locked, submissions and scores are kept.
* Hard restart from here - a separate action that requires confirmation.
  It resets the game to the start of the chosen question or round.
  Everything after that point is discarded for all teams.
  If a round is reopened, its submissions are deleted and captains fill the round in again, with their locally saved drafts restored.

### Answer sheet

For each round the captain's app shows a form with 7 answer fields. In a blitz round each field also has a "+" toggle.

* The form is available from the start of the round and during the whole round.
* Answers are saved as drafts locally on the device, so it is safe to reload the page during the round.
* The "Submit" button appears only after all questions of the round have been shown.
* The team must press "Submit" before the round ends. After submission it is not possible to re-send or correct the answers.
* When the round ends, submission is locked on the server. Answers that were not submitted are not accepted.

### Checking answers and appeals

* The platform checks each answer sheet as soon as it is submitted.
* An LLM compares each answer against the matching criteria of the question. This lets the system accept alternative answers and tolerate simple typos.
* If the automatic check fails for an answer, the answer is marked as "pending" and must be resolved by the host.
* If a team believes that some of their answers were not counted right they appeal to the host verbally.
* The host finds the specific answer in the control panel and overrides the system decision by accepting or rejecting it.
* Each override applies to a single answer only. It is not applied automatically to identical answers from other teams.

## Scope of the first version

The first version covers the core flow only:
* Admin page for content creators.
* Game control panel for the host.
* Big screen presentation.
* Captain webapp for team registration and answer submission.

Technical constraints will be defined separately.
