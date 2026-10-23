@IsTest
private class DE_WidgetControllerTest {
    /** Lead team with the running user as member and a Pull distributor on the queue. */
    private static DE_TestFactory.Fixture pullFixture(Integer pullCount) {
        DE_TestFactory.settings();
        DE_TestFactory.Fixture f = new DE_TestFactory.Fixture();
        f.queue = DE_TestFactory.queue('DE Pull Inbox', new List<String>{ 'Lead' });
        f.users = new List<User>{ new User(Id = UserInfo.getUserId()) };
        f.team = DE_TestFactory.insertTeam('Pull Team', 'Lead');
        f.members = DE_TestFactory.members(f.team.Id, f.users);
        f.distributor = DE_TestFactory.distributor(f.team.Id, 'Get Next', f.queue.Id, 'Round Robin');
        f.distributor.Type__c = 'Pull';
        f.distributor.Pull_Count__c = pullCount;
        f.distributor.Rejection_Enabled__c = true;
        f.distributor.Reject_To_Id__c = f.queue.Id;
        insert f.distributor;
        return f;
    }

    @IsTest
    static void stateShowsMembershipAssignmentsAndPullOptions() {
        DE_TestFactory.Fixture f = pullFixture(2);
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);
        String me = UserInfo.getUserId();
        insert new List<DE_Assignment_Log__c>{
            new DE_Assignment_Log__c(
                Record_Id__c = leads[0].Id,
                Record_Name__c = 'Lead 0',
                Object_API_Name__c = 'Lead',
                Team__c = f.team.Id,
                Distributor__c = f.distributor.Id,
                Assignee_Id__c = me,
                Status__c = 'Assigned',
                Assigned_At__c = System.now(),
                Current__c = true,
                SLA_Missed__c = 1
            )
        };
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });

        DE_WidgetController.State s = DE_WidgetController.getState();

        Assert.isTrue(s.online, 'Users without an availability row are online.');
        Assert.isTrue(s.isMember, 'The user is a team member.');
        Assert.isFalse(s.isManager, 'DE User is not a manager.');
        Assert.areEqual(1, s.pullOptions.size(), 'One pull distributor.');
        Assert.areEqual(3, s.pullOptions[0].waiting, 'Three leads wait.');
        Assert.areEqual(2, s.pullOptions[0].pullCount, 'Pull count shown.');
        Assert.areEqual(1, s.assigned.size(), 'One current assignment.');
        Assert.isTrue(s.assigned[0].canReject, 'The distributor allows rejection.');
        Assert.areEqual(1, s.missedSlas.size(), 'One missed SLA.');
        Assert.isFalse(s.rejectReasons.isEmpty(), 'Default reject reasons are offered.');
    }

    @IsTest
    static void pullAssignsUpToPullCount() {
        DE_TestFactory.Fixture f = pullFixture(2);
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });

        Test.startTest();
        DE_PullService.PullResult r = DE_WidgetController.pull(f.distributor.Id);
        Test.stopTest();

        Assert.areEqual(2, r.recordIds.size(), 'Pull count limits the records.');
        Integer mine = 0;
        for (Id owner : DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()).values()) {
            mine += owner == UserInfo.getUserId() ? 1 : 0;
        }
        Assert.areEqual(2, mine, 'Two leads now belong to the user.');
    }

    @IsTest
    static void pullReportsEmptySourceAndNonMembers() {
        DE_TestFactory.Fixture f = pullFixture(1);
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        DE_PullService.PullResult r = DE_WidgetController.pull(f.distributor.Id);
        Assert.isTrue(r.recordIds.isEmpty(), 'Nothing to pull.');
        Assert.areEqual('No records are available to pull right now.', r.message, 'Empty source message.');

        delete f.members;
        try {
            DE_WidgetController.pull(f.distributor.Id);
            Assert.fail('Only members can pull.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not an active member'), e.getMessage());
        }
    }

    @IsTest
    static void togglesOwnAvailability() {
        DE_TestFactory.settings();
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });

        DE_WidgetController.toggle(false, 'Lunch', 30);

        DE_Agent__c a = [SELECT Online__c, Toggle_Reason__c, Toggle_Until__c FROM DE_Agent__c WHERE User__c = :UserInfo.getUserId()];
        Assert.isFalse(a.Online__c, 'Offline.');
        Assert.areEqual('Lunch', a.Toggle_Reason__c, 'Reason saved.');
        Assert.isNotNull(a.Toggle_Until__c, 'Timer saved.');
        DE_WidgetController.State s = DE_WidgetController.getState();
        Assert.isFalse(s.online, 'State shows offline.');
        Assert.areEqual('Lunch', s.reason, 'State shows the reason.');

        try {
            DE_WidgetController.toggle(false, 'Lunch', 0);
            Assert.fail('A zero-minute timer is invalid.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('at least one minute'), e.getMessage());
        }
        DE_WidgetController.toggle(true, null, null);
        Assert.isTrue([SELECT Online__c FROM DE_Agent__c WHERE User__c = :UserInfo.getUserId()].Online__c, 'Back online.');
    }

    @IsTest
    static void requiresReasonWhenConfigured() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Require_Toggle_Reason__c = true;
        update s;
        DE_Settings.setForTransaction(null);
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_WidgetController.toggle(false, null, null);
            Assert.fail('A reason is required.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose a reason'), e.getMessage());
        }
    }

    @IsTest
    static void rejectFailsForRecordsNotAssignedByEngine() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_WidgetController.reject(l.Id, 'Duplicate');
            Assert.fail('Records not assigned by the engine cannot be rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not assigned by Distribution Engine'), e.getMessage());
        }
    }

    @IsTest
    static void createsOutOfOffice() {
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        Datetime startAt = System.now().addDays(1);
        Id oooId = DE_WidgetController.createOutOfOffice(startAt, startAt.addHours(2), 'Training', false);
        DE_Out_Of_Office__c o = [SELECT User__c, Reason__c FROM DE_Out_Of_Office__c WHERE Id = :oooId];
        Assert.areEqual(UserInfo.getUserId(), o.User__c, 'For the running user.');
        Assert.areEqual('Training', o.Reason__c, 'Reason saved.');
    }

    @IsTest
    static void deniesUsersWithoutRole() {
        DE_TestFactory.grant(new Set<String>());
        try {
            DE_WidgetController.getState();
            Assert.fail('The widget needs DE User.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('widget'), e.getMessage());
        }
    }
}
