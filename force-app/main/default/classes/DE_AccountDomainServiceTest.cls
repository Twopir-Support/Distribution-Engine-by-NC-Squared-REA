@IsTest
private class DE_AccountDomainServiceTest {
    private static Map<String, DE_Account_Domain__c> index() {
        Map<String, DE_Account_Domain__c> out = new Map<String, DE_Account_Domain__c>();
        for (DE_Account_Domain__c d : [SELECT Name, Account__c, Domain_Type__c, Unique_Key__c FROM DE_Account_Domain__c]) {
            out.put(d.Domain_Type__c + ':' + d.Name, d);
        }
        return out;
    }

    @IsTest
    static void websitesAndBusinessContactDomainsAreIndexed() {
        DE_TestFactory.settings();
        Account a = new Account(Name = 'Acme', Website = 'https://www.acme-index.com/about');
        insert a;
        Contact work = new Contact(LastName = 'Work', AccountId = a.Id, Email = 'pat@acme-mail.com');
        Contact personal = new Contact(LastName = 'Personal', AccountId = a.Id, Email = 'pat@gmail.com');
        insert new List<Contact>{ work, personal };

        Map<String, DE_Account_Domain__c> idx = index();
        Assert.areEqual(2, idx.size(), 'Website and business email domain; personal domains are skipped: ' + idx.keySet());
        Assert.areEqual(a.Id, idx.get('Website:acme-index.com').Account__c, 'Website domain');
        Assert.areEqual(a.Id, idx.get('Contact Email:acme-mail.com').Account__c, 'Contact email domain');
        Assert.areEqual('acme-mail.com', [SELECT DE_Email_Domain__c FROM Contact WHERE Id = :work.Id].DE_Email_Domain__c, 'Domain stamped on the contact');
        Assert.isTrue(DE_AccountDomainService.indexAvailable(), 'Index available');
    }

    @IsTest
    static void changesKeepTheIndexCurrent() {
        DE_TestFactory.settings();
        Account a = new Account(Name = 'Acme', Website = 'old-site.com');
        Account b = new Account(Name = 'Beta', Website = 'beta-site.com');
        insert new List<Account>{ a, b };
        Contact c = new Contact(LastName = 'Mover', AccountId = a.Id, Email = 'mover@shared-domain.com');
        insert c;

        a.Website = 'new-site.com';
        update a;
        c.AccountId = b.Id;
        update c;

        Map<String, DE_Account_Domain__c> idx = index();
        Assert.isFalse(idx.containsKey('Website:old-site.com'), 'Old website removed');
        Assert.areEqual(a.Id, idx.get('Website:new-site.com').Account__c, 'New website indexed');
        Assert.areEqual(b.Id, idx.get('Contact Email:shared-domain.com').Account__c, 'Contact domain moved with the contact');

        delete c;
        Assert.isFalse(index().containsKey('Contact Email:shared-domain.com'), 'Deleted contact removed from the index');
    }

    @IsTest
    static void leadMatchingUsesTheIndex() {
        DE_TestFactory.settings();
        insert new DE_Matching_Rule__c(
            Name = 'Accounts',
            Match_Type__c = 'Lead to Account',
            Priority__c = 1,
            Active__c = true,
            Match_Email_Domain__c = true,
            Match_Company_Name__c = false
        );
        Account a = new Account(Name = 'Indexed');
        insert a;
        insert new Contact(LastName = 'Known', AccountId = a.Id, Email = 'known@indexed-corp.com');
        Lead l = new Lead(LastName = 'New', Company = 'Something else', Email = 'new@indexed-corp.com');
        DE_TriggerHandler.bypass = true;
        insert l;
        DE_TriggerHandler.bypass = false;

        DE_ClassifierService.classify('Lead', new Set<Id>{ l.Id }, new Set<String>{ 'Match' });

        DE_Record_Detail__c d = DE_RecordDetails.load(new Set<Id>{ l.Id }, null).get(l.Id);
        Assert.areEqual(a.Id, d.Matched_Account__c, 'Matched through the contact email domain in the index');
        Assert.isTrue(d.Match_Confidence__c.contains('contact email domain'), d.Match_Confidence__c);
    }

    @IsTest
    static void rebuildBatchIndexesExistingDataAndPurgesOrphans() {
        DE_TestFactory.settings();
        DE_TriggerHandler.bypass = true;
        Account a = new Account(Name = 'Loaded', Website = 'loaded-quietly.com');
        insert a;
        DE_TriggerHandler.bypass = false;
        Assert.isTrue(index().isEmpty(), 'Data loaded without triggers is not indexed yet');
        insert new DE_Account_Domain__c(Name = 'orphan.com', Domain_Type__c = 'Website', Unique_Key__c = 'W|orphan');

        Test.startTest();
        Database.executeBatch(new DE_AccountDomainBatch(), 200);
        Test.stopTest();

        Map<String, DE_Account_Domain__c> idx = index();
        Assert.areEqual(a.Id, idx.get('Website:loaded-quietly.com').Account__c, 'Rebuilt');
        Assert.isFalse(idx.containsKey('Website:orphan.com'), 'Rows without an account removed');
        DE_Run_Log__c log = [SELECT Message__c FROM DE_Run_Log__c WHERE Process__c = 'Classifier' LIMIT 1];
        Assert.isTrue(log.Message__c.startsWith('Domain index rebuilt'), log.Message__c);
    }

    @IsTest
    static void nothingIsIndexedWhileTheEngineIsDisabled() {
        DE_Settings__c s = DE_TestFactory.settings();
        s.Engine_Enabled__c = false;
        update s;
        DE_Settings.setForTransaction(null);
        insert new Account(Name = 'Off', Website = 'engine-off.com');
        Assert.isTrue(index().isEmpty(), 'Engine off: no index maintenance');
        Assert.areEqual(0, DE_AccountDomainService.rebuild(new Set<Id>{ null }), 'Nothing to rebuild');
    }
}
