-- Customer Portal Database Schema with HEAVY data for real latency issues

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200),
    price DECIMAL(10,2),
    category VARCHAR(50),
    description TEXT
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20)
);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER,
    discount DECIMAL(5,2)
);

CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_id INTEGER REFERENCES products(id),
    rating INTEGER,
    review_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create LOTS of data - this is what will make queries slow
-- 50,000 users instead of 2,000
INSERT INTO users (name, email)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com'
FROM generate_series(1, 50000) i;

-- 10,000 products instead of 800
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

-- 500,000 orders instead of 8,000
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

-- 2,000,000 order items instead of 25,000
INSERT INTO order_items (order_id, product_id, quantity, discount)
SELECT
    (random() * 499999 + 1)::INTEGER,
    (random() * 9999 + 1)::INTEGER,
    (random() * 10 + 1)::INTEGER,
    (random() * 20)::DECIMAL(5,2)
FROM generate_series(1, 2000000) i;

-- 300,000 reviews instead of 12,000
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

-- SIMULATE AN ACCIDENT: Someone ran a "maintenance script" that accidentally dropped critical indexes
-- This might happen during a migration, maintenance window, or due to a faulty script
-- Comment: "Temporary cleanup for maintenance - will recreate after migration"
DROP INDEX IF EXISTS idx_orders_user_id;
DROP INDEX IF EXISTS idx_order_items_order_id;
DROP INDEX IF EXISTS idx_order_items_product_id;
DROP INDEX IF EXISTS idx_reviews_user_id;

-- This leaves the database in a broken state causing severe performance issues

-- Log recent maintenance activity
CREATE TABLE IF NOT EXISTS maintenance_log (
    id SERIAL PRIMARY KEY,
    action VARCHAR(200),
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(50)
);

INSERT INTO maintenance_log (action, performed_by, performed_at) VALUES
    ('Dropped indexes for table reorganization', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Started data migration process', 'admin', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('Migration completed', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('TODO: Recreate indexes after verification', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day');