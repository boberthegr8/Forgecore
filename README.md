# Forge Core

Canonical backend repository for the Forge construction/LBM software suite.

Forge Core is the shared data, authentication, storage, tenancy and event-history layer used by modular Forge applications including CRM, Scope, Reader, Quote/AI Quoter, Estimating, Purchasing, Operations, Manufacturing and customer/dealer portals.

## Production backend

- Supabase project: `forge-core`
- Project ref: `uyqanhwurngoupmvzxrh`
- Region: Canada Central (`ca-central-1`)
- Database: Postgres with Supabase Auth, Storage and Row Level Security
- Current proof-of-concept organization: Moulton Lumber Group
- Current proof-of-concept location: J&K Home Building Centre - Main

## Hard boundaries

Forge Core is Forge-only infrastructure. Great White Streams is unrelated and must never share Forge Core authentication, storage, database records, naming, Firebase projects, source code or infrastructure.

## Architecture rules

1. Every business record is tenant-scoped with `organization_id`.
2. Location-aware records may additionally carry `location_id`.
3. Client-facing database access is protected by Supabase Auth + RLS.
4. Shared business mutations that must be atomic use `SECURITY INVOKER` database functions unless there is a documented reason otherwise.
5. Original documents are stored in private Supabase Storage buckets; database rows reference storage paths.
6. Quote revisions and other material history are immutable records rather than destructive overwrites.
7. Imports and migrations must be idempotent and conservative.
8. Existing production customer/quote data must never be destroyed as part of an app migration.
9. Forge applications remain modular frontends; Core is the shared contract, not a giant frontend monolith.

## Repository layout

- `supabase/migrations/` — versioned database migrations
- `src/database.types.ts` — generated Supabase TypeScript contract
- `docs/` — architecture, migration ledger and integration contracts

## Current Core domains

Organizations, locations, profiles, memberships/roles, customers, contacts, projects/jobs, documents/drawings, document analysis runs, scopes and versions, takeoffs/items, quotes/revisions/items, activities, tasks, deliveries and event/history records.

## Development rule

A backend ticket is not DONE unless it results in a new migration/contract commit in this repository, or QA explicitly documents why no code/schema change was required.
