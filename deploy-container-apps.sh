#!/bin/bash

# Azure Container Apps deployment script
# Usage: ./deploy-container-apps.sh [custom-suffix]

CUSTOM_SUFFIX="${1}"
if [ -n "$CUSTOM_SUFFIX" ]; then
    # Strip hyphens from custom suffix
    SUFFIX="${CUSTOM_SUFFIX//[-]/}"
else
    SUFFIX="containerapp$(date +%m%d)"
fi

# Resource names with suffix
RESOURCE_GROUP="rg-demo-app-${SUFFIX}"
ACR_NAME="acrcustomer${SUFFIX}"
POSTGRES_SERVER="psql-demo-${SUFFIX}"
LOCATION="australiaeast"
DB_NAME="customerdb"
DB_USER="demoadmin"
DB_PASSWORD="DemoPassword123!"
ENVIRONMENT_NAME="env-demo-app-${SUFFIX}"

echo "🚀 Deploying Customer Portal to Azure Container Apps..."
echo "   Frontend: React + Nginx"
echo "   Backend: Node.js Express API"
echo "   Database: Azure PostgreSQL Flexible Server"
echo "   Using suffix: $SUFFIX"

# Check if resource group exists, create if not
echo "📦 Checking resource group..."
if ! az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo "Creating resource group $RESOURCE_GROUP..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
else
    echo "✅ Resource group $RESOURCE_GROUP already exists"
fi

# Check if Container Registry exists, create if not
echo "🐳 Checking Azure Container Registry..."
if ! az acr show --resource-group $RESOURCE_GROUP --name $ACR_NAME &>/dev/null; then
    echo "Creating Azure Container Registry $ACR_NAME..."
    az acr create \
      --resource-group $RESOURCE_GROUP \
      --name $ACR_NAME \
      --sku Basic \
      --admin-enabled true
else
    echo "✅ Container Registry $ACR_NAME already exists"
fi

# Get ACR login server and credentials
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv)

echo "✅ ACR Login Server: $ACR_LOGIN_SERVER"

# Check if PostgreSQL server exists, create if not
echo "🐘 Checking Azure Database for PostgreSQL Flexible Server..."
if ! az postgres flexible-server show --resource-group $RESOURCE_GROUP --name $POSTGRES_SERVER &>/dev/null; then
    echo "Creating Azure Database for PostgreSQL Flexible Server with public access..."
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
      --public-access 0.0.0.0-255.255.255.255 \
      --yes

    # Wait for server to be ready
    echo "⏳ Waiting for PostgreSQL server to be ready..."
    az postgres flexible-server show \
      --resource-group $RESOURCE_GROUP \
      --name $POSTGRES_SERVER \
      --query state \
      --output tsv
else
    echo "✅ PostgreSQL server $POSTGRES_SERVER already exists"
fi

# Check if database exists, create if not
echo "📝 Checking database..."
if ! az postgres flexible-server db show --resource-group $RESOURCE_GROUP --server-name $POSTGRES_SERVER --database-name $DB_NAME &>/dev/null; then
    echo "Creating database $DB_NAME..."
    az postgres flexible-server db create \
      --resource-group $RESOURCE_GROUP \
      --server-name $POSTGRES_SERVER \
      --database-name $DB_NAME
else
    echo "✅ Database $DB_NAME already exists"
fi

# Get PostgreSQL server hostname
POSTGRES_HOST=$(az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --query fullyQualifiedDomainName \
  --output tsv)

echo "✅ PostgreSQL Host: $POSTGRES_HOST"

# Check if firewall rule for Azure services exists, create if not
# echo "🔐 Checking firewall rule for Azure services..."
# if ! az postgres flexible-server firewall-rule show --resource-group $RESOURCE_GROUP --name $POSTGRES_SERVER --rule-name AllowAzureServices &>/dev/null; then
#     echo "Creating firewall rule for Azure services..."
#     az postgres flexible-server firewall-rule create \
#       --resource-group $RESOURCE_GROUP \
#       --name $POSTGRES_SERVER \
#       --rule-name AllowAzureServices \
#       --start-ip-address 0.0.0.0 \
#       --end-ip-address 0.0.0.0
# else
#     echo "✅ Firewall rule AllowAzureServices already exists"
# fi

# DNS check for PostgreSQL host before proceeding
echo "🔎 Verifying DNS resolution for PostgreSQL host: $POSTGRES_HOST"
if [ -z "$POSTGRES_HOST" ]; then
  echo "❌ POSTGRES_HOST is empty. Aborting."
  exit 1
fi

RESOLVED=0
TRIES=0
MAX_RETRIES=24   # ~2 minutes total if SLEEP=5
SLEEP=5

while [ $TRIES -lt $MAX_RETRIES ]; do
  if command -v getent >/dev/null 2>&1; then
    if getent ahosts "$POSTGRES_HOST" >/dev/null 2>&1; then RESOLVED=1; break; fi
  elif command -v nslookup >/dev/null 2>&1; then
    if nslookup "$POSTGRES_HOST" >/dev/null 2>&1; then RESOLVED=1; break; fi
  elif command -v host >/dev/null 2>&1; then
    if host "$POSTGRES_HOST" >/dev/null 2>&1; then RESOLVED=1; break; fi
  else
    # fallback to ping (may require ICMP and not always reliable)
    if ping -c 1 -W 1 "$POSTGRES_HOST" >/dev/null 2>&1; then RESOLVED=1; break; fi
  fi

  TRIES=$((TRIES + 1))
  echo "⏳ DNS not yet resolvable. Retrying in ${SLEEP}s... ($TRIES/$MAX_RETRIES)"
  sleep $SLEEP
done

if [ $RESOLVED -eq 1 ]; then
  echo "✅ DNS resolution successful for $POSTGRES_HOST"
else
  echo "❌ Unable to resolve $POSTGRES_HOST after $((MAX_RETRIES * SLEEP)) seconds. Aborting."
  exit 1
fi

# Initialize database with test data using migrations
if command -v psql &> /dev/null && [ -d "migrations" ]; then
  echo "💾 Initializing database with migrations..."
  ./run_azure_migrations.sh full "$POSTGRES_HOST" "$DB_USER" "$DB_PASSWORD" "$DB_NAME" || {
    echo "⚠️  Database initialization failed. Data will be initialized during first app run."
  }
fi

# Build and push backend image
echo "🔨 Building and pushing backend image to ACR..."
cd backend
az acr build --registry $ACR_NAME --image customer-portal-backend:latest .
cd ..

# Create VNet and subnets first
echo "🌐 Checking Virtual Network infrastructure..."

# Check if VNet exists, create if not
if ! az network vnet show --resource-group $RESOURCE_GROUP --name vnet-containerapp &>/dev/null; then
    echo "Creating Virtual Network..."
    az network vnet create \
      --resource-group $RESOURCE_GROUP \
      --name vnet-containerapp \
      --location $LOCATION \
      --address-prefix 10.0.0.0/16 \
      --output none
else
    echo "✅ Virtual Network vnet-containerapp already exists"
fi

# # Check if PostgreSQL subnet exists, create if not
# if ! az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name vnet-containerapp --name subnet-postgres &>/dev/null; then
#     echo "Creating subnet for PostgreSQL..."
#     az network vnet subnet create \
#       --resource-group $RESOURCE_GROUP \
#       --vnet-name vnet-containerapp \
#       --name subnet-postgres \
#       --address-prefix 10.0.1.0/24 \
#       --delegations Microsoft.DBforPostgreSQL/flexibleServers \
#       --output none
# else
#     echo "✅ PostgreSQL subnet already exists"
# fi

# Check if Container Apps subnet exists, create if not
if ! az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name vnet-containerapp --name subnet-containerapp &>/dev/null; then
    echo "Creating subnet for Container Apps..."
    az network vnet subnet create \
      --resource-group $RESOURCE_GROUP \
      --vnet-name vnet-containerapp \
      --name subnet-containerapp \
      --address-prefix 10.0.2.0/23 \
      --delegations Microsoft.App/environments \
      --output none
else
    echo "✅ Container Apps subnet already exists"
fi


# Get subnet ID for Container Apps
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-containerapp \
  --name subnet-containerapp \
  --query id \
  --output tsv)

# Check if Container App Environment exists, create if not
echo "🌐 Checking VNet-integrated Container App Environment..."
if ! az containerapp env show --resource-group $RESOURCE_GROUP --name $ENVIRONMENT_NAME &>/dev/null; then
    echo "Creating VNet-integrated Container App Environment..."
    az containerapp env create \
      --name $ENVIRONMENT_NAME \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION \
      --infrastructure-subnet-resource-id "$SUBNET_ID"
else
    echo "✅ Container App Environment $ENVIRONMENT_NAME already exists"
fi

# Get environment ID
ENVIRONMENT_ID=$(az containerapp env show \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --output tsv)

# Check if backend container app exists, create if not
echo "🔧 Checking backend Container App..."
if ! az containerapp show --resource-group $RESOURCE_GROUP --name backend-api &>/dev/null; then
    echo "Creating backend Container App..."
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
else
    echo "✅ Backend Container App backend-api already exists"
fi

# Get backend URL
BACKEND_URL=$(az containerapp show \
  --name backend-api \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

echo "✅ Backend API URL: https://$BACKEND_URL"

# Build and push frontend image
echo "🔨 Building and pushing frontend image to ACR..."
cd frontend
az acr build --registry $ACR_NAME --build-arg BACKEND_URL=https://${BACKEND_URL} --image customer-portal-frontend:latest .
cd ..

# Check if frontend container app exists, create if not
echo "🔧 Checking frontend Container App..."
if ! az containerapp show --resource-group $RESOURCE_GROUP --name frontend-web &>/dev/null; then
    echo "Creating frontend Container App..."
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
else
    echo "✅ Frontend Container App frontend-web already exists"
fi

# Get frontend URL
FRONTEND_URL=$(az containerapp show \
  --name frontend-web \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv)


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