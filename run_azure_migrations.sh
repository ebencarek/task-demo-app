#!/bin/bash

# Run migrations on Azure PostgreSQL database
# Usage: ./run_azure_migrations.sh [fast|slow|full] [postgres_host] [db_user] [db_password] [db_name]

# Set default migration mode
MIGRATION_MODE="${1:-full}"
POSTGRES_HOST="${2}"
DB_USER="${3}"
DB_PASSWORD="${4}"
DB_NAME="${5:-customerdb}"
MIGRATIONS_DIR="./migrations"

# Validate required parameters
if [ -z "$POSTGRES_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Missing required parameters"
    echo "Usage: $0 [fast|slow|full] <postgres_host> <db_user> <db_password> [db_name]"
    echo ""
    echo "Migration modes:"
    echo "  fast - Good performance (migrations 1, 2)"
    echo "  slow - Poor performance (migrations 1, 2, 3)" 
    echo "  full - All migrations (default)"
    exit 1
fi

# Function to run a specific migration
run_migration() {
    local migration_num=$1
    local migration_file="$MIGRATIONS_DIR/$(printf "%03d" $migration_num)_*.sql"
    
    if ls $migration_file 1> /dev/null 2>&1; then
        echo "📝 Running migration $migration_num: $(basename $migration_file)..."
        local output
        output=$(PGPASSWORD=$DB_PASSWORD psql -h $POSTGRES_HOST -U $DB_USER -d $DB_NAME -f $migration_file 2>&1)
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "✅ Migration $migration_num completed successfully"
        elif echo "$output" | grep -q "MIGRATION_SKIP:"; then
            echo "⏭️  Migration $migration_num already applied, skipping..."
        else
            echo "❌ Migration $migration_num failed with exit code $exit_code"
            echo "Error output:"
            echo "$output"
            return 1
        fi
    else
        echo "❌ Migration $migration_num not found"
        return 1
    fi
}

echo "🚀 Running Azure database migrations..."
echo "   Host: $POSTGRES_HOST"
echo "   Database: $DB_NAME"
echo "   Mode: $MIGRATION_MODE"
echo ""

# Determine which migrations to run based on mode
case "$MIGRATION_MODE" in
    "fast")
        echo "🏃 Fast setup (good performance): migrations 1, 2"
        run_migration 1 && run_migration 2
        ;;
    "slow") 
        echo "🐌 Slow setup (demonstrates performance issues): migrations 1, 2, 3"
        run_migration 1 && run_migration 2 && run_migration 3
        ;;
    "full"|*)
        echo "📚 Running all migrations..."
        for migration in $MIGRATIONS_DIR/*.sql; do
            if [ -f "$migration" ]; then
                migration_num=$(basename "$migration" | cut -d'_' -f1)
                run_migration $((10#$migration_num))
                if [ $? -ne 0 ]; then
                    echo "❌ Migration sequence failed at migration $migration_num"
                    exit 1
                fi
            fi
        done
        ;;
esac

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Azure database migrations completed successfully!"
else
    echo ""
    echo "❌ Azure database migrations failed!"
    exit 1
fi