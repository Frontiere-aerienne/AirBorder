const {test,expect}=require('@playwright/test');

test('local HTTP API supplies directory and timing for the browser', async ({page}) => {
  const directory=page.waitForResponse(r=>r.url().includes('/api/facilities?airport=HND'));
  const timing=page.waitForResponse(r=>r.url().endsWith('/api/connection'));
  await page.goto('/');
  const [d,t]=await Promise.all([directory,timing]);
  expect(d.status()).toBe(200); expect(t.status()).toBe(200);
  expect((await d.json()).facilities.length).toBeGreaterThan(0);
  expect(await t.json()).toMatchObject({canFit:true,method:'deterministic-time-budget-v1'});
  await page.locator('[data-view="explore"]:visible').first().click();
  await expect(page.getByRole('region',{name:'Airport directory'})).toBeVisible();
  await expect(page.getByRole('region',{name:'Airport directory'}).locator('a')).not.toHaveCount(0);
  const updatedTiming=page.waitForResponse(r=>r.url().endsWith('/api/connection') && r.request().method()==='POST');
  await page.locator('[data-plan="coffee"]').click();
  expect((await updatedTiming).status()).toBe(200);
  await page.locator('[data-plan="rest"]').click();
  await page.locator('[data-view="journey"]:visible').first().click();
  await expect(page.locator('#my-plan')).toContainText('A coffee before boarding');
  await expect(page.getByText('Your plan needs more time')).toBeVisible();
  await expect(page.locator('#my-plan')).toContainText('minutes past your gate-arrival target');
});

test('unavailable directory is clearly disclosed with retry', async ({page}) => {
  await page.route('**/api/facilities**',route=>route.fulfill({status:503,contentType:'application/json',body:'{}'}));
  await page.goto('/');
  await page.locator('[data-view="explore"]:visible').first().click();
  await expect(page.getByText('Airport services are unavailable at the moment.')).toBeVisible();
  await expect(page.getByRole('button',{name:/Try again/})).toBeVisible();
});

test('unknown and stale data suppress timing requests and invalidate prior results', async ({page}) => {
  let requests=0;
  page.on('request', request=>{if(request.url().endsWith('/api/connection')) requests++;});
  await page.goto('/?presenter=1');
  await page.locator('#fixture').selectOption('unknown');
  await page.locator('#load-fixture').click();
  await page.locator('#step-fixture').click();
  const before=requests;
  await page.locator('[data-view="explore"]:visible').first().click();
  await page.locator('[data-view="journey"]:visible').first().click();
  await expect(page.locator('#my-plan')).toContainText('Some route information is unavailable');
  await expect(page.getByText('Your plan needs more time')).toHaveCount(0);
  expect(requests).toBe(before);
  await page.locator('#fixture').selectOption('gate');
  await page.locator('#load-fixture').click();
  await page.locator('#step-fixture').click();
  await page.evaluate(()=>{ journeyState.now=60; render(); });
  const staleCount=requests;
  await page.locator('[data-view="explore"]:visible').first().click();
  await page.locator('[data-view="journey"]:visible').first().click();
  await expect(page.locator('#my-plan')).toContainText('Some route information is unavailable');
  expect(requests).toBe(staleCount);
});

test('a late timing response cannot revive a result after data becomes unknown', async ({page}) => {
  let release;
  const held = new Promise(resolve => { release=resolve; });
  let finished;
  const completed = new Promise(resolve => { finished=resolve; });
  let seen;
  const started = new Promise(resolve => { seen=resolve; });
  await page.route('**/api/connection', async route => {
    seen(); await held;
    await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({canFit:false,spareMinutes:-10})});
    finished();
  });
  await page.goto('/?presenter=1');
  await started;
  await page.locator('#fixture').selectOption('unknown');
  await page.locator('#load-fixture').click();
  await page.locator('#step-fixture').click();
  release();
  await completed;
  await expect(page.locator('#my-plan')).toContainText('Some route information is unavailable');
  await expect(page.getByText('Your plan needs more time')).toHaveCount(0);
});

 test('a plan change immediately clears the prior warning while new timing is pending', async ({page}) => {
  await page.goto('/');
  await page.locator('[data-view="explore"]:visible').first().click();
  await page.locator('[data-plan="coffee"]').click();
  await page.locator('[data-plan="rest"]').click();
  await page.locator('[data-view="journey"]:visible').first().click();
  await expect(page.getByText('Your plan needs more time')).toBeVisible();
  let release, seen;
  const held=new Promise(resolve=>{release=resolve;});
  const started=new Promise(resolve=>{seen=resolve;});
  await page.route('**/api/connection', async route=>{seen();await held;await route.continue();});
  await page.getByRole('button',{name:'Remove Quiet time near your gate'}).click();
  await started;
  await expect(page.getByText('Your plan needs more time')).toHaveCount(0);
  release();
});
