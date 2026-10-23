import { LightningElement, api } from 'lwc';
import simulate from '@salesforce/apex/DE_ConsoleController.simulate';
import { reduceErrors } from 'c/deUtils';

/** Assignment simulator: explains how a record would be routed, without changing anything. */
export default class DeSimulator extends LightningElement {
    @api recordId;
    @api compact = false;

    inputId;
    simulateAt;
    ignoreCaps = false;
    includeInactive = false;
    stopOnSuccess = false;
    running = false;
    result;
    error;

    get targetId() {
        return this.inputId || this.recordId;
    }

    get showRecordInput() {
        return !this.recordId;
    }

    get runDisabled() {
        return this.running || !this.targetId;
    }

    get rows() {
        if (!this.result) {
            return [];
        }
        return this.result.results.map((r, i) => ({
            ...r,
            key: 'res' + i,
            title: r.teamName + ' › ' + r.distributorName + ' (' + r.type + ', ' + r.method + ')' + (r.active ? '' : ' — inactive'),
            sourceLabel: r.sourcePassed === undefined || r.sourcePassed === null ? 'n/a' : r.sourcePassed ? 'PASS' : 'FAIL',
            sourceClass: r.sourcePassed ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_error',
            filterLabel: r.filtersPassed === undefined || r.filtersPassed === null ? 'n/a' : r.filtersPassed ? 'PASS' : 'FAIL',
            filterClass: r.filtersPassed ? 'slds-badge slds-theme_success' : r.filtersPassed === false ? 'slds-badge slds-theme_error' : 'slds-badge',
            assignLabel: r.assigned ? 'ASSIGN' : '—',
            assignClass: r.assigned ? 'slds-badge slds-theme_success' : 'slds-badge',
            traceLines: (r.trace || []).map((t, j) => ({ key: 't' + j, text: t }))
        }));
    }

    get hasWarnings() {
        return this.result && this.result.warnings && this.result.warnings.length > 0;
    }

    handleRecord(event) {
        this.inputId = event.target.value;
    }
    handleAt(event) {
        this.simulateAt = event.target.value;
    }
    handleIgnoreCaps(event) {
        this.ignoreCaps = event.target.checked;
    }
    handleInactive(event) {
        this.includeInactive = event.target.checked;
    }
    handleStop(event) {
        this.stopOnSuccess = event.target.checked;
    }

    async handleRun() {
        this.running = true;
        this.error = undefined;
        try {
            this.result = await simulate({
                recordId: this.targetId,
                options: {
                    simulateAt: this.simulateAt || null,
                    ignoreCaps: this.ignoreCaps,
                    includeInactive: this.includeInactive,
                    stopOnSuccess: this.stopOnSuccess
                }
            });
        } catch (e) {
            this.error = reduceErrors(e);
            this.result = undefined;
        } finally {
            this.running = false;
        }
    }
}
