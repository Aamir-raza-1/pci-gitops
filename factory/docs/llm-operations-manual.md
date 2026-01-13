# LLM Operations Manual: How to Extend the Factory

This guide is for developers and AI agents (like me) on how to programmatically extend the Tenant Factory using a structured, prompt-based workflow.

---

## The Core Principle: Test-Driven, Layered Extension

The factory is designed to be extended methodically. **Never** add a feature without also adding a test. The workflow is always:

1.  **Extend the Schema:** Define the new API contract.
2.  **Extend the Helm Chart:** Add the new template.
3.  **Add a Layer Test:** Prove that your Helm extension works in isolation.
4.  **Add Kyverno Policies:** Add the mutation and validation logic.
5.  **Add a Policy Test:** Prove that your Kyverno policies work as expected.

---

## How to Use an LLM to Extend the Factory

To have an LLM (like me) add a new feature, you will provide a prompt that contains the following sections:

1.  **Goal:** A clear, one-sentence description of the feature.
2.  **File Modifications:** A list of `CREATE FILE` or `REPLACE FILE` commands with the exact path and content.
3.  **Verification Plan:** The exact `helm template` or `kyverno test` command to run to prove that the changes were successful.

### Good vs. Bad Examples

*   **BAD Prompt (Vague):**
    > "Please add support for Cloud SQL."

    *Why it's bad:* It's ambiguous. Which database engine? What fields should be configurable? How should it be tested? This forces the LLM to guess, which leads to errors.

*   **GOOD Prompt (Precise and Testable):**
    > **Goal:** Add support for a basic `SQLInstance` for MySQL.
    >
    > **File Modifications:**
    > `CREATE FILE generator/chart/templates/30-infra-core/mysql.yaml` with the following content:
    > ```helm
    > {{- if and .Values.infra.database.enabled .Values.infra.database.mysql }}
    > apiVersion: sql.cnrm.cloud.google.com/v1beta1
    > kind: SQLInstance
    > metadata:
    >   name: {{ .Values.infra.database.mysql.name }}
    >   namespace: {{ include "tenant.namespace" . }}
    > spec:
    >   region: {{ .Values.gcp.region }}
    >   databaseVersion: {{ .Values.infra.database.mysql.version }}
    >   settings:
    >     tier: {{ .Values.infra.database.mysql.tier }}
    > {{- end }}
    > ```
    >
    > **Verification Plan:**
    > "After you create the file, run `helm template generator/chart -f tests/layers/03-core-infra/request.yaml`. The output must contain a `SQLInstance` resource with the name `main-db-mysql`."

    *Why it's good:* It is unambiguous, provides the exact code, and gives the LLM a clear, verifiable definition of success.

---

## Prompt Templates for Common Tasks

Here are the prompt templates you can copy, fill in, and send to me (or another LLM) to extend the factory.

### Prompt Template: Add a New Helm Resource

```
You are my stateful development partner. Our goal is to extend the Helm chart to support a new resource.

**Goal:** Add support for the `<RESOURCE_KIND>` resource.

**File Modifications:**

`CREATE FILE path/to/new/template.yaml` with the following content:
```helm
# Paste the full, correct Helm template here
```

`REPLACE FILE path/to/request.yaml` with this updated test request:
```yaml
# Paste the request.yaml content that enables and configures the new resource
```

**Verification Plan:**
"After you create/replace the files, run `helm template generator/chart -f path/to/request.yaml`. The output YAML must contain a document with `kind: <RESOURCE_KIND>`."
```

### Prompt Template: Add a New Kyverno Abstraction/Mutation

```
You are my stateful development partner. Our goal is to add a new Kyverno mutation policy.

**Goal:** Add a Kyverno policy to `<BRIEF_DESCRIPTION_OF_MUTATION>`.

**File Modifications:**

`CREATE FILE generator/policies/<LAYER>/<new-policy-name>.yaml` with the following content:
```yaml
# Paste the full, correct Kyverno policy here
```

**Verification Plan:**
"After you create the file, run `./scripts/generate.sh path/to/scenario/request.yaml temp/test-output`. Then, run `cat temp/test-output/01-mutated.yaml`. The `<RESOURCE_KIND>` in the output must now contain the field `<FIELD_NAME>` with the value `<EXPECTED_VALUE>`."
```

### Prompt Template: Add a New Kyverno Validation & Test

```
You are my stateful development partner. Our goal is to add a new Kyverno validation policy and a corresponding test case.

**Goal:** Add a Kyverno policy to validate that `<BRIEF_DESCRIPTION_OF_RULE>`.

**File Modifications:**

`CREATE FILE generator/policies/20-compliance-validations/<new-validation-policy>.yaml` with the following content:
```yaml
# Paste the full, correct Kyverno validation policy here
```

`CREATE FILE tests/policies/<new-test-suite>/kyverno-test.yaml` with the following content:
```yaml
# Paste the full kyverno-test.yaml content here
```

`CREATE FILE tests/policies/<new-test-suite>/non-compliant-resource.yaml` with the following content:
```yaml
# Paste the intentionally non-compliant resource here
```

**Verification Plan:**
"After you create the files, run `./scripts/run-tests.sh tests/policies/<new-test-suite>`. The command must succeed and show that the validation rule correctly failed as expected."
```
