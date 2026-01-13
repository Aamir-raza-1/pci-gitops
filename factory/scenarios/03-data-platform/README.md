# scenarios/03-data-platform/README.md
# Scenario 3: The "Data & Analytics Platform"

## Business Case
A data science team (`gamma`) requires a powerful, dedicated environment for running large-scale data processing jobs with Spark and Hadoop.

## Technical Choices
*   **`infra.dataproc.enabled: true`**: The core of this blueprint. It provisions a `DataprocCluster` with a specified number of master and worker nodes.
*   **`infra.storage.enabled: true`**: A dedicated `StorageBucket` is created for staging input data and storing output results for the Dataproc jobs.
*   **Focused Services:** This blueprint is purpose-built. It enables only the necessary APIs (Compute, Dataproc, Storage) and omits other services like GKE or Cloud SQL to reduce cost and complexity.
