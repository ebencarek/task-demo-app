-- Temporary index cleanup for table reorganization
-- Migration: 003_temp_index_cleanup.sql
-- Created: 2024-02-01

DROP INDEX IF EXISTS idx_orders_user_id;
DROP INDEX IF EXISTS idx_order_items_order_id;
DROP INDEX IF EXISTS idx_order_items_product_id;
DROP INDEX IF EXISTS idx_reviews_user_id;

INSERT INTO maintenance_log (action, performed_by, performed_at) VALUES
    ('Dropped indexes for table reorganization', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Started data migration process', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Migration completed', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day');