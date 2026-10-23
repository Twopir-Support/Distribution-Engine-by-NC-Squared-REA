@IsTest
private class DE_DynamicMembersTest {
    private static final String DEPARTMENT = 'DE Dynamic QA 7731';

    private class Setup {
        DE_Team__c team;
        List<User> users;
    }

    /** Team whose members are users in DEPARTMENT; users[0..1] match, users[2] is a manual member. */
    private static Setup setup(Boolean enabled) {
        DE_TestFactory.settings();
        Setup s = new Setup();
        s.users = DE_TestFactory.users(3);
        setDepartment(new List<User>{ s.users[0], s.users[1] }, DEPARTMENT);
        s.team = DE_TestFactory.team('Dynamic', 'Lead');
        s.team.Dynamic_Members_Enabled__c = enabled;
        insert s.team;
        DE_Condition__c c = DE_TestFactory.condition('Dynamic Membership', 1, 'Department', 'equals', DEPARTMENT);
        c.Team__c = s.team.Id;
        insert c;
        insert new DE_Team_Member__c(Team__c = s.team.Id, User__c = s.users[2].Id, Active__c = true, Dynamic__c = false);
        return s;
    }

    private static void setDepartment(List<User> users, String department) {
        for (User u : users) {
            u.Department = department;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update users;
        }
    }

    private static DE_Team_Member__c memberOf(Setup s, Id userId) {
        return [SELECT Active__c, Dynamic__c, Unique_Key__c FROM DE_Team_Member__c WHERE Team__c = :s.team.Id AND User__c = :userId];
    }

    @IsTest
    static void matchingUsersAreAdded() {
        Setup s = setup(true);

        Test.startTest();
        Map<String, Integer> result = DE_DynamicMembers.sync(s.team.Id);
        Test.stopTest();

        Assert.areEqual(2, result.get('added'), 'Both matching users added');
        Assert.areEqual(0, result.get('deactivated'), 'Nobody removed');
        DE_Team_Member__c added = memberOf(s, s.users[0].Id);
        Assert.isTrue(added.Active__c, 'Added member is active');
        Assert.isTrue(added.Dynamic__c, 'Added member is marked dynamic');
        Assert.areEqual(s.team.Id + '|' + s.users[0].Id, added.Unique_Key__c, 'Unique key prevents duplicates');
        Assert.isTrue(memberOf(s, s.users[2].Id).Active__c, 'Manual member never changed');
        Assert.isFalse(memberOf(s, s.users[2].Id).Dynamic__c, 'Manual member stays manual');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Agent__c WHERE User__c IN :new List<Id>{ s.users[0].Id, s.users[1].Id }], 'Availability rows created');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Dynamic Members'], 'Sync logged');
    }

    @IsTest
    static void usersWhoStopMatchingAreDeactivatedThenReactivated() {
        Setup s = setup(true);
        DE_DynamicMembers.sync(s.team.Id);
        setDepartment(new List<User>{ s.users[1] }, 'Somewhere else');

        Test.startTest();
        Map<String, Integer> removed = DE_DynamicMembers.sync(s.team.Id);
        Boolean inactiveAfterRemove = !memberOf(s, s.users[1].Id).Active__c;
        setDepartment(new List<User>{ s.users[1] }, DEPARTMENT);
        Map<String, Integer> back = DE_DynamicMembers.sync(s.team.Id);
        Test.stopTest();

        Assert.areEqual(1, removed.get('deactivated'), 'Non-matching dynamic member deactivated');
        Assert.isTrue(inactiveAfterRemove, 'Member row deactivated, not deleted');
        Assert.areEqual(1, back.get('reactivated'), 'Matching again reactivates the member');
        Assert.areEqual(0, back.get('added'), 'No duplicate member created');
        Assert.isTrue(memberOf(s, s.users[1].Id).Active__c, 'Member active again');
    }

    @IsTest
    static void disabledTeamIsUnchanged() {
        Setup s = setup(false);

        Test.startTest();
        Map<String, Integer> result = DE_DynamicMembers.sync(s.team.Id);
        Integer all = DE_DynamicMembers.syncAll();
        Test.stopTest();

        Assert.areEqual(0, result.get('added') + result.get('deactivated') + result.get('reactivated'), 'Disabled team not synced');
        Assert.areEqual(0, all, 'syncAll skips disabled teams');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :s.team.Id], 'Only the manual member');
    }

    @IsTest
    static void syncAllCountsChanges() {
        Setup s = setup(true);

        Test.startTest();
        Integer changes = DE_DynamicMembers.syncAll();
        Test.stopTest();

        Assert.areEqual(2, changes, 'Two members added across enabled teams');
        Assert.areEqual(3, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :s.team.Id], 'Two dynamic plus one manual member');
    }
}
