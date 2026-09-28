# P132 Foreign Linguistic Analyzer V0.1

Supabase Edge Function name: `P132-analyze-foreign`.

## Purpose

Implements the SQL17E analyzer contract. It reads an already-ingested foreign article, creates a versioned analysis run, writes linguistic tokens and term candidates, then calls `P132_MaterializeForeignAnalysis`.

V0.1 supports English only. Japanese intentionally returns `deferred` until a Japanese morphological analyzer is connected.

## Required secrets

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `P132_INGEST_SECRET`

Deploy with JWT verification disabled because this back-office endpoint uses `x-p132-ingest-secret`, matching the P132 RSS ingestion pattern.

## Request

POST JSON:

```json
{"article_id":107}
```

Header:

`x-p132-ingest-secret: <P132_INGEST_SECRET>`

## V0.1 limitations

The English analyzer is deliberately lightweight. It establishes the production architecture and regression path, not final NLP quality. Its output is versioned and replaceable without deleting learner Exposure/Evidence.
