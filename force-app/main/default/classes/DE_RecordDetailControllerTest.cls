@IsTest
private class DE_RecordDetailControllerTest {
    @IsTest
    static void showsCurrentAssignmentAndPermissions() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.distributor.Rejection_Enabled__c = true;
        f.distributor.Reject_To_Id__c = f.queue.Id;
        update f.distributor;
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        insert new List<DE_Assignment_Log__c>{
            new DE_Assignment_Log__c(
                Record_Id__c = l.Id,
                Object_API_Name__c = 'Lead',
                Team__c = f.team.Id,
                Distributor__c = f.distributor.Id,
                Assignee_Id__c = UserInfo.getUserId(),
                Status__c = 'Reassigned',
                Assigned_At__c = System.now().addHours(-2),
                Current__c = false
            ),
            new DE_Assignment_Log__c(
                Record_Id__c = l.Id,
                Object_API_Name__c = 'Lead',
                Team__c = f.team.Id,
                Distributor__c = f.distributor.Id,
                Assignee_Id__c = UserInfo.getUserId(),
                Status__c = 'Assigned',
                Assigned_At__c = System.now(),
                Current__c = true
            )
        };
        DE_TestFactory.grantAll();

        DE_RecordDetailController.RecordState s = DE_RecordDetailController.getRecordState(l.Id);

        Assert.isTrue(s.distributed, 'The record was distributed.');
        Assert.areEqual(2, s.history.size(), 'Full history returned.');
        Assert.areEqual('Assigned', s.current.Status__c, 'The current log is identified.');
        Assert.isTrue(s.canReject, 'The assignee can reject.');
        Assert.isTrue(s.canAssign, 'Managers with edit access can assign.');
        Assert.isTrue(s.canSimulate, 'Managers can simulate.');
        Assert.isTrue(s.canDistribute, 'Editors can distribute.');

        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        s = DE_RecordDetailController.getRecordState(l.Id);
        Assert.isFalse(s.canAssign, 'Users cannot assign manually.');
        Assert.isFalse(s.canSimulate, 'Users cannot simulate.');
    }

    @IsTest
    static void undistributedRecordHasNoCurrent() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        DE_RecordDetailController.RecordState s = DE_RecordDetailController.getRecordState(l.Id);
        Assert.isFalse(s.distributed, 'Not distributed.');
        Assert.isNull(s.current, 'No current log.');
        Assert.isFalse(s.canReject, 'Nothing to reject.');
    }

    @IsTest
    static void distributeNowRunsStandardDistributor() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });

        Test.startTest();
        String message = DE_RecordDetailController.distributeNow(l.Id);
        Test.stopTest();

        Assert.areEqual('Assigned by a standard distributor.', message, 'Assigned by the round robin distributor.');
        Id owner = [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId;
        Assert.isTrue(owner == f.users[0].Id || owner == f.users[1].Id, 'Owned by a team member.');
    }

    @IsTest
    static void distributeNowExplainsWhenNotAssigned() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        Assert.areEqual('Not assigned. Use Simulate to see why.', DE_RecordDetailController.distributeNow(l.Id), 'A lead outside the source is not assigned.');
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Owner unchanged.');
    }

    @IsTest
    static void manualAssignment() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Distributor__c manual = new DE_Distributor__c(
            Team__c = f.team.Id,
            Name = 'Manual',
            Active__c = true,
            Type__c = 'Manual',
            Method__c = 'Round Robin',
            Order__c = 20,
            Send_Notification__c = false
        );
        insert manual;
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_TestFactory.grantAll();

        List<DE_ManualAssignService.TeamOption> options = DE_RecordDetailController.getManualOptions(l.Id);
        Assert.areEqual(1, options.size(), 'One manual distributor.');
        Assert.areEqual(2, options[0].members.size(), 'Both members offered.');
        Assert.areEqual('Within caps', options[0].members[0].capState, 'No caps configured.');

        Test.startTest();
        DE_RecordDetailController.assignManually(l.Id, manual.Id, f.users[1].Id);
        Test.stopTest();

        Assert.areEqual(f.users[1].Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Assigned to the chosen member.');
        DE_Assignment_Log__c log = [SELECT Method__c, Current__c FROM DE_Assignment_Log__c WHERE Record_Id__c = :l.Id];
        Assert.areEqual('Manual', log.Method__c, 'Logged as manual.');
        Assert.isTrue(log.Current__c, 'It is the current assignment.');

        try {
            DE_RecordDetailController.assignManually(l.Id, manual.Id, f.queue.Id);
            Assert.fail('Only team members can be chosen.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('active member'), e.getMessage());
        }
    }

    @IsTest
    static void usersCannotAssignManually() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_RecordDetailController.getManualOptions(l.Id);
            Assert.fail('Manual assignment needs Team Manager.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('assign records manually'), e.getMessage());
        }
    }
}
