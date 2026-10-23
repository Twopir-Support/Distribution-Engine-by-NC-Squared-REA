import { LightningElement, api } from 'lwc';
import getShiftPlanner from '@salesforce/apex/DE_AdminController.getShiftPlanner';
import saveShiftPlanner from '@salesforce/apex/DE_AdminController.saveShiftPlanner';
import setShiftPlannerEnabled from '@salesforce/apex/DE_AdminController.setShiftPlannerEnabled';
import getShiftOptions from '@salesforce/apex/DE_AdminController.getShiftOptions';
import { reduceErrors, toast, toastError } from 'c/deUtils';

/**
 * Shift planner: members x weeks (4 back, 12 ahead). Click a week to choose the shift a member starts that week;
 * the shift applies until the member's next change. Changes are kept locally until Save.
 */
export default class DeShiftPlanner extends LightningElement {
    @api teamId;
    @api canSwitch = false;
    @api readOnly = false;

    grid;
    shiftOptions = [];
    pending = {};
    selected;
    selectedShift;
    error;
    busy = false;

    connectedCallback() {
        this.load();
        getShiftOptions()
            .then((o) => {
                this.shiftOptions = o;
            })
            .catch(() => {});
    }

    async load() {
        try {
            this.grid = await getShiftPlanner({ teamId: this.teamId });
            this.pending = {};
            this.selected = null;
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get enabled() {
        return !!(this.grid && this.grid.enabled);
    }

    get toggleDisabled() {
        return !this.canSwitch || this.busy;
    }

    get weeks() {
        if (!this.grid) {
            return [];
        }
        return this.grid.weeks.map((w) => ({
            key: w,
            label: w.slice(5),
            cls: w === this.grid.currentWeek ? 'week current' : 'week'
        }));
    }

    shiftLabel(shiftId) {
        const o = this.shiftOptions.find((x) => x.value === shiftId);
        return o ? o.label : '';
    }

    /** Rows with each week's shift, applying unsaved changes forward until the member's next change. */
    get rows() {
        if (!this.grid) {
            return [];
        }
        return this.grid.rows.map((r) => {
            let carry = null;
            let previous = { shiftId: null, shiftName: '' };
            const cells = r.cells.map((c) => {
                const key = r.memberId + '|' + c.week;
                const p = this.pending[key];
                let shown;
                let changed = c.isChange;
                if (p) {
                    carry = p.shiftId ? { shiftId: p.shiftId, shiftName: p.shiftName } : { ...previous, removed: true };
                    shown = carry;
                    changed = !!p.shiftId;
                } else if (c.isChange) {
                    carry = null;
                    shown = { shiftId: c.shiftId, shiftName: c.shiftName };
                } else {
                    shown = carry || { shiftId: c.shiftId, shiftName: c.shiftName };
                }
                previous = shown;
                const isSelected = this.selected && this.selected.key === key;
                let cls = 'cell';
                if (!c.editable) {
                    cls += ' past';
                }
                if (changed) {
                    cls += ' change';
                }
                if (p) {
                    cls += ' pending';
                }
                if (isSelected) {
                    cls += ' selected';
                }
                return {
                    key,
                    week: c.week,
                    label: shown.shiftName || '—',
                    title: (shown.shiftName || 'Member or team hours') + (changed ? ' (change starts this week)' : ''),
                    editable: c.editable && !this.readOnly,
                    disabled: !c.editable || this.readOnly,
                    shiftId: shown.shiftId,
                    cls
                };
            });
            return { key: r.memberId, memberId: r.memberId, name: r.name, cells };
        });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get pendingCount() {
        return Object.keys(this.pending).length;
    }

    get hasPending() {
        return this.pendingCount > 0;
    }

    get saveDisabled() {
        return !this.hasPending || this.busy;
    }

    handleCell(event) {
        const { member, week, name } = event.currentTarget.dataset;
        const row = this.rows.find((r) => r.memberId === member);
        const cell = row.cells.find((c) => c.week === week);
        if (!cell.editable) {
            return;
        }
        this.selected = { key: member + '|' + week, memberId: member, week, name };
        this.selectedShift = cell.shiftId || null;
    }

    get selectedLabel() {
        return this.selected ? this.selected.name + ' from the week of ' + this.selected.week : '';
    }

    handleShiftPick(event) {
        this.selectedShift = event.detail.value;
    }

    handleApply() {
        if (!this.selectedShift) {
            return;
        }
        const s = this.selected;
        this.pending = {
            ...this.pending,
            [s.key]: { memberId: s.memberId, weekStart: s.week, shiftId: this.selectedShift, shiftName: this.shiftLabel(this.selectedShift) }
        };
        this.selected = null;
    }

    handleRemoveChange() {
        const s = this.selected;
        this.pending = { ...this.pending, [s.key]: { memberId: s.memberId, weekStart: s.week, shiftId: null, shiftName: '' } };
        this.selected = null;
    }

    handleCloseSelector() {
        this.selected = null;
    }

    handleDiscard() {
        this.pending = {};
        this.selected = null;
    }

    async handleSave() {
        this.busy = true;
        try {
            const changes = Object.values(this.pending).map((p) => ({ memberId: p.memberId, weekStart: p.weekStart, shiftId: p.shiftId }));
            await saveShiftPlanner({ teamId: this.teamId, changes });
            toast(this, 'Shift planner saved', changes.length + ' change(s) saved.');
            await this.load();
            this.dispatchEvent(new CustomEvent('saved'));
        } catch (e) {
            toastError(this, e, 'Could not save the shift planner');
        } finally {
            this.busy = false;
        }
    }

    async handleToggle(event) {
        const enabled = event.target.checked;
        this.busy = true;
        try {
            await setShiftPlannerEnabled({ teamId: this.teamId, enabled });
            toast(
                this,
                enabled ? 'Shift planner on' : 'Shift planner off',
                enabled ? 'Members start on their current hours this week.' : 'Members keep their current shift; future changes were removed.'
            );
            await this.load();
            this.dispatchEvent(new CustomEvent('change', { detail: { enabled } }));
        } catch (e) {
            toastError(this, e, 'Could not switch the shift planner');
            await this.load();
        } finally {
            this.busy = false;
        }
    }
}
