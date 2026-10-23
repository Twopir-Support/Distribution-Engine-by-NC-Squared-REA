import { LightningElement } from 'lwc';
import getOutOfOffice from '@salesforce/apex/DE_AvailabilityController.getOutOfOffice';
import saveOutOfOffice from '@salesforce/apex/DE_AvailabilityController.saveOutOfOffice';
import deleteOutOfOffice from '@salesforce/apex/DE_AvailabilityController.deleteOutOfOffice';
import getHolidays from '@salesforce/apex/DE_AvailabilityController.getHolidays';
import saveHoliday from '@salesforce/apex/DE_AvailabilityController.saveHoliday';
import deleteHoliday from '@salesforce/apex/DE_AvailabilityController.deleteHoliday';
import getHolidayRegions from '@salesforce/apex/DE_AvailabilityController.getHolidayRegions';
import saveHolidayRegion from '@salesforce/apex/DE_AvailabilityController.saveHolidayRegion';
import deleteHolidayRegion from '@salesforce/apex/DE_AvailabilityController.deleteHolidayRegion';
import getShifts from '@salesforce/apex/DE_AvailabilityController.getShifts';
import saveShift from '@salesforce/apex/DE_AvailabilityController.saveShift';
import deleteShift from '@salesforce/apex/DE_AvailabilityController.deleteShift';
import getRoster from '@salesforce/apex/DE_AvailabilityController.getRoster';
import setUsersOnline from '@salesforce/apex/DE_AvailabilityController.setUsersOnline';
import getCalendar from '@salesforce/apex/DE_AvailabilityController.getCalendar';
import getTeams from '@salesforce/apex/DE_AdminController.getTeams';
import getTimezoneOptions from '@salesforce/apex/DE_AdminController.getTimezoneOptions';
import USER_ID from '@salesforce/user/Id';
import { reduceErrors, toast, toastError, formatDateTime, cleanRecord, eventValue } from 'c/deUtils';

const DAYS = [
    { code: 'MON', label: 'Monday' },
    { code: 'TUE', label: 'Tuesday' },
    { code: 'WED', label: 'Wednesday' },
    { code: 'THU', label: 'Thursday' },
    { code: 'FRI', label: 'Friday' },
    { code: 'SAT', label: 'Saturday' },
    { code: 'SUN', label: 'Sunday' }
];

/** Distribution Availability tab. */
export default class DeAvailability extends LightningElement {
    ooo = [];
    oooEdit;
    holidays = [];
    holidayEdit;
    regions = [];
    regionEdit;
    holidayRegionFilter = '';
    holidaySearch = '';
    shifts = [];
    shiftEdit;
    shiftDays = [];
    roster = [];
    calendar = [];
    teamOptions = [];
    timezoneOptions = [];
    teamId;
    month;
    error;

    connectedCallback() {
        const now = new Date();
        this.month = now.toISOString().slice(0, 7);
        this.loadOoo();
        getTeams()
            .then((t) => {
                this.teamOptions = t.map((x) => ({
                    label: x.team.Name,
                    value: x.team.Id
                }));
            })
            .catch(() => {});
        getTimezoneOptions()
            .then((t) => {
                this.timezoneOptions = t;
            })
            .catch(() => {});
    }

    handleTab(event) {
        const v = event.target.value;
        const loaders = {
            ooo: () => this.loadOoo(),
            holidays: () => {
                this.loadRegions();
                this.loadHolidays();
            },
            regions: () => this.loadRegions(),
            shifts: () => this.loadShifts(),
            roster: () => this.loadRoster()
        };
        if (loaders[v]) {
            loaders[v]();
        }
    }

    fail(e) {
        this.error = reduceErrors(e);
    }

    // ---------------------------------------------------------------- out of office

    async loadOoo() {
        try {
            const rows = await getOutOfOffice({
                userId: null,
                fromDate: null,
                toDate: null
            });
            this.ooo = rows.map((o) => ({
                ...o,
                who: o.User__r ? o.User__r.Name : o.Queue_Id__c,
                start: formatDateTime(o.Start__c),
                end: formatDateTime(o.End__c)
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    handleNewOoo() {
        this.oooEdit = {
            User__c: USER_ID,
            Start__c: null,
            End__c: null,
            All_Day__c: false,
            Reason__c: ''
        };
    }

    handleEditOoo(event) {
        const o = this.ooo.find((x) => x.Id === event.currentTarget.dataset.id);
        // Only the record fields: the display helpers (who, start, end) are not fields of DE_Out_Of_Office__c.
        this.oooEdit = {
            Id: o.Id,
            User__c: o.User__c,
            Queue_Id__c: o.Queue_Id__c,
            Start__c: o.Start__c,
            End__c: o.End__c,
            All_Day__c: o.All_Day__c,
            Reason__c: o.Reason__c,
            Timezone__c: o.Timezone__c
        };
    }

    handleOooField(event) {
        this.oooEdit = {
            ...this.oooEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleOooUser(event) {
        this.oooEdit = { ...this.oooEdit, User__c: event.detail.value };
    }

    async handleSaveOoo() {
        try {
            await saveOutOfOffice({ ooo: this.oooEdit });
            this.oooEdit = null;
            toast(this, 'Out of office saved', '');
            await this.loadOoo();
        } catch (e) {
            toastError(this, e, 'Could not save');
        }
    }

    async handleDeleteOoo(event) {
        try {
            await deleteOutOfOffice({ oooId: event.currentTarget.dataset.id });
            await this.loadOoo();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelOoo() {
        this.oooEdit = null;
    }

    // ---------------------------------------------------------------- holidays and regions

    async loadHolidays() {
        try {
            const rows = await getHolidays();
            this.holidays = rows.map((h) => ({
                ...h,
                regionName: h.Holiday_Region__r ? h.Holiday_Region__r.Name : '',
                start: formatDateTime(h.Start__c),
                end: formatDateTime(h.End__c)
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    handleNewHoliday() {
        this.holidayEdit = {
            Name: '',
            Holiday_Region__c: this.holidayRegionFilter || null,
            All_Day__c: true,
            Start__c: null,
            End__c: null,
            Timezone__c: null
        };
    }

    handleEditHoliday(event) {
        const h = this.holidays.find((x) => x.Id === event.currentTarget.dataset.id);
        // Only the record fields: the display helpers (regionName, start, end) are not fields of DE_Holiday__c.
        this.holidayEdit = {
            Id: h.Id,
            Name: h.Name,
            Holiday_Region__c: h.Holiday_Region__c,
            All_Day__c: h.All_Day__c,
            Start__c: h.Start__c,
            End__c: h.End__c,
            Timezone__c: h.Timezone__c
        };
    }

    handleHolidayField(event) {
        this.holidayEdit = {
            ...this.holidayEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    async handleSaveHoliday() {
        try {
            await saveHoliday({ holiday: this.holidayEdit });
            this.holidayEdit = null;
            await this.loadHolidays();
        } catch (e) {
            toastError(this, e, 'Could not save holiday');
        }
    }

    async handleDeleteHoliday(event) {
        try {
            await deleteHoliday({ holidayId: event.currentTarget.dataset.id });
            await this.loadHolidays();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelHoliday() {
        this.holidayEdit = null;
    }

    get regionOptions() {
        return this.regions.map((r) => ({ label: r.name, value: r.id }));
    }

    get regionFilterOptions() {
        return [{ label: 'All regions', value: '' }, ...this.regionOptions];
    }

    get visibleHolidays() {
        const term = (this.holidaySearch || '').toLowerCase();
        return this.holidays.filter(
            (h) => (!this.holidayRegionFilter || h.Holiday_Region__c === this.holidayRegionFilter) && (!term || (h.Name || '').toLowerCase().includes(term))
        );
    }

    handleHolidayRegionFilter(event) {
        this.holidayRegionFilter = event.detail.value;
    }

    handleHolidaySearch(event) {
        this.holidaySearch = event.target.value;
    }

    async loadRegions() {
        try {
            const rows = await getHolidayRegions();
            this.regions = rows.map((r) => ({
                ...r,
                teamList: r.teams.length ? r.teams.join(', ') : '—'
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    handleNewRegion() {
        this.regionEdit = { Name: '', Description__c: '' };
    }

    handleEditRegion(event) {
        const r = this.regions.find((x) => x.id === event.currentTarget.dataset.id);
        this.regionEdit = { Id: r.id, Name: r.name, Description__c: r.description };
    }

    handleRegionField(event) {
        this.regionEdit = { ...this.regionEdit, [event.target.dataset.field]: event.target.value };
    }

    handleCancelRegion() {
        this.regionEdit = null;
    }

    async handleSaveRegion() {
        try {
            await saveHolidayRegion({ region: this.regionEdit });
            toast(this, 'Holiday region saved', this.regionEdit.Name);
            this.regionEdit = null;
            await this.loadRegions();
        } catch (e) {
            toastError(this, e, 'Could not save the region');
        }
    }

    async handleDeleteRegion(event) {
        try {
            await deleteHolidayRegion({ regionId: event.currentTarget.dataset.id });
            await this.loadRegions();
        } catch (e) {
            toastError(this, e, 'Could not delete the region');
        }
    }

    // ---------------------------------------------------------------- shifts

    async loadShifts() {
        try {
            this.shifts = await getShifts();
        } catch (e) {
            this.fail(e);
        }
    }

    handleNewShift() {
        this.openShift({
            Name: '',
            Timezone__c: 'Europe/London',
            Schedule__c: '{"MON":["09:00-17:00"],"TUE":["09:00-17:00"],"WED":["09:00-17:00"],"THU":["09:00-17:00"],"FRI":["09:00-17:00"]}'
        });
    }

    handleEditShift(event) {
        this.openShift(cleanRecord(this.shifts.find((x) => x.Id === event.currentTarget.dataset.id)));
    }

    openShift(shift) {
        this.shiftEdit = shift;
        let schedule = {};
        try {
            schedule = JSON.parse(shift.Schedule__c || '{}');
        } catch {
            schedule = {};
        }
        this.shiftDays = DAYS.map((d) => {
            const blocks = (schedule[d.code] || []).map((b) => {
                const overnight = b.endsWith('+1');
                const [start, end] = b.replace('+1', '').split('-');
                return { start: start.trim(), end: end.trim(), overnight };
            });
            while (blocks.length < 3) {
                blocks.push({ start: '', end: '', overnight: false });
            }
            return {
                code: d.code,
                label: d.label,
                blocks: blocks.map((b, i) => ({ ...b, key: d.code + i, index: i }))
            };
        });
    }

    handleShiftField(event) {
        this.shiftEdit = {
            ...this.shiftEdit,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    handleBlock(event) {
        const { day, index, part } = event.target.dataset;
        const value = eventValue(event);
        this.shiftDays = this.shiftDays.map((d) => {
            if (d.code !== day) {
                return d;
            }
            return {
                ...d,
                blocks: d.blocks.map((b) => (b.index !== Number(index) ? b : { ...b, [part]: value }))
            };
        });
    }

    handleCopyToAll(event) {
        const source = this.shiftDays.find((d) => d.code === event.currentTarget.dataset.day);
        this.shiftDays = this.shiftDays.map((d) => ({
            ...d,
            blocks: source.blocks.map((b) => ({ ...b, key: d.code + b.index }))
        }));
    }

    scheduleJson() {
        const out = {};
        this.shiftDays.forEach((d) => {
            const blocks = d.blocks.filter((b) => b.start && b.end).map((b) => b.start.slice(0, 5) + '-' + b.end.slice(0, 5) + (b.overnight ? '+1' : ''));
            if (blocks.length) {
                out[d.code] = blocks;
            }
        });
        return JSON.stringify(out);
    }

    async handleSaveShift() {
        try {
            await saveShift({
                shift: { ...this.shiftEdit, Schedule__c: this.scheduleJson() }
            });
            this.shiftEdit = null;
            toast(this, 'Shift saved', '');
            await this.loadShifts();
        } catch (e) {
            toastError(this, e, 'Could not save shift');
        }
    }

    async handleDeleteShift(event) {
        try {
            await deleteShift({ shiftId: event.currentTarget.dataset.id });
            await this.loadShifts();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleCancelShift() {
        this.shiftEdit = null;
    }

    // ---------------------------------------------------------------- roster and calendar

    handleTeam(event) {
        this.teamId = event.detail.value;
        this.loadRoster();
        this.loadCalendar();
    }

    async loadRoster() {
        try {
            const rows = await getRoster({ teamId: this.teamId || null });
            this.roster = rows.map((r) => ({
                ...r,
                since: r.minutesOffline !== null && r.minutesOffline !== undefined ? 'offline for ' + r.minutesOffline + ' min' : '',
                badge: r.availability === 'Available' ? 'slds-badge slds-theme_success' : 'slds-badge slds-theme_warning'
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    async handleRosterToggle(event) {
        try {
            await setUsersOnline({
                userIds: [event.target.dataset.id],
                online: event.target.checked,
                reason: 'Manager override'
            });
            await this.loadRoster();
        } catch (e) {
            toastError(this, e);
        }
    }

    get monthDate() {
        return this.month ? this.month + '-01' : null;
    }

    handleMonth(event) {
        this.month = event.target.value ? event.target.value.slice(0, 7) : null;
        this.loadCalendar();
    }

    async loadCalendar() {
        if (!this.teamId || !this.month) {
            return;
        }
        const [y, m] = this.month.split('-').map((x) => parseInt(x, 10));
        try {
            const days = await getCalendar({
                teamId: this.teamId,
                year: y,
                month: m
            });
            this.calendar = days.map((d) => ({
                ...d,
                key: d.day,
                cls: d.holiday ? 'cal-day holiday' : 'cal-day',
                label: d.day.slice(8),
                info: d.holiday ? d.holidayName : d.working + ' working · ' + d.outOfOffice + ' OOO'
            }));
        } catch (e) {
            this.fail(e);
        }
    }

    get hasCalendar() {
        return this.calendar.length > 0;
    }
}
