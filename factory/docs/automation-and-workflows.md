# Automation, Workflows, and the Vision

This document explains the different ways to run the tenant factory, from local manual execution to full CI/CD automation, and presents a vision for a fully automated, prompt-driven system.

---

## How to Run Manually (The Platform Engineer Workflow)

This is the workflow for developing and testing the factory itself.

1.  **Create a Request File:** Create a new `request.yaml` in the `scenarios/` or `tests/` directory to define the infrastructure you want to generate.
2.  **Run the Generation Pipeline:** Execute the main script, pointing to your request file and a temporary output directory.
    ```sh
    ./scripts/generate.sh path/to/your/request.yaml temp/my-test
    ```
3.  **Inspect the Artifacts:**
    *   `temp/my-test/00-helm.yaml`: The raw output from Helm. Useful for debugging the base templates.
    *   `temp/my-test/01-mutated.yaml`: The messy, intermediate output from the Kyverno mutation step.
    *   `temp/my-test/02-golden.yaml`: **This is the final, clean manifest.** This is the file that would be committed to Git.
    *   `temp/my-test/03-policy-report.yaml`: The results of the final validation step. Check this file for any `fail` results.

---

## How to Run in CI/CD (The GitOps Workflow)

The `generate.sh` script is designed to be the core of a CI/CD pipeline (e.g., GitHub Actions, GitLab CI).

**Conceptual CI/CD Pipeline (`.github/workflows/tenant-request.yaml`):**

```yaml
name: Tenant Generation
on:
  pull_request:
    paths:
      - 'requests/**.yaml' # Trigger when a new request is submitted

jobs:
  generate-and-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: setup-helm-tool
      - uses: setup-kyverno-cli

      - name: Generate Manifests for New Request
        # This step finds the new request file and runs the pipeline
        run: |
          REQUEST_FILE=$(git diff --name-only ${{ github.base_ref }} ${{ github.head_ref }} -- 'requests/**.yaml')
          TENANT_NAME=$(basename ${REQUEST_FILE} .yaml)
          ./scripts/generate.sh ${REQUEST_FILE} temp/${TENANT_NAME}

      - name: Commit Golden Manifest to PR
        # This step would use a Git bot to commit the '02-golden.yaml'
        # and 'request.yaml' to a new directory under 'tenants/' in the PR branch.
        run: |
          # ... git commands to configure user, add files, commit, and push ...
```
This pipeline automates the entire process. A developer simply opens a PR with a new `request.yaml`, and the pipeline generates, validates, and commits the final manifest back to the PR for review.

---

## The Vision: Reverse Engineering the Factory (Automated Prompting)

The structured, layered, and testable nature of this factory opens up a powerful possibility: **automating the creation of the factory itself.**

**The Concept:**
Instead of a platform engineer manually creating the Helm templates and Kyverno policies, a higher-level tool could do it for them based on a simple, high-level definition.

**Example Vision (`factory-definition.yaml`):**
```yaml
# This file would be the input to a future "factory-generator" tool.
factory:
  resources:
    - name: "Project"
      template: true # Generate Helm template
      policies:
        - name: "cis-labeling"
          type: "validation"
    - name: "GKECluster"
      template: true
      abstractions:
        - name: "sizing"
          inputs: ["small", "large"]
          outputs:
            - field: "initialNodeCount"
              values: [1, 5]
      policies:
        - name: "pci-dss-private"
          type: "mutation+validation"
          pack: "pci-dss"
  # ... and so on
```

**The "Reverse Engineering" Workflow:**
1.  A platform architect defines the desired state of the *factory itself* in a high-level YAML like the one above.
2.  A script or an AI agent (like me) would parse this file.
3.  For each resource, it would:
    *   Generate the parameterized Helm template.
    *   Generate the Kyverno mutation policies for the defined abstractions.
    *   Generate the Kyverno mutation and validation policies for the defined compliance packs.
    *   Generate the corresponding layered tests.
4.  The output would be the entire, working `generator/` and `tests/` directories that we have just built by hand.

This "factory-for-the-factory" approach is the ultimate goal of a truly automated and scalable platform engineering strategy. It allows you to manage the *rules* of your infrastructure, rather than the infrastructure code itself.

---

## Frequently Asked Questions (FAQ)

**Q: Why does the `generate.sh` script create so many intermediate files?**
> **A:** This is a deliberate design choice for debuggability. By keeping the raw Helm output (`00-helm.yaml`), the messy Kyverno output (`01-messy-mutated.yaml`), and the final golden manifest (`02-golden.yaml`), you can easily trace the transformation of a resource at each step of the pipeline to see exactly which policy made a change.

**Q: My CI/CD pipeline fails on the `kyverno apply` step. What should I do?**
> **A:** The most common reason is that the Kyverno CLI is not installed or not in the `PATH` of the runner. Ensure your CI/CD pipeline has a setup step to install the Kyverno CLI. The second most common reason is a syntax error in a policy; you can debug this by running the `run-tests.sh` script locally.

**Q: What is the purpose of the `make-golden.sh` script?**
> **A:** The Kyverno CLI, when applying mutations, outputs every resource multiple times, along with extra text. The `make-golden.sh` script is a critical cleanup utility that processes this messy output and produces a clean, final manifest with only one version of each resource. It is the key to making the pipeline robust.