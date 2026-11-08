const { test, expect } = require('@playwright/test');

async function nav(page, view) { await page.locator(`[data-view="${view}"]:visible`).first().click(); }
async function fixture(page, name) { await page.locator('#fixture').selectOption(name); await page.locator('#load-fixture').click(); }

test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', route => route.fulfill({status: 503, contentType:'application/json', body:'{}'}));
});

test('selected stops can be added, ordered, removed and mapped', async ({ page }) => {
  await page.goto('/');
  await nav(page, 'explore');
  await page.locator('[data-plan="coffee"]').click();
  await page.locator('[data-plan="rest"]').click();
  await nav(page, 'journey');
  const rows = page.locator('#my-plan article');
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0)).toContainText('A coffee before boarding');
  await rows.nth(1).getByRole('button', { name:'Move earlier' }).click();
  await expect(rows.nth(0)).toContainText('Quiet time near your gate');
  await nav(page, 'map');
  await expect(page.locator('[aria-label="Selected route stops"] li')).toHaveText(['Quiet time near your gate','A coffee before boarding','Gate 105']);
  await nav(page, 'journey');
  await page.getByRole('button', {name:'Remove Quiet time near your gate'}).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('A coffee before boarding');
});

test('recommendations affect only selected stops and stale suggestions cannot be applied', async ({page}) => {
  await page.goto('/?presenter=1');
  await fixture(page, 'indoorRain');
  await page.locator('#step-fixture').click();
  await expect(page.locator('[data-apply]')).toHaveCount(0);
  await fixture(page, 'queue');
  await page.locator('#step-fixture').click();
  await expect(page.locator('[data-apply]')).toHaveCount(1);
  const before = await page.locator('#my-plan article').allTextContents();
  // Update live observations without repainting, reproducing a stale displayed suggestion.
  await page.evaluate(() => { journeyState.dataRevision++; });
  await page.locator('[data-apply]').click();
  await expect(page.locator('#my-plan article')).toHaveText(before);
  await expect(page.locator('#toast')).toContainText('Your plan changed');
  await page.locator('[data-apply]').click();
  await expect(page.locator('#my-plan article')).toHaveCount(1);
  await page.locator('[data-action="undo-plan"]').click();
  await expect(page.locator('#my-plan article')).toHaveCount(2);
});

test('gate suffix propagates during navigation and guide reaches its end', async ({page}) => {
  await page.goto('/?presenter=1');
  await fixture(page, 'gate');
  await page.locator('[data-action="start-route"]').first().click();
  await page.locator('[data-action="next-step"]').click();
  await page.locator('#step-fixture').click();
  await expect(page.locator('.guide-stage')).toContainText('STEP 2');
  await expect(page.locator('main')).toContainText('Gate 108A');
  await nav(page, 'map');
  await expect(page.locator('[aria-label="Selected route stops"] li').last()).toHaveText('Gate 108A');
  await page.locator('[data-action="start-route"]').first().click();
  await expect(page.locator('.guide-stage')).toContainText('STEP 2');
  while (await page.locator('[data-action="next-step"]').count()) await page.locator('[data-action="next-step"]').click();
  await expect(page.locator('.guide-stage')).toContainText('Arrive at Gate 108A');
  await page.locator('[data-action="finish-route"]').click();
  await expect(page.getByRole('heading', {name:'Your journey'})).toBeVisible();
  await expect(page.locator('#toast')).toContainText('Gate 108A');
});

for (const width of [320, 375, 390]) test(`mobile navigation and content fit at ${width}px`, async ({page}) => {
  await page.setViewportSize({width, height:800}); await page.goto('/');
  for (const view of ['journey','flights','explore','map']) {
    await nav(page, view);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    const buttons = page.locator('.bottom-nav button');
    for (let i=0; i<await buttons.count(); i++) {
      const box=await buttons.nth(i).boundingBox(); expect(box.width).toBeGreaterThanOrEqual(44); expect(box.height).toBeGreaterThanOrEqual(44);
      await expect(buttons.nth(i)).toHaveAccessibleName(/\S+/);
    }
  }
});

test('restored palette, accessible controls, and traveller isolation', async ({page}) => {
  const errors=[]; page.on('pageerror', e=>errors.push(e.message)); await page.goto('/');
  await expect(page.locator('[aria-label="Presenter controls"]')).toHaveCount(0);
  const colors=await page.evaluate(() => {const s=getComputedStyle(document.documentElement); return ['--deep','--ink','--teal','--bg','--white','--accent','--info','--warning','--danger'].map(k=>s.getPropertyValue(k).trim().toLowerCase());});
  expect(await page.evaluate(async () => {
    await document.fonts.ready;
    return ['400','600','700'].every(weight => document.fonts.check(`${weight} 16px Outfit`)) && getComputedStyle(document.body).fontFamily.startsWith('Outfit');
  })).toBe(true);
  expect(colors).toEqual(['#17364a','#173247','#225e79','#e9f0f1','#fdfeff','#f9cb41','#8ec1d6','#ed9e38','#db5247']);
  await expect(page.getByRole('button',{name:'AV, traveler profile'})).toBeVisible();
  await expect(page.getByRole('navigation',{name:'Main'})).toBeVisible();
  await expect(page.locator('.primary').first()).toHaveCSS('color','rgb(255, 255, 255)');
  const contrast = await page.locator('.primary').first().evaluate(el => {
    const lum = rgb => { const c=rgb.match(/\d+/g).slice(0,3).map(Number).map(n=>{n/=255;return n<=0.04045?n/12.92:((n+0.055)/1.055)**2.4}); return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]; };
    const style=getComputedStyle(el), a=lum(style.color), b=lum(style.backgroundColor);
    return (Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
  });
  expect(contrast).toBeGreaterThanOrEqual(4.5);
  expect(errors).toEqual([]);
});

test('keyboard navigation and review captures', async ({page}, testInfo) => {
  await page.goto('/');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link',{name:'Skip to content'})).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('#main')).toBeFocused();
  for (const view of ['journey','explore','map','flights']) {
    await nav(page,view);
    await expect(page.locator('#main')).toBeFocused();
    const buttons=page.locator('button:visible:not([disabled])');
    for(let i=0;i<await buttons.count();i++) await expect(buttons.nth(i)).toHaveAccessibleName(/\S+/);
    await testInfo.attach(`${view}.png`,{body:await page.screenshot({fullPage:true}),contentType:'image/png'});
  }
});

test('automated accessibility checks on main views', async ({page}) => {
  const AxeBuilder = require('@axe-core/playwright').default;
  await page.goto('/');
  for (const view of ['journey','explore','map','flights']) {
    await nav(page,view);
    const results=await new AxeBuilder({page}).analyze();
    expect(results.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)}))).toEqual([]);
  }
});

test('visible enabled buttons provide usable targets at mobile size', async ({page}) => {
  await page.setViewportSize({width:375,height:800}); await page.goto('/');
  for(const view of ['journey','explore','map','flights']) {
    await nav(page,view);
    const undersized=await page.locator('button:visible:not([disabled])').evaluateAll(nodes=>nodes.map(n=>({name:n.getAttribute('aria-label')||n.innerText.trim(),width:n.getBoundingClientRect().width,height:n.getBoundingClientRect().height})).filter(x=>x.width<44||x.height<44));
    expect(undersized).toEqual([]);
  }
});


test('demo disclosure remains visible in traveller views', async ({page}) => {
  await page.goto('/');
  for (const view of ['journey','flights','explore','map','guide','settings']) {
    await nav(page,view);
    await expect(page.locator('.demo-disclosure')).toBeVisible();
    await expect(page.locator('.demo-disclosure')).toContainText('Flight, timing and route information are simulated');
    await expect(page.locator('.demo-disclosure')).toContainText('airport directory uses published airport information');
  }
});

test('urgent direct route skips saved stops without removing them and resumes from map', async ({page}) => {
  await page.goto('/?presenter=1');
  await fixture(page,'queue');
  await page.locator('#age-fixture').click();
  await page.locator('#age-fixture').click();
  await page.locator('#age-fixture').click();
  await expect(page.locator('#my-plan article')).toHaveCount(2);
  await page.locator('.hero [data-action="direct-route"]').click();
  await expect(page.locator('.guide-stage')).toContainText('STEP 1 OF 3');
  await page.locator('[data-action="next-step"]').click();
  await expect(page.locator('.guide-stage')).toContainText('Follow signs to Gate 105');
  await nav(page,'map');
  await expect(page.locator('[aria-label="Selected route stops"] li')).toHaveText(['Gate 105']);
  await expect(page.locator('.route-step')).toHaveCount(3);
  await expect(page.getByText('Direct route to your gate. Your saved stops remain in My plan.')).toBeVisible();
  await page.locator('[data-action="start-route"]').click();
  await expect(page.locator('.guide-stage')).toContainText('STEP 2 OF 3');
  await nav(page,'journey');
  await expect(page.locator('#my-plan article')).toHaveCount(2);
  await expect(page.locator('#my-plan')).toContainText('A coffee before boarding');
  await expect(page.locator('#my-plan')).toContainText('Quiet time near your gate');
});
