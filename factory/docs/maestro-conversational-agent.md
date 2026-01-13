# The "Maestro" Agent: A Conversational Interface for the Tenant Factory

This document describes **Maestro**, a conceptual conversational AI agent that acts as an intelligent front-end to the underlying Tenant Factory. Maestro's purpose is to guide users from a high-level business need to a fully-vetted, production-ready `request.yaml` blueprint, which can then be submitted to our existing GitOps factory.

---

## The Vision: From Business Need to Infrastructure Blueprint in One Conversation

The core Tenant Factory is powerful but requires users to understand the `request.yaml` "API contract." Maestro abstracts this away. It allows users to describe their needs in natural language, answers their questions, and intelligently constructs the `request.yaml` for them.

**The Workflow:**
1.  **Describe (The Conversation):** A user starts a chat with Maestro and describes their goal.
2.  **Interview & Refine (The "Smart Blueprint"):** Maestro asks clarifying questions, presents options, and uses its knowledge of the factory's capabilities to co-create a "live blueprint" with the user.
3.  **Generate & Execute (The Handoff):** Once the user is satisfied, Maestro generates the final, compliant `request.yaml` and automatically submits it to the Tenant Factory's Git repository via a pull request.

---

## How It Works: A Three-Step Conversational Workflow

### Step 1: Describe Your Needs (The Initial Prompt)

The user initiates the process with a high-level, goal-oriented prompt. The key is to describe the "what" and "why," not the "how."

**Good Initial Prompts:**
> "I'm migrating a monolithic on-premise e-commerce application to GCP. It has a PostgreSQL database, a Redis cache, and a large amount of static assets in a NAS. The TCO assessment document is attached. We need to be PCI compliant. Can you help me design the landing zone?"

> "My team is starting a new project for real-time data analytics. We'll be using Spark and need a staging area for raw data. This is a production environment."

**Vague Prompts (Maestro will ask for clarification):**
> "I need a new GCP project."
>
> **Maestro's Response:** "I can certainly help with that! To get started, could you tell me a bit more about this project? Is it for a production or non-production environment? What kind of application will it host?"

### Step 2: Customize the Blueprint (The Interactive Interview)

This is the core of the Maestro agent. It does not simply generate a plan; it engages in a dialogue to refine it.

*   **Knowledge of the Factory:** Maestro has been trained on the Tenant Factory's `values.schema.json`, all the `scenarios/`, and all the Kyverno policies. It knows what the factory can and cannot do.
*   **Intelligent Questioning:** Based on the initial prompt, Maestro asks targeted questions.
    *   *User:* "I need to be PCI compliant."
    *   *Maestro:* "Understood. For PCI compliance, the factory will enforce a dedicated VPC and a private GKE cluster. Is that acceptable?"
*   **Presenting Options:** Maestro presents the available blueprints as options.
    *   *Maestro:* "Based on your need for a Spark environment, the 'Data & Analytics Platform' blueprint seems like a good starting point. It includes a dedicated VPC and a Dataproc cluster. Would you like to start with that?"
*   **Dynamic Blueprint Generation:** As the user makes choices, Maestro builds the `request.yaml` in the background. The user sees a "live" summary of their choices, not the raw YAML.

**Example Interaction:**
> **Maestro:** "For your 'large' production database, the factory's sizing policy will provision a `db-n1-standard-4` tier. Does that meet your performance requirements?"
>
> **User:** "Actually, we need a higher-performance machine type for the database."
>
> **Maestro:** "No problem. I can override the abstraction. I will set the `infra.database.postgres.tier` directly to `db-n1-highmem-8`. Please be aware that this falls outside the standard sizing blueprint. I will add a note to the pull request for the platform team to review."

### Step 3: Execute the Blueprint (The Automated Handoff)

Once the user is satisfied, they give the final approval.

1.  **User Confirmation:**
    > **User:** "This looks perfect. Please proceed."
2.  **Final Generation:** Maestro takes the `request.yaml` it has built in the background.
3.  **Automated Pull Request:** Maestro uses a Git bot identity to:
    *   Create a new branch.
    *   Add the `request.yaml` to the `requests/` directory.
    *   Open a pull request with a detailed summary of the user's choices and any deviations from the standard blueprints.
4.  **Handoff to the Tenant Factory:** From this point, the existing CI/CD pipeline of the Tenant Factory takes over, running the `generate.sh` script and committing the final `02-golden.yaml` back to the PR.

---

## Comparison: Factory vs. Maestro-driven Factory

The underlying factory remains the "engine," but Maestro becomes the "smart dashboard."

| Feature | **Base Tenant Factory** | **Maestro-driven Tenant Factory** |
| :--- | :--- | :--- |
| **User Interface** | **Git & YAML.** The user must know how to find, copy, and edit a `request.yaml` file. | **Conversational Chat.** The user describes their needs in natural language. |
| **Blueprint Discovery**| **Manual.** The user must read the `scenarios/` directory to find a suitable starting point. | **Automated.** Maestro analyzes the user's request and recommends the best starting blueprint. |
| **Configuration** | **Manual.** The user is responsible for correctly filling out all the fields in the `request.yaml`. | **Guided & Interactive.** Maestro asks questions and fills out the `request.yaml` in the background, ensuring it is valid. |
| **Execution** | **Manual PR creation.** The user must manually create a branch and open a pull request. | **Automated PR creation.** Maestro handles the entire Git workflow. |
| **Underlying Engine** | **The `generate.sh` pipeline.** (Helm -> Mutate -> Cleanup -> Validate) | **The `generate.sh` pipeline.** (Maestro's final output is a `request.yaml` that feeds into the exact same, robust backend.) |

**Conclusion:** Maestro does not replace the Tenant Factory; it enhances it. It provides a user-friendly, intelligent "wizard" that makes the power of the underlying declarative factory accessible to a much wider audience, reducing errors and accelerating adoption. The robust, testable, and policy-driven backend we have built is the essential prerequisite for a successful conversational agent like Maestro.
