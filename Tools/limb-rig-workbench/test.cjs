const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const elements=new Map();const element=()=>({value:'0.6',checked:true,textContent:'',getContext:()=>({})});
const sandbox={location:{search:'?avatar='+(process.argv[2]||'insistent')},URLSearchParams,document:{querySelector:s=>{if(!elements.has(s))elements.set(s,element());return elements.get(s)},getElementById:id=>element()},Image:class {},matchMedia:()=>({matches:true}),requestAnimationFrame:()=>{},window:{}};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync(__dirname+'/../../Website/assets/avatar-rig/characters.js','utf8'),sandbox);vm.runInContext(fs.readFileSync(__dirname+'/../../Website/assets/avatar-rig/rig.js','utf8'),sandbox);
const check=sandbox.window.rigCheck();assert.ok(check.restError<1e-8);assert.equal(check.normalizedWeights,true);
vm.runInContext(`for(let frame=0;frame<=120;frame++){const ms=pose(frame/120,1);for(const m of ms){if(![m.c,m.s,m.x,m.y].every(Number.isFinite))throw Error('Nonfinite transform')}
for(let i=0;i<joints.length;i++){const j=joints[i];if(j.parent<0)continue;const a=apply(ms[i],j.p),b=apply(ms[j.parent],j.p);if(Math.hypot(a[0]-b[0],a[1]-b[1])>1e-8)throw Error('Disconnected joint')}}
const first=pose(0,1),lastPose=pose(1,1);for(let i=0;i<first.length;i++)for(const key of ['c','s','x','y'])if(Math.abs(first[i][key]-lastPose[i][key])>1e-8)throw Error('Loop discontinuity');`,sandbox);
console.log('Passed: rest identity, normalized skin weights, 121 finite connected poses, seamless loop.');

vm.runInContext(`for(let frame=0;frame<=120;frame++){const ms=pose(frame/120,1);legs.forEach((leg,k)=>{const toe=apply(ms[legStart+k*3+2],leg.toe);if(Math.hypot(toe[0]-leg.toe[0],toe[1]-leg.toe[1])>1e-8)throw Error('Toe contact drift')})}`,sandbox);
console.log('Passed: both toe contacts remain planted across 121 poses.');

if(process.argv[2]==='shy')vm.runInContext(`for(let phase=0;phase<=1;phase+=.05){const ms=pose(phase,1);for(const p of [[400,345],[425,380],[490,250],[530,400]]){const w=weights(p);if(w[headIndex]!==1)throw Error('Face/glove contact must remain rigid');const actual=w.reduce((a,n,i)=>{const q=apply(ms[i],p);return [a[0]+n*q[0],a[1]+n*q[1]]},[0,0]),expected=apply(ms[headIndex],p);if(Math.hypot(actual[0]-expected[0],actual[1]-expected[1])>1e-8)throw Error('Contact distortion')}}`,sandbox);
