@IsTest
private class DE_ManualAssignServiceTest {
    private class Setup {
        DE_TestFactory.Fixture f;
        DE_Distributor__c manual;
    }

    private static Setup setup(Boolean treatAsRejection) {
        Setup s = new Setup();
        s.f = DE_TestFactory.leadFixture(2, 'Round Robin');
        s.manual = DE_TestFactory.distributor(s.f.team.Id, 'Manager picks', null, 'Round Robin');
        s.manual.Type__c = 'Manual';
        s.manual.Source_Type__c = 'Any';
        s.manual.Treat_Manual_As_Rejection__c = treatAsRejection;
        s.manual.Replace_Rejected__c = 'Replace on Usual Assignment';
        insert s.manual;
        return s;
    }

    @IsTest
    static void optionsListManualDistributorMembers() {
        Setup s = setup(false);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        insert new DE_Cap__c(Name = 'No more today', Team__c = s.f.team.Id, Period__c = 'Daily', Default_Cap__c = 0, Active__c = true);
        DE_AgentService.setOnline(new Set<Id>{ s.f.users[1].Id }, false, 'Training', null, 'Manager');

        Test.startTest();
        List<DE_ManualAssignService.TeamOption> options = DE_ManualAssignService.options(l.Id);
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'Only the manual distributor is offered');
        Assert.areEqual(s.manual.Id, options[0].distributorId, 'Option is the manual distributor');
        Assert.areEqual(2, options[0].members.size(), 'Both active members are listed');
        Map<Id, DE_ManualAssignService.MemberOption> byId = new Map<Id, DE_ManualAssignService.MemberOption>();
        for (DE_ManualAssignService.MemberOption o : options[0].members) {
            byId.put(o.memberId, o);
            Assert.areEqual(0, o.assignedToday, 'Nothing assigned yet today');
            Assert.isTrue(o.capState.startsWith('At team daily cap'), 'Cap state shows the team cap: ' + o.capState);
        }
        Assert.isTrue(byId.get(s.f.users[0].Id).available, 'Online member is available');
        Assert.isFalse(byId.get(s.f.users[1].Id).available, 'Offline member is shown as unavailable');
        Assert.isTrue(byId.get(s.f.users[1].Id).availability.startsWith('Toggled offline'), 'Offline reason is shown');
    }

    @IsTest
    static void assignIgnoresCapsAndLogsManualAssignment() {
        Setup s = setup(false);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        insert new DE_Cap__c(Name = 'No more today', Team__c = s.f.team.Id, Period__c = 'Daily', Default_Cap__c = 0, Active__c = true);
        Id target = s.f.users[1].Id;

        Test.startTest();
        DE_ManualAssignService.assign(l.Id, s.manual.Id, target);
        Test.stopTest();

        Lead after = [SELECT OwnerId, DE_Is_Distributed__c, DE_Distribution_Count__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(target, after.OwnerId, 'Manual assignment is allowed at a cap');
        Assert.isTrue(after.DE_Is_Distributed__c, 'Record flagged as distributed');
        Assert.areEqual(1, after.DE_Distribution_Count__c, 'Distribution count incremented');
        DE_Assignment_Log__c log = [
            SELECT Type__c, Method__c, Counts_As_Hit__c, Current__c, Previous_Owner_Id__c, Decision_Trace__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :l.Id
        ];
        Assert.areEqual('Manual', log.Type__c, 'Logged as manual');
        Assert.areEqual('Manual', log.Method__c, 'Method is manual');
        Assert.isFalse(log.Counts_As_Hit__c, 'Manual assignments do not count as a round robin hit by default');
        Assert.isTrue(log.Current__c, 'Log is current');
        Assert.areEqual(String.valueOf(s.f.queue.Id), log.Previous_Owner_Id__c, 'Previous owner is the queue');
        Assert.isTrue(log.Decision_Trace__c.contains('Manually assigned'), 'Trace explains the manual choice');
    }

    @IsTest
    static void treatManualAsRejectionGivesPreviousOwnerReplacementCredit() {
        Setup s = setup(true);
        Id previous = s.f.users[0].Id;
        Id target = s.f.users[1].Id;
        Lead l = DE_TestFactory.insertLeads(1, previous)[0];

        Test.startTest();
        DE_ManualAssignService.assign(l.Id, s.manual.Id, target);
        Test.stopTest();

        Assert.areEqual(target, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Record moved to the chosen member');
        String scope = 'T|' + s.f.team.Id + '|' + previous;
        DE_Rotation_State__c state = [SELECT Replacement_Credits__c FROM DE_Rotation_State__c WHERE Scope_Key__c = :scope];
        Assert.areEqual(1, state.Replacement_Credits__c, 'Previous owner is owed a replacement record');
        DE_Record_Detail__c detail = [SELECT Previous_Assignees__c FROM DE_Record_Detail__c WHERE Record_Id__c = :l.Id];
        Assert.isTrue(detail.Previous_Assignees__c.contains(String.valueOf(previous)), 'Previous owner is tracked so they do not get it back');
        Assert.isTrue(detail.Previous_Assignees__c.startsWith(String.valueOf(target)), 'New assignee is the most recent');
    }

    @IsTest
    static void assignValidatesDistributorMemberAndObject() {
        Setup s = setup(false);
        Lead l = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        Case c = DE_TestFactory.insertCases(1, UserInfo.getUserId())[0];

        Test.startTest();
        String notMember = errorOf(l.Id, s.manual.Id, UserInfo.getUserId());
        String notManual = errorOf(l.Id, s.f.distributor.Id, s.f.users[0].Id);
        String wrongObject = errorOf(c.Id, s.manual.Id, s.f.users[0].Id);
        Test.stopTest();

        Assert.isTrue(notMember.contains('Choose an active member'), 'Non-member rejected: ' + notMember);
        Assert.isTrue(notManual.contains('not active'), 'Standard distributor cannot be used manually: ' + notManual);
        Assert.isTrue(wrongObject.contains('distributes Lead'), 'Object mismatch rejected: ' + wrongObject);
        Assert.areEqual(s.f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Lead untouched');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Assignment_Log__c], 'No logs written');
    }

    private static String errorOf(Id recordId, Id distributorId, Id memberId) {
        try {
            DE_ManualAssignService.assign(recordId, distributorId, memberId);
        } catch (DE_Permissions.AccessException e) {
            return e.getMessage();
        }
        Assert.fail('Expected an AccessException');
        return null;
    }
}
