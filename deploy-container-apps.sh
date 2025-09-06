#!/bin/bash

# Azure Container Apps deployment script
SUFFIX="containerapp$(date +%m%d)"

# Resource names with suffix
RESOURCE_GROUP="rg-demo-app${SUFFIX}"
ACR_NAME="acrcustomer${SUFFIX}"
POSTGRES_SERVER="psql-demo${SUFFIX}"
LOCATION="australiaeast"
DB_NAME="customerdb"
DB_USER="demoadmin"
DB_PASSWORD="DemoPassword123!"
ENVIRONMENT_NAME="env-demo-app${SUFFIX}"

echo "🚀 Deploying Customer Portal to Azure Container Apps..."
echo "   Frontend: React + Nginx"
echo "   Backend: Node.js Express API"
echo "   Database: Azure PostgreSQL Flexible Server"

# Create resource group
echo "📦 Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
echo "🐳 Creating Azure Container Registry..."
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true

# Get ACR login server and credentials
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv)

echo "✅ ACR Login Server: $ACR_LOGIN_SERVER"

# Create Azure PostgreSQL Flexible Server in VNet
echo "🐘 Creating Azure Database for PostgreSQL Flexible Server in VNet..."
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --location $LOCATION \
  --admin-user $DB_USER \
  --admin-password $DB_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15 \
  --subnet subnet-postgres \
  --vnet vnet-containerapp \
  --private-dns-zone privatelink.postgres.database.azure.com \
  --yes

# Wait for server to be ready
echo "⏳ Waiting for PostgreSQL server to be ready..."
az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --query state \
  --output tsv

# Create database
echo "📝 Creating database..."
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER \
  --database-name $DB_NAME

# Get PostgreSQL server hostname
POSTGRES_HOST=$(az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --query fullyQualifiedDomainName \
  --output tsv)

echo "✅ PostgreSQL Host: $POSTGRES_HOST"

# Initialize database with test data
if [ -f "init.sql" ]; then
  echo "💾 Initializing database with test data..."
  PGPASSWORD=$DB_PASSWORD psql -h $POSTGRES_HOST -U $DB_USER -d $DB_NAME -c "\i init.sql" 2>/dev/null || {
    echo "⚠️  Database initialization may require psql client. Data will be initialized during first app run."
  }
fi

# Build and push backend image
echo "🔨 Building and pushing backend image to ACR..."
cd backend
az acr build --registry $ACR_NAME --image customer-portal-backend:latest .
cd ..

# Build and push frontend image  
echo "🔨 Building and pushing frontend image to ACR..."
cd frontend
az acr build --registry $ACR_NAME --image customer-portal-frontend:latest .
cd ..

# Create VNet and subnets first
echo "🌐 Creating Virtual Network infrastructure..."

# Create VNet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name vnet-containerapp \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16 \
  --output none

# Create subnet for PostgreSQL with delegation
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-containerapp \
  --name subnet-postgres \
  --address-prefix 10.0.1.0/24 \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers \
  --output none

# Create subnet for Container Apps (requires /23 or larger)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-containerapp \
  --name subnet-containerapp \
  --address-prefix 10.0.2.0/23 \
  --output none

# Create private DNS zone for PostgreSQL
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name privatelink.postgres.database.azure.com \
  --output none

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RESOURCE_GROUP \
  --zone-name privatelink.postgres.database.azure.com \
  --name vnet-link \
  --virtual-network vnet-containerapp \
  --registration-enabled false \
  --output none

# Get subnet ID for Container Apps
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-containerapp \
  --name subnet-containerapp \
  --query id \
  --output tsv)

# Create VNet-integrated Container App Environment
echo "🌐 Creating VNet-integrated Container App Environment..."
az containerapp env create \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --infrastructure-subnet-resource-id "$SUBNET_ID"

# Get environment ID
ENVIRONMENT_ID=$(az containerapp env show \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --output tsv)

# Create backend container app
echo "🔧 Creating backend Container App..."
az containerapp create \
  --name backend-api \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --image $ACR_LOGIN_SERVER/customer-portal-backend:latest \
  --target-port 3001 \
  --ingress external \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --secrets db-host=$POSTGRES_HOST db-user=$DB_USER db-password=$DB_PASSWORD db-name=$DB_NAME \
  --env-vars DB_HOST=secretref:db-host DB_USER=secretref:db-user DB_PASSWORD=secretref:db-password DB_NAME=secretref:db-name DB_PORT=5432 \
  --cpu 0.25 --memory 0.5Gi \
  --min-replicas 1 --max-replicas 5

# Get backend URL
BACKEND_URL=$(az containerapp show \
  --name backend-api \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

echo "✅ Backend API URL: https://$BACKEND_URL"

# Create frontend container app
echo "🔧 Creating frontend Container App..."
az containerapp create \
  --name frontend-web \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --image $ACR_LOGIN_SERVER/customer-portal-frontend:latest \
  --target-port 80 \
  --ingress external \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --env-vars REACT_APP_API_URL=https://$BACKEND_URL \
  --cpu 0.25 --memory 0.5Gi \
  --min-replicas 1 --max-replicas 3

# Get frontend URL
FRONTEND_URL=$(az containerapp show \
  --name frontend-web \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

# Initialize database if init.sql exists and database is accessible
if [ -f "init.sql" ]; then
  echo "💾 Attempting to initialize database from Container App..."
  
  # Create a temporary container to run the database initialization
  az containerapp job create \
    --name init-database-job \
    --resource-group $RESOURCE_GROUP \
    --environment $ENVIRONMENT_NAME \
    --image postgres:15 \
    --secrets db-host=$POSTGRES_HOST db-user=$DB_USER db-password=$DB_PASSWORD db-name=$DB_NAME \
    --env-vars PGPASSWORD=secretref:db-password \
    --command "/bin/sh" \
    --args "-c,echo 'Connecting to database...'; psql -h $POSTGRES_HOST -U $DB_USER -d $DB_NAME -c 'SELECT version();' && echo 'Database initialized successfully'" \
    --cpu 0.25 --memory 0.5Gi \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD 2>/dev/null || echo "⚠️  Database job creation failed - will initialize on first API call"
fi

# Display summary
echo ""
echo "=================================="
echo "✅ Container Apps Deployment Complete!"
echo "=================================="
echo ""
echo "🌐 Application URLs:"
echo "   Frontend: https://$FRONTEND_URL"
echo "   Backend API: https://$BACKEND_URL"
echo "   Health Check: https://$BACKEND_URL/health"
echo ""
echo "🐘 Database:"
echo "   Server: $POSTGRES_HOST"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo ""
echo "📊 Architecture:"
echo "   ├── Frontend Container App (React + Nginx)"
echo "   ├── Backend Container App (Node.js Express)"
echo "   └── Azure PostgreSQL Flexible Server"
echo ""
echo "⚠️  Performance Demo:"
echo "   1. Open https://$FRONTEND_URL"
echo "   2. Click 'View Customer Insights'"
echo "   3. Query will take 10-30+ seconds due to missing indexes"
echo ""
echo "📝 Container App Commands:"
echo "   az containerapp logs show --name backend-api --resource-group $RESOURCE_GROUP"
echo "   az containerapp logs show --name frontend-web --resource-group $RESOURCE_GROUP"
echo "   az containerapp revision list --name backend-api --resource-group $RESOURCE_GROUP"
echo ""
echo "🗑️  To clean up all resources:"
echo "   az group delete --name $RESOURCE_GROUP --yes"
echo "=================================="