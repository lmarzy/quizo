# Quizo

Supabase-backed multiplayer quiz game.

## First Milestone

Build the host/admin foundation before the live game screen:

1. Registered users can sign up and become hosts.
2. Hosts can create draft games.
3. Hosts can configure rules and choose a question pack.
4. Hosts can add members.
5. Each game receives a join code and shareable link.
6. Guest members can join without creating an account.

## Suggested Product Flow

```text
Sign up -> Dashboard -> Create game -> Configure rules -> Select pack -> Add members -> Share code -> Lobby -> Start game
```

## Supabase Setup

Install and authenticate the Supabase CLI, then link this repo to your project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The first migration creates:

- Profiles for registered hosts
- Plans and subscriptions for future monetization
- Question packs and questions
- Games and game members
- Turns, answers, and game events
- Row Level Security policies

## Access Model

Registered Supabase Auth users are hosts. Guest players do not need accounts for the MVP. Guest actions should go through server-side Edge Functions so the frontend never controls scores, turn order, answer validation, or membership permissions directly.

## Realtime Model

The app should subscribe to game-specific channels/views and receive:

- Lobby joins
- Current question changes
- Score updates
- Answer results
- Game events

Timers should be based on a shared `timer_ends_at` timestamp rather than broadcasting every second.
