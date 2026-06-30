# Job Hunter Enterprise v4.2
### Salesforce-Native AI Recruitment Automation | Internal Systems Portfolio

**Role:** Business Systems Analyst  
**Platform:** Salesforce (Native-First / Aura) + Google Gemini API  
**Status:** Built and validated against real data.

📄 [One-page architecture overview (PDF)](docs/Job%20Hunter%20Enterprise%20One-Pager.pdf)

---

## Overview

Job Hunter Enterprise is a fully custom Salesforce platform that automates the filtering and architectural analysis of job listings using Google's Gemini AI. It was designed and built as a working internal tool, validated through discrete testing phases against real job-listing data, not built as a demo or tutorial project.

The system applies enterprise architecture principles to a personal use case: rather than reading every job description manually, it ingests listings from an external API, runs them through an AI-powered filter and analysis engine, and surfaces only the roles worth pursuing, complete with a pre-drafted architectural alignment proposal.

v4.2 represents a full architectural stabilization pass, moving from a fragile two-phase AI pipeline to a unified, rate-limit-resilient engine with explicit state management and transaction integrity.

---

## System Architecture

### Ingestion Layer

- **Automated:** `JSearchService.cls` runs on a scheduled Apex job (`JSearchScheduler.cls`), pulling listings from the JSearch API (RapidAPI) via Named Credentials.
- **Manual:** A Salesforce Screen Flow hosted on a public Experience Cloud site (Aura runtime) allows direct entry without org access.
- **Security:** "Ingest & Purge" protocol. All external records enter as `Raw Import` and cannot be promoted to active statuses by the ingestion layer directly.
- **Deduplication:** Two-key strategy. `Job_Key__c` (External ID) handles API-level deduplication by `job_id`. `Job_Hash__c` (SHA-256 of stripped, normalized content) catches the same listing posted with different IDs, which is common with aggregator APIs.

### Processing Core: The Drip Pattern

All AI processing routes through `GeminiBatchProcessor` invoked with `Database.executeBatch(..., 1)`.

**Why Scope = 1:**  
Google's Gemini API triggers burst-rate 429 errors when multiple heavy requests arrive within the same second, even on paid tiers. A batch scope of 1 gives each record its own transaction window and a natural 1-2 second gap between calls, guaranteeing rate-limit compliance without sleep loops (which risk Apex CPU timeouts) or Queueable chaining (which hits stack-depth limits).

### Intelligence Layer: Unified Resilient Engine

`GeminiBatchProcessor` performs filtering and deep analysis in a single Gemini API call per record.

**Why unified:**  
v4.1 used two sequential calls per record. Google's burst protection blocked the second call frequently, leaving records permanently unanalyzed with no visible failure signal. A single call means a record is either fully processed or explicitly marked `AI Failed`. No silent partial states.

**Prompt construction:**
- Stage 1 (filter): Ghost Job detection, Anti-Sales filter (quota/cold calling/revenue generation), Goldilocks rule (rejects pure engineering, accepts Salesforce/BSA/Flow/low-code)
- Stage 2 (analysis, if Stage 1 passes): Technical Alignment Matrix (HTML table) and outreach draft, grounded in `Candidate_Profile__c`

**Context grounding:**  
The active `Candidate_Profile__c` record (structured Markdown) is injected into every prompt. The AI is explicitly forbidden from referencing skills or certifications not present in this anchor. A Few-Shot style guide (records flagged `Good_Example_For_AI__c = TRUE`) shapes tone and structure.

**Format resilience:**  
`GeminiHandler.cleanJson()` uses `Pattern.compile('(?s)\\{.*\\}')` to extract the JSON object from responses regardless of markdown fencing. Gemini 2.5 Flash wraps outputs inconsistently, so string replacement alone is insufficient.

### State Machine

| Status | Meaning |
|--------|---------|
| `Raw Import` | Ingested, not yet processed |
| `Archived` | Filtered out by AI (Ghost Job / Sales role / mismatch) |
| `AI Analyzed` | Passed filter; Technical Alignment Matrix and outreach draft ready |
| `AI Failed` | API error, null response, or parse failure. Reason captured in `AI_Debug_Log__c` |
| `Applied` | Human reviewed and application sent |

`AI Failed` was introduced in v4.2, replacing v4.1's `Manual Review` status, which was set after exhausting 3 retry attempts via exponential backoff. v4.2 removes the retry loop entirely: a single Drip Pattern transaction per record either succeeds or fails immediately, with the specific reason captured in `AI_Debug_Log__c` rather than a generic system log entry.

**Data note:** The org retains 56 legacy records still in `Manual Review`, the pre-v4.2 retry-exhaustion status (see above). These predate the v4.2 stabilization pass and were left undisturbed as a data-quality audit trail rather than reprocessed or deleted. They are excluded from all current pipeline metrics in this document.

---

## Technical Highlights

### Transaction Integrity: Single DML Pattern
Salesforce forbids DML before a callout in the same transaction. `GeminiBatchProcessor` accumulates all field updates in memory during the execution loop, then commits a single `Database.update(scope, false)` and flushes buffered logs via `GeminiHandler.publishLogs()` only after all callouts complete.

### Runtime Configuration via Custom Metadata
Operational parameters (Gemini model name, WIP limits, search queries, keyword filters) are managed through `System_Configuration__mdt`. No code deployment is required to adjust pipeline behaviour.

### Gemini Model
Configured via `System_Configuration__mdt` (`Gemini_Model_Name` record). Code default: `gemini-2.5-flash`.

### Named Credentials
All external API authentication (Gemini, JSearch/RapidAPI) is handled via Salesforce Named Credentials and External Credential Principals. API keys are never present in code or plain-text metadata.

### Running-User Context and PII Handling
`GeminiBatchProcessor` is declared without a sharing keyword, meaning Apex runs in System mode and has visibility to all records regardless of sharing rules. This is intentional: the batch runs as a backend process with no user-facing context, and restricting sharing would prevent it from querying records it legitimately owns. The trade-off is documented here so reviewers can assess it directly rather than assume it is an oversight.

Before any job description text is sent to the Gemini API, `StringUtil.stripPii()` replaces email addresses and phone numbers with neutral tokens (`[EMAIL]`, `[PHONE]`). This scoped redaction targets the category of PII most commonly embedded in third-party job listings. Candidate profile data is internal and controlled; it is not subject to the same redaction step.

### Content-Based Deduplication
`StringUtil.generateHash()` strips HTML, lowercases, collapses whitespace, then applies SHA-256. This ensures `<b>Salesforce</b> Architect` and `Salesforce Architect` produce the same hash regardless of source formatting.

---

## ROI Model

| Tier | Status | Time Saved | Value |
|------|--------|-----------|-------|
| Tier 1 | `Archived` | 2 min | Automated rejection of Ghost Jobs and Sales roles |
| Tier 2 | `AI Analyzed` | 15 min | Technical Alignment Matrix and outreach draft ready for review |
| Tier 3 | `Applied` | 30 min | Full architectural proposal finalized and sent |

Tracked via `Time_Saved_Minutes__c` (formula field) and surfaced in the ROI Command Center dashboard.

---

## Governance & Operational Rules

- **The Rabbit Hole Protocol:** If debugging a specific error exceeds 10 minutes or 3 iterations, stop and reassess the approach rather than deepening the same path.
- **Zero-Noise Logging:** `System_Log__c` records only Warnings, Errors, and Critical failures. Successful single-record transactions are never logged. Batch completion summaries use the `Info` level.
- **WIP Limit:** `BacklogRecoveryService.cls` monitors active pipeline capacity against a CMDT-defined limit and releases records from `Backlog` status FIFO when slots are available.

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── GeminiHandler.cls                  # Gemini HTTP adapter, regex extraction, buffered logging
│   ├── GeminiBatchProcessor.cls           # Unified AI engine (active pipeline)
│   ├── JobApplicationTriggerHandler.cls   # Trigger orchestrator, hashing, batch dispatch
│   ├── JSearchService.cls                 # RapidAPI ingestion loop
│   ├── JSearchScheduler.cls               # Scheduled job wrapper
│   ├── JSearchDTO.cls                     # API response deserializer
│   ├── BacklogRecoveryService.cls         # WIP-limit-aware self-healing scheduler
│   ├── StringUtil.cls                     # Shared HTML stripping and hash generation
│   ├── JobFilterService.cls               # CMDT-driven keyword pre-filter
│   ├── JobScoringService.cls              # Weighted composite scoring (AI 70% / Keywords 25% / Title 5%)
│   ├── PortfolioController.cls            # Experience Cloud site controller
│   ├── GeminiLazyFilterQueueable.cls      # [DEPRECATED: superseded by GeminiBatchProcessor v4.2]
│   └── GeminiDeepAnalysisQueueable.cls    # [DEPRECATED: superseded by GeminiBatchProcessor v4.2]
└── triggers/
    └── JobApplicationTrigger.trigger      # Single trigger, delegates to handler
```

---

## Quick Start (Scratch Org)

To spin up a working environment from this repo:

```bash
# 1. Create a scratch org
sf org create scratch --definition-file config/project-scratch-def.json --alias jhe-scratch --duration-days 7

# 2. Deploy all metadata
sf project deploy start --target-org jhe-scratch

# 3. Seed synthetic data
sf apex run --file scripts/apex/seed-data.apex --target-org jhe-scratch

# 4. Open in browser
sf org open --target-org jhe-scratch
```

**After deploy, two manual steps are required before the AI pipeline runs:**

1. **Gemini Named Credential:** Setup > Named Credentials > Gemini_API > set the API key under External Credentials. Without this, `GeminiHandler.generateContent()` will throw a callout error.
2. **Trigger the pipeline:** In the App, select one of the seeded `Raw Import` records and update it to trigger `JobApplicationTrigger`. The batch processor will pick it up and attempt a Gemini API call.

The seed script creates three sample records: two realistic BSA/Salesforce roles and one intentional Sales role that the AI filter should archive automatically.

---

## Built by [Shahar Stern](https://www.linkedin.com/in/stern-shahar85/)
*Business Systems Analyst*
