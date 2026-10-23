import { createElement } from 'lwc';
import DeHistory from 'c/deHistory';
import getHistory from '@salesforce/apex/DE_HistoryController.getHistory';
import getTrackedObjects from '@salesforce/apex/DE_HistoryController.getTrackedObjects';

jest.mock('@salesforce/apex/DE_HistoryController.getHistory', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_HistoryController.getTrackedObjects', () => ({ default: jest.fn() }), { virtual: true });

const ROWS = [
    {
        Id: 'a0H1',
        Object_API_Name__c: 'DE_Team__c',
        Record_Name__c: 'Inbound',
        Change_Type__c: 'Updated',
        Field__c: 'Active__c',
        Old_Value__c: 'false',
        New_Value__c: 'true',
        Changed_At__c: '2026-10-01T10:00:00.000Z',
        Changed_By__r: { Name: 'Ada Admin' },
        Background_Change__c: false
    }
];

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-de-history', () => {
    beforeEach(() => {
        getTrackedObjects.mockResolvedValue([{ label: 'Distribution Team', value: 'DE_Team__c' }]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads the history of the parent record with user and object labels', async () => {
        getHistory.mockResolvedValue(ROWS);
        const el = createElement('c-de-history', { is: DeHistory });
        el.parentId = 'a001';
        document.body.appendChild(el);
        await flushPromises();

        expect(getHistory).toHaveBeenCalledWith({ parentId: 'a001', objectName: null });
        const table = el.shadowRoot.querySelector('lightning-datatable');
        expect(table.data[0].user).toBe('Ada Admin');
        expect(table.data[0].objectLabel).toBe('Distribution Team');
    });

    it('reloads when the object filter changes and shows an empty state', async () => {
        getHistory.mockResolvedValue([]);
        const el = createElement('c-de-history', { is: DeHistory });
        el.showObjectFilter = true;
        document.body.appendChild(el);
        await flushPromises();
        expect(el.shadowRoot.textContent).toContain('No changes recorded.');

        const combo = el.shadowRoot.querySelector('lightning-combobox');
        combo.dispatchEvent(new CustomEvent('change', { detail: { value: 'DE_Team__c' } }));
        await flushPromises();
        expect(getHistory).toHaveBeenLastCalledWith({ parentId: null, objectName: 'DE_Team__c' });
    });

    it('shows load errors', async () => {
        getHistory.mockRejectedValue({ body: { message: 'You do not have permission to view change history.' } });
        const el = createElement('c-de-history', { is: DeHistory });
        document.body.appendChild(el);
        await flushPromises();
        expect(el.shadowRoot.textContent).toContain('You do not have permission');
    });
});
