public class PortfolioStatsWrapper {
    @AuraEnabled public String agentStatus {get;set;}      // Active / Idle / Thinking
    @AuraEnabled public Integer totalJobsProcessed {get;set;} 
    @AuraEnabled public Integer interviewsFound {get;set;}
    @AuraEnabled public List<String> liveTelemetry {get;set;} // הודעות ה"טרמינל"
    
    public PortfolioStatsWrapper() {
        this.agentStatus = 'OFFLINE';
        this.totalJobsProcessed = 0;
        this.interviewsFound = 0;
        this.liveTelemetry = new List<String>();
    }
}