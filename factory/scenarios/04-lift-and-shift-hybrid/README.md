# scenarios/04-lift-and-shift-hybrid/README.md
# Scenario 4: The "Lift & Shift" (Hybrid Connectivity)

## Business Case
An existing application is being migrated from an on-premises data center. The `delta` tenant requires a dedicated VPC configured to connect back to the corporate network.

## Technical Choices
*   **`network.dedicated.router.enabled: true`**: This is the key component. It provisions a `ComputeRouter` with a specified BGP ASN, preparing it for peering with an on-premise VPN or Interconnect.
*   **Specific CIDR:** The subnet CIDR (`10.50.1.0/24`) is carefully chosen to avoid conflicts with on-premise IP ranges.
*   **Minimalist:** This blueprint is network-focused. It does not provision any GKE, database, or application services, assuming those will be handled by a different process (e.g., migrating VMs).
