/**
 * @description       : Self-Healing Mechanism.
 *                      Monitors the "Active" job capacity (WIP Limit).
 *                      If slots are available, releases older records from "Backlog" to "New".
 * @author            : Shahar Stern
 * @group             : Orchestration
 * @version           : 4.1
**/
public class BacklogRecoveryService implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            checkAndReleaseBacklog();
        } catch (Exception e) {
            logError('Backlog Recovery Failed: ' + e.getMessage());
        }
    }

    public static void checkAndReleaseBacklog() {
        // 1. Retrieve WIP Limit from Metadata (Default: 50)
        Integer wipLimit = 50; 
        System_Configuration__mdt config = System_Configuration__mdt.getInstance('WIP_Limit_Count');
        if (config != null && config.Value__c != null) {
            wipLimit = Integer.valueOf(config.Value__c);
        }

        // 2. Check Current Capacity (Active Jobs)
        Integer currentActiveJobs = [
            SELECT Count() 
            FROM Job_Application__c 
            WHERE Status__c IN ('New', 'AI Analyzed')
        ];

        // 3. Calculate Available Slots
        Integer slotsAvailable = wipLimit - currentActiveJobs;

        // 4. Release from Backlog (FIFO Strategy)
        if (slotsAvailable > 0) {
            List<Job_Application__c> jobsToRelease = [
                SELECT Id, Status__c 
                FROM Job_Application__c 
                WHERE Status__c = 'Backlog' 
                ORDER BY CreatedDate ASC 
                LIMIT :slotsAvailable
            ];

            if (!jobsToRelease.isEmpty()) {
                for (Job_Application__c job : jobsToRelease) {
                    // Changing status to 'New' will re-trigger the Async Pipeline
                    job.Status__c = 'New'; 
                }
                
                // Commit changes
                update jobsToRelease;
            }
        }
    }

    // Helper: Centralized Logging
    private static void logError(String msg) {
        System_Log__c log = new System_Log__c(
            Component__c = 'BacklogRecoveryService',
            Error_Level__c = 'Error',
            Message__c = msg.left(32768)
        );
        insert log;
    }
}