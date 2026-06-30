public class JobFilterService {

    private static List<String> blacklist = new List<String>();
    private static List<String> techlist = new List<String>();

    static {
        // Defensive loading: read both keyword lists from CMDT at class init
        Map<String, System_Configuration__mdt> config = System_Configuration__mdt.getAll();

        // Load blacklist keywords (e.g. "quota,cold calling,commission")
        if (config.containsKey('Blacklist_Keywords') && config.get('Blacklist_Keywords').Value__c != null) {
            blacklist = config.get('Blacklist_Keywords').Value__c.toLowerCase().split(',');
        } else {
            System.debug('WARNING: Metadata record "Blacklist_Keywords" not found or empty.');
        }

        // Load tech keyword allowlist (e.g. "salesforce,apex,flow,bsa")
        if (config.containsKey('Tech_Keywords') && config.get('Tech_Keywords').Value__c != null) {
            techlist = config.get('Tech_Keywords').Value__c.toLowerCase().split(',');
        } else {
            System.debug('WARNING: Metadata record "Tech_Keywords" not found or empty.');
        }
    }

    public static Boolean shouldProcessJob(Job_Application__c job) {
        if (job == null) return false;
        
        String content = ((job.Name != null ? job.Name : '') + ' ' + (job.Job_Description__c != null ? job.Job_Description__c : '')).toLowerCase();
        
        // 1. Blacklist check: reject immediately if any banned keyword found
        if (!blacklist.isEmpty()) {
            for (String badWord : blacklist) {
                if (String.isNotBlank(badWord) && content.contains(badWord.trim())) {
                    job.Status__c = 'Archived';
                    job.Strategy_Note__c = 'Auto-Filtered: Contains blacklist keyword "' + badWord.trim() + '"';
                    return false;
                }
            }
        }

        // 2. Tech keyword check: job must contain at least one relevant tech term
        // If the list is empty (config error), default to allow; prevents a misconfiguration from blocking everything
        if (techlist.isEmpty()) return true;

        Boolean hasTech = false;
        for (String techWord : techlist) {
            if (String.isNotBlank(techWord) && content.contains(techWord.trim())) {
                hasTech = true;
                break;
            }
        }

        if (!hasTech) {
            job.Status__c = 'Archived';
            job.Strategy_Note__c = 'Auto-Filtered: No relevant tech keywords found.';
            return false;
        }

        return true;
    }
}