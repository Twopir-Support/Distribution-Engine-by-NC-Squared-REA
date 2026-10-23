@IsTest
private class DE_HistoryServiceTest {
    private class UpdateTeamJob implements Queueable {
        private Id teamId;
        UpdateTeamJob(Id teamId) {
            this.teamId = teamId;
        }
        public void execute(QueueableContext context) {
            update new DE_Team__c(Id = teamId, Description__c = 'Changed by a job');
        }
    }

    private static List<DE_History__c> historyOf(Id recordId) {
        return [
            SELECT Change_Type__c, Field__c, Old_Value__c, New_Value__c, Parent_Record_Id__c, Parent_Object__c, Background_Change__c, Changed_By__c
            FROM DE_History__c
            WHERE Record_Id__c = :recordId
            ORDER BY Name
        ];
    }

    @IsTest
    static void teamCreateUpdateAndDeleteAreRecorded() {
        DE_TestFactory.settings();
        DE_Team__c t = DE_TestFactory.insertTeam('Inbound', 'Lead');
        t.Execution_Order__c = 20;
        t.Rotation_Sequence__c = 7;
        update t;
        delete t;

        List<DE_History__c> rows = historyOf(t.Id);
        Assert.areEqual(3, rows.size(), 'Created, one tracked field change, deleted: ' + rows);
        Assert.areEqual('Created', rows[0].Change_Type__c, 'Creation recorded');
        Assert.areEqual('Updated', rows[1].Change_Type__c, 'Update recorded');
        Assert.areEqual('Execution_Order__c', rows[1].Field__c, 'Engine-maintained Rotation_Sequence__c is not recorded');
        Assert.areEqual('10', rows[1].Old_Value__c, 'Old value');
        Assert.areEqual('20', rows[1].New_Value__c, 'New value');
        Assert.areEqual('Deleted', rows[2].Change_Type__c, 'Deletion recorded');
        Assert.areEqual(t.Id, rows[0].Parent_Record_Id__c, 'A team is its own parent');
        Assert.areEqual(UserInfo.getUserId(), rows[0].Changed_By__c, 'User recorded');
        Assert.isFalse(rows[0].Background_Change__c, 'User change, not background');
    }

    @IsTest
    static void caseOnlyChangesAreRecorded() {
        DE_TestFactory.settings();
        DE_Team__c t = DE_TestFactory.team('Inbound', 'Lead');
        t.Description__c = 'abc';
        insert t;
        t.Description__c = 'ABC';
        update t;

        List<DE_History__c> rows = historyOf(t.Id);
        Assert.areEqual(2, rows.size(), 'Created and the case change');
        Assert.areEqual('Description__c', rows[1].Field__c, 'Case-only change detected');
        Assert.areEqual('abc', rows[1].Old_Value__c, 'Old value');
    }

    @IsTest
    static void childConfigurationCarriesItsTeam() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        DE_Team__c t = DE_TestFactory.insertTeam('Inbound', 'Lead');
        DE_Team_Member__c m = DE_TestFactory.members(t.Id, new List<User>{ u })[0];

        List<DE_History__c> rows = historyOf(m.Id);
        Assert.areEqual(1, rows.size(), 'Member creation recorded');
        Assert.areEqual(t.Id, rows[0].Parent_Record_Id__c, 'Member history shows with its team');
        Assert.areEqual('DE_Team__c', rows[0].Parent_Object__c, 'Parent type');

        DE_TestFactory.grantAll();
        Set<String> recordIds = new Set<String>();
        for (DE_History__c h : DE_HistoryController.getHistory(t.Id, null)) {
            recordIds.add(h.Record_Id__c);
        }
        Assert.isTrue(recordIds.containsAll(new Set<String>{ t.Id, m.Id }), 'Team history includes the team and its member: ' + recordIds);
        Assert.areEqual(1, DE_HistoryController.getHistory(t.Id, 'DE_Team_Member__c').size(), 'Filtered to members');
    }

    @IsTest
    static void onlyTagChangesAreRecordedForUserAvailability() {
        DE_TestFactory.settings();
        DE_Agent__c a = new DE_Agent__c(Name = 'Agent', User__c = UserInfo.getUserId(), Online__c = true);
        insert a;
        a.Online__c = false;
        update a;
        Assert.areEqual(0, historyOf(a.Id).size(), 'Online toggles and agent creation without tags are not configuration history');

        a.Tags__c = 'Language:French';
        update a;
        List<DE_History__c> rows = historyOf(a.Id);
        Assert.areEqual(1, rows.size(), 'Tag assignment recorded');
        Assert.areEqual('Tags__c', rows[0].Field__c, 'Tags field');
        Assert.areEqual('Language:French', rows[0].New_Value__c, 'New tags');
        Assert.areEqual(UserInfo.getUserId(), rows[0].Parent_Record_Id__c, 'Shown with the user');
    }

    @IsTest
    static void engineChangesAreBackgroundChanges() {
        DE_TestFactory.settings();
        DE_Team__c t = DE_TestFactory.insertTeam('Inbound', 'Lead');

        Test.startTest();
        System.enqueueJob(new UpdateTeamJob(t.Id));
        Test.stopTest();

        DE_History__c row = [SELECT Background_Change__c FROM DE_History__c WHERE Record_Id__c = :t.Id AND Field__c = 'Description__c'];
        Assert.isTrue(row.Background_Change__c, 'Changes from async jobs are background changes');
    }

    @IsTest
    static void historyCanBeSwitchedOff() {
        DE_TestFactory.settings();
        DE_HistoryService.disabled = true;
        DE_Team__c t = DE_TestFactory.insertTeam('Quiet', 'Lead');
        Assert.areEqual(0, historyOf(t.Id).size(), 'Nothing recorded while disabled');
    }

    @IsTest
    static void viewerChecksPermissionsAndInput() {
        DE_TestFactory.settings();
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_HistoryController.getHistory(null, null);
            Assert.fail('Users without a manager role cannot view history');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('change history'), e.getMessage());
        }
        DE_TestFactory.grantAll();
        try {
            DE_HistoryController.getHistory(null, 'Lead');
            Assert.fail('Untracked object rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }
        try {
            DE_HistoryController.getHistory('not-an-id', null);
            Assert.fail('Invalid Id rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }
        Set<String> tracked = new Set<String>();
        for (Map<String, String> o : DE_HistoryController.getTrackedObjects()) {
            tracked.add(o.get('value'));
        }
        Assert.isTrue(tracked.containsAll(new Set<String>{ 'DE_Team__c', 'DE_Distributor__c', 'DE_Holiday__c', 'DE_Agent__c' }), 'Documented areas tracked');
    }

    @IsTest
    static void oldHistoryIsPurged() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.History_Retention_Days__c = 30;
        update s;
        DE_Settings.setForTransaction(null);
        insert new List<DE_History__c>{
            new DE_History__c(Object_API_Name__c = 'DE_Team__c', Change_Type__c = 'Updated', Changed_At__c = System.now().addDays(-40)),
            new DE_History__c(Object_API_Name__c = 'DE_Team__c', Change_Type__c = 'Updated', Changed_At__c = System.now().addDays(-5))
        };

        Assert.areEqual(1, DE_HistoryService.purge(System.now()), 'Only history older than the retention period');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_History__c], 'Recent history kept');
    }

    @IsTest
    static void valueFormatting() {
        Assert.isNull(DE_HistoryService.format(null), 'Null stays null');
        Assert.areEqual('2026-01-02 03:04:05 GMT', DE_HistoryService.format(Datetime.newInstanceGmt(2026, 1, 2, 3, 4, 5)), 'Datetimes in GMT');
        Assert.isTrue(DE_HistoryService.same(null, null), 'Both null');
        Assert.isFalse(DE_HistoryService.same('a', 'A'), 'Case matters');
        Assert.isFalse(DE_HistoryService.same(null, 'x'), 'Null vs value');
    }
}
