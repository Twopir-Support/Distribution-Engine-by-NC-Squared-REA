@IsTest
private class DE_PullServiceTest {
    private class Setup {
        DE_TestFactory.Fixture f;
        DE_Distributor__c pull;
    }

    /** Lead team whose only distributor is a Pull distributor on the fixture queue. */
    private static Setup setup(Integer userCount, Integer pullCount) {
        Setup s = new Setup();
        s.f = DE_TestFactory.leadFixture(userCount, 'Round Robin');
        s.f.distributor.Active__c = false;
        update s.f.distributor;
        s.pull = DE_TestFactory.distributor(s.f.team.Id, 'Get Next', s.f.queue.Id, 'Round Robin');
        s.pull.Type__c = 'Pull';
        s.pull.Pull_Count__c = pullCount;
        insert s.pull;
        return s;
    }

    @IsTest
    static void optionsListPullDistributorsWithWaitingCount() {
        Setup s = setup(2, 2);
        DE_TestFactory.insertLeads(3, s.f.queue.Id);

        Test.startTest();
        List<DE_PullService.PullOption> mine = DE_PullService.options(s.f.users[0].Id);
        List<DE_PullService.PullOption> stranger = DE_PullService.options(UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual(1, mine.size(), 'A member sees the team pull distributor');
        Assert.areEqual(s.pull.Id, mine[0].distributorId, 'Option points at the pull distributor');
        Assert.areEqual('Lead', mine[0].objectName, 'Option carries the object');
        Assert.areEqual(3, mine[0].waiting, 'All three queued leads are waiting');
        Assert.areEqual(2, mine[0].pullCount, 'Pull count comes from the distributor');
        Assert.isTrue(stranger.isEmpty(), 'A user outside the team has no pull options');
    }

    @IsTest
    static void pullAssignsPullCountToRequesterEvenWhenOffline() {
        Setup s = setup(2, 2);
        List<Lead> leads = DE_TestFactory.insertLeads(3, s.f.queue.Id);
        Id requester = s.f.users[1].Id;
        DE_AgentService.setOnline(new Set<Id>{ requester }, false, 'Lunch', null, 'Manager');

        Test.startTest();
        DE_PullService.PullResult result = DE_PullService.pull(requester, s.pull.Id);
        Test.stopTest();

        Assert.areEqual(2, result.recordIds.size(), 'Pull returns the pull count');
        Assert.areEqual(2, result.recordNames.size(), 'Names returned for each record');
        Assert.isNull(result.message, 'No message when records were pulled');
        Map<Id, Id> owners = DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet());
        Integer owned = 0;
        for (Id recordId : result.recordIds) {
            Assert.areEqual(requester, owners.get(recordId), 'Pulled record belongs to the requester');
            owned++;
        }
        Assert.areEqual(2, owned, 'Two records pulled');
        List<DE_Assignment_Log__c> logs = [
            SELECT Type__c, Method__c, Assignee_Id__c, Current__c
            FROM DE_Assignment_Log__c
            WHERE Status__c = 'Assigned'
        ];
        Assert.areEqual(2, logs.size(), 'One log per pulled record');
        for (DE_Assignment_Log__c l : logs) {
            Assert.areEqual('Pull', l.Type__c, 'Logged as a pull');
            Assert.areEqual('Pull', l.Method__c, 'Method is Pull');
            Assert.areEqual(String.valueOf(requester), l.Assignee_Id__c, 'Logged against the requester');
            Assert.isTrue(l.Current__c, 'Pull log is current');
        }
    }

    @IsTest
    static void pullStopsAtCapWithMessage() {
        Setup s = setup(1, 2);
        DE_TestFactory.insertLeads(3, s.f.queue.Id);
        insert new DE_Cap__c(Name = 'One a day', Distributor__c = s.pull.Id, Period__c = 'Daily', Default_Cap__c = 1, Active__c = true);

        Test.startTest();
        DE_PullService.PullResult result = DE_PullService.pull(s.f.users[0].Id, s.pull.Id);
        Test.stopTest();

        Assert.areEqual(1, result.recordIds.size(), 'Only one record allowed by the daily cap');
        Assert.isNotNull(result.message, 'Requester is told why no more records were given');
        Assert.areEqual(2, [SELECT COUNT() FROM Lead WHERE OwnerId = :s.f.queue.Id], 'Remaining leads stay in the queue');
    }

    @IsTest
    static void pullWithNothingWaitingReturnsMessage() {
        Setup s = setup(1, 1);

        Test.startTest();
        DE_PullService.PullResult result = DE_PullService.pull(s.f.users[0].Id, s.pull.Id);
        Test.stopTest();

        Assert.isTrue(result.recordIds.isEmpty(), 'Nothing to pull');
        Assert.areEqual('No records are available to pull right now.', result.message, 'Empty source message');
    }

    @IsTest
    static void pullRejectsNonMembersAndOtherDistributorTypes() {
        Setup s = setup(1, 1);
        DE_TestFactory.insertLeads(1, s.f.queue.Id);

        Test.startTest();
        String nonMember = errorOf(UserInfo.getUserId(), s.pull.Id);
        String standard = errorOf(s.f.users[0].Id, s.f.distributor.Id);
        delete [SELECT Id FROM DE_Distributor__c WHERE Id = :s.pull.Id];
        String missing = errorOf(s.f.users[0].Id, s.pull.Id);
        Test.stopTest();

        Assert.isTrue(nonMember.contains('not an active member'), 'Non-member cannot pull: ' + nonMember);
        Assert.isTrue(standard.contains('not active'), 'A non-pull distributor cannot be pulled from: ' + standard);
        Assert.isTrue(missing.contains('no longer exists'), 'Deleted distributor is reported: ' + missing);
        Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE OwnerId = :s.f.queue.Id], 'Nothing was assigned');
    }

    private static String errorOf(Id userId, Id distributorId) {
        try {
            DE_PullService.pull(userId, distributorId);
        } catch (DE_Permissions.AccessException e) {
            return e.getMessage();
        }
        Assert.fail('Expected an AccessException');
        return null;
    }
}
