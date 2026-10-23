@IsTest
private class DE_RunLoggerAndNotifierTest {
    @IsTest
    static void logInsertsRunLog() {
        Test.startTest();
        DE_RunLogger.log('Scheduler', 'Success', 12, 10, 2, 'Run complete');
        Test.stopTest();

        DE_Run_Log__c r = [SELECT Process__c, Status__c, Records_Processed__c, Assignments__c, Errors__c, Message__c, Started_At__c FROM DE_Run_Log__c];
        Assert.areEqual('Scheduler', r.Process__c, 'Process stored');
        Assert.areEqual('Success', r.Status__c, 'Status stored');
        Assert.areEqual(12, r.Records_Processed__c, 'Processed count stored');
        Assert.areEqual(10, r.Assignments__c, 'Assignment count stored');
        Assert.areEqual(2, r.Errors__c, 'Error count stored');
        Assert.areEqual('Run complete', r.Message__c, 'Message stored');
        Assert.isNotNull(r.Started_At__c, 'Start time stamped');
    }

    @IsTest
    static void buildTruncatesLongMessages() {
        Datetime startedAt = System.now().addMinutes(-1);
        DE_Run_Log__c r = DE_RunLogger.build('Classifier', 'Warning', 1, 0, 0, 'x'.repeat(40000), startedAt, 1500L);
        Assert.areEqual(32000, r.Message__c.length(), 'Message truncated to the field length');
        Assert.areEqual(1500, r.Duration_Ms__c, 'Duration stored');
        Assert.areEqual(startedAt, r.Started_At__c, 'Start time kept');
        Assert.isNull(DE_RunLogger.build('Purge', 'Success', 0, 0, 0, null, startedAt, null).Message__c, 'Null message allowed');
    }

    @IsTest
    static void sendNeverThrows() {
        User u = DE_TestFactory.users(1)[0];
        Lead l = new Lead(LastName = 'Notify', Company = 'Acme');
        insert l;
        DE_Notifier.Item withEmail = new DE_Notifier.Item(u.Id, l.Id, 'Assigned', 'A lead was assigned to you.');
        withEmail.email = true;
        Boolean threw = false;

        Test.startTest();
        try {
            DE_Notifier.send(null);
            DE_Notifier.send(new List<DE_Notifier.Item>());
            DE_Notifier.send(
                new List<DE_Notifier.Item>{
                    withEmail,
                    new DE_Notifier.Item(u.Id, l.Id, 'Second', 'Another one.'),
                    // Non-user recipients (for example a queue or null) are skipped.
                    new DE_Notifier.Item(l.Id, l.Id, 'Skipped', 'Not a user.'),
                    new DE_Notifier.Item(null, l.Id, 'Skipped', 'No recipient.')
                }
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Notification problems never break an assignment');
    }

    @IsTest
    static void publishRespectsSetting() {
        DE_Settings__c s = DE_TestFactory.settings();
        DE_Assignment_Event__e ev = new DE_Assignment_Event__e(Record_Id__c = '00Q000000000001', Object_API_Name__c = 'Lead', Event_Type__c = 'Assigned');

        Test.startTest();
        Integer before = Limits.getDmlStatements();
        DE_Notifier.publish(new List<DE_Assignment_Event__e>{ ev });
        Integer whenDisabled = Limits.getDmlStatements() - before;
        s.Publish_Platform_Events__c = true;
        update s;
        DE_Settings.setForTransaction(null);
        before = Limits.getDmlStatements();
        DE_Notifier.publish(new List<DE_Assignment_Event__e>{ ev });
        Integer whenEnabled = Limits.getDmlStatements() - before;
        DE_Notifier.publish(null);
        Test.stopTest();

        Assert.areEqual(0, whenDisabled, 'Nothing published when platform events are off');
        Assert.areEqual(1, whenEnabled, 'Events published in one call when enabled');
    }
}
