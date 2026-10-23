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

    @IsTest
    static void eachSyncedRecordGetsAnObjectSyncLog() {
        Setup s = setup(true);

        Test.startTest();
        DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });
        DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });
        Test.stopTest();

        List<DE_Object_Sync_Log__c> logs = [
            SELECT Record_Id__c, Record_Name__c, Object_API_Name__c, Team__c, Assignee_Id__c, Status__c, Actions_Performed__c, Synced_Records__c, Errors__c
            FROM DE_Object_Sync_Log__c
            ORDER BY Name
        ];
        Assert.areEqual(2, logs.size(), 'One log per synced parent per run');
        Assert.areEqual('Success', logs[0].Status__c, 'First run changed the buyer contact');
        Assert.areEqual('Contact=1', logs[0].Actions_Performed__c, 'Actions performed per related object');
        Assert.areEqual(1, logs[0].Synced_Records__c, 'Records synced');
        Assert.areEqual(0, logs[0].Errors__c, 'No errors');
        Assert.areEqual(s.account.Id, logs[0].Record_Id__c, 'Parent record');
        Assert.areEqual('Acme', logs[0].Record_Name__c, 'Parent name');
        Assert.areEqual(s.cfg.team.Id, logs[0].Team__c, 'Team');
        Assert.areEqual(s.owner.Id, logs[0].Assignee_Id__c, 'Assignee');
        Assert.areEqual('Skipped', logs[1].Status__c, 'Second run had nothing left to change');
    }

    @IsTest
    static void misconfiguredActionsAreLoggedAsErrors() {
        Setup s = setup(true);
        DE_Object_Sync__c broken = new DE_Object_Sync__c(
            Name = 'Broken',
            Active__c = true,
            Parent_Object__c = 'Account',
            Child_Object__c = 'Contact',
            Lookup_Field__c = 'Not_A_Lookup__c',
            Order__c = 1
        );
        insert broken;

        DE_ObjectSyncService.sync(s.cfg, new List<DE_Model.Decision>{ decision(s.account, s.owner.Id, 'Assigned') });

        DE_Object_Sync_Log__c log = [SELECT Status__c, Errors__c, Error_Message__c, Synced_Records__c FROM DE_Object_Sync_Log__c];
        Assert.areEqual('Error', log.Status__c, 'The broken action is reported');
        Assert.isTrue(log.Error_Message__c.startsWith('Broken:'), log.Error_Message__c);
        Assert.areEqual(1, log.Synced_Records__c, 'The valid action still ran');
    }
}
