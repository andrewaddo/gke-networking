#!/bin/bash

# Set directory to script location
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR"

echo "Creating TLS configuration resources..."

# 1. Create ConfigMap from nginx.conf
kubectl create configmap nginx-config-tls --from-file=nginx.conf=nginx.conf --dry-run=client -o yaml | kubectl apply -f -

# 2. Generate self-signed certs
echo "Generating self-signed SSL certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key \
    -out tls.crt \
    -subj "/CN=nginx-tls-sample/O=GKE-Networking-Test"

# 3. Create Secret from certs
kubectl create secret generic nginx-ssl-certs \
    --from-file=tls.crt=tls.crt \
    --from-file=tls.key=tls.key \
    --dry-run=client -o yaml | kubectl apply -f -

# Clean up local cert files
rm tls.key tls.crt

# 4. Apply Deployment and Service
echo "Deploying Nginx and L4 Service..."
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

echo "Setup applied successfully!"
echo "Wait for the LoadBalancer IP to be provisioned using: kubectl get svc nginx-tls-service -w"
