import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export const OPERATORS = [
    'equals',
    'not equals',
    'less than',
    'greater than',
    'less or equal',
    'greater or equal',
    'contains',
    'does not contain',
    'starts with',
    'does not start with',
    'ends with',
    'does not end with',
    'in',
    'not in',
    'includes',
    'includes all',
    'does not include',
    'between',
    'is blank',
    'is not blank'
].map((o) => ({ label: o, value: o }));

export const MEMBER_OPERATORS = ['includes', 'includes all', 'does not include'].map((o) => ({ label: o, value: o }));

export const CAP_PERIODS = ['Hourly', 'Half-hourly', 'Daily', 'Weekly', 'Monthly', 'Custom Minutes', 'Custom Hours', 'Custom Days', 'Active', 'Criteria'].map(
    (o) => ({ label: o, value: o })
);

export function options(values) {
    return values.map((v) => ({ label: v, value: v }));
}

/** Flattens Apex / UI API / JS errors into readable messages. */
export function reduceErrors(errors) {
    const list = Array.isArray(errors) ? errors : [errors];
    return list
        .filter((e) => !!e)
        .map((e) => {
            if (typeof e === 'string') {
                return e;
            }
            if (e.body) {
                if (Array.isArray(e.body)) {
                    return e.body.map((b) => b.message).join(', ');
                }
                if (e.body.pageErrors && e.body.pageErrors.length) {
                    return e.body.pageErrors.map((p) => p.message).join(', ');
                }
                if (e.body.fieldErrors && Object.keys(e.body.fieldErrors).length) {
                    return Object.values(e.body.fieldErrors)
                        .flat()
                        .map((f) => f.message)
                        .join(', ');
                }
                if (e.body.message) {
                    return e.body.message;
                }
            }
            return e.message || JSON.stringify(e);
        })
        .join('\n');
}

export function toast(component, title, message, variant = 'success') {
    component.dispatchEvent(
        new ShowToastEvent({
            title,
            message,
            variant,
            mode: variant === 'error' ? 'sticky' : 'dismissible'
        })
    );
}

export function toastError(component, error, title = 'Something went wrong') {
    toast(component, title, reduceErrors(error), 'error');
}

export function clone(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

/** Keeps only the condition fields Apex needs. */
export function cleanConditions(rows) {
    return (rows || []).map((r, i) => ({
        Sequence__c: r.Sequence__c || i + 1,
        Field_API_Name__c: r.Field_API_Name__c,
        Operator__c: r.Operator__c,
        Value__c: r.Value__c
    }));
}

/** Removes relationship/attribute keys so an SObject can be sent back to Apex. */
export function cleanRecord(record) {
    const out = {};
    Object.keys(record || {}).forEach((k) => {
        const v = record[k];
        if (k === 'attributes' || (v !== null && typeof v === 'object' && !Array.isArray(v))) {
            return;
        }
        if (Array.isArray(v)) {
            return;
        }
        out[k] = v;
    });
    return out;
}

export function formatDateTime(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toLocaleString();
}

export function minutesUntil(value) {
    if (!value) {
        return null;
    }
    return Math.round((new Date(value).getTime() - Date.now()) / 60000);
}

export function recordUrl(recordId) {
    return recordId ? '/' + recordId : null;
}

/** Validated categorical palette (fixed order; never cycled). Slot 8 is reserved for "Other" as neutral gray. */
export const SERIES_COLORS = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6'];
export const OTHER_COLOR = '#8a8986';

/** Value of a lightning-input / combobox / textarea / checkbox change event. */
export function eventValue(event) {
    const t = event.target;
    if (t && (t.type === 'checkbox' || t.type === 'toggle' || t.type === 'checkbox-button')) {
        return t.checked;
    }
    if (event.detail && event.detail.value !== undefined) {
        return event.detail.value;
    }
    return t ? t.value : undefined;
}
