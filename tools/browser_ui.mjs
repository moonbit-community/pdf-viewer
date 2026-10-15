// Playwright polls the predicate synchronously. An async predicate returns a
// truthy Promise even when it resolves to false, so keep frame waits separate.
export async function waitForUI(page,predicate,arg){
  await (await page.waitForFunction(predicate,arg)).dispose();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await (await page.waitForFunction(predicate,arg)).dispose();
}

// An input event may arrive before Rabbita's first after-render controller
// initialization. Keep that ordering deterministic without delaying PDF I/O.
export async function holdBootstrapFramesUntilFile(page,delayMs=500){
  await page.addInitScript(delay=>{
    const frame=requestAnimationFrame.bind(window),cancel=cancelAnimationFrame.bind(window),pending=new Map(),cancelled=new Set();let released=false;
    window.requestAnimationFrame=callback=>{const id=frame(time=>{if(released)callback(time);else pending.set(id,callback);});return id;};
    window.cancelAnimationFrame=id=>{cancelled.add(id);pending.delete(id);cancel(id);};
    document.addEventListener('change',event=>{
      if(event.target?.id!=='file-input'||released)return;
      setTimeout(()=>{released=true;for(const [id,callback]of pending)frame(time=>{if(!cancelled.has(id))callback(time);});pending.clear();},delay);
    },true);
  },delayMs);
}
