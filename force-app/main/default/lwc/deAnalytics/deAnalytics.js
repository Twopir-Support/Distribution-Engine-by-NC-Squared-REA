import { LightningElement } from 'lwc';
import getAnalytics from '@salesforce/apex/DE_ConsoleController.getAnalytics';
import getTeamPerformance from '@salesforce/apex/DE_ConsoleController.getTeamPerformance';
import getTeams from '@salesforce/apex/DE_AdminController.getTeams';
import { reduceErrors, toastError, options, eventValue, SERIES_COLORS, OTHER_COLOR } from 'c/deUtils';

const W = 760;
const H = 260;
const PAD = { left: 48, right: 12, top: 12, bottom: 36 };
const MAX_SERIES = 7;
const PERF_COLUMNS = [
    { label: 'Member', fieldName: 'name' },
    { label: 'Assigned', fieldName: 'assigned', type: 'number' },
    { label: 'Actioned %', fieldName: 'actionedPercent', type: 'number' },
    {
        label: 'Avg time to action (min)',
        fieldName: 'avgTimeToAction',
        type: 'number'
    },
    {
        label: 'Avg speed to assign (s)',
        fieldName: 'avgSpeedToAssignSeconds',
        type: 'number'
    },
    { label: 'SLAs missed', fieldName: 'slasMissed', type: 'number' },
    { label: 'Reassigned', fieldName: 'reassignments', type: 'number' },
    { label: 'Rejected', fieldName: 'rejected', type: 'number' },
    { label: 'Lead conversion %', fieldName: 'conversionPercent', type: 'number' }
];

function niceMax(v) {
    if (v <= 0) {
        return 1;
    }
    const p = Math.pow(10, Math.floor(Math.log10(v)));
    const n = v / p;
    const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return step * p;
}

/** Top-rounded bar path (4px data-end) anchored at the baseline. */
function barPath(x, y, w, h, rounded) {
    if (h <= 0 || w <= 0) {
        return '';
    }
    const r = rounded ? Math.min(4, w / 2, h) : 0;
    return `M${x},${y + h} L${x},${y + r} Q${x},${y} ${x + r},${y} L${x + w - r},${y} Q${x + w},${y} ${x + w},${y + r} L${x + w},${y + h} Z`;
}

function hBarPath(x, y, w, h) {
    if (h <= 0 || w <= 0) {
        return '';
    }
    const r = Math.min(4, h / 2, w);
    return `M${x},${y} L${x + w - r},${y} Q${x + w},${y} ${x + w},${y + r} L${x + w},${y + h - r} Q${x + w},${y + h} ${x + w - r},${y + h} L${x},${y + h} Z`;
}

/** Distribution Analytics tab. */
export default class DeAnalytics extends LightningElement {
    filter = {
        fromDate: null,
        toDate: null,
        teamId: '',
        objectName: '',
        splitBy: 'User'
    };
    teamOptions = [{ label: 'All teams', value: '' }];
    splitOptions = options(['User', 'Distributor']);
    data;
    performance = [];
    perfColumns = PERF_COLUMNS;
    error;
    tip;
    showTables = false;
    width = W;
    height = H;

    connectedCallback() {
        const today = new Date();
        const from = new Date(today.getTime() - 30 * 86400000);
        this.filter = {
            ...this.filter,
            fromDate: from.toISOString().slice(0, 10),
            toDate: today.toISOString().slice(0, 10)
        };
        getTeams()
            .then((teams) => {
                this.teamOptions = [{ label: 'All teams', value: '' }, ...teams.map((t) => ({ label: t.team.Name, value: t.team.Id }))];
            })
            .catch(() => {});
        this.load();
    }

    handleFilter(event) {
        this.filter = {
            ...this.filter,
            [event.target.dataset.field]: eventValue(event)
        };
    }

    async load() {
        try {
            this.data = await getAnalytics({
                fromDate: this.filter.fromDate,
                toDate: this.filter.toDate,
                teamId: this.filter.teamId || null,
                objectName: this.filter.objectName || null,
                splitBy: this.filter.splitBy
            });
            this.performance = this.filter.teamId
                ? await getTeamPerformance({
                      teamId: this.filter.teamId,
                      fromDate: this.filter.fromDate,
                      toDate: this.filter.toDate
                  })
                : [];
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get hasTeam() {
        return !!this.filter.teamId;
    }

    toggleTables() {
        this.showTables = !this.showTables;
    }

    get viewBox() {
        return `0 0 ${W} ${H}`;
    }

    // ---------------------------------------------------------------- series helpers

    /** Keeps the largest series in fixed palette order; the rest fold into "Other". */
    seriesOf(points) {
        const totals = new Map();
        points.forEach((p) => totals.set(p.series || '(none)', (totals.get(p.series || '(none)') || 0) + Number(p.y || 0)));
        const names = [...totals.keys()].sort((a, b) => totals.get(b) - totals.get(a));
        // Up to 7 named series get the 7 palette slots; beyond that the top 6 stay and the rest fold into "Other".
        const kept = names.length > MAX_SERIES ? names.slice(0, MAX_SERIES - 1) : names;
        const colors = new Map();
        // Colour follows the entity (alphabetical), never its rank.
        [...kept].sort().forEach((n, i) => colors.set(n, SERIES_COLORS[i]));
        return { kept: new Set(kept), colors, fold: names.length > kept.length };
    }

    // ---------------------------------------------------------------- over time (stacked columns)

    get overTime() {
        const points = this.data ? this.data.overTime : [];
        if (!points.length) {
            return null;
        }
        const { kept, colors, fold } = this.seriesOf(points);
        const days = [...new Set(points.map((p) => p.x))].sort();
        const stacks = new Map(days.map((d) => [d, []]));
        points.forEach((p) => {
            const name = kept.has(p.series || '(none)') ? p.series || '(none)' : 'Other';
            const s = stacks.get(p.x);
            const existing = s.find((e) => e.name === name);
            if (existing) {
                existing.y += Number(p.y);
            } else {
                s.push({ name, y: Number(p.y) });
            }
        });
        const order = [...colors.keys()].sort();
        if (fold) {
            order.push('Other');
            colors.set('Other', OTHER_COLOR);
        }
        const max = niceMax(Math.max(...days.map((d) => stacks.get(d).reduce((a, b) => a + b.y, 0))));
        const plotW = W - PAD.left - PAD.right;
        const plotH = H - PAD.top - PAD.bottom;
        const slot = plotW / days.length;
        const barW = Math.max(2, Math.min(28, slot * 0.7));
        const marks = [];
        const labels = [];
        days.forEach((d, i) => {
            let base = PAD.top + plotH;
            const x = PAD.left + i * slot + (slot - barW) / 2;
            const segs = order.map((n) => stacks.get(d).find((s) => s.name === n)).filter((s) => s && s.y > 0);
            segs.forEach((s, j) => {
                const h = (s.y / max) * plotH;
                const top = j === segs.length - 1;
                const gap = segs.length > 1 && !top ? 2 : 0;
                marks.push({
                    key: d + s.name,
                    d: barPath(x, base - h, barW, Math.max(0, h - gap), top),
                    fill: colors.get(s.name),
                    tip: `${d} · ${s.name}: ${s.y}`
                });
                base -= h;
            });
            if (days.length <= 16 || i % Math.ceil(days.length / 12) === 0) {
                labels.push({
                    key: 'l' + d,
                    x: x + barW / 2,
                    y: H - PAD.bottom + 16,
                    text: d.slice(5)
                });
            }
        });
        return {
            marks,
            labels,
            ticks: this.ticks(max, plotH),
            legend: order.map((n) => ({
                key: n,
                name: n,
                style: `background:${colors.get(n)}`
            })),
            table: days.map((d) => ({
                key: d,
                day: d,
                values: stacks
                    .get(d)
                    .map((s) => s.name + ': ' + s.y)
                    .join(', ')
            }))
        };
    }

    ticks(max, plotH) {
        return [0, 0.25, 0.5, 0.75, 1].map((f) => ({
            key: 't' + f,
            y: PAD.top + plotH - f * plotH,
            x1: PAD.left,
            x2: W - PAD.right,
            labelX: PAD.left - 6,
            text: Math.round(max * f)
        }));
    }

    // ---------------------------------------------------------------- hourly (single series)

    get hourly() {
        const points = this.data ? this.data.hourly : [];
        if (!points.length) {
            return null;
        }
        const byHour = new Map(points.map((p) => [Number(p.x), Number(p.y)]));
        const max = niceMax(Math.max(...byHour.values()));
        const plotW = W - PAD.left - PAD.right;
        const plotH = H - PAD.top - PAD.bottom;
        const slot = plotW / 24;
        const barW = slot - 2;
        const marks = [];
        const labels = [];
        for (let h = 0; h < 24; h++) {
            const v = byHour.get(h) || 0;
            const bh = (v / max) * plotH;
            const x = PAD.left + h * slot + 1;
            if (v > 0) {
                marks.push({
                    key: 'h' + h,
                    d: barPath(x, PAD.top + plotH - bh, barW, bh, true),
                    fill: SERIES_COLORS[0],
                    tip: `${h}:00 · ${v} assignments`
                });
            }
            if (h % 3 === 0) {
                labels.push({
                    key: 'hl' + h,
                    x: x + barW / 2,
                    y: H - PAD.bottom + 16,
                    text: h + ':00'
                });
            }
        }
        return {
            marks,
            labels,
            ticks: this.ticks(max, plotH),
            table: [...byHour.entries()].sort((a, b) => a[0] - b[0]).map(([h, v]) => ({ key: 'th' + h, hour: h + ':00', value: v }))
        };
    }

    // ---------------------------------------------------------------- horizontal bars

    horizontal(points, unit) {
        if (!points || !points.length) {
            return null;
        }
        const rows = [...points]
            .filter((p) => p.y !== null)
            .sort((a, b) => Number(b.y) - Number(a.y))
            .slice(0, 15);
        const max = niceMax(Math.max(...rows.map((r) => Number(r.y))));
        const left = 160;
        const rowH = 22;
        const height = rows.length * rowH + 8;
        const plotW = W - left - 60;
        const marks = rows.map((r, i) => {
            const w = (Number(r.y) / max) * plotW;
            const y = 4 + i * rowH;
            return {
                key: 'b' + i,
                d: hBarPath(left, y + 3, w, rowH - 8),
                fill: SERIES_COLORS[0],
                tip: `${r.x}: ${r.y} ${unit}`,
                label: {
                    x: left - 6,
                    y: y + rowH / 2 + 4,
                    text: (r.x || '(none)').slice(0, 22)
                },
                value: { x: left + w + 6, y: y + rowH / 2 + 4, text: r.y }
            };
        });
        return { marks, viewBox: `0 0 ${W} ${height}` };
    }

    get timeToAction() {
        return this.horizontal(this.data ? this.data.timeToAction : [], 'min avg');
    }

    get activity() {
        const pts = this.data ? this.data.userActivity : [];
        const off = pts.filter((p) => p.series === 'Toggled off').map((p) => ({ x: p.x, y: p.y }));
        return this.horizontal(off, 'times toggled off');
    }

    // ---------------------------------------------------------------- tooltip

    handleEnter(event) {
        const rect = this.template.querySelector('.charts').getBoundingClientRect();
        this.tip = {
            text: event.target.dataset.tip,
            style: `left:${event.clientX - rect.left + 12}px;top:${event.clientY - rect.top - 8}px`
        };
    }

    handleLeave() {
        this.tip = null;
    }

    // ---------------------------------------------------------------- CSV

    handleCsv() {
        const header = PERF_COLUMNS.map((c) => c.label);
        const lines = [header.join(',')].concat(
            this.performance.map((r) => PERF_COLUMNS.map((c) => JSON.stringify(r[c.fieldName] === undefined ? '' : r[c.fieldName])).join(','))
        );
        const link = document.createElement('a');
        link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(lines.join('\n'));
        link.download = 'team-performance.csv';
        link.click();
    }

    get hasPerformance() {
        return this.performance.length > 0;
    }

    handleError(e) {
        toastError(this, e);
    }
}
