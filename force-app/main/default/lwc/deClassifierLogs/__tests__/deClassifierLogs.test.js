import { createElement } from 'lwc';
import DeClassifierLogs from 'c/deClassifierLogs';
import getClassifierLogs from '@salesforce/apex/DE_ConsoleController.getClassifierLogs';
import retryClassification from '@salesforce/apex/DE_ConsoleController.retryClassification';

jest.mock('@salesforce/apex/DE_ConsoleController.getClassifierLogs', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_ConsoleController.retryClassification', () => ({ default: jest.fn() }), { virtual: true });

const ROW = {
    Id: 'a0T1',
    recordId: '00Q000000000001',
    recordName: 'Ada Lovelace',
    objectName: 'Lead',
    status: 'Error',
    territory: 'EMEA.UK',
    processedAt: '2026-10-01T10:00:00.000Z',
    attempts: 2,
    error: 'Bad field'
};

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-de-classifier-logs', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function build() {
        const el = createElement('c-de-classifier-logs', { is: DeClassifierLogs });
        document.body.appendChild(el);
        return el;
    }

    it('loads territory logs for the last 7 days with type-specific columns', async () => {
        getClassifierLogs.mockResolvedValue([ROW]);
        const el = build();
        await flushPromises();

        const filter = getClassifierLogs.mock.calls[0][0].filter;
        expect(filter.logType).toBe('Territory');
        expect(filter.fromDate).toBeTruthy();
        const table = el.shadowRoot.querySelector('lightning-datatable');
        expect(table.columns.map((c) => c.fieldName)).toContain('territory');
        expect(table.data[0].url).toBe('/00Q000000000001');
        expect(table.data[0].statusClass).toBe('slds-text-color_error');
    });

    it('switches log type and hides retry for object sync logs', async () => {
        getClassifierLogs.mockResolvedValue([]);
        const el = build();
        await flushPromises();
        el.shadowRoot.querySelector('lightning-combobox').dispatchEvent(new CustomEvent('change', { detail: { value: 'Object Sync' } }));
        await flushPromises();

        expect(getClassifierLogs.mock.calls[1][0].filter.logType).toBe('Object Sync');
        expect(el.shadowRoot.querySelector('lightning-datatable').columns.map((c) => c.fieldName)).toContain('actions');
        const labels = Array.from(el.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
        expect(labels).not.toContain('Classify selected again');
    });

    it('retries the selected records', async () => {
        getClassifierLogs.mockResolvedValue([ROW]);
        retryClassification.mockResolvedValue(1);
        const el = build();
        await flushPromises();
        el.shadowRoot.querySelector('lightning-datatable').dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: [ROW] } }));
        Array.from(el.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'Classify selected again')
            .click();
        await flushPromises();

        expect(retryClassification).toHaveBeenCalledWith({ recordIds: ['00Q000000000001'], logType: 'Territory' });
        expect(getClassifierLogs).toHaveBeenCalledTimes(2);
    });
});
