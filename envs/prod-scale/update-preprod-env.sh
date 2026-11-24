set -euo pipefail

ENV_FILE=".env.preprod"

PG_HOST="${1:?PG_HOST argument is missing}"
PG_PORT="${2:?PG_PORT argument is missing}"
REDIS_HOST="${3:?REDIS_HOST argument is missing}"
REDIS_PORT="${4:?REDIS_PORT argument is missing}"

cat > "$ENV_FILE" <<EOF
ENVIRONMENT=pre-prod

DB_HOST=$PG_HOST
DB_PORT=$PG_PORT

REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
EOF

echo "Updated $ENV_FILE"
