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
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'customerdb',
  password: process.env.DB_PASSWORD || 'postgres123',
  port: process.env.DB_PORT || 5432,
  ssl: process.env.DB_HOST && process.env.DB_HOST.includes('azure') ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 30000,
  max: 20,
});

// This endpoint ALWAYS runs slow due to expensive query
app.get('/api/customers', async (req, res) => {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Customer analytics request received...`);

  try {
    // EXTREMELY EXPENSIVE QUERY - Guaranteed to be slow (10-60+ seconds)
    // This query is intentionally inefficient:
    // - Multiple nested subqueries
    // - Self-joins on large tables
    // - Complex aggregations without indexes
    // - CROSS JOIN in subquery creates cartesian products
    const result = await pool.query(`
      WITH customer_metrics AS (
        SELECT 
          u.id,
          u.name,
          u.email,
          COUNT(DISTINCT o.id) as total_orders,
          SUM(oi.quantity * p.price * (1 - COALESCE(oi.discount, 0) / 100)) as lifetime_value,
          AVG(oi.quantity * p.price) as avg_order_value,
          COUNT(DISTINCT p.category) as categories_shopped,
          MAX(o.order_date) as last_purchase,
          MIN(o.order_date) as first_purchase,
          STRING_AGG(DISTINCT p.category, ', ' ORDER BY p.category) as all_categories
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        LEFT JOIN order_items oi ON o.id = oi.order_id
        LEFT JOIN products p ON oi.product_id = p.id
        WHERE u.created_at > '2020-01-01'
        GROUP BY u.id, u.name, u.email
      ),
      review_metrics AS (
        SELECT 
          r.user_id,
          COUNT(*) as review_count,
          AVG(r.rating) as avg_rating,
          COUNT(DISTINCT r.product_id) as products_reviewed
        FROM reviews r
        GROUP BY r.user_id
      ),
      purchase_frequency AS (
        SELECT 
          o2.user_id,
          AVG(EXTRACT(days FROM (o2.order_date - o1.order_date))) as avg_days_between_orders,
          COUNT(DISTINCT DATE_TRUNC('month', o2.order_date)) as active_months
        FROM orders o1
        CROSS JOIN orders o2
        WHERE o1.user_id = o2.user_id 
          AND o1.order_date < o2.order_date
          AND o1.id != o2.id
        GROUP BY o2.user_id
      ),
      category_spending AS (
        SELECT 
          o.user_id,
          p.category,
          SUM(oi.quantity * p.price) as category_total
        FROM orders o
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
        GROUP BY o.user_id, p.category
      ),
      ranked_categories AS (
        SELECT 
          user_id,
          category,
          category_total,
          RANK() OVER (PARTITION BY user_id ORDER BY category_total DESC) as category_rank
        FROM category_spending
      ),
      slow_query AS (
        SELECT pg_sleep(2)
      )
      SELECT 
        cm.*,
        rm.review_count,
        rm.avg_rating,
        rm.products_reviewed,
        pf.avg_days_between_orders,
        pf.active_months,
        rc1.category as top_category,
        rc1.category_total as top_category_spend,
        rc2.category as second_category,
        rc2.category_total as second_category_spend
      FROM slow_query, customer_metrics cm
      LEFT JOIN review_metrics rm ON cm.id = rm.user_id
      LEFT JOIN purchase_frequency pf ON cm.id = pf.user_id
      LEFT JOIN ranked_categories rc1 ON cm.id = rc1.user_id AND rc1.category_rank = 1
      LEFT JOIN ranked_categories rc2 ON cm.id = rc2.user_id AND rc2.category_rank = 2
      WHERE cm.total_orders > 0
      ORDER BY cm.lifetime_value DESC NULLS LAST, cm.total_orders DESC
      LIMIT 20
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
  console.log('⚠️  Performance issue: The /api/customers endpoint has an intentionally expensive query that will cause 10-30+ second latency');
  console.log('📝 Note: Recent maintenance was performed on the database. Check maintenance_log table for details.');
});