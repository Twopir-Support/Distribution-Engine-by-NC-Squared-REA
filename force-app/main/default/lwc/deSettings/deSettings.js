import { LightningElement } from 'lwc';
import getSettings from '@salesforce/apex/DE_SettingsController.getSettings';
import saveSettings from '@salesforce/apex/DE_SettingsController.saveSettings';
import exportConfiguration from '@salesforce/apex/DE_SettingsController.exportConfiguration';
import importConfiguration from '@salesforce/apex/DE_SettingsController.importConfiguration';
import { reduceErrors, toast, toastError, cleanRecord, options, eventValue } from 'c/deUtils';

const DEFAULTS = {
    Engine_Enabled__c: true,
    Scheduler_Interval_Minutes__c: 1,
    Records_Per_Run__c: 500,
    Classifier_Enabled__c: true,
    Classifier_Objects__c: 'Lead,Case,Account,Contact,Opportunity',
    Distribute_After_Classify__c: true,
    Trigger_Distribution_Enabled__c: true,
    Previous_Assignees_Tracked__c: 1,
    Hold_After_Failures__c: 10,
    Hold_Minutes__c: 60,
    Log_Retention_Days__c: 30,
    Decision_Trace_Enabled__c: true,
    Reject_Reasons__c: 'Not my territory,Duplicate,Insufficient information,Workload',
    Allow_Other_Reject_Reason__c: true,
    Toggle_Reasons__c: 'Meeting,Break,Lunch,Training,End of shift',
    Timer_Durations__c: '15,30,60,120',
    Toggle_At_Start_Of_Day__c: 'No Change',
    Toggle_At_End_Of_Day__c: 'No Change',
    Count_Pull_As_Hit__c: true,
    Count_Manual_As_Hit__c: false,
    Count_Sticky_In_Balance__c: true,
    Count_Lookup_In_Balance__c: true,
    Archive_After_Days__c: 90,
    Publish_Platform_Events__c: true,
    Default_Weekday_Start__c: 'Monday',
    History_Retention_Days__c: 90,
    Classifier_Log_Retention_Days__c: 30,
    Failure_Alert_Threshold__c: 5,
    Use_Platform_Cache__c: true
};

/** Distribution Settings tab. */
export default class DeSettings extends LightningElement {
    s = {};
    error;
    saving = false;
    importText = '';
    importResult;
    dayRules = options(['No Change', 'Always On', 'Always Off']);
    weekStarts = options(['Monday', 'Sunday']);

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            const raw = cleanRecord(await getSettings());
            const merged = { ...DEFAULTS };
            Object.keys(raw).forEach((k) => {
                if (raw[k] !== null && raw[k] !== undefined) {
                    merged[k] = raw[k];
                }
            });
            this.s = merged;
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    handleField(event) {
        const v = eventValue(event);
        this.s = { ...this.s, [event.target.dataset.field]: v === '' ? null : v };
    }

    handleArchiveQueue(event) {
        this.s = { ...this.s, Archive_Queue_Id__c: event.detail.value };
    }

    async handleSave() {
        this.saving = true;
        try {
            const record = { ...this.s };
            delete record.Id;
            delete record.SetupOwnerId;
            await saveSettings({ settings: record });
            toast(this, 'Settings saved', '');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save settings');
        } finally {
            this.saving = false;
        }
    }

    async handleExport() {
        try {
            const json = await exportConfiguration();
            const link = document.createElement('a');
            link.href = 'data:application/json;charset=utf-8,' + encodeURIComponent(json);
            link.download = 'distribution-engine-configuration.json';
            link.click();
        } catch (e) {
            toastError(this, e, 'Export failed');
        }
    }

    handleImportText(event) {
        this.importText = event.target.value;
    }

    handleFile(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            this.importText = reader.result;
        };
        reader.readAsText(file);
    }

    async handleImport() {
        try {
            const counts = await importConfiguration({ json: this.importText });
            this.importResult = Object.keys(counts)
                .map((k) => k + ': ' + counts[k])
                .join(' · ');
            toast(this, 'Import complete', 'Imported teams are inactive and territories are Draft. ' + this.importResult);
        } catch (e) {
            toastError(this, e, 'Import failed');
        }
    }
}
