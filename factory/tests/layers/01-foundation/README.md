# tests/layers/01-foundation/README.md
# Layer 1 Test: Foundation (Project & IAM)

This test validates the most basic layer of the factory.

**Given:** A request for a new project with specific IAM bindings.
**When:** `helm template` is run.
**Then:** The output should contain ONLY a `Project` resource and the corresponding `IAMPolicyMember` resources, with all names and IDs correctly populated.
