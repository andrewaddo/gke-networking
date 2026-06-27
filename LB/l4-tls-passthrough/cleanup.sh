#!/bin/bash

# Set directory to script location
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR"

echo "Cleaning up TLS passthrough sample resources..."

kubectl delete -f nginx-service.yaml
kubectl delete -f nginx-deployment.yaml
kubectl delete configmap nginx-config-tls
kubectl delete secret nginx-ssl-certs

echo "Cleanup complete!"
