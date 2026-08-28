# MultiStream Real — Multistream Edition

This package contains:
- Flutter Android broadcaster: Camera + Microphone -> one RTMP input.
- A Node.js control API for destination configuration.
- A Docker/MediaMTX + FFmpeg restreaming server.
- Three destination slots: YouTube, Facebook, TikTok/Custom RTMP.
- A Red5 test destination can also be configured.

## Architecture

Phone -> RTMP ingest (MediaMTX) -> FFmpeg -> YouTube / Facebook / TikTok / Red5

The phone sends ONE upload. The server makes the copies.

## Important platform credentials

The code does NOT contain real YouTube/Facebook/TikTok credentials.
You must provide the destination RTMP URL and stream key/token yourself.

- YouTube Live uses OAuth/API for automatic broadcast management, or its RTMP ingest URL + stream key.
- Facebook Live requires the appropriate Meta permissions/app setup, or an RTMPS ingest URL + key.
- TikTok LIVE availability/API access is account/region dependent. If TikTok gives the account an RTMP URL + stream key, use the TikTok/Custom RTMP destination slot.

Never commit real stream keys to a public GitHub repository.

## Server

Requirements: Docker Desktop or Docker Engine + Compose.

1. Edit `server/.env.example` -> `server/.env`
2. Set `PUBLIC_RTMP_HOST` to the public IP/hostname of the server.
3. Run:
   docker compose up -d --build
4. RTMP ingest:
   rtmp://YOUR_SERVER:1935/live/multistream
5. Control API:
   http://YOUR_SERVER:8787

The API is intentionally protected by `ADMIN_TOKEN`.

## Configure destinations

Example:
POST /api/destinations
Authorization: Bearer YOUR_ADMIN_TOKEN
Content-Type: application/json

{
  "name": "YouTube",
  "enabled": true,
  "url": "rtmps://YOUR_YOUTUBE_INGEST_URL",
  "streamKey": "YOUR_YOUTUBE_STREAM_KEY"
}

Repeat for Facebook and TikTok.

The router builds the final target as:
url + "/" + streamKey
unless `url` already ends with the stream key.

## Flutter

Set the app's RTMP publish URL to:
rtmp://YOUR_SERVER:1935/live/multistream

The app sends one stream to the server. The server fans it out.

## Red5

Red5 can be used as another RTMP destination, but Red5 Cloud's programmatic egress provisioning requires the appropriate Stream Manager/API credentials and plan access. Do not put Red5 admin JWTs in the mobile app.

## Security

For production:
- HTTPS for the control API
- Secret storage (Vault/KMS)
- Per-user auth
- encrypted destination secrets
- RLS if using Supabase
- rate limiting
- audit logs
- token rotation
- do not expose FFmpeg command lines containing keys

## OAuth connections

The mobile UI now has Connect buttons for YouTube, Facebook, and TikTok.
The buttons open the backend OAuth endpoints.

### Required credentials
You must create developer apps on each platform and put their client credentials in `server/.env`.
Do NOT put client secrets in Flutter or GitHub source code.

YouTube is implemented end-to-end for OAuth -> create a private Live Broadcast + Live Stream -> return RTMP ingestion address and stream name. YouTube's official Live Streaming API uses OAuth and exposes ingestion information for the created stream.

Facebook and TikTok connection flows are implemented, but actual Live/RTMP provisioning depends on the permissions and product access approved for your Meta/TikTok developer apps. TikTok's Login Kit OAuth does not by itself grant LIVE streaming APIs.

The backend must be deployed on a public HTTPS URL for OAuth callbacks.
