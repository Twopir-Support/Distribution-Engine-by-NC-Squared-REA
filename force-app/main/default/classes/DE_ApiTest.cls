@IsTest
private class DE_ApiTest {
    /** Lead team with two members and an active Trigger distributor. */
    private static DE_TestFactory.Fixture triggerFixture() {
        DE_TestFactory.settings();
        DE_TestFactory.Fixture f = new DE_TestFactory.Fixture();
        f.users = DE_TestFactory.users(2);
        f.team = DE_TestFactory.insertTeam('Trigger Team', 'Lead');
        f.members = DE_TestFactory.members(f.team.Id, f.users);
        f.distributor = new DE_Distributor__c(
            Team__c = f.team.Id,
            Name = 'Instant',
            Active__c = true,
            Type__c = 'Trigger',
            Method__c = 'Round Robin',
            Order__c = 10,
            Assign_To__c = 'All Team Members',
            Send_Notification__c = false
        );
        insert f.distributor;
        return f;
    }

    private static Set<Id> memberIds(DE_TestFactory.Fixture f) {
        return new Map<Id, User>(f.users).keySet();
    }

    @IsTest
    static void distributeRecordsUsesTriggerDistributors() {
        DE_TestFactory.Fixture f = triggerFixture();
        List<Lead> leads = DE_TestFactory.insertLeads(4, UserInfo.getUserId());

        Test.startTest();
        Integer assigned = DE_Api.distributeRecords(new Map<Id, Lead>(leads).keySet());
        Test.stopTest();

        Assert.areEqual(4, assigned, 'Every lead is assigned.');
        Map<Id, Integer> perOwner = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()));
        Assert.areEqual(memberIds(f), perOwner.keySet(), 'Only team members own the leads.');
        for (Integer n : perOwner.values()) {
            Assert.areEqual(2, n, 'Round robin splits the leads evenly.');
        }
        Assert.areEqual(4, [SELECT COUNT() FROM DE_Assignment_Log__c WHERE Type__c = 'Flow' AND Current__c = TRUE], 'Logged as Flow assignments.');
    }

    @IsTest
    static void distributeInsideTriggerUpdatesRowsInMemory() {
        DE_TestFactory.Fixture f = triggerFixture();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(f.team.Id, false);
        Lead row = (Lead) DE_RecordQuery.byIds('Lead', DE_RecordQuery.requiredPaths(cfg, null), new Set<Id>{ l.Id }, new List<String>())[0];

        DE_Api.distributeInsideTrigger('Lead', new List<SObject>{ row });

        Assert.isTrue(memberIds(f).contains(row.OwnerId), 'The in-memory row is assigned to a member.');
    }

    @IsTest
    static void distributeNowUsesStandardDistributors() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);
        Test.startTest();
        Integer assigned = DE_Api.distributeNow(new Map<Id, Lead>(leads).keySet());
        Test.stopTest();
        Assert.areEqual(3, assigned, 'All queued leads are assigned.');
    }

    @IsTest
    static void togglesAndReportsAvailability() {
        DE_TestFactory.Fixture f = triggerFixture();
        User outsider = DE_TestFactory.users(1)[0];

        DE_Api.toggleUsers(new Set<Id>{ f.users[0].Id }, false, 'Meeting', 60);

        Map<Id, Boolean> availability = DE_Api.getAvailability(new Set<Id>{ f.users[0].Id, f.users[1].Id, outsider.Id });
        Assert.isFalse(availability.get(f.users[0].Id), 'Toggled off.');
        Assert.isTrue(availability.get(f.users[1].Id), 'Still available.');
        Assert.isFalse(availability.get(outsider.Id), 'Not a member of any team.');
        DE_Availability_Event__c e = [SELECT Source__c, Reason__c FROM DE_Availability_Event__c];
        Assert.areEqual('API', e.Source__c, 'API toggles are recorded with source API.');
        Assert.areEqual('Meeting', e.Reason__c, 'Reason recorded.');
    }

    @IsTest
    static void rejectAndClassifyEntryPoints() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        List<String> messages = DE_Api.rejectRecords(new List<Id>{ l.Id }, 'Duplicate');
        Assert.areEqual(1, messages.size(), 'One message per record.');
        Assert.isTrue(messages[0].contains('not assigned by Distribution Engine'), messages[0]);

        DE_Api.classifyRecords(new Set<Id>{ l.Id }, new Set<String>{ 'Territory' });
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Assignment_Log__c], 'Classification does not assign.');
    }
}
