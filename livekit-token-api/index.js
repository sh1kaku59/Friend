require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { AccessToken } = require('livekit-server-sdk');

const app = express();
app.use(cors());
app.use(express.json());

const apiKey = process.env.LIVEKIT_API_KEY;
const apiSecret = process.env.LIVEKIT_API_SECRET;

console.log('DEBUG: LIVEKIT_API_KEY:', apiKey);
console.log('DEBUG: LIVEKIT_API_SECRET:', apiSecret);

app.post('/get-livekit-token', async (req, res) => {
  try {
    const { userId, roomId } = req.body;
    if (!userId || !roomId) {
      return res.status(400).json({ error: 'Missing userId or roomId' });
    }

    if (!apiKey || !apiSecret) {
      console.error('ERROR: LIVEKIT_API_KEY or LIVEKIT_API_SECRET is not set!');
      return res.status(500).json({ error: 'Server configuration error: LiveKit API keys not set.' });
    }

    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
    });

    at.addGrant({
      roomJoin: true,
      room: roomId,
      canPublish: true,
      canSubscribe: true,
    });

    const token = await at.toJwt();
    console.log('DEBUG: Generated JWT Token:', token);

    res.json({ token });
  } catch (error) {
    console.error('Error generating token:', error);
    res.status(500).json({ error: 'Failed to generate token' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`LiveKit token API running on port ${PORT}`);
});