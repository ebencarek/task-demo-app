#!/bin/sh

# Create runtime configuration file
cat > /usr/share/nginx/html/config.js << EOF
window.APP_CONFIG = {
  API_URL: '${REACT_APP_API_URL:-http://localhost:3001}'
};
EOF

# Start nginx
nginx -g "daemon off;"