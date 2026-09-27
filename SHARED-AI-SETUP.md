# Scope shared AI

Policy lives in private Supabase tables. Owner changes require MFA in Account & admin → AI access. Default mode is free, with 5 calls/user/day, 50/day total, 500/month total. Quotas include failed upstream attempts, prevent concurrent over-reservation, and reset in UTC. These are request limits, not dollar budgets.

Deploy `supabase/functions/forge-ai/index.ts`. The function authenticates each bearer token with `auth.getUser`; gateway legacy JWT verification is disabled to support current JWT signing keys. Only approved active workspace members can reserve a call. It accepts at most 20 MB encoded request bodies and fixes the shared model to Gemini 2.5 Flash with at most 8192 output tokens. No prompts, drawings, or keys are stored in the usage table.

Configure secrets in the Supabase Edge Functions dashboard, never in client code:

- `FORGE_FREE_GEMINI_KEY`: a NEW, separate Gemini API project with billing disabled. Do not reuse Rob's key.
- `FORGE_FREE_BILLING_DISABLED=true`: set only after checking that project's billing is disabled. The gateway cannot independently inspect Google billing; this is an operator attestation. If billing is later enabled on that project, this flag must be removed immediately. Never enable billing on the free project.
- `FORGE_BUSINESS_GEMINI_KEY`: separate future business project credential.
- `FORGE_BUSINESS_ENABLED=true`: set only when business usage is approved and its provider limits are configured.

Business mode never uses the free key, and free mode never uses the business key. Neither path reads a generic Gemini key or the owner's key. Missing configuration fails closed. Business mode remains unusable until both its secrets are set. Use provider spending/quota controls in addition to Forge request limits.

Owner personal mode sends their explicitly entered session-only key directly to Gemini 2.5 Pro. The key is not saved to localStorage or sent to Supabase. It is cleared on identity change or missing authentication. Existing origin-wide saved keys are removed when the upgraded Scope page loads. The owner must enter their key again after reloading.

Applied database changes are in `shared-ai-controls.sql` (Supabase migration history names `shared_ai_controls` and `audit_ai_policy_changes`). CLI migration generation was unavailable in this environment; do not apply this combined script again to the existing production database.

Before activating shared AI, confirm provider data-use terms are appropriate for uploaded customer drawings and test a sample drawing with the dedicated credential. Free provider capacity is limited; no unlimited free service is promised.

