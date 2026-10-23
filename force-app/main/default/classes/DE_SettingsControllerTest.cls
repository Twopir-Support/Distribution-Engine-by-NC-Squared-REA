@IsTest
private class DE_SettingsControllerTest {
    @IsTest
    static void adminSavesValidSettings() {
        DE_TestFactory.grantAll();
        DE_Settings__c s = DE_SettingsController.getSettings();
        s.Scheduler_Interval_Minutes__c = 5;
        s.Records_Per_Run__c = 250;
        s.Toggle_At_End_Of_Day__c = 'Always Off';
        s.Classifier_Objects__c = 'Lead, Case';

        DE_SettingsController.saveSettings(s);

        DE_Settings__c saved = DE_Settings__c.getOrgDefaults();
        Assert.areEqual(5, saved.Scheduler_Interval_Minutes__c, 'Interval saved.');
        Assert.areEqual(250, saved.Records_Per_Run__c, 'Records per run saved.');
        Assert.areEqual(5, DE_Settings.schedulerIntervalMinutes(), 'The transaction sees the new values.');
        Assert.areEqual('Always Off', DE_Settings.toggleAtEndOfDay(), 'End of day toggle saved.');
    }

    @IsTest
    static void rejectsInvalidSettings() {
        DE_TestFactory.grantAll();
        DE_Settings__c s = new DE_Settings__c(
            Scheduler_Interval_Minutes__c = 30,
            Records_Per_Run__c = 0,
            Previous_Assignees_Tracked__c = 99,
            Archive_Enabled__c = true,
            Toggle_At_Start_Of_Day__c = 'Sometimes',
            Classifier_Objects__c = 'Lead,Nope__c'
        );
        try {
            DE_SettingsController.saveSettings(s);
            Assert.fail('Invalid settings are rejected.');
        } catch (AuraHandledException e) {
            String m = e.getMessage();
            Assert.isTrue(m.contains('between 1 and 10 minutes'), m);
            Assert.isTrue(m.contains('between 1 and 2000'), m);
            Assert.isTrue(m.contains('between 0 and 50'), m);
            Assert.isTrue(m.contains('Choose the archive queue.'), m);
            Assert.isTrue(m.contains('No Change, Always On or Always Off'), m);
            Assert.isTrue(m.contains('Nope__c does not exist'), m);
        }
        Assert.isNull(DE_Settings__c.getOrgDefaults().Id, 'Nothing saved.');
    }

    @IsTest
    static void enforcesRoles() {
        DE_TestFactory.grant(new Set<String>{ 'DE_System_Manager' });
        Assert.isNotNull(DE_SettingsController.getSettings(), 'System managers can view settings.');
        try {
            DE_SettingsController.saveSettings(new DE_Settings__c());
            Assert.fail('Only admins change settings.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('change Distribution Settings'), e.getMessage());
        }
        try {
            DE_SettingsController.exportConfiguration();
            Assert.fail('Only admins export.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e.getMessage(), 'Access error.');
        }
        DE_TestFactory.grant(new Set<String>());
        try {
            DE_SettingsController.getSettings();
            Assert.fail('Users without a role cannot view settings.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e.getMessage(), 'Access error.');
        }
    }

    @IsTest
    static void exportsAndRejectsBadImport() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();

        String json = DE_SettingsController.exportConfiguration();
        Assert.isTrue(json.contains('Inbound Sales'), 'The export contains the team.');
        try {
            DE_SettingsController.importConfiguration('{not json');
            Assert.fail('Invalid JSON is rejected.');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'An error is reported.');
        }
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Team__c], 'A failed import changes nothing.');
    }
}
