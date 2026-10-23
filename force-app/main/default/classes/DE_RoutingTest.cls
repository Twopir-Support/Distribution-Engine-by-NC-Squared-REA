/**
 * End-to-end tests for Standard distribution (DE_DistributionRunner.runStandard): leads and cases
 * waiting in a queue are routed by round robin, weighting, load balancing and owner methods,
 * subject to caps, sticky matches, availability and filters.
 */
@IsTest
private class DE_RoutingTest {
    // ------------------------------------------------------------------ helpers

    private static DE_Settings__c updateSettings(DE_Settings__c s) {
        update s;
        DE_Settings.setForTransaction(null);
        return s;
    }

    private static Set<Id> ids(List<SObject> records) {
        return new Map<Id, SObject>(records).keySet();
    }

    private static List<String> keys(Set<Id> recordIds) {
        List<String> out = new List<String>();
        for (Id i : recordIds) {
            out.add(String.valueOf(i));
        }
        return out;
    }

    private static List<DE_Assignment_Log__c> logsFor(Set<Id> recordIds) {
        List<String> recordKeys = keys(recordIds);
        return [
            SELECT Id, Record_Id__c, Assignee_Id__c, Assigned_User__c, Status__c, Method__c, Type__c, Current__c, Team__c, Distributor__c, Is_Sticky__c, Sticky_Key__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :recordKeys
            ORDER BY Assigned_At__c, Name
        ];
    }

    /** Assignments that happened earlier today, counted by caps and load balancing. */
    private static void priorAssignments(DE_Team__c team, DE_Distributor__c dist, Id userId, Integer count) {
        List<DE_Assignment_Log__c> logs = new List<DE_Assignment_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(
                new DE_Assignment_Log__c(
                    Team__c = team.Id,
                    Distributor__c = dist.Id,
                    Assignee_Id__c = String.valueOf(userId),
                    Assigned_User__c = userId,
                    Status__c = 'Assigned',
                    Method__c = 'Round Robin',
                    Type__c = 'Standard',
                    Current__c = false,
                    Assigned_At__c = System.now(),
                    Record_Id__c = 'prior' + i
                )
            );
        }
        insert logs;
    }

    private static DE_Agent__c agent(Id userId, Boolean online, String tags) {
        return new DE_Agent__c(Name = 'Agent', User__c = userId, Unique_User__c = String.valueOf(userId), Online__c = online, Tags__c = tags);
    }

    private static Integer countOwnedBy(Map<Id, Id> owners, Id ownerId) {
        Integer n = 0;
        for (Id o : owners.values()) {
            if (o == ownerId) {
                n++;
            }
        }
        return n;
    }

    // ------------------------------------------------------------------ round robin

    @IsTest
    static void roundRobinSpreadsBulkLeadsEvenly() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(3, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(200, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(200, summary.processed, 'All waiting leads should be processed');
        Assert.areEqual(200, summary.assigned, 'All waiting leads should be assigned');
        Assert.areEqual(0, summary.errors, 'No errors expected: ' + summary.messages);
        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', ids(leads)));
        Assert.areEqual(3, counts.size(), 'Every member should receive leads');
        Integer min = 1000;
        Integer max = 0;
        for (User u : f.users) {
            Integer c = counts.get(u.Id);
            Assert.isNotNull(c, 'Member ' + u.LastName + ' received nothing');
            min = Math.min(min, c);
            max = Math.max(max, c);
        }
        Assert.isTrue(max - min <= 1, 'Round robin should be even (min ' + min + ', max ' + max + ')');

        DE_Team__c team = [SELECT Rotation_Sequence__c, Total_Assignments__c, Last_Assigned_At__c FROM DE_Team__c WHERE Id = :f.team.Id];
        Assert.areEqual(200, team.Total_Assignments__c, 'Team assignment counter');
        Assert.areEqual(200, team.Rotation_Sequence__c, 'Rotation sequence advances once per hit');
        Assert.isNotNull(team.Last_Assigned_At__c, 'Last assigned timestamp');
        Assert.areEqual(3, [SELECT COUNT() FROM DE_Rotation_State__c WHERE Team__c = :f.team.Id], 'One rotation state per member');
    }

    @IsTest
    static void roundRobinWritesLogsAndTrackingFields() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        List<DE_Assignment_Log__c> logs = logsFor(ids(leads));
        Assert.areEqual(4, logs.size(), 'One log per assignment');
        Set<Id> userIds = new Map<Id, User>(f.users).keySet();
        for (DE_Assignment_Log__c l : logs) {
            Assert.areEqual('Assigned', l.Status__c, 'Status');
            Assert.areEqual('Round Robin', l.Method__c, 'Method');
            Assert.areEqual('Standard', l.Type__c, 'Type');
            Assert.isTrue(l.Current__c, 'Latest log is current');
            Assert.areEqual(f.team.Id, l.Team__c, 'Team');
            Assert.areEqual(f.distributor.Id, l.Distributor__c, 'Distributor');
            Assert.isTrue(userIds.contains(l.Assigned_User__c), 'Assigned user is a member');
            Assert.areEqual(String.valueOf(l.Assigned_User__c), l.Assignee_Id__c, 'Assignee id mirrors user');
        }
        for (Lead l : [SELECT OwnerId, DE_Is_Distributed__c, DE_Last_Distributed__c, DE_Distribution_Count__c FROM Lead WHERE Id IN :leads]) {
            Assert.isTrue(l.DE_Is_Distributed__c, 'Distributed flag');
            Assert.isNotNull(l.DE_Last_Distributed__c, 'Last distributed');
            Assert.areEqual(1, l.DE_Distribution_Count__c, 'Distribution count');
        }
        Assert.areEqual(4, [SELECT COUNT() FROM DE_Record_Detail__c WHERE Record_Id__c IN :keys(ids(leads))], 'Record details track assignees');
    }

    @IsTest
    static void rotationPersistsAcrossRuns() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        Lead first = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        DE_DistributionRunner.runStandard(null, null);
        Id firstOwner = [SELECT OwnerId FROM Lead WHERE Id = :first.Id].OwnerId;

        Lead second = DE_TestFactory.insertLeads(1, f.queue.Id)[0];
        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Id secondOwner = [SELECT OwnerId FROM Lead WHERE Id = :second.Id].OwnerId;
        Assert.areNotEqual(f.queue.Id, firstOwner, 'First lead assigned');
        Assert.areNotEqual(f.queue.Id, secondOwner, 'Second lead assigned');
        Assert.areNotEqual(firstOwner, secondOwner, 'The next run continues the rotation with the other member');
    }

    @IsTest
    static void runWithOnlyRecordIdsIgnoresOtherLeads() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(new Set<Id>{ leads[0].Id }, null);
        Test.stopTest();

        Assert.areEqual(1, summary.assigned, 'Only the requested record is routed');
        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areNotEqual(f.queue.Id, owners.get(leads[0].Id), 'Requested lead assigned');
        Assert.areEqual(f.queue.Id, owners.get(leads[1].Id), 'Other leads stay in the queue');
        Assert.areEqual(f.queue.Id, owners.get(leads[2].Id), 'Other leads stay in the queue');
    }

    @IsTest
    static void noActiveTeamsDoesNothing() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Active__c = false;
        update f.team;
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);

        Assert.areEqual(0, summary.processed, 'Inactive teams are not run');
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.queue.Id), 'Leads stay in the queue');
    }

    // ------------------------------------------------------------------ weighting

    @IsTest
    static void weightingGivesDoubleWeightTwiceAsMany() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.members[1].Weight__c = 2;
        update f.members[1];
        List<Lead> leads = DE_TestFactory.insertLeads(30, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', ids(leads)));
        Assert.areEqual(10, counts.get(f.users[0].Id), 'Weight 1 receives one per cycle');
        Assert.areEqual(20, counts.get(f.users[1].Id), 'Weight 2 receives two per cycle');
    }

    @IsTest
    static void weightingDisabledIgnoresWeights() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.members[1].Weight__c = 2;
        update f.members[1];
        f.distributor.Weighting_Enabled__c = false;
        update f.distributor;
        List<Lead> leads = DE_TestFactory.insertLeads(10, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Lead', ids(leads)));
        Assert.areEqual(5, counts.get(f.users[0].Id), 'Plain round robin when weighting is off');
        Assert.areEqual(5, counts.get(f.users[1].Id), 'Plain round robin when weighting is off');
    }

    // ------------------------------------------------------------------ load balancing

    @IsTest
    static void dailyLoadBalancingTopsUpTheLowestMember() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Load Balancing');
        f.team.Load_Balancing_Type__c = 'Daily';
        update f.team;
        priorAssignments(f.team, f.distributor, f.users[0].Id, 5);
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(4, countOwnedBy(owners, f.users[1].Id), 'The member with fewer assignments today receives all four');
        for (DE_Assignment_Log__c l : logsFor(ids(leads))) {
            Assert.areEqual('Load Balancing', l.Method__c, 'Method logged');
        }
    }

    @IsTest
    static void dailyLoadBalancingAlternatesOnceLevel() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Load Balancing');
        f.team.Load_Balancing_Type__c = 'Daily';
        update f.team;
        priorAssignments(f.team, f.distributor, f.users[0].Id, 2);
        List<Lead> leads = DE_TestFactory.insertLeads(6, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(2, countOwnedBy(owners, f.users[0].Id), 'Totals end level: 2 prior + 2 new');
        Assert.areEqual(4, countOwnedBy(owners, f.users[1].Id), 'Totals end level: 0 prior + 4 new');
    }

    @IsTest
    static void activeLoadBalancingCountsOwnedRecords() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Load Balancing');
        f.team.Load_Balancing_Type__c = 'Active';
        update f.team;
        DE_TestFactory.insertLeads(3, f.users[0].Id);
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'Member owning fewer records receives both');
    }

    // ------------------------------------------------------------------ caps

    @IsTest
    static void dailyTeamCapStopsAssignment() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new DE_Cap__c(Name = 'Daily', Team__c = f.team.Id, Period__c = 'Daily', Default_Cap__c = 1, Active__c = true);
        List<Lead> leads = DE_TestFactory.insertLeads(5, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(2, summary.assigned, 'One lead per member before the cap is reached');
        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(3, countOwnedBy(owners, f.queue.Id), 'Leads over the cap stay in the queue');
        Assert.areEqual(1, countOwnedBy(owners, f.users[0].Id), 'Cap of one');
        Assert.areEqual(1, countOwnedBy(owners, f.users[1].Id), 'Cap of one');
        List<DE_Record_Detail__c> waiting = [
            SELECT Failed_Attempts__c, Last_Error__c
            FROM DE_Record_Detail__c
            WHERE Record_Id__c IN :keys(ids(leads)) AND Failed_Attempts__c > 0
        ];
        Assert.areEqual(3, waiting.size(), 'Unassigned leads record a failed attempt');
        Assert.isTrue(waiting[0].Last_Error__c.contains('No eligible team member'), 'Reason recorded: ' + waiting[0].Last_Error__c);
    }

    @IsTest
    static void distributorCapLimitsAssignments() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new DE_Cap__c(Name = 'Distributor cap', Distributor__c = f.distributor.Id, Period__c = 'Daily', Default_Cap__c = 2, Active__c = true);
        List<Lead> leads = DE_TestFactory.insertLeads(6, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(4, summary.assigned, 'Two per member');
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.queue.Id), 'Remainder waits');
    }

    @IsTest
    static void cappedMemberIsSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new DE_Cap__c(Name = 'Daily', Team__c = f.team.Id, Period__c = 'Daily', Default_Cap__c = 2, Active__c = true);
        priorAssignments(f.team, f.distributor, f.users[0].Id, 2);
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'The capped member is skipped');
    }

    @IsTest
    static void tagCapOverridesDefaultCap() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new List<DE_Agent__c>{ agent(f.users[0].Id, true, 'Level:Senior'), agent(f.users[1].Id, true, 'Level:Junior') };
        insert new DE_Cap__c(Name = 'Tiered', Team__c = f.team.Id, Period__c = 'Daily', Default_Cap__c = 1, Tag_Caps__c = 'Level:Senior=3', Active__c = true);
        List<Lead> leads = DE_TestFactory.insertLeads(6, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(3, countOwnedBy(owners, f.users[0].Id), 'Senior tag cap of three');
        Assert.areEqual(1, countOwnedBy(owners, f.users[1].Id), 'Default cap of one');
        Assert.areEqual(2, countOwnedBy(owners, f.queue.Id), 'Remainder waits');
    }

    // ------------------------------------------------------------------ sticky

    @IsTest
    static void stickyAssignmentReturnsMatchingEmailToSameMember() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.distributor.Sticky_Enabled__c = true;
        f.distributor.Sticky_Field__c = 'Email';
        update f.distributor;
        Lead first = new Lead(LastName = 'First', Company = 'Initech', Email = 'peter@initech.example.com', OwnerId = f.queue.Id);
        insert first;
        DE_DistributionRunner.runStandard(null, null);
        Id firstOwner = [SELECT OwnerId FROM Lead WHERE Id = :first.Id].OwnerId;

        Lead repeat = new Lead(LastName = 'Repeat', Company = 'Initech', Email = 'PETER@initech.example.com', OwnerId = f.queue.Id);
        Lead other = new Lead(LastName = 'Other', Company = 'Hooli', Email = 'gavin@hooli.example.com', OwnerId = f.queue.Id);
        insert new List<Lead>{ repeat, other };
        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', new Set<Id>{ repeat.Id, other.Id });
        Assert.areEqual(firstOwner, owners.get(repeat.Id), 'Same email (case-insensitive) sticks to the same member');
        Assert.areNotEqual(firstOwner, owners.get(other.Id), 'Sticky hits do not use up the rotation turn of the other member');
        DE_Assignment_Log__c stickyLog = logsFor(new Set<Id>{ repeat.Id })[0];
        Assert.isTrue(stickyLog.Is_Sticky__c, 'Sticky flag on the log');
        Assert.areEqual('Sticky', stickyLog.Method__c, 'Sticky method');
        Assert.areEqual('D|' + f.distributor.Id + '|peter@initech.example.com', stickyLog.Sticky_Key__c, 'Distributor-level sticky key');
    }

    @IsTest
    static void stickyOnlyLeavesUnmatchedRecords() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.distributor.Sticky_Enabled__c = true;
        f.distributor.Sticky_Field__c = 'Email';
        f.distributor.Sticky_Only__c = true;
        update f.distributor;
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(0, summary.assigned, 'Sticky-only distributors do not round robin');
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.queue.Id), 'Leads wait in the queue');
    }

    // ------------------------------------------------------------------ availability

    @IsTest
    static void offlineMemberIsSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert agent(f.users[0].Id, false, null);
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(4, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'Only the online member receives leads');
    }

    @IsTest
    static void expiredOfflineTimerCountsAsOnline() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Agent__c a = agent(f.users[0].Id, false, null);
        a.Toggle_Until__c = System.now().addMinutes(-5);
        insert a;
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(f.users[0].Id, DE_TestFactory.owners('Lead', ids(leads)).get(leads[0].Id), 'An expired timer no longer blocks assignment');
    }

    @IsTest
    static void assignIfOfflineIncludesOfflineMembers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.distributor.Assign_If_Offline__c = true;
        update f.distributor;
        insert agent(f.users[0].Id, false, null);
        List<Lead> leads = DE_TestFactory.insertLeads(4, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(2, countOwnedBy(owners, f.users[0].Id), 'Offline member still receives leads');
        Assert.areEqual(2, countOwnedBy(owners, f.users[1].Id), 'Online member receives leads');
    }

    @IsTest
    static void outOfOfficeMemberIsSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new DE_Out_Of_Office__c(User__c = f.users[0].Id, Start__c = System.now().addHours(-1), End__c = System.now().addHours(2), Reason__c = 'Holiday');
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(3, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'Member out of office receives nothing');
    }

    @IsTest
    static void assignIfUnavailableIgnoresOutOfOffice() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.distributor.Assign_If_Unavailable__c = true;
        update f.distributor;
        insert new DE_Out_Of_Office__c(User__c = f.users[0].Id, Start__c = System.now().addHours(-1), End__c = System.now().addHours(2));
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(f.users[0].Id, DE_TestFactory.owners('Lead', ids(leads)).get(leads[0].Id), 'Assign If Unavailable overrides out of office');
    }

    @IsTest
    static void outsideDistributionHoursIsSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Shift__c closed = new DE_Shift__c(Name = 'Closed today', Timezone__c = 'GMT', Schedule__c = scheduleNotToday());
        insert closed;
        f.team.Team_Hours__c = closed.Id;
        update f.team;
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(0, summary.assigned, 'Members are outside their hours');
        Assert.areEqual(f.queue.Id, DE_TestFactory.owners('Lead', ids(leads)).get(leads[0].Id), 'Lead waits for working hours');
    }

    /** A schedule whose only working block is on a weekday three days away (GMT). */
    private static String scheduleNotToday() {
        Integer today = DE_ShiftCalendar.dayIndex(System.now().dateGmt());
        String day = DE_ShiftCalendar.DAYS[Math.mod(today + 3, 7)];
        return '{"' + day + '":["09:00-10:00"]}';
    }

    @IsTest
    static void teamHolidaySkipsTheTeam() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.team.Holiday_Region__c = 'UK';
        update f.team;
        insert new DE_Holiday__c(Name = 'Bank Holiday', Region__c = 'UK', All_Day__c = true, Start__c = System.now(), End__c = System.now(), Timezone__c = 'GMT');
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(0, summary.processed, 'The team is skipped on a holiday');
        Assert.isTrue(String.join(summary.messages, ' ').contains('Bank Holiday'), 'Holiday reported: ' + summary.messages);
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.queue.Id), 'Leads stay in the queue');
    }

    @IsTest
    static void holidayInAnotherRegionDoesNotApply() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Holiday_Region__c = 'UK';
        update f.team;
        insert new DE_Holiday__c(Name = 'Other', Region__c = 'US', All_Day__c = true, Start__c = System.now(), End__c = System.now(), Timezone__c = 'GMT');
        DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(1, summary.assigned, 'Holidays only apply to their region');
    }

    // ------------------------------------------------------------------ members

    @IsTest
    static void inactiveMemberAndInactiveUserAreSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(3, 'Round Robin');
        f.members[0].Active__c = false;
        update f.members[0];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = f.users[1].Id, IsActive = false);
        }
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(3, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[2].Id), 'Only the active member on an active user receives leads');
    }

    @IsTest
    static void selectedMembersOnlyReceiveFromTheirDistributor() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.distributor.Assign_To__c = 'Selected Members';
        f.distributor.Selected_Member_Ids__c = String.valueOf(f.users[1].Id);
        update f.distributor;
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(3, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'Only the selected member');
    }

    @IsTest
    static void tagMemberFilterRoutesToMatchingTag() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new List<DE_Agent__c>{ agent(f.users[0].Id, true, 'Language:French'), agent(f.users[1].Id, true, 'Language:German;Tier:Gold') };
        DE_Condition__c c = DE_TestFactory.condition('Member Filter', 1, 'Tag:Language', 'includes', 'French');
        c.Distributor__c = f.distributor.Id;
        insert c;
        List<Lead> leads = DE_TestFactory.insertLeads(3, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(3, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[0].Id), 'Only French speakers');
    }

    @IsTest
    static void dynamicTagMemberFilterUsesRecordValue() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert new List<DE_Agent__c>{ agent(f.users[0].Id, true, 'Language:French'), agent(f.users[1].Id, true, 'Language:German') };
        DE_Condition__c c = DE_TestFactory.condition('Member Filter', 1, 'DynamicTag:Language', 'includes', 'Description');
        c.Distributor__c = f.distributor.Id;
        insert c;
        List<Lead> leads = DE_TestFactory.leads(2, f.queue.Id);
        leads[0].Description = 'German';
        leads[1].Description = 'Spanish';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(f.users[1].Id, owners.get(leads[0].Id), 'German lead goes to the German speaker');
        Assert.areEqual(f.queue.Id, owners.get(leads[1].Id), 'Nobody speaks Spanish, so the lead waits');
    }

    // ------------------------------------------------------------------ filters and overflow

    @IsTest
    static void distributorFilterOnlyTakesMatchingRecords() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Condition__c c = DE_TestFactory.condition('Distributor Filter', 1, 'Company', 'equals', 'Acme');
        c.Distributor__c = f.distributor.Id;
        insert c;
        List<Lead> leads = DE_TestFactory.leads(2, f.queue.Id);
        leads[0].Company = 'Acme';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(1, summary.assigned, 'Only the matching lead');
        Assert.areEqual(f.users[0].Id, owners.get(leads[0].Id), 'Matching lead assigned');
        Assert.areEqual(f.queue.Id, owners.get(leads[1].Id), 'Non-matching lead untouched');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM DE_Record_Detail__c WHERE Record_Id__c = :String.valueOf(leads[1].Id) AND Failed_Attempts__c > 0],
            'Filtered-out records are not failures'
        );
    }

    @IsTest
    static void teamFilterWithCustomLogic() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.team.Filter_Logic__c = '1 OR 2';
        update f.team;
        List<DE_Condition__c> conds = new List<DE_Condition__c>{
            DE_TestFactory.condition('Team Filter', 1, 'Company', 'equals', 'Acme'),
            DE_TestFactory.condition('Team Filter', 2, 'Company', 'starts with', 'Glob')
        };
        for (DE_Condition__c c : conds) {
            c.Team__c = f.team.Id;
        }
        insert conds;
        List<Lead> leads = DE_TestFactory.leads(3, f.queue.Id);
        leads[0].Company = 'Acme';
        leads[1].Company = 'Globex';
        leads[2].Company = 'Initech';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(f.users[0].Id, owners.get(leads[0].Id), 'Condition 1 matches');
        Assert.areEqual(f.users[0].Id, owners.get(leads[1].Id), 'Condition 2 matches');
        Assert.areEqual(f.queue.Id, owners.get(leads[2].Id), 'Neither condition matches');
    }

    @IsTest
    static void overflowsToTheNextDistributor() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.distributor.Assign_To__c = 'Selected Members';
        f.distributor.Selected_Member_Ids__c = String.valueOf(f.users[0].Id);
        update f.distributor;
        insert agent(f.users[0].Id, false, null);
        DE_Distributor__c backup = DE_TestFactory.distributor(f.team.Id, 'Backup', f.queue.Id, 'Round Robin');
        backup.Order__c = 20;
        insert backup;
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(2, summary.assigned, 'The backup distributor assigns the overflow');
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.users[1].Id), 'Overflow to the online member');
        for (DE_Assignment_Log__c l : logsFor(ids(leads))) {
            Assert.areEqual(backup.Id, l.Distributor__c, 'Logged against the backup distributor');
        }
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM DE_Record_Detail__c WHERE Record_Id__c IN :keys(ids(leads)) AND Failed_Attempts__c > 0],
            'Overflowed records that were assigned are not failures'
        );
    }

    @IsTest
    static void overflowsToTheNextTeam() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        insert agent(f.users[0].Id, false, null);
        List<User> others = DE_TestFactory.users(1);
        DE_Team__c second = DE_TestFactory.team('Overflow Team', 'Lead');
        second.Execution_Order__c = 20;
        insert second;
        DE_TestFactory.members(second.Id, others);
        DE_TestFactory.insertDistributor(second.Id, 'Overflow', f.queue.Id, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), others[0].Id), 'Second team receives the overflow');
        for (DE_Assignment_Log__c l : logsFor(ids(leads))) {
            Assert.areEqual(second.Id, l.Team__c, 'Logged against the second team');
        }
    }

    // ------------------------------------------------------------------ failures

    @IsTest
    static void noEligibleMemberPutsRecordOnHold() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Settings__c s = DE_Settings__c.getOrgDefaults();
        s.Hold_After_Failures__c = 1;
        s.Hold_Minutes__c = 30;
        updateSettings(s);
        f.members[0].Active__c = false;
        update f.members[0];
        List<Lead> leads = DE_TestFactory.insertLeads(2, f.queue.Id);

        DE_DistributionRunner.Summary first = DE_DistributionRunner.runStandard(null, null);

        Assert.areEqual(0, first.assigned, 'Nobody to assign to');
        Assert.areEqual(2, first.onHold, 'Both records go on hold after one failure');
        Assert.areEqual(2, countOwnedBy(DE_TestFactory.owners('Lead', ids(leads)), f.queue.Id), 'Records stay in the queue');
        for (DE_Record_Detail__c d : [SELECT On_Hold_Until__c, Failed_Attempts__c, Last_Error__c FROM DE_Record_Detail__c WHERE Record_Id__c IN :keys(ids(leads))]) {
            Assert.isTrue(d.On_Hold_Until__c > System.now(), 'Hold until is in the future');
            Assert.areEqual(0, d.Failed_Attempts__c, 'Attempts reset after hold');
            Assert.isTrue(d.Last_Error__c.contains('No eligible team member'), 'Reason kept');
        }
        List<DE_Assignment_Log__c> holdLogs = logsFor(ids(leads));
        Assert.areEqual(2, holdLogs.size(), 'One hold log per record');
        Assert.areEqual('On Hold', holdLogs[0].Status__c, 'Hold status logged');

        f.members[0].Active__c = true;
        update f.members[0];
        Test.startTest();
        DE_DistributionRunner.Summary second = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();
        Assert.areEqual(0, second.processed, 'Records on hold are skipped until the hold expires');
    }

    @IsTest
    static void failedAttemptsAccumulateBelowThreshold() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.members[0].Active__c = false;
        update f.members[0];
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        DE_DistributionRunner.runStandard(null, null);
        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(0, summary.onHold, 'Default threshold of 10 not reached');
        DE_Record_Detail__c d = [SELECT Failed_Attempts__c, On_Hold_Until__c FROM DE_Record_Detail__c WHERE Record_Id__c = :String.valueOf(leads[0].Id)];
        Assert.areEqual(2, d.Failed_Attempts__c, 'One failed attempt per run');
        Assert.isNull(d.On_Hold_Until__c, 'Not on hold yet');
    }

    @IsTest
    static void classifierWaitingRecordsAreSkipped() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);
        insert new DE_Record_Detail__c(Record_Id__c = String.valueOf(leads[0].Id), Object_API_Name__c = 'Lead', Classifier_Status__c = 'Waiting');

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(0, summary.processed, 'Recently created records wait for the classifier');
    }

    // ------------------------------------------------------------------ field updates

    @IsTest
    static void fieldUpdatesAreAppliedOnAssignment() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        f.distributor.Field_Updates__c = 'Description=Routed by DE\nNot_A_Field__c=x';
        update f.distributor;
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(1, summary.assigned, 'An invalid update line does not block assignment');
        Assert.areEqual('Routed by DE', [SELECT Description FROM Lead WHERE Id = :leads[0].Id].Description, 'Valid line applied');
    }

    @IsTest
    static void fieldValueSourceMovesRecordToAfterValue() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(1);
        DE_Team__c team = DE_TestFactory.insertTeam('Field source', 'Lead');
        DE_TestFactory.members(team.Id, users);
        insert new DE_Distributor__c(
            Team__c = team.Id,
            Name = 'Ready leads',
            Active__c = true,
            Type__c = 'Standard',
            Method__c = 'Round Robin',
            Source_Type__c = 'Field Value',
            Source_Field__c = 'Title',
            Source_Ready_Value__c = 'Ready',
            Source_After_Value__c = 'Done',
            Send_Notification__c = false
        );
        List<Lead> leads = DE_TestFactory.leads(2, UserInfo.getUserId());
        leads[0].Title = 'Ready';
        leads[1].Title = 'Draft';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Lead> after = new Map<Id, Lead>([SELECT OwnerId, Title FROM Lead WHERE Id IN :leads]);
        Assert.areEqual(users[0].Id, after.get(leads[0].Id).OwnerId, 'Ready lead assigned');
        Assert.areEqual('Done', after.get(leads[0].Id).Title, 'Source field moved to the after value');
        Assert.areEqual(UserInfo.getUserId(), after.get(leads[1].Id).OwnerId, 'Lead not at the source is untouched');
    }

    // ------------------------------------------------------------------ owner methods

    @IsTest
    static void lookupOwnerFindsAccountOwnerByCompany() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Lookup Owner');
        f.distributor.Lookup_Object__c = 'Account';
        f.distributor.Lookup_Record_Field__c = 'Company';
        f.distributor.Lookup_Target_Field__c = 'Name';
        update f.distributor;
        insert new Account(Name = 'Globex', OwnerId = f.users[1].Id);
        List<Lead> leads = DE_TestFactory.leads(2, f.queue.Id);
        leads[0].Company = 'GLOBEX';
        leads[1].Company = 'Unknown Co';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Map<Id, Id> owners = DE_TestFactory.owners('Lead', ids(leads));
        Assert.areEqual(f.users[1].Id, owners.get(leads[0].Id), 'Lead goes to the matching account owner');
        Assert.areEqual(f.queue.Id, owners.get(leads[1].Id), 'No match: the lead overflows and waits');
        Assert.areEqual('Lookup Owner', logsFor(new Set<Id>{ leads[0].Id })[0].Method__c, 'Method logged');
    }

    @IsTest
    static void lookupOwnerIgnoresOwnersOutsideTheTeam() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Lookup Owner');
        f.distributor.Lookup_Object__c = 'Account';
        f.distributor.Lookup_Record_Field__c = 'Company';
        f.distributor.Lookup_Target_Field__c = 'Name';
        update f.distributor;
        insert new Account(Name = 'Globex', OwnerId = UserInfo.getUserId());
        List<Lead> leads = DE_TestFactory.leads(1, f.queue.Id);
        leads[0].Company = 'Globex';
        insert leads;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(f.queue.Id, DE_TestFactory.owners('Lead', ids(leads)).get(leads[0].Id), 'Only team members can receive lookup matches');
    }

    @IsTest
    static void dynamicOwnerUsesUserInField() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Dynamic Owner');
        f.distributor.Dynamic_Owner_Field__c = 'CreatedById';
        update f.distributor;
        List<Lead> leads = DE_TestFactory.insertLeads(1, f.queue.Id);

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(UserInfo.getUserId(), DE_TestFactory.owners('Lead', ids(leads)).get(leads[0].Id), 'Owner taken from the field');
        Assert.areEqual('Dynamic Owner', logsFor(ids(leads))[0].Method__c, 'Method logged');
    }

    // ------------------------------------------------------------------ cases

    @IsTest
    static void casesRouteFromACaseQueue() {
        DE_TestFactory.settings();
        Group q = DE_TestFactory.queue('DE Support', new List<String>{ 'Case' });
        List<User> users = DE_TestFactory.users(2);
        DE_Team__c team = DE_TestFactory.insertTeam('Support', 'Case');
        DE_TestFactory.members(team.Id, users);
        DE_TestFactory.insertDistributor(team.Id, 'Support inbox', q.Id, 'Round Robin');
        List<Case> cases = DE_TestFactory.insertCases(4, q.Id);

        Test.startTest();
        DE_DistributionRunner.Summary summary = DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(4, summary.assigned, 'All cases assigned');
        Map<Id, Integer> counts = DE_TestFactory.countByValue(DE_TestFactory.owners('Case', ids(cases)));
        Assert.areEqual(2, counts.get(users[0].Id), 'Even split');
        Assert.areEqual(2, counts.get(users[1].Id), 'Even split');
        Assert.isTrue([SELECT DE_Is_Distributed__c FROM Case WHERE Id = :cases[0].Id].DE_Is_Distributed__c, 'Case tracking field set');
    }

    @IsTest
    static void relatedOwnerRoutesCaseToAccountOwner() {
        DE_TestFactory.settings();
        Group q = DE_TestFactory.queue('DE Account Support', new List<String>{ 'Case' });
        List<User> users = DE_TestFactory.users(2);
        DE_Team__c team = DE_TestFactory.insertTeam('Account Support', 'Case');
        DE_TestFactory.members(team.Id, users);
        DE_Distributor__c d = DE_TestFactory.distributor(team.Id, 'Account owner', q.Id, 'Related Owner');
        d.Related_Field__c = 'AccountId';
        insert d;
        Account acct = new Account(Name = 'Umbrella', OwnerId = users[1].Id);
        insert acct;
        Case c = new Case(Subject = 'Help', Origin = 'Web', Status = 'New', OwnerId = q.Id, AccountId = acct.Id);
        insert c;

        Test.startTest();
        DE_DistributionRunner.runStandard(null, null);
        Test.stopTest();

        Assert.areEqual(users[1].Id, [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId, 'Case goes to the account owner');
        Assert.areEqual('Related Owner', logsFor(new Set<Id>{ c.Id })[0].Method__c, 'Method logged');
    }

    // ------------------------------------------------------------------ helpers under test

    @IsTest
    static void atSourceChecksQueueAndActiveStatus() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(f.team.Id, false);
        DE_Model.DistributorConfig dc = cfg.distributors[0];

        Assert.isTrue(DE_DistributionRunner.atSource(cfg, dc, new Lead(OwnerId = f.queue.Id)), 'Owned by the source queue');
        Assert.isFalse(DE_DistributionRunner.atSource(cfg, dc, new Lead(OwnerId = f.users[0].Id)), 'Owned by a user');

        cfg.team.Active_Status_Field__c = 'Description';
        cfg.activeStatusValues.add('open');
        Assert.isTrue(DE_DistributionRunner.atSource(cfg, dc, new Lead(OwnerId = f.queue.Id, Description = 'Open')), 'In active status');
        Assert.isFalse(DE_DistributionRunner.atSource(cfg, dc, new Lead(OwnerId = f.queue.Id, Description = 'Closed')), 'Not in active status');
    }
}
