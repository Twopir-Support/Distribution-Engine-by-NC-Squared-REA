@IsTest
private class DE_SchedulingTest {
    private static Integer healthJobs() {
        String pattern = DE_HealthChecker.JOB_NAME + '%';
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern];
    }

    @IsTest
    static void schedulerRunDistributesAndLogs() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        System.enqueueJob(new DE_SchedulerJob(null, false));
        Test.stopTest();

        for (Id owner : DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()).values()) {
            Assert.areNotEqual(f.queue.Id, owner, 'Every lead left the queue.');
        }
        DE_Run_Log__c run = [SELECT Status__c, Records_Processed__c, Assignments__c FROM DE_Run_Log__c WHERE Process__c = 'Scheduler'];
        Assert.areEqual('Success', run.Status__c, 'Run succeeded.');
        Assert.areEqual(4, run.Records_Processed__c, 'Four records processed.');
        Assert.areEqual(4, run.Assignments__c, 'Four assignments.');
    }

    @IsTest
    static void schedulerDoesNothingWhenEngineDisabled() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Settings__c s = DE_Settings__c.getOrgDefaults();
        s.Engine_Enabled__c = false;
        update s;
        DE_Settings.setForTransaction(null);
        Lead l = DE_TestFactory.insertLeads(1, f.queue.Id)[0];

        Test.startTest();
        System.enqueueJob(new DE_SchedulerJob());
        Test.stopTest();

        Assert.areEqual(f.queue.Id, [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId, 'Nothing is distributed while disabled.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Run_Log__c], 'No run is logged.');
        Assert.areEqual('Engine is disabled in Distribution Settings.', DE_HealthChecker.check(), 'The health checker reports the disabled engine.');
    }

    @IsTest
    static void startAndStopTheChain() {
        DE_TestFactory.settings();
        Test.startTest();
        Assert.isTrue(DE_SchedulerJob.start(), 'The first start enqueues a job.');
        Assert.isTrue(DE_SchedulerJob.isRunning(), 'The queued job counts as running.');
        Assert.isFalse(DE_SchedulerJob.start(), 'A second start does nothing while a job is queued.');
        Assert.areEqual(1, DE_SchedulerJob.stop(), 'Stop aborts the queued job.');
        Test.stopTest();
    }

    @IsTest
    static void healthCheckerRestartsStoppedScheduler() {
        DE_TestFactory.settings();
        Test.startTest();
        String message = DE_HealthChecker.check();
        Test.stopTest();
        Assert.areEqual('Scheduler was not running and has been restarted.', message, 'Restart reported.');
        DE_Run_Log__c run = [SELECT Status__c FROM DE_Run_Log__c WHERE Process__c = 'Health Checker'];
        Assert.areEqual('Warning', run.Status__c, 'A restart is a warning.');
    }

    @IsTest
    static void schedulesAndUnschedulesHealthChecker() {
        DE_TestFactory.settings();
        Test.startTest();
        DE_HealthChecker.schedule(15);
        Assert.areEqual(4, healthJobs(), 'Every 15 minutes needs four hourly jobs.');
        DE_HealthChecker.schedule(null);
        Assert.areEqual(1, healthJobs(), 'Rescheduling replaces the jobs; hourly is one job.');
        Assert.isTrue(DE_HealthChecker.isScheduled(), 'Scheduled.');
        DE_HealthChecker.unschedule();
        Assert.isFalse(DE_HealthChecker.isScheduled(), 'Unscheduled.');
        Test.stopTest();
    }

    @IsTest
    static void healthCheckerRunsAsSchedulable() {
        DE_TestFactory.settings();
        Test.startTest();
        Id jobId = System.schedule('DE Health Test', '0 0 * * * ?', new DE_HealthChecker());
        Test.stopTest();
        Assert.isNotNull(jobId, 'Scheduled.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Health Checker'], 'The scheduled run checked the scheduler.');
    }

    @IsTest
    static void maintenancePurgesOldLogs() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Log_Retention_Days__c = 30;
        update s;
        DE_Settings.setForTransaction(null);
        Datetime old = System.now().addDays(-40);
        insert new List<DE_Assignment_Log__c>{
            new DE_Assignment_Log__c(Record_Id__c = 'x1', Status__c = 'Assigned', Assigned_At__c = old, Current__c = false),
            new DE_Assignment_Log__c(Record_Id__c = 'x2', Status__c = 'Assigned', Assigned_At__c = old, Current__c = true),
            new DE_Assignment_Log__c(Record_Id__c = 'x3', Status__c = 'Assigned', Assigned_At__c = System.now(), Current__c = false)
        };
        insert new List<DE_Run_Log__c>{
            new DE_Run_Log__c(Process__c = 'Scheduler', Status__c = 'Success', Started_At__c = old),
            new DE_Run_Log__c(Process__c = 'Scheduler', Status__c = 'Success', Started_At__c = System.now())
        };
        insert new DE_Availability_Event__c(User__c = UserInfo.getUserId(), Online__c = true, Changed_At__c = System.now().addDays(-100), Source__c = 'User');

        Test.startTest();
        Database.executeBatch(new DE_MaintenanceBatch(), 200);
        Test.stopTest();

        Set<String> remaining = new Set<String>();
        for (DE_Assignment_Log__c l : [SELECT Record_Id__c FROM DE_Assignment_Log__c]) {
            remaining.add(l.Record_Id__c);
        }
        Assert.areEqual(new Set<String>{ 'x2', 'x3' }, remaining, 'Old non-current logs are purged; current and recent logs stay.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Run_Log__c WHERE Started_At__c < :System.now().addDays(-30)], 'Old run logs purged.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Availability_Event__c], 'Availability history older than 92 days purged.');
        DE_Run_Log__c purge = [SELECT Records_Processed__c FROM DE_Run_Log__c WHERE Process__c = 'Purge'];
        Assert.areEqual(3, purge.Records_Processed__c, 'One distribution log, one run log and one event purged.');
    }

    @IsTest
    static void permissionHierarchy() {
        DE_Team__c managed = new DE_Team__c(Name = 'Mine', Manager_User_Ids__c = UserInfo.getUserId());
        DE_Team__c other = new DE_Team__c(Name = 'Other');

        DE_TestFactory.grant(new Set<String>{ 'DE_Admin' });
        Assert.isTrue(DE_Permissions.isUser() && DE_Permissions.isTeamManager() && DE_Permissions.isSystemManager(), 'Admin implies every role.');
        Assert.isTrue(DE_Permissions.canManageTeam(other), 'Admins manage every team.');

        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        Assert.isTrue(DE_Permissions.isUser(), 'Team managers are users.');
        Assert.isFalse(DE_Permissions.isSystemManager(), 'Team managers are not system managers.');
        Assert.isTrue(DE_Permissions.canManageTeam(managed), 'Managers manage teams that list them.');
        Assert.isFalse(DE_Permissions.canManageTeam(other), 'Managers do not manage other teams.');

        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        Assert.isFalse(DE_Permissions.isTeamManager(), 'Users are not managers.');
        Assert.isFalse(DE_Permissions.canManageTeam(managed), 'Users cannot manage teams even if listed.');
        try {
            DE_Permissions.require(DE_Permissions.isAdmin(), 'do admin things');
            Assert.fail('require throws when not allowed.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual('You do not have permission to do admin things.', e.getMessage(), 'Message names the action.');
        }
    }
}
