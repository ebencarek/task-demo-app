#!/bin/bash

# Deploy PostgreSQL Single Server (simpler than Flexible Server)
SUFFIX="containerapp$(date +%m%d)"
RESOURCE_GROUP="rg-demo-app${SUFFIX}"
POSTGRES_SERVER="psql-single${SUFFIX}"
LOCATION="australiaeast"
DB_NAME="customerdb"
DB_USER="demoadmin"
DB_PASSWORD="DemoPassword123!"

echo "🐘 Deploying PostgreSQL Single Server (Legacy but simpler)..."
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Server Name: $POSTGRES_SERVER"

# Check if server already exists with a slightly different name
echo "🔍 Checking if PostgreSQL server exists..."
EXISTING_SERVERS=$(az postgres server list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv 2>/dev/null || echo "")

if [ ! -z "$EXISTING_SERVERS" ]; then
    echo "✅ Found existing PostgreSQL servers: $EXISTING_SERVERS"
    POSTGRES_SERVER=$(echo $EXISTING_SERVERS | head -n1)
    echo "Using existing server: $POSTGRES_SERVER"
else
    echo "📝 Creating new PostgreSQL Single Server..."
    # Create PostgreSQL Single Server (simpler, less configuration needed)
    az postgres server create \
      --resource-group $RESOURCE_GROUP \
      --name $POSTGRES_SERVER \
      --location $LOCATION \
      --admin-user $DB_USER \
      --admin-password "$DB_PASSWORD" \
      --sku-name B_Gen5_1 \
      --version 11 \
      --storage-size 51200 \
      --ssl-enforcement Disabled
    
    echo "⏳ Waiting for server to be ready..."
    sleep 30
fi

# Get PostgreSQL server hostname
POSTGRES_HOST=$(az postgres server show \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --query fullyQualifiedDomainName \
  --output tsv 2>/dev/null || echo "")

if [ -z "$POSTGRES_HOST" ]; then
    echo "❌ Failed to get PostgreSQL hostname. Trying alternative approach..."
    # Try to find any postgres server in the resource group
    POSTGRES_HOST=$(az postgres server list --resource-group $RESOURCE_GROUP --query "[0].fullyQualifiedDomainName" --output tsv 2>/dev/null || echo "")
    
    if [ ! -z "$POSTGRES_HOST" ]; then
        POSTGRES_SERVER=$(az postgres server list --resource-group $RESOURCE_GROUP --query "[0].name" --output tsv)
        echo "✅ Found PostgreSQL server: $POSTGRES_SERVER at $POSTGRES_HOST"
    else
        echo "❌ No PostgreSQL server found. Trying flexible server approach with minimal config..."
        
        # Try minimal flexible server creation
        az postgres flexible-server create \
          --resource-group $RESOURCE_GROUP \
          --name "psql-flex${SUFFIX}" \
          --location $LOCATION \
          --admin-user $DB_USER \
          --admin-password "$DB_PASSWORD" \
          --sku-name Standard_B1ms \
          --tier Burstable \
          --storage-size 32 \
          --version 15 \
          --yes
        
        POSTGRES_HOST=$(az postgres flexible-server show \
          --resource-group $RESOURCE_GROUP \
          --name "psql-flex${SUFFIX}" \
          --query fullyQualifiedDomainName \
          --output tsv 2>/dev/null || echo "")
        
        POSTGRES_SERVER="psql-flex${SUFFIX}"
    fi
fi

echo "✅ PostgreSQL Host: $POSTGRES_HOST"

if [ ! -z "$POSTGRES_HOST" ]; then
    # Create database
    echo "📝 Creating database..."
    az postgres db create \
      --resource-group $RESOURCE_GROUP \
      --server-name $POSTGRES_SERVER \
      --name $DB_NAME || echo "Database may already exist"

    # Create firewall rule for Azure services
    echo "🔐 Configuring firewall for Azure services..."
    az postgres server firewall-rule create \
      --resource-group $RESOURCE_GROUP \
      --server $POSTGRES_SERVER \
      --name AllowAzureServices \
      --start-ip-address 0.0.0.0 \
      --end-ip-address 0.0.0.0 2>/dev/null || echo "Firewall rule may already exist"

    # Also allow all IPs for testing (can be restricted later)
    az postgres server firewall-rule create \
      --resource-group $RESOURCE_GROUP \
      --server $POSTGRES_SERVER \
      --name AllowAll \
      --start-ip-address 0.0.0.0 \
      --end-ip-address 255.255.255.255 2>/dev/null || echo "Firewall rule may already exist"

    # Display connection info
    echo ""
    echo "=================================="
    echo "✅ PostgreSQL Deployment Complete!"
    echo "=================================="
    echo ""
    echo "🐘 Database Connection Info:"
    echo "   Host: $POSTGRES_HOST"
    echo "   Database: $DB_NAME"
    echo "   User: $DB_USER"
    echo "   Password: $DB_PASSWORD"
    echo ""
    echo "🔗 Connection String:"
    echo "postgresql://$DB_USER@$POSTGRES_SERVER:$DB_PASSWORD@$POSTGRES_HOST:5432/$DB_NAME?sslmode=require"
    echo ""
    echo "🔧 Update Container Apps with database connection:"
    echo "   az containerapp update --name backend-api --resource-group $RESOURCE_GROUP \\"
    echo "     --set-env-vars DB_HOST=$POSTGRES_HOST DB_USER=$DB_USER@$POSTGRES_SERVER DB_PASSWORD=$DB_PASSWORD DB_NAME=$DB_NAME DB_PORT=5432"
    echo "=================================="
else
    echo "❌ Failed to create or find PostgreSQL server"
    echo "🔧 Manual creation may be required through Azure Portal"
fi