/**
 * Unit tests for the routing building blocks: rotation, weighting, load balancing, sticky keys,
 * availability reasons and the team lock.
 */
@IsTest
private class DE_RoutingUnitTest {
    private static DE_Model.TeamConfig config(DE_TestFactory.Fixture f) {
        return DE_ConfigRepository.team(f.team.Id, false);
    }

    @IsTest
    static void rotationOrdersByLastSequenceAndPersists() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(3, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        DE_RotationService rotation = new DE_RotationService(cfg);
        String scope = rotation.roundRobinScope(cfg.distributors[0]);
        Assert.areEqual('T|' + f.team.Id, scope, 'Team-level round robin by default');

        DE_Model.Member first = rotation.pickRoundRobin(cfg.members, scope);
        rotation.recordHit(first, scope, true);
        DE_Model.Member second = rotation.pickRoundRobin(cfg.members, scope);
        Assert.areNotEqual(first.memberId, second.memberId, 'The member just served moves to the back');
        rotation.recordHit(second, scope, false);
        Assert.areEqual(second.memberId, rotation.pickRoundRobin(cfg.members, scope).memberId, 'A hit that does not count keeps the turn');
        Assert.areEqual(2, rotation.assignmentCount(), 'Both assignments counted');

        rotation.save();
        DE_Team__c team = [SELECT Rotation_Sequence__c, Total_Assignments__c FROM DE_Team__c WHERE Id = :f.team.Id];
        Assert.areEqual(1, team.Rotation_Sequence__c, 'One counted hit');
        Assert.areEqual(2, team.Total_Assignments__c, 'Two assignments');

        DE_RotationService reloaded = new DE_RotationService(config(f));
        Assert.areEqual(1, reloaded.sequence(scope, first.memberId), 'Sequence persisted');
        Assert.areEqual(0, reloaded.sequence(scope, second.memberId), 'Uncounted hit not persisted as a sequence');
    }

    @IsTest
    static void distributorLevelScopeAndMoveToFront() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.team.Round_Robin_Level__c = 'Distributor';
        update f.team;
        DE_Model.TeamConfig cfg = config(f);
        DE_RotationService rotation = new DE_RotationService(cfg);
        String scope = rotation.roundRobinScope(cfg.distributors[0]);
        Assert.areEqual('D|' + f.distributor.Id, scope, 'Distributor-level scope');

        DE_Model.Member a = rotation.pickRoundRobin(cfg.members, scope);
        rotation.recordHit(a, scope, true);
        rotation.moveToFront(a.memberId, scope);
        Assert.areEqual(a.memberId, rotation.pickRoundRobin(cfg.members, scope).memberId, 'Moved to the front of the line');
    }

    @IsTest
    static void replacementCreditKeepsThePlaceOnce() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        DE_RotationService rotation = new DE_RotationService(cfg);
        String scope = rotation.roundRobinScope(cfg.distributors[0]);
        DE_Model.Member a = rotation.pickRoundRobin(cfg.members, scope);
        rotation.addReplacementCredit(a.memberId, scope);

        rotation.recordHit(a, scope, true);
        Assert.areEqual(a.memberId, rotation.pickRoundRobin(cfg.members, scope).memberId, 'Replacement does not cost a turn');
        rotation.recordHit(a, scope, true);
        Assert.areNotEqual(a.memberId, rotation.pickRoundRobin(cfg.members, scope).memberId, 'The next hit counts again');
    }

    @IsTest
    static void weightedPickFollowsCredits() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        f.members[0].Weight__c = 0.5;
        update f.members[0];
        DE_Model.TeamConfig cfg = config(f);
        DE_RotationService rotation = new DE_RotationService(cfg);
        DE_Model.DistributorConfig dc = cfg.distributors[0];
        String scope = rotation.roundRobinScope(dc);
        Assert.isTrue(rotation.weightsDiffer(cfg.members), 'Weights differ');

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Integer i = 0; i < 6; i++) {
            DE_Model.Member m = rotation.pickWeighted(cfg.members, dc, scope);
            rotation.recordHit(m, scope, true);
            counts.put(m.memberId, (counts.containsKey(m.memberId) ? counts.get(m.memberId) : 0) + 1);
        }
        Assert.areEqual(2, counts.get(f.users[0].Id), 'Weight 0.5 gets one record every other cycle');
        Assert.areEqual(4, counts.get(f.users[1].Id), 'Weight 1 gets one record every cycle');
    }

    @IsTest
    static void memberWeightClampsAndUsesTags() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        DE_Team_Member__c m = new DE_Team_Member__c(Weight__c = 9);
        Assert.areEqual(4, DE_ConfigRepository.memberWeight(cfg, m, new Set<String>()), 'Clamped to 4');
        m.Weight__c = null;
        Assert.areEqual(1, DE_ConfigRepository.memberWeight(cfg, m, new Set<String>()), 'Defaults to 1');

        cfg.team.Weighting_Mode__c = 'Tag';
        cfg.team.Default_Tag_Weight__c = 0.5;
        cfg.tagWeights = DE_ConfigRepository.parseWeights('Tier:Gold=3\nTier:Silver=2\nbad=x');
        Assert.areEqual(3, DE_ConfigRepository.memberWeight(cfg, m, new Set<String>{ 'tier:gold', 'tier:silver' }), 'Highest tag weight');
        Assert.areEqual(0.5, DE_ConfigRepository.memberWeight(cfg, m, new Set<String>{ 'tier:bronze' }), 'Default tag weight');
        Assert.areEqual(2, cfg.tagWeights.size(), 'Invalid weight lines are ignored');
    }

    @IsTest
    static void loadBalancerPicksLowestScore() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Load Balancing');
        f.team.Load_Balancing_Type__c = 'Daily';
        update f.team;
        insert new DE_Assignment_Log__c(
            Team__c = f.team.Id,
            Distributor__c = f.distributor.Id,
            Assignee_Id__c = String.valueOf(f.users[0].Id),
            Status__c = 'Assigned',
            Method__c = 'Round Robin',
            Assigned_At__c = System.now(),
            Record_Id__c = 'x'
        );
        DE_Model.TeamConfig cfg = config(f);
        DE_Model.DistributorConfig dc = cfg.distributors[0];
        DE_RotationService rotation = new DE_RotationService(cfg);
        DE_LoadBalancer lb = new DE_LoadBalancer(cfg, System.now());

        Assert.areEqual(1, lb.score(cfg.member(f.users[0].Id), dc), 'Score from today\'s logs');
        DE_Model.Member picked = lb.pick(cfg.members, dc, rotation, rotation.roundRobinScope(dc));
        Assert.areEqual(f.users[1].Id, picked.memberId, 'Lowest score wins');
        lb.recordAssignment(picked, dc, null);
        lb.recordAssignment(picked, dc, null);
        Assert.areEqual(f.users[0].Id, lb.pick(cfg.members, dc, rotation, rotation.roundRobinScope(dc)).memberId, 'Scores update in memory');
        Assert.isNull(lb.pick(new List<DE_Model.Member>(), dc, rotation, 'T'), 'No eligible members');
    }

    @IsTest
    static void stickyKeysAndLookup() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        DE_Model.DistributorConfig dc = cfg.distributors[0];
        Lead rec = new Lead(Email = ' Ann@Example.com ');

        Assert.isNull(DE_StickyService.key(cfg, dc, rec), 'Sticky disabled');
        dc.dist.Sticky_Enabled__c = true;
        dc.dist.Sticky_Field__c = 'Email';
        Assert.areEqual('D|' + f.distributor.Id + '|ann@example.com', DE_StickyService.key(cfg, dc, rec), 'Distributor scope, trimmed, lower case');
        dc.dist.Sticky_Level__c = 'Team';
        Assert.areEqual('T|' + f.team.Id + '|ann@example.com', DE_StickyService.key(cfg, dc, rec), 'Team scope');
        dc.dist.Sticky_Level__c = 'Global';
        Assert.areEqual('G|ann@example.com', DE_StickyService.key(cfg, dc, rec), 'Global scope');
        Assert.isNull(DE_StickyService.key(cfg, dc, new Lead()), 'Blank value has no key');

        insert new List<DE_Assignment_Log__c>{
            new DE_Assignment_Log__c(
                Sticky_Key__c = 'G|ann@example.com',
                Assignee_Id__c = String.valueOf(f.users[0].Id),
                Status__c = 'Assigned',
                Assigned_At__c = System.now()
            ),
            new DE_Assignment_Log__c(
                Sticky_Key__c = 'G|old@example.com',
                Assignee_Id__c = String.valueOf(f.users[0].Id),
                Status__c = 'Assigned',
                Assigned_At__c = System.now().addDays(-100)
            ),
            new DE_Assignment_Log__c(
                Sticky_Key__c = 'G|err@example.com',
                Assignee_Id__c = String.valueOf(f.users[0].Id),
                Status__c = 'Error',
                Assigned_At__c = System.now()
            )
        };
        Map<String, Id> found = DE_StickyService.lookup(new Set<String>{ 'G|ann@example.com', 'G|old@example.com', 'G|err@example.com' }, 90, System.now());
        Assert.areEqual(f.users[0].Id, found.get('G|ann@example.com'), 'Recent match');
        Assert.isFalse(found.containsKey('G|old@example.com'), 'Outside the sticky period');
        Assert.isFalse(found.containsKey('G|err@example.com'), 'Errors are not sticky');
        Assert.isTrue(DE_StickyService.lookup(new Set<String>(), 90, System.now()).isEmpty(), 'No keys');
    }

    @IsTest
    static void stickyRemoveAlwaysClearsEveryLog() {
        List<DE_Assignment_Log__c> logs = new List<DE_Assignment_Log__c>{
            new DE_Assignment_Log__c(Sticky_Key__c = 'G|k', Status__c = 'Assigned'),
            new DE_Assignment_Log__c(Sticky_Key__c = 'G|k', Status__c = 'Assigned')
        };
        insert logs;
        DE_Assignment_Log__c current = [SELECT Id, Sticky_Key__c FROM DE_Assignment_Log__c WHERE Id = :logs[0].Id];

        DE_StickyService.remove(new List<DE_Assignment_Log__c>{ current }, 'Never');
        Assert.areEqual('G|k', current.Sticky_Key__c, 'Never keeps the key');
        DE_StickyService.remove(new List<DE_Assignment_Log__c>{ current }, 'Always');
        Assert.isNull(current.Sticky_Key__c, 'Key cleared in memory');
        Assert.isNull([SELECT Sticky_Key__c FROM DE_Assignment_Log__c WHERE Id = :logs[1].Id].Sticky_Key__c, 'Other logs with the key cleared');
    }

    @IsTest
    static void availabilityReasons() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        insert new DE_Agent__c(
            Name = 'A',
            User__c = f.users[0].Id,
            Unique_User__c = String.valueOf(f.users[0].Id),
            Online__c = false,
            Toggle_Reason__c = 'Lunch'
        );
        DE_Model.TeamConfig cfg = config(f);
        DE_Model.Member m = cfg.members[0];
        DE_AvailabilityService svc = new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ cfg }, System.now());

        Assert.areEqual('Toggled offline (Lunch)', svc.unavailableReason(m, false, false, false), 'Offline with reason');
        Assert.isNull(svc.unavailableReason(m, false, true, false), 'Assign if offline');
        Assert.isNull(svc.unavailableReason(m, true, false, false), 'Assign if unavailable');
        Assert.isFalse(svc.isOutOfOffice(m.memberId), 'Not out of office');

        insert new DE_Out_Of_Office__c(
            User__c = f.users[0].Id,
            Start__c = System.now().addHours(-1),
            End__c = System.now().addHours(1),
            Reason__c = 'Training'
        );
        DE_AvailabilityService withOoo = new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ cfg }, System.now());
        Assert.areEqual('Out of office (Training)', withOoo.unavailableReason(m, false, true, false), 'Out of office comes before the toggle');
        DE_AvailabilityService later = new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ cfg }, System.now().addHours(3));
        Assert.isFalse(later.isOutOfOffice(m.memberId), 'Out of office has ended');
    }

    @IsTest
    static void holidayWindowCoversWholeLocalDays() {
        DE_Holiday__c h = new DE_Holiday__c(
            Name = 'New Year',
            All_Day__c = true,
            Start__c = Datetime.newInstanceGmt(2030, 1, 1, 12, 0, 0),
            End__c = Datetime.newInstanceGmt(2030, 1, 1, 12, 0, 0),
            Timezone__c = 'GMT'
        );
        List<Datetime> w = DE_AvailabilityService.holidayWindow(h, 'GMT');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 1, 0, 0, 0), w[0], 'Starts at local midnight');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 2, 0, 0, 0), w[1], 'Ends at the next local midnight');

        h.All_Day__c = false;
        h.End__c = Datetime.newInstanceGmt(2030, 1, 1, 14, 0, 0);
        w = DE_AvailabilityService.holidayWindow(h, 'GMT');
        Assert.areEqual(h.Start__c, w[0], 'Timed holiday start');
        Assert.areEqual(h.End__c, w[1], 'Timed holiday end');
    }

    @IsTest
    static void teamLockRefreshesCounters() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        update new DE_Team__c(Id = f.team.Id, Rotation_Sequence__c = 42, Total_Assignments__c = 7);

        DE_TeamLock.lock(cfg);
        Assert.areEqual(42, cfg.team.Rotation_Sequence__c, 'Sequence refreshed from the locked row');
        Assert.areEqual(7, cfg.team.Total_Assignments__c, 'Total refreshed from the locked row');

        delete [SELECT Id FROM DE_Team__c WHERE Id = :f.team.Id];
        try {
            DE_TeamLock.lock(cfg);
            Assert.fail('Locking a deleted team should fail');
        } catch (DE_TeamLock.LockException e) {
            Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
        }
    }

    @IsTest
    static void capWindowsAndTagCaps() {
        Datetime now = Datetime.newInstanceGmt(2030, 1, 9, 10, 45, 0); // a Wednesday
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 9, 10, 0, 0), DE_CapService.windowStart('Hourly', null, now, 'GMT'), 'Hourly');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 9, 10, 30, 0), DE_CapService.windowStart('Half-hourly', null, now, 'GMT'), 'Half-hourly');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 9, 0, 0, 0), DE_CapService.windowStart('Daily', null, now, 'GMT'), 'Daily');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 7, 0, 0, 0), DE_CapService.windowStart('Weekly', null, now, 'GMT'), 'Weekly from Monday');
        Assert.areEqual(Datetime.newInstanceGmt(2030, 1, 1, 0, 0, 0), DE_CapService.windowStart('Monthly', null, now, 'GMT'), 'Monthly');
        Assert.areEqual(now.addMinutes(-15), DE_CapService.windowStart('Custom Minutes', 15, now, 'GMT'), 'Rolling minutes');
        Assert.areEqual(now.addHours(-2), DE_CapService.windowStart('Custom Hours', 2, now, 'GMT'), 'Rolling hours');
        Assert.areEqual(now.addDays(-3), DE_CapService.windowStart('Custom Days', 3, now, 'GMT'), 'Rolling days');
        Assert.isNull(DE_CapService.windowStart('Active', null, now, 'GMT'), 'Active has no window');

        DE_Model.Member m = new DE_Model.Member();
        m.tags = new Set<String>{ 'tier:gold' };
        DE_Cap__c cap = new DE_Cap__c(Default_Cap__c = 5, Tag_Caps__c = 'Tier:Gold=10\nTier:Silver=7');
        Assert.areEqual(10, DE_CapService.capFor(cap, m), 'Tag cap');
        m.tags = new Set<String>();
        Assert.areEqual(5, DE_CapService.capFor(cap, m), 'Default cap');
        cap.Default_Cap__c = null;
        Assert.isNull(DE_CapService.capFor(cap, m), 'Unlimited');
    }

    @IsTest
    static void memberFilterOperators() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Model.TeamConfig cfg = config(f);
        DE_Model.DistributorConfig dc = cfg.distributors[0];
        DE_Model.Member m = cfg.members[0];
        m.tags = DE_Model.parseTags('Language:French;Language:German');
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(new List<DE_Model.TeamConfig>{ cfg }, System.now());
        Lead rec = new Lead(Description = 'German');

        dc.memberFilters = new List<DE_Condition__c>{ DE_TestFactory.condition('Member Filter', 1, 'Tag:Language', 'includes all', 'French;German') };
        Assert.isTrue(DE_DistributionCore.memberFiltersPass(m, dc, rec, ctx), 'Includes all');
        dc.memberFilters[0].Value__c = 'French;Spanish';
        Assert.isFalse(DE_DistributionCore.memberFiltersPass(m, dc, rec, ctx), 'Missing one tag');
        dc.memberFilters[0].Operator__c = 'does not include';
        dc.memberFilters[0].Value__c = 'Spanish';
        Assert.isTrue(DE_DistributionCore.memberFiltersPass(m, dc, rec, ctx), 'Does not include');
        dc.memberFilters = new List<DE_Condition__c>{ DE_TestFactory.condition('Member Filter', 1, 'Territory', 'includes', null) };
        Assert.isFalse(DE_DistributionCore.memberFiltersPass(m, dc, rec, ctx), 'No territory on the record');
    }
}
