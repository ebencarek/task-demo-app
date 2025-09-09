#!/bin/bash

# Deploy PostgreSQL Flexible Server for Container Apps
SUFFIX="containerapp$(date +%m%d)"
RESOURCE_GROUP="rg-demo-app${SUFFIX}"
POSTGRES_SERVER="psql-demo${SUFFIX}"
LOCATION="australiaeast"
DB_NAME="customerdb"
DB_USER="demoadmin"
DB_PASSWORD="DemoPassword123!"

echo "🐘 Deploying PostgreSQL Flexible Server..."
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Server Name: $POSTGRES_SERVER"

# Create PostgreSQL Flexible Server with public access
echo "📝 Creating PostgreSQL Flexible Server with public access..."
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --location $LOCATION \
  --admin-user $DB_USER \
  --admin-password "$DB_PASSWORD" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15 \
  --public-access 0.0.0.0-255.255.255.255

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

# Create firewall rule for Azure services
echo "🔐 Configuring firewall for Azure services..."
az postgres flexible-server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER \
  --rule-name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Try to initialize database with sample data using psql client
echo "💾 Attempting to initialize database with sample data..."
if command -v psql &> /dev/null; then
    echo "psql client found, initializing database..."
    # Run database migrations  
    for migration in migrations/*.sql; do
        if [ -f "$migration" ]; then
            echo "Running migration: $(basename $migration)"
            PGPASSWORD="$DB_PASSWORD" psql -h $POSTGRES_HOST -U $DB_USER -d $DB_NAME -f "$migration"
        fi
    done
    echo "✅ Database initialized successfully!"
else
    echo "⚠️ psql client not found. Database will be initialized on first API call."
fi

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
echo "postgresql://$DB_USER:$DB_PASSWORD@$POSTGRES_HOST:5432/$DB_NAME?sslmode=require"
echo ""
echo "📝 Next Steps:"
echo "1. Update Container App environment variables with database info"
echo "2. Restart Container Apps to pick up new configuration"
echo "3. Test database connectivity"
echo ""
echo "🔧 Update Container Apps with database connection:"
echo "   az containerapp update --name backend-api --resource-group $RESOURCE_GROUP \\"
echo "     --set-env-vars DB_HOST=$POSTGRES_HOST DB_USER=$DB_USER DB_PASSWORD=$DB_PASSWORD DB_NAME=$DB_NAME DB_PORT=5432"
echo "=================================="