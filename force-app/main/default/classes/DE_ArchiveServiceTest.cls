@IsTest
private class DE_ArchiveServiceTest {
    private class Setup {
        DE_TestFactory.Fixture f;
        Group archive;
    }

    private static Setup setup(Boolean enabled, Boolean withQueue) {
        Setup s = new Setup();
        s.f = DE_TestFactory.leadFixture(1, 'Round Robin');
        s.archive = DE_TestFactory.queue('DE Archive', new List<String>{ 'Lead', 'Case' });
        DE_Settings__c settings = DE_Settings__c.getOrgDefaults();
        settings.Archive_Enabled__c = enabled;
        settings.Archive_After_Days__c = 30;
        settings.Archive_Queue_Id__c = withQueue ? String.valueOf(s.archive.Id) : null;
        update settings;
        DE_Settings.setForTransaction(null);
        return s;
    }

    @IsTest
    static void archivesUndistributedRecordsOlderThanTheArchiveAge() {
        Setup s = setup(true, true);
        List<Lead> leads = DE_TestFactory.insertLeads(3, s.f.queue.Id);
        update new Lead(Id = leads[2].Id, DE_Is_Distributed__c = true);

        Test.startTest();
        Integer tooRecent = DE_ArchiveService.archive(System.now());
        Integer archived = DE_ArchiveService.archive(System.now().addDays(31));
        Test.stopTest();

        Assert.areEqual(0, tooRecent, 'New records are not archived');
        Assert.areEqual(2, archived, 'Two never-distributed leads archived');
        for (Lead l : [
            SELECT Id, OwnerId, DE_Is_Archived__c, DE_Source_Queue__c, DE_Last_Archive_Date__c
            FROM Lead
            WHERE Id IN :new List<Id>{ leads[0].Id, leads[1].Id }
        ]) {
            Assert.areEqual(s.archive.Id, l.OwnerId, 'Moved to the archive queue');
            Assert.isTrue(l.DE_Is_Archived__c, 'Archived flag set');
            Assert.areEqual(String.valueOf(s.f.queue.Id), l.DE_Source_Queue__c, 'Source queue remembered');
            Assert.isNotNull(l.DE_Last_Archive_Date__c, 'Archive date stamped');
        }
        Assert.areEqual(s.f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :leads[2].Id].OwnerId, 'Distributed record stays');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Archive' AND Records_Processed__c = 2], 'Run logged');
    }

    @IsTest
    static void editingAnArchivedRecordRestoresIt() {
        Setup s = setup(true, true);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        DE_ArchiveService.archive(System.now().addDays(31));

        Test.startTest();
        update new Lead(Id = l.Id, Title = 'Came back');
        Test.stopTest();

        Lead after = [SELECT OwnerId, DE_Is_Archived__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(s.f.queue.Id, after.OwnerId, 'Restored to its source queue');
        Assert.isFalse(after.DE_Is_Archived__c, 'No longer archived');
    }

    @IsTest
    static void restoreFromConsole() {
        Setup s = setup(true, true);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        Lead notArchived = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        DE_ArchiveService.archive(System.now().addDays(31));
        update new Lead(Id = notArchived.Id, DE_Is_Archived__c = false, OwnerId = s.f.queue.Id);

        Test.startTest();
        Integer restored = DE_ArchiveService.restore(new Set<Id>{ l.Id, notArchived.Id, s.f.team.Id });
        Test.stopTest();

        Assert.areEqual(1, restored, 'Only the archived lead is restored; non Lead/Case ids are ignored');
        Lead after = [SELECT OwnerId, DE_Is_Archived__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(s.f.queue.Id, after.OwnerId, 'Owner restored');
        Assert.isFalse(after.DE_Is_Archived__c, 'Flag cleared');
    }

    @IsTest
    static void disabledOrMissingQueueArchivesNothing() {
        Setup s = setup(false, true);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];

        Test.startTest();
        Integer whenDisabled = DE_ArchiveService.archive(System.now().addDays(31));
        DE_Settings__c settings = DE_Settings__c.getOrgDefaults();
        settings.Archive_Enabled__c = true;
        settings.Archive_Queue_Id__c = null;
        update settings;
        DE_Settings.setForTransaction(null);
        Integer withoutQueue = DE_ArchiveService.archive(System.now().addDays(31));
        Test.stopTest();

        Assert.areEqual(0, whenDisabled, 'Archive disabled');
        Assert.areEqual(0, withoutQueue, 'No archive queue configured');
        Assert.areEqual(s.f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Lead untouched');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Archive' AND Status__c = 'Warning'], 'Missing queue warned');
    }
}
