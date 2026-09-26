'use strict';
function createMeshRenderer(width,height,image,vertices,triangles){
 const surface=document.createElement('canvas');surface.width=width;surface.height=height;
 const gl=surface.getContext('webgl',{alpha:true,antialias:false,preserveDrawingBuffer:true,failIfMajorPerformanceCaveat:true});
 if(!gl)return null;
 // Software rasterisers (VMs, remote desktops, blocklisted GPUs) keep the static artwork instead.
 const info=gl.getExtension('WEBGL_debug_renderer_info');
 if(/swiftshader|llvmpipe|softpipe|software|basic render/i.test(String(gl.getParameter(info?info.UNMASKED_RENDERER_WEBGL:gl.RENDERER))))return null;
 const compile=(type,source)=>{const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(shader));return shader};
 const program=gl.createProgram();
 gl.attachShader(program,compile(gl.VERTEX_SHADER,`attribute vec2 position;attribute vec2 uv;varying vec2 tex;void main(){tex=uv;gl_Position=vec4(position.x/${width.toFixed(1)}*2.0-1.0,1.0-position.y/${height.toFixed(1)}*2.0,0.0,1.0);}`));
 gl.attachShader(program,compile(gl.FRAGMENT_SHADER,'precision mediump float;varying vec2 tex;uniform sampler2D artwork;void main(){gl_FragColor=texture2D(artwork,tex);}'));
 gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));gl.useProgram(program);
 const setup=(name,data,usage)=>{const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,data,usage);const location=gl.getAttribLocation(program,name);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,2,gl.FLOAT,false,0,0);return buffer};
 const positions=new Float32Array(vertices.length*2);
 const positionBuffer=setup('position',positions,gl.DYNAMIC_DRAW);
 setup('uv',new Float32Array(vertices.flatMap(v=>[v.p[0]/width,v.p[1]/height])),gl.STATIC_DRAW);
 const indices=new Uint16Array(triangles.flat());gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,gl.createBuffer());gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indices,gl.STATIC_DRAW);
 gl.bindTexture(gl.TEXTURE_2D,gl.createTexture());gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,true);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);
 gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE_MINUS_SRC_ALPHA);gl.clearColor(0,0,0,0);gl.viewport(0,0,width,height);
 return {surface,draw(points){for(let i=0;i<points.length;i++){positions[2*i]=points[i][0];positions[2*i+1]=points[i][1]}gl.bindBuffer(gl.ARRAY_BUFFER,positionBuffer);gl.bufferSubData(gl.ARRAY_BUFFER,0,positions);gl.clear(gl.COLOR_BUFFER_BIT);gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0)}};
}
