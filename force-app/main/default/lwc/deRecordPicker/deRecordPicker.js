import { LightningElement, api } from 'lwc';
import searchOwners from '@salesforce/apex/DE_AdminController.searchOwners';
import getOwnerNames from '@salesforce/apex/DE_AdminController.getOwnerNames';
import { reduceErrors } from 'c/deUtils';

/**
 * Searches users and/or queues. Single mode fires change { value, label };
 * multiple mode fires change { values: [ids], labels: {id: label} }.
 */
export default class DeRecordPicker extends LightningElement {
    @api label = 'User or queue';
    @api kind = 'Both';
    @api objectName;
    @api multiple = false;
    @api required = false;
    @api disabled = false;
    @api placeholder = 'Search…';

    selected = [];
    results = [];
    term = '';
    error;
    timer;

    @api
    get value() {
        return this.multiple ? this.selected.map((s) => s.value) : this.selected.length ? this.selected[0].value : null;
    }
    set value(v) {
        const ids = Array.isArray(v)
            ? v
            : v
              ? String(v)
                    .split(/[,;\s]+/)
                    .filter((x) => x)
              : [];
        this.selected = ids.map((id) => ({
            value: id,
            label: (this.selected.find((s) => s.value === id) || {}).label || id
        }));
        const unknown = this.selected.filter((s) => s.label === s.value).map((s) => s.value);
        if (unknown.length) {
            getOwnerNames({ ids: unknown })
                .then((names) => {
                    this.selected = this.selected.map((s) => ({
                        ...s,
                        label: names[s.value] || s.label
                    }));
                })
                .catch(() => {});
        }
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get showSearch() {
        return !this.disabled && (this.multiple || this.selected.length === 0);
    }

    get pills() {
        return this.selected.map((s) => ({ ...s, key: s.value }));
    }

    handleTerm(event) {
        this.term = event.target.value;
        clearTimeout(this.timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.search(), 300);
    }

    search() {
        if (!this.term || this.term.length < 2) {
            this.results = [];
            return;
        }
        searchOwners({
            term: this.term,
            kind: this.kind,
            objectName: this.objectName
        })
            .then((r) => {
                const chosen = new Set(this.selected.map((s) => s.value));
                this.results = r.filter((o) => !chosen.has(o.value));
                this.error = undefined;
            })
            .catch((e) => {
                this.error = reduceErrors(e);
            });
    }

    handleSelect(event) {
        const value = event.currentTarget.dataset.value;
        const label = event.currentTarget.dataset.label;
        this.selected = this.multiple ? [...this.selected, { value, label }] : [{ value, label }];
        this.results = [];
        this.term = '';
        this.fire();
    }

    handleRemove(event) {
        const value = event.detail.item ? event.detail.item.name : event.target.name;
        this.selected = this.selected.filter((s) => s.value !== value);
        this.fire();
    }

    fire() {
        if (this.multiple) {
            const labels = {};
            this.selected.forEach((s) => {
                labels[s.value] = s.label;
            });
            this.dispatchEvent(
                new CustomEvent('change', {
                    detail: { values: this.selected.map((s) => s.value), labels }
                })
            );
        } else {
            const s = this.selected[0];
            this.dispatchEvent(
                new CustomEvent('change', {
                    detail: { value: s ? s.value : null, label: s ? s.label : null }
                })
            );
        }
    }
}
