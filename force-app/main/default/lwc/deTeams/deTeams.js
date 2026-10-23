import { LightningElement } from 'lwc';
import getTeams from '@salesforce/apex/DE_AdminController.getTeams';
import setTeamActive from '@salesforce/apex/DE_AdminController.setTeamActive';
import saveTeamOrder from '@salesforce/apex/DE_AdminController.saveTeamOrder';
import cloneTeam from '@salesforce/apex/DE_AdminController.cloneTeam';
import deleteTeam from '@salesforce/apex/DE_AdminController.deleteTeam';
import getDistributionViewer from '@salesforce/apex/DE_AdminController.getDistributionViewer';
import { reduceErrors, toast, toastError } from 'c/deUtils';

const ACTIONS = [
    { label: 'Open', name: 'open' },
    { label: 'Activate / deactivate', name: 'toggle' },
    { label: 'Move up', name: 'up' },
    { label: 'Move down', name: 'down' },
    { label: 'Clone', name: 'clone' },
    { label: 'Delete', name: 'delete' }
];

const COLUMNS = [
    { label: 'Order', fieldName: 'order', type: 'number', initialWidth: 80 },
    {
        label: 'Team',
        fieldName: 'name',
        type: 'button',
        typeAttributes: {
            label: { fieldName: 'name' },
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Object', fieldName: 'objectName' },
    { label: 'Type', fieldName: 'type' },
    { label: 'Active', fieldName: 'active', type: 'boolean', initialWidth: 80 },
    { label: 'Members', fieldName: 'members', type: 'number', initialWidth: 100 },
    {
        label: 'Available now',
        fieldName: 'availableNow',
        type: 'number',
        initialWidth: 130
    },
    {
        label: 'Active distributors',
        fieldName: 'activeDistributors',
        type: 'number',
        initialWidth: 160
    },
    { type: 'action', typeAttributes: { rowActions: ACTIONS } }
];

const VIEWER_COLUMNS = [
    { label: 'Source', fieldName: 'source' },
    { label: 'Team', fieldName: 'teamLabel' },
    { label: 'Distributor', fieldName: 'distributorLabel' },
    { label: 'Type', fieldName: 'type', initialWidth: 100 },
    { label: 'Method', fieldName: 'method' },
    { label: 'Filters', fieldName: 'filters', type: 'number', initialWidth: 90 },
    { label: 'Members', fieldName: 'members', type: 'number', initialWidth: 100 }
];

/** Distribution Teams tab. */
export default class DeTeams extends LightningElement {
    rows = [];
    columns = COLUMNS;
    viewerColumns = VIEWER_COLUMNS;
    viewer = [];
    showViewer = false;
    error;
    loading = false;
    openTeamId;
    newTeamType;

    connectedCallback() {
        this.load();
    }

    get inWorkspace() {
        return !!this.openTeamId || !!this.newTeamType;
    }

    async load() {
        this.loading = true;
        try {
            const teams = await getTeams();
            this.rows = teams.map((t) => ({
                id: t.team.Id,
                order: t.team.Execution_Order__c,
                name: t.team.Name,
                objectName: t.team.Object_API_Name__c,
                type: t.team.Team_Type__c,
                active: t.team.Active__c,
                members: t.members,
                availableNow: t.availableNow,
                activeDistributors: t.activeDistributors
            }));
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    handleNew() {
        this.openTeamId = null;
        this.newTeamType = 'Standard';
    }

    handleNewQ2Q() {
        this.openTeamId = null;
        this.newTeamType = 'Queue to Queue';
    }

    handleClose() {
        this.openTeamId = null;
        this.newTeamType = null;
        this.load();
    }

    handleCreated(event) {
        this.newTeamType = null;
        this.openTeamId = event.detail.teamId;
    }

    async handleViewer() {
        this.showViewer = !this.showViewer;
        if (this.showViewer) {
            try {
                const nodes = await getDistributionViewer();
                this.viewer = nodes.map((n, i) => ({
                    ...n,
                    key: 'v' + i,
                    teamLabel: n.teamName + (n.teamActive ? '' : ' (inactive)'),
                    distributorLabel: n.distributorName + (n.active ? '' : ' (inactive)')
                }));
            } catch (e) {
                toastError(this, e);
            }
        }
    }

    async handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        try {
            if (action === 'open') {
                this.openTeamId = row.id;
                return;
            }
            if (action === 'toggle') {
                await setTeamActive({ teamId: row.id, active: !row.active });
                toast(this, row.active ? 'Team deactivated' : 'Team activated', row.name);
            } else if (action === 'up' || action === 'down') {
                const ids = this.rows.map((r) => r.id);
                const i = ids.indexOf(row.id);
                const j = action === 'up' ? i - 1 : i + 1;
                if (j < 0 || j >= ids.length) {
                    return;
                }
                [ids[i], ids[j]] = [ids[j], ids[i]];
                await saveTeamOrder({ teamIds: ids });
            } else if (action === 'clone') {
                await cloneTeam({ teamId: row.id });
                toast(this, 'Team cloned', 'The copy is inactive until you activate it.');
            } else if (action === 'delete') {
                // eslint-disable-next-line no-alert
                if (!window.confirm('Delete team ' + row.name + ' with its distributors, members, caps and SLAs?')) {
                    return;
                }
                await deleteTeam({ teamId: row.id });
                toast(this, 'Team deleted', row.name);
            }
            await this.load();
        } catch (e) {
            toastError(this, e);
        }
    }
}
