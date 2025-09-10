-- Initial database schema and data
-- Migration: 001_initial_schema.sql
-- Created: 2024-01-15
-- Purpose: Set up customer portal database with sample data

\set ON_ERROR_STOP on

-- Create migration tracking table first
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    migration_id VARCHAR(50) UNIQUE NOT NULL,
    migration_name VARCHAR(200) NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_by VARCHAR(50) DEFAULT 'migration_script'
);

-- Check if migration already applied
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE migration_id = '001') THEN
        RAISE EXCEPTION 'MIGRATION_SKIP: Migration 001 already applied, skipping...';
    END IF;
    RAISE NOTICE 'Applying migration 001: Initial schema and sample data';
END
$$;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200),
    price DECIMAL(10,2),
    category VARCHAR(50),
    description TEXT
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER,
    discount DECIMAL(5,2)
);

CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_id INTEGER REFERENCES products(id),
    rating INTEGER,
    review_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com'
FROM generate_series(1, 50000) i;

INSERT INTO products (name, price, category, description)
SELECT
    'Product ' || i,
    (random() * 500 + 10)::DECIMAL(10,2),
    CASE (i % 10)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Clothing'
        WHEN 2 THEN 'Home'
        WHEN 3 THEN 'Books'
        WHEN 4 THEN 'Sports'
        WHEN 5 THEN 'Toys'
        WHEN 6 THEN 'Food'
        WHEN 7 THEN 'Beauty'
        WHEN 8 THEN 'Garden'
        ELSE 'Office'
    END,
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' ||
    'Description for product ' || i || '. ' ||
    'Features: ' || repeat('Feature ', (random() * 5)::int)
FROM generate_series(1, 10000) i;

INSERT INTO orders (user_id, order_date, status)
SELECT
    (random() * 49999 + 1)::INTEGER,
    CURRENT_TIMESTAMP - (random() * interval '730 days'),
    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        WHEN 2 THEN 'shipped'
        ELSE 'delivered'
    END
FROM generate_series(1, 500000) i;

INSERT INTO order_items (order_id, product_id, quantity, discount)
SELECT
    (random() * 499999 + 1)::INTEGER,
    (random() * 9999 + 1)::INTEGER,
    (random() * 10 + 1)::INTEGER,
    (random() * 20)::DECIMAL(5,2)
FROM generate_series(1, 2000000) i;

INSERT INTO reviews (user_id, product_id, rating, review_text)
SELECT
    (random() * 49999 + 1)::INTEGER,
    (random() * 9999 + 1)::INTEGER,
    (random() * 5 + 1)::INTEGER,
    'Review text for item. ' ||
    CASE (random() * 5)::INTEGER
        WHEN 0 THEN 'Excellent product, highly recommend!'
        WHEN 1 THEN 'Good value for money.'
        WHEN 2 THEN 'Average quality, as expected.'
        WHEN 3 THEN 'Not satisfied with this purchase.'
        WHEN 4 THEN 'Decent product with some issues.'
        ELSE 'Would buy again!'
    END
FROM generate_series(1, 300000) i;

-- Record this migration as completed
INSERT INTO schema_migrations (migration_id, migration_name) VALUES
    ('001', 'Initial schema and sample data');