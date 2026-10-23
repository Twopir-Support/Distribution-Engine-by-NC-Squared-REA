import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getRecordState from '@salesforce/apex/DE_RecordDetailController.getRecordState';
import getManualOptions from '@salesforce/apex/DE_RecordDetailController.getManualOptions';
import assignManually from '@salesforce/apex/DE_RecordDetailController.assignManually';
import rejectRecord from '@salesforce/apex/DE_RecordDetailController.reject';
import distributeNow from '@salesforce/apex/DE_RecordDetailController.distributeNow';
import { reduceErrors, toast, toastError, options, formatDateTime } from 'c/deUtils';

const HISTORY_COLUMNS = [
    { label: 'Date', fieldName: 'when', type: 'text', initialWidth: 160 },
    { label: 'Status', fieldName: 'Status__c', type: 'text', initialWidth: 100 },
    { label: 'Assignee', fieldName: 'assignee', type: 'text' },
    { label: 'Team / Distributor', fieldName: 'where', type: 'text' },
    { label: 'Method', fieldName: 'method', type: 'text' },
    { label: 'SLA', fieldName: 'SLA_Status__c', type: 'text', initialWidth: 90 },
    { label: 'Note', fieldName: 'note', type: 'text', wrapText: true }
];

/** Record page component: distribution status, history, manual assignment, rejection, distribute now and simulation. */
export default class DeRecordDetail extends LightningElement {
    @api recordId;
    state;
    error;
    busy = false;
    panel; // 'assign' | 'reject' | 'simulate'
    manualOptions = [];
    selectedDistributor;
    selectedMember;
    rejectReason;
    rejectOther;
    columns = HISTORY_COLUMNS;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.state = await getRecordState({ recordId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get current() {
        return this.state && this.state.current;
    }

    get summary() {
        const c = this.current;
        if (!c) {
            return 'Not distributed yet';
        }
        return (
            'Assigned to ' +
            (c.Assigned_User__r ? c.Assigned_User__r.Name : c.Assignee_Id__c) +
            ' by ' +
            (c.Team__r ? c.Team__r.Name : '') +
            (c.Distributor__r ? ' / ' + c.Distributor__r.Name : '') +
            ' on ' +
            formatDateTime(c.Assigned_At__c)
        );
    }

    get facts() {
        const out = [];
        const c = this.current;
        const d = this.state && this.state.details;
        if (c) {
            out.push({
                key: 'sla',
                label: 'SLA',
                value: c.SLA_Status__c + (c.Next_SLA_Check__c ? ' · next check ' + formatDateTime(c.Next_SLA_Check__c) : '')
            });
            if (c.Time_To_Action_Mins__c !== undefined && c.Time_To_Action_Mins__c !== null) {
                out.push({
                    key: 'tta',
                    label: 'Time to action',
                    value: c.Time_To_Action_Mins__c + ' min'
                });
            }
            if (c.Speed_To_Assign_Seconds__c !== undefined && c.Speed_To_Assign_Seconds__c !== null) {
                out.push({
                    key: 'sta',
                    label: 'Speed to assign',
                    value: c.Speed_To_Assign_Seconds__c + ' s'
                });
            }
        }
        if (d) {
            if (d.Territory_Name__c) {
                out.push({
                    key: 'ter',
                    label: 'Territory',
                    value: d.Territory_Name__c
                });
            }
            if (d.Stamps__c) {
                out.push({ key: 'stp', label: 'Stamps', value: d.Stamps__c });
            }
            if (d.Match_Confidence__c) {
                const name = d.Matched_Account__r
                    ? d.Matched_Account__r.Name
                    : d.Matched_Contact__r
                      ? d.Matched_Contact__r.Name
                      : d.Matched_Lead__r
                        ? d.Matched_Lead__r.Name
                        : '';
                out.push({
                    key: 'mat',
                    label: 'Match',
                    value: name + ' · ' + d.Match_Confidence__c
                });
            }
            if (d.Conversion_Result__c) {
                out.push({
                    key: 'con',
                    label: 'Conversion',
                    value: d.Conversion_Result__c
                });
            }
            if (d.On_Hold_Until__c) {
                out.push({
                    key: 'hold',
                    label: 'On hold until',
                    value: formatDateTime(d.On_Hold_Until__c)
                });
            }
            if (d.Last_Error__c) {
                out.push({ key: 'err', label: 'Last issue', value: d.Last_Error__c });
            }
        }
        return out;
    }

    get history() {
        return (this.state ? this.state.history : []).map((l) => ({
            ...l,
            when: formatDateTime(l.Assigned_At__c),
            assignee: l.Assigned_User__r ? l.Assigned_User__r.Name : l.Assignee_Id__c,
            where: (l.Team__r ? l.Team__r.Name : '') + (l.Distributor__r ? ' / ' + l.Distributor__r.Name : ''),
            method: (l.Method__c || '') + (l.Is_Sticky__c ? ' (sticky)' : '') + (l.Type__c ? ' · ' + l.Type__c : ''),
            note: l.Reject_Reason__c ? 'Rejected: ' + l.Reject_Reason__c : l.Message__c
        }));
    }

    get hasHistory() {
        return this.history.length > 0;
    }

    get showAssign() {
        return this.panel === 'assign';
    }
    get showReject() {
        return this.panel === 'reject';
    }
    get showSimulate() {
        return this.panel === 'simulate';
    }

    get distributorOptions() {
        return this.manualOptions.map((t) => ({
            label: t.teamName + ' / ' + t.distributorName,
            value: t.distributorId
        }));
    }

    get memberRows() {
        const t = this.manualOptions.find((o) => o.distributorId === this.selectedDistributor);
        return t
            ? t.members.map((m) => ({
                  ...m,
                  selected: m.memberId === this.selectedMember,
                  rowClass: m.memberId === this.selectedMember ? 'slds-theme_shade member-row' : 'member-row',
                  badgeClass: m.available ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_warning'
              }))
            : [];
    }

    get rejectOptions() {
        const base = this.state ? options(this.state.rejectReasons) : [];
        return this.state && this.state.allowOtherReason ? [...base, { label: 'Other…', value: '__other__' }] : base;
    }

    get rejectIsOther() {
        return this.rejectReason === '__other__';
    }

    get assignDisabled() {
        return this.busy || !this.selectedDistributor || !this.selectedMember;
    }

    async handleOpenAssign() {
        this.panel = this.panel === 'assign' ? null : 'assign';
        if (this.panel === 'assign') {
            try {
                this.manualOptions = await getManualOptions({
                    recordId: this.recordId
                });
                if (!this.manualOptions.length) {
                    toast(this, 'No manual distributor', 'No active team has a Manual distributor for this object.', 'warning');
                }
            } catch (e) {
                toastError(this, e);
            }
        }
    }

    handleDistributor(event) {
        this.selectedDistributor = event.detail.value;
        this.selectedMember = null;
    }

    handlePickMember(event) {
        this.selectedMember = event.currentTarget.dataset.id;
    }

    async handleAssign() {
        this.busy = true;
        try {
            await assignManually({
                recordId: this.recordId,
                distributorId: this.selectedDistributor,
                memberId: this.selectedMember
            });
            toast(this, 'Assigned', 'The record was assigned.');
            this.panel = null;
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not assign');
        } finally {
            this.busy = false;
        }
    }

    handleOpenReject() {
        this.panel = this.panel === 'reject' ? null : 'reject';
    }

    handleRejectReason(event) {
        this.rejectReason = event.detail.value;
    }

    handleRejectOther(event) {
        this.rejectOther = event.target.value;
    }

    async handleReject() {
        this.busy = true;
        try {
            await rejectRecord({
                recordId: this.recordId,
                reason: this.rejectIsOther ? this.rejectOther : this.rejectReason
            });
            toast(this, 'Rejected', 'The record was handed back.');
            this.panel = null;
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not reject');
        } finally {
            this.busy = false;
        }
    }

    async handleDistribute() {
        this.busy = true;
        try {
            const message = await distributeNow({ recordId: this.recordId });
            toast(this, 'Distribute now', message, message.startsWith('Assigned') ? 'success' : 'info');
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not distribute');
        } finally {
            this.busy = false;
        }
    }

    handleOpenSimulate() {
        this.panel = this.panel === 'simulate' ? null : 'simulate';
    }
}
