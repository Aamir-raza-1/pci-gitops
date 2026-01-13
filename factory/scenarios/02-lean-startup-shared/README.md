# scenarios/02-lean-startup-shared/README.md
# Scenario 2: The "Lean Startup" (Shared VPC)

## Business Case
A new team (`beta`) needs a non-production environment for rapid development. The primary drivers are cost-effectiveness and speed, leveraging existing shared network resources.

## Technical Choices
*   **`network.mode: "shared"`**: The key feature. This project will be a Service Project attached to a central Shared VPC Host, saving significant cost and management overhead.
*   **`infra.cloud_run.enabled: true`**: Uses a serverless compute model, which is ideal for simple web apps and APIs in a cost-conscious environment.
*   **Minimal Services:** Only enables the Cloud Run and Secret Manager APIs, adhering to the principle of least privilege.
