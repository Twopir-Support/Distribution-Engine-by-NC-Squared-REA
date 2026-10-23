@IsTest
private class DE_AgentServiceTest {
    private static DE_Settings__c settings() {
        DE_Settings__c s = DE_TestFactory.settings();
        return s;
    }

    private static void save(DE_Settings__c s) {
        update s;
        DE_Settings.setForTransaction(null);
    }

    private static DE_Agent__c agentOf(Id userId) {
        return [SELECT Online__c, Toggle_Reason__c, Toggle_Until__c, Last_Status_Change__c FROM DE_Agent__c WHERE User__c = :userId];
    }

    private static String toggleError(Id userId, String reason, Integer timer) {
        try {
            DE_AgentService.setOnline(new Set<Id>{ userId }, false, reason, timer, 'User');
        } catch (DE_AgentService.ToggleException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void ensureCreatesOnlineAgentsOnce() {
        settings();
        List<User> users = DE_TestFactory.users(2);
        Set<Id> ids = new Map<Id, User>(users).keySet();

        Test.startTest();
        Map<Id, DE_Agent__c> first = DE_AgentService.ensure(ids);
        Map<Id, DE_Agent__c> second = DE_AgentService.ensure(ids);
        Test.stopTest();

        Assert.areEqual(2, first.size(), 'An agent row per user');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Agent__c WHERE User__c IN :ids], 'Rows are not duplicated');
        Assert.areEqual(first.get(users[0].Id).Id, second.get(users[0].Id).Id, 'Existing row returned');
        Assert.isTrue(agentOf(users[0].Id).Online__c, 'New agents start online');
    }

    @IsTest
    static void offlineWithReasonAndTimerIsAudited() {
        settings();
        User u = DE_TestFactory.users(1)[0];
        Datetime before = System.now();

        Test.startTest();
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, false, 'Lunch', 30, 'User');
        Test.stopTest();

        DE_Agent__c a = agentOf(u.Id);
        Assert.isFalse(a.Online__c, 'User is offline');
        Assert.areEqual('Lunch', a.Toggle_Reason__c, 'Reason stored');
        Assert.isTrue(a.Toggle_Until__c >= before.addMinutes(30).addSeconds(-1), 'Timer end stored');
        DE_Availability_Event__c ev = [SELECT Online__c, Reason__c, Source__c, Changed_By__c FROM DE_Availability_Event__c WHERE User__c = :u.Id];
        Assert.isFalse(ev.Online__c, 'History records offline');
        Assert.areEqual('Lunch', ev.Reason__c, 'History reason');
        Assert.areEqual('User', ev.Source__c, 'History source');
        Assert.areEqual(UserInfo.getUserId(), ev.Changed_By__c, 'History records who changed it');
    }

    @IsTest
    static void goingOnlineClearsReasonAndTimer() {
        settings();
        User u = DE_TestFactory.users(1)[0];
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, false, 'Lunch', 30, 'User');

        Test.startTest();
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, true, null, null, 'User');
        Test.stopTest();

        DE_Agent__c a = agentOf(u.Id);
        Assert.isTrue(a.Online__c, 'Back online');
        Assert.isNull(a.Toggle_Reason__c, 'Reason cleared');
        Assert.isNull(a.Toggle_Until__c, 'Timer cleared');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Availability_Event__c WHERE User__c = :u.Id], 'Both changes audited');
    }

    @IsTest
    static void selfServiceRulesAreEnforced() {
        DE_Settings__c s = settings();
        s.Require_Toggle_Reason__c = true;
        s.Toggle_Reasons__c = 'Meeting,Break';
        save(s);
        User u = DE_TestFactory.users(1)[0];

        Test.startTest();
        String noReason = toggleError(u.Id, null, null);
        String badReason = toggleError(u.Id, 'Nap', null);
        String goodReason = toggleError(u.Id, 'meeting', null);
        s.Require_Toggle_Reason__c = false;
        s.Timer_Toggles_Only__c = true;
        save(s);
        String noTimer = toggleError(u.Id, null, null);
        String zeroTimer = toggleError(u.Id, null, 0);
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, false, null, null, 'Manager');
        Test.stopTest();

        Assert.areEqual('Choose a reason for going offline.', noReason, 'Reason required');
        Assert.isTrue(badReason.contains('not one of the allowed reasons'), 'Unlisted reason rejected: ' + badReason);
        Assert.isNull(goodReason, 'Listed reason accepted case-insensitively');
        Assert.areEqual('Choose how long you will be offline.', noTimer, 'Timer required');
        Assert.areEqual('The timer must be at least one minute.', zeroTimer, 'Timer must be positive');
        Assert.isFalse(agentOf(u.Id).Online__c, 'Managers bypass self-service rules');
    }

    @IsTest
    static void expiredTimersBringUsersBackOnline() {
        settings();
        List<User> users = DE_TestFactory.users(2);
        DE_AgentService.setOnline(new Set<Id>{ users[0].Id }, false, 'Break', 15, 'User');
        DE_AgentService.setOnline(new Set<Id>{ users[1].Id }, false, 'Training', null, 'User');

        Test.startTest();
        Integer early = DE_AgentService.expireTimers(System.now());
        Integer later = DE_AgentService.expireTimers(System.now().addMinutes(16));
        Test.stopTest();

        Assert.areEqual(0, early, 'Timer not yet ended');
        Assert.areEqual(1, later, 'Only the timed toggle expires');
        Assert.isTrue(agentOf(users[0].Id).Online__c, 'Timed user back online');
        Assert.isFalse(agentOf(users[1].Id).Online__c, 'Untimed user stays offline');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Availability_Event__c WHERE User__c = :users[0].Id AND Source__c = 'Timer'], 'Expiry audited');
    }

    @IsTest
    static void startOfDayTurnsUsersOn() {
        DE_Settings__c s = settings();
        s.Toggle_At_Start_Of_Day__c = 'Always On';
        save(s);
        User u = DE_TestFactory.users(1)[0];
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, false, 'End of shift', null, 'User');
        DE_Agent__c a = [SELECT Id FROM DE_Agent__c WHERE User__c = :u.Id];
        update new DE_Agent__c(Id = a.Id, Last_Status_Change__c = System.now().addDays(-2));

        Test.startTest();
        Integer changed = DE_AgentService.applyDayBoundaries(System.now());
        Integer again = DE_AgentService.applyDayBoundaries(System.now());
        Test.stopTest();

        Assert.areEqual(1, changed, 'User switched on at the start of the day');
        Assert.areEqual(0, again, 'Only once per day');
        Assert.isTrue(agentOf(u.Id).Online__c, 'User is online');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Availability_Event__c WHERE User__c = :u.Id AND Source__c = 'Start of Day'], 'Audited');
    }

    @IsTest
    static void endOfDayTurnsUsersOffAfterLastShiftBlock() {
        DE_Settings__c s = settings();
        s.Toggle_At_End_Of_Day__c = 'Always Off';
        save(s);
        User u = DE_TestFactory.users(1)[0];
        // A shift that ends one minute after local midnight every day has always ended by "now".
        String block = '["00:00-00:01"]';
        DE_Shift__c shift = new DE_Shift__c(
            Name = 'Early',
            Timezone__c = 'Europe/London',
            Schedule__c = '{"MON":' + block + ',"TUE":' + block + ',"WED":' + block + ',"THU":' + block + ',"FRI":' + block + ',"SAT":' + block + ',"SUN":' + block + '}'
        );
        insert shift;
        DE_Team__c team = DE_TestFactory.insertTeam('Night', 'Lead');
        insert new DE_Team_Member__c(Team__c = team.Id, User__c = u.Id, Active__c = true, Member_Hours__c = shift.Id);
        DE_AgentService.ensure(new Set<Id>{ u.Id });
        DE_Agent__c a = [SELECT Id FROM DE_Agent__c WHERE User__c = :u.Id];
        update new DE_Agent__c(Id = a.Id, Online__c = true, Last_Status_Change__c = System.now().addDays(-2));

        Test.startTest();
        Integer changed = DE_AgentService.applyDayBoundaries(System.now());
        Test.stopTest();

        Assert.areEqual(1, changed, 'User switched off after their shift');
        Assert.isFalse(agentOf(u.Id).Online__c, 'User is offline');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Availability_Event__c WHERE User__c = :u.Id AND Source__c = 'End of Day'], 'Audited');
    }

    @IsTest
    static void noDayRulesChangeNothing() {
        settings();
        User u = DE_TestFactory.users(1)[0];
        DE_AgentService.setOnline(new Set<Id>{ u.Id }, false, null, null, 'User');

        Test.startTest();
        Integer changed = DE_AgentService.applyDayBoundaries(System.now().addDays(1));
        Test.stopTest();

        Assert.areEqual(0, changed, 'No Change rules leave availability alone');
        Assert.isFalse(agentOf(u.Id).Online__c, 'Still offline');
    }
}
