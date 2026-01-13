# Extending the Tenant Factory: A Step-by-Step Guide

This guide provides detailed, step-by-step instructions for platform engineers to extend the capabilities of the tenant factory.

---

## How to Add a New Resource (e.g., a `Memorystore` instance)

This is the most common task. We will add a new `RedisInstance` resource, following our layered, test-driven approach.

### Step 1: Extend the Helm Foundation (Layer 1 & 2)

1.  **Update the Schema (`values.schema.json`):**
    First, define the new "API contract". Add an `infra.memorystore` block to the properties in `generator/chart/values.schema.json`.

    ```json
    "infra": {
      "type": "object",
      "properties": {
        "memorystore": {
          "type": "object",
          "properties": {
            "enabled": { "type": "boolean" },
            "redis": { "type": "object" }
          }
        }
        // ... other infra blocks
      }
    }
    ```

2.  **Create the Helm Template:**
    Create a new file: `generator/chart/templates/40-infra-app/memorystore.yaml`. This template will be responsible for scaffolding the basic `RedisInstance`.

    ```helm
    {{- if and .Values.infra.memorystore.enabled .Values.infra.memorystore.redis }}
    apiVersion: redis.cnrm.cloud.google.com/v1beta1
    kind: RedisInstance
    metadata:
      name: {{ .Values.infra.memorystore.redis.name }}
      namespace: {{ include "tenant.namespace" . }}
      labels:
        "platform.eazyops.com/redis-tier": "{{ .Values.infra.memorystore.redis.tier }}"
    spec:
      tier: {{ .Values.infra.memorystore.redis.tier }}
      memorySizeGb: {{ .Values.infra.memorystore.redis.memory_size_gb }}
      locationId: {{ .Values.gcp.region }}
      authorizedNetworkRef:
        name: {{ include "tenant.resourceName" (dict "kind" "VPC" "Values" .Values) }}
    {{- end }}
    ```

3.  **Create a Layer Test:**
    Create a new directory `tests/layers/05-memorystore/`. Add a `request.yaml` that enables the new `infra.memorystore` block and a `generate.sh` script. Run it and verify that a `RedisInstance` is correctly generated in the output.

### Step 2: Add a New Abstraction (Layer 3)

Let's say we want an abstract size, `tier: "HA"`, to automatically translate to the correct GCP tier and memory size.

1.  **Create the Abstraction Policy:**
    Create a new file: `generator/policies/10-abstractions/memorystore-sizing.yaml`.

    ```yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: abstractions-memorystore-sizing
    spec:
      rules:
      - name: "mutate-redis-ha-tier"
        match:
          any:
          - resources:
              kinds: ["RedisInstance"]
              selector:
                matchLabels:
                  "platform.eazyops.com/redis-tier": "HA"
        mutate:
          patchStrategicMerge:
            spec:
              tier: "STANDARD_HA"
              memorySizeGb: 5
    ```

### Step 3: Add a New Compliance Rule (Layer 4 & 5)

Let's say HIPAA requires all Redis instances to have in-transit encryption enabled.

1.  **Create the Compliance Mutation Policy:**
    Create a new file: `generator/policies/15-compliance-mutations/hipaa-redis.yaml`.

    ```yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: compliance-mutations-hipaa-redis
    spec:
      rules:
      - name: "mutate-redis-in-transit-encryption-for-hipaa"
        match:
          any:
          - resources:
              kinds: ["RedisInstance"]
              selector:
                matchLabels:
                  "compliance.eazyops.com/hipaa": "true"
        mutate:
          patchStrategicMerge:
            spec:
              transitEncryptionMode: "SERVER_AUTHENTICATION"
    ```

2.  **Create the Compliance Validation Policy:**
    Create a new file: `generator/policies/20-compliance-validations/hipaa-redis.yaml`.

    ```yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: compliance-validations-hipaa-redis
    spec:
      validationFailureAction: Enforce
      rules:
      - name: "validate-redis-in-transit-encryption-for-hipaa"
        match:
          any:
          - resources:
              kinds: ["RedisInstance"]
              selector:
                matchLabels:
                  "compliance.eazyops.com/hipaa": "true"
        validate:
          message: "HIPAA requires Redis in-transit encryption."
          pattern:
            spec:
              transitEncryptionMode: "SERVER_AUTHENTICATION"
    ```

### Step 4: Add a New Test Case

1.  **Create the Test Suite:**
    Create a new directory `tests/policies/hipaa-redis/`. Inside, create:
    *   `kyverno-test.yaml`: Defines the test cases for your new mutation and validation rules.
    *   `non-compliant-redis.yaml`: A sample `RedisInstance` that is missing the `transitEncryptionMode`.
2.  **Run the Test:**
    Execute `./scripts/run-tests.sh tests/policies/hipaa-redis`. Verify that your mutation rule passes and your validation rule correctly fails the non-compliant resource.

By following these methodical, test-driven steps, you can safely and reliably extend the factory to support any new resource or policy.

---

## Frequently Asked Questions (FAQ)

**Q: Why is the process so layered? Can't I just add a new template and a policy?**
> **A:** The layered approach is critical for stability and testing. By validating each layer independently (`tests/layers/`), we can guarantee that a change to the networking templates doesn't accidentally break the GKE templates. This prevents cascading failures and makes debugging much easier.

**Q: Where do I find the available fields for a new Config Connector resource?**
> **A:** The official Google Cloud Config Connector documentation is the source of truth. For example, to find the fields for `RedisInstance`, you would search for "Config Connector RedisInstance". The `spec` section of the CRD reference will show all available fields.

**Q: My new Helm template has a `nil pointer` error. What does that mean?**
> **A:** This is the most common error in Helm. It means your template is trying to access a value that doesn't exist in the `request.yaml` file you're testing with (e.g., ` .Values.infra.new_service.name`). To fix it, ensure that the `request.yaml` file for your layer test includes the new block you're trying to access.