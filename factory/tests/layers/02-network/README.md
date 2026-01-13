# tests/layers/02-network/README.md
# Layer 2 Test: Networking

This test validates the networking layer on top of the foundation.

**Given:** A request for a project with a dedicated VPC, subnets, and firewall rules.
**When:** `helm template` is run.
**Then:** The output should contain all resources from Layer 1, PLUS `ComputeNetwork`, `ComputeSubnetwork`, and `ComputeFirewall` resources.
