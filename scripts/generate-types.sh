#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="uyqanhwurngoupmvzxrh"
mkdir -p src
supabase gen types typescript --project-id "$PROJECT_REF" --schema public > src/database.types.ts

echo "Generated src/database.types.ts from Forge Core ($PROJECT_REF)."
