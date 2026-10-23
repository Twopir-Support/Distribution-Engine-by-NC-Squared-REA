@IsTest
private class DE_ActionTrackingTest {
    /** One-member Lead team tracking Title = Contacted (and Call tasks) as the first action. */
    private static DE_TestFactory.Fixture setup(Boolean anyUser) {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Action_Tracking_Enabled__c = true;
        f.team.Action_Field__c = 'Title';
        f.team.Tracked_Actions__c = 'Contacted, Qualified';
        f.team.Action_Respect_Hours__c = 'None';
        f.team.Track_Action_From_Any_User__c = anyUser;
        f.team.Auto_Action_Activity_Types__c = 'Call';
        update f.team;
        return f;
    }

    private static Lead distributeOne(DE_TestFactory.Fixture f) {
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_DistributionRunner.runStandard(new Set<Id>{ l.Id }, null);
        return l;
    }

    private static DE_Assignment_Log__c logFor(Id recordId) {
        return [SELECT Action_At__c, Time_To_Action_Mins__c FROM DE_Assignment_Log__c WHERE Record_Id__c = :recordId AND Current__c = TRUE];
    }

    @IsTest
    static void trackedValueChangeRecordsTimeToAction() {
        DE_TestFactory.Fixture f = setup(true);
        Lead l = distributeOne(f);
        DE_Assignment_Log__c log = [SELECT Id FROM DE_Assignment_Log__c WHERE Record_Id__c = :l.Id];
        update new DE_Assignment_Log__c(Id = log.Id, Assigned_At__c = System.now().addMinutes(-30));

        Test.startTest();
        update new Lead(Id = l.Id, Title = 'contacted');
        Test.stopTest();

        DE_Assignment_Log__c after = logFor(l.Id);
        Assert.isNotNull(after.Action_At__c, 'Action time recorded');
        Assert.isTrue(after.Time_To_Action_Mins__c >= 29 && after.Time_To_Action_Mins__c <= 31, 'About 30 minutes: ' + after.Time_To_Action_Mins__c);
        Lead rec = [SELECT DE_Time_To_Action__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(after.Time_To_Action_Mins__c, rec.DE_Time_To_Action__c, 'Time to action copied to the record');
    }

    @IsTest
    static void untrackedValueAndSecondActionAreIgnored() {
        DE_TestFactory.Fixture f = setup(true);
        Lead l = distributeOne(f);

        Test.startTest();
        update new Lead(Id = l.Id, Title = 'Left voicemail');
        DE_Assignment_Log__c afterUntracked = logFor(l.Id);
        update new Lead(Id = l.Id, Title = 'Contacted');
        Datetime first = logFor(l.Id).Action_At__c;
        update new Lead(Id = l.Id, Title = 'Qualified');
        Test.stopTest();

        Assert.isNull(afterUntracked.Action_At__c, 'Untracked values are not actions');
        Assert.isNotNull(first, 'Tracked value is an action');
        Assert.areEqual(first, logFor(l.Id).Action_At__c, 'Only the first action is recorded');
    }

    @IsTest
    static void onlyAssigneeCountsUnlessAnyUserAllowed() {
        DE_TestFactory.Fixture f = setup(false);
        Lead l = distributeOne(f);
        User assignee = f.users[0];

        Test.startTest();
        update new Lead(Id = l.Id, Title = 'Contacted');
        DE_Assignment_Log__c byOther = logFor(l.Id);
        update new Lead(Id = l.Id, Title = 'Waiting');
        System.runAs(assignee) {
            update new Lead(Id = l.Id, Title = 'Contacted');
        }
        Test.stopTest();

        Assert.isNull(byOther.Action_At__c, 'Another user acting does not count');
        Assert.isNotNull(logFor(l.Id).Action_At__c, 'The assignee acting counts');
    }

    @IsTest
    static void loggedCallIsAnAutoAction() {
        DE_TestFactory.Fixture f = setup(true);
        Lead l = distributeOne(f);

        Test.startTest();
        insert new Task(WhoId = l.Id, Subject = 'Call', Type = 'Call', Status = 'Completed', OwnerId = UserInfo.getUserId());
        Test.stopTest();

        Assert.areEqual('Contacted', [SELECT Title FROM Lead WHERE Id = :l.Id].Title, 'Action field set to the first tracked action');
        Assert.isNotNull(logFor(l.Id).Action_At__c, 'Auto action recorded');
    }

    @IsTest
    static void otherActivityTypeIsNotAnAction() {
        DE_TestFactory.Fixture f = setup(true);
        Lead l = distributeOne(f);

        Test.startTest();
        insert new Task(WhoId = l.Id, Subject = 'Email', Type = 'Email', Status = 'Completed', OwnerId = UserInfo.getUserId());
        Test.stopTest();

        Assert.isNull([SELECT Title FROM Lead WHERE Id = :l.Id].Title, 'Action field unchanged');
        Assert.isNull(logFor(l.Id).Action_At__c, 'No action recorded');
    }

    @IsTest
    static void minutesBetweenWithoutCalendarIsWallClock() {
        Datetime now = System.now();
        DE_Assignment_Log__c l = new DE_Assignment_Log__c(Assigned_At__c = now.addMinutes(-90));
        Assert.areEqual(90.0, DE_ActionTracking.minutesBetween(null, l, now), 'Wall-clock minutes without a team');
        Assert.isNull(DE_ActionTracking.minutesBetween(null, new DE_Assignment_Log__c(), now), 'No assignment time, no duration');
    }
}
