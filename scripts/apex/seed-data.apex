// Seed data for Job Hunter Enterprise scratch org
// All data is synthetic. Do not seed real personal information.

// 1. Candidate Profile
Candidate_Profile__c profile = new Candidate_Profile__c(
    Name = 'Demo Candidate',
    Is_Active_Profile__c = true,
    CV_Text__c = 'Business Systems Analyst with 5 years experience in Salesforce platform administration, ' +
                 'Apex development, and business process automation. Certified Salesforce Administrator. ' +
                 'Experience with Flow Builder, SOQL, REST API integrations, and stakeholder requirements gathering. ' +
                 'Background in ERP implementations and cross-functional project delivery.',
    Keywords__c = 'Salesforce,Apex,Flow,BSA,Integration,REST API',
    Target_Role_Titles__c = 'Business Systems Analyst,Salesforce Administrator,Solution Architect'
);
insert profile;

// 2. Sample Job Applications
List<Job_Application__c> jobs = new List<Job_Application__c>{
    new Job_Application__c(
        Name = 'Salesforce Business Analyst - Acme Corp',
        Status__c = 'Raw Import',
        Job_Description__c = 'We are looking for a Salesforce Business Analyst to join our Revenue Operations team. ' +
                             'Responsibilities include gathering requirements, configuring Salesforce Sales Cloud, ' +
                             'building automation using Flow Builder, and collaborating with engineering on integrations. ' +
                             'Required: 3+ years Salesforce experience, strong communication skills, Salesforce Admin certification preferred.',
        Company_Name_Text__c = 'Acme Corp',
        Source_URL__c = 'https://example.com/job/1'
    ),
    new Job_Application__c(
        Name = 'Systems Implementation Consultant - Beta Technologies',
        Status__c = 'Raw Import',
        Job_Description__c = 'Beta Technologies seeks a Systems Implementation Consultant to lead CRM deployments ' +
                             'for enterprise clients. You will manage end-to-end implementations, conduct user training, ' +
                             'and own post-go-live support. Experience with Salesforce or similar CRM platforms required. ' +
                             'Strong analytical and project management skills essential.',
        Company_Name_Text__c = 'Beta Technologies',
        Source_URL__c = 'https://example.com/job/2'
    ),
    new Job_Application__c(
        Name = 'Cold Calling Sales Rep - Fast Money Inc',
        Status__c = 'Raw Import',
        Job_Description__c = 'Uncapped commission opportunity. Hunter mentality required. ' +
                             'Outbound cold calling to generate new business pipeline. ' +
                             'Quota-carrying role with aggressive targets. SDR experience preferred.',
        Company_Name_Text__c = 'Fast Money Inc',
        Source_URL__c = 'https://example.com/job/3'
    )
};
insert jobs;

System.debug('Seed complete. Profile: ' + profile.Id + '. Jobs: ' + jobs.size());
