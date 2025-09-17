#!/bin/bash

# Database setup using migrations
# This script replaces the old init.sql approach
#
# Usage:
#   Local (env vars or defaults):
#     ./setup_db_migrations.sh [fast|slow|full]
#
#   Azure (derive connection info from deployed Azure resources – WILL DROP DB):
#     ./setup_db_migrations.sh azure <custom-suffix> [fast|slow|full] [db_password]
#
#   Where <custom-suffix> is the same suffix used when running
#     deploy-container-apps.sh (without internal hyphen stripping needed; hyphens will be removed automatically).
#   If migration mode omitted it defaults to 'full' for azure path; password optional (falls back to DemoPassword123!).
#
# WARNING: This script now ALWAYS drops and recreates the target database (both local and Azure).
#          Ensure you do NOT run against a production database.

set -euo pipefail

# Defaults for local/dev

DB_NAME="${DB_NAME:-customerdb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres123}"
DB_HOST="${DB_HOST:-localhost}"
MIGRATIONS_DIR="./migrations"

# Migration mode (fast|slow|full)
MIGRATION_MODE="fast"

if [ "${1:-}" = "azure" ]; then
    if ! command -v az >/dev/null 2>&1; then
        echo "❌ Azure mode requested but 'az' CLI not found in PATH" >&2
        exit 1
    fi
    AZURE_SUFFIX_RAW="${2:-}" || true
    if [ -z "$AZURE_SUFFIX_RAW" ]; then
        echo "❌ Azure mode requires a <custom-suffix> argument" >&2
        echo "Usage: $0 azure <custom-suffix> [fast|slow|full] [db_password]" >&2
        exit 1
    fi
    # Normalize suffix (remove hyphens as done in deploy script)
    AZURE_SUFFIX="${AZURE_SUFFIX_RAW//[-]/}"

    # Optional migration mode and password
    MAYBE_MODE="${3:-}"
    if [[ "$MAYBE_MODE" =~ ^(fast|slow|full)$ ]]; then
        MIGRATION_MODE="$MAYBE_MODE"
        DB_PASSWORD_OVERRIDE="${4:-}"
    else
        DB_PASSWORD_OVERRIDE="${3:-}"
    fi

    # Derived resource names must mirror deploy-container-apps.sh logic
    RESOURCE_GROUP="rg-demo-app-${AZURE_SUFFIX}"
    POSTGRES_SERVER="psql-demo-${AZURE_SUFFIX}"
    DB_USER="demoadmin"              # matches deploy script
    DB_PASSWORD="${DB_PASSWORD_OVERRIDE:-DemoPassword123!}"  # same default as deploy script
    DB_NAME="customerdb"

    echo "🔎 Resolving Azure PostgreSQL fully qualified domain name..."
    if ! POSTGRES_HOST=$(az postgres flexible-server show --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_SERVER" --query fullyQualifiedDomainName -o tsv 2>/dev/null); then
        echo "❌ Failed to fetch server info for $POSTGRES_SERVER in $RESOURCE_GROUP" >&2
        exit 1
    fi
    DB_HOST="$POSTGRES_HOST"
else
    # Non-azure path: first arg may be migration mode
    if [[ "${1:-}" =~ ^(fast|slow|full)$ ]]; then
        MIGRATION_MODE="$1"
    fi
fi

# Display database configuration
echo "🗄️  Database Configuration:"
echo "   Host: $DB_HOST"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo "   Password: $(echo "$DB_PASSWORD" | sed 's/./*/g')"
echo "   Migrations Directory: $MIGRATIONS_DIR"
echo "   Mode: $MIGRATION_MODE"
if [ "${1:-}" = "azure" ]; then
    echo "   Source: Azure (resource group derived: rg-demo-app-${AZURE_SUFFIX})"
else
    echo "   Source: Local/Env"
fi
echo ""

# Function to run a specific migration
run_migration() {
    local migration_num=$1
    local migration_file="$MIGRATIONS_DIR/$(printf "%03d" $migration_num)_*.sql"

    if ls $migration_file 1> /dev/null 2>&1; then
        echo "📝 Running migration $migration_num: $(basename $migration_file)..."
        PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f $migration_file
        return $?
    else
        echo "Migration $migration_num not found"
        return 1
    fi
}

# Reset database (ALWAYS). For remote Azure server, terminate active sessions first.
echo "🔄 Resetting database '$DB_NAME'..."
if [ "${1:-}" = "azure" ]; then
    echo "   Azure mode detected: attempting to terminate existing connections before drop."
    # Try terminating sessions (ignore errors to keep flow)
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d postgres -v ON_ERROR_STOP=0 -c \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
fi
PGPASSWORD=$DB_PASSWORD dropdb -f -h $DB_HOST -U $DB_USER $DB_NAME 2>/dev/null || echo "   (Database did not exist)"
PGPASSWORD=$DB_PASSWORD createdb -h $DB_HOST -U $DB_USER $DB_NAME
echo "   Database recreated."

# Determine which migrations to run based on parameters
case "$MIGRATION_MODE" in
    "fast")
        echo "Setting up database with good performance (migrations 1, 2)..."
        run_migration 1 && run_migration 2
        ;;
    "slow")
        echo "Setting up database with poor performance (migrations 1, 2, 3)..."
        run_migration 1 && run_migration 2 && run_migration 3
        ;;
    "full"|*)
        echo "Running all migrations..."
        for migration in $MIGRATIONS_DIR/*.sql; do
            migration_num=$(basename "$migration" | cut -d'_' -f1)
            run_migration $((10#$migration_num))
        done
        ;;
esac

echo "Database setup complete!"