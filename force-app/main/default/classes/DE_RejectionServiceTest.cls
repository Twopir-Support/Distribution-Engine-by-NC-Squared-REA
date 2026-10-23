@IsTest
private class DE_RejectionServiceTest {
    private class Setup {
        DE_TestFactory.Fixture f;
        Group rejectQueue;
        List<Lead> leads;
    }

    /** Team with rejection enabled; leads distributed by the standard runner. */
    private static Setup setup(Integer userCount, Integer leadCount, String limitMode, Decimal perDay, String replaceMode) {
        Setup s = new Setup();
        s.f = DE_TestFactory.leadFixture(userCount, 'Round Robin');
        s.rejectQueue = DE_TestFactory.queue('DE Rejected', new List<String>{ 'Lead' });
        s.f.team.Rejection_Limit__c = limitMode;
        s.f.team.Rejections_Per_Day__c = perDay;
        update s.f.team;
        s.f.distributor.Rejection_Enabled__c = true;
        s.f.distributor.Reject_To_Id__c = s.rejectQueue.Id;
        s.f.distributor.Reject_Field_Updates__c = 'Title=Rejected by assignee';
        s.f.distributor.Replace_Rejected__c = replaceMode;
        update s.f.distributor;
        s.leads = DE_TestFactory.insertLeads(leadCount, s.f.queue.Id);
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(s.leads).keySet(), null);
        return s;
    }

    private static Id ownerOf(Id leadId) {
        return [SELECT OwnerId FROM Lead WHERE Id = :leadId].OwnerId;
    }

    private static String scopeKey(Setup s, Id memberId) {
        return 'T|' + s.f.team.Id + '|' + memberId;
    }

    @IsTest
    static void assigneeRejectsRecord() {
        Setup s = setup(2, 1, 'Unlimited', null, null);
        Lead l = s.leads[0];
        Id assignee = ownerOf(l.Id);
        Assert.areEqual(s.f.users[0].Id, assignee, 'Runner assigned the lead to the first member');

        Test.startTest();
        List<DE_RejectionService.RejectResult> results = DE_RejectionService.reject(new List<Id>{ l.Id }, 'Duplicate', assignee, false);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One result per record');
        Assert.isTrue(results[0].success, 'Rejection succeeded: ' + results[0].message);
        Lead after = [SELECT OwnerId, Title, DE_Is_Rejected__c, DE_Last_Rejected__c FROM Lead WHERE Id = :l.Id];
        Assert.areEqual(s.rejectQueue.Id, after.OwnerId, 'Record goes to the Reject To queue');
        Assert.areEqual('Rejected by assignee', after.Title, 'Reject field updates applied');
        Assert.isTrue(after.DE_Is_Rejected__c, 'Rejected flag set');
        Assert.isNotNull(after.DE_Last_Rejected__c, 'Rejected time stamped');

        DE_Assignment_Log__c log = [
            SELECT Status__c, Current__c, Reject_Reason__c, Rejected_By__c, Rejected_At__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :l.Id
        ];
        Assert.areEqual('Rejected', log.Status__c, 'Log marked rejected');
        Assert.isFalse(log.Current__c, 'Rejected log is no longer current');
        Assert.areEqual('Duplicate', log.Reject_Reason__c, 'Reason stored');
        Assert.areEqual(assignee, log.Rejected_By__c, 'Rejecting user stored');
        Assert.isNotNull(log.Rejected_At__c, 'Rejected time stored');

        String key = scopeKey(s, assignee);
        DE_Rotation_State__c state = [SELECT Replacement_Credits__c FROM DE_Rotation_State__c WHERE Scope_Key__c = :key];
        Assert.areEqual(1, state.Replacement_Credits__c, 'Default mode owes the assignee a replacement on their usual turn');
        DE_Record_Detail__c detail = [SELECT Previous_Assignees__c FROM DE_Record_Detail__c WHERE Record_Id__c = :l.Id];
        Assert.isTrue(detail.Previous_Assignees__c.contains(String.valueOf(assignee)), 'Rejecting user is tracked');
    }

    @IsTest
    static void replaceAsNextAssignmentMovesMemberToFront() {
        Setup s = setup(2, 1, 'Unlimited', null, 'Replace as Next Assignment');
        Id assignee = ownerOf(s.leads[0].Id);

        Test.startTest();
        DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Workload', assignee, false);
        Test.stopTest();

        String key = scopeKey(s, assignee);
        DE_Rotation_State__c state = [SELECT Last_Sequence__c, Replacement_Credits__c FROM DE_Rotation_State__c WHERE Scope_Key__c = :key];
        Assert.areEqual(0, state.Last_Sequence__c, 'Member is first in line again');
        Assert.areEqual(0, state.Replacement_Credits__c, 'No replacement credit in this mode');
    }

    @IsTest
    static void onlyAssigneeOrManagerCanReject() {
        Setup s = setup(2, 1, 'Unlimited', null, null);
        Id other = s.f.users[1].Id;

        Test.startTest();
        List<DE_RejectionService.RejectResult> byOther = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', other, false);
        List<DE_RejectionService.RejectResult> byManager = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', other, true);
        Test.stopTest();

        Assert.isFalse(byOther[0].success, 'Another member cannot reject');
        Assert.areEqual('Only the assignee or a manager can reject this record.', byOther[0].message, 'Explains who can reject');
        Assert.isTrue(byManager[0].success, 'A manager can reject: ' + byManager[0].message);
    }

    @IsTest
    static void managerOnlyLimit() {
        Setup s = setup(1, 1, 'Manager Only', null, null);
        Id assignee = ownerOf(s.leads[0].Id);

        Test.startTest();
        List<DE_RejectionService.RejectResult> byAssignee = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', assignee, false);
        Test.stopTest();

        Assert.isFalse(byAssignee[0].success, 'Assignee cannot reject when only managers may');
        Assert.areEqual('Only managers can reject assignments for this team.', byAssignee[0].message, 'Manager only message');
        Assert.areEqual(assignee, ownerOf(s.leads[0].Id), 'Owner unchanged');
    }

    @IsTest
    static void limitedRejectionsPerDay() {
        Setup s = setup(1, 2, 'Limited', 1, null);
        Id assignee = s.f.users[0].Id;
        Assert.areEqual(assignee, ownerOf(s.leads[0].Id), 'First lead assigned to the only member');
        Assert.areEqual(assignee, ownerOf(s.leads[1].Id), 'Second lead assigned to the only member');

        Test.startTest();
        List<DE_RejectionService.RejectResult> results = DE_RejectionService.reject(
            new List<Id>{ s.leads[0].Id, s.leads[1].Id },
            'Workload',
            assignee,
            false
        );
        Test.stopTest();

        Assert.isTrue(results[0].success, 'First rejection is within the limit: ' + results[0].message);
        Assert.isFalse(results[1].success, 'Second rejection exceeds the daily limit');
        Assert.isTrue(results[1].message.contains('rejection limit (1)'), 'Limit message: ' + results[1].message);
        Assert.areEqual(assignee, ownerOf(s.leads[1].Id), 'Over-limit record keeps its owner');
    }

    @IsTest
    static void limitIncludesEarlierRejectionsToday() {
        Setup s = setup(1, 2, 'Limited', 1, null);
        Id assignee = s.f.users[0].Id;
        DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Workload', assignee, false);

        Test.startTest();
        List<DE_RejectionService.RejectResult> second = DE_RejectionService.reject(new List<Id>{ s.leads[1].Id }, 'Workload', assignee, false);
        List<DE_RejectionService.RejectResult> manager = DE_RejectionService.reject(new List<Id>{ s.leads[1].Id }, 'Workload', UserInfo.getUserId(), true);
        Test.stopTest();

        Assert.isFalse(second[0].success, 'Earlier rejection today counts towards the limit');
        Assert.isTrue(manager[0].success, 'Managers are not limited: ' + manager[0].message);
    }

    @IsTest
    static void reasonValidation() {
        Setup s = setup(1, 1, 'Unlimited', null, null);
        Id assignee = s.f.users[0].Id;

        Test.startTest();
        List<DE_RejectionService.RejectResult> blank = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, ' ', assignee, false);
        String otherAllowed = DE_RejectionService.validateReason('Something else');
        DE_Settings__c settings = DE_Settings__c.getOrgDefaults();
        settings.Allow_Other_Reject_Reason__c = false;
        update settings;
        DE_Settings.setForTransaction(null);
        String otherBlocked = DE_RejectionService.validateReason('Something else');
        String listed = DE_RejectionService.validateReason('duplicate');
        Test.stopTest();

        Assert.isFalse(blank[0].success, 'Blank reason rejected');
        Assert.areEqual('Choose a reason for rejecting.', blank[0].message, 'Blank reason message');
        Assert.isNull(otherAllowed, 'Free-text reasons allowed by default');
        Assert.isTrue(otherBlocked.contains('not an allowed reject reason'), 'Free text blocked when not allowed');
        Assert.isNull(listed, 'Configured reasons match case-insensitively');
        Assert.areEqual(assignee, ownerOf(s.leads[0].Id), 'Owner unchanged after invalid reason');
    }

    @IsTest
    static void rejectionDisabledNotDistributedOrReassigned() {
        Setup s = setup(1, 2, 'Unlimited', null, null);
        Id assignee = s.f.users[0].Id;
        Lead notDistributed = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        Lead moved = s.leads[1];
        moved.OwnerId = UserInfo.getUserId();
        update moved;

        Test.startTest();
        List<DE_RejectionService.RejectResult> results = DE_RejectionService.reject(
            new List<Id>{ notDistributed.Id, moved.Id },
            'Duplicate',
            assignee,
            false
        );
        s.f.distributor.Rejection_Enabled__c = false;
        update s.f.distributor;
        List<DE_RejectionService.RejectResult> disabled = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', assignee, false);
        Test.stopTest();

        Assert.areEqual('This record was not assigned by Distribution Engine.', results[0].message, 'Undistributed record');
        Assert.isTrue(results[1].message.contains('has been reassigned'), 'Owner changed since distribution: ' + results[1].message);
        Assert.isFalse(disabled[0].success, 'Rejection disabled on the distributor');
        Assert.isTrue(disabled[0].message.startsWith('Rejection is not enabled'), 'Disabled message: ' + disabled[0].message);
        Assert.areEqual(assignee, ownerOf(s.leads[0].Id), 'Owner unchanged when rejection is disabled');
    }
}
