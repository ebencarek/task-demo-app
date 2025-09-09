-- Add performance indexes
-- Migration: 002_add_indexes.sql
-- Created: 2024-01-20
-- Purpose: Add critical indexes for query performance

-- Create indexes initially (like a properly configured database would have)
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_reviews_user_id ON reviews(user_id);
CREATE INDEX idx_reviews_product_id ON reviews(product_id);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_products_category ON products(category);

-- Add some statistics to help PostgreSQL
ANALYZE users;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;
ANALYZE reviews;

-- Log maintenance activity
CREATE TABLE IF NOT EXISTS maintenance_log (
    id SERIAL PRIMARY KEY,
    action VARCHAR(200),
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(50)
);