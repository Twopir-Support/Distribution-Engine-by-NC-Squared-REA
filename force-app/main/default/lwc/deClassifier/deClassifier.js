import { LightningElement } from 'lwc';
import getTerritories from '@salesforce/apex/DE_ClassifierController.getTerritories';
import saveTerritory from '@salesforce/apex/DE_ClassifierController.saveTerritory';
import deleteTerritory from '@salesforce/apex/DE_ClassifierController.deleteTerritory';
import setMapStatus from '@salesforce/apex/DE_ClassifierController.setMapStatus';
import reorderTerritories from '@salesforce/apex/DE_ClassifierController.reorderTerritories';
import importTerritories from '@salesforce/apex/DE_ClassifierController.importTerritories';
import getMatchingRules from '@salesforce/apex/DE_ClassifierController.getMatchingRules';
import saveMatchingRule from '@salesforce/apex/DE_ClassifierController.saveMatchingRule';
import deleteMatchingRule from '@salesforce/apex/DE_ClassifierController.deleteMatchingRule';
import getConversionRules from '@salesforce/apex/DE_ClassifierController.getConversionRules';
import saveConversionRule from '@salesforce/apex/DE_ClassifierController.saveConversionRule';
import deleteConversionRule from '@salesforce/apex/DE_ClassifierController.deleteConversionRule';
import getStampGroups from '@salesforce/apex/DE_ClassifierController.getStampGroups';
import saveStampGroup from '@salesforce/apex/DE_ClassifierController.saveStampGroup';
import saveStamp from '@salesforce/apex/DE_ClassifierController.saveStamp';
import deleteStamp from '@salesforce/apex/DE_ClassifierController.deleteStamp';
import deleteStampGroup from '@salesforce/apex/DE_ClassifierController.deleteStampGroup';
import runBackfill from '@salesforce/apex/DE_ClassifierController.runBackfill';
import getObjectOptions from '@salesforce/apex/DE_AdminController.getObjectOptions';
import { reduceErrors, toast, toastError, cleanRecord, cleanConditions, clone, options, eventValue } from 'c/deUtils';

const MATCH_TARGET = {
    'Lead to Account': 'Account',
    'Lead to Contact': 'Contact',
    'Lead to Lead': 'Lead'
};

/** Distribution Classifier tab. */
export default class DeClassifier extends LightningElement {
    objectName = 'Lead';
    objectOptions = [];
    error;

    territories = [];
    territoryEdit;
    territoryConditions = [];
    importText = '';
    importMap = '';

    matching = [];
    matchEdit;
    matchConditions = [];

    conversions = [];
    convEdit;
    convConditions = [];

    groups = [];
    groupEdit;
    stampEdit;
    stampConditions = [];

    backfill = {
        objectName: 'Lead',
        types: ['Territory', 'Stamps', 'Match', 'Conversion'],
        since: null,
        email: true
    };

    matchTypes = options(['Lead to Account', 'Lead to Contact', 'Lead to Lead']);
    tieDirections = options(['Newest or Highest', 'Oldest or Lowest']);
    convMatches = options(['Any', 'No Match', 'Account and Contact Match', 'Account Only Match', 'Lead Only Match']);
    convActions = options(['Do Not Convert', 'Auto Convert', 'De-Duplicate']);
    convOpps = options(['Never', 'Always', 'Only When No Open Opportunity']);
    convOwners = options(['Matched Record Owner', 'Retain Lead Owner', 'Default User']);
    groupTypes = options(['Single', 'Multiple']);
    typeOptions = options(['Territory', 'Stamps', 'Match', 'Conversion']);

    connectedCallback() {
        getObjectOptions()
            .then((o) => {
                this.objectOptions = o;
            })
            .catch(() => {});
        this.loadTerritories();
    }

    fail(e) {
        this.error = reduceErrors(e);
    }

    handleObject(event) {
        this.objectName = event.detail.value;
        this.loadTerritories();
        this.loadGroups();
    }

    handleTab(event) {
        const v = event.target.value;
        if (v === 'territories') {
            this.loadTerritories();
        } else if (v === 'matching') {
            this.loadMatching();
        } else if (v === 'conversion') {
            this.loadConversions();
        } else if (v === 'stamps') {
            this.loadGroups();
        }
    }

    // ---------------------------------------------------------------- territories

    async loadTerritories() {
        try {
            const rows = await getTerritories({ objectName: this.objectName });
            this.territories = rows.map((r) => ({
                ...r,
                key: r.record.Id,
                rec: r.record,
                mapName: r.record.Map__c || 'Default map',
                badge: r.record.Status__c === 'Active' ? 'slds-badge slds-theme_success' : 'slds-badge'
            }));
            this.error = undefined;
        } catch (e) {
            this.fail(e);
        }
    }

    get maps() {
        return [...new Set(this.territories.map((t) => t.rec.Map__c || ''))].map((m) => ({ key: 'm' + m, name: m || 'Default map', value: m }));
    }

    handleNewTerritory() {
        const max = this.territories.reduce((m, t) => Math.max(m, t.rec.Priority__c || 0), 0);
        this.territoryEdit = {
            Name: '',
            Object_API_Name__c: this.objectName,
            Priority__c: max + 10,
            Status__c: 'Draft'
        };
        this.territoryConditions = [];
    }

    handleEditTerritory(event) {
        const t = this.territories.find((x) => x.key === event.currentTarget.dataset.id);
        this.territoryEdit = cleanRecord(t.rec);
        this.territoryConditions = clone(t.conditions);
    }

    handleTerritoryField(event) {
        this.territoryEdit = {
            ...this.territoryEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleTerritoryConditions(event) {
        this.territoryConditions = event.detail.conditions;
        this.territoryEdit = {
            ...this.territoryEdit,
            Condition_Logic__c: event.detail.logic
        };
    }

    async handleSaveTerritory() {
        try {
            await saveTerritory({
                territory: this.territoryEdit,
                conditions: cleanConditions(this.territoryConditions)
            });
            this.territoryEdit = null;
            toast(this, 'Territory saved', '');
            await this.loadTerritories();
        } catch (e) {
            toastError(this, e, 'Could not save territory');
        }
    }

    handleCancelTerritory() {
        this.territoryEdit = null;
    }

    async handleTerritoryAction(event) {
        const id = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;
        try {
            if (action === 'delete') {
                await deleteTerritory({ territoryId: id });
            } else {
                const ids = this.territories.map((t) => t.key);
                const i = ids.indexOf(id);
                const j = action === 'up' ? i - 1 : i + 1;
                if (j < 0 || j >= ids.length) {
                    return;
                }
                [ids[i], ids[j]] = [ids[j], ids[i]];
                await reorderTerritories({ territoryIds: ids });
            }
            await this.loadTerritories();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleMapStatus(event) {
        try {
            const n = await setMapStatus({
                objectName: this.objectName,
                mapName: event.currentTarget.dataset.map,
                status: event.currentTarget.dataset.status
            });
            toast(this, 'Map ' + event.currentTarget.dataset.status.toLowerCase(), n + ' territories updated.');
            await this.loadTerritories();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleImportText(event) {
        this.importText = event.target.value;
    }

    handleImportMap(event) {
        this.importMap = event.target.value;
    }

    async handleImport() {
        try {
            const n = await importTerritories({
                objectName: this.objectName,
                mapName: this.importMap,
                text: this.importText
            });
            toast(this, 'Imported', n + ' draft territories. Activate the map when ready.');
            this.importText = '';
            await this.loadTerritories();
        } catch (e) {
            toastError(this, e, 'Import failed');
        }
    }

    // ---------------------------------------------------------------- matching

    async loadMatching() {
        try {
            const rows = await getMatchingRules();
            this.matching = rows.map((r) => ({
                ...r,
                key: r.record.Id,
                rec: r.record
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    get matchTarget() {
        return this.matchEdit ? MATCH_TARGET[this.matchEdit.Match_Type__c] : 'Account';
    }

    get isAccountMatch() {
        return this.matchEdit && this.matchEdit.Match_Type__c === 'Lead to Account';
    }

    handleNewMatch() {
        this.matchEdit = {
            Name: '',
            Active__c: true,
            Match_Type__c: 'Lead to Account',
            Priority__c: (this.matching.length + 1) * 10,
            Match_Email_Domain__c: true,
            Match_Company_Name__c: true,
            Fuzzy_Threshold__c: 85,
            Match_Email__c: true,
            Tie_Breaker_Direction__c: 'Newest or Highest'
        };
        this.matchConditions = [];
    }

    handleEditMatch(event) {
        const r = this.matching.find((x) => x.key === event.currentTarget.dataset.id);
        this.matchEdit = cleanRecord(r.rec);
        this.matchConditions = clone(r.conditions);
    }

    handleMatchField(event) {
        this.matchEdit = {
            ...this.matchEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleMatchConditions(event) {
        this.matchConditions = event.detail.conditions;
        this.matchEdit = { ...this.matchEdit, Filter_Logic__c: event.detail.logic };
    }

    async handleSaveMatch() {
        try {
            await saveMatchingRule({
                rule: this.matchEdit,
                conditions: cleanConditions(this.matchConditions)
            });
            this.matchEdit = null;
            await this.loadMatching();
        } catch (e) {
            toastError(this, e, 'Could not save rule');
        }
    }

    async handleDeleteMatch(event) {
        try {
            await deleteMatchingRule({ ruleId: event.currentTarget.dataset.id });
            await this.loadMatching();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelMatch() {
        this.matchEdit = null;
    }

    // ---------------------------------------------------------------- conversion

    async loadConversions() {
        try {
            const rows = await getConversionRules();
            this.conversions = rows.map((r) => ({
                ...r,
                key: r.record.Id,
                rec: r.record,
                orderLabel: r.record.Is_Default__c ? 'Default (last)' : r.record.Order__c
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    get isDefaultUser() {
        return this.convEdit && this.convEdit.Owner_Source__c === 'Default User';
    }

    get isDedupe() {
        return this.convEdit && this.convEdit.Action__c === 'De-Duplicate';
    }

    handleNewConv() {
        this.convEdit = {
            Name: '',
            Active__c: true,
            Order__c: (this.conversions.length + 1) * 10,
            Match__c: 'Account Only Match',
            Action__c: 'Auto Convert',
            Create_Opportunity__c: 'Never',
            Owner_Source__c: 'Matched Record Owner',
            Copy_Blank_Fields__c: true
        };
        this.convConditions = [];
    }

    handleEditConv(event) {
        const r = this.conversions.find((x) => x.key === event.currentTarget.dataset.id);
        this.convEdit = cleanRecord(r.rec);
        this.convConditions = clone(r.conditions);
    }

    handleConvField(event) {
        this.convEdit = {
            ...this.convEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleConvUser(event) {
        this.convEdit = {
            ...this.convEdit,
            Default_User_Id__c: event.detail.value
        };
    }

    handleConvConditions(event) {
        this.convConditions = event.detail.conditions;
        this.convEdit = { ...this.convEdit, Filter_Logic__c: event.detail.logic };
    }

    async handleSaveConv() {
        try {
            await saveConversionRule({
                rule: this.convEdit,
                conditions: cleanConditions(this.convConditions)
            });
            this.convEdit = null;
            await this.loadConversions();
        } catch (e) {
            toastError(this, e, 'Could not save rule');
        }
    }

    async handleDeleteConv(event) {
        try {
            await deleteConversionRule({ ruleId: event.currentTarget.dataset.id });
            await this.loadConversions();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelConv() {
        this.convEdit = null;
    }

    // ---------------------------------------------------------------- stamp groups

    async loadGroups() {
        try {
            const rows = await getStampGroups({ objectName: this.objectName });
            this.groups = rows.map((g) => ({
                key: g.stampGroup.Id,
                rec: g.stampGroup,
                stamps: g.stamps.map((s) => ({
                    key: s.record.Id,
                    rec: s.record,
                    conditions: s.conditions,
                    count: s.conditions.length
                }))
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    handleNewGroup() {
        this.groupEdit = {
            Name: '',
            Object_API_Name__c: this.objectName,
            Active__c: true,
            Group_Type__c: 'Single'
        };
    }

    handleEditGroup(event) {
        this.groupEdit = cleanRecord(this.groups.find((g) => g.key === event.currentTarget.dataset.id).rec);
    }

    handleGroupField(event) {
        this.groupEdit = {
            ...this.groupEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    async handleSaveGroup() {
        try {
            await saveStampGroup({ stampGroup: this.groupEdit });
            this.groupEdit = null;
            await this.loadGroups();
        } catch (e) {
            toastError(this, e, 'Could not save group');
        }
    }

    async handleDeleteGroup(event) {
        try {
            await deleteStampGroup({ groupId: event.currentTarget.dataset.id });
            await this.loadGroups();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleNewStamp(event) {
        const g = this.groups.find((x) => x.key === event.currentTarget.dataset.id);
        this.stampEdit = {
            Name: '',
            Stamp_Group__c: g.key,
            Order__c: (g.stamps.length + 1) * 10
        };
        this.stampConditions = [];
    }

    handleEditStamp(event) {
        const { group, id } = event.currentTarget.dataset;
        const s = this.groups.find((g) => g.key === group).stamps.find((x) => x.key === id);
        this.stampEdit = cleanRecord(s.rec);
        this.stampConditions = clone(s.conditions);
    }

    handleStampField(event) {
        this.stampEdit = {
            ...this.stampEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleStampConditions(event) {
        this.stampConditions = event.detail.conditions;
        this.stampEdit = {
            ...this.stampEdit,
            Condition_Logic__c: event.detail.logic
        };
    }

    async handleSaveStamp() {
        try {
            await saveStamp({
                stamp: this.stampEdit,
                conditions: cleanConditions(this.stampConditions)
            });
            this.stampEdit = null;
            await this.loadGroups();
        } catch (e) {
            toastError(this, e, 'Could not save stamp');
        }
    }

    async handleDeleteStamp(event) {
        try {
            await deleteStamp({ stampId: event.currentTarget.dataset.id });
            await this.loadGroups();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelGroup() {
        this.groupEdit = null;
        this.stampEdit = null;
    }

    // ---------------------------------------------------------------- backfill

    handleBackfillField(event) {
        this.backfill = {
            ...this.backfill,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    async handleBackfill() {
        try {
            const jobId = await runBackfill({
                objectName: this.backfill.objectName,
                types: this.backfill.types,
                createdSince: this.backfill.since,
                emailWhenDone: this.backfill.email
            });
            toast(this, 'Backfill started', 'Batch job ' + jobId + '. You will get an email when it finishes.');
        } catch (e) {
            toastError(this, e, 'Could not start backfill');
        }
    }
}
