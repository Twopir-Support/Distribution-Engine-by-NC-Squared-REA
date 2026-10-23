@IsTest
private class DE_ClassifierServiceTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static DE_Territory__c ukTerritory() {
        return new DE_Territory__c(Name = 'UK', Object_API_Name__c = 'Lead', Status__c = 'Active', Priority__c = 1, Countries__c = 'United Kingdom');
    }

    private static List<Lead> ukLeads(Integer count) {
        List<Lead> out = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            out.add(new Lead(LastName = 'Lead ' + i, Company = 'Company ' + i, Country = 'UK'));
        }
        return out;
    }

    private static Map<Id, DE_Record_Detail__c> details(List<SObject> records) {
        return DE_RecordDetails.load(new Map<Id, SObject>(records).keySet(), null);
    }

    @IsTest
    static void insertWithoutConfigurationDoesNothing() {
        DE_TestFactory.settings();
        List<Lead> leads = ukLeads(3);

        Test.startTest();
        insert leads;
        Test.stopTest();

        Assert.isFalse(DE_ClassifierService.hasConfiguration('Lead'), 'No classifier configuration');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Record_Detail__c], 'Nothing to classify or distribute');
    }

    @IsTest
    static void insertMarksRecordsWaitingThenClassifiesAsynchronously() {
        DE_TestFactory.settings();
        insert ukTerritory();
        List<Lead> leads = ukLeads(3);

        Test.startTest();
        insert leads;
        Map<Id, DE_Record_Detail__c> waiting = details(leads);
        Assert.areEqual(3, waiting.size(), 'Details created on insert');
        for (DE_Record_Detail__c d : waiting.values()) {
            Assert.areEqual('Waiting', d.Classifier_Status__c, 'Waiting until the job runs');
            Assert.isTrue(DE_RecordDetails.isWaiting(d, System.now(), System.now()), 'Distributors wait for new records');
        }
        Test.stopTest();

        for (DE_Record_Detail__c d : details(leads).values()) {
            Assert.areEqual('Done', d.Classifier_Status__c, 'Classified by the queueable');
            Assert.areEqual('UK', d.Territory_Name__c, 'Territory applied');
            Assert.isFalse(DE_RecordDetails.isWaiting(d, System.now(), System.now()), 'No longer waiting');
        }
    }

    @IsTest
    static void classifierSettingsCanSwitchClassificationOff() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Classifier_Objects__c = 'Case';
        update s;
        DE_Settings.setForTransaction(null);
        insert ukTerritory();
        List<Lead> leads = ukLeads(2);

        Test.startTest();
        insert leads;
        Test.stopTest();

        Assert.isTrue(DE_ClassifierService.hasConfiguration('Lead'), 'Configuration exists');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Record_Detail__c], 'Lead is not a classifier object');
    }

    @IsTest
    static void typesParameterLimitsTheClassification() {
        DE_TestFactory.settings();
        insert ukTerritory();
        DE_Stamp_Group__c g = new DE_Stamp_Group__c(Name = 'Segment', Object_API_Name__c = 'Lead', Group_Type__c = 'Single', Active__c = true);
        insert g;
        insert new DE_Stamp__c(Stamp_Group__c = g.Id, Name = 'All', Order__c = 1);
        List<Lead> leads = ukLeads(1);
        insertQuietly(leads);
        Id leadId = leads[0].Id;

        Integer count = DE_ClassifierService.classify('Lead', new Set<Id>{ leadId }, new Set<String>{ 'Stamps' });
        DE_Record_Detail__c d = details(leads).get(leadId);
        Assert.areEqual(1, count, 'One record classified');
        Assert.areEqual('Segment:All', d.Stamps__c, 'Stamps applied');
        Assert.isNull(d.Territory_Name__c, 'Territory not requested');

        DE_ClassifierService.classify('Lead', new Set<Id>{ leadId }, new Set<String>{ 'Territory' });
        d = details(leads).get(leadId);
        Assert.areEqual('UK', d.Territory_Name__c, 'Territory applied on the second pass');
        Assert.areEqual('Segment:All', d.Stamps__c, 'Earlier stamps kept');
    }

    @IsTest
    static void classifierJobRunsDirectly() {
        DE_TestFactory.settings();
        insert ukTerritory();
        List<Lead> leads = ukLeads(2);
        insertQuietly(leads);

        Test.startTest();
        System.enqueueJob(new DE_ClassifierJob('Lead', new Map<Id, Lead>(leads).keySet(), true, false));
        Test.stopTest();

        for (DE_Record_Detail__c d : details(leads).values()) {
            Assert.areEqual('UK', d.Territory_Name__c, 'Job classified the records');
        }
    }

    @IsTest
    static void distributeAfterClassifyRoutesNewRecordsImmediately() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Settings__c s = DE_Settings__c.getOrgDefaults();
        s.Distribute_After_Classify__c = true;
        update s;
        DE_Settings.setForTransaction(null);
        List<Lead> leads = DE_TestFactory.leads(4, f.queue.Id);

        Test.startTest();
        insert leads;
        Test.stopTest();

        Set<Id> userIds = new Map<Id, User>(f.users).keySet();
        Map<Id, Id> owners = DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet());
        for (Id owner : owners.values()) {
            Assert.isTrue(userIds.contains(owner), 'Distributed to a team member, not left in the queue');
        }
        Assert.areEqual(2, DE_TestFactory.countByValue(owners).size(), 'Round robin used both members');
    }

    @IsTest
    static void withoutDistributeAfterClassifyRecordsWaitForTheScheduler() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<Lead> leads = DE_TestFactory.leads(2, f.queue.Id);

        Test.startTest();
        insert leads;
        Test.stopTest();

        for (Id owner : DE_TestFactory.owners('Lead', new Map<Id, Lead>(leads).keySet()).values()) {
            Assert.areEqual(f.queue.Id, owner, 'Still at the source queue');
        }
    }

    @IsTest
    static void conditionErrorsAreLoggedAndRecordsStillFinish() {
        DE_TestFactory.settings();
        DE_Territory__c t = ukTerritory();
        insert t;
        DE_Condition__c c = DE_TestFactory.condition('Territory', 1, 'Not_A_Real_Field__c', 'equals', 'x');
        c.Territory__c = t.Id;
        insert c;
        List<Lead> leads = ukLeads(1);
        insertQuietly(leads);

        DE_ClassifierService.classify('Lead', new Map<Id, Lead>(leads).keySet(), null);

        DE_Run_Log__c log = [SELECT Status__c, Message__c FROM DE_Run_Log__c WHERE Process__c = 'Classifier' LIMIT 1];
        Assert.areEqual('Error', log.Status__c, 'Classification error logged');
        Assert.isTrue(log.Message__c.contains('Not_A_Real_Field__c'), 'Message names the field: ' + log.Message__c);
        Assert.areEqual('Done', details(leads).get(leads[0].Id).Classifier_Status__c, 'Records are released for distribution');
    }

    @IsTest
    static void territoryConditionsCanReadTheMatchedAccount() {
        DE_TestFactory.settings();
        insert new DE_Matching_Rule__c(
            Name = 'Accounts',
            Match_Type__c = 'Lead to Account',
            Priority__c = 1,
            Active__c = true,
            Match_Email_Domain__c = true,
            Match_Company_Name__c = false
        );
        DE_Territory__c keyAccounts = new DE_Territory__c(Name = 'Key Accounts', Object_API_Name__c = 'Lead', Status__c = 'Active', Priority__c = 1);
        insert keyAccounts;
        DE_Condition__c c = DE_TestFactory.condition('Territory', 1, 'DE.MatchedAccount.Type', 'equals', 'Customer - Direct');
        c.Territory__c = keyAccounts.Id;
        insert c;
        insert new Account(Name = 'Big Customer', Website = 'bigcustomer.com', Type = 'Customer - Direct');
        Lead known = new Lead(LastName = 'Known', Company = 'Big Customer', Email = 'a@bigcustomer.com');
        Lead unknown = new Lead(LastName = 'Unknown', Company = 'Small', Email = 'b@small-unknown.com');
        List<Lead> leads = new List<Lead>{ known, unknown };
        insertQuietly(leads);
        // Existing details rows (as created on insert) must not break relationship paths.
        insert new List<DE_Record_Detail__c>{
            new DE_Record_Detail__c(Record_Id__c = known.Id, Object_API_Name__c = 'Lead', Classifier_Status__c = 'Waiting'),
            new DE_Record_Detail__c(Record_Id__c = unknown.Id, Object_API_Name__c = 'Lead', Classifier_Status__c = 'Waiting')
        };

        DE_ClassifierService.classify('Lead', new Map<Id, Lead>(leads).keySet(), null);

        Map<Id, DE_Record_Detail__c> after = details(leads);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Classifier' AND Status__c = 'Error'], 'No classification error');
        Assert.areEqual('Key Accounts', after.get(known.Id).Territory_Name__c, 'Matched account type evaluated in the same run');
        Assert.isNull(after.get(unknown.Id).Territory_Name__c, 'No matched account, no territory');
    }

    @IsTest
    static void backfillBatchClassifiesExistingRecords() {
        DE_TestFactory.settings();
        List<Lead> leads = ukLeads(3);
        insertQuietly(leads);
        insert ukTerritory();

        Test.startTest();
        Database.executeBatch(new DE_BackfillBatch('lead', new Set<String>{ 'Territory' }, null, true));
        Test.stopTest();

        for (DE_Record_Detail__c d : details(leads).values()) {
            Assert.areEqual('UK', d.Territory_Name__c, 'Backfill applied the territory');
        }
        DE_Run_Log__c log = [SELECT Status__c, Message__c, Records_Processed__c FROM DE_Run_Log__c WHERE Process__c = 'Classifier' LIMIT 1];
        Assert.areEqual('Success', log.Status__c, 'Backfill logged');
        Assert.areEqual(3, log.Records_Processed__c, 'Three records processed');
        Assert.isTrue(log.Message__c.contains('Backfill of Lead (Territory) classified 3 records.'), 'Message: ' + log.Message__c);
    }

    @IsTest
    static void backfillHonoursTheCreatedSinceDate() {
        DE_TestFactory.settings();
        insertQuietly(ukLeads(2));
        insert ukTerritory();

        Test.startTest();
        Database.executeBatch(new DE_BackfillBatch('Lead', null, System.now().addDays(1), false));
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM DE_Record_Detail__c], 'No records created after the cut-off');
        DE_Run_Log__c log = [SELECT Records_Processed__c FROM DE_Run_Log__c WHERE Process__c = 'Classifier' LIMIT 1];
        Assert.areEqual(0, log.Records_Processed__c, 'Nothing processed');
    }
}
