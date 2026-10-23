@IsTest
private class DE_SimulatorTest {
    @IsTest
    static void explainsAssignmentWithoutSaving() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];

        DE_Simulator.Result r = DE_Simulator.simulate(l.Id, null);

        Assert.areEqual('Lead', r.objectName, 'Object detected from the Id.');
        Assert.areEqual(1, r.results.size(), 'One distributor evaluated.');
        Assert.isTrue(r.results[0].sourcePassed, 'The lead is in the source queue.');
        Assert.isTrue(r.results[0].filtersPassed, 'No filters to fail.');
        Assert.isTrue(r.results[0].assigned, 'A member would be chosen.');
        Assert.isTrue(r.wouldAssignTo.contains('Inbound Sales / Inbound'), 'Team and distributor named: ' + r.wouldAssignTo);
        Assert.areEqual(f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'The simulator does not change the owner.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Assignment_Log__c], 'The simulator writes no logs.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Rotation_State__c], 'The simulator does not move the rotation.');
    }

    @IsTest
    static void explainsSourceAndFilterFailures() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Distributor__c filtered = DE_TestFactory.distributor(f.team.Id, 'Web only', f.queue.Id, 'Round Robin');
        filtered.Order__c = 20;
        insert filtered;
        DE_Condition__c c = DE_TestFactory.condition('Distributor Filter', 1, 'LeadSource', 'equals', 'Web');
        c.Distributor__c = filtered.Id;
        insert c;
        Lead elsewhere = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        Lead queued = DE_TestFactory.insertLeads(1, f.queue.Id)[0];

        DE_Simulator.Result r = DE_Simulator.simulate(elsewhere.Id, null);
        Assert.isFalse(r.results[0].sourcePassed, 'The lead is not in the queue.');
        Assert.isTrue(r.results[0].message.contains('not at this distributor'), r.results[0].message);
        Assert.isNull(r.wouldAssignTo, 'Nothing would be assigned.');

        DE_Simulator.Options o = new DE_Simulator.Options();
        o.stopOnSuccess = false;
        r = DE_Simulator.simulate(queued.Id, o);
        Assert.areEqual(2, r.results.size(), 'Both distributors evaluated.');
        Assert.isFalse(r.results[1].filtersPassed, 'The Web-only filter fails.');
        Assert.areEqual('Record does not match the filters.', r.results[1].message, 'Filter failure explained.');

        o.stopOnSuccess = true;
        r = DE_Simulator.simulate(queued.Id, o);
        Assert.areEqual(1, r.results.size(), 'Stops after the first distributor that would assign.');
    }

    @IsTest
    static void warnsWhenNoTeamsAndIncludesInactive() {
        DE_TestFactory.settings();
        Case c = DE_TestFactory.insertCases(1, UserInfo.getUserId())[0];
        DE_Simulator.Result r = DE_Simulator.simulate(c.Id, null);
        Assert.areEqual(1, r.warnings.size(), 'A warning explains why.');
        Assert.areEqual('No active teams distribute Case records.', r.warnings[0], 'No active Case teams.');

        DE_Team__c t = DE_TestFactory.team('Paused', 'Case');
        t.Active__c = false;
        insert t;
        insert new DE_Distributor__c(Team__c = t.Id, Name = 'Manual', Active__c = true, Type__c = 'Manual', Method__c = 'Round Robin');
        DE_Simulator.Options o = new DE_Simulator.Options();
        o.includeInactive = true;
        r = DE_Simulator.simulate(c.Id, o);
        Assert.areEqual('Paused (inactive)', r.results[0].teamName, 'Inactive teams are labelled.');
        Assert.areEqual('Manual distributor: a manager chooses the member.', r.results[0].message, 'Manual distributors are explained.');
    }

    @IsTest
    static void controllersRequireManagerRole() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        Assert.isNotNull(DE_ConsoleController.simulate(l.Id, null).wouldAssignTo, 'Managers can simulate from the console.');
        Assert.isNotNull(DE_RecordDetailController.simulate(l.Id, null).wouldAssignTo, 'Managers can simulate from the record page.');
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_ConsoleController.simulate(l.Id, null);
            Assert.fail('Users cannot simulate.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e.getMessage(), 'Access error.');
        }
    }
}
