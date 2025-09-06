# VNet Integration for Container Apps

## Problem
The Container App environment `env-demo-appcontainerapp0905` is not VNet-integrated, so it cannot reach the PostgreSQL server `psql-final0905.postgres.database.azure.com` which is in a private subnet.

## Current Resources
- **VNet**: `vnet-containerapp` (10.0.0.0/16)
- **PostgreSQL Subnet**: `subnet-postgres` (10.0.1.0/24) - Contains PostgreSQL server
- **Container App Subnet**: `subnet-containerapp` (10.0.2.0/23) - Ready for Container Apps
- **PostgreSQL Server**: `psql-final0905.postgres.database.azure.com` (Private access only)

## Solution Options

### Option 1: Azure Portal (Recommended)
1. **Create New Container App Environment**:
   - Go to Azure Portal → Container Apps → Environments
   - Click "Create"
   - Resource Group: `rg-demo-appcontainerapp0905`
   - Environment Name: `env-vnet0905`
   - Region: `Australia East`
   - **VNet Integration**: 
     - Select existing VNet: `vnet-containerapp`
     - Select subnet: `subnet-containerapp`
   - Create Log Analytics workspace

2. **Recreate Container Apps in New Environment**:
   - Cannot migrate existing apps - must recreate
   - Use same images: `acrcustomercontainerapp0905.azurecr.io/customer-portal-backend:latest` and `frontend:latest`
   - Same environment variables

### Option 2: Azure CLI (Fixed Path)
Run in PowerShell or Command Prompt (not Git Bash):
```powershell
# Create VNet-integrated environment
az containerapp env create `
  --name env-vnet0905 `
  --resource-group rg-demo-appcontainerapp0905 `
  --location australiaeast `
  --infrastructure-subnet-resource-id "/subscriptions/474eaba6-0f3f-4b5a-bae5-a7858bd7c53b/resourceGroups/rg-demo-appcontainerapp0905/providers/Microsoft.Network/virtualNetworks/vnet-containerapp/subnets/subnet-containerapp"

# Recreate backend app in VNet environment
az containerapp create `
  --name backend-api-vnet `
  --resource-group rg-demo-appcontainerapp0905 `
  --environment env-vnet0905 `
  --image acrcustomercontainerapp0905.azurecr.io/customer-portal-backend:latest `
  --target-port 3001 `
  --ingress external `
  --registry-server acrcustomercontainerapp0905.azurecr.io `
  --registry-username acrcustomercontainerapp0905 `
  --registry-password [PASSWORD] `
  --env-vars DB_HOST=psql-final0905.postgres.database.azure.com DB_USER=demoadmin DB_PASSWORD=DemoPassword123! DB_NAME=customerdb DB_PORT=5432 `
  --cpu 0.25 --memory 0.5Gi `
  --min-replicas 1 --max-replicas 3

# Recreate frontend app
az containerapp create `
  --name frontend-web-vnet `
  --resource-group rg-demo-appcontainerapp0905 `
  --environment env-vnet0905 `
  --image acrcustomercontainerapp0905.azurecr.io/customer-portal-frontend:latest `
  --target-port 80 `
  --ingress external `
  --registry-server acrcustainercontainerapp0905.azurecr.io `
  --registry-username acrcustomercontainerapp0905 `
  --registry-password [PASSWORD] `
  --env-vars REACT_APP_API_URL=https://[BACKEND-URL] `
  --cpu 0.25 --memory 0.5Gi
```

### Option 3: Alternative - Enable Public Access (Quick Fix)
This would be simpler but less secure:

1. **Delete current PostgreSQL server**:
```bash
az postgres flexible-server delete --name psql-final0905 --resource-group rg-demo-appcontainerapp0905 --yes
```

2. **Create new PostgreSQL with public access**:
```bash
az postgres flexible-server create \
  --name psql-public0905 \
  --resource-group rg-demo-appcontainerapp0905 \
  --location australiaeast \
  --admin-user demoadmin \
  --admin-password "DemoPassword123!" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15 \
  --public-access All \
  --yes
```

## Current Status
- ✅ VNet and subnets created
- ✅ PostgreSQL server created (private access)
- ✅ Container Apps running (but can't reach database)
- ❌ VNet integration needed for connectivity

## Next Steps
1. Choose one of the options above
2. Test connectivity: `https://[new-backend-url]/health`
3. Initialize database: Click "📊 Analyze Customer Data" on frontend
4. Verify full application functionality

The Git Bash path issue prevents CLI creation, so Azure Portal is the most reliable option.