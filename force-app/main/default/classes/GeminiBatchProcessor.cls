/**
 * @description : The active AI processing engine for Job Hunter Enterprise (v4.2+).
 *                Implements the Unified Resilient Engine: a single Gemini API call per record
 *                performs both role filtering and deep architectural analysis.
 *
 * Architectural decisions:
 *
 * 1. Unified Prompt (filter + analysis in one call):
 *    Problem: v4.1 used two sequential API calls per record (GeminiLazyFilterQueueable ->
 *    GeminiDeepAnalysisQueueable). Google's burst-protection triggered 429 errors on the
 *    second call even on paid tiers, causing silent failures where jobs were never fully analyzed.
 *    Decision: Combine both stages into one prompt. A record is either fully processed or
 *    explicitly marked AI Failed. No silent partial states.
 *    Benefit: ~50% token cost reduction and elimination of inter-phase 429 risk.
 *    Alternatives considered: Chained Queueables with 5s System.sleep(); rejected because
 *    sleep() risks Apex CPU timeout and hits Queueable stack-depth limits.
 *
 * 2. Batch Scope = 1 (The Drip Pattern):
 *    Problem: Processing multiple records per batch execution sends concurrent heavy requests
 *    to Gemini within milliseconds, triggering burst-rate 429s regardless of tier.
 *    Decision: Database.executeBatch(..., 1) gives each record its own transaction window,
 *    creating a natural 1-2 second gap between API calls, which guarantees rate-limit compliance
 *    without any sleep() or delay logic.
 *    Alternatives considered: CMDT-driven scope size; rejected because any scope > 1
 *    reintroduces the burst risk; the correct value is always 1 for Gemini AI callouts.
 *
 * 3. Single DML at end of execute() (Buffering Pattern):
 *    Problem: Salesforce forbids DML before a callout in the same transaction. Any attempt
 *    to update a record or insert a log before the Gemini callout throws "Uncommitted work pending".
 *    Decision: Mutate records in-memory during the loop; commit one Database.update(scope, false)
 *    and flush GeminiHandler.publishLogs() only after all callouts in the execute() scope complete.
 *
 * 4. AI Failed state (State Machine):
 *    Problem: v4.1 left failed records in Raw Import, making it impossible to distinguish
 *    between "waiting to be processed" and "already tried and crashed".
 *    Decision: Any null response or exception transitions the record to AI Failed and populates
 *    AI_Debug_Log__c with the specific failure reason, enabling targeted retry and reporting.
**/
public class GeminiBatchProcessor implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private List<Id> jobIds;
    private Integer successCount = 0;
    private Integer archivedCount = 0;
    private Integer failedCount = 0;

    public GeminiBatchProcessor(List<Id> jobIds) {
        this.jobIds = jobIds;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, Name, Job_Description__c, Status__c, AI_Debug_Log__c 
            FROM Job_Application__c 
            WHERE Id IN :jobIds
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Job_Application__c> scope) {
        // CMDT pause control: if Processing_Paused = 'true', skip without touching records
        System_Configuration__mdt pauseConfig = System_Configuration__mdt.getInstance('Processing_Paused');
        if (pauseConfig != null && 'true'.equalsIgnoreCase(pauseConfig.Value__c)) {
            GeminiHandler.publishLogs();
            return;
        }

        Candidate_Profile__c profile = [SELECT CV_Text__c FROM Candidate_Profile__c WHERE Is_Active_Profile__c = TRUE LIMIT 1];

        for (Job_Application__c job : scope) {
            try {
                String prompt = buildUnifiedPrompt(job, profile);
                String jsonResponse = GeminiHandler.generateContent(prompt);
                
                if (String.isNotBlank(jsonResponse)) {
                    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
                    String action = (String) result.get('action');

                    if (action == 'skip') {
                        job.Status__c = 'Archived';
                        job.Primary_Rejection_Reason__c = (String) result.get('reason');
                        archivedCount++;
                    } else {
                        job.Status__c = 'AI Analyzed';
                        job.Outreach_Draft__c = (String) result.get('outreach_draft');
                        job.Strategy_Note__c = (String) result.get('strategy_html'); 
                        job.Match_Confidence__c = (String) result.get('match_confidence'); 
                        job.Prompt_Version__c = 'v4.2 - Unified Resilient Engine';
                        successCount++;
                    }
                    job.AI_Debug_Log__c = 'Success'; // Clear previous errors
                } else {
                    job.Status__c = 'AI Failed';
                    job.AI_Debug_Log__c = 'Gemini returned null response.';
                    failedCount++;
                }
            } catch (Exception e) {
                job.Status__c = 'AI Failed';
                job.AI_Debug_Log__c = 'Exception: ' + e.getMessage();
                failedCount++;
            }
        }

        // SINGLE DML: Update all records at the very end of the transaction
        Database.update(scope, false);
        
        // Flush buffered logs
        GeminiHandler.publishLogs();
    }

    public void finish(Database.BatchableContext BC) {
        System_Log__c log = new System_Log__c(
            Component__c = 'GeminiBatchProcessor',
            Error_Level__c = 'Info',
            Message__c = 'Unified Batch Complete. Success: ' + successCount + ', Archived: ' + archivedCount + ', Failed: ' + failedCount
        );
        insert log;
    }

    private String buildUnifiedPrompt(Job_Application__c job, Candidate_Profile__c profile) {
        String descr = (job.Job_Description__c != null) ? StringUtil.stripPii(job.Job_Description__c.left(3000)) : job.Name;
        return 
            'ROLE: Senior Internal Systems Architect. \n' +
            'TASK: Perform a two-stage analysis in ONE response. \n\n' +
            'STAGE 1 (Filter): Check if job is a Sales role, Ghost job, or Pure Engineering. \n' +
            'STAGE 2 (Analysis): If it passes Stage 1, generate a Technical Alignment Matrix and Outreach Draft. \n\n' +
            'MY PROFILE: \n' + profile.CV_Text__c.left(3000) + '\n\n' +
            'JOB DESCRIPTION: \n' + descr + '\n\n' +
            'OUTPUT RAW JSON ONLY: \n' +
            '{ \n' +
            '  "action": "proceed" | "skip", \n' +
            '  "reason": "If skip, why?", \n' +
            '  "outreach_draft": "If proceed, the draft", \n' +
            '  "strategy_html": "If proceed, the HTML table", \n' +
            '  "match_confidence": "High|Medium|Low" \n' +
            '}';
    }
}