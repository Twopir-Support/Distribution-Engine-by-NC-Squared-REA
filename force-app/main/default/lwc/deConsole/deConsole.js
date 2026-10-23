import { LightningElement } from 'lwc';
import getMonitoring from '@salesforce/apex/DE_ConsoleController.getMonitoring';
import startScheduler from '@salesforce/apex/DE_ConsoleController.startScheduler';
import stopScheduler from '@salesforce/apex/DE_ConsoleController.stopScheduler';
import runHealthCheck from '@salesforce/apex/DE_ConsoleController.runHealthCheck';
import scheduleHealthChecker from '@salesforce/apex/DE_ConsoleController.scheduleHealthChecker';
import getTodaysDistributions from '@salesforce/apex/DE_ConsoleController.getTodaysDistributions';
import getSources from '@salesforce/apex/DE_ConsoleController.getSources';
import getArchived from '@salesforce/apex/DE_ConsoleController.getArchived';
import restoreArchived from '@salesforce/apex/DE_ConsoleController.restoreArchived';
import { reduceErrors, toast, toastError, formatDateTime, options } from 'c/deUtils';

const TODAY_COLUMNS = [
    { label: 'Team', fieldName: 'teamName' },
    { label: 'Object', fieldName: 'objectName', initialWidth: 110 },
    {
        label: 'Distributions',
        fieldName: 'distributions',
        type: 'number',
        initialWidth: 120
    },
    {
        label: 'SLA alerts',
        fieldName: 'slaAlerts',
        type: 'number',
        initialWidth: 110
    },
    {
        label: 'Reassignments',
        fieldName: 'reassignments',
        type: 'number',
        initialWidth: 130
    },
    {
        label: 'Rejections',
        fieldName: 'rejections',
        type: 'number',
        initialWidth: 110
    },
    {
        label: 'Errors / on hold',
        fieldName: 'errors',
        type: 'number',
        initialWidth: 140
    },
    { label: 'Available', fieldName: 'availableLabel', initialWidth: 110 }
];
const SOURCE_COLUMNS = [
    { label: 'Team', fieldName: 'teamName' },
    {
        label: 'Order',
        fieldName: 'distributorOrder',
        type: 'number',
        initialWidth: 80
    },
    { label: 'Distributor', fieldName: 'distributorName' },
    { label: 'Type', fieldName: 'type', initialWidth: 100 },
    { label: 'Object', fieldName: 'objectName', initialWidth: 110 },
    { label: 'Source', fieldName: 'source' },
    { label: 'Waiting', fieldName: 'waiting', type: 'number', initialWidth: 100 },
    { label: 'Active', fieldName: 'active', type: 'boolean', initialWidth: 80 }
];
const ARCHIVE_COLUMNS = [
    {
        label: 'Record',
        fieldName: 'url',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' } }
    },
    { label: 'Archived', fieldName: 'archivedAtLabel' },
    { label: 'Source queue', fieldName: 'sourceQueue' }
];

/** Distribution Console tab. */
export default class DeConsole extends LightningElement {
    monitoring;
    today = [];
    sources = [];
    archived = [];
    archiveObject = 'Lead';
    selectedArchived = [];
    todayColumns = TODAY_COLUMNS;
    sourceColumns = SOURCE_COLUMNS;
    archiveColumns = ARCHIVE_COLUMNS;
    archiveObjects = options(['Lead', 'Case']);
    healthOptions = [
        { label: 'Every 15 minutes', value: '15' },
        { label: 'Every 30 minutes', value: '30' },
        { label: 'Hourly', value: '60' }
    ];
    healthEvery = '60';
    error;

    connectedCallback() {
        this.loadMonitoring();
        this.loadToday();
    }

    async loadMonitoring() {
        try {
            this.monitoring = await getMonitoring();
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    async loadToday() {
        try {
            const rows = await getTodaysDistributions();
            this.today = rows.map((r) => ({
                ...r,
                availableLabel: r.available + ' of ' + r.members
            }));
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    async loadSources() {
        try {
            this.sources = await getSources();
        } catch (e) {
            toastError(this, e);
        }
    }

    async loadArchived() {
        try {
            const rows = await getArchived({ objectName: this.archiveObject });
            this.archived = rows.map((r) => ({
                ...r,
                url: '/' + r.id,
                archivedAtLabel: formatDateTime(r.archivedAt)
            }));
        } catch (e) {
            toastError(this, e);
        }
    }

    handleTab(event) {
        const v = event.target.value;
        if (v === 'sources') {
            this.loadSources();
        } else if (v === 'archive') {
            this.loadArchived();
        } else if (v === 'today') {
            this.loadToday();
        } else if (v === 'monitoring') {
            this.loadMonitoring();
        }
    }

    get statusClass() {
        const s = this.monitoring ? this.monitoring.schedulerStatus : '';
        if (s === 'Running') {
            return 'slds-badge slds-theme_success';
        }
        if (s === 'Errored') {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge slds-theme_warning';
    }

    get lastRun() {
        return this.monitoring ? formatDateTime(this.monitoring.lastRunAt) : '';
    }

    get lastClassifier() {
        return this.monitoring ? formatDateTime(this.monitoring.lastClassifierRun) : '';
    }

    get healthLabel() {
        return this.monitoring && this.monitoring.healthCheckerScheduled ? 'Scheduled' : 'Not scheduled';
    }

    async handleStart() {
        try {
            const started = await startScheduler();
            toast(this, 'Scheduler', started ? 'Scheduler started and health checker scheduled.' : 'The scheduler is already running.');
            await this.loadMonitoring();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleStop() {
        try {
            const n = await stopScheduler();
            toast(this, 'Scheduler stopped', n + ' queued job(s) aborted.', 'warning');
            await this.loadMonitoring();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleHealth() {
        try {
            toast(this, 'Health check', await runHealthCheck(), 'info');
            await this.loadMonitoring();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleHealthEvery(event) {
        this.healthEvery = event.detail.value;
    }

    async handleScheduleHealth() {
        try {
            await scheduleHealthChecker({
                everyMinutes: parseInt(this.healthEvery, 10)
            });
            toast(this, 'Health checker scheduled', '');
            await this.loadMonitoring();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleArchiveObject(event) {
        this.archiveObject = event.detail.value;
        this.loadArchived();
    }

    handleArchiveSelect(event) {
        this.selectedArchived = event.detail.selectedRows.map((r) => r.id);
    }

    async handleRestore() {
        try {
            const n = await restoreArchived({ recordIds: this.selectedArchived });
            toast(this, 'Restored', n + ' records returned to their source queues.');
            await this.loadArchived();
        } catch (e) {
            toastError(this, e);
        }
    }
}
