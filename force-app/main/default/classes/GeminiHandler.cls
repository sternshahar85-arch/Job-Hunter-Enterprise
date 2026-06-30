/**
 * @description : Core HTTP adapter for the Google Gemini API.
 *                Handles request construction, response parsing, and buffered error logging.
 *
 * Architectural decisions:
 *
 * 1. Regex-based JSON extraction (cleanJson):
 *    Problem: Gemini 2.5 Flash non-deterministically wraps responses in markdown fences (```json).
 *    Decision: Pattern.compile('(?s)\\{.*\\}') extracts the raw JSON object regardless of surrounding text.
 *    Alternatives considered: String.replaceAll('```json',''); rejected because it breaks on
 *    responses where the model adds conversational text before or after the fence.
 *
 * 2. BLOCK_NONE safety override (all four harm categories):
 *    Problem: Public Sector and FedCiv job descriptions triggered Google's default safety filters,
 *    returning null candidates and causing silent pipeline failures.
 *    Decision: Override all four harm categories (HARASSMENT, HATE_SPEECH, SEXUALLY_EXPLICIT,
 *    DANGEROUS_CONTENT) to BLOCK_NONE. HARASSMENT was the primary false-positive source, but
 *    the others can also trigger on enforcement/authority/security-clearance language common in
 *    government and defense job descriptions. A partial override leaves the same silent-failure
 *    risk for a different category; all-or-nothing is the safer operational choice here.
 *
 * 3. Buffered logging (pendingLogs / publishLogs):
 *    Problem: Salesforce forbids DML before a callout in the same transaction. Direct insert of
 *    System_Log__c inside generateContent() caused "Uncommitted work pending" errors.
 *    Decision: Accumulate logs in a static list; caller flushes via publishLogs() after all callouts.
 *    Alternatives considered: @future logging; rejected because it loses transaction context
 *    and creates a second async job per record.
**/
public class GeminiHandler {
    
    private static List<System_Log__c> pendingLogs = new List<System_Log__c>();

    private static String getModelName() {
        System_Configuration__mdt config = System_Configuration__mdt.getInstance('Gemini_Model_Name');
        return (config != null && String.isNotBlank(config.Value__c)) ? config.Value__c : 'gemini-2.5-flash';
    }

    public static String generateContent(String prompt) {
        String endpoint = 'callout:Gemini_API/v1beta/models/' + getModelName() + ':generateContent';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000); 
        
        // All four harm categories set to BLOCK_NONE to prevent silent pipeline failures
        // on Public Sector and FedCiv job descriptions that trigger Google's default filters
        List<Object> safetySettings = new List<Object>{
            new Map<String, Object>{ 'category' => 'HARM_CATEGORY_HARASSMENT',        'threshold' => 'BLOCK_NONE' },
            new Map<String, Object>{ 'category' => 'HARM_CATEGORY_HATE_SPEECH',       'threshold' => 'BLOCK_NONE' },
            new Map<String, Object>{ 'category' => 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold' => 'BLOCK_NONE' },
            new Map<String, Object>{ 'category' => 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold' => 'BLOCK_NONE' }
        };

        Map<String, Object> bodyMap = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{ 'parts' => new List<Object>{ new Map<String, Object>{ 'text' => prompt } } }
            },
            'safetySettings' => safetySettings
        };
        
        req.setBody(JSON.serialize(bodyMap));
        
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                return parseResponse(res.getBody());
            } else {
                addLog('Error', 'Gemini API Error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                return null; 
            }
        } catch (Exception e) {
            addLog('Error', 'Gemini Callout Exception: ' + e.getMessage());
            return null;
        }
    }

    private static String parseResponse(String responseBody) {
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> candidates = (List<Object>) root.get('candidates');
            
            if (candidates == null || candidates.isEmpty()) {
                addLog('Warning', 'Gemini blocked content due to safety or empty response.');
                return null;
            }

            Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
            Map<String, Object> content = (Map<String, Object>) firstCandidate.get('content');
            List<Object> parts = (List<Object>) content.get('parts');
            Map<String, Object> firstPart = (Map<String, Object>) parts[0];
            return cleanJson((String) firstPart.get('text'));
            
        } catch (Exception e) {
            addLog('Error', 'Gemini Parse Error: ' + e.getMessage());
            return null;
        }
    }

    public static String cleanJson(String input) {
        if (String.isBlank(input)) return '';
        try {
            Pattern jsonPattern = Pattern.compile('(?s)\\{.*\\}');
            Matcher matcher = jsonPattern.matcher(input);
            if (matcher.find()) return matcher.group(0).trim();
        } catch (Exception e) {}
        return input.trim();
    }

    private static void addLog(String level, String msg) {
        pendingLogs.add(new System_Log__c(
            Component__c = 'GeminiHandler',
            Error_Level__c = level,
            Message__c = msg.left(32768)
        ));
    }

    public static void publishLogs() {
        if (!pendingLogs.isEmpty()) {
            insert pendingLogs;
            pendingLogs.clear();
        }
    }
}