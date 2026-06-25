# Scenario Guide: GKE Autopilot to GCS via PSC (SNAT vs. Firewall)

This guide walks through setting up the infrastructure, validating default behavior, and resolving connectivity from a GKE Autopilot cluster to Google Cloud Storage (GCS) via a Private Service Connect (PSC) endpoint.

We explore two distinct solutions to resolve connectivity when egress traffic is restricted:
*   **Solution 1**: Modify GKE **SNAT policy** to masquerade Pod traffic to Node IPs.
*   **Solution 2**: Modify the **VPC Firewall** to allow Pod IP ranges directly.

---

## 1. Infrastructure Setup

Follow these steps to create the necessary Google Cloud resources.

### 1.1. Create VPC and Subnet
Create a VPC network and a subnet with secondary ranges for GKE Pods and Services.

```bash
# Create VPC
gcloud compute networks create gke-psc-vpc --subnet-mode=custom

# Create Subnet with secondary ranges
gcloud compute networks subnets create gke-subnet \
    --network=gke-psc-vpc \
    --region=us-central1 \
    --range=10.128.0.0/20 \
    --secondary-range=pods=10.48.0.0/14,services=10.52.0.0/20 \
    --enable-private-ip-google-access
```

#### Subnet Parameter Breakdown:
*   **`gke-subnet`**: The name of the subnet being created.
*   **`--network=gke-psc-vpc`**: Binds this subnet to the VPC network we created.
*   **`--region=us-central1`**: The regional location of the subnet. GKE cluster resources must reside in the same region.
*   **`--range=10.128.0.0/20`**: The **Primary IP Range**. In GKE, this range is dedicated to the **GKE Nodes** (the virtual machine hosts). A `/20` subnet provides 4,094 usable IP addresses.
*   **`--secondary-range`**: GKE uses **VPC-native** networking. This defines **secondary IP ranges** which are **NOT sub-ranges (children) of the primary range**. They are separate, non-overlapping CIDR blocks allocated to the same subnet:
    *   **`pods=10.48.0.0/14`**: A separate sibling range from which **Pod IPs** are allocated. A `/14` range provides 262,144 IP addresses.
    *   **`services=10.52.0.0/20`**: A separate sibling range from which **Kubernetes Services (ClusterIPs)** are allocated. A `/20` range provides 4,096 IP addresses.
    *   *Note: All three ranges (Primary Node, Secondary Pod, Secondary Service) must be completely distinct and must not overlap with any other CIDRs in the VPC.*
*   **`--enable-private-ip-google-access`**: Enables **Private Google Access (PGA)** on this subnet.

#### What does `--enable-private-ip-google-access` explicitly do?

When a VM or GKE Node has **only a private IP address** (no external/public IP), it cannot communicate with the public internet because public routers don't know how to route responses back to private RFC 1918 IPs.

Enabling Private Google Access (PGA) changes this behavior *specifically for Google APIs*:

1.  **DNS Resolution**: When a Pod/Node queries DNS for `storage.googleapis.com`, it still receives Google's **public IP addresses** (just like any machine on the internet).
2.  **Routing Interception**: When the Pod sends a packet to that public IP, the Google Cloud virtual router in the VPC intercepts the packet because PGA is enabled on the subnet.
3.  **Internal Routing**: Instead of dropping the packet or trying to route it to the internet (which would fail without a public IP or NAT), the VPC router forwards the packet **directly to Google's internal production network** over the Google backbone.
4.  **Response**: Google services process the request and route the response back to the private IP of your Node/Pod.

**Explicit Effect**: It allows private-IP-only resources in the subnet to consume Google services (GCS, Artifact Registry, BigQuery, etc.) without needing a public IP, Cloud NAT, or a VPN/Interconnect. It does *not* grant access to non-Google public websites.

---

#### Note on Private Google Access (PGA) vs. Private Service Connect (PSC)
While we enable `--enable-private-ip-google-access` (PGA) on the subnet, it is important to understand the distinction between PGA and PSC:

*   **Private Google Access (PGA)**: Allows VMs/Nodes with only internal IP addresses to reach Google APIs using their *default public IP addresses* (e.g., resolving `storage.googleapis.com` to public IPs, but Google routes the traffic internally). PGA is a regional setting enabled at the subnet level.
*   **Private Service Connect (PSC)**: Creates a *specific private IP address* (`10.150.0.100` in our case) inside your VPC to represent the Google APIs. You then use DNS to route traffic to this IP.
*   **Relationship in this Scenario**: 
    *   PSC does **not** strictly require PGA to be enabled to function, because PSC traffic is routed to an IP address within your VPC.
    *   However, we enable PGA on the GKE subnet as a **best practice** for GKE. This ensures that any Google API traffic *not* explicitly routed to the PSC endpoint (or during cluster bootstrapping before DNS is active) can still reach Google APIs privately.
    *   In this validation scenario, we are explicitly testing traffic routing to the **PSC endpoint** (via DNS resolution to `10.150.0.100`), which allows us to apply VPC Firewall rules to it. PGA traffic (using public IPs) would bypass these specific VPC firewall rules targeting the PSC IP.

### 1.2. Create Cloud NAT (Required for Private Nodes to pull images)
Private GKE nodes do not have public IPs. We need Cloud NAT to allow them to pull the test image from external registries.

```bash
# Create Cloud Router
gcloud compute routers create gke-router \
    --network=gke-psc-vpc \
    --region=us-central1

# Create Cloud NAT Gateway
gcloud compute routers nats create gke-nat \
    --router=gke-router \
    --region=us-central1 \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges
```

### 1.3. Create GKE Autopilot Cluster
Create a private GKE Autopilot cluster, explicitly pointing it to the secondary ranges we created in the subnet.

```bash
gcloud container clusters create-auto psc-test-cluster \
    --region=us-central1 \
    --network=gke-psc-vpc \
    --subnetwork=gke-subnet \
    --cluster-secondary-range-name=pods \
    --services-secondary-range-name=services \
    --enable-private-nodes
```
*Note: If you do not specify `--cluster-secondary-range-name` and `--services-secondary-range-name`, GKE Autopilot will automatically allocate new secondary ranges for you (e.g., `gke-psc-test-cluster-pods-xxxx`). If that happens, you must find the actual allocated range and use it in your firewall rules instead of `10.48.0.0/14`.*


### 1.4. Create Private Service Connect (PSC) for Google APIs
Reserve a private IP and create a forwarding rule to route Google API traffic (including GCS) to a private endpoint.

```bash
# Reserve IP address for PSC (outside subnet ranges, but within VPC)
gcloud compute addresses create gcs-psc-ip \
    --global \
    --purpose=PRIVATE_SERVICE_CONNECT \
    --addresses=10.150.0.100 \
    --network=gke-psc-vpc

# Create Forwarding Rule for all Google APIs
# Note: The name must be 1-20 characters, lowercase letters and numbers only (no hyphens).
gcloud compute forwarding-rules create gcspsc \
    --global \
    --network=gke-psc-vpc \
    --address=gcs-psc-ip \
    --target-google-apis-bundle=all-apis
```

### 1.5. Configure Cloud DNS for googleapis.com
Configure DNS so that workloads automatically resolve `*.googleapis.com` to the PSC IP (`10.150.0.100`).

```bash
# Create Private DNS Zone
gcloud dns managed-zones create googleapis-private \
    --dns-name=googleapis.com. \
    --description="Private zone for Google APIs PSC" \
    --visibility=private \
    --networks=gke-psc-vpc

# Add wildcard A record pointing to PSC IP
gcloud dns record-sets create "*.googleapis.com." \
    --zone=googleapis-private \
    --type=A \
    --ttl=300 \
    --rrdatas=10.150.0.100
```

---

## 2. Baseline Firewall Setup (Strict Egress via Network Firewall Policy)

To restrict egress traffic based on the packet's source IP (Pod IP vs. Node IP), we must use **Network Firewall Policies**. Legacy VPC firewall rules do not support filtering by source IP range for egress traffic.

### 2.1. Create and Associate the Firewall Policy
Create a global network firewall policy and associate it with our VPC.

```bash
# 1. Create a global network firewall policy
gcloud compute network-firewall-policies create gke-psc-policy \
    --global \
    --description="Firewall policy for GKE PSC validation"

# 2. Associate the policy with our VPC network
gcloud compute network-firewall-policies associations create \
    --firewall-policy=gke-psc-policy \
    --network=gke-psc-vpc \
    --name=gke-psc-association \
    --global-firewall-policy
```

### 2.2. Create Policy Rules
We define rules to deny egress from the Pod CIDR to the PSC IP, while allowing egress from the Node CIDR.

```bash
# Rule 1: Deny Pod Egress to PSC IP (Priority 1000)
# Matches source Pod IP (10.48.0.0/14) going to PSC IP (10.150.0.100/32)
gcloud compute network-firewall-policies rules create 1000 \
    --firewall-policy=gke-psc-policy \
    --direction=EGRESS \
    --action=DENY \
    --dest-ip-ranges=10.150.0.100/32 \
    --src-ip-ranges=10.48.0.0/14 \
    --layer4-configs=tcp:443 \
    --global-firewall-policy

# Rule 2: Allow Node Egress to PSC IP (Priority 900 - Higher Priority)
# Matches source Node IP (10.128.0.0/20) going to PSC IP (10.150.0.100/32)
gcloud compute network-firewall-policies rules create 900 \
    --firewall-policy=gke-psc-policy \
    --direction=EGRESS \
    --action=ALLOW \
    --dest-ip-ranges=10.150.0.100/32 \
    --src-ip-ranges=10.128.0.0/20 \
    --layer4-configs=tcp:443 \
    --global-firewall-policy
```

---

## 3. Verify the Failed State (Default Behavior)

By default, GKE Autopilot does **not** perform SNAT (masquerading) for traffic destined for RFC 1918 ranges (like our PSC IP `10.150.0.100`).

### Step 3.1: Deploy the Test Pod
Deploy a test pod to simulate the workload:

```yaml
# Save as NAT/validation-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gcs-validation-pod
  namespace: default
spec:
  containers:
  - name: cloud-sdk
    image: google/cloud-sdk:slim
    command: ["sleep", "3600"]
```
```bash
kubectl apply -f NAT/validation-pod.yaml
```

### Step 3.2: Test Connectivity
Exec into the pod and attempt to connect to GCS. Thanks to Cloud DNS, we can use the standard URL:

```bash
kubectl exec -it gcs-validation-pod -- bash
```

Inside the pod, run:
```bash
curl -v --connect-timeout 5 https://storage.googleapis.com
```

### Expected Result (Failure)
The connection should **timeout**:
```
* Connecting to storage.googleapis.com (10.150.0.100) port 443 (#0)
* Connection timed out after 5001 milliseconds
* Closing connection 0
curl: (28) Connection timed out after 5001 milliseconds
```
*Note: The output confirms `storage.googleapis.com` resolved to the PSC IP `10.150.0.100`.*

### Why it failed:
1.  The destination IP (`10.150.0.100`) is in RFC 1918.
2.  GKE's default policy is `NoSNAT` for RFC 1918, so the packet leaves the Node with the source IP of the Pod (`10.48.0.x`).
3.  VPC Firewall **Rule 1** (`deny-pod-to-psc`) matches the source Pod IP and **denies** the egress traffic.

---

## 4. Solution 1: Force SNAT via EgressNATPolicy

This solution keeps the firewall strict (blocking Pod IPs) and forces GKE to translate Pod IPs to Node IPs for traffic going to the PSC endpoint.

### Step 4.1: Apply Custom EgressNATPolicy
We modify the `default` `EgressNATPolicy` to exclude the PSC subnet from the `NoSNAT` list. This forces GKE to SNAT traffic destined for the PSC IP.

```yaml
# Save as NAT/egress-nat-policy-sol1.yaml
apiVersion: networking.gke.io/v1
kind: EgressNATPolicy
metadata:
  name: default
spec:
  action: NoSNAT
  destinations:
  # We list only the ranges we want to KEEP Pod IP visibility for:
  - cidr: 10.48.0.0/14   # Pod CIDR
  - cidr: 10.128.0.0/20  # Node CIDR (Example range)
  # 10.150.0.0/24 (PSC) is omitted, meaning it WILL be SNATed.
```
```bash
kubectl apply -f NAT/egress-nat-policy-sol1.yaml
```
*Note: It may take up to 1-2 minutes for Dataplane V2 to apply the policy changes to all nodes.*

### Step 4.2: Verify Connectivity
Exec back into the validation pod and test again:

```bash
kubectl exec -it gcs-validation-pod -- bash
```
```bash
curl -v --connect-timeout 5 https://storage.googleapis.com/storage/v1/b
```

### Expected Result (Success)
The connection should now succeed (returning a 401 or 403 API response, but not timing out):
```
* Connected to storage.googleapis.com (10.150.0.100) port 443 (#0)
...
< HTTP/2 401 
...
{"error":{"code":401,"message":"Anonymous caller does not have storage.buckets.list access...
```

### Why it succeeded:
1.  The traffic to `10.150.0.100` did not match the `NoSNAT` list in our new policy.
2.  GKE SNATed the packet source from Pod IP (`10.48.0.x`) to Node IP (`10.128.0.y`).
3.  VPC Firewall Policy **Rule 900** allowed the egress because the source was now the Node IP.

---

## 5. Solution 2: Allow Pod IPs in Firewall (Alternative)

This solution reverts the GKE SNAT policy to default (no SNAT for RFC 1918) and instead updates the firewall to allow Pod IPs to reach the PSC endpoint directly.

### Step 5.1: Revert EgressNATPolicy to Default (Reset Environment)
Revert the policy so that GKE does **not** perform SNAT for RFC 1918 ranges (including the PSC).

```yaml
# Save as NAT/egress-nat-policy-default.yaml
apiVersion: networking.gke.io/v1
kind: EgressNATPolicy
metadata:
  name: default
spec:
  action: NoSNAT
  destinations:
  - cidr: 10.0.0.0/8
  - cidr: 172.16.0.0/12
  - cidr: 192.168.0.0/16
```
```bash
kubectl apply -f NAT/egress-nat-policy-default.yaml
```

#### Verify Reverted (Failed) State
Before applying the firewall fix, verify that connectivity is once again **blocked** (proving the environment has been successfully reset):
```bash
kubectl exec -it gcs-validation-pod -- bash
# Inside pod:
curl -v --connect-timeout 5 https://storage.googleapis.com
```
*Expected Result: Connection times out (same as Step 3.2).*

### Step 5.2: Update VPC Firewall Rules (Modify Network Firewall Policy)
Now, modify the firewall policy to allow Pod IPs to reach the PSC endpoint.

We can update the existing deny rule (priority 1000) to ALLOW:

```bash
# Update Rule 1 (priority 1000) action to ALLOW
gcloud compute network-firewall-policies rules update 1000 \
    --firewall-policy=gke-psc-policy \
    --action=ALLOW \
    --global-firewall-policy
```

### Step 5.3: Verify Connectivity
Exec into the pod and test:

```bash
kubectl exec -it gcs-validation-pod -- bash
# Inside pod:
curl -v --connect-timeout 5 https://storage.googleapis.com/storage/v1/b
```

### Expected Result (Success)
The connection succeeds.

### Why it succeeded:
1.  GKE did not SNAT the traffic (retained Pod IP `10.48.0.x`).
2.  The updated VPC Firewall Policy Rule (priority 1000 is now ALLOW) allowed the traffic because we explicitly allowed the Pod CIDR to reach the PSC IP.
3.  The destination (PSC) received the traffic with the Pod IP as the source.

