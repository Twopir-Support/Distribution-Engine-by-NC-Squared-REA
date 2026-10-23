@IsTest
private class DE_SlaServiceTest {
    private class Setup {
        DE_TestFactory.Fixture f;
        DE_SLA__c first;
        Lead lead;
        User spare;
    }

    /** One-member Lead team with SLA checkpoints (wall-clock minutes) and one distributed lead. */
    private static Setup setup(List<Integer> checkpointMinutes, Boolean autoReassign) {
        Setup s = new Setup();
        s.f = DE_TestFactory.leadFixture(1, 'Round Robin');
        s.spare = DE_TestFactory.users(1)[0];
        s.f.team.SLA_Respect_Hours__c = 'None';
        update s.f.team;
        s.f.distributor.SLA_Enabled__c = true;
        if (autoReassign) {
            s.f.distributor.Auto_Reassign__c = true;
            s.f.distributor.Reassign_From_SLA__c = 1;
            s.f.distributor.Reassign_To_Id__c = s.spare.Id;
            s.f.distributor.Reassign_Field_Updates__c = 'Title=Reassigned after SLA';
            s.f.distributor.Toggle_User_Off__c = true;
            s.f.distributor.Remove_Sticky_On_Reassign__c = 'Always';
        }
        update s.f.distributor;
        List<DE_SLA__c> slas = new List<DE_SLA__c>();
        for (Integer i = 0; i < checkpointMinutes.size(); i++) {
            slas.add(
                new DE_SLA__c(
                    Name = 'Checkpoint ' + (i + 1),
                    Team__c = s.f.team.Id,
                    Checkpoint__c = i + 1,
                    Alert_Type__c = 'Time Checkpoint',
                    Minutes_After_Assignment__c = checkpointMinutes[i],
                    Notify_Assignee__c = true,
                    Active__c = true
                )
            );
        }
        insert slas;
        s.first = slas[0];
        return s;
    }

    private static void distribute(Setup s) {
        s.lead = DE_TestFactory.insertLeads(1, s.f.queue.Id)[0];
        DE_DistributionRunner.runStandard(new Set<Id>{ s.lead.Id }, null);
    }

    private static DE_Assignment_Log__c currentLog(Id recordId) {
        return [
            SELECT Id, Status__c, SLA_Status__c, SLA_Missed__c, Last_SLA_Checkpoint__c, Next_SLA_Check__c, Assigned_At__c, Current__c, Sticky_Key__c, Message__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :recordId AND Type__c = 'Standard'
            LIMIT 1
        ];
    }

    /** Moves the assignment back in time so checkpoints are due now. */
    private static DE_Assignment_Log__c backdate(Id recordId, Integer minutesAgo) {
        DE_Assignment_Log__c l = currentLog(recordId);
        l.Assigned_At__c = System.now().addMinutes(-minutesAgo);
        l.Next_SLA_Check__c = System.now().addMinutes(-1);
        update l;
        return l;
    }

    @IsTest
    static void assignmentSchedulesFirstCheckpoint() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        Datetime before = System.now();

        Test.startTest();
        distribute(s);
        Test.stopTest();

        DE_Assignment_Log__c l = currentLog(s.lead.Id);
        Assert.areEqual('Pending', l.SLA_Status__c, 'SLA is pending after assignment');
        Assert.isNotNull(l.Next_SLA_Check__c, 'Next check scheduled');
        Long minutes = (l.Next_SLA_Check__c.getTime() - l.Assigned_At__c.getTime()) / 60000;
        Assert.areEqual(30, minutes, 'Checkpoint is 30 wall-clock minutes after assignment');
        Assert.isTrue(l.Assigned_At__c >= before.addSeconds(-1), 'Assigned now');
    }

    @IsTest
    static void missedCheckpointRaisesAlert() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        distribute(s);
        backdate(s.lead.Id, 60);

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(1, summary.checked, 'One log checked');
        Assert.areEqual(1, summary.missed, 'One SLA missed');
        Assert.areEqual(0, summary.reassigned, 'No auto reassign configured');
        DE_Assignment_Log__c l = currentLog(s.lead.Id);
        Assert.areEqual('SLA Alert', l.Status__c, 'Log flagged as an SLA alert');
        Assert.areEqual(1, l.SLA_Missed__c, 'One checkpoint missed');
        Assert.areEqual(1, l.Last_SLA_Checkpoint__c, 'Checkpoint 1 processed');
        Assert.areEqual('Missed', l.SLA_Status__c, 'No further checkpoints: SLA missed');
        Assert.isNull(l.Next_SLA_Check__c, 'Nothing left to check');
        Assert.isTrue(l.Current__c, 'Assignment stays current without auto reassign');
        Assert.areEqual(s.f.users[0].Id, [SELECT OwnerId FROM Lead WHERE Id = :s.lead.Id].OwnerId, 'Owner unchanged');
    }

    @IsTest
    static void falseConditionMeansSlaMet() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        // SLA missed only when Title is blank.
        DE_Condition__c c = DE_TestFactory.condition('SLA Condition', 1, 'Title', 'is blank', null);
        c.SLA__c = s.first.Id;
        insert c;
        distribute(s);
        Lead l = new Lead(Id = s.lead.Id, Title = 'Called back');
        update l;
        backdate(s.lead.Id, 60);

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(0, summary.missed, 'Condition false: not missed');
        DE_Assignment_Log__c log = currentLog(s.lead.Id);
        Assert.areEqual('Met', log.SLA_Status__c, 'SLA met');
        Assert.areEqual('Assigned', log.Status__c, 'Status unchanged');
        Assert.areEqual(1, log.Last_SLA_Checkpoint__c, 'Checkpoint 1 evaluated');
    }

    @IsTest
    static void laterCheckpointIsScheduledAfterFirstMiss() {
        Setup s = setup(new List<Integer>{ 30, 120 }, false);
        distribute(s);
        backdate(s.lead.Id, 60);
        DE_Assignment_Log__c start = currentLog(s.lead.Id);

        Test.startTest();
        DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        DE_Assignment_Log__c l = currentLog(s.lead.Id);
        Assert.areEqual('Pending', l.SLA_Status__c, 'Checkpoint 2 still pending');
        Assert.areEqual(1, l.SLA_Missed__c, 'First checkpoint missed');
        Assert.areEqual(start.Assigned_At__c.addMinutes(120), l.Next_SLA_Check__c, 'Next check at checkpoint 2');
    }

    @IsTest
    static void autoReassignAfterMissedCheckpoint() {
        Setup s = setup(new List<Integer>{ 30 }, true);
        distribute(s);
        Id original = s.f.users[0].Id;
        DE_Assignment_Log__c l = backdate(s.lead.Id, 60);
        l.Sticky_Key__c = 'stickykey';
        update l;
        DE_Assignment_Log__c olderSticky = new DE_Assignment_Log__c(
            Record_Id__c = s.lead.Id,
            Object_API_Name__c = 'Lead',
            Status__c = 'Assigned',
            Type__c = 'Trigger',
            Current__c = false,
            Sticky_Key__c = 'stickykey'
        );
        insert olderSticky;

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(1, summary.reassigned, 'Record reassigned');
        Lead after = [SELECT OwnerId, Title, DE_Is_Reassigned__c, DE_Last_Reassigned__c FROM Lead WHERE Id = :s.lead.Id];
        Assert.areEqual(s.spare.Id, after.OwnerId, 'Reassigned to the Reassign To user');
        Assert.areEqual('Reassigned after SLA', after.Title, 'Reassign field updates applied');
        Assert.isTrue(after.DE_Is_Reassigned__c, 'Reassigned flag set');
        Assert.isNotNull(after.DE_Last_Reassigned__c, 'Reassigned time set');

        DE_Assignment_Log__c old = currentLog(s.lead.Id);
        Assert.areEqual('Reassigned', old.Status__c, 'Original log marked reassigned');
        Assert.isFalse(old.Current__c, 'Original log no longer current');
        Assert.areEqual('Missed', old.SLA_Status__c, 'Original SLA missed');
        Assert.isNull(old.Sticky_Key__c, 'Sticky key removed from the reassigned log');
        Assert.isNull([SELECT Sticky_Key__c FROM DE_Assignment_Log__c WHERE Id = :olderSticky.Id].Sticky_Key__c, 'Always mode clears every log with the key');

        DE_Assignment_Log__c fresh = [
            SELECT Assignee_Id__c, Current__c, Status__c, Previous_Owner_Id__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :s.lead.Id AND Type__c = 'Reassignment'
        ];
        Assert.areEqual(String.valueOf(s.spare.Id), fresh.Assignee_Id__c, 'New log for the new owner');
        Assert.isTrue(fresh.Current__c, 'New log is current');
        Assert.areEqual(String.valueOf(original), fresh.Previous_Owner_Id__c, 'Previous owner recorded');

        DE_Agent__c agent = [SELECT Online__c, Toggle_Reason__c FROM DE_Agent__c WHERE User__c = :original];
        Assert.isFalse(agent.Online__c, 'Assignee toggled offline after missing the SLA');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Availability_Event__c WHERE User__c = :original AND Source__c = 'Auto Reassign'], 'Toggle audited');
        DE_Record_Detail__c detail = [SELECT Previous_Assignees__c FROM DE_Record_Detail__c WHERE Record_Id__c = :s.lead.Id];
        Assert.isTrue(detail.Previous_Assignees__c.contains(String.valueOf(original)), 'Original assignee tracked');
    }

    @IsTest
    static void ownerChangeCancelsSla() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        distribute(s);
        update new Lead(Id = s.lead.Id, OwnerId = s.spare.Id);
        backdate(s.lead.Id, 60);

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(1, summary.cancelled, 'SLA cancelled');
        Assert.areEqual(0, summary.missed, 'Not counted as missed');
        DE_Assignment_Log__c l = currentLog(s.lead.Id);
        Assert.areEqual('Cancelled', l.SLA_Status__c, 'SLA status cancelled');
        Assert.areEqual('Owner changed after assignment', l.Message__c, 'Reason recorded');
    }

    @IsTest
    static void inactiveStatusEndsSla() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        s.f.team.Active_Status_Field__c = 'Title';
        s.f.team.Active_Status_Values__c = 'Open';
        s.f.team.Apply_Active_Status_To_SLAs__c = true;
        update s.f.team;
        s.lead = DE_TestFactory.leads(1, s.f.queue.Id)[0];
        s.lead.Title = 'Open';
        insert s.lead;
        DE_DistributionRunner.runStandard(new Set<Id>{ s.lead.Id }, null);
        Assert.areEqual(s.f.users[0].Id, [SELECT OwnerId FROM Lead WHERE Id = :s.lead.Id].OwnerId, 'Active lead distributed');
        update new Lead(Id = s.lead.Id, Title = 'Closed');
        backdate(s.lead.Id, 60);

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(0, summary.missed, 'Inactive record is not alerted');
        Assert.areEqual('Met', currentLog(s.lead.Id).SLA_Status__c, 'SLA closed as met once inactive');
    }

    @IsTest
    static void nothingDueDoesNothing() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        distribute(s);

        Test.startTest();
        DE_SlaService.MonitorSummary summary = DE_SlaService.monitor(200, System.now());
        Test.stopTest();

        Assert.areEqual(0, summary.checked, 'Checkpoint not yet due');
        Assert.areEqual('Pending', currentLog(s.lead.Id).SLA_Status__c, 'Still pending');
    }

    @IsTest
    static void dueTimeAndStampRules() {
        Setup s = setup(new List<Integer>{ 30 }, false);
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(s.f.team.Id, true);
        Datetime assignedAt = Datetime.newInstanceGmt(2026, 3, 2, 10, 0, 0);

        Test.startTest();
        Datetime timed = DE_SlaService.dueTime(cfg, null, cfg.slas[0], assignedAt, null);
        Datetime continuous = DE_SlaService.dueTime(
            cfg,
            null,
            new DE_SLA__c(Alert_Type__c = 'Continuous Field Monitoring', Minutes_After_Assignment__c = 60),
            assignedAt,
            null
        );
        Datetime customNoField = DE_SlaService.dueTime(cfg, null, new DE_SLA__c(Alert_Type__c = 'Custom Date/Time'), assignedAt, null);
        cfg.slas[0].Stamp_Value__c = 'VIP';
        DE_SlaService.Checkpoint noStamp = DE_SlaService.nextCheckpoint(cfg, null, assignedAt, null, 0, new DE_Record_Detail__c(Stamps__c = 'Standard'));
        DE_SlaService.Checkpoint withStamp = DE_SlaService.nextCheckpoint(cfg, null, assignedAt, null, 0, new DE_Record_Detail__c(Stamps__c = 'Gold; vip'));
        DE_SlaService.Checkpoint afterLast = DE_SlaService.nextCheckpoint(cfg, null, assignedAt, null, 1, new DE_Record_Detail__c(Stamps__c = 'VIP'));
        Test.stopTest();

        Assert.areEqual(assignedAt.addMinutes(30), timed, 'Time checkpoint is minutes after assignment');
        Assert.areEqual(assignedAt, continuous, 'Continuous monitoring starts at assignment');
        Assert.isNull(customNoField, 'Custom date/time without a field cannot be scheduled');
        Assert.isNull(noStamp, 'Stamp-specific SLA skipped without the stamp');
        Assert.isNotNull(withStamp, 'Stamp-specific SLA applies when the record has the stamp');
        Assert.areEqual(1, withStamp.sla.Checkpoint__c.intValue(), 'Checkpoint 1 returned');
        Assert.isNull(afterLast, 'No checkpoint after the last one');
    }
}
