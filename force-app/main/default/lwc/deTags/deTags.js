import { LightningElement } from 'lwc';
import getTagAssignments from '@salesforce/apex/DE_AvailabilityController.getTagAssignments';
import getTagCollections from '@salesforce/apex/DE_AvailabilityController.getTagCollections';
import saveTags from '@salesforce/apex/DE_AvailabilityController.saveTags';
import cloneTags from '@salesforce/apex/DE_AvailabilityController.cloneTags';
import { reduceErrors, toast, toastError } from 'c/deUtils';

/** Distribution Tags tab: tag collections and tag assignment to users. */
export default class DeTags extends LightningElement {
    users = [];
    collections = [];
    editing;
    editTags = '';
    cloneFrom;
    cloneTo = [];
    error;
    filter = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            const [users, cols] = await Promise.all([getTagAssignments(), getTagCollections()]);
            this.users = users.map((u) => ({
                ...u,
                pills: (u.tags || '')
                    .split(';')
                    .filter((t) => t)
                    .map((t) => ({ key: u.userId + t, label: t }))
            }));
            this.collections = Object.keys(cols)
                .sort()
                .map((c) => ({ key: c, name: c, tags: cols[c].join(', ') }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get visibleUsers() {
        const f = this.filter.toLowerCase();
        return this.users.filter((u) => !f || u.name.toLowerCase().includes(f) || (u.tags || '').toLowerCase().includes(f));
    }

    get userOptions() {
        return this.users.map((u) => ({ label: u.name, value: u.userId }));
    }

    handleFilter(event) {
        this.filter = event.target.value || '';
    }

    handleEdit(event) {
        const u = this.users.find((x) => x.userId === event.currentTarget.dataset.id);
        this.editing = u;
        this.editTags = (u.tags || '').split(';').join('\n');
    }

    handleEditTags(event) {
        this.editTags = event.target.value;
    }

    handleCancel() {
        this.editing = null;
    }

    async handleSave() {
        try {
            await saveTags({ userId: this.editing.userId, tags: this.editTags });
            toast(this, 'Tags saved', this.editing.name);
            this.editing = null;
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save tags');
        }
    }

    handleCloneFrom(event) {
        this.cloneFrom = event.detail.value;
    }

    handleCloneTo(event) {
        this.cloneTo = event.detail.value;
    }

    async handleClone() {
        try {
            await cloneTags({ fromUserId: this.cloneFrom, toUserIds: this.cloneTo });
            toast(this, 'Tags cloned', this.cloneTo.length + ' users updated.');
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }
}
