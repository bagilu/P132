# P132 漸浸外語 — Progressive Immersion V0.1
**Foreign languages, one step at a time. / 讓外語，一點一點進入閱讀。**

First runnable baseline for Vocabulary Infiltration. GitHub Pages frontend + shared Supabase Auth + P132-only PostgreSQL/RPC objects.

## Deploy
1. Run `database/01_P132_Tables.sql`.
2. Run `02_P132_RLS.sql`, `03_P132_Functions.sql`, then `90_P132_Permissions.sql`.
3. Optionally run `04_P132_Seed_Demo.sql` to test the reader immediately.
4. Run `99_P132_HealthCheck.sql` and confirm the cross-project scan returns zero rows.
5. Copy `config-sample.js` to `config.js` locally/deployment only and fill Supabase URL/key and P130 URL.
6. Publish the static files on GitHub Pages.

## What works in V0.1
Shared Auth sign-in; English/Japanese target switch; article feed; personalized low-density vocabulary replacement; Translation and I Understand evidence; derived familiarity state; Japanese reading display; AlgorithmVersion on exposure.

## SDS v3.1
Only P132 database objects are created/modified. No global schema grants/default privileges. Frontend writes learner evidence through P132 RPCs; service role belongs only in the Edge Function environment.

## V0.1.1 UI Reading Refinement
- 翻譯／我懂改為低干擾紅／綠微型圖示。
- 翻譯使用浮動 popover，不改變文章排版。
- 「顯示原文」可切換回「顯示漸浸版」，切換本身不建立 translation evidence。
- 新增 `database/05_P132_Seed_5MoreDemoArticles.sql`，提供五篇額外示範文章與英／日詞彙。
