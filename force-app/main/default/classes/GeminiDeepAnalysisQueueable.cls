/**
 * @description       : Phase 2 of the AI Pipeline. Performs Deep Analysis using Gemini.
 *                      v4.1: Hardened for Rate Limits and Version Tracking.
 *
 * @deprecated Superseded by GeminiBatchProcessor (v4.2 Unified Engine).
 *             In v4.1 this class handled Deep Analysis as Phase 2 of a two-phase pipeline.
 *             In v4.2 both Filter and Deep Analysis are combined into a single GeminiBatchProcessor
 *             prompt, eliminating the inter-phase "Burst 429" risk that caused silent failures.
 *             Alternatives considered: chained Queueables with 5s delay (rejected: fragile, hits
 *             stack-depth limits). Retained in org for reference only.
**/
public class GeminiDeepAnalysisQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> jobIds;

    public GeminiDeepAnalysisQueueable(List<Id> jobIds) {
        this.jobIds = jobIds;
    }

    public void execute(QueueableContext context) {
        if (jobIds == null || jobIds.isEmpty()) return;

        // 1. Retrieve the Anchor
        Candidate_Profile__c profile;
        try {
            profile = [SELECT CV_Text__c FROM Candidate_Profile__c WHERE Is_Active_Profile__c = TRUE LIMIT 1];
        } catch (Exception e) {
            GeminiHandler.publishLogs();
            return; 
        }

        // 2. Process only the FIRST job
        Id currentJobId = jobIds.remove(0);
        Job_Application__c job = [
            SELECT Id, Name, Job_Description__c, Outreach_Draft__c, Strategy_Note__c, 
                   Match_Confidence__c, Primary_Rejection_Reason__c 
            FROM Job_Application__c WHERE Id = :currentJobId
        ];

        // 3. Retrieve Style Guide
        List<Job_Application__c> examples = [
            SELECT Outreach_Draft__c FROM Job_Application__c 
            WHERE Good_Example_For_AI__c = TRUE 
            ORDER BY CreatedDate DESC LIMIT 3
        ];
        
        String styleGuide = '';
        if (!examples.isEmpty()) {
            styleGuide = 'STYLE GUIDE:\n';
            for (Job_Application__c ex : examples) {
                if (String.isNotBlank(ex.Outreach_Draft__c)) {
                    styleGuide += 'EXAMPLE:\n' + ex.Outreach_Draft__c.left(500) + '...\n\n';
                }
            }
        }

        try {
            String prompt = buildDeepAnalysisPrompt(job, profile, styleGuide);
            String jsonResponse = GeminiHandler.generateContent(prompt);
            
            if (String.isNotBlank(jsonResponse)) {
                Map<String, Object> res = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
                
                job.Outreach_Draft__c = (String) res.get('outreach_draft');
                job.Strategy_Note__c = (String) res.get('strategy_html'); 
                job.Match_Confidence__c = (String) res.get('match_confidence'); 
                job.Status__c = 'AI Analyzed';
                
                // v4.1: Update Version Label
                job.Prompt_Version__c = 'v4.1 - Internal Systems Architecture';
                
                update job;
            }
        } catch (Exception e) {
            job.Status__c = 'Manual Review';
            update job;
        }

        // 4. Chain next job
        if (!jobIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeminiDeepAnalysisQueueable(jobIds));
        }

        GeminiHandler.publishLogs();
    }

    private String buildDeepAnalysisPrompt(Job_Application__c job, Candidate_Profile__c profile, String styleGuide) {
        String description = (job.Job_Description__c != null) ? job.Job_Description__c.left(3000) : job.Name;
        return 
            'ROLE: Senior Internal Systems Architect. \n' +
            'TASK: Analyze job against profile. Return RAW JSON ONLY. \n\n' +
            'MY PROFILE: \n' + profile.CV_Text__c.left(4000) + '\n\n' +
            styleGuide + '\n' +
            'JOB DESCRIPTION: \n' + description + '\n\n' +
            'JSON SCHEMA: { "outreach_draft": "...", "strategy_html": "...", "match_confidence": "High|Medium|Low" }';
    }
}