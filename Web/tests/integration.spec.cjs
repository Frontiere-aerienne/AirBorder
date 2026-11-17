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

test('host itinerary uses its own airports, carrier and times without borrowing synthetic guidance',async({page})=>{
 const paths=[];
 page.on('request',request=>{const url=new URL(request.url());if(url.pathname.startsWith('/api/'))paths.push(url.pathname+url.search);});
 await page.addInitScript(()=>{
  window.AIRBORDER_ITINERARY={
   id:'london-connection',date:'22 February 2027',
   inbound:{id:'BA 203',airline:'British Airways',from:{code:'BOS',name:'Boston',zone:'EST'},to:{code:'LHR',name:'London Heathrow',zone:'GMT',country:'GB'},departure:'20:10',arrival:'07:45',terminal:'5',gate:'A12'},
   onward:{id:'BA 578',airline:'British Airways',from:{code:'LHR',name:'London Heathrow',zone:'GMT',country:'GB'},to:{code:'FCO',name:'Rome Fiumicino',zone:'CET'},departure:'12:30',arrival:'16:05',terminal:'5',gate:'B36',target:'11:55'}
  };
 });
 const directory=page.waitForResponse(r=>r.url().includes('/api/facilities?airport=LHR'));
 await page.goto('/?presenter=1');
 await directory;
 const ticket=page.getByRole('region',{name:'Next flight'});
 await expect(ticket).toContainText('BA 578');
 await expect(ticket).toContainText('London Heathrow');
 await expect(ticket).toContainText('Rome Fiumicino');
 await expect(ticket).toContainText('12:30');
 await expect(ticket).toContainText('16:05');
 await expect(ticket).toContainText('Last known gate B36');
 await expect(page.getByRole('region',{name:'Your next action'})).toContainText('Indoor route unavailable');
 await expect(page.getByRole('complementary',{name:'Presenter controls'})).toHaveCount(0);
 await page.getByRole('button',{name:'Journey details'}).click();
 await expect(page.getByRole('main')).toContainText('Gate-arrival target · GMT');
 await expect(page.getByRole('main')).toContainText('11:55');
 await page.getByRole('navigation',{name:'Main'}).getByRole('button',{name:'Layover'}).click();
 await expect(page.getByRole('main')).toContainText('Airport services are unavailable');
 await expect(page.getByRole('button',{name:'Add to my plan'})).toHaveCount(0);
 expect(paths).toEqual(['/api/facilities?airport=LHR']);
 await expect(page.getByRole('main')).not.toContainText(/Haneda|Narita|Gate 105/);
});

test('non-Tokyo host timing uses matching recent route input and expires without supplying a map',async({page})=>{
 await page.clock.install({time:new Date('2027-02-22T10:55:00Z')});
 await page.addInitScript(()=>{
  const airport={code:'LHR',name:'London Heathrow',zone:'GMT',country:'GB',timeZone:'Europe/London'};
  window.AIRBORDER_ITINERARY={
   inbound:{id:'BA 203',from:{code:'BOS'},to:airport},
   onward:{id:'BA 578',from:airport,to:{code:'FCO'},departure:'12:30',terminal:'5',gate:'B36'},
   timing:{airportCode:'LHR',flightId:'BA 578',gate:'B36',walkMinutes:15,observedAt:'2027-02-22T10:54:00Z',expiresAt:'2027-02-22T11:00:00Z',arrivalTargetAt:'2027-02-22T11:55:00Z'}
  };
 });
 await page.goto('/');
 const next=page.getByRole('region',{name:'Your next action'});
 await expect(next).toContainText('15 min');
 await expect(next).toContainText('11:10');
 await expect(next).toContainText('11:55');
 await expect(next.getByRole('button',{name:/route/i})).toHaveCount(0);
 await page.getByRole('navigation',{name:'Main'}).getByRole('button',{name:'Route'}).click();
 await expect(page.getByRole('main')).toContainText('Indoor route unavailable');
 await expect(page.getByRole('img',{name:/route overview/i})).toHaveCount(0);
 await page.getByRole('navigation',{name:'Main'}).getByRole('button',{name:'Flight'}).click();
 await page.clock.fastForward('06:00');
 await expect(next).toContainText('Indoor route unavailable');
 await expect(next).not.toContainText('15 min');
});
