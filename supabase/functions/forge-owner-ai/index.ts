import { createClient } from 'npm:@supabase/supabase-js@2.112.4';
import { createHandler } from './owner-handler.mjs';
// Authenticate every request against Supabase Auth and the private owner registry.
Deno.serve(createHandler({createClient,env:(name:string)=>Deno.env.get(name)}));

