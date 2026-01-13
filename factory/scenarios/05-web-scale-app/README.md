# scenarios/05-web-scale-app/README.md
# Scenario 5: The "Web-Scale Application"

## Business Case
A new public-facing, web-scale application (`epsilon`) is being deployed. It requires a highly available GKE cluster, a high-performance in-memory cache (Memorystore), public DNS, and protection from web attacks (Cloud Armor).

## Technical Choices
*   **`infra.gke.enabled: true`**: A GKE cluster forms the core of the application platform.
*   **`infra.memorystore.redis.tier: "STANDARD_HA"`**: A highly available Memorystore for Redis instance is provisioned for session caching and other low-latency data storage needs.
*   **`infra.dns.enabled: true`**: A `DNSManagedZone` is created to host the public DNS records for the application.
*   **`infra.security.cloud_armor.enabled: true`**: A `ComputeSecurityPolicy` (Cloud Armor) is created with a sample rule to block a specific IP range, providing a foundational Web Application Firewall (WAF).
