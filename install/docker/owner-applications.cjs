'use strict';
// Initial-owner setup uses the normal reviewed assignment lifecycle. It grants only explicit selections.
const fs = require('node:fs');
const ENGINEERING = ['design-studio', 'cad-studio', 'circuit-lab', 'embodied', 'aero-lab', 'scan-to-print'];
const ROLES = Object.fromEntries(ENGINEERING.map(app => [app, app === 'scan-to-print' ? 'maker' : '@app-admin']));
function selected(value) {
    const names = value === 'engineering' ? ENGINEERING : value.split(',').filter(Boolean);
    if (!names.length || names.some(name => !Object.hasOwn(ROLES, name)))
        throw new Error('owner-apps must be engineering or a comma-separated selection of engineering applications');
    return [...new Set(names)];
}
async function provision(input, transport = fetch) {
    const apps = selected(input.applications);
    const base = input.base || 'http://127.0.0.1:38788';
    const login = await transport(base + '/sessions', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: input.username, password: input.password }) });
    const signed = await login.json();
    if (login.status !== 201 || !signed.session)
        throw new Error('initial owner could not sign in');
    const call = async (method, path, body) => {
        const response = await transport(base + path, { method, headers: { 'content-type': 'application/json', authorization: 'Bearer ' + signed.session }, ...(body ? { body: JSON.stringify(body) } : {}) });
        const result = await response.json();
        if (!response.ok)
            throw new Error(`${path} refused (${response.status}): ${result.detail || result.error || 'no assignment was accepted'}`);
        return result;
    };
    const granted = [];
    for (const app of apps) {
        const state = await call('GET', '/api/authorization/composites');
        if (!state.administrator || !state.caller?.id || state.caller.subject !== input.username || state.caller.issuer !== 'urn:oshal:local-auth')
            throw new Error('setup requires the signed-in local first administrator');
        const existing = state.assignments.find(row => row.status === 'active' && row.assignment.target.id === state.caller.id && row.assignment.selection.app === app && row.assignment.selection.kind === 'granular' && row.assignment.selection.role === ROLES[app]);
        if (existing) {
            granted.push(app);
            continue;
        }
        const blocked = state.assignments.find(row => row.assignment.id === 'initial-owner-' + app || (row.assignment.target.id === state.caller.id && row.assignment.selection.app === app && row.assignment.selection.kind === 'granular' && row.assignment.selection.role === ROLES[app]));
        if (blocked)
            throw new Error(`${app}: existing owner assignment is ${blocked.status}; grants and revocations were preserved. Review it in Access.`);
        const change = { target: state.caller.id, assignment_id: 'initial-owner-' + app, action: 'assign', selection: { kind: 'granular', app, role: ROLES[app] }, expected_revision: state.revision, expected_plan_revision: null, expires_at: null, reason: 'The first owner selected this engineering application during installation.', idempotency_key: 'initial-owner-' + app };
        let plan;
        try { plan = await call('POST', '/api/authorization/composites/preview', change); }
        catch (error) { throw new Error(`${app}: ${error.message}`); }
        if (!plan.plan_revision)
            throw new Error(`${app} has no current supported owner role`);
        await call('POST', '/api/authorization/composites/apply', { ...change, expected_revision: plan.revision, expected_plan_revision: plan.plan_revision });
        granted.push(app);
    }
    return { applications: granted };
}
async function main() {
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    const result = await provision(input);
    process.stdout.write(JSON.stringify(result) + '\n');
}
module.exports = { selected, provision, main };
if (require.main === module)
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
