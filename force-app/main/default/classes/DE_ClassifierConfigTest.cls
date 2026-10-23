@IsTest
private class DE_ClassifierConfigTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static String stampsOf(Id leadId) {
        return DE_RecordDetails.load(new Set<Id>{ leadId }, null).get(leadId).Stamps__c;
    }

    @IsTest
    static void defaultStampOnlyWhenNothingElseMatches() {
        DE_TestFactory.settings();
        DE_Stamp_Group__c g = new DE_Stamp_Group__c(Name = 'Segment', Object_API_Name__c = 'Lead', Active__c = true, Group_Type__c = 'Single');
        insert g;
        DE_Stamp__c enterprise = new DE_Stamp__c(Name = 'Enterprise', Stamp_Group__c = g.Id, Order__c = 1);
        DE_Stamp__c other = new DE_Stamp__c(Name = 'Other', Stamp_Group__c = g.Id, Order__c = 0, Is_Default__c = true);
        DE_Stamp__c retired = new DE_Stamp__c(Name = 'Retired', Stamp_Group__c = g.Id, Order__c = 2, Active__c = false);
        insert new List<DE_Stamp__c>{ enterprise, other, retired };
        List<DE_Condition__c> conds = new List<DE_Condition__c>{
            DE_TestFactory.condition('Stamp', 1, 'Company', 'equals', 'Big Co'),
            DE_TestFactory.condition('Stamp', 1, 'Company', 'equals', 'Small Co')
        };
        conds[0].Stamp__c = enterprise.Id;
        conds[1].Stamp__c = retired.Id;
        insert conds;
        Lead big = new Lead(LastName = 'A', Company = 'Big Co');
        Lead small = new Lead(LastName = 'B', Company = 'Small Co');
        insertQuietly(new List<Lead>{ big, small });

        DE_ClassifierService.classify('Lead', new Set<Id>{ big.Id, small.Id }, new Set<String>{ 'Stamps' });

        Assert.areEqual('Segment:Enterprise', stampsOf(big.Id), 'Matching stamp wins over the default, whatever its order');
        Assert.areEqual('Segment:Other', stampsOf(small.Id), 'Inactive stamps are ignored; the default stamp applies');
    }

    @IsTest
    static void controllerValidatesTheNewOptions() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();
        try {
            DE_ClassifierController.saveTerritory(
                new DE_Territory__c(Name = 'UK', Object_API_Name__c = 'Lead', Priority__c = 1, Color__c = 'blue'),
                new List<DE_Condition__c>()
            );
            Assert.fail('Colour must be hex');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }
        Id t = DE_ClassifierController.saveTerritory(
            new DE_Territory__c(Name = 'UK', Object_API_Name__c = 'Lead', Priority__c = 1, Color__c = '#2a78d6'),
            new List<DE_Condition__c>()
        );
        Assert.areEqual('#2a78d6', [SELECT Color__c FROM DE_Territory__c WHERE Id = :t].Color__c, 'Colour saved');

        DE_Stamp_Group__c g = new DE_Stamp_Group__c(Name = 'Segment', Object_API_Name__c = 'Lead', Active__c = true, Group_Type__c = 'Single');
        insert g;
        DE_ClassifierController.saveStamp(
            new DE_Stamp__c(Name = 'Other', Stamp_Group__c = g.Id, Order__c = 1, Is_Default__c = true),
            new List<DE_Condition__c>()
        );
        try {
            DE_ClassifierController.saveStamp(
                new DE_Stamp__c(Name = 'Else', Stamp_Group__c = g.Id, Order__c = 2, Is_Default__c = true),
                new List<DE_Condition__c>()
            );
            Assert.fail('Only one default stamp per group');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }

        DE_Conversion_Rule__c r = new DE_Conversion_Rule__c(
            Name = 'Convert',
            Order__c = 1,
            Match__c = 'Account Only Match',
            Action__c = 'Auto Convert',
            Owner_Source__c = 'Matched Record Owner',
            Account_Record_Type__c = 'No_Such_Record_Type',
            Distribute_After__c = true
        );
        try {
            DE_ClassifierController.saveConversionRule(r, new List<DE_Condition__c>());
            Assert.fail('Unknown record type and distribute-after on a convert rule are rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('No_Such_Record_Type'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('De-Duplicate'), e.getMessage());
        }
    }

    @IsTest
    static void unknownRecordTypesResolveToNull() {
        Assert.isNull(DE_LeadConversion.recordTypeId('Account', null), 'Blank');
        Assert.isNull(DE_LeadConversion.recordTypeId('Account', 'No_Such_Record_Type'), 'Unknown');
        Assert.isNull(DE_LeadConversion.recordTypeId('Account', 'Master'), 'The master record type is never set');
    }

    @IsTest
    static void conversionCopiesLeadSourceOntoTheExistingContact() {
        DE_TestFactory.settings();
        insert new DE_Matching_Rule__c(Name = 'Contacts', Match_Type__c = 'Lead to Contact', Priority__c = 1, Active__c = true, Match_Email__c = true);
        DE_Conversion_Rule__c r = new DE_Conversion_Rule__c(
            Name = 'Known contacts',
            Order__c = 1,
            Match__c = 'Account and Contact Match',
            Action__c = 'Auto Convert',
            Active__c = true,
            Create_Opportunity__c = 'Never',
            Owner_Source__c = 'Matched Record Owner',
            Overwrite_Lead_Source__c = true,
            Send_Email__c = true
        );
        insert r;
        Account a = new Account(Name = 'Acme');
        insert a;
        Contact c = new Contact(LastName = 'Known', AccountId = a.Id, Email = 'known@acme-convert.com');
        insert c;
        Lead l = new Lead(LastName = 'Known', Company = 'Acme', Email = 'known@acme-convert.com', LeadSource = 'Web');
        insertQuietly(new List<Lead>{ l });

        Test.startTest();
        DE_ClassifierService.classify('Lead', new Set<Id>{ l.Id }, new Set<String>{ 'Match', 'Conversion' });
        Test.stopTest();

        Assert.isTrue([SELECT IsConverted FROM Lead WHERE Id = :l.Id].IsConverted, 'Converted into the known contact');
        Assert.areEqual('Web', [SELECT LeadSource FROM Contact WHERE Id = :c.Id].LeadSource, 'Lead source copied onto the existing contact');
        DE_Conversion_Log__c log = [SELECT Result__c, Contact_Id__c, Account_Id__c, Conversion_Rule__c FROM DE_Conversion_Log__c WHERE Record_Id__c = :l.Id];
        Assert.areEqual('Converted', log.Result__c, 'Logged');
        Assert.areEqual(c.Id, log.Contact_Id__c, 'Contact recorded');
        Assert.areEqual(a.Id, log.Account_Id__c, 'Account recorded');
        Assert.areEqual(r.Id, log.Conversion_Rule__c, 'Rule recorded');
    }

    @IsTest
    static void domainIndexRebuildCanBeStarted() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();
        Test.startTest();
        Id jobId = DE_ClassifierController.rebuildDomainIndex();
        Test.stopTest();
        Assert.isNotNull(jobId, 'Batch started');
        Assert.areEqual(0, DE_ClassifierController.getDomainIndexSize(), 'No accounts, no domains');
        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        try {
            DE_ClassifierController.rebuildDomainIndex();
            Assert.fail('Admins only');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e, 'Denied');
        }
    }

    @IsTest
    static void settingsValidateMonitoringFields() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();
        DE_Settings__c s = DE_SettingsController.getSettings();
        s.History_Retention_Days__c = 0;
        s.Failure_Alert_Threshold__c = 500;
        s.Admin_Alert_Emails__c = 'ops@example.com, not-an-email';
        try {
            DE_SettingsController.saveSettings(s);
            Assert.fail('Invalid monitoring settings rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Retention periods'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Failure alert threshold'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('not-an-email'), e.getMessage());
        }
        s.History_Retention_Days__c = 60;
        s.Failure_Alert_Threshold__c = 3;
        s.Admin_Alert_Emails__c = 'ops@example.com; lead@example.com';
        DE_SettingsController.saveSettings(s);
        Assert.areEqual(60, DE_Settings.historyRetentionDays(), 'Saved');
        Assert.areEqual(new List<String>{ 'ops@example.com', 'lead@example.com' }, DE_Settings.adminAlertEmails(), 'Recipients parsed');
        Assert.areEqual(3, DE_Settings.failureAlertThreshold(), 'Threshold');
    }
}
