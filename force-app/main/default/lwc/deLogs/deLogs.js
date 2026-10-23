import { LightningElement } from 'lwc';
import getLogs from '@salesforce/apex/DE_ConsoleController.getLogs';
import getLogTrace from '@salesforce/apex/DE_ConsoleController.getLogTrace';
import retry from '@salesforce/apex/DE_ConsoleController.retry';
import retryAll from '@salesforce/apex/DE_ConsoleController.retryAll';
import getRunLogs from '@salesforce/apex/DE_ConsoleController.getRunLogs';
import { reduceErrors, toast, toastError, formatDateTime, options, eventValue } from 'c/deUtils';

const COLUMNS = [
    { label: 'Assignment date', fieldName: 'when', initialWidth: 170 },
    {
        label: 'Record',
        fieldName: 'url',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Record_Name__c' } }
    },
    { label: 'Status', fieldName: 'Status__c', initialWidth: 100 },
    { label: 'Object', fieldName: 'Object_API_Name__c', initialWidth: 100 },
    { label: 'Team', fieldName: 'team' },
    { label: 'Distributor', fieldName: 'distributor' },
    { label: 'Method', fieldName: 'method' },
    { label: 'Assignee', fieldName: 'assignee' },
    {
        label: 'Speed (s)',
        fieldName: 'Speed_To_Assign_Seconds__c',
        type: 'number',
        initialWidth: 90
    },
    { label: 'SLA', fieldName: 'SLA_Status__c', initialWidth: 90 },
    {
        label: 'Time to action (min)',
        fieldName: 'Time_To_Action_Mins__c',
        type: 'number',
        initialWidth: 120
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Decision trace', name: 'trace' },
                { label: 'Retry', name: 'retry' }
            ]
        }
    }
];
const RUN_COLUMNS = [
    { label: 'Started', fieldName: 'when', initialWidth: 170 },
    { label: 'Process', fieldName: 'Process__c', initialWidth: 130 },
    { label: 'Status', fieldName: 'Status__c', initialWidth: 90 },
    {
        label: 'Processed',
        fieldName: 'Records_Processed__c',
        type: 'number',
        initialWidth: 100
    },
    {
        label: 'Assignments',
        fieldName: 'Assignments__c',
        type: 'number',
        initialWidth: 110
    },
    { label: 'Errors', fieldName: 'Errors__c', type: 'number', initialWidth: 80 },
    {
        label: 'Duration (ms)',
        fieldName: 'Duration_Ms__c',
        type: 'number',
        initialWidth: 110
    },
    { label: 'Message', fieldName: 'Message__c', wrapText: true }
];

/** Distribution Logs tab: distribution logs with filters, trace, retry; engine run logs. */
export default class DeLogs extends LightningElement {
    filter = {
        fromDate: null,
        toDate: null,
        status: '',
        objectName: '',
        search: ''
    };
    rows = [];
    runs = [];
    columns = COLUMNS;
    runColumns = RUN_COLUMNS;
    statusOptions = [{ label: 'All', value: '' }, ...options(['Assigned', 'SLA Alert', 'Reassigned', 'Rejected', 'On Hold', 'Error'])];
    processOptions = [
        { label: 'All', value: '' },
        ...options(['Scheduler', 'Classifier', 'SLA Monitor', 'Object Sync', 'Archive', 'Health Checker', 'Dynamic Members', 'Purge'])
    ];
    process = '';
    selected = [];
    trace;
    error;
    loading = false;

    connectedCallback() {
        const today = new Date();
        const week = new Date(today.getTime() - 7 * 86400000);
        this.filter = {
            ...this.filter,
            fromDate: week.toISOString().slice(0, 10),
            toDate: today.toISOString().slice(0, 10)
        };
        this.load();
    }

    handleFilter(event) {
        this.filter = {
            ...this.filter,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    async load() {
        this.loading = true;
        try {
            const f = { ...this.filter };
            Object.keys(f).forEach((k) => {
                if (f[k] === '') {
                    f[k] = null;
                }
            });
            const logs = await getLogs({ filter: f });
            this.rows = logs.map((l) => ({
                ...l,
                when: formatDateTime(l.Assigned_At__c),
                url: l.Record_Id__c ? '/' + l.Record_Id__c : null,
                team: l.Team__r ? l.Team__r.Name : '',
                distributor: l.Distributor__r ? l.Distributor__r.Name : '',
                method: (l.Method__c || '') + (l.Is_Sticky__c ? ' (sticky)' : ''),
                assignee: l.Assigned_User__r ? l.Assigned_User__r.Name : l.Assignee_Id__c
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    get count() {
        return this.rows.length;
    }

    handleSelect(event) {
        this.selected = event.detail.selectedRows.map((r) => r.Record_Id__c);
    }

    async handleRowAction(event) {
        const row = event.detail.row;
        if (event.detail.action.name === 'trace') {
            try {
                const l = await getLogTrace({ logId: row.Id });
                this.trace = {
                    title: l.Name + ' · ' + row.Record_Name__c,
                    text: l.Decision_Trace__c || l.Message__c || 'No trace recorded.'
                };
            } catch (e) {
                toastError(this, e);
            }
        } else {
            await this.doRetry([row.Record_Id__c]);
        }
    }

    handleCloseTrace() {
        this.trace = null;
    }

    async handleRetrySelected() {
        await this.doRetry(this.selected);
    }

    async doRetry(ids) {
        try {
            const n = await retry({ recordIds: ids });
            toast(this, 'Retry', n + ' of ' + ids.length + ' records assigned now. The rest stay at their source for the next run.');
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleRetryAll() {
        try {
            const n = await retryAll();
            toast(this, 'Retry all', n + ' records released from hold for the next scheduler run.');
        } catch (e) {
            toastError(this, e);
        }
    }

    handleProcess(event) {
        this.process = event.detail.value;
        this.loadRuns();
    }

    async loadRuns() {
        try {
            const runs = await getRunLogs({ process: this.process });
            this.runs = runs.map((r) => ({
                ...r,
                when: formatDateTime(r.Started_At__c)
            }));
        } catch (e) {
            toastError(this, e);
        }
    }
}
