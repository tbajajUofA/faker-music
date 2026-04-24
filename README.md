# Red/Black Spotify-Style Flutter App

Android-first Flutter music app with:
- Local MP3 import
- Playback with loop modes (off/track/playlist)
- Playlist creation and management
- In-app YouTube search + video preview + download (MP3/MP4) via backend API
- YouTube account login to load personalized home feed and your playlists
- Hybrid download path: backend first, local fallback in app

## Flutter Setup

1. Install Flutter and run:
   - `flutter pub get`
2. Start Android emulator/device.
3. Run app:
   - `flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8787`

## Backend Setup (YouTube Search + Download)

Backend lives in `backend/`.

1. Install requirements on your machine:
   - Node.js 20+
   - `yt-dlp` in PATH
   - `ffmpeg` in PATH
2. Configure environment:
   - Copy `backend/.env.example` to `backend/.env`
   - Set `YOUTUBE_API_KEY`
   - Set OAuth vars:
     - `GOOGLE_CLIENT_ID`
     - `GOOGLE_CLIENT_SECRET`
     - `GOOGLE_REDIRECT_URI`
     - `ENCRYPTION_SECRET`
3. Install dependencies and run:
   - `cd backend`
   - `npm install`
   - `npm run start`

Backend defaults to `http://localhost:8787`.
Android emulator reaches host via `http://10.0.2.2:8787`.
Physical phone should use `http://<your_laptop_lan_ip>:8787` in the app's backend URL field.

## Google OAuth Setup

1. In Google Cloud Console, create OAuth credentials (Web application type).
2. Add authorized redirect URI:
   - `http://localhost:8787/auth/youtube/callback`
3. Enable YouTube Data API v3 for the same project.
4. Add OAuth values to `backend/.env`.
5. Restart backend, then use the app's **Login** button in Home.

## API Contract

- `GET /health` -> health check
- `GET /search?q=<term>` -> YouTube search results
- `GET /auth/youtube/start` -> starts login and returns browser auth URL
- `GET /auth/youtube/callback` -> OAuth callback handler
- `GET /auth/youtube/status` -> current login state and profile info
- `POST /auth/youtube/logout` -> clear current auth session
- `GET /youtube/home` -> personalized recent feed (from subscriptions)
- `GET /youtube/playlists` -> logged-in account playlists
- `GET /youtube/playlists/:id/items` -> items in one playlist
- `POST /youtube/download/video` body:
  ```json
  {
    "videoId": "xxxx",
    "title": "Track Name",
    "format": "mp3"
  }
  ```
  Returns one downloaded file payload.
- `POST /youtube/download/playlist` body:
  ```json
  {
    "playlistId": "PLxxxx",
    "format": "mp3"
  }
  ```
  Returns all downloaded file payloads for that playlist.

## Download Folder Organization

- All backend MP3 downloads are written to:
  - `backend/downloads/youtube-mp3`
- All backend MP4 downloads are written to:
  - `backend/downloads/youtube-mp4`

This keeps MP3 files in one dedicated folder to avoid clutter.
