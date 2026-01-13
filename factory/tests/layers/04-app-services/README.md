# tests/layers/04-app-services/README.md
# Layer 4 Test: Application Services

This test validates the final layer of application and security services.

**Given:** A request that includes all previous layers plus Memorystore, Pub/Sub, Artifact Registry, Eventarc, DNS, and Cloud Armor.
**When:** `helm template` is run.
**Then:** The output should contain all resources from Layers 1, 2, & 3, PLUS all the corresponding application and security service resources.
