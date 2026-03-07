# Google OAuth Setup

## What It Does

Enables two features:
1. **"Sign in with Google"** - Agents/admins log in using Google accounts
2. **Connect Gmail as email inbox** - Organizations connect Gmail for email support

## Configuration Values

| Config | What It DOES | Example |
|--------|-------------|---------|
| **GOOGLE_OAUTH_CLIENT_ID** | Identifies your app to Google | `1234567890-abc123.apps.googleusercontent.com` |
| **GOOGLE_OAUTH_CLIENT_SECRET** | Proves your app is legitimate to Google | `GOCSPX-abcdef123456` |
| **GOOGLE_OAUTH_REDIRECT_URI** | Where Google sends users after authorization | `https://your-chatwoot-domain.com/omniauth/google_oauth2/callback` |
| **GOOGLE_OAUTH_CALLBACK_URL** | Same as REDIRECT_URI (frontend callback) | `https://your-chatwoot-domain.com/omniauth/google_oauth2/callback` |

## How to Get These Values

### Step 1: Create Google Cloud Project
1. Go to https://console.cloud.google.com/
2. Create new project
3. Enable "Google+ API"
4. Go to "OAuth consent screen" → Configure app name and scopes

### Step 2: Create OAuth Credentials
1. Go to "Credentials" 
2. Click "Create OAuth 2.0 Client ID" (Web application)
3. Add Authorized URIs

### Step 3: Configure in Google Cloud Console

| Field | Value |
|-------|-------|
| **OAuth 2.0 client name** | `Chatwoot` (for identification only) |
| **Authorized JavaScript origins** | `https://your-chatwoot-domain.com` |
| **Authorized redirect URIs** | `https://your-chatwoot-domain.com/omniauth/google_oauth2/callback` |

**Important:** Both domains must match exactly and use HTTPS.

### Step 4: Copy to Chatwoot Super Admin Console

Path: `/super_admin/app_config?config=google`

```
Google OAuth Client ID: [paste from Google console]
Google OAuth Client Secret: [paste from Google console]
Google OAuth Redirect URI: https://your-chatwoot-domain.com/omniauth/google_oauth2/callback
Enable Google OAuth login: ON
```

## OAuth Flow

```
User clicks "Sign in with Google"
  ↓
Redirected to Google login page (accounts.google.com)
  ↓
User enters credentials and clicks "Allow"
  ↓
Google redirects to: /omniauth/google_oauth2/callback
  ↓
Chatwoot processes response:
  - If user exists: Sign in
  - If new user: Create account + send password reset
  ↓
User logged into Chatwoot ✅
```
