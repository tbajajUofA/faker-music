# Red/Black Phone Music App

Android-first Flutter music app with:
- Local MP3 import from files already on the phone
- Playlist creation and management
- Playback with loop modes (off/track/playlist)
- Phone-only YouTube search and MP3 download
- A dormant personalized YouTube/feed path reserved for a later recommendation iteration

No Node backend is required for the current phone-only flow. You only need the phone and internet for YouTube search/download; saved MP3s can be played afterward from app storage.

## WSL + Android Phone Setup

1. Install Flutter in WSL and make sure `flutter` is on the WSL PATH.
2. Connect your Android phone with USB debugging enabled.
3. From WSL, open this project folder:
   - `cd /home/tj/fake`
4. Install Dart/Flutter packages:
   - `flutter pub get`
5. Confirm Flutter sees the phone:
   - `flutter devices`
6. Run the app on the phone:
   - `flutter run -d <device-id>`

If `flutter devices` does not show the phone from WSL, start/confirm ADB on Windows first, reconnect the USB cable, accept the phone authorization prompt, then try `flutter devices` again.

## Current App Flow

- Use **Library** or **Home** to import existing `.mp3` files from the phone.
- Use **Playlists** to create playlists and import MP3 files directly into a playlist.
- Use **Search** to search YouTube, preview a result, and download audio as a real `.mp3` on the phone.
- Use **Now Playing** for queue controls, next/previous, and loop mode.

## Personalized YouTube Feed

Personalized YouTube login/feed/playlists are intentionally disabled for this iteration. The app keeps service/model hooks for a later local recommendation system based on user activity, but the current build does not require Google OAuth, a YouTube API key, or the backend server.

## Legacy Backend

The `backend/` folder is still present as legacy/experimental code, but it is not required to install, run, search YouTube, download MP3s, import songs, create playlists, or play music in the current app.

## TODO

- Add personalized feed/recommendations based on user activity
- Add geolocation to get certain radio stations
- Add premium account service
- Customize backgrounds