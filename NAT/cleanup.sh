#!/bin/bash
# Cleanup script for GKE PSC SNAT validation scenario

set -euo pipefail

REGION="us-central1"
VPC_NAME="gke-psc-vpc"
SUBNET_NAME="gke-subnet"
CLUSTER_NAME="psc-test-cluster"
FORWARDING_RULE_NAME="gcspsc"
ADDRESS_NAME="gcs-psc-ip"
DNS_ZONE_NAME="googleapis-private"
FIREWALL_POLICY_NAME="gke-psc-policy"
FIREWALL_ASSOCIATION_NAME="gke-psc-association"
ROUTER_NAME="gke-router"
NAT_NAME="gke-nat"

echo "=== Starting Teardown ==="

echo "1. Deleting GKE Cluster (this will take some time)..."
gcloud container clusters delete "$CLUSTER_NAME" --region="$REGION" --quiet || echo "Cluster already deleted or failed to delete."

echo "2. Deleting PSC Forwarding Rule..."
gcloud compute forwarding-rules delete "$FORWARDING_RULE_NAME" --global --quiet || echo "Forwarding rule already deleted."

echo "3. Deleting PSC Reserved IP Address..."
gcloud compute addresses delete "$ADDRESS_NAME" --global --quiet || echo "IP address already deleted."

echo "4. Deleting DNS records and Zone..."
gcloud dns record-sets delete "*.googleapis.com." --zone="$DNS_ZONE_NAME" --type=A --quiet || echo "DNS record already deleted."
gcloud dns managed-zones delete "$DNS_ZONE_NAME" --quiet || echo "DNS zone already deleted."

echo "5. Deleting Network Firewall Policy Association..."
gcloud compute network-firewall-policies associations delete \
    --firewall-policy="$FIREWALL_POLICY_NAME" \
    --name="$FIREWALL_ASSOCIATION_NAME" \
    --global-firewall-policy \
    --quiet || echo "Firewall association already deleted."

echo "6. Deleting Network Firewall Policy..."
gcloud compute network-firewall-policies delete "$FIREWALL_POLICY_NAME" --global --quiet || echo "Firewall policy already deleted."

echo "7. Deleting Cloud NAT..."
gcloud compute routers nats delete "$NAT_NAME" --router="$ROUTER_NAME" --region="$REGION" --quiet || echo "Cloud NAT already deleted."

echo "8. Deleting Cloud Router..."
gcloud compute routers delete "$ROUTER_NAME" --region="$REGION" --quiet || echo "Cloud router already deleted."

echo "9. Deleting Subnet..."
gcloud compute networks subnets delete "$SUBNET_NAME" --region="$REGION" --quiet || echo "Subnet already deleted."

echo "10. Deleting remaining VPC firewall rules..."
# Detect and delete any auto-created firewall rules associated with the VPC
FW_RULES=$(gcloud compute firewall-rules list --filter="network=$VPC_NAME" --format="value(name)")
if [ -n "$FW_RULES" ]; then
    echo "Found remaining firewall rules to delete:"
    echo "$FW_RULES"
    echo "$FW_RULES" | xargs gcloud compute firewall-rules delete --quiet
else
    echo "No remaining firewall rules found."
fi

echo "11. Deleting VPC..."
gcloud compute networks delete "$VPC_NAME" --quiet || echo "VPC already deleted."

echo "=== Teardown Complete ==="
