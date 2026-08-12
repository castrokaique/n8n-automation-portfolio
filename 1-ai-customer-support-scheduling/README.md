# Project: Omnichannel AI Customer Support & Appointment Scheduling (Multi-Agent System)

## 🎯 Overview
This repository contains the architecture of an enterprise-grade conversational AI and automation solution developed in **n8n**. The system is designed to act as a **multi-agent orchestrator**, managing end-to-end automated WhatsApp support — from initial lead qualification to autonomous appointment scheduling, knowledge base retrieval (RAG), payments, human handoff, and advanced data manipulation via custom code.

The solution resolves critical operational business bottlenecks, eliminating human support response latency, reducing First Response Time (FRT) to zero, and ensuring infrastructure scalability with high reliability and fault-tolerant exception handling.

---

## 🏗️ System Architecture & Workflow Topology
The ecosystem is driven by a **Central Router Agent** acting as the operational brain, dispatching user intents to specialized, modular sub-workflows located in the `workflows/` directory.

### 1. Central Routing & Core
*   **`1.00-whatsapp-ai-router-core.json`**: The master router workflow. Handles channel webhooks, audio/text processing, conversational memory, and role-based prompt intelligence to accurately dispatch users to the appropriate sub-workflow.

### 2. Scheduling & Critical Operations Module (`core`)
*   **`1.01-core-check-availability.json`**: Real-time database/calendar slot availability queries to prevent scheduling conflicts (double-booking prevention).
*   **`1.02-core-book-appointment.json`**: Executes the booking transaction, validating client payloads and persisting records into the database.
*   **`1.03-core-cancel-appointment.json`**: Manages automated cancellation logic and frees up operational grid slots.

### 3. Knowledge Base & Information (`kb`)
*   **`1.04-kb-services-info.json`**: Retrieves structured data regarding service catalogs, duration estimates, and technical specifications.
*   **`1.05-kb-location-contact.json`**: Delivers logistical data, geolocation, and institutional contact touchpoints.
*   **`1.06-kb-membership-plans.json`**: Manages queries regarding subscription tiers and recurring packages.
*   **`1.07-kb-policies-rules.json`**: Answers inquiries regarding cancellation rules, grace periods, and internal policies.

### 4. Business Operations & Billing (`ops`)
*   **`1.08-ops-billing-payments.json`**: Processes financial info, accepted payment gateways, and billing validations.

### 5. Exceptions, Small Talk & Handoff (`handoff` / `exception`)
*   **`1.09-ai-smalltalk-handler.json`**: Manages casual dialogue and social interactions to maintain the persona's conversational fluidity and empathy.
*   **`1.10-handoff-human-agent.json`**: Human-in-the-loop escalation protocol. Detects user frustration, complex requests, or specific triggers to route conversations to human desks.
*   **`1.11-subagent-owner-routing.json`**: Specialized routing for executive scheduling, VIP stakeholder calendars, or owner-level exception rules.
*   **`1.12-exception-fallback-handler.json`**: Safety fallback mechanism for malformed inputs, API timeouts, or LLM comprehension failures.
*   **`1.13-session-closure-handler.json`**: Manages conversational session teardown, CSAT feedback collection, or ticket archiving.

---

## 🛠️ Technology Stack
*   **Orchestration & Infrastructure:** n8n (Self-hosted on Hostinger KVM 2 VPS / Enterprise architecture)
*   **Artificial Intelligence & NLP:** Google Gemini LLMs integrated via LangChain and native n8n AI nodes for entity extraction, intent routing, and conversational state management.
*   **Custom Code & Logic:** Custom **JavaScript / TypeScript** code nodes for advanced data manipulation, payload transformation, and complex business logic.
*   **Channels & Messaging:** WhatsApp Business API triggered via secure Webhooks.
*   **Persistence & State Management:** Supabase (Relational database and schema structuring) and Redis (Real-time session state tracking and caching).