import { LightningElement } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';
import getState from '@salesforce/apex/DE_WidgetController.getState';
import toggle from '@salesforce/apex/DE_WidgetController.toggle';
import pull from '@salesforce/apex/DE_WidgetController.pull';
import reject from '@salesforce/apex/DE_WidgetController.reject';
import createOutOfOffice from '@salesforce/apex/DE_WidgetController.createOutOfOffice';
import { reduceErrors, toast, toastError, options, minutesUntil, recordUrl } from 'c/deUtils';

const CHANNEL = '/event/DE_Assignment_Event__e';
const POLL_MS = 15000;

/** Distribution Engine widget for the utility bar. */
export default class DeWidget extends LightningElement {
    state;
    error;
    busy = false;
    showOffline = false;
    offlineReason;
    offlineMinutes;
    showOoo = false;
    ooo = { start: null, end: null, reason: null, allDay: false };
    rejectingId;
    rejectReason;
    rejectOther;
    showMissed = false;
    subscription;
    pollTimer;

    connectedCallback() {
        this.refresh();
        onError(() => this.startPolling());
        subscribe(CHANNEL, -1, (message) => this.handleEvent(message))
            .then((s) => {
                this.subscription = s;
            })
            .catch(() => this.startPolling());
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
        }
        clearInterval(this.pollTimer);
    }

    startPolling() {
        if (!this.pollTimer) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.pollTimer = setInterval(() => this.refresh(), POLL_MS);
        }
    }

    handleEvent(message) {
        const p = message && message.data && message.data.payload;
        if (!p || p.Assignee_Id__c !== USER_ID) {
            return;
        }
        if (p.Event_Type__c === 'Assigned') {
            toast(this, 'New assignment', (p.Object_API_Name__c || '') + ': ' + (p.Record_Name__c || p.Record_Id__c), 'info');
        }
        this.refresh();
    }

    async refresh() {
        try {
            this.state = await getState();
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get statusLabel() {
        return this.state && this.state.online ? 'Online' : 'Offline';
    }

    get statusClass() {
        return this.state && this.state.online ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_warning';
    }

    get offlineDetail() {
        if (!this.state || this.state.online) {
            return null;
        }
        const parts = [];
        if (this.state.reason) {
            parts.push(this.state.reason);
        }
        const m = minutesUntil(this.state.offlineUntil);
        if (m !== null) {
            parts.push('back online in ' + Math.max(0, m) + ' min');
        }
        return parts.join(' · ');
    }

    get reasonOptions() {
        return this.state ? options(this.state.toggleReasons) : [];
    }

    get durationOptions() {
        const opts = this.state
            ? this.state.timerDurations.map((d) => ({
                  label: d + ' minutes',
                  value: String(d)
              }))
            : [];
        return this.state && this.state.timerOnly ? opts : [{ label: 'Until I come back', value: '' }, ...opts];
    }

    get assigned() {
        return (this.state ? this.state.assigned : []).map((a) => this.decorate(a));
    }

    get missed() {
        return (this.state ? this.state.missedSlas : []).map((a) => this.decorate(a));
    }

    get missedCount() {
        return this.state ? this.state.missedSlas.length : 0;
    }

    get hasAssigned() {
        return this.assigned.length > 0;
    }

    get hasPull() {
        return this.state && this.state.pullOptions && this.state.pullOptions.length > 0;
    }

    get pullOptions() {
        return (this.state ? this.state.pullOptions : []).map((p) => ({
            ...p,
            label: 'Get next: ' + p.distributorName + ' (' + p.waiting + ' waiting)',
            disabled: this.busy || !p.waiting
        }));
    }

    get rejectOptions() {
        const base = this.state ? options(this.state.rejectReasons) : [];
        return this.state && this.state.allowOtherReason ? [...base, { label: 'Other…', value: '__other__' }] : base;
    }

    get rejectIsOther() {
        return this.rejectReason === '__other__';
    }

    decorate(a) {
        const m = minutesUntil(a.nextSlaCheck);
        return {
            ...a,
            url: recordUrl(a.recordId),
            sla: a.slaMissed > 0 ? a.slaMissed + ' SLA missed' : m === null ? '' : m >= 0 ? 'SLA in ' + m + ' min' : 'SLA due',
            slaClass: a.slaMissed > 0 || (m !== null && m < 0) ? 'slds-text-color_error' : 'slds-text-color_weak',
            rejecting: this.rejectingId === a.recordId
        };
    }

    // ---------------------------------------------------------------- toggle

    handleToggle() {
        if (this.state.online) {
            this.showOffline = true;
        } else {
            this.setOnline(true, null, null);
        }
    }

    handleReason(event) {
        this.offlineReason = event.detail.value;
    }

    handleDuration(event) {
        this.offlineMinutes = event.detail.value ? parseInt(event.detail.value, 10) : null;
    }

    handleCancelOffline() {
        this.showOffline = false;
        // Re-render the toggle in its real (online) position.
        this.state = { ...this.state };
    }

    handleConfirmOffline() {
        this.setOnline(false, this.offlineReason, this.offlineMinutes);
    }

    async setOnline(online, reason, minutes) {
        this.busy = true;
        try {
            await toggle({ online, reason, timerMinutes: minutes });
            this.showOffline = false;
            this.offlineReason = null;
            this.offlineMinutes = null;
            await this.refresh();
        } catch (e) {
            toastError(this, e, 'Could not change availability');
        } finally {
            this.busy = false;
        }
    }

    // ---------------------------------------------------------------- pull

    async handlePull(event) {
        this.busy = true;
        try {
            const result = await pull({
                distributorId: event.currentTarget.dataset.id
            });
            if (result.recordIds.length) {
                toast(this, 'Records assigned to you', result.recordNames.join(', '));
            } else {
                toast(this, 'Nothing pulled', result.message, 'info');
            }
            await this.refresh();
        } catch (e) {
            toastError(this, e, 'Get next failed');
        } finally {
            this.busy = false;
        }
    }

    // ---------------------------------------------------------------- reject

    handleStartReject(event) {
        this.rejectingId = event.currentTarget.dataset.id;
        this.rejectReason = null;
        this.rejectOther = null;
    }

    handleRejectReason(event) {
        this.rejectReason = event.detail.value;
    }

    handleRejectOther(event) {
        this.rejectOther = event.target.value;
    }

    handleCancelReject() {
        this.rejectingId = null;
    }

    async handleConfirmReject() {
        const reason = this.rejectIsOther ? this.rejectOther : this.rejectReason;
        this.busy = true;
        try {
            await reject({ recordId: this.rejectingId, reason });
            toast(this, 'Rejected', 'The record was handed back.');
            this.rejectingId = null;
            await this.refresh();
        } catch (e) {
            toastError(this, e, 'Could not reject');
        } finally {
            this.busy = false;
        }
    }

    toggleMissed() {
        this.showMissed = !this.showMissed;
    }

    // ---------------------------------------------------------------- out of office

    handleOooOpen() {
        this.showOoo = !this.showOoo;
    }

    handleOooField(event) {
        const f = event.target.dataset.field;
        this.ooo = {
            ...this.ooo,
            [f]: event.target.type === 'checkbox' ? event.target.checked : event.target.value
        };
    }

    async handleOooSave() {
        this.busy = true;
        try {
            await createOutOfOffice({
                startAt: this.ooo.start,
                endAt: this.ooo.end,
                reason: this.ooo.reason,
                allDay: this.ooo.allDay
            });
            toast(this, 'Out of office saved', 'You will not receive assignments during this time.');
            this.showOoo = false;
            this.ooo = { start: null, end: null, reason: null, allDay: false };
        } catch (e) {
            toastError(this, e, 'Could not save out of office');
        } finally {
            this.busy = false;
        }
    }
}
