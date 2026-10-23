/**
 * Lead auto-conversion and de-duplication rules (classifier). Rules run in order; the default rule
 * runs last. The first rule whose Match condition and filters pass decides the action:
 *  - Auto Convert: converts into the matched account/contact (or new ones), optional opportunity.
 *  - De-Duplicate (Lead Only Match): merges the new lead into the existing lead. Not reversible.
 *  - Do Not Convert: stops rule evaluation.
 */
public without sharing class DE_LeadConversion {
    public static List<DE_Conversion_Rule__c> rules() {
        return [
            SELECT
                Id,
                Name,
                Order__c,
                Is_Default__c,
                Match__c,
                Filter_Logic__c,
                Action__c,
                Create_Opportunity__c,
                Owner_Source__c,
                Default_User_Id__c,
                Converted_Status__c,
                Account_Field_Update__c,
                Contact_Field_Update__c,
                Opportunity_Field_Update__c,
                Copy_Blank_Fields__c,
                Survivor_Field_Update__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Conversion_Rule__c
            WHERE Active__c = TRUE
            ORDER BY Is_Default__c, Order__c, Name
        ];
    }

    public static Set<String> requiredPaths(List<DE_Conversion_Rule__c> rules) {
        Set<String> out = new Set<String>{ 'OwnerId', 'IsConverted' };
        for (DE_Conversion_Rule__c r : rules) {
            out.addAll(DE_Conditions.recordPaths(r.Conditions__r));
        }
        return out;
    }

    public static Boolean matchApplies(String match, DE_Record_Detail__c d) {
        Boolean acct = d.Matched_Account__c != null;
        Boolean contact = d.Matched_Contact__c != null;
        Boolean lead = d.Matched_Lead__c != null;
        switch on (match == null ? 'Any' : match) {
            when 'No Match' {
                return !acct && !contact && !lead;
            }
            when 'Account and Contact Match' {
                return acct && contact;
            }
            when 'Account Only Match' {
                return acct && !contact;
            }
            when 'Lead Only Match' {
                return lead && !acct && !contact;
            }
            when else {
                return true;
            }
        }
    }

    public static void run(List<SObject> leads, Map<Id, DE_Record_Detail__c> details, List<DE_Conversion_Rule__c> rules) {
        if (rules.isEmpty()) {
            return;
        }
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = details;
        Map<SObject, DE_Conversion_Rule__c> toConvert = new Map<SObject, DE_Conversion_Rule__c>();
        Map<SObject, DE_Conversion_Rule__c> toDedupe = new Map<SObject, DE_Conversion_Rule__c>();
        for (SObject l : leads) {
            if (l.get('IsConverted') == true) {
                continue;
            }
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, l.Id, 'Lead');
            for (DE_Conversion_Rule__c r : rules) {
                if (!matchApplies(r.Match__c, d) || !DE_Conditions.matches(l, r.Conditions__r, r.Filter_Logic__c, ctx, null)) {
                    continue;
                }
                if (r.Action__c == 'Auto Convert') {
                    toConvert.put(l, r);
                } else if (r.Action__c == 'De-Duplicate' && d.Matched_Lead__c != null) {
                    toDedupe.put(l, r);
                } else {
                    d.Conversion_Result__c = ('Not converted (rule ' + r.Name + ')').left(255);
                }
                break;
            }
        }
        convert(toConvert, details);
        dedupe(toDedupe, details);
    }

    private static String defaultConvertedStatus() {
        List<LeadStatus> s = [SELECT ApiName FROM LeadStatus WHERE IsConverted = TRUE ORDER BY SortOrder LIMIT 1];
        return s.isEmpty() ? null : s[0].ApiName;
    }

    private static void convert(Map<SObject, DE_Conversion_Rule__c> toConvert, Map<Id, DE_Record_Detail__c> details) {
        if (toConvert.isEmpty()) {
            return;
        }
        String defaultStatus = defaultConvertedStatus();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (SObject l : toConvert.keySet()) {
            DE_Record_Detail__c d = details.get(l.Id);
            if (d.Matched_Account__c != null) {
                accountIds.add(d.Matched_Account__c);
            }
            if (d.Matched_Contact__c != null) {
                contactIds.add(d.Matched_Contact__c);
            }
        }
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, OwnerId, Owner.IsActive FROM Account WHERE Id IN :accountIds]);
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, AccountId, OwnerId, Owner.IsActive FROM Contact WHERE Id IN :contactIds]);
        Set<Id> withOpenOpps = new Set<Id>();
        for (AggregateResult ar : [SELECT AccountId a FROM Opportunity WHERE AccountId IN :accountIds AND IsClosed = FALSE GROUP BY AccountId]) {
            withOpenOpps.add((Id) ar.get('a'));
        }
        List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
        List<SObject> order = new List<SObject>();
        for (SObject l : toConvert.keySet()) {
            DE_Conversion_Rule__c r = toConvert.get(l);
            DE_Record_Detail__c d = details.get(l.Id);
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            Contact c = contacts.get(d.Matched_Contact__c);
            Id accountId = c != null ? c.AccountId : d.Matched_Account__c;
            if (accountId != null) {
                lc.setAccountId(accountId);
            }
            if (c != null) {
                lc.setContactId(c.Id);
            }
            lc.setConvertedStatus(String.isBlank(r.Converted_Status__c) ? defaultStatus : r.Converted_Status__c);
            String opp = r.Create_Opportunity__c == null ? 'Never' : r.Create_Opportunity__c;
            lc.setDoNotCreateOpportunity(opp == 'Never' || (opp == 'Only When No Open Opportunity' && accountId != null && withOpenOpps.contains(accountId)));
            Id owner = null;
            if (r.Owner_Source__c == 'Default User') {
                owner = DE_Ids.toId(r.Default_User_Id__c);
            } else if (r.Owner_Source__c != 'Retain Lead Owner') {
                if (c != null && c.Owner.IsActive) {
                    owner = c.OwnerId;
                } else if (accounts.containsKey(accountId) && accounts.get(accountId).Owner.IsActive) {
                    owner = accounts.get(accountId).OwnerId;
                }
            }
            if (owner == null && ((Id) l.get('OwnerId')).getSobjectType() == Group.SObjectType) {
                owner = UserInfo.getUserId(); // converted records cannot be owned by a queue
            }
            if (owner != null) {
                lc.setOwnerId(owner);
            }
            converts.add(lc);
            order.add(l);
        }
        List<Database.LeadConvertResult> results = Database.convertLead(converts, false);
        List<SObject> postUpdates = new List<SObject>();
        for (Integer i = 0; i < results.size(); i++) {
            DE_Record_Detail__c d = details.get(order[i].Id);
            DE_Conversion_Rule__c r = toConvert.get(order[i]);
            if (!results[i].isSuccess()) {
                d.Conversion_Result__c = ('Failed: ' + results[i].getErrors()[0].getMessage()).left(255);
                continue;
            }
            d.Conversion_Result__c = ('Converted (rule ' + r.Name + ')').left(255);
            addUpdate(postUpdates, 'Account', results[i].getAccountId(), r.Account_Field_Update__c);
            addUpdate(postUpdates, 'Contact', results[i].getContactId(), r.Contact_Field_Update__c);
            addUpdate(postUpdates, 'Opportunity', results[i].getOpportunityId(), r.Opportunity_Field_Update__c);
        }
        if (!postUpdates.isEmpty()) {
            postUpdates.sort();
            Database.update(postUpdates, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void addUpdate(List<SObject> updates, String objectName, Id recordId, String spec) {
        if (recordId == null || String.isBlank(spec)) {
            return;
        }
        SObject s = DE_Schema.sobjectType(objectName).newSObject(recordId);
        DE_FieldUpdates.apply(s, objectName, spec, null);
        updates.add(s);
    }

    private static void dedupe(Map<SObject, DE_Conversion_Rule__c> toDedupe, Map<Id, DE_Record_Detail__c> details) {
        if (toDedupe.isEmpty()) {
            return;
        }
        List<String> fields = new List<String>();
        for (Schema.SObjectField f : Schema.SObjectType.Lead.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (fd.isUpdateable() && !fd.isCalculated() && fd.getType() != Schema.DisplayType.ADDRESS) {
                fields.add(fd.getName());
            }
        }
        Set<Id> ids = new Set<Id>();
        for (SObject l : toDedupe.keySet()) {
            ids.add(l.Id);
            ids.add(details.get(l.Id).Matched_Lead__c);
        }
        Map<Id, SObject> full = new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT Id, ' + String.join(fields, ', ') + ' FROM Lead WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
        for (SObject l : toDedupe.keySet()) {
            DE_Conversion_Rule__c r = toDedupe.get(l);
            DE_Record_Detail__c d = details.get(l.Id);
            SObject survivor = full.get(d.Matched_Lead__c);
            SObject incoming = full.get(l.Id);
            if (survivor == null || incoming == null) {
                continue;
            }
            Lead master = new Lead(Id = survivor.Id);
            if (r.Copy_Blank_Fields__c != false) {
                for (String f : fields) {
                    if (f == 'OwnerId' || f == 'Status') {
                        continue;
                    }
                    if (survivor.get(f) == null && incoming.get(f) != null) {
                        master.put(f, incoming.get(f));
                    }
                }
            }
            DE_FieldUpdates.apply(master, 'Lead', r.Survivor_Field_Update__c, null);
            Savepoint sp = Database.setSavepoint();
            try {
                Database.MergeResult mr = Database.merge(master, l.Id, false);
                d.Conversion_Result__c = mr.isSuccess()
                    ? ('De-duplicated into ' + survivor.Id + ' (rule ' + r.Name + ')').left(255)
                    : ('Failed: ' + mr.getErrors()[0].getMessage()).left(255);
            } catch (Exception e) {
                Database.rollback(sp);
                d.Conversion_Result__c = ('Failed: ' + e.getMessage()).left(255);
            }
        }
    }
}
