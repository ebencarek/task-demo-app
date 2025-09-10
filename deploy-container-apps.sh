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
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv | tr -d '\r\n' | xargs)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv | tr -d '\r\n' | xargs)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv | tr -d '\r\n' | xargs)

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
      --tier GeneralPurpose \
      --public-access 0.0.0.0-255.255.255.255 \
      --yes

    # Wait for server to be ready
    echo "⏳ Waiting for PostgreSQL server to be ready..."
    az postgres flexible-server show \
      --resource-group $RESOURCE_GROUP \
      --name $POSTGRES_SERVER \
      --query state \
      --output tsv

    # Enable Query Store + Wait Sampling required for Query Performance Insight
    echo "Configuring PostgreSQL server parameters for query analysis (Query Store + Wait Sampling + Enhanced Metrics)..."
    az postgres flexible-server parameter set --resource-group $RESOURCE_GROUP --server-name $POSTGRES_SERVER --name pg_qs.query_capture_mode --value ALL --output none || echo "⚠️  Failed to set pg_qs.query_capture_mode"
    az postgres flexible-server parameter set --resource-group $RESOURCE_GROUP --server-name $POSTGRES_SERVER --name pgms_wait_sampling.query_capture_mode --value ALL --output none || echo "⚠️  Failed to set pgms_wait_sampling.query_capture_mode"
    az postgres flexible-server parameter set --resource-group $RESOURCE_GROUP --server-name $POSTGRES_SERVER --name metrics.collector_database_activity --value ON --output none || echo "⚠️  Failed to set metrics.collector_database_activity"
    echo "✅ PostgreSQL server parameters configured"
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
  --output tsv | tr -d '\r\n' | xargs)

echo "✅ PostgreSQL Host: $POSTGRES_HOST"

# -----------------------------------------------------------------------------
# Log Analytics (Diagnostic Settings) for Query Performance Insight
# Categories needed: Sessions (PostgreSQLLogs), Query Store Runtime (PostgreSQLFlexQueryStoreRuntime),
# Query Store Wait Statistics (PostgreSQLFlexQueryStoreWaitStats)
# -----------------------------------------------------------------------------
LOG_ANALYTICS_WS="law-demo-app-${SUFFIX}"
echo "📊 Configuring Log Analytics workspace $LOG_ANALYTICS_WS for PostgreSQL diagnostics..."

# Create workspace if it does not exist
if ! az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_WS &>/dev/null; then
    echo "Creating Log Analytics workspace $LOG_ANALYTICS_WS..."
    az monitor log-analytics workspace create \
      --resource-group $RESOURCE_GROUP \
      --workspace-name $LOG_ANALYTICS_WS \
      --location $LOCATION \
      --output none
else
    echo "✅ Log Analytics workspace $LOG_ANALYTICS_WS already exists"
fi

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $LOG_ANALYTICS_WS \
  --query id -o tsv | tr -d '\r\n' | xargs)

POSTGRES_SERVER_ID=$(az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --query id -o tsv | tr -d '\r\n' | xargs)

# Check if a diagnostic setting already exists pointing to this workspace
EXISTING_DIAG=$(az monitor diagnostic-settings list --resource $POSTGRES_SERVER_ID --query "[?workspaceId=='$WORKSPACE_ID'].name" -o tsv | head -n1)

# Categories: PostgreSQLLogs (includes session connections/activity), Query Store runtime + wait stats
LOG_CATEGORIES='[{"category":"PostgreSQLLogs","enabled":true},{"category":"PostgreSQLFlexQueryStoreRuntime","enabled":true},{"category":"PostgreSQLFlexQueryStoreWaitStats","enabled":true},{"category":"PostgreSQLFlexSessions","enabled":true}]'
METRIC_CATEGORIES='[{"category":"AllMetrics","enabled":true}]'

if [ -z "$EXISTING_DIAG" ]; then
  echo "Creating diagnostic settings for PostgreSQL server (Sessions + Query Store categories)..."
  az monitor diagnostic-settings create \
    --name pg-flex-diag \
    --resource $POSTGRES_SERVER_ID \
    --workspace $WORKSPACE_ID \
    --logs "$LOG_CATEGORIES" \
    --metrics "$METRIC_CATEGORIES" \
    --output none || echo "⚠️  Failed to create diagnostic settings"
else
  echo "✅ Diagnostic settings already configured: $EXISTING_DIAG"
fi


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

while [ $TRIES -lt $MAX_RETRIES ] && [ $RESOLVED -eq 0 ]; do
  TRIES=$((TRIES + 1))
  echo "⏳ Attempting DNS resolution... ($TRIES/$MAX_RETRIES)"

  # Try multiple DNS resolution methods
  if command -v getent >/dev/null 2>&1; then
    if getent ahosts "$POSTGRES_HOST" >/dev/null 2>&1; then
      RESOLVED=1
      echo "✅ DNS resolution successful using getent"
      break
    fi
  fi

  if [ $RESOLVED -eq 0 ] && command -v nslookup >/dev/null 2>&1; then
    if nslookup "$POSTGRES_HOST" >/dev/null 2>&1; then
      RESOLVED=1
      echo "✅ DNS resolution successful using nslookup"
      break
    fi
  fi

  if [ $RESOLVED -eq 0 ] && command -v host >/dev/null 2>&1; then
    if host "$POSTGRES_HOST" >/dev/null 2>&1; then
      RESOLVED=1
      echo "✅ DNS resolution successful using host"
      break
    fi
  fi

  if [ $RESOLVED -eq 0 ] && command -v dig >/dev/null 2>&1; then
    if dig "$POSTGRES_HOST" +short | grep -q .; then
      RESOLVED=1
      echo "✅ DNS resolution successful using dig"
      break
    fi
  fi

  # If still not resolved and not at max retries, wait and try again
  if [ $RESOLVED -eq 0 ] && [ $TRIES -lt $MAX_RETRIES ]; then
    echo "⏳ DNS not yet resolvable. Retrying in ${SLEEP}s..."
    sleep $SLEEP
  fi
done

if [ $RESOLVED -eq 1 ]; then
  echo "✅ DNS resolution confirmed for $POSTGRES_HOST"
else
  echo "❌ Unable to resolve $POSTGRES_HOST after $((MAX_RETRIES * SLEEP)) seconds."
  echo "❌ PostgreSQL host is not reachable. Deployment cannot continue."
  echo "❌ Please check that the PostgreSQL server exists and DNS propagation is complete."
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

# Build and push frontend image
echo "🔨 Building and pushing frontend image to ACR..."
cd frontend
az acr build --registry $ACR_NAME --image customer-portal-frontend:latest .
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
  --output tsv | tr -d '\r\n' | xargs)

# Check if Container App Environment exists, create if not
echo "🌐 Checking VNet-integrated Container App Environment..."
if ! az containerapp env show --resource-group $RESOURCE_GROUP --name $ENVIRONMENT_NAME &>/dev/null; then
    echo "Creating VNet-integrated Container App Environment..."
    az containerapp env create \
      --name $ENVIRONMENT_NAME \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION \
      --infrastructure-subnet-resource-id $SUBNET_ID \
      --logs-destination azure-monitor
else
    echo "✅ Container App Environment $ENVIRONMENT_NAME already exists"
fi

# Get environment ID
ENVIRONMENT_ID=$(az containerapp env show \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --output tsv | tr -d '\r\n' | xargs)

# Check if backend container app exists, create or update
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
    echo "✅ Backend Container App backend-api already exists, creating new revision..."
    az containerapp update \
      --name backend-api \
      --resource-group $RESOURCE_GROUP \
      --image $ACR_LOGIN_SERVER/customer-portal-backend:latest \
      --set-env-vars DB_HOST=secretref:db-host DB_USER=secretref:db-user DB_PASSWORD=secretref:db-password DB_NAME=secretref:db-name DB_PORT=5432 \
      --replace-secrets db-host=$POSTGRES_HOST db-user=$DB_USER db-password=$DB_PASSWORD db-name=$DB_NAME
fi

# Get backend URL
BACKEND_URL=$(az containerapp show \
  --name backend-api \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv | tr -d '\r\n' | xargs)

echo "✅ Backend API URL: https://$BACKEND_URL"

# Check if frontend container app exists, create or update
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
    echo "✅ Frontend Container App frontend-web already exists, creating new revision..."
    az containerapp update \
      --name frontend-web \
      --resource-group $RESOURCE_GROUP \
      --image $ACR_LOGIN_SERVER/customer-portal-frontend:latest \
      --set-env-vars REACT_APP_API_URL=https://$BACKEND_URL
fi

# Get frontend URL
FRONTEND_URL=$(az containerapp show \
  --name frontend-web \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn \
  --output tsv | tr -d '\r\n' | xargs)


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
echo ""
echo "📝 Container App Commands:"
echo "   az containerapp logs show --name backend-api --resource-group $RESOURCE_GROUP"
echo "   az containerapp logs show --name frontend-web --resource-group $RESOURCE_GROUP"
echo "   az containerapp revision list --name backend-api --resource-group $RESOURCE_GROUP"
echo ""
echo "🗑️  To clean up all resources:"
echo "   az group delete --name $RESOURCE_GROUP --yes"
echo "=================================="