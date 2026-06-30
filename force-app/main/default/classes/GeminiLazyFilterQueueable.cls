/**
 * @deprecated Superseded by GeminiBatchProcessor (v4.2 Unified Engine).
 *             JobApplicationTriggerHandler no longer routes to this class.
 *             Retained in org for reference; not part of the active pipeline.
 *             Active path: JobApplicationTriggerHandler -> GeminiBatchProcessor (Scope=1).
 **/
public class GeminiLazyFilterQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> jobIds;

    public GeminiLazyFilterQueueable(List<Id> jobIds) {
        this.jobIds = jobIds;
    }

    public void execute(QueueableContext context) {
        if (jobIds == null || jobIds.isEmpty()) return;

        // 1. Process only the first job in the list (one-at-a-time pattern)
        Id currentJobId = jobIds.remove(0);
        Job_Application__c job = [SELECT Id, Name, Job_Description__c FROM Job_Application__c WHERE Id = :currentJobId];

        try {
            // Stage 1: Lazy Filter
            String descr = (job.Job_Description__c != null) ? job.Job_Description__c.left(2500) : job.Name;
            String lazyPrompt = 'Analyze job. Return RAW JSON ONLY: {"action": "proceed" | "skip", "reason": "..."}. Job: ' + descr;

            String lazyResponse = GeminiHandler.generateContent(lazyPrompt);
            if (String.isNotBlank(lazyResponse)) {
                Map<String, Object> lazyResult = (Map<String, Object>) JSON.deserializeUntyped(lazyResponse);

                if ((String)lazyResult.get('action') == 'skip') {
                    job.Status__c = 'Archived';
                    job.Primary_Rejection_Reason__c = (String)lazyResult.get('reason');
                    update job;
                } else {
                    // Stage 2: Deep Analysis (runs in same execution to avoid extra Enqueue depth)
                    processDeepAnalysis(job);
                }
            }
        } catch (Exception e) {
            // On error: log and continue to next job rather than halting the chain
        }

        // 2. Chain to next job; the only permitted enqueue in this class
        if (!jobIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeminiLazyFilterQueueable(jobIds));
        }

        GeminiHandler.publishLogs();
    }

    // Helper: runs Deep Analysis within the same Queueable execution to avoid extra enqueue depth
    private void processDeepAnalysis(Job_Application__c job) {
        Candidate_Profile__c profile = [SELECT CV_Text__c FROM Candidate_Profile__c WHERE Is_Active_Profile__c = TRUE LIMIT 1];
        
        String deepPrompt = 'ROLE: Senior Systems Architect. TASK: Analyze job against profile. Return RAW JSON ONLY. \n' +
                           'PROFILE: ' + profile.CV_Text__c.left(3000) + '\n' +
                           'JOB: ' + job.Name + ' ' + (job.Job_Description__c != null ? job.Job_Description__c.left(2000) : '') + '\n' +
                           'JSON SCHEMA: {"outreach_draft": "...", "strategy_html": "...", "match_confidence": "High|Medium|Low"}';
        
        String deepResponse = GeminiHandler.generateContent(deepPrompt);
        if (String.isNotBlank(deepResponse)) {
            Map<String, Object> res = (Map<String, Object>) JSON.deserializeUntyped(deepResponse);
            job.Outreach_Draft__c = (String) res.get('outreach_draft');
            job.Strategy_Note__c = (String) res.get('strategy_html'); 
            job.Match_Confidence__c = (String) res.get('match_confidence'); 
            job.Status__c = 'AI Analyzed';
            update job;
        }
    }
}