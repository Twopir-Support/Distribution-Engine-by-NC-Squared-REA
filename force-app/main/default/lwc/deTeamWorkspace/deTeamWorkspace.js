import { LightningElement, api } from 'lwc';
import getTeamDetail from '@salesforce/apex/DE_AdminController.getTeamDetail';
import getObjectOptions from '@salesforce/apex/DE_AdminController.getObjectOptions';
import getShiftOptions from '@salesforce/apex/DE_AdminController.getShiftOptions';
import saveTeam from '@salesforce/apex/DE_AdminController.saveTeam';
import setTeamActive from '@salesforce/apex/DE_AdminController.setTeamActive';
import addMembers from '@salesforce/apex/DE_AdminController.addMembers';
import saveMembers from '@salesforce/apex/DE_AdminController.saveMembers';
import removeMember from '@salesforce/apex/DE_AdminController.removeMember';
import syncDynamicMembers from '@salesforce/apex/DE_AdminController.syncDynamicMembers';
import setDistributorActive from '@salesforce/apex/DE_AdminController.setDistributorActive';
import saveDistributorOrder from '@salesforce/apex/DE_AdminController.saveDistributorOrder';
import cloneDistributor from '@salesforce/apex/DE_AdminController.cloneDistributor';
import deleteDistributor from '@salesforce/apex/DE_AdminController.deleteDistributor';
import saveTeamCaps from '@salesforce/apex/DE_AdminController.saveTeamCaps';
import saveSlas from '@salesforce/apex/DE_AdminController.saveSlas';
import setUsersOnline from '@salesforce/apex/DE_AvailabilityController.setUsersOnline';
import getSourcePreview from '@salesforce/apex/DE_ConsoleController.getSourcePreview';
import { reduceErrors, toast, toastError, clone, cleanConditions, cleanRecord, options, CAP_PERIODS, formatDateTime, eventValue } from 'c/deUtils';

let seq = 0;
const NEW_TEAM = {
    Name: '',
    Object_API_Name__c: 'Lead',
    Assignment_Field__c: 'OwnerId',
    Round_Robin_Level__c: 'Team',
    Load_Balancing_Level__c: 'Team',
    Load_Balancing_Type__c: 'Daily',
    Balance_By__c: 'Record Count',
    Weighting_Mode__c: 'Individual',
    Default_Tag_Weight__c: 1,
    Rejection_Limit__c: 'Unlimited',
    Rejections_Per_Day__c: 3,
    SLA_Respect_Hours__c: 'Team and Member',
    Action_Respect_Hours__c: 'Team and Member',
    Apply_Active_Status_To_SLAs__c: true
};

/** One team: members, distributors, weighting and caps, hours, SLAs and tracking, rejection, post assignment, settings. */
export default class DeTeamWorkspace extends LightningElement {
    @api teamId;
    @api newTeamType;

    section = 'summary';
    detail;
    team = {};
    teamFilters = [];
    teamLogic;
    dynamicConditions = [];
    members = [];
    caps = [];
    slas = [];
    distributorDraft;
    objectOptions = [];
    shiftOptions = [];
    addIds = [];
    preview;
    error;
    busy = false;

    rrLevels = options(['Team', 'Distributor']);
    lbTypes = options(['Daily', 'Weekly', 'Monthly', 'Active']);
    balanceBy = options(['Record Count', 'Field Value']);
    weightingModes = options(['Individual', 'Tag']);
    rejectionLimits = options(['Unlimited', 'Manager Only', 'Limited']);
    hoursOptions = options(['Team and Member', 'Team Only', 'None']);
    teamTypes = options(['Standard', 'Queue to Queue']);
    capPeriods = CAP_PERIODS;
    criteriaSources = options(['Field', 'Distributor Filters']);
    alertTypes = options(['Time Checkpoint', 'Continuous Field Monitoring', 'Custom Date/Time']);

    connectedCallback() {
        getObjectOptions()
            .then((o) => {
                this.objectOptions = o;
            })
            .catch(() => {});
        this.loadShifts();
        if (this.teamId) {
            this.load();
        } else {
            this.team = { ...NEW_TEAM, Team_Type__c: this.newTeamType || 'Standard' };
            this.section = 'settings';
        }
    }

    loadShifts() {
        getShiftOptions()
            .then((o) => {
                this.shiftOptions = [{ label: '— none —', value: '' }, ...o];
            })
            .catch(() => {});
    }

    async load() {
        try {
            const d = await getTeamDetail({ teamId: this.teamId });
            this.detail = d;
            this.team = cleanRecord(d.team);
            this.teamLogic = d.team.Filter_Logic__c;
            this.teamFilters = clone(d.teamFilters);
            this.dynamicConditions = clone(d.dynamicConditions);
            this.members = d.members.map((m) => ({
                key: m.record.Id,
                Id: m.record.Id,
                userId: m.record.User__c,
                name: m.name,
                isQueue: m.isQueue,
                Active__c: m.record.Active__c,
                Weight__c: m.record.Weight__c,
                Member_Hours__c: m.record.Member_Hours__c || '',
                online: m.online,
                availability: m.availability,
                availabilityClass: m.availableNow ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_warning',
                today: m.today,
                tags: m.tags,
                dynamic: m.record.Dynamic__c
            }));
            this.caps = d.caps.map((c) => ({
                key: 'c' + seq++,
                cap: cleanRecord(c.cap),
                criteria: clone(c.criteria)
            }));
            this.slas = d.slas.map((s) => ({
                key: 's' + seq++,
                sla: cleanRecord(s.sla),
                conditions: clone(s.conditions)
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    // ---------------------------------------------------------------- navigation

    get isNew() {
        return !this.teamId;
    }
    get title() {
        return this.isNew ? 'New ' + (this.team.Team_Type__c || 'Standard') + ' Team' : this.team.Name;
    }
    get canEdit() {
        return this.isNew || (this.detail && this.detail.canEdit);
    }
    get readOnly() {
        return !this.canEdit;
    }
    get canManage() {
        return this.detail && this.detail.canManage;
    }
    get readOnlyMembers() {
        return !this.canManage;
    }
    get isQ2Q() {
        return this.team.Team_Type__c === 'Queue to Queue';
    }
    get memberKind() {
        return this.isQ2Q ? 'Queue' : 'User';
    }
    get activeLabel() {
        return this.team.Active__c ? 'Deactivate' : 'Activate';
    }
    get statusBadge() {
        return this.team.Active__c ? 'slds-badge slds-theme_success' : 'slds-badge';
    }
    get statusText() {
        return this.team.Active__c ? 'Active' : 'Inactive';
    }
    get holiday() {
        return this.detail && this.detail.holiday;
    }
    get historyUrl() {
        return this.teamId ? '/lightning/r/DE_Team__c/' + this.teamId + '/related/Histories/view' : null;
    }

    handleNav(event) {
        this.section = event.detail.name;
        this.distributorDraft = null;
    }

    get show() {
        const s = this.section;
        return {
            summary: s === 'summary',
            members: s === 'members',
            distributors: s === 'distributors',
            caps: s === 'caps',
            hours: s === 'hours',
            slas: s === 'slas',
            rejection: s === 'rejection',
            post: s === 'post',
            settings: s === 'settings'
        };
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ---------------------------------------------------------------- team fields

    handleTeamField(event) {
        const field = event.target.dataset.field;
        const value = eventValue(event);
        this.team = { ...this.team, [field]: value === '' ? null : value };
    }

    handleManagers(event) {
        this.team = {
            ...this.team,
            Manager_User_Ids__c: event.detail.values.join(',')
        };
    }

    handleTeamFilters(event) {
        this.teamFilters = event.detail.conditions;
        this.teamLogic = event.detail.logic;
    }

    handleDynamic(event) {
        this.dynamicConditions = event.detail.conditions;
        this.team = { ...this.team, Dynamic_Members_Logic__c: event.detail.logic };
    }

    get isFieldBalance() {
        return this.team.Balance_By__c === 'Field Value';
    }
    get isTagWeighting() {
        return this.team.Weighting_Mode__c === 'Tag';
    }
    get isLimitedRejection() {
        return this.team.Rejection_Limit__c === 'Limited';
    }
    get objectLocked() {
        return !this.isNew;
    }

    async handleSaveTeam() {
        this.busy = true;
        try {
            const record = { ...this.team, Filter_Logic__c: this.teamLogic };
            const id = await saveTeam({
                team: record,
                filters: cleanConditions(this.teamFilters),
                dynamicConditions: cleanConditions(this.dynamicConditions)
            });
            toast(this, 'Team saved', record.Name);
            if (this.isNew) {
                this.dispatchEvent(new CustomEvent('created', { detail: { teamId: id } }));
            } else {
                await this.load();
            }
        } catch (e) {
            toastError(this, e, 'Could not save the team');
        } finally {
            this.busy = false;
        }
    }

    async handleToggleActive() {
        try {
            await setTeamActive({
                teamId: this.teamId,
                active: !this.team.Active__c
            });
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleSyncDynamic() {
        try {
            const r = await syncDynamicMembers({ teamId: this.teamId });
            toast(this, 'Dynamic members synced', r.added + ' added, ' + r.reactivated + ' reactivated, ' + r.deactivated + ' deactivated.');
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    // ---------------------------------------------------------------- members

    get hasMembers() {
        return this.members.length > 0;
    }

    get memberShiftOptions() {
        return this.shiftOptions;
    }

    handleAddIds(event) {
        this.addIds = event.detail.values;
    }

    async handleAddMembers() {
        if (!this.addIds.length) {
            return;
        }
        try {
            await addMembers({ teamId: this.teamId, memberIds: this.addIds });
            this.addIds = [];
            const picker = this.template.querySelector('c-de-record-picker[data-id="add"]');
            if (picker) {
                picker.value = [];
            }
            toast(this, 'Members added', '');
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleMemberField(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = eventValue(event);
        this.members = this.members.map((m) => (m.Id === id ? { ...m, [field]: value } : m));
    }

    async handleSaveMembers() {
        try {
            await saveMembers({
                members: this.members.map((m) => ({
                    Id: m.Id,
                    Active__c: m.Active__c,
                    Weight__c: m.Weight__c === '' || m.Weight__c === null ? 1 : Number(m.Weight__c),
                    Member_Hours__c: m.Member_Hours__c || null
                }))
            });
            toast(this, 'Members saved', '');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save members');
        }
    }

    async handleRemoveMember(event) {
        try {
            await removeMember({ memberId: event.currentTarget.dataset.id });
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleMemberOnline(event) {
        const userId = event.target.dataset.user;
        try {
            await setUsersOnline({
                userIds: [userId],
                online: event.target.checked,
                reason: 'Manager override'
            });
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    get weightShares() {
        const active = this.members.filter((m) => m.Active__c);
        const total = active.reduce((s, m) => s + Number(m.Weight__c || 1), 0) || 1;
        return active.map((m) => ({
            key: m.Id,
            name: m.name,
            weight: m.Weight__c,
            share: Math.round((Number(m.Weight__c || 1) * 100) / total) + '%'
        }));
    }

    // ---------------------------------------------------------------- distributors

    get distributorRows() {
        if (!this.detail) {
            return [];
        }
        const names = this.detail.ownerNames || {};
        return this.detail.distributors.map((d) => {
            const r = d.distributor;
            let source = 'Any (trigger/manual)';
            if (r.Source_Type__c === 'Field Value') {
                source = r.Source_Field__c + ' = ' + r.Source_Ready_Value__c;
            } else if (r.Source_Id__c) {
                source = names[r.Source_Id__c] || r.Source_Id__c;
            }
            return {
                key: r.Id,
                id: r.Id,
                order: r.Order__c,
                name: r.Name,
                type: r.Type__c,
                method: r.Method__c + (r.Sticky_Enabled__c ? ' + sticky' : ''),
                source,
                filters: (d.filters || []).length,
                active: r.Active__c,
                activeLabel: r.Active__c ? 'Deactivate' : 'Activate',
                badge: r.Active__c ? 'slds-badge slds-theme_success' : 'slds-badge',
                status: r.Active__c ? 'Active' : 'Inactive',
                extras: [r.SLA_Enabled__c ? 'SLAs' : null, r.Auto_Reassign__c ? 'Auto reassign' : null, r.Rejection_Enabled__c ? 'Rejection' : null]
                    .filter((x) => x)
                    .join(' · ')
            };
        });
    }

    get hasDistributors() {
        return this.distributorRows.length > 0;
    }

    handleNewDistributor() {
        this.distributorDraft = {
            distributor: {
                Team__c: this.teamId,
                Type__c: 'Standard',
                Method__c: 'Round Robin',
                Source_Type__c: 'Queue',
                Assign_To__c: 'All Team Members',
                Weighting_Enabled__c: true,
                Respect_Team_Caps__c: true,
                Send_Notification__c: true,
                Pull_Count__c: 1,
                Sticky_Days__c: 90,
                Sticky_Level__c: 'Distributor',
                Sticky_Cap_Behaviour__c: 'Ignore Caps',
                Reassign_From_SLA__c: 1,
                Remove_Sticky_On_Reassign__c: 'New Sticky Only',
                Replace_Rejected__c: 'Replace on Usual Assignment',
                Lookup_Tie_Breaker_Direction__c: 'Newest or Highest'
            },
            filters: [],
            memberFilters: [],
            lookupWhere: [],
            caps: []
        };
    }

    handleEditDistributor(event) {
        const d = this.detail.distributors.find((x) => x.distributor.Id === event.currentTarget.dataset.id);
        this.distributorDraft = clone(d);
    }

    handleEditorClose() {
        this.distributorDraft = null;
    }

    async handleEditorSaved() {
        this.distributorDraft = null;
        await this.load();
    }

    async handleDistributorAction(event) {
        const id = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;
        const rows = this.distributorRows;
        const row = rows.find((r) => r.id === id);
        try {
            if (action === 'toggle') {
                await setDistributorActive({ distributorId: id, active: !row.active });
            } else if (action === 'up' || action === 'down') {
                const ids = rows.map((r) => r.id);
                const i = ids.indexOf(id);
                const j = action === 'up' ? i - 1 : i + 1;
                if (j < 0 || j >= ids.length) {
                    return;
                }
                [ids[i], ids[j]] = [ids[j], ids[i]];
                await saveDistributorOrder({ distributorIds: ids });
            } else if (action === 'clone') {
                await cloneDistributor({ distributorId: id });
            } else if (action === 'delete') {
                // eslint-disable-next-line no-alert
                if (!window.confirm('Delete distributor ' + row.name + '?')) {
                    return;
                }
                await deleteDistributor({ distributorId: id });
            } else if (action === 'preview') {
                const recs = await getSourcePreview({ distributorId: id });
                this.preview = {
                    title: 'Waiting at the source of ' + row.name,
                    rows: recs.map((r) => ({
                        key: r.id,
                        name: r.name,
                        url: '/' + r.id,
                        created: formatDateTime(r.created)
                    }))
                };
                return;
            }
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleClosePreview() {
        this.preview = null;
    }

    // ---------------------------------------------------------------- caps

    get capRows() {
        return this.caps.map((c, i) => ({
            ...c,
            index: i,
            label: 'Team cap ' + (i + 1),
            isCustom: (c.cap.Period__c || '').startsWith('Custom'),
            isCriteria: c.cap.Period__c === 'Criteria',
            isFieldCriteria: c.cap.Period__c === 'Criteria' && c.cap.Criteria_Source__c !== 'Distributor Filters'
        }));
    }

    get canAddCap() {
        return this.caps.length < 3;
    }

    handleAddCap() {
        this.caps = [
            ...this.caps,
            {
                key: 'c' + seq++,
                cap: {
                    Period__c: 'Daily',
                    Active__c: true,
                    Criteria_Source__c: 'Field'
                },
                criteria: []
            }
        ];
    }

    handleRemoveCap(event) {
        const key = event.currentTarget.dataset.key;
        this.caps = this.caps.filter((c) => c.key !== key);
    }

    handleCapField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = eventValue(event);
        this.caps = this.caps.map((c) => (c.key === key ? { ...c, cap: { ...c.cap, [field]: value === '' ? null : value } } : c));
    }

    handleCapCriteria(event) {
        const key = event.target.dataset.key;
        this.caps = this.caps.map((c) => {
            if (c.key !== key) {
                return c;
            }
            return { ...c, criteria: event.detail.conditions, cap: { ...c.cap, Criteria_Logic__c: event.detail.logic } };
        });
    }

    async handleSaveCaps() {
        try {
            await saveTeamCaps({
                teamId: this.teamId,
                caps: this.caps.map((c) => ({
                    cap: c.cap,
                    criteria: cleanConditions(c.criteria)
                }))
            });
            toast(this, 'Team caps saved', '');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save caps');
        }
    }

    // ---------------------------------------------------------------- SLAs

    get slaRows() {
        return this.slas.map((s) => ({
            ...s,
            isCustomDate: s.sla.Alert_Type__c === 'Custom Date/Time',
            minutesLabel: s.sla.Alert_Type__c === 'Continuous Field Monitoring' ? 'Monitor for (minutes, max 20160)' : 'Minutes after assignment'
        }));
    }

    get canAddSla() {
        return this.slas.length < 3;
    }

    handleAddSla() {
        const n = this.slas.length + 1;
        this.slas = [
            ...this.slas,
            {
                key: 's' + seq++,
                sla: {
                    Name: 'SLA ' + n,
                    Checkpoint__c: n,
                    Alert_Type__c: 'Time Checkpoint',
                    Minutes_After_Assignment__c: 60 * n,
                    Notify_Assignee__c: true,
                    Notify_Manager__c: false,
                    Active__c: true
                },
                conditions: []
            }
        ];
    }

    handleRemoveSla(event) {
        const key = event.currentTarget.dataset.key;
        this.slas = this.slas.filter((s) => s.key !== key);
    }

    handleSlaField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = eventValue(event);
        this.slas = this.slas.map((s) => (s.key === key ? { ...s, sla: { ...s.sla, [field]: value === '' ? null : value } } : s));
    }

    handleSlaConditions(event) {
        const key = event.target.dataset.key;
        this.slas = this.slas.map((s) => {
            if (s.key !== key) {
                return s;
            }
            return { ...s, conditions: event.detail.conditions, sla: { ...s.sla, Condition_Logic__c: event.detail.logic } };
        });
    }

    async handleSaveSlas() {
        try {
            await saveSlas({
                teamId: this.teamId,
                slas: this.slas.map((s) => ({
                    sla: s.sla,
                    conditions: cleanConditions(s.conditions)
                }))
            });
            await saveTeam({
                team: { ...this.team, Filter_Logic__c: this.teamLogic },
                filters: cleanConditions(this.teamFilters),
                dynamicConditions: cleanConditions(this.dynamicConditions)
            });
            toast(this, 'SLAs and tracking saved', '');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not save SLAs');
        }
    }
}
