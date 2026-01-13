# tests/layers/03-core-infra/README.md
# Layer 3 Test: Core Infrastructure

This test validates the core infrastructure layer, including databases and GKE.

**Given:** A request for a project with a network, a GKE cluster, a PostgreSQL instance, and a MySQL instance.
**When:** `helm template` is run.
**Then:** The output should contain all resources from Layers 1 & 2, PLUS `ContainerCluster`, and two `SQLInstance` resources.
