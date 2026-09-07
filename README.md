# Bite

An Expo web/mobile restaurant-decider for groups: sign in with a passwordless email link, create a timed room, swipe restaurants, use super-likes, settle ties with a first-to-three emoji game, and retain visit history for public reviews and future variety nudges.

## Free, secure stack

- **Expo + React Native** deploys to web, iOS, and Android from one codebase.
- **Supabase Free** supplies passwordless email authentication, Postgres, realtime-ready rooms, and row-level security. It is a good secure prototype tier; move to a paid plan before relying on it in production because free projects can pause.
- **Google Places API** is called only from a Supabase Edge Function. The Google Maps key never ships in the app bundle.

## Setup

1. Run `npm install`, copy `.env.example` to `.env`, and add the Supabase project URL and publishable key.
2. In the Supabase SQL Editor run `supabase/migrations/0001_family_ledger.sql`, then `supabase/migrations/0002_bite.sql`. The first migration is legacy scaffolding; the second creates Bite's data model and policies.
3. In Supabase Auth, configure email sign-in and add `bite://` plus your web deployment URL to redirect URLs. Set a production SMTP provider before launch so sign-in emails are reliable.
4. In Google Cloud, enable **Places API** and **Geocoding API**, then create a restricted API key. Deploy the search proxy: `supabase functions deploy places-search`, then set `GOOGLE_MAPS_API_KEY` as an Edge Function secret. Restrict the key to those APIs; never add it to the web app or GitHub repository.
5. Run `npm run web` for the web app, or `npm start` for Expo.

## Current product scope

The interface has a credential-free demo mode. In a real signed-in room, the swipe screen calls the server-only `places-search` function using the host-selected area and radius.

The database schema already protects room membership and only accepts each person's own swipe. Before public launch, add server-side final-result calculation (unanimous/majority), host save-visit action, review moderation, rate limiting, and abuse reporting.
