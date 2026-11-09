const { test, expect } = require('@playwright/test');

test.use({ viewport: { width: 390, height: 844 } });
test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }));
});
const tab = (page, view) => page.locator(`.bottom-nav [data-view="${view}"]`).click();

test('plan timelines distinguish departure, arrival and the target without reversing time', async ({ page }) => {
  await page.goto('/');
  const plan = page.locator('#my-plan');
  await expect(plan.locator('.plan-timeline strong')).toHaveText(['16:30', '16:30', '16:42', '17:25']);
  await tab(page, 'explore');
  await page.locator('[data-plan="coffee"]').click();
  await tab(page, 'journey');
  const coffee = plan.locator('article').first();
  // Seven minutes to the selected cafe, 25 minutes there, then five to the gate.
  await expect(coffee.locator('.plan-timeline strong')).toHaveText(['16:30', '17:02', '17:07', '17:25']);
  await tab(page, 'explore');
  await page.locator('[data-plan="rest"]').click();
  await tab(page, 'journey');
  await expect(plan.locator('article')).toHaveCount(2);
  await expect(plan.locator('article').first()).toContainText('At gate · late');
  await expect(plan.locator('article').first().locator('.plan-timeline strong').last()).toHaveText('17:25');
});

test('unknown observations do not create precise plan-card times', async ({ page }) => {
  await page.goto('/?presenter=1');
  await page.locator('#fixture').selectOption('unknown');
  await page.locator('#load-fixture').click();
  await page.locator('#step-fixture').click();
  await expect(page.locator('#my-plan')).toContainText('Some route information is unavailable');
  await expect(page.locator('#my-plan .plan-timeline')).toHaveCount(0);
});

test('resetting profile preferences retains the selected plan and original phone navigation', async ({ page }) => {
  await page.goto('/');
  await tab(page, 'explore');
  await page.locator('[data-plan="coffee"]').click();
  await tab(page, 'settings');
  await page.getByRole('switch', { name: 'Step-free routes' }).click();
  await page.getByRole('button', { name: 'Reset preferences' }).click();
  await expect(page.getByRole('switch', { name: 'Step-free routes' })).toHaveAttribute('aria-checked', 'false');
  await expect(page.locator('.bottom-nav button')).toHaveText(['Flight', 'Layover', 'Route', 'Profile']);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  await expect(page.locator('.demo-disclosure')).toHaveCount(0);
  await tab(page, 'journey');
  await expect(page.locator('#my-plan article')).toHaveCount(1);
  await expect(page.locator('#my-plan article')).toContainText('A coffee before boarding');
});

test('restored Profile controls retain usable touch targets', async ({ page }) => {
  await page.goto('/');
  await tab(page, 'settings');
  const undersized = await page.locator('button:visible:not([disabled])').evaluateAll(nodes =>
    nodes.map(node => ({ name: node.innerText.trim(), width: node.getBoundingClientRect().width, height: node.getBoundingClientRect().height }))
      .filter(target => target.width < 44 || target.height < 44));
  expect(undersized).toEqual([]);
});
