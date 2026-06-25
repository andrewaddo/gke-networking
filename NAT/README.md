# GKE Networking: NAT (SNAT)

This folder contains research, design documentation, and configuration templates for GKE NAT (Source NAT) scenarios.

## Contents

*   **[best-practices.md](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/best-practices.md)**: General best practices for GKE NAT, covering Cloud NAT (Dynamic Port Allocation, PGA) and IP Masquerade Agent.
*   **[psc-gcs-snat.md](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/psc-gcs-snat.md)**: Detailed step-by-step scenario guide for routing GKE Autopilot traffic to GCS via Private Service Connect (PSC) with SNAT/Firewall options.

## Manifests & Scripts

*   [cleanup.sh](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/cleanup.sh): Bash script to tear down all created infrastructure.
*   [validation-pod.yaml](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/validation-pod.yaml): Test Pod for validating connectivity.
*   [egress-nat-policy-sol1.yaml](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/egress-nat-policy-sol1.yaml): SNAT configuration to force masquerading to PSC IP.
*   [egress-nat-policy-default.yaml](file:///usr/local/google/home/ducdo/workspace/gke-networking/NAT/egress-nat-policy-default.yaml): Default SNAT policy (restores baseline).
