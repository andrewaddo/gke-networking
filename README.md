# GKE Networking Best Practices & Design

This repository is dedicated to exploring and documenting best practices and design recommendations for GKE networking, specifically focusing on NAT, DNS, and foundational configurations.

## Repository Structure

*   **[foundation/](file:///usr/local/google/home/ducdo/workspace/gke-networking/foundation/)**: Contains foundational GKE manifests and configurations (e.g., Nginx deployments, basic configs).
*   **[NAT/](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/)**: Research, design, and best practices for NAT (SNAT), Cloud NAT, and `ip-masq-agent`.
    *   [NAT Best Practices Guide](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/best-practices.md)
    *   [Scenario: SNAT for GCS via PSC](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/psc-gcs-snat.md)
*   **[DNS/](file:///usr/local/google/home/ducdo/workspace/gke-networking/DNS/)**: Research, design, and best practices for DNS resolution, Cloud DNS, and NodeLocal DNSCache.
    *   [DNS Best Practices Guide](file:///usr/local/google/home/ducdo/workspace/gke-networking/DNS/best-practices.md)

## Key Focus Areas

### 1. Egress Traffic Management (NAT)
Optimizing outbound traffic to the internet and internal private networks using Cloud NAT and IP Masquerade Agent. Key goals include avoiding port exhaustion and maintaining IP visibility where needed.

### 2. Name Resolution (DNS)
Ensuring reliable and low-latency DNS resolution within the cluster and VPC using Cloud DNS and NodeLocal DNSCache, and optimizing application-level DNS settings.
