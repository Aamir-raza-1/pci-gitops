# PCI DSS 4.0 GitOps Validation Guide

This document provides step-by-step validation procedures for each deployment wave, mapping them to specific PCI DSS 4.0 requirements. It is designed to be used by both engineers and auditors to verify the compliant state of the environment.

---

## Wave 00 – Bootstrap
**PCI Requirement:** 7.2.1 (System component inventory), 2.4 (Single primary function per server)

This wave establishes the tenant's dedicated namespace, providing a foundational boundary for all subsequent resources.

### 1. Pre-Deploy Validation
- **What:** An ArgoCD cluster is running and the `pci-dss` AppProject exists.
- **How:**
  ```bash
  # Verify ArgoCD pods are running
  kubectl get pods -n argocd

  # Verify the AppProject is created
  kubectl get appproject pci-dss -n argocd
  ```

### 2. Deployment Validation
- **What:** The `tenant-a-00-bootstrap` ArgoCD application syncs successfully and creates a namespace for the tenant.
- **How:**
  ```bash
  # Check ArgoCD application status
  argocd app get tenant-a-00-bootstrap --grpc-web

  # Verify the namespace exists and is labeled correctly
  kubectl get ns tenant-a --show-labels
  # EXPECTED OUTPUT: NAME       STATUS   AGE   LABELS
  #                tenant-a   Active   ...   tenant=tenant-a,argocd.argoproj.io/managed-by=argocd
  ```

### 3. Negative Test
- **Scenario:** A manual attempt to delete the namespace managed by ArgoCD.
- **Action:** `kubectl delete ns tenant-a`
- **Expected Result:** The namespace will be automatically recreated by ArgoCD's self-healing policy.
- **PCI Evidence:** This demonstrates automated configuration enforcement (related to PCI Req 2.2), ensuring the foundational tenant boundary cannot be accidentally or maliciously removed.

### 4. Evidence Generated
- **Artifact:** ArgoCD Sync History.
- **Auditor Verification:** In the ArgoCD UI, navigate to `Applications > tenant-a-00-bootstrap`. The sync history provides an immutable log of when the namespace was created and reconciled, proving it has been consistently enforced since deployment.

---

## Wave 10 – Organization & Project
**PCI Requirement:** 7.1 (Access control), 7.2 (System component inventory), 8.2 (User authentication)

This wave creates the dedicated GCP Project, which acts as the primary resource and IAM boundary for the tenant's Cardholder Data Environment (CDE).

### 1. Pre-Deploy Validation
- **What:** The GCP Folder ID and Billing Account ID in `env.yaml` are correct and the ArgoCD service account has `Project Creator` and `Billing Account User` roles on the parent folder/organization.
- **How:**
  ```bash
  # Verify folder exists
  gcloud resource-manager folders describe FOLDER_ID

  # Verify billing account exists
  gcloud billing accounts describe BILLING_ACCOUNT_ID
  ```

### 2. Deployment Validation
- **What:** The `tenant-a-10-org` ArgoCD app syncs, creating a GCP Project via Config Connector.
- **How:**
  ```bash
  # Check ArgoCD application status
  argocd app get tenant-a-10-org --grpc-web

  # Verify the KCC Project resource is "UpToDate"
  kubectl get project pci-tenant-a-12345 -n tenant-a -o yaml

  # Verify the actual GCP project exists
  gcloud projects describe pci-tenant-a-12345
  ```

### 3. Negative Test
- **Scenario:** Manually changing a critical project setting (e.g., removing a required service API) via the GCP Console.
- **Action:** Go to `APIs & Services` in the GCP Console for the new project and disable the `Cloud Resource Manager API`.
- **Expected Result:** The `tenant-a-10-org` ArgoCD application will become `OutOfSync`. Upon the next sync, ArgoCD will re-enable the API, reverting the manual change.
- **PCI Evidence:** This proves automated drift detection and remediation, a key part of maintaining a secure and compliant configuration as per PCI Req 2.2.

### 4. Evidence Generated
- **Artifact:** GCP Audit Logs (`Cloud ResourceManager` -> `UpdateProject`) and ArgoCD Sync History.
- **Auditor Verification:** Filter GCP Audit Logs for the project ID. The logs will show the `UpdateProject` event initiated by the Config Connector service account. This, combined with the ArgoCD history, provides a clear audit trail of the project's lifecycle being managed exclusively through the approved GitOps workflow.

---

## Wave 20 – Network Segmentation
**PCI Requirement:** 1.2 (Firewall configurations), 1.3 (Prohibit direct public access)

This wave provisions the tenant's VPC, private subnet, and a baseline deny-all ingress firewall rule.

### 1. Pre-Deploy Validation
- **What:** The GCP Project from Wave 10 exists and the `compute.googleapis.com` API is enabled.
- **How:**
  ```bash
  gcloud services list --project=pci-tenant-a-12345 | grep "compute.googleapis.com"
  ```

### 2. Deployment Validation
- **What:** A VPC, subnet, and deny-all firewall rule are created in the tenant's project.
- **How:**
  ```bash
  # Check ArgoCD application status
  argocd app get tenant-a-20-network --grpc-web

  # Verify VPC exists
  gcloud compute networks list --project=pci-tenant-a-12345

  # Verify Subnet exists and has Private Google Access ON
  gcloud compute networks subnets describe pci-tenant-a-12345-subnet --region=us-central1 --project=pci-tenant-a-12345

  # Verify the deny-all ingress rule exists
  gcloud compute firewall-rules list --project=pci-tenant-a-12345 --filter="name=pci-tenant-a-12345-deny-all-ingress"
  ```

### 3. Negative Test
- **Scenario:** Attempting to create a new firewall rule that allows public SSH access (`0.0.0.0/0` on port 22).
- **Action:**
  ```bash
  gcloud compute firewall-rules create allow-ssh --network=pci-tenant-a-12345-vpc --allow=tcp:22 --source-ranges=0.0.0.0/0 --project=pci-tenant-a-12345
  ```
- **Expected Result:** The command succeeds, but if you were to add this rule via a KCC manifest without approval, it would violate the GitOps workflow. A proper negative test would be to add a `ComputeFirewall` manifest to the chart that allows public ingress and see the pipeline fail a policy check (if one were implemented, e.g., with OPA Gatekeeper). The existing deny-all rule ensures that even if other rules are added, a baseline of denial is maintained at the lowest priority.
- **PCI Evidence:** The existence of the `deny-all-ingress` rule provides auditable proof of a default-deny security posture, fulfilling PCI Req 1.2.1.

### 4. Evidence Generated
- **Artifact:** Config Connector `ComputeNetwork`, `ComputeSubnetwork`, `ComputeFirewall` resources in Kubernetes.
- **Auditor Verification:** An auditor can run the `gcloud` commands above to verify the live GCP environment. They can also inspect the Helm chart templates in Git (`charts/20-network/templates/`) to confirm the secure network configuration is defined "as-code," providing a repeatable and auditable source of truth.

---

## Wave 30 – GKE Cluster
**PCI Requirement:** 2.2 (Secure configurations), 1.3 (Private access), 8.2.5 (No shared IDs)

This wave provisions a private GKE cluster with hardened security settings, including Workload Identity and private nodes.

### 1. Pre-Deploy Validation
- **What:** The network resources from Wave 20 exist.
- **How:**
  ```bash
  gcloud compute networks subnets describe pci-tenant-a-12345-subnet --region=us-central1 --project=pci-tenant-a-12345
  ```

### 2. Deployment Validation
- **What:** A private GKE cluster is created with no public endpoint.
- **How:**
  ```bash
  # Check ArgoCD application status
  argocd app get tenant-a-30-gke --grpc-web

  # Verify GKE cluster status and settings
  gcloud container clusters describe pci-tenant-a-12345-gke --region=us-central1 --project=pci-tenant-a-12345

  # Specifically check for private cluster config and workload identity
  gcloud container clusters describe pci-tenant-a-12345-gke --region=us-central1 --project=pci-tenant-a-12345 --format="value(privateClusterConfig.enablePrivateEndpoint, workloadIdentityConfig.workloadPool)"
  # EXPECTED OUTPUT: True  pci-tenant-a-12345.svc.id.goog
  ```

### 3. Negative Test
- **Scenario:** Attempting to connect to the GKE cluster's control plane from the public internet.
- **Action:** From a machine not peered to the VPC, configure `gcloud` with cluster credentials and run `kubectl get pods`.
- **Expected Result:** The connection will time out and fail. The control plane has no public IP address.
- **PCI Evidence:** This directly proves compliance with PCI Req 1.3.2, which prohibits public access to the CDE.

### 4. Evidence Generated
- **Artifact:** Config Connector `ContainerCluster` resource.
- **Auditor Verification:** The output of the `gcloud container clusters describe` command provides definitive proof of the cluster's configuration. An auditor can verify that `privateClusterConfig` is enabled and that the `privateEndpoint` is populated while `publicEndpoint` is empty.

---

## Wave 40 – Admission Control
**PCI Requirement:** 2.2 (Secure configurations), 5.1 (Malware protection), 7.1.2 (Least privilege)

This wave deploys a Kyverno `ClusterPolicy` that enforces security best practices on all workloads deployed to the cluster.

### 1. Pre-Deploy Validation
- **What:** The GKE cluster from Wave 30 is running and Kyverno is installed.
- **How:**
  ```bash
  # (Assuming Kyverno is installed as a prerequisite)
  kubectl get pods -n kyverno
  ```

### 2. Deployment Validation
- **What:** The `pci-req-2-runasnonroot` ClusterPolicy is created.
- **How:**
  ```bash
  # Check ArgoCD application status
  argocd app get tenant-a-40-admission --grpc-web

  # Verify the policy is active
  kubectl get clusterpolicy pci-req-2-runasnonroot
  # EXPECTED OUTPUT: NAME                       BACKGROUND   ACTION    READY
  #                pci-req-2-runasnonroot     true         Enforce   true
  ```

### 3. Negative Test (MANDATORY)
- **Scenario:** Attempting to deploy a Pod that explicitly tries to run as the root user.
- **Action:** Create a file `bad-pod.yaml` and apply it.
  ```yaml
  # bad-pod.yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: bad-pod
    namespace: tenant-a
  spec:
    containers:
    - name: nginx
      image: nginx
      securityContext:
        runAsNonRoot: false # Explicitly violating the policy
  ```
  ```bash
  kubectl apply -f bad-pod.yaml
  ```
- **Expected Failure Message:**
  ```
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

  resource Pod/tenant-a/bad-pod was blocked due to the following policies

  pci-req-2-runasnonroot:
    require-run-as-non-root: 'validation error: Running as root is not allowed (PCI DSS Req 2.2). The securityContext.runAsNonRoot must be set to true. rule require-run-as-non-root failed at path /spec/containers/0/securityContext/runAsNonRoot/'
  ```
- **PCI Evidence:** This is direct, auditable proof that preventative controls are in place to enforce secure configuration standards (PCI Req 2.2) and principles of least privilege (PCI Req 7.1.2) for all workloads.

### 4. Evidence Generated
- **Artifact:** Kyverno `PolicyReport` and Admission Controller logs.
- **Auditor Verification:** An auditor can perform the negative test above to witness the enforcement in real-time. Additionally, they can review Kyverno's `PolicyReport` CRDs, which provide a continuous compliance assessment.
  ```bash
  # Check for policy reports in the tenant namespace
  kubectl get policyreports -n tenant-a
  ```
  The report will show a "fail" result for any pre-existing workloads that violate the policy, demonstrating the effectiveness of the background scan.
