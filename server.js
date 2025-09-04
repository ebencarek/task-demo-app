const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = 3000;

const pool = new Pool({
    user: 'postgres',
    host: 'postgres-service',
    database: 'customerdb',
    password: 'postgres123',
    port: 5432,
});

app.get('/', (req, res) => {
    res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Customer Portal</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; max-width: 600px; margin: 0 auto; }
        h1 { color: #333; }
        .button { 
          background: #007bff; color: white; padding: 12px 24px; 
          border: none; border-radius: 4px; cursor: pointer; font-size: 16px;
          margin: 10px 5px;
        }
        .button:hover { background: #0056b3; }
        #loading { color: #666; font-style: italic; }
        #result { margin-top: 20px; padding: 15px; background: #f8f9fa; border-radius: 4px; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Customer Portal Dashboard</h1>
        <p>Welcome to your customer analytics portal</p>
        
        <button class="button" onclick="loadCustomerData()">View Customer Insights</button>
        <button class="button" onclick="checkHealth()">System Status</button>
        
        <div id="loading" style="display: none;">Loading customer data...</div>
        <div id="result"></div>
      </div>

      <script>
        async function loadCustomerData() {
          document.getElementById('loading').style.display = 'block';
          document.getElementById('result').innerHTML = '';
          
          const startTime = Date.now();
          
          try {
            const response = await fetch('/api/customers');
            const data = await response.json();
            const duration = Date.now() - startTime;
            
            document.getElementById('loading').style.display = 'none';
            document.getElementById('result').innerHTML = 
              '<h3>Customer Analytics Results</h3>' +
              '<p><strong>Load time:</strong> ' + duration + 'ms</p>' +
              '<p><strong>Records found:</strong> ' + data.count + '</p>' +
              '<pre>' + JSON.stringify(data.data, null, 2) + '</pre>';
              
          } catch (error) {
            document.getElementById('loading').style.display = 'none';
            document.getElementById('result').innerHTML = 
              '<p style="color: red;">Error: ' + error.message + '</p>';
          }
        }
        
        async function checkHealth() {
          try {
            const response = await fetch('/health');
            const data = await response.json();
            document.getElementById('result').innerHTML = 
              '<h3>System Status</h3>' +
              '<p>Status: ' + data.status + '</p>';
          } catch (error) {
            document.getElementById('result').innerHTML = 
              '<p style="color: red;">Health check failed: ' + error.message + '</p>';
          }
        }
      </script>
    </body>
    </html>
  `);
});

// This endpoint ALWAYS runs slow due to expensive query
app.get('/api/customers', async (req, res) => {
    console.log('Customer analytics request received...');

    try {
        // EXPENSIVE QUERY - This will always be slow (10-30+ seconds)
        const result = await pool.query(`
      SELECT 
        u.id,
        u.name,
        u.email,
        COUNT(DISTINCT o.id) as total_orders,
        SUM(oi.quantity * p.price) as lifetime_value,
        AVG(oi.quantity * p.price) as avg_order_value,
        COUNT(DISTINCT p.category) as categories_shopped,
        MAX(o.order_date) as last_purchase
      FROM users u
      LEFT JOIN orders o ON u.id = o.user_id
      LEFT JOIN order_items oi ON o.id = oi.order_id
      LEFT JOIN products p ON oi.product_id = p.id
      LEFT JOIN (
        SELECT user_id, COUNT(*) as review_count 
        FROM reviews 
        GROUP BY user_id
      ) r ON u.id = r.user_id
      LEFT JOIN (
        SELECT o2.user_id, AVG(EXTRACT(days FROM (o2.order_date - o1.order_date))) as avg_days_between_orders
        FROM orders o1, orders o2
        WHERE o1.user_id = o2.user_id AND o1.order_date < o2.order_date
        GROUP BY o2.user_id
      ) freq ON u.id = freq.user_id
      WHERE u.created_at > '2020-01-01'
      GROUP BY u.id, u.name, u.email, r.review_count, freq.avg_days_between_orders
      HAVING COUNT(o.id) > 0
      ORDER BY lifetime_value DESC, total_orders DESC
      LIMIT 20
    `);

        console.log(`Query completed, returning ${result.rows.length} rows`);

        res.json({
            message: 'Customer analytics completed',
            count: result.rows.length,
            data: result.rows
        });
    } catch (error) {
        console.error('Database error:', error.message);
        res.status(500).json({ error: error.message });
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
});