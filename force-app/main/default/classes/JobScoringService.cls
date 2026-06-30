public without sharing class JobScoringService {

    // Wrapper for the composite score result
    public class ScoreResult {
        public Integer finalScore;
        public String explanation;
    }

    public static ScoreResult calculateMatch(String jobTitle, String jobDescription, Integer aiScore) {
        ScoreResult result = new ScoreResult();

        // 1. Retrieve active candidate profile (the scoring anchor)
        Candidate_Profile__c profile;
        try {
            profile = [SELECT Keywords__c, Target_Titles__c
                       FROM Candidate_Profile__c
                       WHERE Is_Active_Profile__c = true
                       LIMIT 1];
        } catch (Exception e) {
            // Fallback: return raw AI score if no profile is configured
            result.finalScore = aiScore;
            result.explanation = 'No active candidate profile found. Using raw AI score.';
            return result;
        }

        // 2. Keyword component (25% weight)
        // Rationale: keyword density provides a structured signal independent of AI subjectivity
        Double keywordScore = 0;
        if (String.isNotBlank(profile.Keywords__c) && String.isNotBlank(jobDescription)) {
            List<String> keywords = profile.Keywords__c.split(',');
            Integer matches = 0;
            for (String kw : keywords) {
                if (jobDescription.containsIgnoreCase(kw.trim())) {
                    matches++;
                }
            }
            keywordScore = (matches >= 5) ? 100 : (matches * 20); // 5 keyword matches = full component score
        }

        // 3. Title match component (5% weight)
        Double titleScore = 0;
        if (String.isNotBlank(profile.Target_Titles__c) && String.isNotBlank(jobTitle)) {
            List<String> targets = profile.Target_Titles__c.split(',');
            for (String target : targets) {
                if (jobTitle.containsIgnoreCase(target.trim())) {
                    titleScore = 100;
                    break;
                }
            }
        }

        // 4. Weighted composite: AI drives 70%, keywords 25%, title 5%
        // AI score carries the majority weight as it incorporates full JD context;
        // keyword and title signals correct for cases where AI confidence is borderline.
        Double finalCalc = (aiScore * 0.70) + (keywordScore * 0.25) + (titleScore * 0.05);

        result.finalScore = (Integer)Math.round(finalCalc);
        result.explanation = String.format(
            'Weighted Score: AI({0}%)={1}, Keywords(25%)={2}, Title(5%)={3}.',
            new List<Object>{ 70, Math.round(aiScore * 0.7), Math.round(keywordScore * 0.25), Math.round(titleScore * 0.05) }
        );

        return result;
    }
}