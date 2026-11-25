'use strict';
const play=document.getElementById('play-all'),motion=document.getElementById('motion-all'),bones=document.getElementById('joints-all');
let playing=!matchMedia('(prefers-reduced-motion: reduce)').matches;
function sync(){play.textContent=playing?'Pause all':'Play all';for(const frame of document.querySelectorAll('iframe'))frame.contentWindow.postMessage({type:'butler-controls',amount:Number(motion.value),bones:bones.checked,playing},location.origin)}
play.onclick=()=>{playing=!playing;sync()};motion.oninput=bones.onchange=sync;
for(const frame of document.querySelectorAll('iframe'))frame.addEventListener('load',sync);
sync();
