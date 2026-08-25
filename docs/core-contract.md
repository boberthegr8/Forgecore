# Forge Core Integration Contract

This contract applies to every Forge module.

## Identity and tenancy

- Supabase Auth is the shared Forge identity provider.
- `organizations` are top-level tenants.
- `organization_memberships` bind authenticated users to one or more organizations with a Forge role.
- `locations` represent stores/branches within an organization.
- Every business record must include `organization_id`.
- Store-sensitive records should also include `location_id`.
- Frontends must never trust a client-supplied organization without RLS independently enforcing access.

## Current roles

`owner`, `admin`, `manager`, `sales`, `estimator`, `operations`, `viewer`.

## Core domains

### CRM
`customers`, `contacts`, `projects`, `quotes`, `quote_revisions`, `quote_items`, `activities`, `tasks`, `deliveries`.

### Documents / Reader
`documents`, `document_analysis_runs`.

### Scope / estimating
`scopes`, `scope_versions`, `takeoffs`, `takeoff_items`.

### Platform history
`events` provides cross-module event/history records.

## Storage

Private buckets:

- `forge-documents` — source drawings, quote PDFs and uploaded business documents.
- `forge-generated` — generated Forge reports/exports.

Object paths are tenant-prefixed. Current storage RLS verifies the first folder segment equals an active membership organization UUID.

Recommended path shape:

`<organization_id>/<module>/<entity_id-or-upload-id>/<filename>`

## Document contract

A file stored by Reader/CRM is represented by a `documents` row containing:

- organization/location
- optional customer/project
- document type/title
- original filename
- private bucket/path
- MIME type and byte size
- SHA-256 digest for deduplication
- status/source/metadata

Reader processing is represented separately by `document_analysis_runs`, allowing multiple analyses/retries without mutating the original document record.

## Quote contract

`quotes` is the mutable quote header/current state.

`quote_revisions` is immutable material history. A revision increment creates a new row; prior revision rows are not overwritten.

Quote PDF Intake uses `commit_quote_intake_v1` to atomically commit document/customer/project/quote/revision/activity/task/event records.

Manual CRM quote creation/revision/conversion uses:

- `create_crm_quote_v1`
- `revise_crm_quote_v1`
- `convert_crm_quote_to_project_v1`

These functions are `SECURITY INVOKER`, so caller RLS remains authoritative.

## App behavior

- CRM: Core-first reads/writes; localStorage may exist only as fallback/cache during migration.
- Reader: uploads originals to Core Storage, writes `documents`, creates analysis runs, then emits structured metadata for Scope/Quoter.
- Scope: stores canonical scope payloads in `scopes`/`scope_versions` and links them to documents/projects.
- Quoter: consumes Reader/Scope/Takeoff output and writes canonical quotes/revisions.

## Safety requirements

- Never destructive-migrate existing customer/quote history.
- Imports must be idempotent whenever stable external/legacy identifiers exist.
- Never reuse Great White Streams infrastructure, Firebase projects, auth, data, storage, naming or code paths in Forge.
- Service-role credentials must never be shipped to browser code.
- Publishable keys are allowed in clients only with RLS enabled and tested.
