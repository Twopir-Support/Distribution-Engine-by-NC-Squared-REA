import { LightningElement, api } from 'lwc';
import saveDistributor from '@salesforce/apex/DE_AdminController.saveDistributor';
import { toast, toastError, clone, cleanConditions, cleanRecord, options, CAP_PERIODS, eventValue } from 'c/deUtils';

const METHODS_BY_TYPE = {
    Standard: ['Round Robin', 'Load Balancing', 'Lookup Owner', 'Related Owner'],
    Pull: ['Round Robin'],
    Manual: ['Round Robin'],
    Trigger: ['Round Robin', 'Load Balancing', 'Dynamic Owner', 'Current Owner']
};
let seq = 0;

/** Create / edit one distributor: method, source, filters, team member filter, availability, caps, post assignment, SLAs and rejection. */
export default class DeDistributorEditor extends LightningElement {
    @api team;
    @api ownerNames;

    d = {};
    filters = [];
    memberFilters = [];
    lookupWhere = [];
    caps = [];
    saving = false;

    typeOptions = options(['Standard', 'Pull', 'Manual', 'Trigger']);
    sourceOptions = options(['Queue', 'User', 'Field Value']);
    assignToOptions = options(['All Team Members', 'Selected Members']);
    stickyLevels = options(['Distributor', 'Team', 'Global']);
    stickyCaps = options(['Ignore Caps', 'Respect Caps - Assign to Next Member', "Respect Caps - Don't Assign"]);
    tieDirections = options(['Newest or Highest', 'Oldest or Lowest']);
    removeSticky = options(['New Sticky Only', 'Always', 'Never']);
    replaceOptions = options(['Replace on Usual Assignment', 'Replace as Next Assignment', "Don't Replace"]);
    capPeriods = CAP_PERIODS;

    @api
    get draft() {
        return { distributor: this.d };
    }
    set draft(value) {
        const v = clone(value) || {};
        this.d = cleanRecord(v.distributor || {});
        this.filters = v.filters || [];
        this.memberFilters = v.memberFilters || [];
        this.lookupWhere = v.lookupWhere || [];
        this.caps = (v.caps || []).map((c) => ({
            key: 'c' + seq++,
            cap: cleanRecord(c.cap),
            criteria: c.criteria || []
        }));
    }

    get title() {
        return this.d.Id ? 'Edit distributor: ' + this.d.Name : 'New distributor';
    }
    get objectName() {
        return this.team ? this.team.Object_API_Name__c : null;
    }
    get methodOptions() {
        return options(METHODS_BY_TYPE[this.d.Type__c || 'Standard']);
    }
    get type() {
        return this.d.Type__c || 'Standard';
    }
    get method() {
        return this.d.Method__c || 'Round Robin';
    }
    get needsSource() {
        return this.type === 'Standard' || this.type === 'Pull';
    }
    get isFieldSource() {
        return this.d.Source_Type__c === 'Field Value';
    }
    get sourceKind() {
        return this.d.Source_Type__c === 'User' ? 'User' : 'Queue';
    }
    get isPull() {
        return this.type === 'Pull';
    }
    get isTrigger() {
        return this.type === 'Trigger';
    }
    get isManual() {
        return this.type === 'Manual';
    }
    get isRotation() {
        return this.method === 'Round Robin' || this.method === 'Load Balancing';
    }
    get isLookup() {
        return this.method === 'Lookup Owner';
    }
    get isRelated() {
        return this.method === 'Related Owner';
    }
    get isDynamic() {
        return this.method === 'Dynamic Owner';
    }
    get showStickySettings() {
        return this.isRotation && this.d.Sticky_Enabled__c;
    }
    get isSelected() {
        return this.d.Assign_To__c === 'Selected Members';
    }
    get maxFilters() {
        return this.isTrigger ? 5 : undefined;
    }
    get showReassign() {
        return this.d.Auto_Reassign__c;
    }
    get showReject() {
        return this.d.Rejection_Enabled__c;
    }
    get memberKind() {
        return this.team && this.team.Team_Type__c === 'Queue to Queue' ? 'Queue' : 'User';
    }
    get capRows() {
        return this.caps.map((c) => ({
            ...c,
            isCustom: (c.cap.Period__c || '').startsWith('Custom')
        }));
    }

    handleField(event) {
        const field = event.target.dataset.field;
        let value = eventValue(event);
        if (value === '') {
            value = null;
        }
        const next = { ...this.d, [field]: value };
        if (field === 'Type__c' && !METHODS_BY_TYPE[value].includes(next.Method__c)) {
            next.Method__c = METHODS_BY_TYPE[value][0];
        }
        this.d = next;
    }

    handlePicker(event) {
        const field = event.target.dataset.field;
        const detail = event.detail;
        this.d = {
            ...this.d,
            [field]: detail.values ? detail.values.join(',') : detail.value
        };
    }

    handleFilters(event) {
        this.filters = event.detail.conditions;
        this.d = { ...this.d, Filter_Logic__c: event.detail.logic };
    }

    handleMemberFilters(event) {
        this.memberFilters = event.detail.conditions;
    }

    handleLookupWhere(event) {
        this.lookupWhere = event.detail.conditions;
        this.d = { ...this.d, Lookup_Where_Logic__c: event.detail.logic };
    }

    handleAddCap() {
        this.caps = [
            ...this.caps,
            {
                key: 'c' + seq++,
                cap: { Period__c: 'Daily', Active__c: true },
                criteria: []
            }
        ];
    }

    handleRemoveCap(event) {
        this.caps = this.caps.filter((c) => c.key !== event.currentTarget.dataset.key);
    }

    handleCapField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = eventValue(event);
        this.caps = this.caps.map((c) => (c.key === key ? { ...c, cap: { ...c.cap, [field]: value === '' ? null : value } } : c));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        this.saving = true;
        try {
            const input = {
                distributor: this.d,
                filters: cleanConditions(this.filters),
                memberFilters: cleanConditions(this.memberFilters),
                lookupWhere: cleanConditions(this.lookupWhere),
                caps: this.caps.map((c) => ({
                    cap: c.cap,
                    criteria: cleanConditions(c.criteria)
                }))
            };
            await saveDistributor({ input });
            toast(this, 'Distributor saved', this.d.Name + (this.d.Id ? '' : ' (inactive until you activate it)'));
            this.dispatchEvent(new CustomEvent('saved'));
        } catch (e) {
            toastError(this, e, 'Could not save the distributor');
        } finally {
            this.saving = false;
        }
    }
}
