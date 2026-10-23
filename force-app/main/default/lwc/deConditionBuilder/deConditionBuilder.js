import { LightningElement, api, track } from 'lwc';
import getFieldOptions from '@salesforce/apex/DE_AdminController.getFieldOptions';
import { OPERATORS, MEMBER_OPERATORS, reduceErrors } from 'c/deUtils';

const CUSTOM = '__custom__';
let keySeq = 0;

/**
 * Filter rows (Field / Operator / Value) with optional filter logic.
 * mode="record" uses the object's fields (and DE classifier paths); mode="member" uses member filter syntax.
 * Fires "change" with detail { conditions, logic }.
 */
export default class DeConditionBuilder extends LightningElement {
    @api label = 'Filters';
    @api objectName;
    @api mode = 'record';
    @api includeClassifier = false;
    @api showLogic = false;
    @api readOnly = false;
    @api maxRows;
    @api helpText;

    @track rows = [];
    logicValue = '';
    fieldOptions = [];
    loadError;
    _loadedFor;

    @api
    get conditions() {
        return this.rows.map((r, i) => this.toCondition(r, i));
    }
    set conditions(value) {
        this.rows = (value || []).map((c, i) => ({
            key: 'r' + keySeq++,
            number: c.Sequence__c || i + 1,
            field: c.Field_API_Name__c,
            operator: c.Operator__c || (this.mode === 'member' ? 'includes' : 'equals'),
            value: c.Value__c,
            custom: false
        }));
        this.markCustom();
    }

    @api
    get logic() {
        return this.logicValue;
    }
    set logic(value) {
        this.logicValue = value || '';
    }

    connectedCallback() {
        this.loadFields();
    }

    renderedCallback() {
        if (this.objectName !== this._loadedFor) {
            this.loadFields();
        }
    }

    loadFields() {
        if (this.mode === 'member' || !this.objectName) {
            this._loadedFor = this.objectName;
            return;
        }
        this._loadedFor = this.objectName;
        getFieldOptions({
            objectName: this.objectName,
            includeClassifier: this.includeClassifier
        })
            .then((opts) => {
                this.fieldOptions = [{ label: 'Other (type a field path)…', value: CUSTOM }, ...opts];
                this.loadError = undefined;
                this.markCustom();
            })
            .catch((e) => {
                this.loadError = reduceErrors(e);
            });
    }

    markCustom() {
        if (this.mode === 'member' || !this.fieldOptions.length) {
            return;
        }
        const known = new Set(this.fieldOptions.map((o) => o.value));
        this.rows = this.rows.map((r) => ({
            ...r,
            custom: !!r.field && !known.has(r.field)
        }));
    }

    get isMember() {
        return this.mode === 'member';
    }

    get operatorOptions() {
        return this.isMember ? MEMBER_OPERATORS : OPERATORS;
    }

    get canAdd() {
        return !this.readOnly && (!this.maxRows || this.rows.length < this.maxRows);
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get displayRows() {
        const byValue = new Map(this.fieldOptions.map((o) => [o.value, o]));
        return this.rows.map((r) => {
            const meta = byValue.get(r.field);
            const blankOp = r.operator === 'is blank' || r.operator === 'is not blank';
            let placeholder = 'Value';
            if (this.isMember) {
                placeholder = 'Tags separated by ;';
            } else if (meta && meta.picklistValues && meta.picklistValues.length) {
                placeholder = meta.picklistValues.slice(0, 6).join('; ') + (meta.picklistValues.length > 6 ? '…' : '');
            } else if (meta && (meta.type === 'DATETIME' || meta.type === 'DATE')) {
                placeholder = 'TODAY, NOW, 2026-01-31 or "5 minutes ago"';
            } else if (r.operator === 'between') {
                placeholder = 'low..high';
            }
            return {
                ...r,
                pickerValue: r.custom ? CUSTOM : r.field,
                showPath: this.isMember || r.custom,
                valueDisabled: blankOp || this.readOnly,
                placeholder
            };
        });
    }

    toCondition(r, i) {
        return {
            Sequence__c: r.number || i + 1,
            Field_API_Name__c: r.field,
            Operator__c: r.operator,
            Value__c: r.operator === 'is blank' || r.operator === 'is not blank' ? null : r.value
        };
    }

    update(key, changes) {
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, ...changes } : r));
        this.notify();
    }

    notify() {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { conditions: this.conditions, logic: this.logicValue }
            })
        );
    }

    handleAdd() {
        const next = this.rows.reduce((m, r) => Math.max(m, r.number || 0), 0) + 1;
        this.rows = [
            ...this.rows,
            {
                key: 'r' + keySeq++,
                number: next,
                field: '',
                operator: this.isMember ? 'includes' : 'equals',
                value: '',
                custom: this.isMember
            }
        ];
        this.notify();
    }

    handleRemove(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.filter((r) => r.key !== key);
        this.notify();
    }

    handleFieldPick(event) {
        const key = event.target.dataset.key;
        const value = event.detail.value;
        if (value === CUSTOM) {
            this.update(key, { custom: true, field: '' });
        } else {
            this.update(key, { custom: false, field: value });
        }
    }

    handlePath(event) {
        this.update(event.target.dataset.key, { field: event.target.value });
    }

    handleOperator(event) {
        this.update(event.target.dataset.key, { operator: event.detail.value });
    }

    handleValue(event) {
        this.update(event.target.dataset.key, { value: event.target.value });
    }

    handleNumber(event) {
        this.update(event.target.dataset.key, {
            number: parseInt(event.target.value, 10) || null
        });
    }

    handleLogic(event) {
        this.logicValue = event.target.value;
        this.notify();
    }
}
