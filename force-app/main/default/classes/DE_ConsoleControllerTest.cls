@IsTest
private class DE_ConsoleControllerTest {
    private static DE_Assignment_Log__c log(DE_TestFactory.Fixture f, SObject rec, User assignee, String status, Datetime at) {
        return new DE_Assignment_Log__c(
            Record_Id__c = rec.Id,
            Record_Name__c = (String) rec.get('LastName'),
            Object_API_Name__c = 'Lead',
            Team__c = f.team.Id,
            Distributor__c = f.distributor.Id,
            Assignee_Id__c = assignee.Id,
            Assigned_User__c = assignee.Id,
            Status__c = status,
            Type__c = 'Standard',
            Method__c = 'Round Robin',
            Assigned_At__c = at,
            Current__c = status == 'Assigned'
        );
    }

    @IsTest
    static void requiresConsoleAccess() {
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_ConsoleController.getMonitoring();
            Assert.fail('Users cannot open the console.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('Distribution Console'), e.getMessage());
        }
        try {
            DE_ConsoleController.startScheduler();
            Assert.fail('Only admins start the scheduler.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isFalse(DE_SchedulerJob.isRunning(), 'Nothing was enqueued.');
        }
    }

    @IsTest
    static void monitoringReflectsRunLogs() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();
        insert new List<DE_Run_Log__c>{
            new DE_Run_Log__c(Process__c = 'Scheduler', Status__c = 'Error', Started_At__c = System.now(), Message__c = 'Boom'),
            new DE_Run_Log__c(Process__c = 'Health Checker', Status__c = 'Warning', Started_At__c = System.now().addMinutes(-5)),
            new DE_Run_Log__c(Process__c = 'Classifier', Status__c = 'Success', Started_At__c = System.now().addMinutes(-2))
        };

        DE_ConsoleController.Monitoring m = DE_ConsoleController.getMonitoring();

        Assert.isTrue(m.engineEnabled, 'Engine enabled by the test settings.');
        Assert.areEqual('Errored', m.schedulerStatus, 'Last scheduler run errored.');
        Assert.areEqual('Boom', m.lastRunMessage, 'Last run message shown.');
        Assert.areEqual(1, m.errorsLastDay, 'One error in the last day.');
        Assert.areEqual(1, m.restartsLastDay, 'One health checker restart.');
        Assert.isNotNull(m.lastClassifierRun, 'Last classifier run shown.');
        Assert.areEqual(0, m.onHold, 'Nothing on hold.');
        Assert.areEqual(3, DE_ConsoleController.getRunLogs(null).size(), 'All run logs listed.');
        Assert.areEqual(1, DE_ConsoleController.getRunLogs('Classifier').size(), 'Run logs filtered by process.');
    }

    @IsTest
    static void startsAndStopsScheduler() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();

        Test.startTest();
        Boolean started = DE_ConsoleController.startScheduler();
        Assert.isTrue(started, 'The scheduler chain is started.');
        Assert.isTrue(DE_HealthChecker.isScheduled(), 'Starting also schedules the health checker.');
        DE_ConsoleController.stopScheduler();
        Assert.isFalse(DE_HealthChecker.isScheduled(), 'Stopping unschedules the health checker.');
        Test.stopTest();

        try {
            DE_ConsoleController.scheduleHealthChecker(7);
            Assert.fail('Only 15, 30 or 60 minutes are allowed.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('15, 30 or 60'), e.getMessage());
        }
    }

    @IsTest
    static void summarisesTodaysDistributions() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.users[0].Id);
        DE_Assignment_Log__c missed = log(f, leads[1], f.users[0], 'Assigned', System.now());
        missed.SLA_Missed__c = 1;
        insert new List<DE_Assignment_Log__c>{
            log(f, leads[0], f.users[0], 'Assigned', System.now()),
            missed,
            log(f, leads[2], f.users[1], 'Rejected', System.now()),
            log(f, leads[3], f.users[1], 'Error', System.now())
        };
        DE_TestFactory.grantAll();

        List<DE_ConsoleController.TeamToday> rows = DE_ConsoleController.getTodaysDistributions();

        Assert.areEqual(1, rows.size(), 'One active team.');
        Assert.areEqual(3, rows[0].distributions, 'Assigned and rejected logs count as distributions.');
        Assert.areEqual(1, rows[0].rejections, 'One rejection.');
        Assert.areEqual(1, rows[0].errors, 'One error.');
        Assert.areEqual(1, rows[0].slaAlerts, 'One SLA alert.');
        Assert.areEqual(2, rows[0].members, 'Two members.');
        Assert.areEqual(2, rows[0].available, 'Both available.');
    }

    @IsTest
    static void listsSourcesAndPreview() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.insertLeads(3, f.queue.Id);
        DE_TestFactory.grantAll();

        List<DE_ConsoleController.SourceRow> sources = DE_ConsoleController.getSources();
        Assert.areEqual(1, sources.size(), 'One standard distributor.');
        Assert.areEqual(3, sources[0].waiting, 'Three leads wait in the queue.');
        Assert.areEqual(f.queue.Name + ' (queue)', sources[0].source, 'Source queue named.');
        Assert.isTrue(sources[0].active, 'Team and distributor are active.');
        Assert.areEqual(3, DE_ConsoleController.getSourcePreview(f.distributor.Id).size(), 'Preview lists the waiting leads.');
    }

    @IsTest
    static void filtersLogsAndLimitsUsersToOwn() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.users[0].Id);
        User me = new User(Id = UserInfo.getUserId());
        DE_Assignment_Log__c mine = log(f, leads[2], me, 'Assigned', System.now());
        mine.Decision_Trace__c = 'Round robin picked me.';
        insert new List<DE_Assignment_Log__c>{
            log(f, leads[0], f.users[0], 'Assigned', System.now()),
            log(f, leads[1], f.users[0], 'Rejected', System.now().addDays(-20)),
            mine
        };
        DE_TestFactory.grantAll();

        Assert.areEqual(2, DE_ConsoleController.getLogs(null).size(), 'Default range is the last 7 days.');
        DE_ConsoleController.LogFilter filter = new DE_ConsoleController.LogFilter();
        filter.fromDate = Date.today().addDays(-30);
        filter.status = 'Rejected';
        Assert.areEqual(1, DE_ConsoleController.getLogs(filter).size(), 'Status filter.');
        filter = new DE_ConsoleController.LogFilter();
        filter.search = 'Lead 0';
        filter.teamId = f.team.Id;
        Assert.areEqual(1, DE_ConsoleController.getLogs(filter).size(), 'Search by record name.');
        Assert.areEqual('Round robin picked me.', DE_ConsoleController.getLogTrace(mine.Id).Decision_Trace__c, 'Trace returned.');

        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        List<DE_Assignment_Log__c> own = DE_ConsoleController.getLogs(null);
        Assert.areEqual(1, own.size(), 'Users only see their own assignments.');
        Assert.areEqual(mine.Id, own[0].Id, 'It is the running user\'s log.');
    }

    @IsTest
    static void retryClearsHoldsAndDistributes() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);
        List<DE_Record_Detail__c> holds = new List<DE_Record_Detail__c>();
        for (Lead l : leads) {
            holds.add(
                new DE_Record_Detail__c(Record_Id__c = l.Id, Object_API_Name__c = 'Lead', On_Hold_Until__c = System.now().addHours(1), Failed_Attempts__c = 0)
            );
        }
        insert holds;
        DE_TestFactory.grantAll();

        Test.startTest();
        Integer assigned = DE_ConsoleController.retry(new List<String>{ leads[0].Id, leads[1].Id, leads[2].Id, 'not-an-id' });
        Test.stopTest();

        Assert.areEqual(3, assigned, 'All held leads are distributed on retry.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Record_Detail__c WHERE On_Hold_Until__c != NULL], 'Holds cleared.');
        for (Id owner : DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()).values()) {
            Assert.areEqual(User.SObjectType, owner.getSobjectType(), 'Each lead is owned by a team member.');
        }
    }

    @IsTest
    static void retryAllClearsRecentHolds() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        insert new DE_Record_Detail__c(Record_Id__c = l.Id, Object_API_Name__c = 'Lead', On_Hold_Until__c = System.now().addHours(1), Failed_Attempts__c = 3);
        insert new DE_Assignment_Log__c(
            Record_Id__c = l.Id,
            Object_API_Name__c = 'Lead',
            Status__c = 'On Hold',
            Type__c = 'Standard',
            Assigned_At__c = System.now()
        );
        DE_TestFactory.grantAll();

        Assert.areEqual(1, DE_ConsoleController.retryAll(), 'One record released.');
        DE_Record_Detail__c d = [SELECT On_Hold_Until__c, Failed_Attempts__c FROM DE_Record_Detail__c];
        Assert.isNull(d.On_Hold_Until__c, 'Hold cleared.');
        Assert.areEqual(0, d.Failed_Attempts__c, 'Failures reset.');
    }

    @IsTest
    static void analyticsAndPerformance() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.users[0].Id);
        DE_Assignment_Log__c actioned = log(f, leads[0], f.users[0], 'Assigned', System.now());
        actioned.Action_At__c = System.now();
        actioned.Time_To_Action_Mins__c = 10;
        actioned.Speed_To_Assign_Seconds__c = 30;
        DE_Assignment_Log__c reassigned = log(f, leads[1], f.users[0], 'Reassigned', System.now());
        reassigned.Speed_To_Assign_Seconds__c = 90;
        reassigned.SLA_Missed__c = 1;
        insert new List<DE_Assignment_Log__c>{ actioned, reassigned };
        insert new DE_Availability_Event__c(User__c = f.users[0].Id, Online__c = false, Changed_At__c = System.now(), Source__c = 'User');
        DE_TestFactory.grantAll();

        DE_ConsoleController.Analytics a = DE_ConsoleController.getAnalytics(null, null, f.team.Id, 'Lead', 'User');
        Decimal total = 0;
        for (DE_ConsoleController.SeriesPoint p : a.overTime) {
            total += p.y;
        }
        Assert.areEqual(2, total, 'Both distributions appear over time.');
        Assert.areEqual(1, a.timeToAction.size(), 'One user with time to action.');
        Assert.areEqual(10, a.timeToAction[0].y, 'Average time to action.');
        Assert.areEqual(1, a.userActivity.size(), 'One toggle recorded.');
        Assert.areEqual('Toggled off', a.userActivity[0].series, 'Toggle direction.');
        Assert.isFalse(a.hourly.isEmpty(), 'Hourly distribution is returned.');

        List<DE_ConsoleController.PerformanceRow> perf = DE_ConsoleController.getTeamPerformance(f.team.Id, null, null);
        Assert.areEqual(1, perf.size(), 'One assignee.');
        Assert.areEqual(2, perf[0].assigned, 'Two assignments.');
        Assert.areEqual(1, perf[0].actioned, 'One actioned.');
        Assert.areEqual(50.0, perf[0].actionedPercent, 'Half actioned.');
        Assert.areEqual(10.0, perf[0].avgTimeToAction, 'Average time to action.');
        Assert.areEqual(60, perf[0].avgSpeedToAssignSeconds, 'Average speed to assign.');
        Assert.areEqual(1, perf[0].reassignments, 'One reassignment.');
        Assert.areEqual(1, perf[0].slasMissed, 'One SLA missed.');
        Assert.areEqual(0.0, perf[0].conversionPercent, 'No leads converted.');
    }

    @IsTest
    static void managesObjectSyncActions() {
        DE_TestFactory.grantAll();
        DE_Object_Sync__c action = new DE_Object_Sync__c(
            Name = 'Contacts follow account',
            Parent_Object__c = 'Account',
            Child_Object__c = 'Contact',
            Lookup_Field__c = 'AccountId',
            Active__c = true
        );
        Id actionId = DE_ConsoleController.saveSyncAction(
            action,
            new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'Email', Operator__c = 'is not blank') }
        );

        List<DE_ClassifierController.ConditionalRecord> actions = DE_ConsoleController.getSyncActions();
        Assert.areEqual(1, actions.size(), 'Sync action listed.');
        Assert.areEqual(1, actions[0].conditions.size(), 'Its filter is listed.');

        try {
            DE_ConsoleController.saveSyncAction(
                new DE_Object_Sync__c(Name = 'Bad', Parent_Object__c = 'Account', Child_Object__c = 'Contact', Lookup_Field__c = 'Email'),
                null
            );
            Assert.fail('The lookup field must be a reference.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose the lookup field'), e.getMessage());
        }

        DE_ConsoleController.deleteSyncAction(actionId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Object_Sync__c], 'Sync action deleted.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Condition__c], 'Its conditions are deleted.');
    }

    @IsTest
    static void listsAndRestoresArchivedLeads() {
        DE_TestFactory.settings();
        Group q = DE_TestFactory.queue('DE Archive Source', new List<String>{ 'Lead' });
        Lead l = DE_TestFactory.leads(1, UserInfo.getUserId())[0];
        l.DE_Is_Archived__c = true;
        l.DE_Source_Queue__c = q.Id;
        l.DE_Last_Archive_Date__c = System.now();
        insert l;
        DE_TestFactory.grantAll();

        List<Map<String, Object>> archived = DE_ConsoleController.getArchived('Lead');
        Assert.areEqual(1, archived.size(), 'Archived lead listed.');
        Assert.areEqual(l.Id, archived[0].get('id'), 'It is the archived lead.');
        try {
            DE_ConsoleController.getArchived('Account');
            Assert.fail('Archive only covers leads and cases.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Leads and Cases'), e.getMessage());
        }

        Assert.areEqual(1, DE_ConsoleController.restoreArchived(new List<Id>{ l.Id }), 'One lead restored.');
        Lead restored = [SELECT OwnerId, DE_Is_Archived__c FROM Lead WHERE Id = :l.Id];
        Assert.isFalse(restored.DE_Is_Archived__c, 'No longer archived.');
        Assert.areEqual(q.Id, restored.OwnerId, 'Returned to its source queue.');
    }
}
