#!/bin/bash

# Database migration runner
# Usage: ./run_migrations.sh [migration_number]
# If no migration number is provided, runs all migrations

DB_NAME="${DB_NAME:-customerdb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres123}"

MIGRATIONS_DIR="./migrations"

if [ -z "$1" ]; then
    echo "Running all migrations..."
    for migration in $MIGRATIONS_DIR/*.sql; do
        echo "Applying $(basename $migration)..."
        PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f "$migration"
    done
else
    migration_file="$MIGRATIONS_DIR/$(printf "%03d" $1)_*.sql"
    if ls $migration_file 1> /dev/null 2>&1; then
        echo "Applying migration $1..."
        PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f $migration_file
    else
        echo "Migration $1 not found"
        exit 1
    fi
fi

echo "Migrations complete!"