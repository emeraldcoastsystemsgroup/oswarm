const fs = require('node:fs');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const safeError = value => String(value).replace(/Bearer\s+[^\s\u001b]+/gi, 'Bearer [redacted]');
(async () => {
    const [base, passwordFile] = process.argv.slice(2);
    const endpoint = new URL(base);
    assert.ok(endpoint.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(endpoint.hostname) && !['38788', '8787'].includes(endpoint.port), 'requires a disposable loopback kernel');
    const signed = await (await fetch(base + '/sessions', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: 'admin', password: fs.readFileSync(passwordFile, 'utf8').trim() }) })).json();
    const browser = await chromium.launch({ headless: true, args: ['--disable-dev-shm-usage'] });
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, extraHTTPHeaders: { Authorization: 'Bearer ' + signed.session } });
    await context.route('**/*', r => new URL(r.request().url()).origin === base ? r.continue() : r.abort());
    const page = await context.newPage();
    let id;
    let builtSpec;
    page.on('response', async (response) => { if (response.url().endsWith('/plant-spec') && response.status() === 200)
        builtSpec = (await response.json()).spec; });
    const json = async (response) => { const value = await response.json(); assert.ok(response.ok(), JSON.stringify(value).slice(0, 800)); return value; };
    const api = async (method, path, data) => json(await context.request.fetch(base + path, { method, timeout: 180000, ...(data ? { data } : {}) }));
    const reload = async () => { await page.reload(); await page.locator('#studio[data-ready="1"]').waitFor({ timeout: 60000 }); };
    try {
        const response = await context.request.post(base + '/api/design-studio/projects', { data: { example: 'lift-1' } });
        const created = await response.json();
        assert.equal(response.status(), 201, JSON.stringify(created));
        id = created.project.id;
        await page.goto(base + '/api/design-studio/app?theme=midnight#/product/' + id);
        await page.locator('#studio[data-ready="1"]').waitFor({ timeout: 60000 });
        await page.click('#act-brief');
        await page.locator('#close-dialog[open]').waitFor({ timeout: 5000 });
        await page.click('#close-dialog button[value="close"]');
        await page.locator('#poster-brief[data-closed="1"]').waitFor({ timeout: 30000 });
        console.log('ok: owner confirmed the example brief');
        await page.click('#act-design');
        await page.locator('#make-close:not([disabled])').waitFor({ timeout: 120000 });
        await page.click('#make-close');
        await page.locator('#poster-design[data-stage="parts-complete"]').waitFor({ timeout: 60000 });
        console.log('ok: actual browser created CAD parts and closed the parts dialog');
        await page.click('#act-design');
        await page.locator('#close-dialog[open]').waitFor({ timeout: 5000 });
        await page.click('#close-dialog button[value="close"]');
        await page.locator('#poster-design[data-closed="1"]').waitFor({ timeout: 30000 });
        console.log('ok: owner closed Design against the real part revisions');
        await page.click('#act2-design');
        await page.locator('#studio[data-screen="mechanism"][data-ready="1"]').waitFor({ timeout: 30000 });
        const parts = await page.locator('#mech-parts li').allTextContents();
        assert.equal(parts.length, 3, parts.join('\n'));
        console.log('ok: mechanism uses three real CAD reports');
        await page.click('#mech-save');
        await page.locator('#studio[data-screen="product"][data-ready="1"]').waitFor({ timeout: 30000 });
        await page.click('#act-simulate');
        await page.locator('#poster-simulate[data-stage="built"]').waitFor({ timeout: 90000 });
        console.log('ok: browser built the real managed MuJoCo plant');
        await page.click('#act-simulate');
        await page.locator('#poster-simulate[data-stage="baseline"]').waitFor({ timeout: 180000 });
        console.log('ok: browser ran the real baseline');
        assert.ok(builtSpec, 'the page supplied a real plant spec');
        const listing = await api('GET', '/api/embodied/physics/reports');
        const baseline = listing.reports.find(r => r.file === `plant-${id}-reach-seed0.json`).report;
        const trained = await api('POST', '/api/embodied/physics/plant/train', { project: id, spec: builtSpec, task: baseline.taskSpec, timesteps: 2048, seed: 0 });
        assert.equal(trained.started, true);
        const until = Date.now() + 600000;
        while (true) {
            const { jobs } = await api('GET', '/api/embodied/physics/plant/train');
            const job = jobs.find(j => j.file === trained.job.file);
            assert.ok(!job.error, JSON.stringify(job));
            if (job.state === 'done')
                break;
            assert.ok(Date.now() < until, 'training timeout');
            await new Promise(r => setTimeout(r, 1000));
        }
        await reload();
        await page.locator('#poster-simulate[data-stage="trained"]').waitFor({ timeout: 60000 });
        console.log('ok: page reads the completed short PPO training run');
        const gate = page.waitForResponse(r => r.request().method() === 'POST' && new URL(r.url()).pathname.endsWith('/certify'), { timeout: 180000 });
        await page.click('#act-simulate');
        await json(await gate);
        let certificate;
        for (let n = 0; n < 30; n++) {
            const reports = await api('GET', '/api/embodied/physics/reports');
            certificate = reports.reports.find(r => r.file === `plant-${id}-reach-ppo-seed0.certificate.json`);
            if (certificate)
                break;
            await new Promise(r => setTimeout(r, 1000));
        }
        assert.ok(certificate, 'the real certification result exists');
        if (certificate.report.ok) {
            await page.locator('#poster-simulate[data-stage="certified"]').waitFor({ timeout: 30000 });
            await page.click('#act-simulate');
            await page.locator('#close-dialog[open]').waitFor({ timeout: 5000 });
            await page.click('#close-dialog button[value="close"]');
            await page.locator('#poster-simulate[data-closed="1"]').waitFor({ timeout: 30000 });
            const body = await api('GET', `/api/design-studio/projects/${id}/body`);
            assert.equal(body.walker.kind, 'certified-policy');
            console.log('ok: browser closed the safety-certified Simulation phase and read its body contract');
        }
        else
            console.log('gate refused short policy; phase correctly remains open', JSON.stringify(certificate.report.refused));
        console.log('real certification verdict', JSON.stringify({ safetyPassed: certificate.report.ok, policyBeatsBaseline: certificate.report.policyBeatsBaseline, performanceVerdict: certificate.report.verdict, simulationClosed: await page.locator('#poster-simulate').getAttribute('data-closed') === '1' }));
        await page.click('#act-fabricate');
        await page.locator('#make-dialog[open]').waitFor({ timeout: 5000 });
        await page.locator('#make-close:not([disabled])').waitFor({ timeout: 180000 });
        assert.match(await page.locator('#make-result').innerText(), /^3 of 3 parts exported watertight/);
        await page.click('#make-close');
        await page.locator('#poster-fabricate[data-stage="fabricated"]').waitFor({ timeout: 60000 });
        const printSet = await api('GET', `/api/design-studio/projects/${id}/print-set`);
        assert.equal(printSet.exported, 3);
        for (const part of printSet.manifest.parts) {
            const exported = await context.request.get(base + `/api/design-studio/projects/${id}/print-set/${encodeURIComponent(part.file)}`);
            assert.ok(exported.ok(), `missing printable file ${part.file}`);
            assert.equal(createHash('sha256').update(await exported.body()).digest('hex'), part.sha256);
        }
        await page.click('#act-fabricate');
        await page.locator('#close-dialog[open]').waitFor({ timeout: 5000 });
        await page.click('#close-dialog button[value="close"]');
        await page.locator('#poster-fabricate[data-closed="1"]').waitFor({ timeout: 30000 });
        console.log('ok: browser made three watertight printable parts, verified their bytes and closed Fabricate');
        if (process.env.ENGINE_WORKFLOW_SHOTS)
            await page.screenshot({ path: process.env.ENGINE_WORKFLOW_SHOTS + '-1280.png', fullPage: true });
        await page.setViewportSize({ width: 412, height: 915 });
        await page.reload();
        await page.locator('#studio[data-ready="1"]').waitFor({ timeout: 60000 });
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth), 0);
        if (process.env.ENGINE_WORKFLOW_SHOTS)
            await page.screenshot({ path: process.env.ENGINE_WORKFLOW_SHOTS + '-412.png', fullPage: true });
        console.log('browser artifact/phase checks passed; learned quality reported separately', JSON.stringify({ project: id, parts }));
    }
    catch (e) {
        console.log('browser failure', safeError(e.message));
        console.log((await page.locator('body').innerText()).slice(-5000));
        if (process.env.ENGINE_WORKFLOW_SHOTS)
            await page.screenshot({ path: process.env.ENGINE_WORKFLOW_SHOTS + '-failure.png', fullPage: true });
        throw e;
    }
    finally {
        await context.close();
        await browser.close();
    }
})().catch(e => { console.error(safeError(e.stack)); process.exitCode = 1; });
