/**
 * Tests for Trigger distributors: immediate assignment when DE_Trigger_Distribution__c is set on update,
 * and the Apex/Flow entry point DE_TriggerDistribution.distributeIds.
 */
@IsTest
private class DE_TriggerDistributionTest {
    private class Setup {
        List<User> users;
        DE_Team__c team;
        List<DE_Team_Member__c> members;
        DE_Distributor__c distributor;
    }

    private static Setup setup(Integer userCount, String method) {
        DE_TestFactory.settings();
        Setup s = new Setup();
        s.users = DE_TestFactory.users(userCount);
        s.team = DE_TestFactory.insertTeam('Instant routing', 'Lead');
        s.members = DE_TestFactory.members(s.team.Id, s.users);
        s.distributor = new DE_Distributor__c(
            Team__c = s.team.Id,
            Name = 'Instant',
            Active__c = true,
            Type__c = 'Trigger',
            Method__c = method,
            Order__c = 10,
            Assign_To__c = 'All Team Members',
            Send_Notification__c = false
        );
        insert s.distributor;
        return s;
    }

    private static List<DE_Assignment_Log__c> logsFor(Id recordId) {
        return [
            SELECT Status__c, Method__c, Type__c, Assignee_Id__c, Message__c, Current__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :String.valueOf(recordId)
            ORDER BY Name
        ];
    }

    private static void flag(List<Lead> leads) {
        for (Lead l : leads) {
            l.DE_Trigger_Distribution__c = true;
        }
        update leads;
    }

    @IsTest
    static void flaggingARecordAssignsItImmediately() {
        Setup s = setup(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(2, UserInfo.getUserId());

        Test.startTest();
        flag(leads);
        Test.stopTest();

        Set<Id> memberIds = new Map<Id, User>(s.users).keySet();
        Set<Id> owners = new Set<Id>();
        for (Lead l : [SELECT OwnerId, DE_Trigger_Distribution__c, DE_Is_Triggered__c, DE_Is_Distributed__c FROM Lead WHERE Id IN :leads]) {
            Assert.isTrue(memberIds.contains(l.OwnerId), 'Assigned to a team member');
            Assert.isFalse(l.DE_Trigger_Distribution__c, 'The trigger flag is cleared');
            Assert.isTrue(l.DE_Is_Triggered__c, 'Marked as triggered');
            Assert.isTrue(l.DE_Is_Distributed__c, 'Marked as distributed');
            owners.add(l.OwnerId);
        }
        Assert.areEqual(2, owners.size(), 'Round robin across both members');
        DE_Assignment_Log__c log = logsFor(leads[0].Id)[0];
        Assert.areEqual('Trigger', log.Type__c, 'Type');
        Assert.areEqual('Round Robin', log.Method__c, 'Method');
        Assert.areEqual('Assigned', log.Status__c, 'Status');
        Assert.isTrue(log.Current__c, 'Current');
    }

    @IsTest
    static void bulkFlaggingAssignsAll() {
        Setup s = setup(4, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(200, UserInfo.getUserId());

        Test.startTest();
        flag(leads);
        Test.stopTest();

        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()));
        for (User u : s.users) {
            Assert.areEqual(50, counts.get(u.Id), 'Even split for ' + u.LastName);
        }
    }

    @IsTest
    static void unflaggedUpdatesAreIgnored() {
        setup(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        l.Description = 'Just an edit';
        update l;
        Test.stopTest();

        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owner unchanged');
        Assert.areEqual(0, logsFor(l.Id).size(), 'No log');
    }

    @IsTest
    static void disabledInSettingsDoesNothing() {
        setup(1, 'Round Robin');
        DE_Settings__c settings = DE_Settings__c.getOrgDefaults();
        settings.Trigger_Distribution_Enabled__c = false;
        update settings;
        DE_Settings.setForTransaction(null);
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        flag(new List<Lead>{ l });
        Test.stopTest();

        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owner unchanged when trigger distribution is off');
    }

    @IsTest
    static void bypassSkipsTheEngine() {
        setup(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        DE_TriggerHandler.bypass = true;
        flag(new List<Lead>{ l });
        DE_TriggerHandler.bypass = false;
        Test.stopTest();

        Lead after = [SELECT OwnerId, DE_Trigger_Distribution__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(UserInfo.getUserId(), after.OwnerId, 'Bypassed updates are not routed');
        Assert.isTrue(after.DE_Trigger_Distribution__c, 'Flag left as saved');
    }

    @IsTest
    static void defaultOwnerWhenNobodyIsAvailable() {
        Setup s = setup(2, 'Round Robin');
        insert new DE_Agent__c(Name = 'Off', User__c = s.users[0].Id, Unique_User__c = String.valueOf(s.users[0].Id), Online__c = false);
        s.members[1].Active__c = false;
        update s.members[1];
        s.distributor.Default_Owner_Id__c = String.valueOf(s.users[1].Id);
        update s.distributor;
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Flow');
        Test.stopTest();

        Assert.areEqual(0, outcome.assigned, 'No member could be assigned');
        Assert.areEqual(1, outcome.defaulted, 'Default owner used');
        Assert.areEqual(s.users[1].Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owned by the default owner');
        DE_Assignment_Log__c log = logsFor(l.Id)[0];
        Assert.areEqual('Default Owner', log.Method__c, 'Method');
        Assert.areEqual('Flow', log.Type__c, 'Type follows the entry point');
    }

    @IsTest
    static void noDefaultOwnerLogsAnError() {
        Setup s = setup(1, 'Round Robin');
        s.members[0].Active__c = false;
        update s.members[0];
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Flow');
        Test.stopTest();

        Assert.areEqual(1, outcome.failed, 'Failure reported');
        Assert.areEqual('No eligible team member', outcome.messageByRecord.get(l.Id), 'Reason reported');
        DE_Assignment_Log__c log = logsFor(l.Id)[0];
        Assert.areEqual('Error', log.Status__c, 'Error logged');
        Assert.isTrue(log.Message__c.contains('No eligible team member'), 'Message: ' + log.Message__c);
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owner unchanged');
    }

    @IsTest
    static void filtersDecideWhichRecordsAreRouted() {
        Setup s = setup(1, 'Round Robin');
        DE_Condition__c c = DE_TestFactory.condition('Distributor Filter', 1, 'Company', 'equals', 'Acme');
        c.Distributor__c = s.distributor.Id;
        insert c;
        List<Lead> leads = DE_TestFactory.leads(2, UserInfo.getUserId());
        leads[0].Company = 'Acme';
        insert leads;

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Map<Id, Lead>(leads).keySet(), 'Flow');
        Test.stopTest();

        Assert.areEqual(1, outcome.assigned, 'Only the matching lead');
        Assert.areEqual(1, outcome.failed, 'The other lead matched no trigger distributor');
        Map<Id, Id> owners = DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet());
        Assert.areEqual(s.users[0].Id, owners.get(leads[0].Id), 'Matching lead assigned');
        Assert.areEqual(UserInfo.getUserId(), owners.get(leads[1].Id), 'Other lead unchanged');
        Assert.isTrue(logsFor(leads[1].Id)[0].Message__c.contains('No trigger distributor matched'), 'Unmatched reason logged');
    }

    @IsTest
    static void distributionHoursAreIgnoredByDefault() {
        Setup s = setup(1, 'Round Robin');
        DE_Shift__c closed = new DE_Shift__c(Name = 'Closed', Timezone__c = 'GMT', Schedule__c = scheduleNotToday());
        insert closed;
        s.team.Team_Hours__c = closed.Id;
        update s.team;
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Flow');
        Test.stopTest();

        Assert.areEqual(1, outcome.assigned, 'Trigger distribution ignores hours unless the team respects them');
    }

    @IsTest
    static void distributionHoursRespectedWhenConfigured() {
        Setup s = setup(1, 'Round Robin');
        DE_Shift__c closed = new DE_Shift__c(Name = 'Closed', Timezone__c = 'GMT', Schedule__c = scheduleNotToday());
        insert closed;
        s.team.Team_Hours__c = closed.Id;
        s.team.Respect_Hours_For_Triggers__c = true;
        update s.team;
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Flow');
        Test.stopTest();

        Assert.areEqual(0, outcome.assigned, 'Outside hours');
        Assert.areEqual(1, outcome.failed, 'No default owner, so the record fails');
    }

    @IsTest
    static void currentOwnerKeepsOwnerAndLogs() {
        Setup s = setup(1, 'Current Owner');
        Lead l = DE_TestFactory.insertLeads(1, s.users[0].Id)[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Trigger');
        Test.stopTest();

        Assert.areEqual(1, outcome.assigned, 'Logged as an assignment');
        Lead after = [SELECT OwnerId, DE_Is_Distributed__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(s.users[0].Id, after.OwnerId, 'Owner kept');
        Assert.isTrue(after.DE_Is_Distributed__c, 'Tracking field set');
        Assert.areEqual('Current Owner', logsFor(l.Id)[0].Method__c, 'Method');
    }

    @IsTest
    static void standardOnlyTeamsAreNotUsedByTriggers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];

        Test.startTest();
        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ l.Id }, 'Flow');
        Test.stopTest();

        Assert.areEqual(0, outcome.assigned, 'No trigger distributor exists');
        Assert.areEqual(0, outcome.failed, 'Nothing attempted');
        Assert.areEqual(f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owner unchanged');
    }

    @IsTest
    static void objectsWithoutTeamsAreSkipped() {
        DE_TestFactory.settings();
        Account a = new Account(Name = 'No teams');
        insert a;

        DE_TriggerDistribution.Outcome outcome = DE_TriggerDistribution.distributeIds(new Set<Id>{ a.Id }, 'Flow');

        Assert.areEqual(0, outcome.assigned + outcome.failed + outcome.defaulted, 'No configuration for Account');
    }

    private static String scheduleNotToday() {
        Integer today = DE_ShiftCalendar.dayIndex(System.now().dateGmt());
        return '{"' + DE_ShiftCalendar.DAYS[Math.mod(today + 3, 7)] + '":["09:00-10:00"]}';
    }
}
