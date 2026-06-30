public class JSearchDTO {
    public List<JobData> data;

    public class JobData {
        public String job_id;
        public String employer_name;
        public String job_title;
        public String job_description;
        public String job_apply_link;
        public String job_city;
        public String job_country;
        public String job_posted_at_datetime_utc;
    }

    public static JSearchDTO parse(String json) {
        // v4.1 Defensive Coding: Handle empty responses gracefully
        if (String.isBlank(json)) {
            return null;
        }
        
        // Note: Raw HTML stripping happens later in the Trigger (Sanitization Layer)
        return (JSearchDTO) System.JSON.deserialize(json, JSearchDTO.class);
    }
}