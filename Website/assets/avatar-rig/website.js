'use strict';
// Original images remain accessible and visible until a GPU-rendered frame is ready.
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
const entries=[...document.querySelectorAll('[data-avatar]')].map(host=>({host,frame:null,visible:false,unavailable:false}));
function update(entry){
 if(reduced.matches){entry.frame?.remove();entry.frame=null;entry.host.classList.remove('rig-ready');return}
 if(entry.visible&&!entry.frame&&!entry.unavailable){
  const frame=document.createElement('iframe');frame.className='avatar-rig';frame.title=`Animated ${entry.host.dataset.avatar} Butler`;frame.setAttribute('aria-hidden','true');frame.tabIndex=-1;
  frame.src=`/assets/avatar-rig/embed.html?website=1&avatar=${encodeURIComponent(entry.host.dataset.avatar)}`;entry.frame=frame;entry.host.append(frame);
 }
 entry.frame?.contentWindow?.postMessage({type:'butler-controls',playing:entry.visible&&!document.hidden,amount:1,bones:false},location.origin);
}
window.addEventListener('message',event=>{
 if(event.origin!==location.origin)return;
 const entry=entries.find(e=>e.frame?.contentWindow===event.source);if(!entry)return;
 if(event.data?.type==='butler-ready'){entry.host.classList.add('rig-ready');update(entry)}
 if(event.data?.type==='butler-unavailable'){entry.unavailable=true;entry.host.classList.remove('rig-ready');entry.frame?.remove();entry.frame=null}
});
const observer=new IntersectionObserver(changes=>{for(const change of changes){const entry=entries.find(e=>e.host===change.target);entry.visible=change.isIntersecting;update(entry)}},{threshold:0});
entries.forEach(e=>observer.observe(e.host));
reduced.addEventListener('change',()=>entries.forEach(update));
document.addEventListener('visibilitychange',()=>entries.forEach(update));
window.addEventListener('pagehide',()=>entries.forEach(e=>e.frame?.contentWindow?.postMessage({type:'butler-controls',playing:false},location.origin)));
