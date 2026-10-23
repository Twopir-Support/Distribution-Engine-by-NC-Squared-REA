import { LightningElement } from 'lwc';
import getClassifierLogs from '@salesforce/apex/DE_ConsoleController.getClassifierLogs';
import retryClassification from '@salesforce/apex/DE_ConsoleController.retryClassification';
import { reduceErrors, toast, toastError, formatDateTime, recordUrl, eventValue } from 'c/deUtils';

const TYPES = [
    { label: 'Territories', value: 'Territory' },
    { label: 'Lead Matching', value: 'Match' },
    { label: 'Auto Conversion', value: 'Conversion' },
    { label: 'Custom Classification', value: 'Stamps' },
    { label: 'Object Sync', value: 'Object Sync' }
];

const BASE = [
    { label: 'Date', fieldName: 'when', initialWidth: 170 },
    { label: 'Name', fieldName: 'url', type: 'url', typeAttributes: { label: { fieldName: 'recordName' } } },
    { label: 'Status', fieldName: 'status', initialWidth: 90, cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'Object', fieldName: 'objectName', initialWidth: 110 }
];
const TAIL = [
    { label: 'Attempts', fieldName: 'attempts', type: 'number', initialWidth: 90 },
    { label: 'Error', fieldName: 'error', wrapText: true }
];
const COLUMNS = {
    Territory: [
        ...BASE,
        { label: 'Territory', fieldName: 'territory' },
        { label: 'Matched level', fieldName: 'matchLevel', initialWidth: 120 },
        { label: 'Cleaned territory data', fieldName: 'cleaned' },
        ...TAIL
    ],
    Match: [
        ...BASE,
        { label: 'Matched account', fieldName: 'matchedAccount' },
        { label: 'Matched contact', fieldName: 'matchedContact' },
        { label: 'Matched lead', fieldName: 'matchedLead' },
        { label: 'Account rule', fieldName: 'accountRule' },
        { label: 'Confidence', fieldName: 'accountConfidence' },
        { label: 'Lead rule', fieldName: 'leadRule' },
        ...TAIL
    ],
    Conversion: [
        ...BASE,
        { label: 'Type', fieldName: 'result', initialWidth: 120 },
        { label: 'Rule', fieldName: 'rule' },
        { label: 'Opportunity created', fieldName: 'opportunityCreated', type: 'boolean', initialWidth: 120 },
        { label: 'Assignee', fieldName: 'assignee' },
        { label: 'Converted into', fieldName: 'targets', wrapText: true },
        ...TAIL
    ],
    Stamps: [...BASE, { label: 'Stamps', fieldName: 'stamps', wrapText: true }, ...TAIL],
    'Object Sync': [
        ...BASE,
        { label: 'Number of actions', fieldName: 'actionCount', type: 'number', initialWidth: 110 },
        { label: 'Team', fieldName: 'teamName' },
        { label: 'Assignee', fieldName: 'assignee' },
        { label: 'Actions performed', fieldName: 'actions', wrapText: true },
        { label: 'Records synced', fieldName: 'synced', type: 'number', initialWidth: 110 },
        { label: 'Error', fieldName: 'error', wrapText: true }
    ]
};

/** Territory, Lead Matching, Auto Conversion, Custom Classification and Object Sync logs. */
export default class DeClassifierLogs extends LightningElement {
    typeOptions = TYPES;
    filter = { logType: 'Territory', fromDate: null, toDate: null, objectName: '', errorsOnly: false, search: '' };
    rows = [];
    selected = [];
    error;
    loading = false;

    connectedCallback() {
        const today = new Date();
        this.filter = {
            ...this.filter,
            fromDate: new Date(today.getTime() - 7 * 86400000).toISOString().slice(0, 10),
            toDate: today.toISOString().slice(0, 10)
        };
        this.load();
    }

    get columns() {
        return COLUMNS[this.filter.logType];
    }

    get canRetry() {
        return this.filter.logType !== 'Object Sync';
    }

    get count() {
        return this.rows.length;
    }

    handleType(event) {
        this.filter = { ...this.filter, logType: event.detail.value };
        this.selected = [];
        this.load();
    }

    handleFilter(event) {
        this.filter = { ...this.filter, [event.target.dataset.field]: eventValue(event) };
    }

    handleSelect(event) {
        this.selected = event.detail.selectedRows.map((r) => r.recordId);
    }

    async load() {
        this.loading = true;
        try {
            const rows = await getClassifierLogs({ filter: { ...this.filter } });
            this.rows = rows.map((r) => ({
                ...r,
                when: formatDateTime(r.processedAt),
                url: recordUrl(r.recordId),
                recordName: r.recordName || r.recordId,
                statusClass: r.status === 'Error' ? 'slds-text-color_error' : ''
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    async handleRetry() {
        if (!this.selected.length) {
            toast(this, 'Nothing selected', 'Select the records to classify again.', 'info');
            return;
        }
        try {
            const n = await retryClassification({ recordIds: this.selected, logType: this.filter.logType });
            toast(this, 'Classified again', n + ' records processed.');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Retry failed');
        }
    }
}
