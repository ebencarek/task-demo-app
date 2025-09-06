#!/bin/bash

# Simplified Azure Container Apps deployment script (without PostgreSQL)
SUFFIX="containerapp$(date +%m%d)"

# Resource names with suffix
RESOURCE_GROUP="rg-demo-app${SUFFIX}"
ACR_NAME="acrcustomer${SUFFIX}"
LOCATION="australiaeast"
ENVIRONMENT_NAME="env-demo-app${SUFFIX}"

echo "🚀 Deploying Customer Portal to Azure Container Apps (Simplified)..."
echo "   Frontend: React + Nginx"
echo "   Backend: Node.js Express API"
echo "   Database: Will connect to existing PostgreSQL or fail gracefully"

# Use existing resource group and ACR if available
echo "📦 Ensuring resource group exists..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

echo "🐳 Ensuring Azure Container Registry exists..."
ACR_EXISTS=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>/dev/null || echo "")
if [ -z "$ACR_EXISTS" ]; then
    az acr create \
      --resource-group $RESOURCE_GROUP \
      --name $ACR_NAME \
      --sku Basic \
      --admin-enabled true \
      --output none
fi

# Get ACR login server and credentials
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv)

echo "✅ ACR Login Server: $ACR_LOGIN_SERVER"

# Build and push backend image
echo "🔨 Building and pushing backend image to ACR..."
cd backend
az acr build --registry $ACR_NAME --image customer-portal-backend:latest . --output none
cd ..

# Build and push frontend image  
echo "🔨 Building and pushing frontend image to ACR..."
cd frontend
az acr build --registry $ACR_NAME --image customer-portal-frontend:latest . --output none
cd ..

# Create Container App Environment
echo "🌐 Creating Container App Environment..."
ENV_EXISTS=$(az containerapp env show --name $ENVIRONMENT_NAME --resource-group $RESOURCE_GROUP --query "name" --output tsv 2>/dev/null || echo "")
if [ -z "$ENV_EXISTS" ]; then
    az containerapp env create \
      --name $ENVIRONMENT_NAME \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION \
      --output none
fi

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
  --env-vars PORT=3001 \
  --cpu 0.25 --memory 0.5Gi \
  --min-replicas 1 --max-replicas 3 \
  --output none

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
  --min-replicas 1 --max-replicas 3 \
  --output none

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
echo "📊 Architecture:"
echo "   ├── Frontend Container App (React + Nginx)"
echo "   ├── Backend Container App (Node.js Express)"
echo "   └── Database: Not configured (will show connection errors)"
echo ""
echo "⚠️  Note: Database is not configured in this simplified deployment."
echo "   The backend will show database connection errors until PostgreSQL is set up."
echo ""
echo "📝 Container App Commands:"
echo "   az containerapp logs show --name backend-api --resource-group $RESOURCE_GROUP"
echo "   az containerapp logs show --name frontend-web --resource-group $RESOURCE_GROUP"
echo ""
echo "🗑️  To clean up all resources:"
echo "   az group delete --name $RESOURCE_GROUP --yes"
echo "=================================="