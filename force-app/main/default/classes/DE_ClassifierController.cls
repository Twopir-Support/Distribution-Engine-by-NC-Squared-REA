/**
 * Distribution Classifier tab: territories, lead matching, auto conversion, stamp groups and backfill.
 * Admins only (the reference restricts the classifier to administrators).
 */
public with sharing class DE_ClassifierController {
    public class ConditionalRecord {
        @AuraEnabled
        public SObject record { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> conditions { get; set; }
    }

    public class StampGroupDetail {
        @AuraEnabled
        public DE_Stamp_Group__c stampGroup;
        @AuraEnabled
        public List<ConditionalRecord> stamps = new List<ConditionalRecord>();
    }

    private static void requireAdmin() {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'configure the classifier');
    }

    private static ConditionalRecord wrap(SObject r, List<DE_Condition__c> c) {
        ConditionalRecord cr = new ConditionalRecord();
        cr.record = r;
        cr.conditions = c == null ? new List<DE_Condition__c>() : c;
        return cr;
    }

    // ------------------------------------------------------------------ territories

    @AuraEnabled
    public static List<ConditionalRecord> getTerritories(String objectName) {
        requireAdmin();
        List<ConditionalRecord> out = new List<ConditionalRecord>();
        for (DE_Territory__c t : [
            SELECT
                Id,
                Name,
                Object_API_Name__c,
                Map__c,
                Status__c,
                Priority__c,
                Condition_Logic__c,
                Countries__c,
                States__c,
                Postal_Codes__c,
                Stamp_Field__c,
                Description__c,
                Color__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Territory__c
            WHERE Object_API_Name__c = :objectName
            WITH USER_MODE
            ORDER BY Priority__c, Name
        ]) {
            out.add(wrap(t, t.Conditions__r));
        }
        return out;
    }

    @AuraEnabled
    public static Id saveTerritory(DE_Territory__c territory, List<DE_Condition__c> conditions) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<String> errors = new List<String>();
        if (String.isBlank(territory.Name)) {
            errors.add('Enter a territory name.');
        }
        if (!DE_Schema.objectExists(territory.Object_API_Name__c)) {
            errors.add('Choose an object.');
        }
        if (territory.Priority__c == null) {
            errors.add('Enter the territory order.');
        }
        if (String.isNotBlank(territory.Color__c) && !Pattern.matches('#[0-9a-fA-F]{6}', territory.Color__c.trim())) {
            errors.add('Colour must be a hex value such as #2a78d6.');
        }
        if (String.isNotBlank(territory.Stamp_Field__c)) {
            Schema.DescribeFieldResult f = DE_Schema.field(territory.Object_API_Name__c, territory.Stamp_Field__c);
            if (f == null || !f.isUpdateable() || f.getType() != Schema.DisplayType.STRING) {
                errors.add('Stamp field must be an updateable text field.');
            }
        }
        List<DE_Condition__c> c = DE_Ui.prepare(conditions, 'Territory');
        if (errors.isEmpty() && !c.isEmpty()) {
            String err = DE_Conditions.validate(territory.Object_API_Name__c, c, territory.Condition_Logic__c);
            if (err != null) {
                errors.add(err);
            }
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            if (territory.Status__c == null) {
                territory.Status__c = 'Draft';
            }
            territory.Object_API_Name__c = DE_Schema.objectName(territory.Object_API_Name__c);
            Database.upsert(territory, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Territory__c', territory.Id, new Set<String>{ 'Territory' }, 'Territory', c);
            return territory.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteTerritory(Id territoryId) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Territory__c = :territoryId], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Territory__c(Id = territoryId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    /** Activates or returns to draft every territory of a map (blank map = default). */
    @AuraEnabled
    public static Integer setMapStatus(String objectName, String mapName, String status) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<DE_Territory__c> rows = String.isBlank(mapName)
            ? [SELECT Id FROM DE_Territory__c WHERE Object_API_Name__c = :objectName AND Map__c = NULL WITH USER_MODE]
            : [SELECT Id FROM DE_Territory__c WHERE Object_API_Name__c = :objectName AND Map__c = :mapName WITH USER_MODE];
        for (DE_Territory__c t : rows) {
            t.Status__c = status == 'Active' ? 'Active' : 'Draft';
        }
        try {
            Database.update(rows, true, AccessLevel.USER_MODE);
            return rows.size();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void reorderTerritories(List<Id> territoryIds) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<DE_Territory__c> rows = new List<DE_Territory__c>();
        Integer order = 10;
        for (Id i : territoryIds) {
            rows.add(new DE_Territory__c(Id = i, Priority__c = order));
            order += 10;
        }
        try {
            Database.update(rows, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    /**
     * Imports territories from pasted lines: Territory Name, Countries, States, Postal Codes
     * (lists inside a column separated by semicolons; columns by commas or tabs). Imported territories are Draft.
     */
    @AuraEnabled
    public static Integer importTerritories(String objectName, String mapName, String text) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        if (!DE_Schema.objectExists(objectName)) {
            throw DE_Ui.error('Choose an object.');
        }
        AggregateResult ar = [SELECT MAX(Priority__c) m FROM DE_Territory__c WHERE Object_API_Name__c = :objectName];
        Decimal order = ar.get('m') == null ? 0 : (Decimal) ar.get('m');
        List<DE_Territory__c> rows = new List<DE_Territory__c>();
        Integer lineNo = 0;
        for (String line : (text == null ? '' : text).split('\\n')) {
            lineNo++;
            if (String.isBlank(line)) {
                continue;
            }
            List<String> cols = line.split('[,\\t]');
            if (String.isBlank(cols[0])) {
                throw DE_Ui.error('Line ' + lineNo + ' has no territory name.');
            }
            order += 10;
            rows.add(
                new DE_Territory__c(
                    Name = cols[0].trim().left(80),
                    Object_API_Name__c = DE_Schema.objectName(objectName),
                    Map__c = String.isBlank(mapName) ? null : mapName,
                    Status__c = 'Draft',
                    Priority__c = order,
                    Countries__c = cols.size() > 1 ? cols[1].trim() : null,
                    States__c = cols.size() > 2 ? cols[2].trim() : null,
                    Postal_Codes__c = cols.size() > 3 ? cols[3].trim() : null
                )
            );
        }
        try {
            Database.insert(rows, true, AccessLevel.USER_MODE);
            return rows.size();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ lead matching

    @AuraEnabled
    public static List<ConditionalRecord> getMatchingRules() {
        requireAdmin();
        List<ConditionalRecord> out = new List<ConditionalRecord>();
        for (DE_Matching_Rule__c r : [
            SELECT
                Id,
                Name,
                Active__c,
                Match_Type__c,
                Priority__c,
                Match_Email_Domain__c,
                Match_Company_Name__c,
                Fuzzy_Threshold__c,
                Match_Email__c,
                Source_Field__c,
                Target_Field__c,
                Filter_Logic__c,
                Tie_Breaker_Field__c,
                Tie_Breaker_Direction__c,
                Description__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Matching_Rule__c
            WITH USER_MODE
            ORDER BY Priority__c, Name
        ]) {
            out.add(wrap(r, r.Conditions__r));
        }
        return out;
    }

    private static String targetObject(String matchType) {
        return matchType == 'Lead to Contact' ? 'Contact' : (matchType == 'Lead to Lead' ? 'Lead' : 'Account');
    }

    @AuraEnabled
    public static Id saveMatchingRule(DE_Matching_Rule__c rule, List<DE_Condition__c> conditions) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<String> errors = new List<String>();
        if (String.isBlank(rule.Name) || rule.Priority__c == null) {
            errors.add('Enter a name and order.');
        }
        if (rule.Fuzzy_Threshold__c != null && (rule.Fuzzy_Threshold__c < 50 || rule.Fuzzy_Threshold__c > 100)) {
            errors.add('Fuzzy threshold must be between 50 and 100.');
        }
        String target = targetObject(rule.Match_Type__c);
        if (String.isNotBlank(rule.Source_Field__c) && !DE_Schema.hasField('Lead', rule.Source_Field__c)) {
            errors.add('Custom lead field ' + rule.Source_Field__c + ' does not exist.');
        }
        if (String.isNotBlank(rule.Target_Field__c) && !DE_Schema.hasField(target, rule.Target_Field__c)) {
            errors.add('Custom target field ' + rule.Target_Field__c + ' does not exist on ' + target + '.');
        }
        if (String.isNotBlank(rule.Tie_Breaker_Field__c) && !DE_Schema.hasField(target, rule.Tie_Breaker_Field__c)) {
            errors.add('Order field ' + rule.Tie_Breaker_Field__c + ' does not exist on ' + target + '.');
        }
        List<DE_Condition__c> c = DE_Ui.prepare(conditions, 'Match Filter');
        if (!c.isEmpty()) {
            String err = DE_Conditions.validate(target, c, rule.Filter_Logic__c);
            if (err != null) {
                errors.add('Match filter: ' + err);
            }
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            Database.upsert(rule, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Matching_Rule__c', rule.Id, new Set<String>{ 'Match Filter' }, 'Match Filter', c);
            return rule.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteMatchingRule(Id ruleId) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Matching_Rule__c = :ruleId], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Matching_Rule__c(Id = ruleId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ auto conversion

    @AuraEnabled
    public static List<ConditionalRecord> getConversionRules() {
        requireAdmin();
        List<ConditionalRecord> out = new List<ConditionalRecord>();
        for (DE_Conversion_Rule__c r : [
            SELECT
                Id,
                Name,
                Active__c,
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
                Description__c,
                Account_Record_Type__c,
                Contact_Record_Type__c,
                Opportunity_Record_Type__c,
                Distribute_After__c,
                Overwrite_Lead_Source__c,
                Send_Email__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Conversion_Rule__c
            WITH USER_MODE
            ORDER BY Is_Default__c, Order__c, Name
        ]) {
            out.add(wrap(r, r.Conditions__r));
        }
        return out;
    }

    @AuraEnabled
    public static Id saveConversionRule(DE_Conversion_Rule__c rule, List<DE_Condition__c> conditions) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<String> errors = new List<String>();
        if (String.isBlank(rule.Name) || rule.Order__c == null) {
            errors.add('Enter a name and order.');
        }
        if (rule.Action__c == 'De-Duplicate' && rule.Match__c != 'Lead Only Match') {
            errors.add('De-Duplicate is only available with Match = Lead Only Match.');
        }
        if (rule.Owner_Source__c == 'Default User') {
            String err = DE_Ids.ownerError(rule.Default_User_Id__c, false);
            if (err != null || String.isBlank(rule.Default_User_Id__c)) {
                errors.add(err == null ? 'Choose the default user.' : err);
            }
        }
        if (
            String.isNotBlank(rule.Converted_Status__c) &&
            [SELECT COUNT() FROM LeadStatus WHERE ApiName = :rule.Converted_Status__c AND IsConverted = TRUE] == 0
        ) {
            errors.add('"' + rule.Converted_Status__c + '" is not a converted lead status.');
        }
        for (
            List<String> pair : new List<List<String>>{
                new List<String>{ 'Account', rule.Account_Field_Update__c },
                new List<String>{ 'Contact', rule.Contact_Field_Update__c },
                new List<String>{ 'Opportunity', rule.Opportunity_Field_Update__c },
                new List<String>{ 'Lead', rule.Survivor_Field_Update__c }
            }
        ) {
            String err = DE_FieldUpdates.validate(pair[0], pair[1]);
            if (err != null) {
                errors.add(pair[0] + ' field update: ' + err);
            }
        }
        for (
            List<String> pair : new List<List<String>>{
                new List<String>{ 'Account', rule.Account_Record_Type__c },
                new List<String>{ 'Contact', rule.Contact_Record_Type__c },
                new List<String>{ 'Opportunity', rule.Opportunity_Record_Type__c }
            }
        ) {
            if (String.isNotBlank(pair[1]) && DE_LeadConversion.recordTypeId(pair[0], pair[1]) == null) {
                errors.add(pair[0] + ' record type "' + pair[1] + '" does not exist or is inactive.');
            }
        }
        if (rule.Distribute_After__c == true && rule.Action__c != 'De-Duplicate') {
            errors.add('Distribute after de-duplication only applies to De-Duplicate rules.');
        }
        List<DE_Condition__c> c = DE_Ui.prepare(conditions, 'Conversion Filter');
        if (c.size() > 5) {
            errors.add('Conversion rules support at most 5 filters.');
        }
        if (!c.isEmpty()) {
            String err = DE_Conditions.validate('Lead', c, rule.Filter_Logic__c);
            if (err != null) {
                errors.add(err);
            }
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            if (rule.Is_Default__c == true) {
                List<DE_Conversion_Rule__c> others = [SELECT Id FROM DE_Conversion_Rule__c WHERE Is_Default__c = TRUE AND Id != :rule.Id WITH USER_MODE];
                for (DE_Conversion_Rule__c o : others) {
                    o.Is_Default__c = false;
                }
                Database.update(others, true, AccessLevel.USER_MODE);
            }
            Database.upsert(rule, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Conversion_Rule__c', rule.Id, new Set<String>{ 'Conversion Filter' }, 'Conversion Filter', c);
            return rule.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteConversionRule(Id ruleId) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Conversion_Rule__c = :ruleId], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Conversion_Rule__c(Id = ruleId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ stamp groups

    @AuraEnabled
    public static List<StampGroupDetail> getStampGroups(String objectName) {
        requireAdmin();
        List<StampGroupDetail> out = new List<StampGroupDetail>();
        List<DE_Stamp_Group__c> groups = [
            SELECT
                Id,
                Name,
                Object_API_Name__c,
                Active__c,
                Group_Type__c,
                Stamp_Field__c,
                Description__c,
                (SELECT Id, Name, Order__c, Condition_Logic__c, Stamp_Group__c, Active__c, Is_Default__c FROM Stamps__r ORDER BY Order__c)
            FROM DE_Stamp_Group__c
            WHERE Object_API_Name__c = :objectName
            WITH USER_MODE
            ORDER BY Name
        ];
        Set<Id> stampIds = new Set<Id>();
        for (DE_Stamp_Group__c g : groups) {
            stampIds.addAll(new Map<Id, DE_Stamp__c>(g.Stamps__r).keySet());
        }
        Map<Id, List<DE_Condition__c>> conds = new Map<Id, List<DE_Condition__c>>();
        for (DE_Condition__c c : [
            SELECT Id, Stamp__c, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c
            FROM DE_Condition__c
            WHERE Stamp__c IN :stampIds
            WITH USER_MODE
            ORDER BY Sequence__c
        ]) {
            if (!conds.containsKey(c.Stamp__c)) {
                conds.put(c.Stamp__c, new List<DE_Condition__c>());
            }
            conds.get(c.Stamp__c).add(c);
        }
        for (DE_Stamp_Group__c g : groups) {
            StampGroupDetail d = new StampGroupDetail();
            d.stampGroup = g;
            for (DE_Stamp__c s : g.Stamps__r) {
                d.stamps.add(wrap(s, conds.get(s.Id)));
            }
            out.add(d);
        }
        return out;
    }

    @AuraEnabled
    public static Id saveStampGroup(DE_Stamp_Group__c stampGroup) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        List<String> errors = new List<String>();
        if (String.isBlank(stampGroup.Name) || !DE_Schema.objectExists(stampGroup.Object_API_Name__c)) {
            errors.add('Enter a group name and object.');
        }
        if (String.isNotBlank(stampGroup.Stamp_Field__c) && !DE_Schema.hasField(stampGroup.Object_API_Name__c, stampGroup.Stamp_Field__c)) {
            errors.add('Stamp field ' + stampGroup.Stamp_Field__c + ' does not exist.');
        }
        if (stampGroup.Id == null) {
            Integer existing = [SELECT COUNT() FROM DE_Stamp_Group__c WHERE Object_API_Name__c = :stampGroup.Object_API_Name__c];
            if (existing >= 10) {
                errors.add('An object can have at most 10 stamp groups.');
            }
        }
        DE_Ui.throwIfErrors(errors);
        try {
            Database.upsert(stampGroup, true, AccessLevel.USER_MODE);
            return stampGroup.Id;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Id saveStamp(DE_Stamp__c stamp, List<DE_Condition__c> conditions) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        DE_Stamp_Group__c g = [SELECT Object_API_Name__c FROM DE_Stamp_Group__c WHERE Id = :stamp.Stamp_Group__c WITH USER_MODE];
        List<DE_Condition__c> c = DE_Ui.prepare(conditions, 'Stamp');
        List<String> errors = new List<String>();
        if (String.isBlank(stamp.Name) || stamp.Order__c == null) {
            errors.add('Enter a stamp value and order.');
        }
        if (
            stamp.Is_Default__c == true &&
            [SELECT COUNT() FROM DE_Stamp__c WHERE Stamp_Group__c = :stamp.Stamp_Group__c AND Is_Default__c = TRUE AND Id != :stamp.Id WITH USER_MODE] > 0
        ) {
            errors.add('A stamp group can have only one default stamp.');
        }
        if (!c.isEmpty()) {
            String err = DE_Conditions.validate(g.Object_API_Name__c, c, stamp.Condition_Logic__c);
            if (err != null) {
                errors.add(err);
            }
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            Database.upsert(stamp, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Stamp__c', stamp.Id, new Set<String>{ 'Stamp' }, 'Stamp', c);
            return stamp.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteStamp(Id stampId) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Stamp__c = :stampId], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Stamp__c(Id = stampId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteStampGroup(Id groupId) {
        requireAdmin();
        DE_Cache.invalidateClassifier();
        try {
            List<DE_Stamp__c> stamps = [SELECT Id FROM DE_Stamp__c WHERE Stamp_Group__c = :groupId];
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Stamp__c IN :stamps], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Stamp_Group__c(Id = groupId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ lead matching domain index

    /** Rebuilds the account domain index used by lead matching (batch). */
    @AuraEnabled
    public static Id rebuildDomainIndex() {
        requireAdmin();
        try {
            return Database.executeBatch(new DE_AccountDomainBatch(), 200);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Integer getDomainIndexSize() {
        requireAdmin();
        return [SELECT COUNT() FROM DE_Account_Domain__c WHERE Account__c != NULL WITH USER_MODE];
    }

    // ------------------------------------------------------------------ backfill

    @AuraEnabled
    public static Id runBackfill(String objectName, List<String> types, Date createdSince, Boolean emailWhenDone) {
        requireAdmin();
        if (!DE_Schema.objectExists(objectName)) {
            throw DE_Ui.error('Choose an object.');
        }
        Datetime since = createdSince == null ? null : Datetime.newInstance(createdSince, Time.newInstance(0, 0, 0, 0));
        return Database.executeBatch(new DE_BackfillBatch(objectName, types == null ? null : new Set<String>(types), since, emailWhenDone), 100);
    }

    @AuraEnabled
    public static Integer classifyRecord(Id recordId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'classify records');
        try {
            return DE_ClassifierService.classify(recordId.getSobjectType().getDescribe().getName(), new Set<Id>{ recordId }, null);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }
}
