@IsTest
private class DE_ObjectSyncServiceTest {
    private class Setup {
        User owner;
        Account account;
        Contact buyer;
        Contact other;
        DE_Model.TeamConfig cfg;
    }

    /** Account team, an Account -> Contact sync action filtered to Title = Buyer, two contacts. */
    private static Setup setup(Boolean active) {
        DE_TestFactory.settings();
        Setup s = new Setup();
        s.owner = DE_TestFactory.users(1)[0];
        DE_Team__c team = DE_TestFactory.team('Accounts', 'Account');
        team.Object_Sync_Enabled__c = true;
        insert team;
        DE_Object_Sync__c action = new DE_Object_Sync__c(
            Name = 'Contacts follow account',
            Active__c = active,
            Parent_Object__c = 'Account',
            Child_Object__c = 'Contact',
            Lookup_Field__c = 'AccountId'
        );
        insert action;
        DE_Condition__c c = DE_TestFactory.condition('Sync Filter', 1, 'Title', 'equals', 'Buyer');
        c.Object_Sync__c = action.Id;
        insert c;
        s.account = new Account(Name = 'Acme');
        insert s.account;
        s.buyer = new Contact(LastName = 'Buyer', Title = 'Buyer', AccountId = s.account.Id);
        s.other = new Contact(LastName = 'Other', Title = 'Engineer', AccountId = s.account.Id);
        insert new List<Contact>{ s.buyer, s.other };
        s.cfg = DE_ConfigRepository.team(team.Id, true);
        return s;
    }

    private static DE_Model.Decision decision(SObject rec, Id assigneeId, String status) {
        DE_Model.Decision d = new DE_Model.Decision(rec);
        d.assigneeId = assigneeId;
        d.status = status;
        return d;
    }

    @IsTest
    static void matchingChildrenTakeTheNewOwner() {
        Setup s = setup(true);

        Test.startTest();
        Integer changed = DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });
        Test.stopTest();

        Assert.areEqual(1, changed, 'One contact matched the filter');
        Assert.areEqual(s.owner.Id, [SELECT OwnerId FROM Contact WHERE Id = :s.buyer.Id].OwnerId, 'Buyer contact follows the account owner');
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Contact WHERE Id = :s.other.Id].OwnerId, 'Filtered-out contact unchanged');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Object Sync' AND Status__c = 'Success'], 'Sync logged');
    }

    @IsTest
    static void queueAssignmentsUnassignedDecisionsAndInactiveActionsAreSkipped() {
        Setup s = setup(true);
        Group q = DE_TestFactory.queue('DE Accounts', new List<String>{ 'Lead' });

        Test.startTest();
        Integer toQueue = DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, q.Id, 'Assigned') });
        Integer unassigned = DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Unassigned') });
        update new DE_Object_Sync__c(Id = [SELECT Id FROM DE_Object_Sync__c LIMIT 1].Id, Active__c = false);
        Integer inactive = DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });
        Test.stopTest();

        Assert.areEqual(0, toQueue, 'Only user owners are synced');
        Assert.areEqual(0, unassigned, 'Unassigned decisions are ignored');
        Assert.areEqual(0, inactive, 'Inactive sync actions do not run');
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Contact WHERE Id = :s.buyer.Id].OwnerId, 'Contact unchanged');
    }

    @IsTest
    static void childAlreadyOwnedIsNotUpdated() {
        Setup s = setup(true);
        update new Contact(Id = s.buyer.Id, OwnerId = s.owner.Id);

        Test.startTest();
        Integer changed = DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });
        Test.stopTest();

        Assert.areEqual(0, changed, 'Nothing to change when the owner already matches');
    }
}
