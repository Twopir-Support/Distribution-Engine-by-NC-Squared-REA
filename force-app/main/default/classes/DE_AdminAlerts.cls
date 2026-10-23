/**
 * Failure alerts to administrators (Distribution Settings: Admin Alert Emails). Covers records that keep
 * failing classification or distribution, failed automatic reassignments and the health checker
 * restarting the scheduler. Each category is emailed at most once per hour; every alert sent is
 * recorded as a Health Checker run log.
 */
public without sharing class DE_AdminAlerts {
    public static final String CLASSIFIER_FAILURES = 'Classifier failures';
    public static final String DISTRIBUTION_FAILURES = 'Distribution failures';
    public static final String REASSIGN_FAILURES = 'Auto reassignment failures';
    public static final String SCHEDULER_RESTARTED = 'Scheduler restarted';
    public static final String PREFIX = 'Admin alert: ';

    @TestVisible
    private static List<Messaging.SingleEmailMessage> sent = new List<Messaging.SingleEmailMessage>();

    /** Checks every failure category and emails the ones with something to report. Returns alerts sent. */
    public static Integer checkAll(Datetime now) {
        if (DE_Settings.adminAlertEmails().isEmpty()) {
            return 0;
        }
        Integer threshold = DE_Settings.failureAlertThreshold();
        Integer alerts = 0;
        Map<String, Integer> classifier = DE_ClassifierLogs.repeatedFailures(threshold);
        if (!classifier.isEmpty()) {
            List<String> lines = new List<String>();
            for (String stage : classifier.keySet()) {
                lines.add(stage + ': ' + classifier.get(stage) + ' records');
            }
            alerts += send(
                    CLASSIFIER_FAILURES,
                    'Records failed classification ' + threshold + ' or more times in a row:\n' + String.join(lines, '\n') + '\n\nSee Distribution Logs > Classifier and Sync Logs.'
                )
                ? 1
                : 0;
        }
        Integer held = [SELECT COUNT() FROM DE_Record_Detail__c WHERE Failed_Attempts__c >= :threshold OR On_Hold_Until__c > :now];
        if (held > 0) {
            alerts += send(
                    DISTRIBUTION_FAILURES,
                    held + ' records failed distribution ' + threshold + ' or more times in a row or are on hold.\n\nSee Distribution Logs (status On Hold) and use Retry.'
                )
                ? 1
                : 0;
        }
        Datetime hourAgo = now.addHours(-1);
        Integer reassign = [SELECT COUNT() FROM DE_Assignment_Log__c WHERE Reassign_Error_At__c >= :hourAgo];
        if (reassign > 0) {
            alerts += send(REASSIGN_FAILURES, reassign + ' automatic reassignments failed in the last hour.\n\nSee Distribution Logs (status Error).') ? 1 : 0;
        }
        return alerts;
    }

    /** Emails the category unless it was already emailed in the last hour. Returns true when sent. */
    public static Boolean send(String category, String body) {
        List<String> to = DE_Settings.adminAlertEmails();
        if (to.isEmpty() || sentRecently(category)) {
            return false;
        }
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(to);
        m.setSaveAsActivity(false);
        m.setSenderDisplayName('Distribution Engine');
        m.setSubject('Distribution Engine: ' + category);
        m.setPlainTextBody(body + '\n\nOrg: ' + UserInfo.getOrganizationName() + ' (' + UserInfo.getOrganizationId() + ')');
        sent.add(m);
        if (!Test.isRunningTest() && Limits.getEmailInvocations() < Limits.getLimitEmailInvocations()) {
            try {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Admin alert not emailed: ' + e.getMessage());
            }
        }
        DE_RunLogger.log('Health Checker', 'Warning', 0, 0, 0, PREFIX + category + '\n' + body);
        DE_Cache.put('alert' + category, String.valueOf(System.now().getTime()));
        return true;
    }

    @TestVisible
    private static Boolean sentRecently(String category) {
        String cached = DE_Cache.get('alert' + category);
        if (cached != null && System.now().getTime() - Long.valueOf(cached) < 3600000) {
            return true;
        }
        Datetime hourAgo = System.now().addHours(-1);
        String marker = PREFIX + category;
        for (DE_Run_Log__c r : [
            SELECT Message__c
            FROM DE_Run_Log__c
            WHERE Process__c = 'Health Checker' AND Status__c = 'Warning' AND Started_At__c >= :hourAgo
            ORDER BY Started_At__c DESC
            LIMIT 50
        ]) {
            if (r.Message__c != null && r.Message__c.startsWith(marker)) {
                return true;
            }
        }
        return false;
    }
}
