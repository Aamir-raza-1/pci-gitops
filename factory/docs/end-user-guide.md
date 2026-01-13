# The Tenant Factory: End-User Guide & Backend Workflow

This document is a guide for two primary audiences:
1.  **End-Users (e.g., Developers):** How to request a new environment using the factory.
2.  **Platform Engineers:** A look "behind the curtain" at the backend process for each step.

It also includes a comparison with a conversational, agent-driven infrastructure workflow.

---

## How to Use the Factory to Get a New Environment (End-User Guide)

As a developer, you can get a new, production-ready cloud environment in three simple, Git-based steps.

### Step 1: Describe Your Needs in a `request.yaml` File

Your "request" is a simple YAML file. You don't need to be a cloud expert; you just need to describe what you need.

1.  **Find a Blueprint:** Go to the `scenarios/` directory in this repository. Look through the subdirectories and find a blueprint that most closely matches your needs (e.g., `02-lean-startup-shared` for a simple web app, `03-data-platform` for a Spark job).
2.  **Copy and Customize:** Copy the `request.yaml` from that scenario into a new file. Name it for your application and environment (e.g., `my-app-nonprod.yaml`).
3.  **Edit the File:** Change the values to match your specific requirements.

**Good `request.yaml`:**
```yaml
# You clearly state your tenant code, environment, and the services you need.
tenant_code: "my-app"
environment: "nonprod"
gcp:
  region: "us-central1"
  # ... billing info ...
network:
  mode: "shared" # I want to save costs by using the shared network
infra:
  cloud_run:
    enabled: true # I need a Cloud Run service
    service:
      name: "my-api"
      template:
        containers: [{ image: "gcr.io/my-project/my-api:latest" }]
```

**Vague Request (This will be rejected by our system):**
```yaml
# This is not enough information. The schema validation will fail.
tenant_code: "my-app"
```
> **Pro Tip:** Your request is validated by a schema. If you submit a request with missing required fields (like `gcp.billing_account_id`), the automated pipeline will fail immediately and tell you exactly what is missing.

### Step 2: Submit Your Request for "Blueprint" Generation

1.  **Create a Pull Request:** Add your new `my-app-nonprod.yaml` file to the `requests/` directory in a new branch and open a pull request.
2.  **Automated Generation:** Our CI/CD pipeline will automatically detect your new file. It will run the full `Helm -> Mutate -> Cleanup -> Validate` pipeline.
3.  **Review the Plan:** The pipeline will commit the final, "golden" infrastructure manifest (`02-golden.yaml`) back to your pull request. You and your team can review this file. It is the exact, low-level blueprint of the infrastructure that will be created.

### Step 3: Execute by Merging

1.  **Approval:** Once your pull request is approved, you simply merge it.
2.  **Automated Deployment:** The merged files (your `request.yaml` and the `02-golden.yaml`) are placed in the `tenants/` directory. Our GitOps controller (Argo CD) detects the new files and automatically begins provisioning your infrastructure in Google Cloud.

---

## The Backend Perspective (Platform Engineer Guide)

This is what our automated system is doing at each step.

| User Action | Backend Step 1: Helm Generation | Backend Step 2: Kyverno Mutation | Backend Step 3: Validation & Deploy |
| :--- | :--- | :--- | :--- |
| **User submits `request.yaml` in a PR.** | The CI pipeline runs `helm template -f request.yaml`. | The Helm output is piped to `kyverno apply` with mutation policies. | The mutated YAML is validated by `kyverno apply` with validation policies. |
| **Result:** A raw `00-helm.yaml` is created. | **Result:** A clean `02-golden.yaml` is created. | **Result:** A `03-policy-report.yaml` is generated. If it passes, the golden manifest is committed to the PR. |
| **User merges the PR.** | The `02-golden.yaml` is now in the `tenants/` directory. | Argo CD detects the new file in the Git repository. | Argo CD runs `kubectl apply -f 02-golden.yaml`, and Config Connector begins creating the GCP resources. |

---

## Comparison with a Conversational AI Agent Workflow

This factory uses a **declarative, Git-centric** model. Let's compare it to a **conversational, agent-driven** model.

| Feature | **Our Tenant Factory (Declarative)** | **Conversational AI Agent** |
| :--- | :--- | :--- |
| **Input** | A structured, schema-validated `request.yaml` file. | A natural language prompt (e.g., "Deploy my app to the cloud"). |
| **"Blueprint" Phase** | The CI pipeline **automatically generates** the final manifest and commits it to the PR for review. The blueprint is a direct result of the code. | The agent generates a "plan" that the user must **manually review and refine** by chatting with the agent. The quality depends on the agent's interpretation. |
| **Execution** | **Fully automated via Git merge.** The act of merging the PR *is* the execution command. | **Interactive and step-by-step.** The user must guide the agent through each step, validating its actions along the way. |
| **Source of Truth** | **Git.** The `tenants/` directory is the absolute, verifiable "golden record" of all deployed infrastructure. | **The agent's state and the deployed infrastructure.** It can be difficult to get a single, declarative view of the final state. |
| **Best For** | **Enterprise-scale, repeatable deployments.** Enforcing strict standards, governance, and providing a perfect audit trail. Ideal for platform teams building a "paved road." | **Rapid prototyping, exploration, and one-off tasks.** Generating boilerplate for a new project or learning a new technology. Ideal for individual developers or small teams. |

**Conclusion:** Our factory's declarative, Git-based approach is intentionally designed for the enterprise. It prioritizes **repeatability, auditability, and governance** over the free-form flexibility of a conversational agent, which is the correct trade-off for a system that provisions production-ready infrastructure at scale.
