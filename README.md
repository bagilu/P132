# P132 漸浸外語 — Progressive Immersion V0.1
**Foreign languages, one step at a time. / 讓外語，一點一點進入閱讀。**

First runnable baseline for Vocabulary Infiltration. GitHub Pages frontend + shared Supabase Auth + P132-only PostgreSQL/RPC objects.

## Deploy
1. Run `database/01_P132_Tables.sql`.
2. Run `02_P132_RLS.sql`, `03_P132_Functions.sql`, then `90_P132_Permissions.sql`.
3. Optionally run `04_P132_Seed_Demo.sql` to test the reader immediately.
4. Run `99_P132_HealthCheck.sql` and confirm the cross-project scan returns zero rows.
5. Copy `config-sample.js` to `config.js` locally/deployment only and fill Supabase URL/key and P130 URL. Do not commit real secrets.
6. Publish the static files on GitHub Pages.
7. Ensure the P132 GitHub Pages URL is allowed in Supabase Auth URL Configuration. Account registration/password lifecycle belongs to P130.

## What works in V0.1
Shared Auth sign-in; English/Japanese target switch; article feed; personalized low-density vocabulary replacement from pre-annotated occurrences; Translation and I Understand evidence; derived familiarity state; Japanese reading display; AlgorithmVersion on exposure.

## Deliberate V0.1 boundary
The RSS Edge Function is a safe fetch scaffold and verifies feeds against `TblP132NewsSource`; production RSS dialect parsing, article extraction, automatic vocabulary concept matching/occurrence generation, researcher/admin UI, and calibrated adaptive scoring are not silently faked in this baseline. Use the demo seed or insert normalized articles/occurrences to test the full learning loop now.

## SDS v3.1
Only P132 database objects are created/modified. No global schema grants/default privileges. `config.js` is excluded; only `config-sample.js` ships. Frontend writes learner evidence through P132 RPCs; service role belongs only in the Edge Function environment.
