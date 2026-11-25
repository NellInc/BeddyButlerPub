'use strict';
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const events={},docEvents={};let observe,changed;
const reduced={matches:false,addEventListener:(_,fn)=>changed=fn};
const hosts=['shy','insistent','zombie'].map(avatar=>({dataset:{avatar},classes:new Set(),append(frame){this.frame=frame}}));
hosts.forEach(h=>h.classList={add:c=>h.classes.add(c),remove:c=>h.classes.delete(c)});
const document={hidden:false,querySelectorAll:()=>hosts,addEventListener:(n,f)=>docEvents[n]=f,createElement:()=>({setAttribute(){},contentWindow:{messages:[],postMessage(m){this.messages.push(m)}},remove(){this.removed=true}})};
vm.runInNewContext(fs.readFileSync(__dirname+'/../Website/assets/avatar-rig/website.js','utf8'),{document,window:{addEventListener:(n,f)=>events[n]=f},location:{origin:'http://localhost'},matchMedia:()=>reduced,encodeURIComponent,IntersectionObserver:class{constructor(fn){observe=fn}observe(){}}});
assert(hosts.every(h=>!h.frame));
observe(hosts.map(target=>({target,isIntersecting:true})));
for(const h of hosts){assert(h.frame.src.endsWith('avatar='+h.dataset.avatar));events.message({origin:'http://localhost',source:h.frame.contentWindow,data:{type:'butler-ready'}});assert(h.classes.has('rig-ready'))}
document.hidden=true;docEvents.visibilitychange();assert(hosts.every(h=>h.frame.contentWindow.messages.at(-1).playing===false));
document.hidden=false;docEvents.visibilitychange();assert(hosts.every(h=>h.frame.contentWindow.messages.at(-1).playing===true));
observe([{target:hosts[0],isIntersecting:false}]);assert.equal(hosts[0].frame.contentWindow.messages.at(-1).playing,false);
events.message({origin:'http://localhost',source:hosts[1].frame.contentWindow,data:{type:'butler-unavailable'}});assert(!hosts[1].classes.has('rig-ready'));assert(hosts[1].frame.removed);
docEvents.visibilitychange();observe([{target:hosts[1],isIntersecting:true}]);assert(hosts[1].frame.removed);
reduced.matches=true;changed();assert(hosts.every(h=>!h.classes.has('rig-ready')&&h.frame.removed));
reduced.matches=false;changed();assert(!hosts[2].frame.removed);assert(hosts[1].frame.removed);
console.log('Avatar loader passed: three personalities, lazy initialization, visibility pause, sticky GPU fallback, Reduced Motion.');
