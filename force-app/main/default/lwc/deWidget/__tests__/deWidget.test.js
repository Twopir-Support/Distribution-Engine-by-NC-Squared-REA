import { createElement } from 'lwc';
import DeWidget from 'c/deWidget';
import getState from '@salesforce/apex/DE_WidgetController.getState';
import toggle from '@salesforce/apex/DE_WidgetController.toggle';
import pull from '@salesforce/apex/DE_WidgetController.pull';
import { subscribe } from 'lightning/empApi';

jest.mock('@salesforce/apex/DE_WidgetController.getState', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_WidgetController.toggle', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_WidgetController.pull', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_WidgetController.reject', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DE_WidgetController.createOutOfOffice', () => ({ default: jest.fn() }), { virtual: true });

const STATE = {
    online: true,
    reason: null,
    offlineUntil: null,
    toggleReasons: ['Meeting', 'Lunch'],
    timerDurations: [15, 30],
    timerOnly: false,
    rejectReasons: ['Duplicate'],
    allowOtherReason: true,
    pullOptions: [{ distributorId: 'a03000000000001', distributorName: 'Backlog', waiting: 4 }],
    assigned: [{ recordId: '00Q000000000001', name: 'Ada Lovelace', canReject: true, slaMissed: 0, nextSlaCheck: null }],
    missedSlas: []
};

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-de-widget', () => {
    beforeEach(() => {
        subscribe.mockResolvedValue({ channel: '/event/DE_Assignment_Event__e' });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function build() {
        const el = createElement('c-de-widget', { is: DeWidget });
        document.body.appendChild(el);
        return el;
    }

    it('loads state and subscribes to the assignment channel', async () => {
        getState.mockResolvedValue(STATE);
        const el = build();
        await flushPromises();
        expect(getState).toHaveBeenCalled();
        expect(subscribe).toHaveBeenCalledWith('/event/DE_Assignment_Event__e', -1, expect.any(Function));
        expect(el.shadowRoot.textContent).toContain('Online');
        expect(el.shadowRoot.textContent).toContain('Ada Lovelace');
    });

    it('offers a pull button per pull distributor with the waiting count', async () => {
        getState.mockResolvedValue(STATE);
        pull.mockResolvedValue({ recordIds: ['00Q000000000002'], recordNames: ['Grace Hopper'], message: null });
        const el = build();
        await flushPromises();
        const button = el.shadowRoot.querySelector('lightning-button[data-id="a03000000000001"]');
        expect(button.label).toBe('Get next: Backlog (4 waiting)');
        button.click();
        await flushPromises();
        expect(pull).toHaveBeenCalledWith({ distributorId: 'a03000000000001' });
        expect(getState).toHaveBeenCalledTimes(2);
    });

    it('goes online directly when offline', async () => {
        getState.mockResolvedValue({ ...STATE, online: false, reason: 'Lunch' });
        toggle.mockResolvedValue(null);
        const el = build();
        await flushPromises();
        expect(el.shadowRoot.textContent).toContain('Offline');
        Array.from(el.shadowRoot.querySelectorAll('lightning-input'))
            .find((i) => i.type === 'toggle')
            .dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(toggle).toHaveBeenCalledWith({ online: true, reason: null, timerMinutes: null });
    });

    it('shows the error when state cannot load', async () => {
        getState.mockRejectedValue({ body: { message: 'No access' } });
        const el = build();
        await flushPromises();
        expect(el.shadowRoot.textContent).toContain('No access');
    });
});
