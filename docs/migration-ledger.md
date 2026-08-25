# Forge Core Production Migration Ledger

Production Supabase project: `uyqanhwurngoupmvzxrh` (`forge-core`, Canada Central).

This repository was created after the initial Core database had already been built through the connected Supabase migration API. The entries below are the authoritative production migration history as of 2026-08-25.

| Version | Migration | Purpose |
|---|---|---|
| 20260825175823 | `forge_core_foundation_v1` | Initial tenant-aware Forge domain model, Auth-facing profiles/memberships, RLS, private document/generated storage buckets and base indexes. |
| 20260825180457 | `add_organization_locations` | Adds organization locations/stores and location references to operational records. |
| 20260825181307 | `add_core_foreign_key_indexes` | Adds covering indexes for Core foreign keys after performance-advisor review. |
| 20260825181543 | `atomic_quote_intake_v1` | Atomic PDF Quote Intake transaction for document/customer/project/quote/revision/activity/task/event creation. |
| 20260825181624 | `fix_atomic_quote_intake_customer_name` | Corrects customer-name handling in Quote Intake transaction. |
| 20260825182009 | `qualify_atomic_quote_intake_columns` | Fixes PL/pgSQL output/column shadowing found by authenticated QA. |
| 20260825182547 | `add_idempotent_legacy_keys` | Adds conservative uniqueness/idempotency support for legacy CRM migration sources. |
| 20260825183202 | `enable_pg_net_for_internal_jobs` | Enables internal HTTP support used during one-time controlled migration/bootstrap work. |
| 20260825185030 | `crm_direct_write_rpcs_v1` | Adds atomic CRM quote creation, manual revision and quote-to-project conversion RPCs. |
| 2026082519xxxx | `forge_reader_analysis_runs_v1` | Adds tenant-scoped document analysis run records for Forge Reader. |

## Current production data checkpoint

At the first Core-first CRM production release:

- 34 deduplicated customers
- 52 quotes
- 53 quote revision records
- 9 projects/workflows
- 3 tasks
- $2,675,834.91 quoted subtotal/value across the migrated POC dataset

The J&K deterministic backfill and cleaned ForgeWhiteAM snapshot were migrated conservatively. Browser CRM data was not deleted.

## Legacy backend retirement

The old `forge-portal` Supabase project (`zumamemyvczdmpswirjt`) was removed from CRM startup dependencies and paused after migration verification. It must not be treated as Forge Core infrastructure.

## Repository transition rule

Migrations created before this repository existed are recorded above and remain present in Supabase's production migration history. New Core schema/function/policy changes must be committed here as SQL in `supabase/migrations/` as part of the same engineering ticket that deploys them.
