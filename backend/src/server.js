import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import PQueue from 'p-queue';
import { google } from 'googleapis';

const app = express();
app.use(cors());
app.use(express.json());

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..');
const downloadsRoot = path.join(projectRoot, 'downloads');
const mp3Folder = path.join(downloadsRoot, 'youtube-mp3');
const mp4Folder = path.join(downloadsRoot, 'youtube-mp4');
const queue = new PQueue({ concurrency: Number(process.env.DOWNLOAD_CONCURRENCY ?? 2) });
const searchCache = new Map();
const searchCacheTtlMs = 60_000;
const oauthStates = new Set();
const tokenFile = path.join(projectRoot, 'secure-youtube-token.dat');
const credentialsFile = path.join(projectRoot, 'secure-youtube-profile.json');
const playlistQueue = new PQueue({ concurrency: 2 });

await fs.mkdir(mp3Folder, { recursive: true });
await fs.mkdir(mp4Folder, { recursive: true });

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/search', async (req, res) => {
  try {
    const query = String(req.query.q ?? '').trim();
    if (!query) return res.status(400).json({ error: 'q is required' });
    const cacheKey = query.toLowerCase();
    const cached = searchCache.get(cacheKey);
    if (cached && Date.now() - cached.createdAt < searchCacheTtlMs) {
      return res.json({ items: cached.items, cached: true });
    }

    const key = process.env.YOUTUBE_API_KEY;
    if (!key) return res.status(500).json({ error: 'Missing YOUTUBE_API_KEY' });

    const endpoint = new URL('https://www.googleapis.com/youtube/v3/search');
    endpoint.searchParams.set('part', 'snippet');
    endpoint.searchParams.set('maxResults', '12');
    endpoint.searchParams.set('q', query);
    endpoint.searchParams.set('type', 'video');
    endpoint.searchParams.set('key', key);

    const response = await fetch(endpoint);
    if (!response.ok) {
      const text = await response.text();
      return res.status(502).json({ error: 'YouTube API error', details: text });
    }

    const payload = await response.json();
    const items = (payload.items ?? []).map((item) => ({
      videoId: item.id.videoId,
      title: item.snippet.title,
      channel: item.snippet.channelTitle,
      thumbnail: item.snippet.thumbnails?.medium?.url ?? '',
    }));
    searchCache.set(cacheKey, { createdAt: Date.now(), items });
    return res.json({ items });
  } catch (error) {
    return res.status(500).json({ error: 'Search failed', details: String(error) });
  }
});

app.post('/download', async (req, res) => {
  const { videoId, title, format } = req.body ?? {};
  if (!videoId || !title || !format) {
    return res.status(400).json({ error: 'videoId, title and format required' });
  }
  if (format !== 'mp3' && format !== 'mp4') {
    return res.status(400).json({ error: 'format must be mp3 or mp4' });
  }

  try {
    const result = await queue.add(() => downloadFile({ videoId, title, format }));
    return res.json(result);
  } catch (error) {
    return res.status(500).json({ error: 'Download failed', details: String(error) });
  }
});

app.get('/auth/youtube/start', async (_req, res) => {
  try {
    const state = crypto.randomUUID();
    oauthStates.add(state);
    const oauthClient = createOAuthClient();
    const authUrl = oauthClient.generateAuthUrl({
      access_type: 'offline',
      scope: [
        'openid',
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/youtube.readonly',
      ],
      prompt: 'consent',
      state,
    });
    res.json({ authUrl });
  } catch (error) {
    res.status(500).json({ error: 'Unable to start OAuth flow', details: String(error) });
  }
});

app.get('/auth/youtube/callback', async (req, res) => {
  const code = String(req.query.code ?? '');
  const state = String(req.query.state ?? '');
  if (!code || !state || !oauthStates.has(state)) {
    return res.status(400).send('Invalid OAuth callback state.');
  }

  try {
    oauthStates.delete(state);
    const oauthClient = createOAuthClient();
    const { tokens } = await oauthClient.getToken(code);
    oauthClient.setCredentials(tokens);
    await saveEncryptedToken(tokens);

    const profile = await fetchYouTubeProfile(oauthClient);
    await fs.writeFile(credentialsFile, JSON.stringify(profile, null, 2), 'utf8');

    return res.send(
      '<html><body style="font-family:sans-serif;padding:24px;"><h2>YouTube login complete</h2><p>You can return to the app now.</p></body></html>',
    );
  } catch (error) {
    return res.status(500).send(`OAuth callback failed: ${String(error)}`);
  }
});

app.get('/auth/youtube/status', async (_req, res) => {
  try {
    const oauthClient = await getAuthenticatedClient();
    if (!oauthClient) {
      return res.json({ loggedIn: false });
    }
    const profile = await readJsonIfExists(credentialsFile);
    return res.json({ loggedIn: true, profile });
  } catch (error) {
    return res.status(500).json({ error: 'Failed checking auth status', details: String(error) });
  }
});

app.post('/auth/youtube/logout', async (_req, res) => {
  await fs.rm(tokenFile, { force: true });
  await fs.rm(credentialsFile, { force: true });
  return res.json({ loggedIn: false });
});

app.get('/youtube/home', async (_req, res) => {
  try {
    const oauthClient = await requireAuthenticatedClient(res);
    if (!oauthClient) return;
    const yt = google.youtube({ version: 'v3', auth: oauthClient });

    const subChannels = await yt.subscriptions.list({
      mine: true,
      part: ['snippet'],
      maxResults: 10,
      order: 'relevance',
    });

    const channelIds = (subChannels.data.items ?? [])
      .map((item) => item.snippet?.resourceId?.channelId)
      .filter(Boolean)
      .slice(0, 8);

    const uploads = [];
    for (const channelId of channelIds) {
      const search = await yt.search.list({
        channelId,
        maxResults: 3,
        order: 'date',
        type: ['video'],
        part: ['snippet'],
      });
      uploads.push(...(search.data.items ?? []));
    }

    const feedItems = uploads
      .sort((a, b) => new Date(b.snippet?.publishedAt ?? 0) - new Date(a.snippet?.publishedAt ?? 0))
      .slice(0, 25)
      .map(mapSearchItem);

    return res.json({ items: feedItems });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to fetch home feed', details: String(error) });
  }
});

app.get('/youtube/playlists', async (_req, res) => {
  try {
    const oauthClient = await requireAuthenticatedClient(res);
    if (!oauthClient) return;
    const yt = google.youtube({ version: 'v3', auth: oauthClient });
    const response = await yt.playlists.list({
      mine: true,
      part: ['snippet', 'contentDetails'],
      maxResults: 50,
    });
    const playlists = (response.data.items ?? []).map((item) => ({
      id: item.id,
      title: item.snippet?.title ?? 'Untitled',
      thumbnail: item.snippet?.thumbnails?.medium?.url ?? '',
      itemCount: item.contentDetails?.itemCount ?? 0,
    }));
    return res.json({ items: playlists });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to fetch playlists', details: String(error) });
  }
});

app.get('/youtube/playlists/:id/items', async (req, res) => {
  try {
    const playlistId = req.params.id;
    const oauthClient = await requireAuthenticatedClient(res);
    if (!oauthClient) return;
    const yt = google.youtube({ version: 'v3', auth: oauthClient });
    const response = await yt.playlistItems.list({
      playlistId,
      part: ['snippet'],
      maxResults: 50,
    });
    const items = (response.data.items ?? [])
      .filter((item) => item.snippet?.resourceId?.videoId)
      .map((item) => ({
        videoId: item.snippet.resourceId.videoId,
        title: item.snippet.title ?? 'Untitled',
        channel: item.snippet.videoOwnerChannelTitle ?? '',
        thumbnail: item.snippet.thumbnails?.medium?.url ?? '',
      }));
    return res.json({ items });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to fetch playlist items', details: String(error) });
  }
});

app.post('/youtube/download/video', async (req, res) => {
  const { videoId, title, format } = req.body ?? {};
  if (!videoId || !title || !format) {
    return res.status(400).json({ error: 'videoId, title and format required' });
  }
  try {
    const result = await queue.add(() => downloadFile({ videoId, title, format }));
    return res.json({ items: [result] });
  } catch (error) {
    return res.status(500).json({ error: 'Video download failed', details: String(error) });
  }
});

app.post('/youtube/download/playlist', async (req, res) => {
  const { playlistId, format } = req.body ?? {};
  if (!playlistId || !format) {
    return res.status(400).json({ error: 'playlistId and format required' });
  }
  try {
    const oauthClient = await requireAuthenticatedClient(res);
    if (!oauthClient) return;
    const yt = google.youtube({ version: 'v3', auth: oauthClient });
    const response = await yt.playlistItems.list({
      playlistId,
      part: ['snippet'],
      maxResults: 30,
    });

    const videoItems = (response.data.items ?? [])
      .filter((item) => item.snippet?.resourceId?.videoId)
      .map((item) => ({
        videoId: item.snippet.resourceId.videoId,
        title: item.snippet.title ?? 'Untitled',
      }));

    const results = await playlistQueue.addAll(
      videoItems.map((video) => async () => queue.add(() => downloadFile({ ...video, format }))),
    );
    return res.json({ items: results });
  } catch (error) {
    return res.status(500).json({ error: 'Playlist download failed', details: String(error) });
  }
});

app.use('/files', express.static(downloadsRoot));

const port = Number(process.env.PORT ?? 8787);
app.listen(port, () => {
  console.log(`Backend listening on ${port}`);
});

async function downloadFile({ videoId, title, format }) {
  const safeTitle = sanitize(title);
  const outDir = format === 'mp3' ? mp3Folder : mp4Folder;
  const ext = format === 'mp3' ? 'mp3' : 'mp4';
  const filePath = path.join(outDir, `${safeTitle}-${Date.now()}.${ext}`);
  const url = `https://www.youtube.com/watch?v=${videoId}`;

  const args =
    format === 'mp3'
      ? [
          '--extract-audio',
          '--audio-format',
          'mp3',
          '--audio-quality',
          '0',
          '-o',
          filePath,
          url,
        ]
      : ['-f', 'mp4', '-o', filePath, url];

  await runProcess('yt-dlp', args);

  const relPath = path.relative(downloadsRoot, filePath).split(path.sep).join('/');
  return {
    title,
    filePath,
    relativePath: relPath,
    format,
  };
}

function runProcess(command, args) {
  return new Promise((resolve, reject) => {
    const process = spawn(command, args, { stdio: 'inherit' });
    process.on('error', reject);
    process.on('exit', (code) => {
      if (code === 0) return resolve();
      reject(new Error(`${command} exited with ${code}`));
    });
  });
}

function sanitize(value) {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 80);
}

function createOAuthClient() {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const redirectUri = process.env.GOOGLE_REDIRECT_URI;
  if (!clientId || !clientSecret || !redirectUri) {
    throw new Error('Missing Google OAuth env vars');
  }
  return new google.auth.OAuth2(clientId, clientSecret, redirectUri);
}

async function requireAuthenticatedClient(res) {
  const client = await getAuthenticatedClient();
  if (!client) {
    res.status(401).json({ error: 'Not logged into YouTube' });
    return null;
  }
  return client;
}

async function getAuthenticatedClient() {
  const encrypted = await readTextIfExists(tokenFile);
  if (!encrypted) return null;
  const oauthClient = createOAuthClient();
  const tokens = decryptToken(encrypted);
  oauthClient.setCredentials(tokens);
  if (tokens.expiry_date && Date.now() >= tokens.expiry_date) {
    const refreshed = await oauthClient.refreshAccessToken();
    oauthClient.setCredentials(refreshed.credentials);
    await saveEncryptedToken(refreshed.credentials);
  }
  return oauthClient;
}

async function fetchYouTubeProfile(oauthClient) {
  const yt = google.youtube({ version: 'v3', auth: oauthClient });
  const response = await yt.channels.list({
    mine: true,
    part: ['snippet'],
    maxResults: 1,
  });
  const channel = response.data.items?.[0];
  return {
    channelId: channel?.id ?? '',
    title: channel?.snippet?.title ?? '',
    avatar: channel?.snippet?.thumbnails?.default?.url ?? '',
  };
}

function mapSearchItem(item) {
  return {
    videoId: item.id?.videoId ?? '',
    title: item.snippet?.title ?? 'Untitled',
    channel: item.snippet?.channelTitle ?? '',
    thumbnail: item.snippet?.thumbnails?.medium?.url ?? '',
    publishedAt: item.snippet?.publishedAt ?? '',
  };
}

async function saveEncryptedToken(tokens) {
  const payload = JSON.stringify(tokens);
  const cipherText = encryptToken(payload);
  await fs.writeFile(tokenFile, cipherText, 'utf8');
}

function encryptToken(plainText) {
  const secret = process.env.ENCRYPTION_SECRET ?? 'dev_secret_change_me';
  const key = crypto.createHash('sha256').update(secret).digest();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const encrypted = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  return `${iv.toString('hex')}:${encrypted.toString('hex')}`;
}

function decryptToken(cipherText) {
  const secret = process.env.ENCRYPTION_SECRET ?? 'dev_secret_change_me';
  const key = crypto.createHash('sha256').update(secret).digest();
  const [ivHex, encryptedHex] = cipherText.split(':');
  const iv = Buffer.from(ivHex, 'hex');
  const encrypted = Buffer.from(encryptedHex, 'hex');
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  return JSON.parse(decrypted.toString('utf8'));
}

async function readTextIfExists(file) {
  try {
    return await fs.readFile(file, 'utf8');
  } catch {
    return null;
  }
}

async function readJsonIfExists(file) {
  const text = await readTextIfExists(file);
  return text ? JSON.parse(text) : null;
}
