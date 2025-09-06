import React, { useState, useEffect } from 'react';
import './App.css';

const API_URL = 'https://backend-api-vnet.jollybay-a0c6cabe.australiaeast.azurecontainerapps.io';

function App() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [healthStatus, setHealthStatus] = useState(null);
  const [lastUpdateTime, setLastUpdateTime] = useState(new Date());

  // Auto-refresh health status every 30 seconds
  useEffect(() => {
    const checkHealthStatus = async () => {
      try {
        const response = await fetch(`${API_URL}/health`);
        const data = await response.json();
        setHealthStatus(data);
      } catch (error) {
        setHealthStatus({ status: 'unhealthy', error: error.message });
      }
    };

    checkHealthStatus();
    const interval = setInterval(checkHealthStatus, 30000);
    return () => clearInterval(interval);
  }, []);

  const loadCustomerData = async () => {
    setLoading(true);
    setResult(null);
    setLastUpdateTime(new Date());
    
    const startTime = Date.now();
    
    try {
      const response = await fetch(`${API_URL}/api/customers`);
      const data = await response.json();
      const duration = Date.now() - startTime;
      
      setResult({
        type: 'success',
        data,
        duration
      });
    } catch (error) {
      const duration = Date.now() - startTime;
      setResult({
        type: 'error',
        error: error.message,
        duration
      });
    } finally {
      setLoading(false);
    }
  };

  const refreshDashboard = async () => {
    setLoading(true);
    setLastUpdateTime(new Date());
    
    try {
      const response = await fetch(`${API_URL}/health`);
      const data = await response.json();
      setHealthStatus(data);
    } catch (error) {
      setHealthStatus({ status: 'unhealthy', error: error.message });
    } finally {
      setLoading(false);
    }
  };

  const getPerformanceBadge = (duration) => {
    if (duration < 1000) return 'performance-fast';
    if (duration < 5000) return 'performance-medium';
    return 'performance-slow';
  };

  const getPerformanceText = (duration) => {
    if (duration < 1000) return 'FAST';
    if (duration < 5000) return 'MEDIUM';
    return 'SLOW';
  };

  return (
    <div className="app">
      <div className="dashboard">
        {/* Header */}
        <div className="header">
          <h1>Customer Analytics Dashboard</h1>
          <p className="subtitle">Real-time insights and performance monitoring</p>
        </div>

        {/* Controls */}
        <div className="controls">
          <button 
            className="button primary" 
            onClick={loadCustomerData} 
            disabled={loading}
          >
            📊 Analyze Customer Data
          </button>
          <button 
            className="button secondary" 
            onClick={refreshDashboard} 
            disabled={loading}
          >
            🔄 Refresh Dashboard
          </button>
        </div>

        {loading && (
          <div className="loading">
            Processing your request...
          </div>
        )}

        {/* Dashboard Grid */}
        <div className="dashboard-grid">
          {/* System Status Card */}
          <div className="card">
            <h3>
              <div className="card-icon">🛡️</div>
              System Health
            </h3>
            {healthStatus && (
              <>
                <div className="metrics-grid">
                  <div className="metric">
                    <div className="metric-value">
                      <span 
                        className={`status-indicator ${
                          healthStatus.status === 'healthy' ? 'status-healthy' : 'status-unhealthy'
                        }`}
                      ></span>
                      {healthStatus.status === 'healthy' ? 'ONLINE' : 'OFFLINE'}
                    </div>
                    <div className="metric-label">API Status</div>
                  </div>
                  <div className="metric">
                    <div className="metric-value">
                      {healthStatus.timestamp ? 
                        new Date(healthStatus.timestamp).toLocaleTimeString() : 
                        'N/A'
                      }
                    </div>
                    <div className="metric-label">Last Check</div>
                  </div>
                </div>
                {healthStatus.error && (
                  <div className="warning">
                    ⚠️ Database connection issue: {healthStatus.error}
                  </div>
                )}
              </>
            )}
          </div>

          {/* Performance Overview Card */}
          {result && result.type === 'success' && (
            <div className="card">
              <h3>
                <div className="card-icon">⚡</div>
                Performance Metrics
              </h3>
              <div className="metrics-grid">
                <div className="metric">
                  <div className="metric-value">{result.duration}ms</div>
                  <div className="metric-label">Query Time</div>
                </div>
                <div className="metric">
                  <div className="metric-value">{result.data.count || 0}</div>
                  <div className="metric-label">Records Found</div>
                </div>
                <div className="metric">
                  <div className="metric-value">
                    <span className={`performance-badge ${getPerformanceBadge(result.duration)}`}>
                      {getPerformanceText(result.duration)}
                    </span>
                  </div>
                  <div className="metric-label">Performance</div>
                </div>
                <div className="metric">
                  <div className="metric-value">
                    {lastUpdateTime.toLocaleTimeString()}
                  </div>
                  <div className="metric-label">Last Updated</div>
                </div>
              </div>
              
              {result.duration > 5000 && (
                <div className="warning">
                  ⚠️ <strong>Performance Alert:</strong> Query took {(result.duration/1000).toFixed(1)}s. 
                  Database optimization needed.
                </div>
              )}
            </div>
          )}

          {/* Customer Insights Card */}
          {result && result.type === 'success' && result.data.data && result.data.data.length > 0 && (
            <div className="card">
              <h3>
                <div className="card-icon">👥</div>
                Top Customer Insights
              </h3>
              <div className="data-preview">
                <h4>Sample Customer Analytics</h4>
                <pre>{JSON.stringify(result.data.data.slice(0, 2), null, 2)}</pre>
                {result.data.data.length > 2 && (
                  <p className="success">
                    ✓ Showing 2 of {result.data.data.length} customer records
                  </p>
                )}
              </div>
            </div>
          )}

          {/* Error Display Card */}
          {result && result.type === 'error' && (
            <div className="card">
              <h3>
                <div className="card-icon">❌</div>
                System Alert
              </h3>
              <div className="metrics-grid">
                <div className="metric">
                  <div className="metric-value error">ERROR</div>
                  <div className="metric-label">Status</div>
                </div>
                <div className="metric">
                  <div className="metric-value">{(result.duration/1000).toFixed(1)}s</div>
                  <div className="metric-label">Failed After</div>
                </div>
              </div>
              <div className="warning">
                🚨 <strong>Connection Failed:</strong> {result.error}
                <br />
                The database query timed out or the service is unavailable.
              </div>
            </div>
          )}

          {/* Quick Stats Card */}
          <div className="card">
            <h3>
              <div className="card-icon">📈</div>
              Dashboard Stats
            </h3>
            <div className="metrics-grid">
              <div className="metric">
                <div className="metric-value">2</div>
                <div className="metric-label">Container Apps</div>
              </div>
              <div className="metric">
                <div className="metric-value">1</div>
                <div className="metric-label">Database</div>
              </div>
              <div className="metric">
                <div className="metric-value">Azure</div>
                <div className="metric-label">Cloud Provider</div>
              </div>
              <div className="metric">
                <div className="metric-value">
                  {healthStatus?.status === 'healthy' ? '🟢' : '🔴'}
                </div>
                <div className="metric-label">Status</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;