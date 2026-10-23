/**
 * Assignment pipeline features added for the reference inventory: log fields and record lookups,
 * logging disabled, campaign filter, role assignment, reject log, sticky removal on reject,
 * auto reassign retries, log actions, trigger attempt stamp and the widget's active-only list.
 */
@IsTest
private class DE_AssignmentPipelineTest {
    private static List<Lead> webLeads(Integer count, Id ownerId) {
        List<Lead> out = DE_TestFactory.leads(count, ownerId);
        for (Lead l : out) {
            l.LeadSource = 'Web';
        }
        insert out;
        return out;
    }

    private static DE_Assignment_Log__c currentLog(Id recordId) {
        return [
            SELECT
                Id,
                Assignee_Id__c,
                Assignee_Name__c,
                Send_Email__c,
                Lead__c,
                Case__c,
                Account__c,
                Status_On_Assignment__c,
                Team_Role__c,
                Team_Member_Record_Id__c,
                Current__c,
                Status__c,
                Message__c,
                Reject_Request__c,
                Actions_Complete__c,
                Last_Action_At__c,
                Action_At__c,
                Time_To_Action_Mins__c,
                Reassign_Attempts__c,
                Reassign_Error_At__c,
                SLA_Status__c,
                Next_SLA_Check__c,
                Sticky_Key__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :recordId
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
    }

    // ------------------------------------------------------------------ log fields

    @IsTest
    static void logCarriesAssigneeNameEmailFlagLookupAndStatus() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Active_Status_Field__c = 'LeadSource';
        f.team.Active_Status_Values__c = 'Web';
        update f.team;
        f.distributor.Send_Email__c = true;
        update f.distributor;
        List<Lead> leads = webLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(leads).keySet(), null);
        Test.stopTest();

        DE_Assignment_Log__c log = currentLog(leads[0].Id);
        User u = [SELECT Name FROM User WHERE Id = :f.users[0].Id];
        Assert.areEqual(u.Id, log.Assignee_Id__c, 'Assigned to the only member');
        Assert.areEqual(u.Name, log.Assignee_Name__c, 'Assignee name resolved');
        Assert.isTrue(log.Send_Email__c, 'Send email copied from the distributor for the email flows');
        Assert.areEqual(leads[0].Id, log.Lead__c, 'Lead lookup set');
        Assert.isNull(log.Case__c, 'Other record lookups stay empty');
        Assert.areEqual('Web', log.Status_On_Assignment__c, 'Active status value at assignment recorded');
    }

    @IsTest
    static void emailFlagIsOffWhenDistributorDoesNotSendEmail() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(leads).keySet(), null);
        Test.stopTest();

        DE_Assignment_Log__c log = currentLog(leads[0].Id);
        Assert.isFalse(log.Send_Email__c, 'No standard email unless the distributor asks for it');
        Assert.isNull(log.Status_On_Assignment__c, 'No active status field configured');
    }

    @IsTest
    static void loggingDisabledAssignsWithoutLogs() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.team.Logging_Disabled__c = true;
        update f.team;
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary s = DE_DistributionRunner.runStandard(new Map<Id, Lead>(leads).keySet(), null);
        Test.stopTest();

        Assert.areEqual(4, s.assigned, 'All leads assigned');
        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()));
        Assert.areEqual(2, counts.get(f.users[0].Id), 'Rotation still works without logs');
        Assert.areEqual(2, counts.get(f.users[1].Id), 'Rotation still works without logs');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Assignment_Log__c WHERE Team__c = :f.team.Id], 'No distribution logs written');
    }

    // ------------------------------------------------------------------ campaign filter

    @IsTest
    static void campaignFilterOnlyDistributesCampaignMembers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);
        User marketer = DE_TestFactory.users(1)[0];
        marketer.UserPermissionsMarketingUser = true;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update marketer;
        }
        Campaign c;
        System.runAs(marketer) {
            c = new Campaign(Name = 'Spring webinar', IsActive = true);
            insert c;
        }
        insert new CampaignMember(CampaignId = c.Id, LeadId = leads[0].Id);
        f.distributor.Campaign_Ids__c = c.Id;
        update f.distributor;

        Test.startTest();
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(leads).keySet(), null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet());
        Assert.areEqual(f.users[0].Id, owners.get(leads[0].Id), 'Campaign member distributed');
        Assert.areEqual(f.queue.Id, owners.get(leads[1].Id), 'Non-member stays in the queue');
        Assert.areEqual(f.queue.Id, owners.get(leads[2].Id), 'Non-member stays in the queue');
    }

    @IsTest
    static void campaignFilterRejectsObjectsThatCannotBeCampaignMembers() {
        DE_Model.DistributorConfig dc = new DE_Model.DistributorConfig();
        dc.dist = new DE_Distributor__c(Name = 'Campaign', Campaign_Ids__c = '701000000000001AAA');
        Case cs = new Case(Subject = 'No campaigns', Status = 'New', Origin = 'Web');
        insert cs;
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(new List<DE_Model.TeamConfig>(), System.now());
        List<String> trace = new List<String>();

        Assert.isFalse(DE_DistributionCore.campaignPasses(dc, cs, ctx, trace), 'Cases are never campaign members');
        Assert.isTrue(trace[0].contains('only leads and contacts'), 'Trace explains why: ' + trace);
    }

    // ------------------------------------------------------------------ role assignment

    @IsTest
    static void accessLevelsParse() {
        Map<String, String> levels = DE_SalesforceTeamService.accessLevels('Account=Edit; Opportunity=Read\nCase=None');
        Assert.areEqual('Edit', levels.get('account'), 'Account level');
        Assert.areEqual('Read', levels.get('opportunity'), 'Opportunity level');
        Assert.areEqual('None', levels.get('case'), 'Case level');
        Assert.isTrue(DE_SalesforceTeamService.accessLevels(null).isEmpty(), 'Blank means defaults');
        Assert.isFalse(DE_SalesforceTeamService.isSupported('Lead'), 'Leads have no record teams');
    }

    @IsTest
    static void roleAssignmentAddsTeamMemberInsteadOfChangingOwner() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(1);
        DE_Team__c team = DE_TestFactory.insertTeam('Account Coverage', 'Account');
        DE_TestFactory.members(team.Id, users);
        DE_Distributor__c d = DE_TestFactory.distributor(team.Id, 'Account manager role', null, 'Round Robin');
        d.Source_Type__c = 'Field Value';
        d.Source_Id__c = null;
        d.Source_Field__c = 'Rating';
        d.Source_Ready_Value__c = 'Hot';
        d.Source_After_Value__c = 'Warm';
        d.Salesforce_Team_Enabled__c = true;
        d.Team_Role__c = 'Account Manager';
        d.Team_Access_Level__c = 'Account=Edit;Opportunity=Read;Case=Read';
        d.Send_Email__c = true;
        insert d;
        Account a = new Account(Name = 'Globex', Rating = 'Hot');
        insert a;

        Test.startTest();
        DE_DistributionRunner.runStandard(new Set<Id>{ a.Id }, null);
        Test.stopTest();

        Account after = [SELECT OwnerId, Rating FROM Account WHERE Id = :a.Id];
        Assert.areEqual(UserInfo.getUserId(), after.OwnerId, 'Role assignment never changes the owner');
        DE_Assignment_Log__c log = currentLog(a.Id);
        Assert.areEqual(a.Id, log.Account__c, 'Account lookup set');
        Assert.areEqual('Account Manager', log.Team_Role__c, 'Team role logged');
        Assert.isFalse(log.Current__c, 'Role assignments are not the record\'s current assignment');
        if (DE_SalesforceTeamService.isSupported('Account')) {
            Assert.areEqual('Assigned', log.Status__c, 'Assigned when account teams are enabled: ' + log.Message__c);
            Assert.isNotNull(log.Team_Member_Record_Id__c, 'Team member record id stored');
            Assert.areEqual('Warm', after.Rating, 'Field value source moved to its after value');
            List<SObject> members = Database.query('SELECT UserId, TeamMemberRole FROM AccountTeamMember WHERE AccountId = \'' + a.Id + '\'');
            Assert.areEqual(1, members.size(), 'One account team member added');
            Assert.areEqual(users[0].Id, members[0].get('UserId'), 'The selected member was added');
            Assert.areEqual('Account Manager', members[0].get('TeamMemberRole'), 'With the configured role');
        } else {
            Assert.areEqual('Error', log.Status__c, 'Without account teams the assignment is an error');
            Assert.isTrue(log.Message__c.contains('not enabled'), 'Message explains the missing feature: ' + log.Message__c);
        }
    }

    @IsTest
    static void roleAssignmentDistributorsCannotBeRejected() {
        Assert.isNotNull(DE_SalesforceTeamService.SUPPORTED, 'Supported objects declared');
        DE_Model.Decision dec = new DE_Model.Decision(new Lead(LastName = 'x'));
        dec.distributor = new DE_Model.DistributorConfig();
        dec.distributor.dist = new DE_Distributor__c(Salesforce_Team_Enabled__c = true);
        Assert.isTrue(DE_AssignmentWriter.isRoleAssignment(dec), 'Role assignment decision detected');
        dec.distributor.dist.Salesforce_Team_Enabled__c = false;
        Assert.isFalse(DE_AssignmentWriter.isRoleAssignment(dec), 'Owner assignment decision detected');
    }

    @IsTest
    static void relatedRoleWithoutTeamMembersMatchesNobody() {
        Account a = new Account(Name = 'No team');
        insert a;
        Map<Id, Id> holders = DE_OwnerResolver.roleHolders(new Set<Id>{ a.Id, null }, 'Account Manager');
        Assert.isFalse(holders.containsKey(a.Id), 'No team member holds the role');
    }

    // ------------------------------------------------------------------ rejection log

    private class RejectSetup {
        DE_TestFactory.Fixture f;
        Group rejectQueue;
        List<Lead> leads;
    }

    private static RejectSetup rejectSetup(String limitMode) {
        RejectSetup s = new RejectSetup();
        s.f = DE_TestFactory.leadFixture(2, 'Round Robin');
        s.rejectQueue = DE_TestFactory.queue('DE Rejected', new List<String>{ 'Lead' });
        s.f.team.Rejection_Limit__c = limitMode;
        update s.f.team;
        s.f.distributor.Rejection_Enabled__c = true;
        s.f.distributor.Reject_To_Id__c = s.rejectQueue.Id;
        update s.f.distributor;
        s.leads = DE_TestFactory.insertLeads(2, s.f.queue.Id);
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(s.leads).keySet(), null);
        return s;
    }

    @IsTest
    static void approvedRejectionIsLoggedAndLinked() {
        RejectSetup s = rejectSetup('Unlimited');
        Id assignee = DE_TestFactory.owners('Lead', new Set<Id>{ s.leads[0].Id }).get(s.leads[0].Id);

        Test.startTest();
        DE_RejectionService.RejectResult r = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', assignee, false)[0];
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        DE_Reject_Request__c req = [
            SELECT Status__c, Reason__c, Requested_By__c, Reviewed_By__c, Team__c, Assignment_Log__c, Record_Name__c, Object_API_Name__c
            FROM DE_Reject_Request__c
            WHERE Record_Id__c = :s.leads[0].Id
        ];
        Assert.areEqual('Approved', req.Status__c, 'Applied request is approved');
        Assert.areEqual('Duplicate', req.Reason__c, 'Reason stored');
        Assert.areEqual(assignee, req.Requested_By__c, 'Requester stored');
        Assert.isNull(req.Reviewed_By__c, 'Own rejection needs no reviewer');
        Assert.areEqual(s.f.team.Id, req.Team__c, 'Team stored');
        Assert.areEqual('Lead', req.Object_API_Name__c, 'Object stored');
        DE_Assignment_Log__c log = [SELECT Reject_Request__c FROM DE_Assignment_Log__c WHERE Id = :req.Assignment_Log__c];
        Assert.areEqual(req.Id, [SELECT Id FROM DE_Reject_Request__c WHERE Record_Id__c = :s.leads[0].Id].Id, 'Single request');
        Assert.isNotNull(log.Reject_Request__c, 'Distribution log links to its reject log');
    }

    @IsTest
    static void deniedRejectionIsLoggedWithReason() {
        RejectSetup s = rejectSetup('Manager Only');
        Id assignee = DE_TestFactory.owners('Lead', new Set<Id>{ s.leads[0].Id }).get(s.leads[0].Id);

        Test.startTest();
        DE_RejectionService.RejectResult r = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', assignee, false)[0];
        Test.stopTest();

        Assert.isFalse(r.success, 'Users cannot reject in a manager-only team');
        DE_Reject_Request__c req = [SELECT Status__c, Message__c FROM DE_Reject_Request__c WHERE Record_Id__c = :s.leads[0].Id];
        Assert.areEqual('Denied', req.Status__c, 'Refused request is denied');
        Assert.isTrue(req.Message__c.contains('Only managers'), 'Why it was denied: ' + req.Message__c);
        Assert.isNull(currentLog(s.leads[0].Id).Reject_Request__c, 'Denied requests are not linked to the assignment');
    }

    @IsTest
    static void invalidReasonStillCreatesDeniedRows() {
        RejectSetup s = rejectSetup('Unlimited');
        DE_Settings__c settings = DE_TestFactory.settings();
        settings.Reject_Reasons__c = 'Duplicate';
        settings.Allow_Other_Reject_Reason__c = false;
        update settings;
        DE_Settings.setForTransaction(null);

        Test.startTest();
        List<DE_RejectionService.RejectResult> results = DE_RejectionService.reject(
            new List<Id>{ s.leads[0].Id, s.leads[1].Id },
            'Bored',
            UserInfo.getUserId(),
            true
        );
        Test.stopTest();

        Assert.isFalse(results[0].success, 'Invalid reason refused');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Reject_Request__c WHERE Status__c = 'Denied'], 'One denied row per requested record');
    }

    @IsTest
    static void managerRejectingOnBehalfIsTheReviewer() {
        RejectSetup s = rejectSetup('Unlimited');

        Test.startTest();
        DE_RejectionService.RejectResult r = DE_RejectionService.reject(new List<Id>{ s.leads[0].Id }, 'Duplicate', UserInfo.getUserId(), true)[0];
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        DE_Reject_Request__c req = [SELECT Reviewed_By__c, Reviewed_At__c FROM DE_Reject_Request__c WHERE Record_Id__c = :s.leads[0].Id];
        Assert.areEqual(UserInfo.getUserId(), req.Reviewed_By__c, 'Manager recorded as reviewer');
        Assert.isNotNull(req.Reviewed_At__c, 'Review time recorded');
    }

    @IsTest
    static void rejectionRemovesStickyPerRejectSetting() {
        RejectSetup s = rejectSetup('Unlimited');
        s.f.distributor.Sticky_Enabled__c = true;
        s.f.distributor.Sticky_Field__c = 'Email';
        s.f.distributor.Remove_Sticky_On_Reject__c = 'Always';
        s.f.distributor.Remove_Sticky_On_Reassign__c = 'Never';
        update s.f.distributor;
        Lead l = new Lead(LastName = 'Sticky', Company = 'Initech', Email = 'sticky.reject@initech.example.com', OwnerId = s.f.queue.Id);
        insert l;
        DE_DistributionRunner.runStandard(new Set<Id>{ l.Id }, null);
        DE_Assignment_Log__c before = currentLog(l.Id);
        Assert.isNotNull(before.Sticky_Key__c, 'Sticky key recorded at assignment');

        Test.startTest();
        DE_RejectionService.RejectResult r = DE_RejectionService.reject(new List<Id>{ l.Id }, 'Duplicate', UserInfo.getUserId(), true)[0];
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.isNull([SELECT Sticky_Key__c FROM DE_Assignment_Log__c WHERE Id = :before.Id].Sticky_Key__c, 'Remove sticky on reject (Always) cleared the key');
    }

    // ------------------------------------------------------------------ auto reassign retries

    @IsTest
    static void failedAutoReassignIsRetriedThreeTimesThenGivenUp() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Group caseOnly = DE_TestFactory.queue('DE Case Only', new List<String>{ 'Case' });
        insert new DE_SLA__c(
            Team__c = f.team.Id,
            Name = 'First contact',
            Checkpoint__c = 1,
            Alert_Type__c = 'Time Checkpoint',
            Minutes_After_Assignment__c = 1
        );
        f.distributor.SLA_Enabled__c = true;
        f.distributor.Auto_Reassign__c = true;
        f.distributor.Reassign_From_SLA__c = 1;
        // A queue that cannot own leads makes every reassignment fail.
        f.distributor.Reassign_To_Id__c = caseOnly.Id;
        update f.distributor;
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_DistributionRunner.runStandard(new Set<Id>{ l.Id }, null);
        DE_Assignment_Log__c log = currentLog(l.Id);
        Datetime now = System.now();
        update new DE_Assignment_Log__c(Id = log.Id, Assigned_At__c = now.addMinutes(-10), Next_SLA_Check__c = now.addMinutes(-9));

        Test.startTest();
        DE_SlaService.monitor(200, now);
        DE_Assignment_Log__c first = currentLog(l.Id);
        DE_SlaService.monitor(200, now.addMinutes(5));
        DE_SlaService.monitor(200, now.addMinutes(10));
        DE_Assignment_Log__c third = currentLog(l.Id);
        DE_SlaService.monitor(200, now.addMinutes(15));
        Test.stopTest();

        Assert.areEqual(1, first.Reassign_Attempts__c, 'First failure counted');
        Assert.areEqual('Pending', first.SLA_Status__c, 'Retry scheduled');
        Assert.isNotNull(first.Reassign_Error_At__c, 'Error time stamped');
        Assert.isTrue(first.Message__c.contains('retrying'), first.Message__c);
        Assert.areEqual(3, third.Reassign_Attempts__c, 'Retried on later runs');
        DE_Assignment_Log__c last = currentLog(l.Id);
        Assert.areEqual(4, last.Reassign_Attempts__c, 'Initial attempt plus three retries');
        Assert.areEqual('Missed', last.SLA_Status__c, 'Gives up after three retries');
        Assert.isNull(last.Next_SLA_Check__c, 'No further checks');
        Assert.isTrue(last.Message__c.contains('after 4 attempts'), last.Message__c);
        Assert.areEqual(f.users[0].Id, DE_TestFactory.owners('Lead', new Set<Id>{ l.Id }).get(l.Id), 'Record stays with the assignee');
    }

    // ------------------------------------------------------------------ log actions

    @IsTest
    static void everyTrackedActionIsLogged() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Action_Tracking_Enabled__c = true;
        f.team.Action_Field__c = 'DE_Action__c';
        f.team.Tracked_Actions__c = 'Contacted;Responded';
        f.team.Track_Action_From_Any_User__c = true;
        f.team.Action_Respect_Hours__c = 'None';
        update f.team;
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_DistributionRunner.runStandard(new Set<Id>{ l.Id }, null);

        Test.startTest();
        update new Lead(Id = l.Id, DE_Action__c = 'Contacted');
        DE_Assignment_Log__c afterFirst = currentLog(l.Id);
        update new Lead(Id = l.Id, DE_Action__c = 'Not Reached');
        update new Lead(Id = l.Id, DE_Action__c = 'Responded');
        Test.stopTest();

        DE_Assignment_Log__c log = currentLog(l.Id);
        List<DE_Log_Action__c> actions = [
            SELECT Action__c, Source__c, Actioned_By__c, Time_To_Action_Mins__c, Time_To_Action_Days__c
            FROM DE_Log_Action__c
            WHERE Assignment_Log__c = :log.Id
            ORDER BY Name
        ];
        Assert.areEqual(2, actions.size(), 'Two tracked actions; untracked values are ignored');
        Assert.areEqual('Contacted', actions[0].Action__c, 'First action value');
        Assert.areEqual('Responded', actions[1].Action__c, 'Second action value');
        Assert.areEqual('Field Change', actions[0].Source__c, 'Field change source');
        Assert.areEqual(UserInfo.getUserId(), actions[0].Actioned_By__c, 'Actor stored');
        Assert.isNotNull(actions[0].Time_To_Action_Days__c, 'Days computed');
        Assert.areEqual(2, log.Actions_Complete__c, 'Actions counted on the log');
        Assert.isNotNull(log.Last_Action_At__c, 'Last action stamped');
        Assert.areEqual(afterFirst.Action_At__c, log.Action_At__c, 'First action time is kept');
    }

    // ------------------------------------------------------------------ trigger attempt

    @IsTest
    static void triggerDistributionStampsLastAttempt() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.distributor.Type__c = 'Trigger';
        update f.distributor;
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];

        Test.startTest();
        update new Lead(Id = l.Id, DE_Trigger_Distribution__c = true);
        Test.stopTest();

        String key = String.valueOf(l.Id);
        DE_Record_Detail__c d = [SELECT Trigger_Last_Attempt__c FROM DE_Record_Detail__c WHERE Record_Id__c = :key];
        Assert.isNotNull(d.Trigger_Last_Attempt__c, 'Last trigger attempt recorded');
        Assert.areEqual(l.Id, currentLog(l.Id).Lead__c, 'Trigger logs carry the record lookup');
    }

    // ------------------------------------------------------------------ widget

    @IsTest
    static void widgetHidesInactiveRecordsForActiveOnlyTeams() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Widget_Active_Only__c = true;
        f.team.Active_Status_Field__c = 'LeadSource';
        f.team.Active_Status_Values__c = 'Web';
        update f.team;
        List<Lead> leads = webLeads(2, f.queue.Id);
        DE_DistributionRunner.runStandard(new Map<Id, Lead>(leads).keySet(), null);
        update new Lead(Id = leads[1].Id, LeadSource = 'Phone Inquiry');

        Test.startTest();
        List<DE_Assignment_Log__c> logs = [
            SELECT Record_Id__c, Object_API_Name__c, Team__r.Widget_Active_Only__c, Team__r.Active_Status_Field__c, Team__r.Active_Status_Values__c
            FROM DE_Assignment_Log__c
            WHERE Team__c = :f.team.Id AND Current__c = TRUE
        ];
        Set<Id> hidden = DE_WidgetController.inactiveRecords(logs);
        Test.stopTest();

        Assert.areEqual(2, logs.size(), 'Both leads assigned');
        Assert.isTrue(hidden.contains(leads[1].Id), 'Inactive lead hidden');
        Assert.isFalse(hidden.contains(leads[0].Id), 'Active lead shown');
    }
}
