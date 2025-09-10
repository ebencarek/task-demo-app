#!/bin/bash

# Database setup using migrations
# This script replaces the old init.sql approach

DB_NAME="${DB_NAME:-customerdb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres123}"
DB_HOST="${DB_HOST:-localhost}"
MIGRATIONS_DIR="./migrations"

# Display database configuration
echo "🗄️  Database Configuration:"
echo "   Host: $DB_HOST"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo "   Password: $(echo "$DB_PASSWORD" | sed 's/./*/g')"
echo "   Migrations Directory: $MIGRATIONS_DIR"
echo "   Migration Mode: ${1:-full}"
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

# Reset database - drop and recreate
echo "Resetting database..."
PGPASSWORD=$DB_PASSWORD dropdb -f -h $DB_HOST -U $DB_USER $DB_NAME 2>/dev/null || echo "Database doesn't exist"
PGPASSWORD=$DB_PASSWORD createdb -h $DB_HOST -U $DB_USER $DB_NAME

# Determine which migrations to run based on parameters
case "${1:-full}" in
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