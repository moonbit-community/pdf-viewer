// Playwright polls the predicate synchronously. An async predicate returns a
// truthy Promise even when it resolves to false, so keep frame waits separate.
export async function waitForUI(page,predicate,arg){
  await (await page.waitForFunction(predicate,arg)).dispose();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await (await page.waitForFunction(predicate,arg)).dispose();
}
