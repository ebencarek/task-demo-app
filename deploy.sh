# File: deploy.sh
#!/bin/bash

RESOURCE_GROUP="rg-demo-app"
AKS_CLUSTER="aks-demo-portal" 
ACR_NAME="acrcustomerportal"

echo "Deploying Customer Portal with latency issue..."

# Create resources
az group create --name $RESOURCE_GROUP --location eastus
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
az acr build --registry $ACR_NAME --image customer-portal:latest .

# Create AKS
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --node-count 2 \
  --attach-acr $ACR_NAME \
  --generate-ssh-keys

# Deploy
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER
sed -i "s/your-registry/$ACR_NAME.azurecr.io/g" k8s-manifests.yaml
kubectl apply -f k8s-manifests.yaml

echo "Deployment complete. The webapp will be slow due to expensive database queries."
echo "Get external IP: kubectl get service customer-portal-service -n customer-portal"