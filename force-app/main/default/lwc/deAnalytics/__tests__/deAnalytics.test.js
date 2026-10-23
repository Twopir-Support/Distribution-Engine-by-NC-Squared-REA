import { createElement } from 'lwc';
import DeAnalytics from 'c/deAnalytics';
import getAnalytics from '@salesforce/apex/DE_ConsoleController.getAnalytics';
import getTeams from '@salesforce/apex/DE_AdminController.getTeams';
import { SERIES_COLORS, OTHER_COLOR } from 'c/deUtils';

jest.mock('@salesforce/apex/DE_ConsoleController.getAnalytics', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_ConsoleController.getTeamPerformance', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_AdminController.getTeams', () => ({ default: jest.fn() }), { virtual: true });

function payload(seriesNames) {
    const overTime = [];
    seriesNames.forEach((name, i) => {
        overTime.push({ x: '2026-10-01', series: name, y: 100 - i });
        overTime.push({ x: '2026-10-02', series: name, y: 50 - i });
    });
    return { overTime, hourly: [], timeToAction: [], userActivity: [] };
}

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function legend(el) {
    return Array.from(el.shadowRoot.querySelectorAll('ul.legend li')).map((li) => ({
        name: li.textContent,
        style: li.querySelector('.swatch').getAttribute('style')
    }));
}

describe('c-de-analytics', () => {
    beforeEach(() => {
        getTeams.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function build() {
        const el = createElement('c-de-analytics', { is: DeAnalytics });
        document.body.appendChild(el);
        return el;
    }

    it('names up to seven series with palette colours in alphabetical order and no Other', async () => {
        getAnalytics.mockResolvedValue(payload(['Support', 'Inbound', 'Partners']));
        const el = build();
        await flushPromises();
        const items = legend(el);
        expect(items.map((i) => i.name)).toEqual(['Inbound', 'Partners', 'Support']);
        expect(items[0].style).toContain(SERIES_COLORS[0]);
        expect(items[2].style).toContain(SERIES_COLORS[2]);
    });

    it('keeps the six largest series and folds the rest into a neutral Other', async () => {
        const names = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9'];
        getAnalytics.mockResolvedValue(payload(names));
        const el = build();
        await flushPromises();
        const items = legend(el);
        expect(items).toHaveLength(7);
        expect(items.map((i) => i.name)).toEqual(['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'Other']);
        expect(items[6].style).toContain(OTHER_COLOR);
    });

    it('keeps a series colour when another series is filtered out', async () => {
        getAnalytics.mockResolvedValue(payload(['Alpha', 'Bravo', 'Charlie']));
        const el = build();
        await flushPromises();
        const before = legend(el).find((i) => i.name === 'Bravo').style;
        el.remove();

        getAnalytics.mockResolvedValue(payload(['Bravo', 'Charlie', 'Alpha']));
        const again = build();
        await flushPromises();
        expect(legend(again).find((i) => i.name === 'Bravo').style).toBe(before);
    });

    it('shows the load error', async () => {
        getAnalytics.mockRejectedValue({ body: { message: 'Not allowed' } });
        const el = build();
        await flushPromises();
        expect(el.shadowRoot.textContent).toContain('Not allowed');
    });
});
