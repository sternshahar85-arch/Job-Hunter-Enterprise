/**
 * @description : Shared string sanitization utilities for the Job Hunter Enterprise pipeline.
 *                Centralizes HTML stripping and hash generation used across multiple classes,
 *                ensuring consistent normalization at every point data enters the system.
 *
 * Design note: inline regex in each caller was rejected in favour of this utility because
 * hash consistency requires identical normalization. A single shared function guarantees
 * that JobApplicationTriggerHandler and any future ingestion path produce the same hash
 * for the same content, regardless of source formatting differences.
 */
public class StringUtil {

    /**
     * v3.5 Update: Aggressively removes HTML tags and special entities.
     * Essential for matching raw scraped data (Apify) with manual entries.
     */
    public static String stripHtml(String input) {
        if (String.isBlank(input)) return '';
        
        // 1. Use native Salesforce method for basic stripping
        String cleanText = input.stripHtmlTags();
        
        // 2. Clean common HTML entities that appear in Google Jobs/Apify data
        // These can break hash consistency if not handled.
        cleanText = cleanText.replaceAll('&nbsp;', ' ')
                             .replaceAll('&amp;', '&')
                             .replaceAll('&quot;', '"')
                             .replaceAll('&#39;', '\'')
                             .replaceAll('&lt;', '<')
                             .replaceAll('&gt;', '>')
                             .replaceAll('<[^>]+>', ''); // Final regex safety net
                             
        return cleanText.trim();
    }

    /**
     * Generates a SHA-256 Hash based on the content.
     * Logic: Strip HTML -> Lowercase -> Remove ALL whitespace -> Hash.
     * Ensure that "<b>Job</b> Description" matches "Job Description".
     */
    public static String generateHash(String input) {
        if (String.isBlank(input)) return null;

        // 1. Sanitization: Strip HTML artifacts
        String textWithoutHtml = stripHtml(input);

        // 2. Normalization: Lowercase and remove ALL types of whitespace (spaces, tabs, newlines)
        // This ensures the hash is identical regardless of formatting differences.
        String normalizedText = textWithoutHtml.toLowerCase().replaceAll('\\s+', '');

        if (String.isBlank(normalizedText)) return null;

        // 3. Calculate SHA-256 Hash
        Blob targetBlob = Blob.valueOf(normalizedText);
        Blob hash = Crypto.generateDigest('SHA-256', targetBlob);
        
        return EncodingUtil.convertToHex(hash);
    }
    
    /**
     * Strips common PII patterns from text before it reaches the Gemini API or any log.
     * Replaces email addresses and phone numbers with neutral tokens.
     * Scope: job description text only — candidate profile is controlled internal data.
     */
    public static String stripPii(String input) {
        if (String.isBlank(input)) return input;
        String cleaned = input.replaceAll('[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}', '[EMAIL]');
        cleaned = cleaned.replaceAll('(\\+?\\d[\\d\\s\\-().]{7,}\\d)', '[PHONE]');
        return cleaned;
    }

    /**
     * Helper to truncate strings to field limits to prevent DML errors.
     */
    public static String truncate(String input, Integer length) {
        if (String.isBlank(input)) return '';
        if (input.length() <= length) return input;
        return input.substring(0, length);
    }
}