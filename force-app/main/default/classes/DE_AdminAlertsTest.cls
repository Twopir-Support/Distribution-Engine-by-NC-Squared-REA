@IsTest
private class DE_AdminAlertsTest {
    private static void alertsTo(String emails, Integer threshold) {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Admin_Alert_Emails__c = emails;
        s.Failure_Alert_Threshold__c = threshold;
        update s;
        DE_Settings.setForTransaction(null);
    }

    @IsTest
    static void noAlertsWithoutRecipients() {
        alertsTo(null, 1);
        insert new DE_Territory_Log__c(Record_Id__c = 'r1', In_Error__c = true, Attempts__c = 5, Processed_At__c = System.now());
        Assert.areEqual(0, DE_AdminAlerts.checkAll(System.now()), 'No recipients, no alerts');
        Assert.isFalse(DE_AdminAlerts.send(DE_AdminAlerts.SCHEDULER_RESTARTED, 'x'), 'Not sent');
    }

    @IsTest
    static void repeatedFailuresAreEmailedOncePerHour() {
        alertsTo('ops@example.com, lead@example.com', 3);
        insert new List<DE_Territory_Log__c>{
            new DE_Territory_Log__c(Record_Id__c = 'r1', In_Error__c = true, Attempts__c = 3, Processed_At__c = System.now()),
            new DE_Territory_Log__c(Record_Id__c = 'r2', In_Error__c = true, Attempts__c = 1, Processed_At__c = System.now())
        };
        insert new DE_Record_Detail__c(Record_Id__c = 'd1', On_Hold_Until__c = System.now().addMinutes(30));
        insert new DE_Assignment_Log__c(Record_Id__c = 'x1', Status__c = 'Error', Reassign_Error_At__c = System.now().addMinutes(-5));

        Integer sent = DE_AdminAlerts.checkAll(System.now());

        Assert.areEqual(3, sent, 'Classifier, distribution and reassignment alerts');
        Assert.areEqual(3, DE_AdminAlerts.sent.size(), 'Three emails');
        Assert.areEqual(new List<String>{ 'ops@example.com', 'lead@example.com' }, DE_AdminAlerts.sent[0].getToAddresses(), 'Recipients');
        Assert.isTrue(DE_AdminAlerts.sent[0].getPlainTextBody().contains('Territory: 1 records'), DE_AdminAlerts.sent[0].getPlainTextBody());
        Assert.areEqual(3, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Health Checker' AND Status__c = 'Warning'], 'Each alert logged');
        Assert.areEqual(0, DE_AdminAlerts.checkAll(System.now()), 'Throttled for an hour');
    }

    @IsTest
    static void throttleSurvivesWithoutTheCache() {
        alertsTo('ops@example.com', 1);
        insert new DE_Run_Log__c(
            Process__c = 'Health Checker',
            Status__c = 'Warning',
            Started_At__c = System.now().addMinutes(-10),
            Message__c = DE_AdminAlerts.PREFIX + DE_AdminAlerts.SCHEDULER_RESTARTED + '\nearlier'
        );
        Assert.isTrue(DE_AdminAlerts.sentRecently(DE_AdminAlerts.SCHEDULER_RESTARTED), 'Found in the run logs');
        Assert.isFalse(DE_AdminAlerts.sentRecently(DE_AdminAlerts.CLASSIFIER_FAILURES), 'Other categories unaffected');
        Assert.isFalse(DE_AdminAlerts.send(DE_AdminAlerts.SCHEDULER_RESTARTED, 'again'), 'Not resent within the hour');
        Assert.isTrue(DE_AdminAlerts.send(DE_AdminAlerts.CLASSIFIER_FAILURES, 'first'), 'Sent');
    }

    @IsTest
    static void cacheFallsBackToTheTransaction() {
        DE_TestFactory.settings();
        Assert.areEqual('abc123', DE_Cache.key('a-b_c 1/2/3'), 'Keys are alphanumeric');
        Assert.isNull(DE_Cache.get('missing'), 'Nothing cached');
        DE_Cache.put('greeting', 'hello');
        Assert.areEqual('hello', DE_Cache.get('greeting'), 'Cached for the transaction');
        DE_Cache.remove('greeting');
        Assert.isNull(DE_Cache.get('greeting'), 'Removed');

        String before = DE_Cache.classifierKey('territories', 'Lead');
        Assert.areEqual(before, DE_Cache.classifierKey('territories', 'Lead'), 'Stable until configuration changes');
        insert new DE_Territory__c(Name = 'New', Object_API_Name__c = 'Lead', Status__c = 'Draft', Priority__c = 1);
        Assert.areNotEqual(before, DE_Cache.classifierKey('territories', 'Lead'), 'Configuration DML invalidates the classifier cache');
    }

    @IsTest
    static void territoriesAreServedFromTheCacheUntilChanged() {
        DE_TestFactory.settings();
        insert new DE_Territory__c(Name = 'UK', Object_API_Name__c = 'Lead', Status__c = 'Active', Priority__c = 1, Countries__c = 'United Kingdom');
        List<DE_Territory__c> first = DE_TerritoryClassifier.territories('Lead');
        Integer queries = Limits.getQueries();
        List<DE_Territory__c> second = DE_TerritoryClassifier.territories('Lead');
        Assert.areEqual(queries, Limits.getQueries(), 'Second read served from the cache');
        Assert.areEqual(first.size(), second.size(), 'Same territories');
        insert new DE_Territory__c(Name = 'FR', Object_API_Name__c = 'Lead', Status__c = 'Active', Priority__c = 2, Countries__c = 'France');
        Assert.areEqual(2, DE_TerritoryClassifier.territories('Lead').size(), 'Reloaded after the change');
    }
}
