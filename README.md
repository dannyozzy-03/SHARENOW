# Twitter Clone Backend

A Node.js backend server for a Flutter Twitter clone app with real-time messaging and admin post functionality.

## Features

- 🔌 **WebSocket Server** - Real-time messaging between users
- 📝 **REST API** - Admin post management
- 🔔 **Firebase Push Notifications** - FCM integration
- 📊 **Server-Sent Events** - Live admin post updates
- 💬 **Group Chat Support** - Multi-user conversations

## Endpoints

- `POST /admin/post` - Create admin posts
- `GET /events` - Server-sent events for admin posts
- `GET /health` - Health check
- `WS /` - WebSocket connection for real-time messaging

## Quick Start

```bash
npm install
npm start
```

Server runs on port 4000 (or PORT environment variable).

## Deployment

This backend is configured for easy deployment on:
- Render.com
- Railway.app
- Heroku
- Any Node.js hosting platform

## Firebase Setup

Make sure to configure Firebase Admin SDK with your service account credentials.

## Tech Stack

- Node.js + Express
- WebSocket (ws library)
- Firebase Admin SDK
- CORS enabled
