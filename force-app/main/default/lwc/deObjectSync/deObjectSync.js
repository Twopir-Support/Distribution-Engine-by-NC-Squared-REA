import { LightningElement } from 'lwc';
import getSyncActions from '@salesforce/apex/DE_ConsoleController.getSyncActions';
import saveSyncAction from '@salesforce/apex/DE_ConsoleController.saveSyncAction';
import deleteSyncAction from '@salesforce/apex/DE_ConsoleController.deleteSyncAction';
import { reduceErrors, toast, toastError, cleanRecord, cleanConditions, clone, eventValue } from 'c/deUtils';

/** Distribution Sync tab: related records follow the distributed record's new owner. */
export default class DeObjectSync extends LightningElement {
    actions = [];
    editing;
    conditions = [];
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            const rows = await getSyncActions();
            this.actions = rows.map((r) => ({
                ...r,
                key: r.record.Id,
                rec: r.record,
                status: r.record.Active__c ? 'Active' : 'Inactive'
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get hasActions() {
        return this.actions.length > 0;
    }

    handleNew() {
        this.editing = {
            Name: '',
            Parent_Object__c: 'Lead',
            Child_Object__c: 'Task',
            Lookup_Field__c: 'WhoId',
            Active__c: false
        };
        this.conditions = [];
    }

    handleEdit(event) {
        const a = this.actions.find((x) => x.key === event.currentTarget.dataset.id);
        this.editing = cleanRecord(a.rec);
        this.conditions = clone(a.conditions);
    }

    handleField(event) {
        this.editing = {
            ...this.editing,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleConditions(event) {
        this.conditions = event.detail.conditions;
        this.editing = { ...this.editing, Filter_Logic__c: event.detail.logic };
    }

    handleCancel() {
        this.editing = null;
    }

    async handleSave() {
        try {
            await saveSyncAction({
                action: this.editing,
                conditions: cleanConditions(this.conditions)
            });
            toast(this, 'Sync action saved', this.editing.Name);
            this.editing = null;
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save');
        }
    }

    async handleDelete(event) {
        try {
            await deleteSyncAction({ actionId: event.currentTarget.dataset.id });
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }
}
