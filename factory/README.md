# The Enterprise Tenant Factory

This repository contains the automated system for provisioning GCP tenant environments using a "Generate, Test, and Commit" (GTC) GitOps workflow.

## How It Works

1.  **Request:** A user submits a `request.yaml` file (see `scenarios/` for examples).
2.  **Generate (Helm):** `helm template` creates the base resource manifests.
3.  **Mutate (Kyverno):** Kyverno policies in `10-abstractions` and `15-compliance-mutations` are applied to the Helm output to enforce sizing, defaults, and compliance requirements.
4.  **Validate (Kyverno):** Kyverno policies in `20-compliance-validations` are applied to the mutated manifests to generate a policy report and ensure the final configuration is valid.
5.  **Commit & Sync:** The final, validated manifest is committed to Git and synced by Argo CD.

## How to Use

**Prerequisites:**
*   Helm CLI
*   Kyverno CLI

**To generate a tenant:**
```sh
# Make the script executable
chmod +x scripts/generate.sh

# Run the pipeline for a scenario
./scripts/generate.sh scenarios/01-max-security-enterprise/request.yaml temp/alpha-prod
```
The final, validated manifest will be at `temp/alpha-prod/01-mutated.yaml`.

## How to Test the Policies

This repository includes a suite of tests for our Kyverno policies, located in `tests/policies/`. Each subdirectory represents a test suite for a specific policy.

### To Run a Test Suite:
1. Make the script executable: `chmod +x scripts/run-tests.sh`
2. Run the script, pointing to a test directory:
   ```sh
   ./scripts/run-tests.sh tests/policies/pci-dss
   ```
A successful run will show that all test cases passed as expected.

### How to Extend (Testing)
When you add a new Kyverno policy (e.g., for HIPAA):
1.  Create a new directory: `tests/policies/hipaa/`.
2.  Add a `kyverno-test.yaml` file defining your test cases.
3.  Add "bad" resource files (e.g., `non-compliant-sql-instance.yaml`) that your policy should either fix (mutate) or fail (validate).
4.  Run your new test suite using the `run-tests.sh` script.

## How to Deploy (The GitOps Loop)

This factory is designed to be used with a GitOps controller like Argo CD.

1.  **The `tenants/` Directory:** This is the "live" directory that Argo CD watches. It is the source of truth for what should be deployed.
2.  **The Workflow:**
    a. After a user's `request.yaml` has been processed by the `generate.sh` script, the final, validated `02-golden.yaml` and the original `request.yaml` are committed to a new directory, e.g., `tenants/alpha/prod/`.
    b. The `ApplicationSet` in `argocd/applicationset.yaml` will automatically detect this new directory.
    c. It will generate a new Argo CD `Application` specifically for the `alpha-prod` tenant.
    d. This new Application will sync **only** the `02-golden.yaml` file, deploying the tenant's infrastructure.
3.  **To Onboard a New Tenant:** Simply run the `generate.sh` script and commit the results to a new directory under `tenants/`. Argo CD handles the rest.

### How to Extend (Argo CD)
The `ApplicationSet` is designed to be generic. You do not need to modify it to add new tenants. To add a new resource type to your tenants (e.g., a `Memorystore` instance), you simply need to:
1.  Update the Helm chart to generate the `Memorystore` resource.
2.  The `generate.sh` script will automatically include it in the `02-golden.yaml`.
3.  Argo CD will automatically pick up the change and sync the new resource.