#!/usr/bin/env bash
# Stage 06 — seed/reset the SUPER_ADMIN login in auth_db. Idempotent.
# Uses only the SUPER_ADMIN scope, which is valid in every deployed admin model
# (the 2-scope enum on release-1.0.0 AND older varchar builds). See RUNBOOK §12 for
# the model gotcha (the repo's 4-scope insert-admin.sql does NOT work on prod).
# Override the PIN:  ADMIN_PIN=xxxxxx ./06-seed-admin.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
CTX="$PROD_CONTEXT"
echo "=== [06] Seed admin ($ADMIN_PHONE) ==="
PG_HOST=$(doctl databases connection "$PROD_PG_ID" --no-header --format Host)
APW=$(doctl databases user get "$PROD_PG_ID" yescare_app --no-header --format Password)
POD="psql-admin-$$"
kubectl --context "$CTX" -n "$PROD_NS" run "$POD" --image=postgres:16 --restart=Never -- sleep 120 >/dev/null
kubectl --context "$CTX" -n "$PROD_NS" wait --for=condition=ready pod/"$POD" --timeout=120s >/dev/null
kubectl --context "$CTX" -n "$PROD_NS" exec -i "$POD" -- \
  env PGPASSWORD="$APW" psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=yescare_app" \
  -v ON_ERROR_STOP=1 -v phone="$ADMIN_PHONE" -v pin="$ADMIN_PIN" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
WITH up AS (
  INSERT INTO users (phone_number, status, user_type, admin_scope)
  VALUES (:'phone', 'ACTIVE'::user_status_enum, 'ADMIN'::user_type_enum, 'SUPER_ADMIN')
  ON CONFLICT (phone_number)
    DO UPDATE SET status='ACTIVE'::user_status_enum, user_type='ADMIN'::user_type_enum
  RETURNING id
)
INSERT INTO user_credentials (user_id, pin_hash, failed_attempts)
SELECT id, crypt(:'pin', gen_salt('bf',10)), 0 FROM up
ON CONFLICT (user_id)
  DO UPDATE SET pin_hash=crypt(:'pin', gen_salt('bf',10)), failed_attempts=0, locked_until=NULL;
SELECT phone_number, admin_scope, status,
       (c.pin_hash = crypt(:'pin', c.pin_hash)) AS pin_ok
FROM users u JOIN user_credentials c ON c.user_id=u.id WHERE phone_number=:'phone';
SQL
kubectl --context "$CTX" -n "$PROD_NS" delete pod "$POD" >/dev/null 2>&1 || true
echo "[06] admin ready: phone=$ADMIN_PHONE (login: POST /bff/api/v1/auth/login/admin)"
