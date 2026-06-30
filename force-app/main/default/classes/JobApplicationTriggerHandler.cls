/**
 * @description : Master trigger handler for Job_Application__c.
 *                Enforces data integrity on insert/update (Before context) and routes
 *                new records into the async AI pipeline (After context).
 *
 * Architectural decisions:
 *
 * 1. Always routes to GeminiBatchProcessor with Scope=1 (no Queueable fork):
 *    v4.1 used a fork: small batches went to GeminiLazyFilterQueueable (Queueable),
 *    large batches to GeminiBatchProcessor (Batch). The fork was removed in v4.2 because:
 *    - Both paths now share the same Unified Prompt logic in GeminiBatchProcessor.
 *    - Scope=1 is the only safe value for Gemini AI callouts regardless of volume
 *      (see GeminiBatchProcessor for the Drip Pattern rationale).
 *    - Maintaining two parallel code paths increased complexity with no benefit.
 *
 * 2. StringUtil.stripHtml() for hash generation:
 *    Raw job descriptions from JSearch contain HTML tags. Hashing without stripping means
 *    "<b>Engineer</b>" and "Engineer" produce different hashes for identical content.
 *    StringUtil provides a shared, tested sanitization function rather than inline regex.
 *
 * 3. Content-based deduplication via SHA-256 (Job_Hash__c):
 *    Job_Key__c (External ID) handles API-level deduplication by job_id.
 *    Job_Hash__c catches the same job posted multiple times with different IDs;
 *    common with aggregator APIs. Two-key strategy covers both vectors.
**/
public class JobApplicationTriggerHandler {

    // Phase 1: Data Integrity (Hashing & Deduplication)
    public static void handleBeforeInsertUpdate(List<Job_Application__c> newRecords) {
        Set<String> hashesToCheck = new Set<String>();

        for (Job_Application__c job : newRecords) {
            if (job.Status__c == 'New' || job.Status__c == 'Raw Import') {
                String rawContent = job.Job_Description__c;
                if (String.isBlank(rawContent)) {
                    rawContent = job.Name + (job.Company_Name_Text__c != null ? job.Company_Name_Text__c : '');
                }
                
                // Using StringUtil for architectural consistency
                String cleanText = StringUtil.stripHtml(rawContent).trim().toLowerCase();
                
                Blob targetBlob = Blob.valueOf(cleanText);
                Blob hash = Crypto.generateDigest('SHA-256', targetBlob);
                job.Job_Hash__c = EncodingUtil.convertToHex(hash);
                
                if (hashesToCheck.contains(job.Job_Hash__c)) {
                    job.addError('Duplicate detected within the current ingestion batch.');
                } else {
                    hashesToCheck.add(job.Job_Hash__c);
                }
            }
        }
    }

    // Phase 2: Async Orchestration (The Resilient Path)
    public static void handleAfterInsertUpdate(List<Job_Application__c> newRecords, Map<Id, Job_Application__c> oldMap) {
        List<Id> jobIdsToProcess = new List<Id>();
        
        for (Job_Application__c job : newRecords) {
            Boolean isNew = (oldMap == null && (job.Status__c == 'Raw Import' || job.Status__c == 'New'));
            Boolean isRetry = (oldMap != null && job.Status__c == 'Raw Import' && oldMap.get(job.Id).Status__c != 'Raw Import');

            if (isNew || isRetry) {
                jobIdsToProcess.add(job.Id);
            }
        }

        if (!jobIdsToProcess.isEmpty()) {
            // Senior Move: Always use the Resilient Batch with size 1 to handle API Chaos
            Database.executeBatch(new GeminiBatchProcessor(jobIdsToProcess), 1);
        }
    }
}