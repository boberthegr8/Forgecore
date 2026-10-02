# Owner AI connection

Deploy forge-owner-ai with verify_jwt=false: the handler validates the Bearer token using auth.getUser and the private owner registry on every request. Status and generation require a verified active owner; saving additionally requires admin_unlocked (MFA). Vault access RPCs are service-role-only and recheck the owner registry. No personal key is returned to the client or used by shared AI. Configure the key once in Account & admin → My AI connection. No owner key was provisioned by this migration.

Run `node --test supabase/functions/forge-owner-ai/owner-handler.test.mjs`.
