require("dotenv").config();
const express = require("express");
const session = require("express-session");
const crypto = require("crypto");
const { google } = require("googleapis");

const app = express();
app.use(express.json());
app.use(session({
  secret: process.env.ADMIN_TOKEN || crypto.randomBytes(32).toString("hex"),
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, secure: true, sameSite: "lax" }
}));

const PORT = Number(process.env.PORT || 8787);

function need(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing environment variable: ${name}`);
  return v;
}

function googleClient() {
  return new google.auth.OAuth2(
    need("GOOGLE_CLIENT_ID"),
    need("GOOGLE_CLIENT_SECRET"),
    need("GOOGLE_REDIRECT_URI")
  );
}

app.get("/auth/youtube/start", (req,res)=>{
  const oauth2 = googleClient();
  const state = crypto.randomBytes(24).toString("hex");
  req.session.oauthState = state;
  const url = oauth2.generateAuthUrl({
    access_type: "offline",
    prompt: "consent",
    state,
    scope: [
      "https://www.googleapis.com/auth/youtube"
    ]
  });
  res.redirect(url);
});

app.get("/auth/youtube/callback", async (req,res)=>{
  try {
    if (!req.query.code || req.query.state !== req.session.oauthState)
      return res.status(400).send("Invalid OAuth state/code.");
    const oauth2 = googleClient();
    const {tokens} = await oauth2.getToken(req.query.code);
    oauth2.setCredentials(tokens);

    // Store tokens server-side only. For this prototype we keep them in session.
    req.session.youtube = {
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      expiry_date: tokens.expiry_date
    };

    const youtube = google.youtube({version:"v3", auth: oauth2});
    const ch = await youtube.channels.list({part:["id,snippet"], mine:true});
    const channel = ch.data.items?.[0];

    res.type("html").send(`
      <h2>YouTube connected</h2>
      <p>Channel: ${escapeHtml(channel?.snippet?.title || "Unknown")}</p>
      <p>You can close this window and return to MultiStream.</p>
    `);
  } catch (e) {
    console.error(e);
    res.status(500).send("YouTube OAuth failed.");
  }
});

// Creates a private YouTube broadcast + RTMP stream and returns ingestion info.
// This must only be called after a successful YouTube OAuth connection.
app.post("/api/youtube/create-stream", async (req,res)=>{
  try {
    if (!req.session.youtube) return res.status(401).json({error:"youtube_not_connected"});
    const oauth2 = googleClient();
    oauth2.setCredentials(req.session.youtube);
    const youtube = google.youtube({version:"v3", auth: oauth2});

    const title = String(req.body?.title || "MultiStream Live");
    const privacy = process.env.YOUTUBE_DEFAULT_PRIVACY || "private";

    const stream = await youtube.liveStreams.insert({
      part: ["snippet,cdn,contentDetails,status"],
      requestBody: {
        snippet: {title: `${title} Stream`},
        cdn: {
          frameRate: "variable",
          ingestionType: "rtmp",
          resolution: "variable"
        },
        contentDetails: {isReusable: false}
      }
    });

    const broadcast = await youtube.liveBroadcasts.insert({
      part: ["snippet,status,contentDetails"],
      requestBody: {
        snippet: {
          title,
          scheduledStartTime: new Date(Date.now()+60000).toISOString()
        },
        status: {privacyStatus: privacy},
        contentDetails: {enableAutoStart: true, enableAutoStop: true}
      }
    });

    await youtube.liveBroadcasts.bind({
      part: ["id,contentDetails"],
      id: broadcast.data.id,
      streamId: stream.data.id
    });

    const ing = stream.data.cdn?.ingestionInfo;
    if (!ing?.ingestionAddress || !ing?.streamName)
      throw new Error("YouTube did not return ingestion info.");

    res.json({
      provider:"youtube",
      broadcastId:broadcast.data.id,
      streamId:stream.data.id,
      ingestionAddress:ing.ingestionAddress,
      streamName:ing.streamName
    });
  } catch(e) {
    console.error(e.response?.data || e);
    res.status(500).json({error:"youtube_stream_creation_failed", detail:e.response?.data || e.message});
  }
});

// Facebook OAuth connection.
// Actual Live creation requires the Meta app's approved permissions/product access.
app.get("/auth/facebook/start", (req,res)=>{
  const state = crypto.randomBytes(24).toString("hex");
  req.session.fbState = state;
  const redirect = need("META_REDIRECT_URI");
  const url = new URL("https://www.facebook.com/v24.0/dialog/oauth");
  url.searchParams.set("client_id", need("META_APP_ID"));
  url.searchParams.set("redirect_uri", redirect);
  url.searchParams.set("state", state);
  url.searchParams.set("scope", "public_profile");
  res.redirect(url.toString());
});

app.get("/auth/facebook/callback", async (req,res)=>{
  try {
    if (!req.query.code || req.query.state !== req.session.fbState)
      return res.status(400).send("Invalid Facebook OAuth state/code.");
    const tokenUrl = new URL("https://graph.facebook.com/v24.0/oauth/access_token");
    tokenUrl.searchParams.set("client_id", need("META_APP_ID"));
    tokenUrl.searchParams.set("client_secret", need("META_APP_SECRET"));
    tokenUrl.searchParams.set("redirect_uri", need("META_REDIRECT_URI"));
    tokenUrl.searchParams.set("code", req.query.code);
    const r = await fetch(tokenUrl);
    const data = await r.json();
    if (!r.ok) throw new Error(JSON.stringify(data));
    req.session.facebook = data;
    res.type("html").send("<h2>Facebook connected</h2><p>Return to MultiStream.</p>");
  } catch(e) {
    console.error(e);
    res.status(500).send("Facebook OAuth failed. Meta Live permissions/app review may still be required.");
  }
});

// TikTok Login Kit connection.
// LIVE-specific APIs/permissions are subject to TikTok app approval.
app.get("/auth/tiktok/start", (req,res)=>{
  const state = crypto.randomBytes(24).toString("hex");
  req.session.ttState = state;
  const url = new URL("https://www.tiktok.com/v2/auth/authorize/");
  url.searchParams.set("client_key", need("TIKTOK_CLIENT_KEY"));
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", "user.info.basic");
  url.searchParams.set("redirect_uri", need("TIKTOK_REDIRECT_URI"));
  url.searchParams.set("state", state);
  res.redirect(url.toString());
});

app.get("/auth/tiktok/callback", async (req,res)=>{
  try {
    if (!req.query.code || req.query.state !== req.session.ttState)
      return res.status(400).send("Invalid TikTok OAuth state/code.");

    const body = new URLSearchParams();
    body.set("client_key", need("TIKTOK_CLIENT_KEY"));
    body.set("client_secret", need("TIKTOK_CLIENT_SECRET"));
    body.set("code", req.query.code);
    body.set("grant_type", "authorization_code");
    body.set("redirect_uri", need("TIKTOK_REDIRECT_URI"));

    const r = await fetch("https://open.tiktokapis.com/v2/oauth/token/", {
      method:"POST",
      headers:{"Content-Type":"application/x-www-form-urlencoded"},
      body
    });
    const data = await r.json();
    if (!r.ok) throw new Error(JSON.stringify(data));
    req.session.tiktok = data;
    res.type("html").send("<h2>TikTok connected</h2><p>Return to MultiStream. LIVE access still depends on your app/account permissions.</p>");
  } catch(e) {
    console.error(e);
    res.status(500).send("TikTok OAuth failed.");
  }
});

app.get("/api/connections",(req,res)=>{
  res.json({
    youtube: !!req.session.youtube,
    facebook: !!req.session.facebook,
    tiktok: !!req.session.tiktok
  });
});

app.get("/health",(req,res)=>res.json({ok:true}));

function escapeHtml(x){
  return String(x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
}

app.listen(PORT,()=>console.log(`OAuth server listening on ${PORT}`));
