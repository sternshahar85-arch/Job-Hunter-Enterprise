public class JSearchService {
    
    private static final Integer MAX_BATCH_SIZE = 50;
    // רשימה לאיסוף לוגים כדי למנוע שגיאת Uncommitted Work
    private static List<System_Log__c> pendingLogs = new List<System_Log__c>();

    public static void fetchAndInsertJobs() {
        Map<String, System_Configuration__mdt> config = System_Configuration__mdt.getAll();
        
        if (!config.containsKey('Job_Search_Query')) {
            addLog('Critical', 'Missing Metadata Configuration: Job_Search_Query');
            commitLogs();
            return;
        }

        String fullQuery = config.get('Job_Search_Query').Value__c;
        List<String> queryList = fullQuery.split(';'); 

        Map<String, Job_Application__c> allJobsToInsertMap = new Map<String, Job_Application__c>();

        for (String singleQuery : queryList) {
            if (allJobsToInsertMap.size() >= MAX_BATCH_SIZE) break; 

            try {
                List<Job_Application__c> jobsFromQuery = searchOneQuery(singleQuery.trim());
                for (Job_Application__c job : jobsFromQuery) {
                    if (allJobsToInsertMap.size() < MAX_BATCH_SIZE) {
                        allJobsToInsertMap.put(job.Job_Key__c, job);
                    }
                }
            } catch (Exception e) {
                addLog('Error', 'Failed processing query: ' + singleQuery + '. Error: ' + e.getMessage());
            }
        }

        // שמירת משרות
        if (!allJobsToInsertMap.isEmpty()) {
            try {
                Database.UpsertResult[] results = Database.upsert(allJobsToInsertMap.values(), Job_Application__c.Fields.Job_Key__c, false);
                analyzeResults(results);
            } catch (Exception e) {
                addLog('Critical', 'DML Failed: ' + e.getMessage());
            }
        }

        // רק בסוף - שמירת כל הלוגים שנאספו
        commitLogs();
    }

    private static List<Job_Application__c> searchOneQuery(String query) {
        List<Job_Application__c> results = new List<Job_Application__c>();
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
        String endpoint = 'callout:RapidAPI_JSearch/search?query=' + encodedQuery + '&date_posted=all&num_pages=1';
        
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(60000); 

        HttpResponse response = http.send(request);
        
        if (response.getStatusCode() == 200) {
            results = convertResponseToJobs(response.getBody(), query);
        } else {
            addLog('Error', 'API Failure - Query: ' + query + ' | Status: ' + response.getStatusCode() + ' | Body: ' + response.getBody().left(255));
        }
        
        return results;
    }

    private static List<Job_Application__c> convertResponseToJobs(String jsonBody, String queryTerm) {
        List<Job_Application__c> jobList = new List<Job_Application__c>();
        try {
            JSearchDTO dto = JSearchDTO.parse(jsonBody);
            if (dto == null || dto.data == null) return jobList;
            for (JSearchDTO.JobData job : dto.data) {
                Job_Application__c newJob = new Job_Application__c();
                newJob.Name = (job.job_title != null) ? job.job_title.left(80) : 'Unknown Title';
                newJob.Company_Name_Text__c = job.employer_name;
                newJob.Job_Description__c = job.job_description;
                newJob.Source_URL__c = job.job_apply_link;
                newJob.Job_Key__c = job.job_id;
                newJob.Status__c = 'Raw Import'; 
                jobList.add(newJob);
            }
        } catch (Exception e) {
            addLog('Error', 'Parse Error for query: ' + queryTerm + '. ' + e.getMessage());
        }
        return jobList;
    }

    // מתודה חדשה להוספת לוג לרשימה (ללא DML)
    private static void addLog(String level, String message) {
        pendingLogs.add(new System_Log__c(
            Error_Level__c = level,         
            Component__c = 'JSearchService', 
            Message__c = message.left(32768) 
        ));
    }

    // מתודה חדשה לביצוע ה-DML המרוכז בסוף
    private static void commitLogs() {
        if (!pendingLogs.isEmpty()) {
            insert pendingLogs;
            pendingLogs.clear();
        }
    }

    private static void analyzeResults(Database.UpsertResult[] results) {
        Integer errors = 0;
        for (Database.UpsertResult sr : results) {
            if (!sr.isSuccess()) errors++;
        }
        if (errors > 0) addLog('Error', 'DML Partial Failure. Errors: ' + errors);
    }
}