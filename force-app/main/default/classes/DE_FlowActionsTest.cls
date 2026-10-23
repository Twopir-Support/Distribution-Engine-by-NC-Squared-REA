@IsTest
private class DE_FlowActionsTest {
    private static DE_FlowActions.DistributeRequest request(Id recordId, Boolean includeStandard) {
        DE_FlowActions.DistributeRequest r = new DE_FlowActions.DistributeRequest();
        r.recordId = recordId;
        r.includeStandard = includeStandard;
        return r;
    }

    @IsTest
    static void distributeActionUsesTriggerDistributors() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(1);
        DE_Team__c t = DE_TestFactory.insertTeam('Flow Team', 'Lead');
        DE_TestFactory.members(t.Id, users);
        insert new DE_Distributor__c(
            Team__c = t.Id,
            Name = 'Instant',
            Active__c = true,
            Type__c = 'Trigger',
            Method__c = 'Round Robin',
            Send_Notification__c = false
        );
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        List<DE_FlowActions.DistributeResult> results = DE_FlowActions.distribute(new List<DE_FlowActions.DistributeRequest>{ request(l.Id, false) });
        Test.stopTest();

        Assert.isTrue(results[0].assigned, 'Assigned by the trigger distributor.');
        Assert.areEqual('Assigned.', results[0].message, 'Success message.');
        Assert.areEqual(users[0].Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owned by the member.');
    }

    @IsTest
    static void distributeActionFallsBackToStandard() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Lead queued = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        Lead elsewhere = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        List<DE_FlowActions.DistributeResult> results = DE_FlowActions.distribute(
            new List<DE_FlowActions.DistributeRequest>{ request(queued.Id, true), request(elsewhere.Id, false) }
        );
        Test.stopTest();

        Assert.isTrue(results[0].assigned, 'Standard distributors run when requested.');
        Assert.areEqual(f.users[0].Id, [SELECT OwnerId FROM Lead WHERE Id = :queued.Id].OwnerId, 'Assigned by the standard distributor.');
        Assert.isFalse(results[1].assigned, 'Without a trigger distributor nothing happens.');
        Assert.areEqual('Not assigned.', results[1].message, 'Default message.');
    }

    @IsTest
    static void toggleActionGroupsRequests() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(3);
        List<DE_ToggleUsersAction.Request> requests = new List<DE_ToggleUsersAction.Request>();
        for (Integer i = 0; i < 3; i++) {
            DE_ToggleUsersAction.Request r = new DE_ToggleUsersAction.Request();
            r.userId = users[i].Id;
            r.online = i < 2 ? false : true;
            r.reason = i < 2 ? 'Training' : null;
            requests.add(r);
        }

        DE_ToggleUsersAction.toggle(requests);

        Map<Id, DE_Agent__c> agents = DE_ConfigRepository.agentsByUser(new Map<Id, User>(users).keySet());
        Assert.isFalse(agents.get(users[0].Id).Online__c, 'First user offline.');
        Assert.isFalse(agents.get(users[1].Id).Online__c, 'Second user offline.');
        Assert.isTrue(agents.get(users[2].Id).Online__c, 'Third user online.');
        Assert.areEqual('Training', agents.get(users[0].Id).Toggle_Reason__c, 'Reason applied.');
        Assert.areEqual(3, [SELECT COUNT() FROM DE_Availability_Event__c WHERE Source__c = 'API'], 'Each toggle recorded with source API.');
    }

    @IsTest
    static void rejectActionReportsPerRecordAndEnforcesLimit() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_RejectRecordAction.Request r = new DE_RejectRecordAction.Request();
        r.recordId = l.Id;
        r.reason = 'Duplicate';

        List<DE_RejectRecordAction.Result> results = DE_RejectRecordAction.reject(new List<DE_RejectRecordAction.Request>{ r });
        Assert.isFalse(results[0].rejected, 'Not assigned by the engine, so not rejected.');
        Assert.isTrue(results[0].message.contains('not assigned by Distribution Engine'), results[0].message);

        List<DE_RejectRecordAction.Request> tooMany = new List<DE_RejectRecordAction.Request>();
        for (Integer i = 0; i <= DE_RejectRecordAction.MAX_RECORDS; i++) {
            tooMany.add(r);
        }
        try {
            DE_RejectRecordAction.reject(tooMany);
            Assert.fail('More than 500 records per call are rejected.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('at most 500'), e.getMessage());
        }
    }
}
