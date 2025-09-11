const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3001;

// Enable CORS for all routes
app.use(cors());
app.use(express.json());

// Use environment variables for all config - works for both Docker and Container Apps
const pool = new Pool({
  connectionString: process.env.DB_CONNECTION_STRING || 'postgres://customerdb:postgres123@localhost:5432/customerdb',
  ssl: { rejectUnauthorized: false },
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 30000,
  max: 20,
});

// This endpoint ALWAYS runs slow due to expensive query
app.get('/api/customers', async (req, res) => {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Customer analytics request received...`);

  try {
    // Test query designed to be very sensitive to missing indexes
    const result = await pool.query(`
      SELECT
        o.id,
        u.name,
        u.email,
        o.order_date,
        oi.quantity,
        p.name as product_name,
        p.price
      FROM orders o
      JOIN users u ON o.user_id = u.id
      JOIN order_items oi ON o.id = oi.order_id
      JOIN products p ON oi.product_id = p.id
      WHERE u.email LIKE '%example.com'
        AND p.category IN ('Electronics', 'Clothing', 'Books')
      ORDER BY o.order_date DESC, p.price DESC
      LIMIT 50
    `);

    const duration = Date.now() - startTime;
    console.log(`[${new Date().toISOString()}] Query completed in ${duration}ms, returning ${result.rows.length} rows`);

    res.json({
      message: 'Customer analytics completed',
      count: result.rows.length,
      data: result.rows,
      query_time: `${duration}ms`
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    console.error(`[${new Date().toISOString()}] Database error after ${duration}ms:`, error.message);
    res.status(500).json({
      error: 'Database query failed - likely due to timeout or excessive resource usage',
      message: error.message,
      query_time: `${duration}ms`
    });
  }
});

// Database initialization endpoint
app.post('/api/init-db', async (req, res) => {
  console.log('Database initialization requested...');
  try {
    // Check if tables already exist
    const tableCheck = await pool.query(`
      SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('users', 'products', 'orders', 'order_items', 'reviews')
    `);

    if (parseInt(tableCheck.rows[0].count) === 5) {
      return res.json({
        message: 'Database already initialized',
        tables: 5,
        status: 'already_exists'
      });
    }

    console.log('Creating database tables...');

    // Create tables
    await pool.query(`
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

      -- Create indexes for query performance
      CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
      CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
      CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date);
      CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
      CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);
      CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
      CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
    `);

    console.log('Inserting test data - this may take several minutes...');

    // Insert sample data (smaller dataset for faster initialization)
    await pool.query(`
      INSERT INTO users (name, email)
      SELECT
        'Customer ' || i,
        'customer' || i || '@example.com'
      FROM generate_series(1, 1000) i;
    `);

    await pool.query(`
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
        'Description for product ' || i
      FROM generate_series(1, 1000) i;
    `);

    await pool.query(`
      INSERT INTO orders (user_id, order_date, status)
      SELECT
        (random() * 999 + 1)::INTEGER,
        CURRENT_TIMESTAMP - (random() * interval '365 days'),
        CASE (random() * 3)::INTEGER
          WHEN 0 THEN 'pending'
          WHEN 1 THEN 'completed'
          WHEN 2 THEN 'shipped'
          ELSE 'delivered'
        END
      FROM generate_series(1, 5000) i;
    `);

    await pool.query(`
      INSERT INTO order_items (order_id, product_id, quantity, discount)
      SELECT
        (random() * 4999 + 1)::INTEGER,
        (random() * 999 + 1)::INTEGER,
        (random() * 10 + 1)::INTEGER,
        (random() * 20)::DECIMAL(5,2)
      FROM generate_series(1, 10000) i;
    `);

    await pool.query(`
      INSERT INTO reviews (user_id, product_id, rating, review_text)
      SELECT
        (random() * 999 + 1)::INTEGER,
        (random() * 999 + 1)::INTEGER,
        (random() * 5 + 1)::INTEGER,
        'Review text for product ' || i
      FROM generate_series(1, 2000) i;
    `);

    console.log('Database initialization completed successfully!');

    res.json({
      message: 'Database initialized successfully',
      tables_created: 5,
      sample_data: {
        users: 1000,
        products: 1000,
        orders: 5000,
        order_items: 10000,
        reviews: 2000
      },
      status: 'success'
    });

  } catch (error) {
    console.error('Database initialization failed:', error.message);
    res.status(500).json({
      error: 'Database initialization failed',
      message: error.message,
      status: 'error'
    });
  }
});

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

app.listen(port, () => {
  console.log(`Customer Portal Backend API running on port ${port}`);
  //console.log('⚠️  Performance issue: The /api/customers endpoint has an intentionally expensive query that will cause 10-30+ second latency');
  //console.log('📝 Note: Recent maintenance was performed on the database. Check maintenance_log table for details.');
});