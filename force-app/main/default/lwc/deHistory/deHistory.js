import { LightningElement, api } from 'lwc';
import getHistory from '@salesforce/apex/DE_HistoryController.getHistory';
import getTrackedObjects from '@salesforce/apex/DE_HistoryController.getTrackedObjects';
import { reduceErrors, formatDateTime } from 'c/deUtils';

const COLUMNS = [
    { label: 'Date', fieldName: 'when', initialWidth: 170 },
    { label: 'User', fieldName: 'user', initialWidth: 150 },
    { label: 'Object', fieldName: 'objectLabel', initialWidth: 150 },
    { label: 'Record', fieldName: 'Record_Name__c' },
    { label: 'Change', fieldName: 'Change_Type__c', initialWidth: 100 },
    { label: 'Field', fieldName: 'Field__c' },
    { label: 'Old value', fieldName: 'Old_Value__c', wrapText: true },
    { label: 'New value', fieldName: 'New_Value__c', wrapText: true },
    { label: 'Background', fieldName: 'Background_Change__c', type: 'boolean', initialWidth: 110 }
];

/**
 * Change history: the last 100 configuration changes, for one parent record (team, holiday region, user)
 * or across the configuration, optionally for one object type.
 */
export default class DeHistory extends LightningElement {
    @api title = 'Change History';
    @api showObjectFilter = false;

    _parentId;
    _objectName = '';
    rows = [];
    objectOptions = [];
    labels = {};
    error;
    loading = false;
    columns = COLUMNS;
    connected = false;

    @api
    get parentId() {
        return this._parentId;
    }
    set parentId(value) {
        this._parentId = value;
        if (this.connected) {
            this.load();
        }
    }

    @api
    get objectName() {
        return this._objectName;
    }
    set objectName(value) {
        this._objectName = value || '';
        if (this.connected) {
            this.load();
        }
    }

    connectedCallback() {
        this.connected = true;
        getTrackedObjects()
            .then((objs) => {
                this.labels = Object.fromEntries(objs.map((o) => [o.value, o.label]));
                this.objectOptions = [{ label: 'All objects', value: '' }, ...objs];
                this.rows = this.rows.map((r) => ({ ...r, objectLabel: this.labels[r.Object_API_Name__c] || r.Object_API_Name__c }));
            })
            .catch(() => {});
        this.load();
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleObject(event) {
        this._objectName = event.detail.value;
        this.load();
    }

    @api
    async load() {
        this.loading = true;
        try {
            const rows = await getHistory({ parentId: this._parentId || null, objectName: this._objectName || null });
            this.rows = rows.map((r) => ({
                ...r,
                when: formatDateTime(r.Changed_At__c),
                user: r.Changed_By__r ? r.Changed_By__r.Name : '',
                objectLabel: this.labels[r.Object_API_Name__c] || r.Object_API_Name__c
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }
}
