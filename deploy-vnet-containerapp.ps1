# PowerShell script to deploy VNet-integrated Container Apps
# Run this in PowerShell (not Git Bash) to avoid path issues

$SUFFIX = "vnet$(Get-Date -Format 'MMdd')"
$RESOURCE_GROUP = "rg-demo-app$SUFFIX"
$ACR_NAME = "acrcustomer$SUFFIX"
$POSTGRES_SERVER = "psql-demo$SUFFIX" 
$LOCATION = "australiaeast"
$ENVIRONMENT_NAME = "env-demo-app$SUFFIX"
$DB_NAME = "customerdb"
$DB_USER = "demoadmin"
$DB_PASSWORD = "DemoPassword123!"

Write-Host "🚀 Deploying VNet-integrated Container Apps..." -ForegroundColor Green
Write-Host "   Resource Group: $RESOURCE_GROUP" -ForegroundColor Cyan
Write-Host "   Environment: $ENVIRONMENT_NAME" -ForegroundColor Cyan

# Create resource group
Write-Host "📦 Creating resource group..." -ForegroundColor Yellow
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

# Create Azure Container Registry
Write-Host "🐳 Creating Azure Container Registry..." -ForegroundColor Yellow
az acr create `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled true `
  --output none

# Get ACR credentials
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv
$ACR_USERNAME = az acr credential show --name $ACR_NAME --query username --output tsv
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv

Write-Host "✅ ACR Login Server: $ACR_LOGIN_SERVER" -ForegroundColor Green

# Create VNet infrastructure
Write-Host "🌐 Creating Virtual Network infrastructure..." -ForegroundColor Yellow

# Create VNet
az network vnet create `
  --resource-group $RESOURCE_GROUP `
  --name vnet-containerapp `
  --location $LOCATION `
  --address-prefix 10.0.0.0/16 `
  --output none

# Create subnet for PostgreSQL
az network vnet subnet create `
  --resource-group $RESOURCE_GROUP `
  --vnet-name vnet-containerapp `
  --name subnet-postgres `
  --address-prefix 10.0.1.0/24 `
  --delegations Microsoft.DBforPostgreSQL/flexibleServers `
  --output none

# Create subnet for Container Apps
az network vnet subnet create `
  --resource-group $RESOURCE_GROUP `
  --vnet-name vnet-containerapp `
  --name subnet-containerapp `
  --address-prefix 10.0.2.0/23 `
  --output none

# Create private DNS zone
az network private-dns zone create `
  --resource-group $RESOURCE_GROUP `
  --name privatelink.postgres.database.azure.com `
  --output none

# Link DNS zone to VNet
az network private-dns link vnet create `
  --resource-group $RESOURCE_GROUP `
  --zone-name privatelink.postgres.database.azure.com `
  --name vnet-link `
  --virtual-network vnet-containerapp `
  --registration-enabled false `
  --output none

# Get subnet ID
$SUBNET_ID = az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name vnet-containerapp `
  --name subnet-containerapp `
  --query id `
  --output tsv

# Create PostgreSQL server in VNet
Write-Host "🐘 Creating PostgreSQL Flexible Server in VNet..." -ForegroundColor Yellow
az postgres flexible-server create `
  --resource-group $RESOURCE_GROUP `
  --name $POSTGRES_SERVER `
  --location $LOCATION `
  --admin-user $DB_USER `
  --admin-password $DB_PASSWORD `
  --sku-name Standard_B1ms `
  --tier Burstable `
  --storage-size 32 `
  --version 15 `
  --subnet subnet-postgres `
  --vnet vnet-containerapp `
  --private-dns-zone privatelink.postgres.database.azure.com `
  --yes

# Create database
Write-Host "📝 Creating database..." -ForegroundColor Yellow
az postgres flexible-server db create `
  --resource-group $RESOURCE_GROUP `
  --server-name $POSTGRES_SERVER `
  --database-name $DB_NAME

$POSTGRES_HOST = az postgres flexible-server show `
  --resource-group $RESOURCE_GROUP `
  --name $POSTGRES_SERVER `
  --query fullyQualifiedDomainName `
  --output tsv

Write-Host "✅ PostgreSQL Host: $POSTGRES_HOST" -ForegroundColor Green

# Build and push images
Write-Host "🔨 Building and pushing backend image..." -ForegroundColor Yellow
Set-Location backend
az acr build --registry $ACR_NAME --image customer-portal-backend:latest . --output none
Set-Location ..

Write-Host "🔨 Building and pushing frontend image..." -ForegroundColor Yellow  
Set-Location frontend
az acr build --registry $ACR_NAME --image customer-portal-frontend:latest . --output none
Set-Location ..

# Create VNet-integrated Container App Environment
Write-Host "🌐 Creating VNet-integrated Container App Environment..." -ForegroundColor Yellow
az containerapp env create `
  --name $ENVIRONMENT_NAME `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --infrastructure-subnet-resource-id $SUBNET_ID

# Create backend container app
Write-Host "🔧 Creating backend Container App..." -ForegroundColor Yellow
az containerapp create `
  --name backend-api `
  --resource-group $RESOURCE_GROUP `
  --environment $ENVIRONMENT_NAME `
  --image "$ACR_LOGIN_SERVER/customer-portal-backend:latest" `
  --target-port 3001 `
  --ingress external `
  --registry-server $ACR_LOGIN_SERVER `
  --registry-username $ACR_USERNAME `
  --registry-password $ACR_PASSWORD `
  --secrets "db-host=$POSTGRES_HOST" "db-user=$DB_USER" "db-password=$DB_PASSWORD" "db-name=$DB_NAME" `
  --env-vars "DB_HOST=secretref:db-host" "DB_USER=secretref:db-user" "DB_PASSWORD=secretref:db-password" "DB_NAME=secretref:db-name" "DB_PORT=5432" `
  --cpu 0.25 --memory 0.5Gi `
  --min-replicas 1 --max-replicas 5

# Get backend URL
$BACKEND_URL = az containerapp show `
  --name backend-api `
  --resource-group $RESOURCE_GROUP `
  --query properties.configuration.ingress.fqdn `
  --output tsv

Write-Host "✅ Backend API URL: https://$BACKEND_URL" -ForegroundColor Green

# Create frontend container app
Write-Host "🔧 Creating frontend Container App..." -ForegroundColor Yellow
az containerapp create `
  --name frontend-web `
  --resource-group $RESOURCE_GROUP `
  --environment $ENVIRONMENT_NAME `
  --image "$ACR_LOGIN_SERVER/customer-portal-frontend:latest" `
  --target-port 80 `
  --ingress external `
  --registry-server $ACR_LOGIN_SERVER `
  --registry-username $ACR_USERNAME `
  --registry-password $ACR_PASSWORD `
  --env-vars "REACT_APP_API_URL=https://$BACKEND_URL" `
  --cpu 0.25 --memory 0.5Gi `
  --min-replicas 1 --max-replicas 3

# Get frontend URL  
$FRONTEND_URL = az containerapp show `
  --name frontend-web `
  --resource-group $RESOURCE_GROUP `
  --query properties.configuration.ingress.fqdn `
  --output tsv

# Display summary
Write-Host ""
Write-Host "=================================="
Write-Host "✅ VNet-Integrated Container Apps Deployed!"
Write-Host "==================================" 
Write-Host ""
Write-Host "🌐 Application URLs:" -ForegroundColor Green
Write-Host "   Frontend: https://$FRONTEND_URL" -ForegroundColor Cyan
Write-Host "   Backend API: https://$BACKEND_URL" -ForegroundColor Cyan
Write-Host "   Health Check: https://$BACKEND_URL/health" -ForegroundColor Cyan
Write-Host ""
Write-Host "🐘 Database:" -ForegroundColor Green  
Write-Host "   Server: $POSTGRES_HOST" -ForegroundColor Cyan
Write-Host "   Database: $DB_NAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 VNet Architecture:" -ForegroundColor Green
Write-Host "   ├── VNet: vnet-containerapp (10.0.0.0/16)" -ForegroundColor Cyan
Write-Host "   ├── PostgreSQL subnet: 10.0.1.0/24" -ForegroundColor Cyan
Write-Host "   ├── Container Apps subnet: 10.0.2.0/23" -ForegroundColor Cyan
Write-Host "   └── Private DNS: privatelink.postgres.database.azure.com" -ForegroundColor Cyan
Write-Host ""
Write-Host "🗑️  To clean up:" -ForegroundColor Yellow
Write-Host "   az group delete --name $RESOURCE_GROUP --yes"
Write-Host "=================================="