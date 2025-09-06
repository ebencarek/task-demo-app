# Customer Portal - Azure Container Apps Deployment

This application has been restructured to use Azure Container Apps with a modern microservices architecture:

- **Frontend**: React application served by Nginx
- **Backend**: Node.js Express API
- **Database**: Azure PostgreSQL Flexible Server

## Architecture

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Frontend          │    │   Backend           │    │   Azure PostgreSQL  │
│   Container App     │◄──►│   Container App     │◄──►│   Flexible Server   │
│   (React + Nginx)   │    │   (Node.js Express) │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

## Deployment

### Prerequisites

- Azure CLI installed and logged in
- Docker (for local testing)
- Node.js 18+ (for local development)

### Deploy to Azure Container Apps

Run the deployment script:

```bash
chmod +x deploy-container-apps.sh
./deploy-container-apps.sh
```

This will:
1. Create resource group and Container Registry
2. Create Azure PostgreSQL Flexible Server
3. Build and push Docker images to ACR
4. Create Container App Environment
5. Deploy frontend and backend Container Apps
6. Initialize database with test data

### Local Development

#### Backend API
```bash
cd backend
npm install
npm start
# API runs on http://localhost:3001
```

#### Frontend
```bash
cd frontend  
npm install
npm start
# Frontend runs on http://localhost:3000
```

#### Database (Local PostgreSQL)
```bash
# Start PostgreSQL locally
psql -U postgres -d customerdb < init.sql
```

## Container App Features

- **Auto-scaling**: Scales based on HTTP requests
- **Blue-green deployments**: Zero-downtime deployments
- **Managed certificates**: Automatic HTTPS
- **Container logs**: Built-in logging and monitoring
- **Health checks**: Automatic restart on failures

## Performance Demo

The application includes an intentionally slow database query to demonstrate performance monitoring:

1. Access the frontend URL
2. Click "View Customer Insights" 
3. Query takes 10-30+ seconds due to missing database indexes
4. This simulates a real-world performance issue

## Monitoring

View Container App logs:
```bash
# Backend logs
az containerapp logs show --name backend-api --resource-group rg-demo-app-containerapp09051

# Frontend logs  
az containerapp logs show --name frontend-web --resource-group rg-demo-app-containerapp09051

# List revisions
az containerapp revision list --name backend-api --resource-group rg-demo-app-containerapp09051
```

## Cleanup

Remove all resources:
```bash
az group delete --name rg-demo-app-containerapp09051 --yes
```

## Files Structure

```
├── frontend/                 # React frontend
│   ├── src/
│   │   ├── App.js           # Main React component
│   │   ├── App.css          # Styles
│   │   └── index.js         # Entry point
│   ├── public/
│   │   └── index.html       # HTML template
│   ├── Dockerfile           # Frontend container
│   ├── nginx.conf           # Nginx configuration
│   └── package.json         # Frontend dependencies
├── backend/                  # Node.js backend
│   ├── server.js            # Express API server
│   ├── Dockerfile           # Backend container
│   └── package.json         # Backend dependencies
├── deploy-container-apps.sh  # Deployment script
├── backend-containerapp.yaml # Backend Container App manifest
├── frontend-containerapp.yaml # Frontend Container App manifest
└── init.sql                 # Database initialization
```
