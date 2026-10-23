/**
 * Distribution Settings tab: org settings and configuration export/import (JSON).
 */
public with sharing class DE_SettingsController {
    @AuraEnabled
    public static DE_Settings__c getSettings() {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'view Distribution Settings');
        DE_Settings__c s = DE_Settings__c.getOrgDefaults();
        return s == null ? new DE_Settings__c() : s;
    }

    @AuraEnabled
    public static void saveSettings(DE_Settings__c settings) {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'change Distribution Settings');
        List<String> errors = new List<String>();
        if (settings.Scheduler_Interval_Minutes__c != null && (settings.Scheduler_Interval_Minutes__c < 1 || settings.Scheduler_Interval_Minutes__c > 10)) {
            errors.add('Scheduler interval must be between 1 and 10 minutes.');
        }
        if (settings.Records_Per_Run__c != null && (settings.Records_Per_Run__c < 1 || settings.Records_Per_Run__c > 2000)) {
            errors.add('Records per run must be between 1 and 2000.');
        }
        if (settings.Previous_Assignees_Tracked__c != null && (settings.Previous_Assignees_Tracked__c < 0 || settings.Previous_Assignees_Tracked__c > 50)) {
            errors.add('Previous assignees tracked must be between 0 and 50.');
        }
        if (settings.Archive_Enabled__c == true) {
            String err = DE_Ids.ownerError(settings.Archive_Queue_Id__c, true);
            if (err != null || !DE_Ids.isQueue(settings.Archive_Queue_Id__c)) {
                errors.add('Choose the archive queue.');
            }
        }
        for (String rule : new List<String>{ settings.Toggle_At_Start_Of_Day__c, settings.Toggle_At_End_Of_Day__c }) {
            if (String.isNotBlank(rule) && !new Set<String>{ 'No Change', 'Always On', 'Always Off' }.contains(rule)) {
                errors.add('Start and end of day toggles must be No Change, Always On or Always Off.');
            }
        }
        if (String.isNotBlank(settings.Classifier_Objects__c)) {
            for (String o : settings.Classifier_Objects__c.split(',')) {
                if (!DE_Schema.objectExists(o.trim())) {
                    errors.add('Classifier object ' + o.trim() + ' does not exist.');
                }
            }
        }
        DE_Ui.throwIfErrors(errors);
        try {
            DE_Settings__c existing = DE_Settings__c.getOrgDefaults();
            settings.Id = existing == null ? null : existing.Id;
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            Database.upsert(settings, true, AccessLevel.USER_MODE);
            DE_Settings.setForTransaction(settings);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ export / import

    @AuraEnabled
    public static String exportConfiguration() {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'export configuration');
        try {
            return DE_ConfigTransfer.exportJson();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Map<String, Integer> importConfiguration(String json) {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'import configuration');
        Savepoint sp = Database.setSavepoint();
        try {
            return DE_ConfigTransfer.importJson(json);
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }
}
