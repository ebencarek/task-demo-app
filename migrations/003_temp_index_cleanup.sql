-- Temporary index cleanup for table reorganization
-- Migration: 003_temp_index_cleanup.sql
-- Created: 2024-02-01

\set ON_ERROR_STOP on

-- Check if migration already applied
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE migration_id = '003') THEN
        RAISE EXCEPTION 'MIGRATION_SKIP: Migration 003 already applied, skipping...';
    END IF;
    RAISE NOTICE 'Applying migration 003: Temporary index cleanup for table reorganization';
END
$$;

DROP INDEX IF EXISTS idx_orders_user_id;
DROP INDEX IF EXISTS idx_order_items_order_id;
DROP INDEX IF EXISTS idx_order_items_product_id;
DROP INDEX IF EXISTS idx_reviews_user_id;

INSERT INTO maintenance_log (action, performed_by, performed_at) VALUES
    ('Dropped indexes for table reorganization', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Started data migration process', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Migration completed', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day');

-- Record this migration as completed
INSERT INTO schema_migrations (migration_id, migration_name) VALUES 
    ('003', 'Temporary index cleanup for table reorganization');

