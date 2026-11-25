'use strict';
const avatar=typeof location==='undefined'?'insistent':new URLSearchParams(location.search).get('avatar')||'insistent';
const website=typeof location!=='undefined'&&new URLSearchParams(location.search).has('website');
const config=typeof CHARACTER_RIGS==='undefined'?null:CHARACTER_RIGS[avatar];
const W=960,H=config?.height||1210, canvas=document.querySelector('#rig'), ctx=website?null:canvas.getContext('2d');
const controls=Object.fromEntries(['play','amount','phase','bones','rest'].map(id=>[id,document.getElementById(id)]));
const assetBase=canvas.dataset?.assetBase||'..';
const image=new Image();image.src=`${assetBase}/${config?avatar:'insistent'}-960.webp`;
canvas.height=H;if(!website)document.querySelector('#original').height=H;
if(config&&!website)document.querySelector('h1').textContent=`${avatar[0].toUpperCase()+avatar.slice(1)}: limb rig experiment`;
// Parent-first skeleton, expressed in original artwork coordinates.
const joints=[
 {name:'body',p:[550,690],parent:-1},
 {name:'neck',p:[520,335],parent:0},
 {name:'raised shoulder',p:[493,398],parent:0},
 {name:'raised elbow',p:[360,499],parent:2},
 {name:'raised wrist',p:[263,350],parent:3},
 {name:'front shoulder',p:[622,395],parent:0},
 {name:'front elbow',p:[513,543],parent:5},
 {name:'front wrist',p:[388,645],parent:6}
];
const segments=[[[520,760],[570,1150]],[[520,335],[490,115]],[[493,398],[360,499]],[[360,499],[263,350]],[[263,350],[198,298]],[[622,395],[513,543]],[[513,543],[388,645]],[[388,645],[303,661]]];
// Visible digits only: separate roots and tips, parented to each wrist.
const digits=[
 ['raised thumb',4,[239,297],[244,249]],
 ['raised index',4,[215,289],[153,286]],
 ['raised middle',4,[216,304],[145,303]],
 ['raised ring',4,[219,317],[157,322]],
 ['front thumb',7,[354,638],[327,626]],
 ['front index',7,[337,649],[278,654]],
 ['front middle',7,[332,664],[270,681]],
 ['front ring',7,[340,673],[285,697]]
];
for(const [name,parent,p,tip] of digits){joints.push({name,p,parent});segments.push([p,tip])}
const headIndex=joints.length;
joints.push({name:'head',p:[516,300],parent:1});segments.push([[516,300],[490,115]]);
const chestIndex=joints.length;
joints.push({name:'chest',p:[553,730],parent:0});segments.push([[553,730],[540,400]]);
for(const i of [1,2,5])joints[i].parent=chestIndex;
// Evaluate parent-first even though the chest was added after its children.
const knuckleStart=joints.length;
for(let i=0;i<digits.length;i++){
 const [name,,root,tip]=digits[i],mid=[root[0]+(tip[0]-root[0])*.48,root[1]+(tip[1]-root[1])*.48];
 joints.push({name:`${name} knuckle`,p:mid,parent:8+i});segments[8+i]=[root,mid];segments.push([mid,tip]);
}
const legStart=joints.length;
const legs=[
 {hip:[578,797],knee:[555,959],ankle:[539,1122],toe:[478,1164]},
 {hip:[658,797],knee:[674,962],ankle:[698,1133],toe:[754,1167]}
];
legs.forEach((leg,k)=>{
 const i=legStart+k*3;
 joints.push({name:`hip ${k+1}`,p:leg.hip,parent:0},{name:`knee ${k+1}`,p:leg.knee,parent:i},{name:`ankle ${k+1}`,p:leg.ankle,parent:i+1});
 segments.push([leg.hip,leg.knee],[leg.knee,leg.ankle],[leg.ankle,leg.toe]);
});
const evaluationOrder=[0,chestIndex,1,2,3,4,5,6,7,...digits.map((_,i)=>8+i),headIndex,...digits.map((_,i)=>knuckleStart+i)];
if(config){
 config.base.forEach((p,i)=>joints[i].p=p);
 joints[headIndex].p=config.head;joints[chestIndex].p=config.chest;
 config.digitPoints.forEach(([root,tip],i)=>{digits[i][2]=root;digits[i][3]=tip;joints[8+i].p=root;joints[knuckleStart+i].p=[root[0]+(tip[0]-root[0])*.48,root[1]+(tip[1]-root[1])*.48]});
 config.legs.forEach((leg,k)=>{legs[k]=leg;for(const [n,key] of ['hip','knee','ankle'].entries())joints[legStart+k*3+n].p=leg[key]});
 segments[0]=[config.base[0],config.chest];segments[1]=[config.base[1],config.head];
 for(const [i,end] of [[2,3],[3,4],[5,6],[6,7]])segments[i]=[joints[i].p,joints[end].p];
 segments[4]=[joints[4].p,joints[8].p];segments[7]=[joints[7].p,joints[12].p];
 segments[headIndex]=[config.head,config.headTip];segments[chestIndex]=[config.chest,config.base[1]];
 digits.forEach((d,i)=>{segments[8+i]=[d[2],joints[knuckleStart+i].p];segments[knuckleStart+i]=[joints[knuckleStart+i].p,d[3]]});
 legs.forEach((leg,k)=>{const i=legStart+k*3;segments[i]=[leg.hip,leg.knee];segments[i+1]=[leg.knee,leg.ankle];segments[i+2]=[leg.ankle,leg.toe]});
}
function inside(p,box){return p[0]>=box[0]&&p[0]<=box[2]&&p[1]>=box[1]&&p[1]<=box[3]}
function characterWeights(p){
 const result=joints.map(()=>0);
 if(inside(p,config.headBox)){result[headIndex]=1;return result}
 if(p[1]>config.legTop){
  const k=p[0]<config.legSplit?0:1,i=legStart+k*3,leg=legs[k];
  const pelvis=Math.max(0,1-(p[1]-config.legTop)/60),ankle=Math.max(0,Math.min(1,(p[1]-leg.ankle[1]+25)/45)),shin=Math.max(0,Math.min(1,(p[1]-leg.knee[1]+40)/80));
  result[0]=pelvis;result[i]=(1-pelvis)*(1-ankle)*(1-shin);result[i+1]=(1-pelvis)*(1-ankle)*shin;result[i+2]=(1-pelvis)*ankle;return result;
 }
 const ws=segments.map(([a,b],i)=>{
  if(i>=legStart||i===headIndex)return 0;
  const digit=(i>=8&&i<16)?i-8:(i>=knuckleStart&&i<legStart)?i-knuckleStart:-1;
  if(digit>=0&&!inside(p,config.hands[digit<4?0:1]))return 0;
  return 1/Math.pow(Math.max(digit>=0?7:18,distance(p,a,b)),4);
 });
 const sum=ws.reduce((a,b)=>a+b,0);return ws.map(w=>w/sum);
}
function distance(p,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)));return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)}
function weights(p){
 if(config){
  const base=characterWeights(p);
  if(avatar==='shy'){
   // The glove overlaps the face in the flattened source: keep that contact patch rigid.
   const t=Math.max(0,Math.min(1,(p[1]-445)/65)),headWeight=1-t*t*(3-2*t);
   for(let i=0;i<base.length;i++)base[i]*=1-headWeight;
   base[headIndex]+=headWeight;
  }
  return base;
 }
 // Preserve the face and lower body; blend only near anatomical joints.
 if(p[1]<300&&p[0]>370)return joints.map((_,i)=>i===headIndex?1:0);
 if(p[1]>770){
  const result=joints.map(()=>0),leg=p[0]<620?0:1,i=legStart+leg*3;
  const pelvis=Math.max(0,Math.min(1,(830-p[1])/60));
  const ankle=Math.max(0,Math.min(1,(p[1]-1090)/45));
  const shin=Math.max(0,Math.min(1,(p[1]-915)/80));
  result[0]=pelvis;result[i]=(1-pelvis)*(1-ankle)*(1-shin);
  result[i+1]=(1-pelvis)*(1-ankle)*shin;result[i+2]=(1-pelvis)*ankle;
  return result;
 }
 const ds=segments.map(([a,b])=>distance(p,a,b));
 // Finger weights remain inside their own glove, away from face and jacket.
 for(const i of [...digits.map((_,i)=>8+i),...digits.map((_,i)=>knuckleStart+i)]){
   const digit=i>=knuckleStart?i-knuckleStart:i-8;
   const raised=digit<4;
   const inside=raised ? p[0]<260&&p[1]>222&&p[1]<340 : p[0]<374&&p[1]>610&&p[1]<715;
   if(!inside)ds[i]=10000;
 }
 if(p[1]>330)ds[headIndex]=10000;
 ds[chestIndex]=10000;
 if(p[0]>550&&p[1]>490)ds[0]=Math.min(ds[0],15);
 if(p[0]>450&&p[0]<590&&p[1]>330&&p[1]<480)ds[0]=Math.min(ds[0],25);
 const ws=ds.map((d,i)=>(i===chestIndex||i>=legStart)?0:1/Math.pow(Math.max(12,d),4)),sum=ws.reduce((a,b)=>a+b,0);const normalized=ws.map(w=>w/sum);
 const chestBlend=Math.max(0,Math.min(1,(800-p[1])/160));
 normalized[chestIndex]=normalized[0]*chestBlend;normalized[0]*=1-chestBlend;
 return normalized;
}
const cols=96,rows=Math.ceil(H/10),vertices=[],triangles=[],vertexMap=new Map();
function vertex(x,y){const key=`${x.toFixed(5)},${y.toFixed(5)}`;if(vertexMap.has(key))return vertexMap.get(key);const index=vertices.length,p=[x,y],w=weights(p),sparse=[];for(let i=0;i<w.length;i++)if(w[i]>=1e-12)sparse.push(i,w[i]);vertices.push({p,w,sparse});vertexMap.set(key,index);return index}
for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){
 const left=x*W/cols,top=y*H/rows,right=(x+1)*W/cols,bottom=(y+1)*H/rows;
 const hand=config?config.hands.some(box=>left<box[2]+20&&right>box[0]-20&&top<box[3]+20&&bottom>box[1]-20):(left<280&&right>120&&top<360&&bottom>210)||(left<410&&right>240&&top<730&&bottom>590);
 const n=1;
 for(let sy=0;sy<n;sy++)for(let sx=0;sx<n;sx++){
  const x0=left+(right-left)*sx/n,x1=left+(right-left)*(sx+1)/n,y0=top+(bottom-top)*sy/n,y1=top+(bottom-top)*(sy+1)/n;
  const a=vertex(x0,y0),b=vertex(x1,y0),c=vertex(x0,y1),d=vertex(x1,y1);triangles.push([a,b,d],[a,d,c]);
 }
}
function pose(phase,amount){const t=phase*2*Math.PI;
 const angles=[Math.sin(t)*.005,Math.sin(t+.2)*.018,Math.sin(t)*.055,Math.sin(t-.6)*.16,Math.sin(t-1)*.09,Math.sin(t+.8)*.025,Math.sin(t)*.085,Math.sin(t-.5)*.065];
 for(let i=0;i<digits.length;i++){
  const thumb=i%4===0,delay=(i%4)*.7+(i<4?0:1.1);
  angles.push((Math.sin(t-delay)*.7+Math.sin(2*t-delay)*.3)*(thumb?.13:.10));
 }
 angles.push(Math.sin(t-.25)*.012);
 angles.push(Math.sin(t+.7)*.018);
 for(let i=0;i<digits.length;i++){
  const delay=(i%4)*.7+(i<4?0:1.1);
  angles.push(Math.sin(t-delay-.35)*.20);
 }
 for(let i=0;i<angles.length;i++){
  const multiplier=config?(i>=8&&i!==headIndex&&i!==chestIndex?config.fingerMotion:(i>=2&&i<=7?config.armMotion:1)):1;
  angles[i]*=amount*multiplier*(i>=2&&i<=7?1.5:1);
 }
 const transforms=[];
 evaluationOrder.forEach(i=>{const j=joints[i];const parent=j.parent<0?null:transforms[j.parent];let pivot=i===0?[j.p[0]+Math.sin(t)*5*amount*(config?.hipMotion||1),j.p[1]+(4+(1-Math.cos(t))*1.5)*amount]:j.p;
 if(parent)pivot=apply(parent,pivot);const a=angles[i]+(parent?.angle||0),c=Math.cos(a),s=Math.sin(a);
 transforms[i]={c,s,x:pivot[0]-c*j.p[0]+s*j.p[1],y:pivot[1]-s*j.p[0]-c*j.p[1],angle:a};
 if(i===chestIndex){
  const scale=1+Math.sin(t)*.0025*amount,m=transforms[i];m.c*=scale;m.s*=scale;
  m.x=pivot[0]-m.c*j.p[0]+m.s*j.p[1];m.y=pivot[1]-m.s*j.p[0]-m.c*j.p[1];
 }});
 legs.forEach((leg,k)=>{
  const i=legStart+k*3,hip=apply(transforms[0],leg.hip);
  // A tiny heel lift rotates the shoe about a fixed toe contact.
  const roll=(k===0?1:-1)*(1-Math.cos(t+(k===0?0:Math.PI)))*.009*amount;
  const foot=rotationAt(leg.toe,leg.toe,roll),ankle=apply(foot,leg.ankle);
  const l1=Math.hypot(leg.knee[0]-leg.hip[0],leg.knee[1]-leg.hip[1]),l2=Math.hypot(leg.ankle[0]-leg.knee[0],leg.ankle[1]-leg.knee[1]);
  const dx=ankle[0]-hip[0],dy=ankle[1]-hip[1],d=Math.hypot(dx,dy),ux=dx/d,uy=dy/d;
  const along=(l1*l1-l2*l2+d*d)/(2*d),height=Math.sqrt(Math.max(0,l1*l1-along*along));
  const cross=(leg.ankle[0]-leg.hip[0])*(leg.knee[1]-leg.hip[1])-(leg.ankle[1]-leg.hip[1])*(leg.knee[0]-leg.hip[0]);
  const sign=Math.sign(cross)||1,knee=[hip[0]+along*ux-sign*height*uy,hip[1]+along*uy+sign*height*ux];
  transforms[i]=rotationAt(leg.hip,hip,Math.atan2(knee[1]-hip[1],knee[0]-hip[0])-Math.atan2(leg.knee[1]-leg.hip[1],leg.knee[0]-leg.hip[0]));
  transforms[i+1]=rotationAt(leg.knee,knee,Math.atan2(ankle[1]-knee[1],ankle[0]-knee[0])-Math.atan2(leg.ankle[1]-leg.knee[1],leg.ankle[0]-leg.knee[0]));
  transforms[i+2]=foot;
 });
 if(avatar==='shy'){
  const shoulder=apply(transforms[chestIndex],joints[2].p),wrist=apply(transforms[headIndex],joints[4].p);
  const a=joints[2].p,b=joints[3].p,c=joints[4].p;
  const l1=Math.hypot(b[0]-a[0],b[1]-a[1]),l2=Math.hypot(c[0]-b[0],c[1]-b[1]);
  const dx=wrist[0]-shoulder[0],dy=wrist[1]-shoulder[1],d=Math.hypot(dx,dy);
  const along=(l1*l1-l2*l2+d*d)/(2*d),height=Math.sqrt(Math.max(0,l1*l1-along*along)),sign=Math.sign((c[0]-a[0])*(b[1]-a[1])-(c[1]-a[1])*(b[0]-a[0]))||1;
  const elbow=[shoulder[0]+along*dx/d-sign*height*dy/d,shoulder[1]+along*dy/d+sign*height*dx/d];
  transforms[2]=rotationAt(a,shoulder,Math.atan2(elbow[1]-shoulder[1],elbow[0]-shoulder[0])-Math.atan2(b[1]-a[1],b[0]-a[0]));
  transforms[3]=rotationAt(b,elbow,Math.atan2(wrist[1]-elbow[1],wrist[0]-elbow[0])-Math.atan2(c[1]-b[1],c[0]-b[0]));
  for(const i of [4,8,9,10,11,18,19,20,21])transforms[i]={...transforms[headIndex]};
 }
 return transforms;
}
function rotationAt(source,target,a){const c=Math.cos(a),s=Math.sin(a);return {c,s,x:target[0]-c*source[0]+s*source[1],y:target[1]-s*source[0]-c*source[1],angle:a}}
function apply(m,p){return [m.c*p[0]-m.s*p[1]+m.x,m.s*p[0]+m.c*p[1]+m.y]}
function triangle(src,dst){const [a,b,c]=src,[A,B,C]=dst;
 const u=b[0]-a[0],v=b[1]-a[1],r=c[0]-a[0],s=c[1]-a[1],det=u*s-v*r;
 const aa=((B[0]-A[0])*s-(C[0]-A[0])*v)/det,cc=((C[0]-A[0])*u-(B[0]-A[0])*r)/det;
 const bb=((B[1]-A[1])*s-(C[1]-A[1])*v)/det,dd=((C[1]-A[1])*u-(B[1]-A[1])*r)/det;
 ctx.save();ctx.beginPath();ctx.moveTo(...A);ctx.lineTo(...B);ctx.lineTo(...C);ctx.closePath();ctx.clip();ctx.setTransform(aa,bb,cc,dd,A[0]-aa*a[0]-cc*a[1],A[1]-bb*a[0]-dd*a[1]);ctx.drawImage(image,0,0,W,H);ctx.restore();
}
const warpedFlat=new Float32Array(vertices.length*2);
function skinIntoFlat(ms){
 for(let vIndex=0;vIndex<vertices.length;vIndex++){
  const v=vertices[vIndex],px=v.p[0],py=v.p[1],sparse=v.sparse;
  let x=0,y=0;
  for(let k=0;k<sparse.length;k+=2){
   const m=ms[sparse[k]],w=sparse[k+1];
   x+=w*(m.c*px-m.s*py+m.x);y+=w*(m.s*px+m.c*py+m.y);
  }
  warpedFlat[vIndex*2]=x;warpedFlat[vIndex*2+1]=y;
 }
}
function render(){const phase=phaseValue,amount=Number(controls.amount.value),ms=pose(phase,amount);
 skinIntoFlat(ms);
 if(gpu&&gpu.direct){gpu.draw(warpedFlat);return}
 ctx.clearRect(0,0,W,H);
 if(amount===0)ctx.drawImage(image,0,0,W,H);else if(gpu){gpu.draw(warpedFlat);ctx.drawImage(gpu.surface,0,0)}else{
  const warped=vertices.map((_,i)=>[warpedFlat[i*2],warpedFlat[i*2+1]]);
  for(const ids of triangles)triangle(ids.map(i=>vertices[i].p),ids.map(i=>warped[i]));
 }
 if(!website){const hand=document.querySelector('#hand-rig').getContext('2d');hand.clearRect(0,0,300,200);hand.drawImage(canvas,...(config?.handCrop||[95,210,225,150]),0,0,300,200);}
 if(controls.bones.checked){ctx.strokeStyle='#9be3ff';ctx.fillStyle='#102438';ctx.lineWidth=3;joints.forEach((j,i)=>{const p=apply(ms[i],j.p);if(j.parent>=0){ctx.beginPath();ctx.moveTo(...apply(ms[j.parent],joints[j.parent].p));ctx.lineTo(...p);ctx.stroke()}ctx.beginPath();ctx.arc(...p,7,0,Math.PI*2);ctx.fill();ctx.stroke()})}
}
let gpu=null,phaseValue=0,rafId=0;
let running=!matchMedia('(prefers-reduced-motion: reduce)').matches,ready=false,last=0;
function scheduleFrame(){if(!rafId&&ready&&running&&!document.hidden)rafId=requestAnimationFrame(tick)}
function setRunning(v){running=v;last=0;controls.play.textContent=v?'Pause':'Play';if(v)scheduleFrame()}setRunning(running);
controls.play.onclick=()=>setRunning(!running);controls.rest.onclick=()=>{setRunning(false);controls.amount.value=0;if(ready)render()};controls.phase.oninput=()=>{setRunning(false);phaseValue=Number(controls.phase.value);if(ready)render()};controls.amount.oninput=controls.bones.onchange=()=>ready&&render();
image.onload=()=>{gpu=typeof createMeshRenderer==='function'?createMeshRenderer(W,H,image,vertices,triangles,website?canvas:null):null;if(canvas.dataset)canvas.dataset.renderer=gpu?'webgl':'canvas2d';if(website&&!gpu){parent.postMessage({type:'butler-unavailable'},location.origin);return}if(website)gpu.surface.addEventListener('webglcontextlost',()=>parent.postMessage({type:'butler-unavailable'},location.origin));ready=true;if(!website){document.querySelector('#hand-original').getContext('2d').drawImage(image,...(config?.handCrop||[95,210,225,150]),0,0,300,200);document.querySelector('#original').getContext('2d').drawImage(image,0,0,W,H)}render();if(website)parent.postMessage({type:'butler-ready'},location.origin);scheduleFrame()};
image.onerror=()=>{if(website)parent.postMessage({type:'butler-unavailable'},location.origin);else document.querySelector('p').textContent='Artwork could not load.'};
function tick(now){
 rafId=0;
 if(ready&&running&&!document.hidden){
  if(last)phaseValue=(phaseValue+(now-last)/((config?.cycle||8)*1000))%1;
  last=now;controls.phase.value=phaseValue;render();
  scheduleFrame();
 }else last=0;
}
if(typeof document.addEventListener==='function')document.addEventListener('visibilitychange',()=>{if(document.hidden)last=0;else scheduleFrame()});
// Deterministic geometry checks, available without starting playback.
window.rigCheck=()=>{let error=0;const ms=pose(0,0);for(const v of vertices)for(const m of ms){const p=apply(m,v.p);error=Math.max(error,Math.hypot(p[0]-v.p[0],p[1]-v.p[1]))}return {vertices:vertices.length,joints:joints.length,restError:error,normalizedWeights:vertices.every(v=>Math.abs(v.w.reduce((a,b)=>a+b,0)-1)<1e-9)}};

// Same-origin gallery controls, restricted to the containing parent window.
if(typeof window.addEventListener==='function')window.addEventListener('message',event=>{
 if(event.source!==parent||event.origin!==location.origin||event.data?.type!=='butler-controls')return;
 const {amount,bones,playing}=event.data;
 if(Number.isFinite(amount))controls.amount.value=Math.max(0,Math.min(1,amount));
 if(typeof bones==='boolean')controls.bones.checked=bones;
 if(typeof playing==='boolean')setRunning(playing);
 if(ready)render();
});
