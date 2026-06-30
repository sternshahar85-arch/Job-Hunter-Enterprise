/**
 * @description       : Scheduled Job to trigger the Daily Ingestion Cycle.
 *                      Runs the JSearchService to fetch and process new job listings.
 * @author            : Shahar Stern
 * @group             : Automation
 * @version           : 4.1
**/
public class JSearchScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        try {
            // Executes the Active Ingestion Engine
            JSearchService.fetchAndInsertJobs();
        } catch (Exception e) {
            // Safety Net: Log critical scheduler failures to the database
            System_Log__c log = new System_Log__c(
                Component__c = 'JSearchScheduler',
                Error_Level__c = 'Critical',
                Message__c = 'Scheduler Execution Failed: ' + e.getMessage()
            );
            insert log;
        }
    }
}