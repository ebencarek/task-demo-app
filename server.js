const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = 3000;

const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres',  // 'postgres' for Docker, 'postgres-service' for K8s
  database: process.env.DB_NAME || 'customerdb',
  password: process.env.DB_PASSWORD || 'postgres123',
  port: process.env.DB_PORT || 5432,
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Customer Portal</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; max-width: 800px; margin: 0 auto; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .button { 
          background: #007bff; color: white; padding: 12px 24px; 
          border: none; border-radius: 4px; cursor: pointer; font-size: 16px;
          margin: 10px 5px;
        }
        .button:hover { background: #0056b3; }
        .button:disabled { opacity: 0.5; cursor: not-allowed; }
        #loading { color: #666; font-style: italic; margin-top: 20px; }
        #result { margin-top: 20px; padding: 20px; background: #f8f9fa; border-radius: 4px; border: 1px solid #dee2e6; }
        .metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
        .metric { padding: 10px; background: white; border-radius: 4px; border: 1px solid #e9ecef; }
        .metric-label { font-size: 12px; color: #6c757d; text-transform: uppercase; }
        .metric-value { font-size: 24px; font-weight: bold; color: #212529; }
        .warning { background: #fff3cd; border: 1px solid #ffc107; color: #856404; padding: 12px; border-radius: 4px; margin-top: 15px; }
        .error { color: #dc3545; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 12px; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Customer Portal Dashboard</h1>
        <p>Welcome to your customer analytics portal</p>
        
        <button class="button" onclick="loadCustomerData()">View Customer Insights</button>
        <button class="button" onclick="checkHealth()">System Status</button>
        
        <div id="loading" style="display: none;">Loading customer analytics data...</div>
        <div id="result" style="display: none;"></div>
      </div>

      <script>
        async function loadCustomerData() {
          const button = event.target;
          button.disabled = true;
          document.getElementById('loading').style.display = 'block';
          document.getElementById('result').style.display = 'none';
          
          const startTime = Date.now();
          
          try {
            const response = await fetch('/api/customers');
            const data = await response.json();
            const duration = Date.now() - startTime;
            
            document.getElementById('loading').style.display = 'none';
            document.getElementById('result').style.display = 'block';
            
            let html = '<h3>Customer Analytics Results</h3>';
            html += '<div class="metrics">';
            html += '<div class="metric"><div class="metric-label">Load time</div><div class="metric-value">' + duration + 'ms</div></div>';
            html += '<div class="metric"><div class="metric-label">Records found</div><div class="metric-value">' + (data.count || 0) + '</div></div>';
            html += '</div>';
            
            if (duration > 5000) {
              html += '<div class="warning">⚠️ <strong>Performance Warning:</strong> This query took ' + (duration/1000).toFixed(1) + ' seconds. The database query has performance issues.</div>';
            }
            
            if (data.data && data.data.length > 0) {
              html += '<h4>Customer Data Sample:</h4>';
              html += '<pre>' + JSON.stringify(data.data.slice(0, 3), null, 2) + '</pre>';
              if (data.data.length > 3) {
                html += '<p>... and ' + (data.data.length - 3) + ' more customers</p>';
              }
            }
            
            document.getElementById('result').innerHTML = html;
              
          } catch (error) {
            const duration = Date.now() - startTime;
            document.getElementById('loading').style.display = 'none';
            document.getElementById('result').style.display = 'block';
            document.getElementById('result').innerHTML = 
              '<h3>Error</h3>' +
              '<p class="error">Failed to load customer data after ' + (duration/1000).toFixed(1) + ' seconds</p>' +
              '<p class="error">Error: ' + error.message + '</p>' +
              '<div class="warning">The database query likely timed out due to performance issues.</div>';
          } finally {
            button.disabled = false;
          }
        }
        
        async function checkHealth() {
          const button = event.target;
          button.disabled = true;
          
          try {
            const response = await fetch('/health');
            const data = await response.json();
            document.getElementById('result').style.display = 'block';
            
            const statusColor = data.status === 'healthy' ? 'green' : 'red';
            let html = '<h3>System Status</h3>';
            html += '<p>Status: <strong style="color: ' + statusColor + '">' + data.status + '</strong></p>';
            
            if (data.timestamp) {
              html += '<p>Timestamp: ' + data.timestamp + '</p>';
            }
            
            if (data.error) {
              html += '<p class="error">Error: ' + data.error + '</p>';
              html += '<div class="warning">Database connection issue detected. The PostgreSQL service may be down or unreachable.</div>';
            }
            
            document.getElementById('result').innerHTML = html;
          } catch (error) {
            document.getElementById('result').style.display = 'block';
            document.getElementById('result').innerHTML = 
              '<h3>System Status</h3>' +
              '<p class="error">Health check failed: ' + error.message + '</p>';
          } finally {
            button.disabled = false;
          }
        }
      </script>
    </body>
    </html>
  `);
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
      FROM customer_metrics cm
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

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

app.listen(port, () => {
  console.log(`Customer Portal running on port ${port}`);
  console.log('⚠️  Performance issue: The /api/customers endpoint has an intentionally expensive query that will cause 10-30+ second latency');
});