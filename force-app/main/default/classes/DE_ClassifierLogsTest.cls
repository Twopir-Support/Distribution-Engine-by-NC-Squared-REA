@IsTest
private class DE_ClassifierLogsTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static DE_Territory__c ukTerritory() {
        return new DE_Territory__c(
            Name = 'UK',
            Map__c = 'EMEA',
            Object_API_Name__c = 'Lead',
            Status__c = 'Active',
            Priority__c = 1,
            Countries__c = 'United Kingdom'
        );
    }

    private static List<Lead> leads(Integer count, String country) {
        List<Lead> out = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            out.add(new Lead(LastName = 'Lead ' + i, Company = 'Company ' + i, Country = country));
        }
        return out;
    }

    private static Set<Id> ids(List<SObject> records) {
        return new Map<Id, SObject>(records).keySet();
    }

    @IsTest
    static void territoryLogShowsTheCleanedAddressAndLevel() {
        DE_TestFactory.settings();
        DE_Territory__c t = ukTerritory();
        insert t;
        List<Lead> uk = leads(2, 'UK');
        List<Lead> other = leads(1, 'Japan');
        List<Lead> all = new List<Lead>(uk);
        all.addAll(other);
        insertQuietly(all);

        DE_ClassifierService.classify('Lead', ids(all), null);

        Map<String, DE_Territory_Log__c> logs = new Map<String, DE_Territory_Log__c>();
        for (DE_Territory_Log__c l : [
            SELECT Record_Id__c, Record_Name__c, Object_API_Name__c, Territory__c, Match_Level__c, Clean_Country__c, In_Error__c, Attempts__c
            FROM DE_Territory_Log__c
        ]) {
            logs.put(l.Record_Id__c, l);
        }
        Assert.areEqual(3, logs.size(), 'One log per classified record');
        DE_Territory_Log__c matched = logs.get(uk[0].Id);
        Assert.areEqual(t.Id, matched.Territory__c, 'Matched territory');
        Assert.areEqual('Country', matched.Match_Level__c, 'Matched on the country list');
        Assert.areEqual(DE_TextMatch.normalizeCountry('UK'), matched.Clean_Country__c, 'Cleaned country');
        Assert.areEqual('Lead 0', matched.Record_Name__c, 'Record name');
        Assert.areEqual('Lead', matched.Object_API_Name__c, 'Object');
        Assert.isFalse(matched.In_Error__c, 'No error');
        Assert.areEqual(1, matched.Attempts__c, 'First attempt');
        Assert.areEqual('None', logs.get(other[0].Id).Match_Level__c, 'Unmatched records are logged with no territory');
        for (Lead l : [SELECT DE_Classifier_Status__c FROM Lead WHERE Id IN :ids(all)]) {
            Assert.areEqual('Done', l.DE_Classifier_Status__c, 'Status mirrored on the record');
        }
    }

    @IsTest
    static void stageErrorsAreLoggedPerRecordAndAttemptsGrow() {
        DE_TestFactory.settings();
        DE_Territory__c t = ukTerritory();
        insert t;
        DE_Condition__c c = DE_TestFactory.condition('Territory', 1, 'Not_A_Real_Field__c', 'equals', 'x');
        c.Territory__c = t.Id;
        insert c;
        List<Lead> uk = leads(1, 'UK');
        insertQuietly(uk);

        DE_ClassifierService.classify('Lead', ids(uk), null);
        DE_ClassifierService.classify('Lead', ids(uk), null);

        DE_Territory_Log__c log = [SELECT In_Error__c, Attempts__c, Error_Message__c FROM DE_Territory_Log__c WHERE Record_Id__c = :uk[0].Id];
        Assert.isTrue(log.In_Error__c, 'Territory stage failed');
        Assert.areEqual(2, log.Attempts__c, 'Consecutive failures counted');
        Assert.isTrue(log.Error_Message__c.contains('Not_A_Real_Field__c'), log.Error_Message__c);
        Assert.areEqual('Error', [SELECT DE_Classifier_Status__c FROM Lead WHERE Id = :uk[0].Id].DE_Classifier_Status__c, 'Error mirrored');
        Assert.areEqual(new Map<String, Integer>{ 'Territory' => 1 }, DE_ClassifierLogs.repeatedFailures(2), 'Repeated failure detected');
        Assert.isTrue(DE_ClassifierLogs.repeatedFailures(3).isEmpty(), 'Below the threshold');
    }

    @IsTest
    static void failedRecordsAreRetried() {
        DE_TestFactory.settings();
        insert ukTerritory();
        List<Lead> uk = leads(1, 'UK');
        insertQuietly(uk);
        insert new DE_Territory_Log__c(
            Record_Id__c = uk[0].Id,
            Object_API_Name__c = 'Lead',
            In_Error__c = true,
            Attempts__c = 3,
            Processed_At__c = System.now().addMinutes(-5)
        );

        Integer retried = DE_ClassifierLogs.retryFailed(50);

        Assert.areEqual(1, retried, 'The failed record was retried');
        DE_Territory_Log__c log = [SELECT In_Error__c, Attempts__c, Match_Level__c FROM DE_Territory_Log__c WHERE Record_Id__c = :uk[0].Id];
        Assert.isFalse(log.In_Error__c, 'Succeeded on retry');
        Assert.areEqual(1, log.Attempts__c, 'Attempts reset after success');
        Assert.areEqual('Country', log.Match_Level__c, 'Classified');
        Assert.areEqual(0, DE_ClassifierLogs.retryFailed(50), 'Nothing left to retry');
    }

    @IsTest
    static void matchingLogRecordsTheRuleAndConfidence() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c rule = new DE_Matching_Rule__c(
            Name = 'Accounts',
            Match_Type__c = 'Lead to Account',
            Priority__c = 1,
            Active__c = true,
            Match_Email_Domain__c = true,
            Match_Company_Name__c = false
        );
        insert rule;
        Account a = new Account(Name = 'Acme', Website = 'https://www.acme-logs.com');
        insert a;
        Lead l = new Lead(LastName = 'Buyer', Company = 'Acme', Email = 'buyer@acme-logs.com');
        insertQuietly(new List<Lead>{ l });

        DE_ClassifierService.classify('Lead', new Set<Id>{ l.Id }, new Set<String>{ 'Match' });

        DE_Matching_Log__c log = [
            SELECT Matched_Account__c, Account_Rule__c, Account_Confidence__c, In_Error__c
            FROM DE_Matching_Log__c
            WHERE Record_Id__c = :l.Id
        ];
        Assert.areEqual(a.Id, log.Matched_Account__c, 'Matched account');
        Assert.areEqual(rule.Id, log.Account_Rule__c, 'Rule used');
        Assert.isTrue(log.Account_Confidence__c.contains('website domain'), log.Account_Confidence__c);
        Assert.isFalse(log.In_Error__c, 'No error');
    }

    @IsTest
    static void conversionAndClassificationLogs() {
        DE_TestFactory.settings();
        DE_Conversion_Rule__c keep = new DE_Conversion_Rule__c(
            Name = 'Never convert',
            Order__c = 1,
            Match__c = 'Any',
            Action__c = 'Do Not Convert',
            Active__c = true,
            Create_Opportunity__c = 'Never',
            Owner_Source__c = 'Matched Record Owner'
        );
        insert keep;
        DE_Stamp_Group__c g = new DE_Stamp_Group__c(Name = 'Tier', Object_API_Name__c = 'Lead', Active__c = true, Group_Type__c = 'Single');
        insert g;
        insert new DE_Stamp__c(Name = 'Gold', Stamp_Group__c = g.Id, Order__c = 1);
        List<Lead> ls = leads(1, 'UK');
        insertQuietly(ls);

        DE_ClassifierService.classify('Lead', ids(ls), null);

        DE_Conversion_Log__c conv = [SELECT Result__c, Conversion_Rule__c, In_Error__c FROM DE_Conversion_Log__c WHERE Record_Id__c = :ls[0].Id];
        Assert.areEqual('Not Converted', conv.Result__c, 'Do Not Convert rule');
        Assert.areEqual(keep.Id, conv.Conversion_Rule__c, 'Rule recorded');
        DE_Classification_Log__c cls = [SELECT Stamps__c, In_Error__c FROM DE_Classification_Log__c WHERE Record_Id__c = :ls[0].Id];
        Assert.areEqual('Tier:Gold', cls.Stamps__c, 'Stamps recorded');
        Assert.isFalse(cls.In_Error__c, 'No error');
    }

    @IsTest
    static void consoleListsAndRetriesLogs() {
        DE_TestFactory.settings();
        insert ukTerritory();
        List<Lead> uk = leads(1, 'UK');
        insertQuietly(uk);
        DE_ClassifierService.classify('Lead', ids(uk), null);
        insert new DE_Object_Sync_Log__c(
            Record_Id__c = uk[0].Id,
            Object_API_Name__c = 'Lead',
            Status__c = 'Success',
            Actions_Performed__c = 'Task=2',
            Synced_Records__c = 2,
            Processed_At__c = System.now()
        );
        DE_TestFactory.grantAll();

        DE_ConsoleController.ClassifierLogFilter f = new DE_ConsoleController.ClassifierLogFilter();
        f.logType = 'Territory';
        List<Map<String, Object>> rows = DE_ConsoleController.getClassifierLogs(f);
        Assert.areEqual(1, rows.size(), 'One territory log');
        Assert.areEqual('EMEA.UK', rows[0].get('territory'), 'Map.Territory');
        Assert.areEqual('Success', rows[0].get('status'), 'Status');
        f.errorsOnly = true;
        Assert.areEqual(0, DE_ConsoleController.getClassifierLogs(f).size(), 'No errors');

        f.logType = 'Object Sync';
        f.errorsOnly = false;
        rows = DE_ConsoleController.getClassifierLogs(f);
        Assert.areEqual(1, rows.size(), 'Sync log listed');
        Assert.areEqual(1, rows[0].get('actionCount'), 'One action line');

        f.logType = 'Nope';
        try {
            DE_ConsoleController.getClassifierLogs(f);
            Assert.fail('Unknown log type rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }
        Assert.areEqual(1, DE_ConsoleController.retryClassification(new List<String>{ uk[0].Id }, 'Territory'), 'Classified again');
        try {
            DE_ConsoleController.retryClassification(new List<String>{ uk[0].Id }, 'Object Sync');
            Assert.fail('Sync logs are not classifier logs');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Rejected');
        }
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_ConsoleController.retryClassification(new List<String>{ uk[0].Id }, 'Territory');
            Assert.fail('Users cannot retry classification');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e, 'Denied');
        }
    }

    @IsTest
    static void oldLogsArePurgedWithinTheRetentionPeriod() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Classifier_Log_Retention_Days__c = 10;
        update s;
        DE_Settings.setForTransaction(null);
        Datetime old = System.now().addDays(-20);
        insert new List<SObject>{
            new DE_Territory_Log__c(Record_Id__c = 'r1', Processed_At__c = old),
            new DE_Territory_Log__c(Record_Id__c = 'r2', Processed_At__c = System.now()),
            new DE_Matching_Log__c(Record_Id__c = 'r3', Processed_At__c = old),
            new DE_Object_Sync_Log__c(Record_Id__c = 'r4', Processed_At__c = old)
        };

        Map<String, Integer> purged = DE_MaintenanceBatch.purgeAll(System.now());

        Assert.areEqual(3, purged.get('classifier and object sync logs'), 'Old classifier and sync logs purged');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Territory_Log__c], 'Recent log kept');
    }
}
