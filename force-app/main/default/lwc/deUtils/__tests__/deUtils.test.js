import { reduceErrors, cleanConditions, cleanRecord, eventValue, options, minutesUntil, recordUrl, clone, SERIES_COLORS, OTHER_COLOR } from 'c/deUtils';

describe('c-de-utils', () => {
    it('reduces Apex, page and field errors to messages', () => {
        expect(reduceErrors({ body: { message: 'Apex failed' } })).toBe('Apex failed');
        expect(reduceErrors({ body: [{ message: 'a' }, { message: 'b' }] })).toBe('a, b');
        expect(reduceErrors({ body: { pageErrors: [{ message: 'page' }] } })).toBe('page');
        expect(reduceErrors({ body: { pageErrors: [], fieldErrors: { Name: [{ message: 'required' }] } } })).toBe('required');
        expect(reduceErrors([new Error('js'), 'plain', null])).toBe('js\nplain');
    });

    it('keeps only the condition fields Apex needs and numbers rows', () => {
        const out = cleanConditions([
            { key: 'x', Field_API_Name__c: 'Industry', Operator__c: 'equals', Value__c: 'Retail' },
            { Sequence__c: 5, Field_API_Name__c: 'Country', Operator__c: 'in', Value__c: 'UK;FR' }
        ]);
        expect(out).toEqual([
            { Sequence__c: 1, Field_API_Name__c: 'Industry', Operator__c: 'equals', Value__c: 'Retail' },
            { Sequence__c: 5, Field_API_Name__c: 'Country', Operator__c: 'in', Value__c: 'UK;FR' }
        ]);
        expect(cleanConditions(null)).toEqual([]);
    });

    it('strips relationship, attribute and child list keys from records', () => {
        const out = cleanRecord({
            attributes: { type: 'DE_Team__c' },
            Id: 'a01',
            Name: 'T',
            Owner: { Name: 'x' },
            Members__r: [],
            Active__c: false,
            Note__c: null
        });
        expect(out).toEqual({ Id: 'a01', Name: 'T', Active__c: false, Note__c: null });
    });

    it('reads checkbox, combobox and input values from change events', () => {
        expect(eventValue({ target: { type: 'checkbox', checked: true } })).toBe(true);
        expect(eventValue({ target: { type: 'text', value: 'ignored' }, detail: { value: 'picked' } })).toBe('picked');
        expect(eventValue({ target: { type: 'text', value: 'typed' }, detail: {} })).toBe('typed');
    });

    it('builds options, urls and clones', () => {
        expect(options(['A'])).toEqual([{ label: 'A', value: 'A' }]);
        expect(recordUrl('001x')).toBe('/001x');
        expect(recordUrl(null)).toBeNull();
        const src = { a: [1, { b: 2 }] };
        const copy = clone(src);
        expect(copy).toEqual(src);
        expect(copy).not.toBe(src);
        expect(clone(undefined)).toBeUndefined();
    });

    it('computes minutes until a timestamp', () => {
        expect(minutesUntil(null)).toBeNull();
        const inTen = new Date(Date.now() + 10 * 60000).toISOString();
        expect(minutesUntil(inTen)).toBe(10);
    });

    it('exposes a fixed seven-colour categorical palette with a neutral Other', () => {
        expect(SERIES_COLORS).toHaveLength(7);
        expect(new Set(SERIES_COLORS).size).toBe(7);
        expect(SERIES_COLORS).not.toContain(OTHER_COLOR);
    });
});
