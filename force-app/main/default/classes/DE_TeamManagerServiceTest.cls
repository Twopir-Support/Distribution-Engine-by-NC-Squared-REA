@IsTest
private class DE_TeamManagerServiceTest {
    @IsTest
    static void setsReplacesAndQueriesManagers() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(3);
        DE_Team__c a = DE_TestFactory.insertTeam('A', 'Lead');
        DE_Team__c b = DE_TestFactory.insertTeam('B', 'Lead');

        DE_TeamManagerService.setManagers(a.Id, new List<Id>{ users[0].Id, users[1].Id, null });
        DE_TeamManagerService.setManagers(b.Id, new Set<Id>{ users[0].Id });

        Assert.isTrue(DE_TeamManagerService.isManager(a.Id, users[1].Id), 'User 2 manages A');
        Assert.isFalse(DE_TeamManagerService.isManager(b.Id, users[1].Id), 'User 2 does not manage B');
        Assert.areEqual(new Set<Id>{ a.Id, b.Id }, DE_TeamManagerService.teamIdsManagedBy(users[0].Id), 'User 1 manages both teams');
        Map<Id, Set<Id>> byTeam = DE_TeamManagerService.managersOf(new Set<Id>{ a.Id, b.Id });
        Assert.areEqual(2, byTeam.get(a.Id).size(), 'Null ids are ignored');

        DE_TeamManagerService.setManagers(a.Id, new List<Id>{ users[1].Id, users[2].Id });

        Map<Id, Set<Id>> after = DE_TeamManagerService.managersOf(new Set<Id>{ a.Id });
        Assert.areEqual(new Set<Id>{ users[1].Id, users[2].Id }, after.get(a.Id), 'Managers replaced');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Team_Manager__c WHERE Team__c = :a.Id AND User__c = :users[1].Id], 'Kept managers are not duplicated');
        Assert.areEqual(
            DE_TeamManagerService.uniqueKey(a.Id, users[2].Id),
            [SELECT Unique_Key__c FROM DE_Team_Manager__c WHERE Team__c = :a.Id AND User__c = :users[2].Id].Unique_Key__c,
            'Unique key is team + user'
        );
        Assert.isFalse(DE_TeamManagerService.isManager(a.Id, users[0].Id), 'Cache refreshed after a change');
    }

    @IsTest
    static void copiesManagersToAClone() {
        DE_TestFactory.settings();
        List<User> users = DE_TestFactory.users(1);
        DE_Team__c a = DE_TestFactory.insertTeam('A', 'Lead');
        DE_Team__c b = DE_TestFactory.insertTeam('B', 'Lead');
        DE_TeamManagerService.setManagers(a.Id, new List<Id>{ users[0].Id });

        DE_TeamManagerService.copyManagers(a.Id, b.Id);

        Assert.isTrue(DE_TeamManagerService.isManager(b.Id, users[0].Id), 'Clone has the same managers');
    }

    @IsTest
    static void emptyInputs() {
        Assert.isTrue(DE_TeamManagerService.teamIdsManagedBy(null).isEmpty(), 'No user, no teams');
        Assert.isFalse(DE_TeamManagerService.isManager(null, UserInfo.getUserId()), 'No team, not a manager');
        Assert.isTrue(DE_TeamManagerService.managersOf(null).isEmpty(), 'No teams, no managers');
    }

    @IsTest
    static void adminControllerSavesManagersAndValidatesUsers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();

        DE_AdminController.saveTeamManagers(f.team.Id, new List<Id>{ f.users[0].Id });
        DE_AdminController.TeamDetail d = DE_AdminController.getTeamDetail(f.team.Id);
        Assert.areEqual(new List<Id>{ f.users[0].Id }, d.managerIds, 'Team detail lists the managers');
        Assert.isTrue(d.ownerNames.containsKey(f.users[0].Id), 'Manager names are resolved for the UI');

        try {
            DE_AdminController.saveTeamManagers(f.team.Id, new List<Id>{ f.queue.Id });
            Assert.fail('Queues cannot manage teams');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('must be a User Id'), e.getMessage());
        }

        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        try {
            DE_AdminController.saveTeamManagers(f.team.Id, new List<Id>());
            Assert.fail('Only system managers change managers');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(1, [SELECT COUNT() FROM DE_Team_Manager__c WHERE Team__c = :f.team.Id], 'Managers unchanged');
        }
    }

    @IsTest
    static void cloningATeamCopiesItsManagers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();
        DE_TeamManagerService.setManagers(f.team.Id, new List<Id>{ f.users[0].Id });

        Id cloneId = DE_AdminController.cloneTeam(f.team.Id);

        Assert.isTrue(DE_TeamManagerService.isManager(cloneId, f.users[0].Id), 'The clone keeps the managers');
    }
}
