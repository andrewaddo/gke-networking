# GKE IP Address Planning & Upgrade Strategies

This document explains GKE IP address allocation and how different node pool upgrade strategies (Surge vs. Blue-Green) impact IP address requirements in Autopilot and Standard clusters.

---

## 1. Per-Node IP Allocation (Both Autopilot & Standard)

To prevent issues with **fast IP reuse** (where a new Pod immediately gets the IP of a recently deleted Pod, causing network confusion), GKE allocates a block of IPs to each node that is **roughly double** the maximum number of Pods that node is allowed to run.

*   **Standard Clusters (Default):** The default is `110` max Pods per node. GKE allocates a **`/24` CIDR block (256 IPs)** to each node from the Pod secondary range.
*   **Autopilot Clusters:** GKE manages this dynamically. By default, Autopilot often sets the max Pods per node to `32`, which allocates a **`/26` CIDR block (64 IPs)** to each node.

---

## 2. Upgrade Strategies & IP Requirements

During node pool upgrades, GKE needs extra IP addresses to run the new nodes and pods before the old ones are decommissioned. You can choose different strategies in GKE Standard, while GKE Autopilot is fixed to Surge upgrades.

### The Analogy

*   **Surge Upgrade (Rolling):** Like **remodeling a hotel room-by-room** while guests are still staying there. You build one temporary room (surge node), move guests from Room 1 to it, remodel Room 1, move guests from Room 2 to Room 1, and so on.
    *   *IP Impact:* Low. You only need extra space for the temporary room.
*   **Blue-Green Upgrade (Replacement):** Like **building a brand new hotel wing next door**. You build the entire new wing (Green pool), verify it works, move all guests from the old wing (Blue pool) at once, and then demolish the old wing.
    *   *IP Impact:* High. You temporarily need double the space to run both wings at the same time.

---

### Comparison of Upgrade Strategies

| Dimension | Surge Upgrades (Node-by-Node) | Blue-Green Upgrades (Pool-by-Pool) |
| :--- | :--- | :--- |
| **GKE Mode Support** | **Autopilot** (Fixed) & **Standard** (Default) | **Standard Only** |
| **Resource Cost** | **Low:** Only requires `maxSurge` extra nodes (typically 1). | **High:** Requires doubling the node pool size temporarily. |
| **IP Space Required** | **Low:** Needs only `maxSurge` Node IPs + `maxSurge` Pod CIDR blocks. | **High:** Needs `N` Node IPs + `N` Pod CIDR blocks (where `N` is pool size). |
| **Upgrade Speed** | **Slower:** Nodes are upgraded sequentially. | **Faster:** All new nodes are provisioned at once. |
| **Rollback Safety** | **Harder:** Partial upgrade state if it fails midway. | **Easy:** Instant rollback to intact Blue pool during soak phase. |

---

### Strategy A: Surge Upgrades

Surge upgrades use a rolling method to upgrade nodes. 

*   **How it works (e.g., `maxSurge=1`, `maxUnavailable=0`):**
    1.  GKE provisions **1 new "surge" node** with the new version.
    2.  GKE cordons and drains one old node.
    3.  Pods from the old node are rescheduled onto the new surge node.
    4.  Once the old node is empty, it is deleted.
    5.  This process repeats one node at a time.
*   **IP Requirement:** 
    *   **For `maxSurge=1`:** You need **1 additional Node IP** (for the VM) + **1 additional Pod CIDR block** (e.g., 256 IPs if using `/24` per node) from your secondary range.
*   **Autopilot:** This is the **only** option. GKE manages this automatically (`maxSurge=1`, `maxUnavailable=0`) and it cannot be changed.

### Strategy B: Blue-Green Upgrades (Standard Only)

In a Blue-Green upgrade, GKE duplicates the entire node pool.

*   **How it works:**
    1.  **Provision Green Pool:** GKE creates a new set of nodes (Green) equal in size to the existing pool (Blue).
    2.  **Soak Phase:** GKE begins routing traffic to the Green nodes. Both pools exist simultaneously. You can configure a **soak time** (e.g., 1 hour) to validate workloads.
    3.  **Drain Blue Pool:** If validation succeeds, GKE deletes the Blue nodes. If it fails, GKE rolls back to the Blue nodes.
*   **IP Requirement:** **Requires temporary duplication (2x) of IP resources** for the node pool being upgraded.
    *   *Example:* If you have a node pool with 10 nodes (using `/24` Pod CIDR per node), you need an additional **10 Node IPs** and **10 Pod CIDR blocks (2,560 Pod IPs)** available during the upgrade.

---

## 3. Common Questions

### Q: Does Blue-Green node upgrade use a Load Balancer to route traffic?
**No.** It does not use a GCP Load Balancer to route traffic between the Blue and Green *nodes*. 

Instead, it uses standard **Kubernetes Service Routing**:
1.  As GKE drains Pods from the Blue nodes, those Pods are terminated.
2.  New Pods are started on the Green nodes.
3.  The Kubernetes `Service` (or `Ingress`/`Gateway` via NEGs) automatically detects the new Pods on the Green nodes as endpoints and starts sending traffic to them.
4.  The traffic shift happens naturally at the Pod/Application level, not by configuring a Load Balancer to point to different VMs.

### Q: Can Blue-Green node upgrades support Canary deployments?
**Not natively at the node level.** 

GKE's Blue-Green *node* upgrade is designed for infrastructure maintenance, not application release control. During the "soak phase", both node pools are active, and Kubernetes will load balance traffic across all pods. If you have 5 pods on Blue and 5 pods on Green, traffic is split 50/50. GKE does not provide a way to say "send only 10% of traffic to the Green node pool."

If you want **Canary Deployments** (routing a specific % of user traffic to a new version of your app), you should manage this at the **Application level** using:
*   **Kubernetes Gateway API** (HTTPRoute split)
*   **Service Mesh** (e.g., Istio / Anthos Service Mesh)
*   **Ingress controllers** that support canary annotations (e.g., Nginx Ingress)

### Q: In Surge mode (e.g., `maxSurge=1`), do I just need 1 additional IP?
**No, you need 1 Node IP + 1 Pod CIDR Block.**

A GKE node cannot share Pod IPs with other nodes. Each node must have its own dedicated block of IPs for the Pods it hosts.
*   You need **1 IP** for the node VM itself (from the primary subnet).
*   You need **a block of IPs** (e.g., 256 IPs for a `/24` block) from the secondary Pod range for the Pods that will run on that surge node.
*   If your secondary Pod range is completely full, the surge upgrade will fail because GKE cannot allocate the Pod CIDR block to the new surge node, even if you have plenty of Node IPs left.
