# GKE Upgrade Strategies Guide

This document outlines the various strategies for upgrading Google Kubernetes Engine (GKE) clusters, ranging from node-level upgrades within a single cluster to cluster-level migrations using Multi-Cluster Gateways.

---

## 1. Node Pool Upgrades (Within a Single Cluster)

These strategies are used to upgrade the nodes (VMs) within a single cluster. GKE always upgrades the Control Plane first, followed by the node pools.

### Option A: Surge Upgrades (Rolling)
*Supported in: Autopilot (Fixed) & Standard (Default)*

GKE upgrades nodes in a rolling fashion, one by one (or in small batches).

*   **How it works (e.g., `maxSurge=1`, `maxUnavailable=0`):**
    1.  GKE creates 1 new "surge" node running the new version.
    2.  GKE cordons and drains 1 old node.
    3.  Pods are rescheduled onto the surge node.
    4.  The old node is deleted.
    5.  This repeats sequentially.
*   **IP/Resource Cost:** **Low.** Requires only `maxSurge` extra Node IPs and Pod CIDR blocks (e.g., 1 extra node's worth).
*   **Pros:** Cost-effective, works well when IP space is limited.
*   **Cons:** Slow for large clusters; hard to rollback if a failure occurs late in the process.

### Option B: Blue-Green Upgrades (Pool-by-Pool)
*Supported in: Standard Only*

GKE duplicates the entire node pool to perform the upgrade.

*   **How it works:**
    1.  GKE creates a new node pool (Green) of the same size as the old pool (Blue), running the new version.
    2.  **Soak Phase:** Workloads are gradually moved to the Green pool. Both pools exist simultaneously. You can configure a "soak time" (e.g., 1 hour) to validate application health on the new nodes.
    3.  **Commit/Rollback:** If validation succeeds, the Blue pool is deleted. If it fails, GKE rolls back by moving workloads back to the Blue pool.
*   **IP/Resource Cost:** **High.** Temporarily requires **double (2x)** the Node IPs and Pod CIDR blocks for the pool being upgraded.
*   **Pros:** Safe, provides a clear and fast rollback path, allows validation before committing.
*   **Cons:** Expensive; requires significant IP space and GCP resource quota.

---

## 2. Infrastructure Upgrades vs. Application Deployments (Canary)

It is important to distinguish between **Infrastructure (Node) Upgrades** and **Application Deployments**:

*   **Node Upgrades (Surge, Blue-Green):** These are managed by the GKE control plane to update the underlying VMs. They **do not** natively support Canary routing (e.g., "send 10% of user traffic to the new nodes") because Kubernetes services load-balance traffic across pods, regardless of which node they reside on.
*   **Application Deployments (Canary, Blue-Green):** These are managed by developers using Kubernetes resources to route traffic between different versions of an *application* (e.g., v1.0.0 vs v1.1.0). This is achieved using:
    *   **Kubernetes Gateway API** (splitting traffic via `HTTPRoute` weights).
    *   **Service Meshes** (e.g., Istio / Anthos Service Mesh).
    *   **Ingress Controllers** (e.g., Nginx Ingress Canary).

---

## 3. Multi-Cluster Upgrade Strategy (Cluster-Level Blue-Green)
*Supported in: Standard & Autopilot (via Fleets)*

For the lowest-risk, zero-downtime upgrades (especially across major GKE versions), you can perform a **Multi-Cluster Blue-Green Upgrade** using a **Multi-Cluster Gateway (MCG)**.

This strategy treats **entire clusters** as the "Blue" and "Green" environments.

```
                  [ User Traffic ]
                         │
                         ▼
           [ Multi-Cluster Gateway ]
           (Traffic Split: e.g., 90/10)
                 /              \
                ▼                ▼
       [ Blue Cluster ]   [ Green Cluster ]
          (GKE v1.32)        (GKE v1.33)
```

### How it Works:
1.  **Baseline (Blue):** Your application runs on the primary cluster (e.g., running GKE v1.32).
2.  **Expansion (Green):** You provision a completely new, separate GKE cluster running the new version (e.g., GKE v1.33) and deploy your application there.
3.  **Fleet Registration:** Both clusters are registered to the same GKE **Fleet**.
4.  **Multi-Cluster Services (MCS):** You use `ServiceExport` to expose the application across the fleet. GKE automatically creates Multi-Cluster Endpoint Groups (NEGs).
5.  **Multi-Cluster Gateway (MCG):** You deploy a Regional Multi-Cluster Gateway (`gke-l7-regional-external-managed-mc`).
6.  **Canary Traffic Split:** You define an `HTTPRoute` with weights to gradually shift traffic from the Blue cluster to the Green cluster (e.g., 90/10 -> 50/50 -> 0/100).
7.  **Solidify & Cleanup:** Once 100% of traffic is on the Green cluster, you update DNS to point directly to the Green cluster's local load balancer, tear down the MCG, and delete the old Blue cluster.

### Why Use This Option?
*   **True Canary Testing:** You can test how your application behaves on the new GKE version with a small percentage of real user traffic (e.g., 5%).
*   **Isolate Control Plane Risks:** If the new GKE version has a control plane bug that impacts your application, the old cluster remains completely untouched and healthy.
*   **GitOps Native:** The routing rules (`Gateway`, `HTTPRoute`) are Kubernetes manifests, allowing you to manage the entire upgrade via GitOps (ArgoCD/Flux) without manual GCP console changes.
*   **Zero Downtime:** DNS-based transition combined with MCG ensures that traffic shifts seamlessly without dropping connections.

### Trade-offs:
*   **Highest Cost:** You must run two full GKE clusters simultaneously during the transition period.
*   **Complexity:** Requires setting up Fleets, Multi-Cluster Services, and managing DNS transitions.

---

## 4. Application Version Updates

While infrastructure upgrades focus on the GKE nodes and control plane, **Application Version Updates** focus on deploying new versions of your software (e.g., upgrading your app from v1 to v2) running on the cluster.

Here are the primary strategies available in Kubernetes and GKE:

### Option A: Rolling Update (Default)
Kubernetes gradually replaces instances of the old version with the new version.

*   **How it works:**
    1.  A new Pod (v2) is created.
    2.  Once the new Pod is ready (passes readiness probes), GKE terminates one old Pod (v1).
    3.  This repeats until all Pods are running v2.
    *   Configured via `spec.strategy.type: RollingUpdate` in the Deployment manifest.
*   **Downtime:** **No.**
*   **Pros:** Easy to use (default), no extra configuration needed, zero downtime.
*   **Cons:** During the rollout, **both v1 and v2 are running simultaneously** and receiving traffic. Your application must support backward compatibility (e.g., database schema must work with both versions).

### Option B: Recreate
All existing Pods are killed before any new Pods are created.

*   **How it works:**
    1.  GKE terminates all running Pods (v1).
    2.  Once all v1 Pods are dead, GKE starts the new Pods (v2).
    *   Configured via `spec.strategy.type: Recreate` in the Deployment manifest.
*   **Downtime:** **Yes.**
*   **Pros:** Simple; guarantees that v1 and v2 never run at the same time (useful if you have breaking database migrations that cannot run concurrently).
*   **Cons:** Application is completely unavailable during the transition.

### Option C: Blue-Green (Red-Black)
You deploy the new version (Green) alongside the old version (Blue) at full capacity, test it, and then switch traffic.

*   **How it works:**
    1.  You have a Deployment for v1 (Blue) and a Kubernetes `Service` pointing to it.
    2.  You create a second Deployment for v2 (Green) with the same replica count.
    3.  You validate the Green deployment (e.g., via a temporary test service).
    4.  You update the production `Service` selector to point to the Green Pods. Traffic flips instantly.
    5.  Once verified, you delete the Blue deployment.
*   **Downtime:** **No.**
*   **Pros:** Instant rollback (just flip the Service selector back), no version mix in production traffic during the flip.
*   **Cons:** Requires **double (2x) the CPU/Memory resources** temporarily during the deploy.

### Option D: Canary
You deploy a small number of v2 Pods and route a small percentage of traffic to them to test with real users.

*   **How it works:**
    1.  You deploy v2 with a small replica count (e.g., 1 pod vs 9 pods of v1).
    2.  You configure traffic routing to send a percentage of traffic to v2.
    3.  If metrics (error rates, latency) look good, you increase the traffic share and scale up v2 while scaling down v1.
*   **Implementation Options in GKE:**
    *   **Service Mesh (Istio/ASM):** Best for fine-grained control (e.g., route based on HTTP headers, cookies, or exact percentages).
    *   **Gateway API (`HTTPRoute`):** Native GKE L7 load balancing. You define weights in the `HTTPRoute` backend refs:
        ```yaml
        spec:
          rules:
          - backendRefs:
            - name: app-v1
              port: 80
              weight: 90
            - name: app-v2
              port: 80
              weight: 10
        ```
*   **Downtime:** **No.**
*   **Pros:** Lowest risk; allows testing in production with minimal blast radius.
*   **Cons:** Complex to set up and automate (often requires a tool like Argo Rollouts or Keptn).

