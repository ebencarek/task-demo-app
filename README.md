# Customer Portal - Azure Container Apps Deployment

This application has been restructured to use Azure Container Apps with a modern microservices architecture:

- **Frontend**: React application served by a lightweight Node.js/Express server (acts as API gateway/proxy)
- **Backend**: Node.js Express API
- **Database**: Azure PostgreSQL Flexible Server

## Architecture

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Frontend          │    │   Backend           │    │   Azure PostgreSQL  │
│   Container App     │◄──►│   Container App     │◄──►│   Flexible Server   │
│ (React + Express)   │◄──►│   (Node.js Express) │    │                     │
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
./deploy-container-apps.sh [custom_suffix]
```

This will:
1. Create resource group and Container Registry
2. Create Azure PostgreSQL Flexible Server
3. Build and push Docker images to ACR
4. Create Container App Environment
5. Deploy frontend and backend Container Apps
6. Initialize database with test data

### Local Development

For detailed local development setup instructions, see [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md).

## Container App Features

- **Auto-scaling**: Scales based on HTTP requests
- **Blue-green deployments**: Zero-downtime deployments
- **Managed certificates**: Automatic HTTPS
- **Container logs**: Built-in logging and monitoring
- **Health checks**: Automatic restart on failures

## Performance Demo

The application includes an intentionally slow database query to demonstrate performance monitoring. The initial deployment creates DB indexes to make the query perform faster:

1. Access the frontend URL
2. Click "Analyze Customer Data"
3. Query takes ~5 milliseconds

Deploy the base setup:

```bash
./deploy-container-apps.sh [custom_suffix]
```

Start simulating customer traffic, let it run for a little bit:

```bash
./simulate_customer_traffic.sh [fqdn of frontend webapp]
```

Deploy a problematic DB migration that drops the indexes and impacts latency:

```bash
./deploy-container-apps.sh [custom_suffix] full
```

1. Click "Analyze Customer Data"
2. Query takes >700 milliseconds
3. Tell agent to analyze issues.

Reset the DB to fast state:

```bash
chmod +x setup_db_migrations.sh
./setup_db_migrations.sh azure [custom_suffix] fast
```

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
├── frontend/                 # React frontend + Express proxy
│   ├── src/
│   │   ├── App.js           # Main React component
│   │   ├── App.css          # Styles
│   │   └── index.js         # Entry point
│   ├── public/
│   │   └── index.html       # HTML template
│   ├── Dockerfile           # Frontend container (Node multi-stage build)
│   ├── server.js            # Express server serving static build + proxy
│   ├── nginx.conf           # (Deprecated) Old Nginx configuration
│   └── package.json         # Frontend dependencies
├── backend/                  # Node.js backend
│   ├── server.js            # Express API server
│   ├── Dockerfile           # Backend container
│   └── package.json         # Backend dependencies
├── deploy-container-apps.sh  # Deployment script
├── backend-containerapp.yaml # Backend Container App manifest
├── frontend-containerapp.yaml # Frontend Container App manifest
├── migrations/              # Database migrations
│   ├── 001_initial_schema.sql
│   ├── 002_add_indexes.sql
│   └── 003_temp_index_cleanup.sql
├── setup_db_migrations.sh   # Database setup script
└── LOCAL_DEVELOPMENT.md     # Local development guide
```
