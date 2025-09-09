-- Restore performance indexes
-- Migration: 004_restore_indexes.sql
-- Created: 2024-02-05
-- Purpose: Recreate indexes after table reorganization

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);

INSERT INTO maintenance_log (action, performed_by, performed_at) VALUES 
    ('Recreated performance indexes', 'dba', CURRENT_TIMESTAMP);