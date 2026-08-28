const express = require("express");
const fs = require("fs");
const { spawn } = require("child_process");

const app = express();
app.use(express.json({limit:"256kb"}));

const PORT = Number(process.env.PORT || 8787);
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "";
const INPUT_RTMP = process.env.INPUT_RTMP || "rtmp://mediamtx:1935/live/multistream";
const DB = "/data/destinations.json";
const procs = new Map();

function auth(req,res,next){
  const got = (req.headers.authorization || "").replace(/^Bearer\s+/i,"");
  if (!ADMIN_TOKEN || got !== ADMIN_TOKEN) return res.status(401).json({error:"unauthorized"});
  next();
}
function load(){
  try { return JSON.parse(fs.readFileSync(DB,"utf8")); } catch { return []; }
}
function save(x){
  fs.mkdirSync("/data",{recursive:true});
  fs.writeFileSync(DB, JSON.stringify(x,null,2));
}
function targetUrl(d){
  const base = String(d.url||"").trim().replace(/\/+$/,"");
  const key = String(d.streamKey||"").trim().replace(/^\/+/,"");
  if (!base) throw new Error("Missing destination URL");
  if (!key) return base;
  // If the caller already supplied a path containing the key, do not append it twice.
  if (base.endsWith("/"+key) || base.endsWith(key)) return base;
  return `${base}/${key}`;
}
function startDestination(d){
  if (!d.enabled) return;
  if (procs.has(d.name)) return;
  const out = targetUrl(d);
  const args = [
    "-hide_banner","-loglevel","warning",
    "-i",INPUT_RTMP,
    "-c","copy",
    "-f","flv",
    out
  ];
  const p = spawn("ffmpeg", args, {stdio:["ignore","ignore","pipe"]});
  procs.set(d.name,p);
  p.stderr.on("data", b => process.stdout.write(`[${d.name}] ${b}`));
  p.on("exit", () => {
    procs.delete(d.name);
    // Restart while the destination is enabled.
    setTimeout(() => {
      const current = load().find(x => x.name === d.name);
      if (current && current.enabled) startDestination(current);
    }, 3000);
  });
}
function stopDestination(name){
  const p = procs.get(name);
  if (p) { p.kill("SIGTERM"); procs.delete(name); }
}
function reconcile(){
  const ds = load();
  for (const d of ds) {
    if (d.enabled) startDestination(d);
    else stopDestination(d.name);
  }
  for (const name of [...procs.keys()]) {
    if (!ds.some(d => d.name === name && d.enabled)) stopDestination(name);
  }
}

app.get("/health",(req,res)=>res.json({ok:true, input:INPUT_RTMP, running:[...procs.keys()]}));
app.get("/api/destinations",auth,(req,res)=>res.json(load().map(d=>({...d,streamKey:d.streamKey?"********":"")})));

app.post("/api/destinations",auth,(req,res)=>{
  const {name,url,streamKey,enabled=true} = req.body || {};
  if (!name || !url) return res.status(400).json({error:"name and url are required"});
  const ds=load();
  const i=ds.findIndex(x=>x.name===name);
  const d={name:String(name),url:String(url),streamKey:String(streamKey||""),enabled:Boolean(enabled)};
  if(i>=0) ds[i]=d; else ds.push(d);
  save(ds); reconcile();
  res.json({ok:true,name:d.name,enabled:d.enabled});
});

app.delete("/api/destinations/:name",auth,(req,res)=>{
  const ds=load().filter(x=>x.name!==req.params.name);
  stopDestination(req.params.name); save(ds);
  res.json({ok:true});
});

app.post("/api/reconcile",auth,(req,res)=>{reconcile();res.json({ok:true,running:[...procs.keys()]});});

app.listen(PORT,()=>{console.log(`Router API listening on ${PORT}`); reconcile();});
