const {test,expect}=require('@playwright/test');
async function expandSteps(page){const closed=page.locator('dialog[open] details:not([open]) > summary'); while(await closed.count()) await closed.first().click();}

test('journey steps persist independently of plans and only conditional steps permit not needed',async({page})=>{
  await page.setViewportSize({width:390,height:844}); await page.goto('/');
  const tracker=page.getByRole('region',{name:'Journey steps'});
  await expect(tracker).toContainText('Transfer'); await expect(tracker).toContainText('Confirm arrival');
  await page.getByRole('button',{name:'Layover',exact:true}).click();
  await expect(tracker).toBeVisible(); await page.locator('[data-plan="coffee"]').click();
  await expect(tracker).toContainText('Confirm arrival'); await tracker.getByRole('button',{name:'View steps'}).click();
  let dialog=page.getByRole('dialog'); await expandSteps(page); await expect(dialog).toContainText('Confirm arrival');
  await expect(dialog.getByRole('button',{name:'Not needed: Confirm arrival'})).toHaveCount(0);
  await expect(dialog.getByRole('button',{name:'Not needed: Confirm baggage handling, if needed'})).toBeVisible();
  await dialog.getByRole('button',{name:'Confirm arrival',exact:true}).click(); await expandSteps(page);
  await dialog.getByRole('button',{name:'Not needed: Confirm baggage handling, if needed'}).click();
  await dialog.getByLabel('Journey stage').selectOption('departure');
  await expect(dialog).toContainText('Confirm check-in');
  await dialog.getByRole('button',{name:'Confirm check-in',exact:true}).click();
  await dialog.getByRole('button',{name:'Done',exact:true}).click();
  await expect(tracker).toContainText('Departure');
  await page.reload(); await expect(tracker).toContainText('Departure');
  await tracker.getByRole('button',{name:'View steps'}).click(); await expandSteps(page);
  await expect(dialog.getByRole('button',{name:'Undo Confirm check-in'})).toBeVisible();
  await dialog.getByLabel('Journey stage').selectOption('transfer'); await expandSteps(page);
  await expect(dialog.getByRole('button',{name:'Undo Confirm arrival'})).toBeVisible();
  await expect(dialog.getByRole('button',{name:'Undo Confirm baggage handling, if needed'})).toBeVisible();
  await expect(dialog.getByText('Confirm airport transfer')).toHaveCount(0);
  await dialog.getByRole('button',{name:'Done',exact:true}).click();
  await page.getByRole('button',{name:'Flight',exact:true}).click();
  await expect(page.locator('#my-plan article')).toContainText('A coffee before boarding');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

test('airport-transfer step appears only for a change of airport',async({page})=>{
  await page.goto('/?presenter=1');
  await page.evaluate(()=>{state.scenario='transfer';render();});
  await page.getByRole('button',{name:'View steps'}).click(); await expandSteps(page);
  await expect(page.getByRole('dialog').getByText('Confirm airport transfer')).toBeVisible();
  await expect(page.getByRole('dialog').getByRole('button',{name:'Not needed: Confirm airport transfer'})).toHaveCount(0);
  await page.getByRole('dialog').getByRole('button',{name:'Confirm airport transfer',exact:true}).click(); await expandSteps(page);
  await expect(page.getByRole('dialog').getByRole('button',{name:'Undo Confirm airport transfer'})).toBeVisible();
});


test('border preparation advice is scoped to the current stage and airport',async({page})=>{
  await page.goto('/'); await page.getByRole('button',{name:'View steps'}).click();
  const dialog=page.getByRole('dialog'); await expandSteps(page); await expect(dialog.getByRole('link',{name:'Visit Japan Web'})).toHaveCount(1);
  await expect(dialog.getByText('Confirm entry requirements separately.')).toBeVisible();
  await dialog.getByLabel('Journey stage').selectOption('departure');
  await expect(dialog.getByRole('link',{name:'Visit Japan Web'})).toHaveCount(0);
  const advice=await page.evaluate(()=>({uk:progressAdvice('arrival','LHR','passport'),japan:progressAdvice('transfer','HND','passport'),wrong:progressAdvice('departure','LHR','passport'),other:progressAdvice('arrival','SIN','passport')}));
  expect(advice.uk).toContain('gov.uk/registered-traveller'); expect(advice.uk).toContain('Check eligibility');
  expect(advice.japan).toContain('digital.go.jp'); expect(advice.wrong).toBe(''); expect(advice.other).toBe('');
});

test('past trips do not change advice for the active journey',async({page})=>{
  await page.goto('/'); await page.getByRole('button',{name:'Profile',exact:true}).click();
  await page.getByRole('button',{name:'Previous trips'}).click(); await expect(page.getByText('London Heathrow')).toBeVisible();
  await page.getByRole('button',{name:'View steps'}).click(); const dialog=page.getByRole('dialog'); await expandSteps(page);
  await expect(dialog.getByRole('link',{name:'Visit Japan Web'})).toBeVisible();
  await expect(dialog.getByRole('link',{name:'Registered Traveller'})).toHaveCount(0);
});

test('journey checklist is accessible at a narrow width',async({page})=>{
  await page.setViewportSize({width:320,height:844}); await page.goto('/');
  await page.getByRole('button',{name:'View steps'}).click();
  const dialog=page.getByRole('dialog'); await expandSteps(page); expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
  const results=await new (require('@axe-core/playwright').default)({page}).analyze();
  expect(results.violations.map(v=>v.id)).toEqual([]);
  await dialog.getByRole('button',{name:'Confirm boarding'}).scrollIntoViewIfNeeded();
  await expect(dialog.getByRole('button',{name:'Confirm boarding'})).toBeVisible();
});

for (const phase of ['arrival','departure','transfer']) {
  test(`${phase} overlay stays clear of navigation and retains progress while adding a stop`,async({page})=>{
    await page.setViewportSize({width:390,height:844}); await page.goto('/');
    const tracker=page.getByRole('region',{name:'Journey steps'});
    await tracker.getByRole('button',{name:'View steps'}).click();
    const dialog=page.getByRole('dialog'); await expandSteps(page);
    await dialog.getByLabel('Journey stage').selectOption(phase);
    const confirmation=dialog.locator('[data-progress-value="done"]').first();
    const stepId=await confirmation.getAttribute('data-progress-id');
    await confirmation.click();
    await dialog.getByRole('button',{name:'Done',exact:true}).click();
    await page.getByRole('button',{name:'Layover',exact:true}).click();
    await page.locator('[data-plan="coffee"]').click();
    await expect(tracker).toBeVisible();
    const {overlay,nav}=await page.evaluate(()=>({overlay:document.querySelector('.journey-progress').getBoundingClientRect().toJSON(),nav:document.querySelector('.bottom-nav').getBoundingClientRect().toJSON()}));
    expect(overlay.y+overlay.height).toBeLessThanOrEqual(nav.y+1);
    expect(overlay.x).toBeGreaterThanOrEqual(0); expect(overlay.x+overlay.width).toBeLessThanOrEqual(390);
    await page.reload(); await tracker.getByRole('button',{name:'View steps'}).click(); await expandSteps(page);
    await expect(dialog.getByLabel('Journey stage')).toHaveValue(phase);
    await expect(dialog.locator(`[data-progress-id="${stepId}"][data-progress-value="pending"]`)).toBeVisible();
    await dialog.getByRole('button',{name:'Done',exact:true}).click();
    await page.getByRole('button',{name:'Flight',exact:true}).click();
    await expect(page.locator('#my-plan article')).toContainText('A coffee before boarding');
  });
}

test('opening checklist from plan edit preserves unsaved duration and returns with Close',async({page})=>{
  await page.setViewportSize({width:390,height:844}); await page.goto('/');
  await page.getByRole('button',{name:'Layover',exact:true}).click();
  await page.locator('[data-plan="coffee"]').click();
  await page.getByRole('button',{name:'Flight',exact:true}).click();
  await page.getByRole('button',{name:'Edit A coffee before boarding'}).click();
  await page.getByLabel('Visit duration in minutes').fill('30');
  await page.getByRole('dialog').getByRole('button',{name:'View steps'}).click();
  await expect(page.getByRole('dialog').getByLabel('Journey stage')).toBeVisible();
  await page.getByRole('dialog').getByRole('button',{name:'Close dialog',exact:true}).click();
  await expect(page.getByLabel('Visit duration in minutes')).toHaveValue('30');
  await page.getByRole('button',{name:'Save stop'}).click();
  await expect(page.locator('#my-plan article')).toContainText('30 min visit');
});

test('authenticated trip progress connects overlay to server without changing selected plan',async({page})=>{
 const owner='b'.repeat(64);let record={owner,revision:0,phase:'arrival',status:{arrival:{landed:'done'},departure:{},transfer:{}}};let saved;
 await page.addInitScript(()=>{window.AIRBORDER_JOURNEY={trip:'trip-2026',leg:'leg-hnd'};});
 await page.route('**/v1/journeys/trip-2026/leg-hnd',async route=>{if(route.request().method()==='POST'){saved=route.request().postDataJSON();record={...record,revision:1,status:{...record.status,arrival:{landed:'done',passport:'done'}}};}await route.fulfill({json:record});});
 await page.goto('/');const tracker=page.getByRole('region',{name:'Journey steps'});
 await expect(tracker).toContainText('Arrival checklist');await tracker.getByRole('button',{name:'View steps'}).click();
 await page.getByRole('button',{name:'Confirm passport control, if required',exact:true}).click();
 await expect.poll(()=>saved?.expectedOwner).toBe(owner);expect(saved.expectedRevision).toBe(0);
 await expect(page.getByRole('dialog')).toContainText('Journey progress saved');
 await page.getByRole('button',{name:'Done',exact:true}).click();await page.reload();
 await expect(tracker).toContainText('Confirm baggage collection');
});

test('account checklist waits for initial load and does not restore another owner cache',async({page})=>{
 let release;const gate=new Promise(r=>release=r);
 await page.addInitScript(()=>{window.AIRBORDER_JOURNEY={trip:'slow-trip',leg:'leg'};sessionStorage.setItem('airborder-progress:slow-trip:leg',JSON.stringify({phase:'arrival',status:{arrival:{landed:'done'},departure:{},transfer:{}}}));});
 await page.route('**/v1/journeys/slow-trip/leg',async route=>{await gate;await route.fulfill({json:{owner:'c'.repeat(64),revision:0,phase:'arrival',status:{arrival:{},departure:{},transfer:{}}}});});
 await page.goto('/');await page.getByRole('button',{name:'View steps'}).click();
 await expect(page.getByLabel('Journey stage')).toBeDisabled();await expect(page.getByRole('button',{name:'Confirm arrival',exact:true})).toBeDisabled();
 release();await expect(page.getByLabel('Journey stage')).toHaveValue('arrival');await expect(page.getByRole('button',{name:'Confirm landing',exact:true})).toBeEnabled();
});

test('conflict recovery is offered immediately in the open checklist',async({page})=>{
 await page.addInitScript(()=>{window.AIRBORDER_JOURNEY={trip:'conflict',leg:'leg'};});
 await page.route('**/v1/journeys/conflict/leg',route=>route.fulfill({status:route.request().method()==='POST'?409:200,json:{owner:'d'.repeat(64),revision:0,phase:'arrival',status:{arrival:{},departure:{},transfer:{}}}}));
 await page.goto('/');await expect(page.getByRole('region',{name:'Journey steps'})).toContainText('Arrival checklist');await page.getByRole('button',{name:'View steps'}).click();
 await page.getByRole('button',{name:'Confirm landing',exact:true}).click();await expect(page.getByRole('dialog').getByRole('button',{name:'Use saved progress'})).toBeVisible();
});

test('logout closes and clears the account checklist and editor return state',async({page})=>{
 await page.addInitScript(()=>{window.AIRBORDER_JOURNEY={trip:'logout',leg:'leg'};});
 await page.route('**/v1/journeys/logout/leg',r=>r.fulfill({json:{owner:'e'.repeat(64),revision:1,phase:'arrival',status:{arrival:{landed:'done'},departure:{},transfer:{}}}}));
 await page.goto('/');await expect(page.getByRole('region',{name:'Journey steps'})).toContainText('Arrival checklist');await page.getByRole('button',{name:'View steps'}).click();await expandSteps(page);await expect(page.getByRole('button',{name:'Undo Confirm landing'})).toBeVisible();
 await page.evaluate(()=>{Storage.prototype.removeItem=()=>{throw Error('storage blocked');};window.dispatchEvent(new Event('airborder:logout'));});await expect(page.getByRole('dialog')).toHaveCount(0);await expect(page.locator('#dialog')).toBeEmpty();expect(await page.evaluate(()=>progressReturnEdit)).toBeNull();expect(await page.evaluate(()=>journeyProgress)).toEqual({phase:'transfer',status:{departure:{},arrival:{},transfer:{}}});
});

test('account change without logout clears old progress and open checklist',async({page})=>{
 let changed=false;await page.addInitScript(()=>{window.AIRBORDER_JOURNEY={trip:'switch',leg:'leg'};});
 await page.route('**/v1/journeys/switch/leg',r=>r.fulfill({json:{owner:(changed?'b':'a').repeat(64),revision:1,phase:'arrival',status:{arrival:{landed:'done'},departure:{},transfer:{}}}}));
 await page.goto('/');await expect(page.getByRole('region',{name:'Journey steps'})).toContainText('Arrival checklist');await page.getByRole('button',{name:'View steps'}).click();changed=true;await page.evaluate(()=>progressSync.start());await expect(page.getByRole('dialog')).toHaveCount(0);await expect(page.locator('#dialog')).toBeEmpty();expect(await page.evaluate(()=>journeyProgress.status.arrival)).toEqual({});await expect(page.getByRole('region',{name:'Journey steps'})).toContainText('Transfer checklist');
});
