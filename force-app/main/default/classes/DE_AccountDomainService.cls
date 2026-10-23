/**
 * Index of account domains used by lead matching: one DE_Account_Domain__c row per account website
 * domain and per distinct business email domain of the account's contacts. Kept current from Account and
 * Contact triggers; DE_AccountDomainBatch rebuilds it for existing data.
 */
public without sharing class DE_AccountDomainService {
    public static final String WEBSITE = 'Website';
    public static final String CONTACT_EMAIL = 'Contact Email';
    private static final Integer NAME_LENGTH = 80;
    private static Boolean available;

    /** True once the index holds any rows (built by the triggers or the rebuild batch). */
    public static Boolean indexAvailable() {
        if (available == null) {
            available = [SELECT COUNT() FROM DE_Account_Domain__c WHERE Account__c != NULL LIMIT 1] > 0;
        }
        return available;
    }

    public static List<DE_Account_Domain__c> lookup(Set<String> domains) {
        List<String> keys = new List<String>();
        for (String d : domains) {
            if (String.isNotBlank(d) && d.length() <= NAME_LENGTH) {
                keys.add(d.toLowerCase());
            }
        }
        if (keys.isEmpty()) {
            return new List<DE_Account_Domain__c>();
        }
        return [SELECT Name, Account__c, Domain_Type__c FROM DE_Account_Domain__c WHERE Name IN :keys AND Account__c != NULL LIMIT 5000];
    }

    public static String uniqueKey(String domainType, Id accountId, String domain) {
        return ((domainType == WEBSITE ? 'W|' : 'C|') + accountId + '|' + domain).left(120);
    }

    // ------------------------------------------------------------------ trigger entry points

    /** Contact before insert/update: stamp the email domain used for matching. */
    public static void stampContactDomains(List<SObject> contacts) {
        if (!DE_Schema.hasField('Contact', 'DE_Email_Domain__c')) {
            return;
        }
        for (SObject c : contacts) {
            String d = DE_TextMatch.emailDomain((String) c.get('Email'));
            c.put('DE_Email_Domain__c', d == null ? null : d.left(255));
        }
    }

    /** Account after insert/update/delete: re-index accounts whose website changed. */
    public static void onAccountsChanged(List<SObject> newRows, Map<Id, SObject> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (SObject a : newRows == null ? oldMap.values() : newRows) {
            SObject old = oldMap == null ? null : oldMap.get(a.Id);
            if (newRows == null || old == null || old.get('Website') != a.get('Website')) {
                ids.add(a.Id);
            }
        }
        rebuild(ids);
    }

    /** Contact after insert/update/delete: re-index the old and new accounts of contacts whose email or account changed. */
    public static void onContactsChanged(List<SObject> newRows, Map<Id, SObject> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (SObject c : newRows == null ? oldMap.values() : newRows) {
            SObject old = oldMap == null ? null : oldMap.get(c.Id);
            Boolean changed = newRows == null || old == null || old.get('Email') != c.get('Email') || old.get('AccountId') != c.get('AccountId');
            if (!changed) {
                continue;
            }
            if (c.get('AccountId') != null) {
                ids.add((Id) c.get('AccountId'));
            }
            if (old != null && old.get('AccountId') != null) {
                ids.add((Id) old.get('AccountId'));
            }
        }
        rebuild(ids);
    }

    // ------------------------------------------------------------------ index maintenance

    /** Recomputes the index rows of the given accounts (adds new domains, removes stale ones). Returns rows written. */
    public static Integer rebuild(Set<Id> accountIds) {
        accountIds.remove(null);
        if (accountIds.isEmpty()) {
            return 0;
        }
        Set<String> personal = DE_Settings.personalDomains();
        Map<String, DE_Account_Domain__c> desired = new Map<String, DE_Account_Domain__c>();
        for (Account a : [SELECT Id, Website FROM Account WHERE Id IN :accountIds]) {
            add(desired, WEBSITE, a.Id, DE_TextMatch.websiteDomain(a.Website), personal);
        }
        for (Contact c : [SELECT AccountId, Email FROM Contact WHERE AccountId IN :accountIds AND Email != NULL LIMIT 10000]) {
            add(desired, CONTACT_EMAIL, c.AccountId, DE_TextMatch.emailDomain(c.Email), personal);
        }
        List<DE_Account_Domain__c> stale = new List<DE_Account_Domain__c>();
        for (DE_Account_Domain__c existing : [SELECT Id, Unique_Key__c FROM DE_Account_Domain__c WHERE Account__c IN :accountIds]) {
            if (!desired.containsKey(existing.Unique_Key__c)) {
                stale.add(existing);
            }
        }
        if (!stale.isEmpty()) {
            Database.delete(stale, false, AccessLevel.SYSTEM_MODE);
        }
        if (!desired.isEmpty()) {
            Database.upsert(desired.values(), DE_Account_Domain__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
            available = true;
        }
        return desired.size();
    }

    private static void add(Map<String, DE_Account_Domain__c> desired, String domainType, Id accountId, String domain, Set<String> personal) {
        if (String.isBlank(domain) || domain.length() > NAME_LENGTH || personal.contains(domain.toLowerCase())) {
            return;
        }
        String d = domain.toLowerCase();
        String k = uniqueKey(domainType, accountId, d);
        desired.put(k, new DE_Account_Domain__c(Name = d, Account__c = accountId, Domain_Type__c = domainType, Unique_Key__c = k));
    }

    /** Deletes rows whose account was deleted (the lookup is cleared on delete). Returns rows removed. */
    public static Integer purgeOrphans() {
        List<DE_Account_Domain__c> orphans = [SELECT Id FROM DE_Account_Domain__c WHERE Account__c = NULL LIMIT 9000];
        if (!orphans.isEmpty()) {
            Database.delete(orphans, false, AccessLevel.SYSTEM_MODE);
        }
        return orphans.size();
    }
}
