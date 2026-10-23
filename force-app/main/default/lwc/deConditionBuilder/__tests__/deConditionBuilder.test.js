import { createElement } from 'lwc';
import DeConditionBuilder from 'c/deConditionBuilder';
import getFieldOptions from '@salesforce/apex/DE_AdminController.getFieldOptions';

jest.mock(
    '@salesforce/apex/DE_AdminController.getFieldOptions',
    () => {
        return { default: jest.fn() };
    },
    { virtual: true }
);

const FIELDS = [
    { label: 'Industry', value: 'Industry', type: 'PICKLIST', picklistValues: ['Retail', 'Banking'] },
    { label: 'Country', value: 'Country', type: 'STRING', picklistValues: [] }
];

function findInput(el, predicate) {
    return Array.from(el.shadowRoot.querySelectorAll('lightning-input')).find(predicate) || null;
}

function flushPromises() {
    return Promise.resolve().then(() => Promise.resolve());
}

describe('c-de-condition-builder', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function build(props) {
        const el = createElement('c-de-condition-builder', { is: DeConditionBuilder });
        Object.assign(el, props);
        document.body.appendChild(el);
        return el;
    }

    it('loads field options for the object and renders the given rows', async () => {
        getFieldOptions.mockResolvedValue(FIELDS);
        const el = build({
            objectName: 'Lead',
            conditions: [{ Sequence__c: 1, Field_API_Name__c: 'Industry', Operator__c: 'equals', Value__c: 'Retail' }]
        });
        await flushPromises();
        expect(getFieldOptions).toHaveBeenCalledWith({ objectName: 'Lead', includeClassifier: false });
        const combos = el.shadowRoot.querySelectorAll('lightning-combobox');
        expect(combos.length).toBe(2);
        expect(combos[0].value).toBe('Industry');
        expect(el.conditions).toEqual([{ Sequence__c: 1, Field_API_Name__c: 'Industry', Operator__c: 'equals', Value__c: 'Retail' }]);
    });

    it('marks unknown field paths as custom and shows a path input', async () => {
        getFieldOptions.mockResolvedValue(FIELDS);
        const el = build({
            objectName: 'Lead',
            conditions: [{ Sequence__c: 1, Field_API_Name__c: 'DE.Territory', Operator__c: 'equals', Value__c: 'EMEA' }]
        });
        await flushPromises();
        const pathInput = findInput(el, (i) => i.label === 'Field path');
        expect(pathInput).not.toBeNull();
        expect(pathInput.value).toBe('DE.Territory');
    });

    it('fires change with conditions and logic when a row is added and logic typed', async () => {
        getFieldOptions.mockResolvedValue(FIELDS);
        const el = build({ objectName: 'Lead', showLogic: true });
        await flushPromises();
        const handler = jest.fn();
        el.addEventListener('change', handler);

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.conditions).toEqual([{ Sequence__c: 1, Field_API_Name__c: '', Operator__c: 'equals', Value__c: '' }]);

        const logic = findInput(el, (i) => i.label === 'Filter logic (optional)');
        logic.value = '1';
        logic.dispatchEvent(new CustomEvent('change'));
        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler.mock.calls[1][0].detail.logic).toBe('1');
    });

    it('drops the value for blank operators', async () => {
        getFieldOptions.mockResolvedValue(FIELDS);
        const el = build({
            objectName: 'Lead',
            conditions: [{ Sequence__c: 1, Field_API_Name__c: 'Country', Operator__c: 'is blank', Value__c: 'stale' }]
        });
        await flushPromises();
        expect(el.conditions[0].Value__c).toBeNull();
    });

    it('uses member operators and no field lookup in member mode', async () => {
        const el = build({ mode: 'member', conditions: [{ Field_API_Name__c: 'Tag:Language', Value__c: 'French' }] });
        await flushPromises();
        expect(getFieldOptions).not.toHaveBeenCalled();
        expect(el.conditions[0].Operator__c).toBe('includes');
        const operator = el.shadowRoot.querySelector('lightning-combobox');
        expect(operator.options.map((o) => o.value)).toEqual(['includes', 'includes all', 'does not include']);
    });

    it('shows the load error when field options fail', async () => {
        getFieldOptions.mockRejectedValue({ body: { message: 'Unknown object' } });
        const el = build({ objectName: 'Nope__c' });
        await flushPromises();
        expect(el.shadowRoot.querySelector('.slds-text-color_error').textContent).toBe('Unknown object');
    });
});
