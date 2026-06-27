# GKE Load Balancer Provisioning

This document explains how Google Kubernetes Engine (GKE) provisions Layer 4 (L4) and Layer 7 (L7) Load Balancers in Google Cloud Platform (GCP).

In GKE, load balancer provisioning is declarative: you define Kubernetes resources (`Service`, `Ingress`, or `Gateway`), and GKE controllers automatically provision and manage the corresponding GCP infrastructure.

---

## 1. Layer 4 Load Balancers (TCP/UDP)

L4 load balancers are provisioned using Kubernetes **Service** resources.

```
Kubernetes Service (Type: LoadBalancer) 
       │
       ▼ (Monitored by GKE Service Controller)
┌────────────────────────────────────────┐
│      Google Cloud L4 Load Balancer     │
│                                        │
│  [Forwarding Rule] (IP Address)        │
│          │                             │
│          ▼                             │
│  [Backend Service / Target Pool]       │
│          │                             │
│          ▼                             │
│  [Health Check]                        │
└────────────────────────────────────────┘
```

### How to Provision
1. Create a `Service` with `spec.type: LoadBalancer`.
2. Define whether it should be **Internal** or **External**:
   * **External (Default)**: Provisions an External Passthrough Network Load Balancer (NetLB).
   * **Internal**: Provisions an Internal Passthrough Network Load Balancer (ILB). This is triggered by adding the annotation `cloud.google.com/load-balancer-type: "Internal"` or setting `spec.loadBalancerClass` to `networking.gke.io/l4-regional-internal`.

### GCP Resources Created
* **Forwarding Rule**: Allocates the IP address (either a public IP or an internal VPC IP).
* **Backend Service** (or Target Pool for legacy configurations): Manages the destination targets (nodes/VMs).
* **Health Check**: Monitors the health of the nodes or pods.
* **Firewall Rules**: Automatically created to allow health check traffic and client traffic to the nodes.

### Backend Routing Modes
* **Instance Groups (Legacy)**: Traffic is sent to the GKE node VMs. The node then routes traffic to the Pod using kube-proxy (iptables/IPVS).
* **Network Endpoint Groups (NEGs)**: Enabled by default in newer GKE versions (via "GKE Subsetting"). Traffic is routed directly to the node IPs using zonal NEGs, improving scalability.

---

## 2. Layer 7 Load Balancers (HTTP/HTTPS)

L7 load balancers are provisioned using Kubernetes **Ingress** or **Gateway** (Gateway API) resources.

```
Kubernetes Ingress / Gateway
       │
       ▼ (Monitored by GKE Ingress/Gateway Controller)
┌────────────────────────────────────────┐
│      Google Cloud L7 Load Balancer     │
│                                        │
│  [Forwarding Rule] (Frontend IP)       │
│          │                             │
│          ▼                             │
│  [Target HTTP/HTTPS Proxy]             │
│          │                             │
│          ▼                             │
│  [URL Map] (Routing Rules)             │
│          │                             │
│          ▼                             │
│  [Backend Services] (using NEGs)       │
│          │                             │
│          ▼                             │
│  [Health Checks]                       │
└────────────────────────────────────────┘
```

### How to Provision
1. **GKE Ingress**: Create an `Ingress` resource defining host/path routing rules.
   * **External**: Use the ingress class `gce` (provisions a Global external Application Load Balancer).
   * **Internal**: Use the ingress class `gce-internal` (provisions a Regional internal Application Load Balancer). *Requires a proxy-only subnet in the VPC.*
2. **GKE Gateway API**: Create a `Gateway` resource (defining the entry point) and `HTTPRoute` resources (defining routing rules).
   * Uses class names like `gke-l7-gxlb` (global external) or `gke-l7-rilb` (regional internal).

### GCP Resources Created
* **Forwarding Rule**: The entry point IP address.
* **Target HTTP/HTTPS Proxy**: Terminates TLS (if configured) and passes requests to the URL map.
* **URL Map**: Implements the routing rules defined in the Ingress/Gateway (matching host/path to backend services).
* **Backend Services**: GKE automatically creates a Backend Service for each Kubernetes Service. It uses **Network Endpoint Groups (NEGs)** to route traffic directly to Pod IPs (container-native load balancing), bypassing kube-proxy.
* **Health Checks**: Configured for each backend service to monitor Pod readiness.
* **Firewall Rules**: Created to allow Google Front Ends (GFEs) or Envoy proxies to perform health checks and forward traffic to the GKE nodes.
* **SSL Certificates**: Provisions Google-managed SSL certificates or attaches self-managed certs from Kubernetes Secrets.

---

## 3. TLS/SSL Offloading (Termination)

TLS offloading (or termination) is the process of decrypting SSL/TLS traffic at the load balancer level before sending it to the backend servers (Pods). This reduces the CPU load on the Pods.

| Feature / Capability | Layer 4 Load Balancers | Layer 7 Load Balancers |
| :--- | :--- | :--- |
| **TLS Offloading Support** | **No** (by default in GKE) / **Yes** (limited/manual via GCP Proxy LBs) | **Yes** (fully supported and managed by GKE) |
| **How it works** | Passthrough L4 LBs do not terminate TCP connections. Packets are routed directly to nodes. TLS must be handled by the application in the Pod. | The LB terminates the TLS connection at the GFE (Google Frontend) or Envoy proxy, then sends decrypted (or re-encrypted) traffic to the Pods. |
| **GKE Configuration** | N/A (handled inside Pod application code) | Configured via `Ingress` (using `tls` block with Secrets) or `Gateway` (using `listeners.tls` configuration) and GCP `FrontendConfig` (for SSL Policies). |
| **Certificate Management** | N/A | Supports Google-managed certificates (automatic renewal) and self-managed certificates (stored as Kubernetes Secrets). |

### Note on L4 Proxy Load Balancers
While GCP supports **L4 Proxy Load Balancers** (SSL Proxy and TCP Proxy) which *can* terminate TLS, GKE's default integration for `Service` of `type: LoadBalancer` only provisions **Passthrough** L4 Load Balancers. To achieve TLS offloading in GKE, it is highly recommended to use **L7 Load Balancers** (Ingress or Gateway API).
