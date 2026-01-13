# The Tenant Factory: System Reference Guide

This document is the definitive technical reference for the Tenant Factory. It details every configurable field in the `request.yaml`, every implemented abstraction, and every compliance rule.

---

## 1. The `request.yaml` API Contract

This section details all the fields available in a `request.yaml` file, their purpose, and allowed values.

| Path | Type | Description | Required | Example |
| :--- | :--- | :--- | :--- | :--- |
| `tenant_code` | string | A short, unique, lowercase code for the tenant. | Yes | `"alpha"` |
| `environment` | string | The deployment environment. | Yes | `"prod"` |
| `gcp.region` | string | The primary GCP region for resources. | Yes | `"us-east4"` |
| `gcp.billing_account_id` | string | The GCP Billing Account ID. | Yes | `"016112-AAF779-C59A78"` |
| `gcp.org_id` | string | The GCP Organization ID. | Yes | `"547574100405"` |
| `organization.use_folder` | boolean | If `true`, the project is created in a folder. | No | `true` |
| `organization.folder_name`| string | The name of the folder to use. | If `use_folder` is `true` | `"production-tenants"` |
| `organization.iam` | array | A list of IAM bindings for the project. | No | `[{ "role": "roles/viewer", "member": "..." }]` |
| `project_services` | array | A list of Google Cloud APIs to enable. | No | `["compute.googleapis.com"]` |
| `network.mode` | string | The networking model. | Yes | `"dedicated"` |
| `network.dedicated.vpc` | object | Configuration for the VPC. | If `mode` is `dedicated` | `{ "auto_create_subnetworks": false }` |
| `network.dedicated.subnets`| array | A list of subnets to create. | If `mode` is `dedicated` | `[{ "name": "main", "cidr": "..." }]` |
| `infra.gke.enabled` | boolean | If `true`, a GKE cluster is provisioned. | No | `true` |
| `infra.gke.size` | string | The abstract size for the GKE cluster. | If `gke.enabled` is `true` | `"large"` |
| `infra.database.enabled` | boolean | If `true`, database(s) are provisioned. | No | `true` |
| `infra.database.postgres` | object | Configuration for a PostgreSQL instance. | No | `{ "name": "main-db", ... }` |
| `infra.database.size` | string | The abstract size for the database. | If `database.enabled` is `true` | `"large"` |
| `compliance.packs` | array | A list of compliance packs to enable. | No | `["pci-dss"]` |

---

## 2. Implemented Abstractions

This section lists all the "magic" that the factory does to translate high-level requests into concrete values.

| Abstraction | Policy File | Trigger | Input (`request.yaml`) | Output (Mutated Value) |
| :--- | :--- | :--- | :--- | :--- |
| **GKE Sizing** | `10-abstractions/sizing.yaml` | `ContainerCluster` with `platform.eazyops.com/gke-size` label | `infra.gke.size: "large"` | `spec.initialNodeCount: 5`, `spec.nodeConfig.machineType: "e2-standard-8"` |
| **GKE Sizing** | `10-abstractions/sizing.yaml` | `ContainerCluster` with `platform.eazyops.com/gke-size` label | `infra.gke.size: "small"` | `spec.initialNodeCount: 1`, `spec.nodeConfig.machineType: "e2-standard-2"` |
| **Database Sizing** | `10-abstractions/sizing.yaml` | `SQLInstance` with `platform.eazyops.com/db-size` label | `infra.database.size: "large"` | `spec.settings.tier: "db-n1-standard-4"` |
| **Database Sizing** | `10-abstractions/sizing.yaml` | `SQLInstance` with `platform.eazyops.com/db-size` label | `infra.database.size: "small"` | `spec.settings.tier: "db-g1-small"` |

---

## 3. Implemented Compliance Rules

This section lists all the compliance rules currently enforced by the factory.

| Compliance Pack | Policy File | Resource | Rule Description | Action |
| :--- | :--- | :--- | :--- | :--- |
| **PCI-DSS** | `15-compliance-mutations/pci-dss.yaml` | `ContainerCluster` | GKE cluster must be private. | **Mutates** `spec.privateClusterConfig.enablePrivateEndpoint` to `true`. |
| **PCI-DSS** | `20-compliance-validations/pci-dss.yaml`| `ContainerCluster` | GKE cluster must be private. | **Validates** that `spec.privateClusterConfig.enablePrivateEndpoint` is `true`. |

---

## 4. Current Resource Coverage

This is the list of all Config Connector resources that the Helm chart can currently generate.

*   `Project`
*   `IAMPolicyMember`
*   `Service`
*   `ComputeNetwork`
*   `ComputeSubnetwork`
*   `ComputeFirewall`
*   `ComputeRouter`
*   `ComputeRouterNAT`
*   `ContainerCluster`
*   `SQLInstance` (PostgreSQL & MySQL)
*   `AlloyDBCluster`
*   `DataprocCluster`
*   `RunService`
*   `RedisInstance`
*   `PubSubTopic`
*   `EventarcTrigger`
*   `StorageBucket`
*   `SecretManagerSecret`
*   `DNSManagedZone`
*   `ComputeSecurityPolicy` (Cloud Armor)
*   `IAMServiceAccount`
