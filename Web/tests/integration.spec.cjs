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
  await page.locator('[data-view="journey"]:visible').first().click();
  await expect(page.locator('#my-plan')).toContainText('A coffee before boarding');
});

test('unavailable directory is clearly disclosed with retry', async ({page}) => {
  await page.route('**/api/facilities**',route=>route.fulfill({status:503,contentType:'application/json',body:'{}'}));
  await page.goto('/');
  await page.locator('[data-view="explore"]:visible').first().click();
  await expect(page.getByText('Airport services are unavailable at the moment.')).toBeVisible();
  await expect(page.getByRole('button',{name:/Try again/})).toBeVisible();
});
