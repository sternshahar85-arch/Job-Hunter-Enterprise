/**
 * @description : Apex controller for the Job Hunter Hub public Experience Cloud site.
 *                Exposes aggregate pipeline statistics to the Aura UI component.
 *
 * without sharing rationale: This controller runs in the context of the Experience Cloud
 * Guest User, who has no record-level sharing on Job_Application__c by design (Create Only).
 * without sharing is required so the controller can read aggregate counts for display
 * without needing to open up object-level sharing to the Guest User profile.
 * No individual record data is exposed, only totals and status strings.
 *
 * Current status: DEMO. Returns hardcoded mock data while the live org accumulates
 * sufficient real records for meaningful aggregate display. The method signature and
 * wrapper structure are production-ready; swap the hardcoded block for SOQL aggregates
 * when connecting to real Job_Application__c data.
**/
// without sharing: required for Guest User context; see class header for full rationale
public without sharing class PortfolioController {

    @AuraEnabled(cacheable=true)
    public static PortfolioStatsWrapper getAgentStats() {
        PortfolioStatsWrapper dto = new PortfolioStatsWrapper();

        try {
            // DEMO: Mock data for UI validation. Replace with SOQL aggregates when going live.
            dto.agentStatus = 'ACTIVE';
            dto.totalJobsProcessed = 1240;
            dto.interviewsFound = 12;
            dto.liveTelemetry = new List<String>{
                'initializing neural network...',
                'scanning linkedin api...',
                'analyzing job description id: 99283',
                'matching skills: Salesforce Architect, Apex, LWC',
                'agent v3.7: high match detected (94%)'
            };
        } catch (Exception e) {
            System.debug('Error fetching stats: ' + e.getMessage());
        }

        return dto;
    }
}