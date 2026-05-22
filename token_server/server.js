require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;

// In-memory data store
let messages = [];
let callRequests = [];
let sessionLogs = [];
let roomMetas = [];

// Seed database
const SEED_TRAINER = {
  id: 'aarav_trainer',
  role: 'trainer',
  name: 'Aarav (Lead Trainer)',
  email: 'aarav@wtf.fit',
  avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
};

const SEED_MEMBER = {
  id: 'dk_member',
  role: 'member',
  name: 'DK',
  email: 'dk@wtf.fit',
  avatarUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=150&q=80',
  assignedTrainerId: 'aarav_trainer'
};

// 100ms JWT Generation
app.get('/token', (req, res) => {
  const { userId, role, roomId } = req.query;

  if (!userId || !role || !roomId) {
    return res.status(400).json({ error: 'userId, role, and roomId are required parameters' });
  }

  const accessKey = process.env.HMS_ACCESS_KEY || 'mock_access_key';
  const appSecret = process.env.HMS_APP_SECRET || 'mock_app_secret';

  const payload = {
    access_key: accessKey,
    room_id: roomId,
    user_id: userId,
    role: role,
    type: 'app',
    version: 2,
    jti: uuidv4(),
    iat: Math.floor(Date.now() / 1000),
    nbf: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 24 * 60 * 60, // 24 Hours validity
  };

  try {
    const token = jwt.sign(payload, appSecret, { algorithm: 'HS256' });
    console.log(`[RTC] Token generated for user: ${userId}, role: ${role}, room: ${roomId}`);
    res.json({ token });
  } catch (err) {
    console.error('[RTC] Token generation failed:', err);
    res.status(500).json({ error: 'Failed to generate token' });
  }
});

// Create 100ms Room
app.post('/api/rooms', async (req, res) => {
  const { callRequestId } = req.body;
  if (!callRequestId) {
    return res.status(400).json({ error: 'callRequestId is required' });
  }

  const accessKey = process.env.HMS_ACCESS_KEY;
  const appSecret = process.env.HMS_APP_SECRET;

  // Fallback / mock behavior
  if (!accessKey || !appSecret || accessKey === 'mock_access_key') {
    const mockRoomId = 'mock_room_' + uuidv4();
    const meta = {
      id: uuidv4(),
      callRequestId,
      hmsRoomId: mockRoomId,
      hmsRoleMember: 'member',
      hmsRoleTrainer: 'trainer'
    };
    roomMetas.push(meta);
    console.log(`[RTC] Created Mock Room for Request ${callRequestId}: ${mockRoomId}`);
    return res.json(meta);
  }

  // Real 100ms Room creation API
  try {
    // Generate Management Token
    const mgmtPayload = {
      access_key: accessKey,
      type: 'management',
      version: 2,
      jti: uuidv4(),
      iat: Math.floor(Date.now() / 1000),
      nbf: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 600, // 10 minutes
    };
    const mgmtToken = jwt.sign(mgmtPayload, appSecret, { algorithm: 'HS256' });

    // Node-fetch is not required if we use standard dynamic import or https module.
    // Let's use dynamic import of node-fetch or standard https request for portability.
    const https = require('https');
    const postData = JSON.stringify({
      name: `room-${callRequestId.substring(0, 8)}`,
      description: `Call session for request ${callRequestId}`,
      template_id: process.env.HMS_TEMPLATE_ID
    });

    const options = {
      hostname: 'api.100ms.live',
      port: 443,
      path: '/v2/rooms',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${mgmtToken}`,
        'Content-Type': 'application/json',
        'Content-Length': postData.length
      }
    };

    const request = https.request(options, (response) => {
      let body = '';
      response.on('data', (d) => { body += d; });
      response.on('end', () => {
        try {
          const roomData = JSON.parse(body);
          if (roomData.id) {
            const meta = {
              id: uuidv4(),
              callRequestId,
              hmsRoomId: roomData.id,
              hmsRoleMember: 'member',
              hmsRoleTrainer: 'trainer'
            };
            roomMetas.push(meta);
            console.log(`[RTC] Created 100ms Room for Request ${callRequestId}: ${roomData.id}`);
            res.json(meta);
          } else {
            console.error('[RTC] 100ms Room creation failed, using mock:', roomData);
            fallbackMockRoom();
          }
        } catch (e) {
          console.error('[RTC] JSON parsing failed:', e);
          fallbackMockRoom();
        }
      });
    });

    request.on('error', (e) => {
      console.error('[RTC] Request failed, using mock:', e);
      fallbackMockRoom();
    });

    request.write(postData);
    request.end();

    function fallbackMockRoom() {
      const mockRoomId = 'mock_room_fallback_' + uuidv4();
      const meta = {
        id: uuidv4(),
        callRequestId,
        hmsRoomId: mockRoomId,
        hmsRoleMember: 'member',
        hmsRoleTrainer: 'trainer'
      };
      roomMetas.push(meta);
      res.json(meta);
    }

  } catch (err) {
    console.error('[RTC] Internal error creating room, using mock:', err);
    const mockRoomId = 'mock_room_fallback_' + uuidv4();
    const meta = {
      id: uuidv4(),
      callRequestId,
      hmsRoomId: mockRoomId,
      hmsRoleMember: 'member',
      hmsRoleTrainer: 'trainer'
    };
    roomMetas.push(meta);
    res.json(meta);
  }
});

// Simulated Room Signalling Store
let simulatedRooms = {};

app.post('/api/rooms/:roomId/signal', (req, res) => {
  const { roomId } = req.params;
  const { role, state } = req.body;

  if (!simulatedRooms[roomId]) {
    simulatedRooms[roomId] = {
      member: { isJoined: false, isAudioOn: true, isVideoOn: true, isCameraFlipped: false },
      trainer: { isJoined: false, isAudioOn: true, isVideoOn: true, isCameraFlipped: false }
    };
  }

  if (role === 'member' || role === 'trainer') {
    simulatedRooms[roomId][role] = { ...simulatedRooms[roomId][role], ...state };
    console.log(`[RTC] Simulated Signalling [${roomId}] for ${role}:`, state);
  }

  res.json(simulatedRooms[roomId]);
});

app.get('/api/rooms/:roomId/signal', (req, res) => {
  const { roomId } = req.params;
  const state = simulatedRooms[roomId] || {
    member: { isJoined: false, isAudioOn: true, isVideoOn: true, isCameraFlipped: false },
    trainer: { isJoined: false, isAudioOn: true, isVideoOn: true, isCameraFlipped: false }
  };
  res.json(state);
});

// Sync data endpoint
app.get('/api/sync', (req, res) => {
  const since = req.query.since ? parseInt(req.query.since, 10) : 0;
  
  const newMessages = messages.filter(m => {
    const msgTime = m.updatedAt ? new Date(m.updatedAt).getTime() : new Date(m.createdAt).getTime();
    return msgTime > since;
  });
  const newRequests = callRequests.filter(r => {
    const reqTime = r.updatedAt ? new Date(r.updatedAt).getTime() : new Date(r.requestedAt).getTime();
    return reqTime > since;
  });
  const newLogs = sessionLogs.filter(s => {
    const logTime = s.updatedAt ? new Date(s.updatedAt).getTime() : new Date(s.endedAt).getTime();
    return logTime > since;
  });
  
  res.json({
    timestamp: Date.now(),
    messages: newMessages,
    callRequests: newRequests,
    sessionLogs: newLogs,
    roomMetas: roomMetas
  });
});

// Chat Message Post (and updates)
app.post('/api/chat', (req, res) => {
  const msg = req.body;
  if (!msg.id || !msg.senderId || !msg.text) {
    return res.status(400).json({ error: 'id, senderId, and text are required' });
  }

  // Check if it already exists (for read receipt / status update)
  const existingIdx = messages.findIndex(m => m.id === msg.id);
  if (existingIdx !== -1) {
    messages[existingIdx] = { ...messages[existingIdx], ...msg, updatedAt: new Date().toISOString() };
    console.log(`[CHAT] Updated message status: ${msg.id} -> ${msg.status}`);
    return res.json(messages[existingIdx]);
  }

  const newMsg = {
    id: msg.id,
    chatId: msg.chatId || 'default_chat',
    senderId: msg.senderId,
    receiverId: msg.receiverId,
    text: msg.text,
    createdAt: msg.createdAt || new Date().toISOString(),
    status: msg.status === 'sending' ? 'sent' : (msg.status || 'sent'),
    updatedAt: new Date().toISOString()
  };

  messages.push(newMsg);
  console.log(`[CHAT] New Message from ${msg.senderId}: "${msg.text.substring(0, 20)}..."`);
  
  // Simulate typing indicator trigger if it is not a system message
  if (msg.senderId !== 'system') {
    simulateTypingDelay(newMsg);
  }

  res.json(newMsg);
});

// Typing indicator storage (mock)
let activeTyping = {};
app.get('/api/typing', (req, res) => {
  res.json(activeTyping);
});

app.post('/api/typing', (req, res) => {
  const { userId, isTyping } = req.body;
  if (userId) {
    activeTyping[userId] = isTyping;
  }
  res.json(activeTyping);
});

function simulateTypingDelay(msg) {
  const recipient = msg.receiverId;
  const sender = msg.senderId;
  
  // Set recipient starts typing to simulate reply behavior after 800ms
  // Wait 1.5s then post a simulated response sometimes, or just toggle typing indicator
  activeTyping[recipient] = true;
  
  setTimeout(() => {
    activeTyping[recipient] = false;
  }, 1500);
}

// Call requests Post
app.post('/api/calls', (req, res) => {
  const reqData = req.body;
  if (!reqData.id || !reqData.memberId || !reqData.trainerId) {
    return res.status(400).json({ error: 'id, memberId, and trainerId are required' });
  }

  const existingIdx = callRequests.findIndex(r => r.id === reqData.id);
  if (existingIdx !== -1) {
    callRequests[existingIdx] = { 
      ...callRequests[existingIdx], 
      ...reqData, 
      updatedAt: new Date().toISOString() 
    };
    console.log(`[SCHEDULE] Updated Call Request: ${reqData.id} -> ${reqData.status}`);
    
    // If request approved, push system message
    if (reqData.status === 'approved') {
      const scheduledTime = new Date(callRequests[existingIdx].scheduledFor);
      const timeStr = scheduledTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      const systemMsg = {
        id: 'sys_' + uuidv4(),
        chatId: 'default_chat',
        senderId: 'system',
        receiverId: 'all',
        text: `Call approved for ${timeStr}.`,
        createdAt: new Date().toISOString(),
        status: 'read',
        updatedAt: new Date().toISOString()
      };
      messages.push(systemMsg);
      console.log(`[CHAT] System Message: Call approved for ${timeStr}`);
    } else if (reqData.status === 'declined') {
      const reason = reqData.declineReason || 'No reason specified';
      const systemMsg = {
        id: 'sys_' + uuidv4(),
        chatId: 'default_chat',
        senderId: 'system',
        receiverId: 'all',
        text: `Call request declined. Reason: ${reason}`,
        createdAt: new Date().toISOString(),
        status: 'read',
        updatedAt: new Date().toISOString()
      };
      messages.push(systemMsg);
      console.log(`[CHAT] System Message: Call request declined: ${reason}`);
    }

    return res.json(callRequests[existingIdx]);
  }

  const newRequest = {
    id: reqData.id,
    memberId: reqData.memberId,
    trainerId: reqData.trainerId,
    requestedAt: reqData.requestedAt || new Date().toISOString(),
    scheduledFor: reqData.scheduledFor,
    note: reqData.note || '',
    status: reqData.status || 'pending',
    declineReason: reqData.declineReason,
    updatedAt: new Date().toISOString()
  };

  callRequests.push(newRequest);
  console.log(`[SCHEDULE] New Call Request from Member ${reqData.memberId} for ${reqData.scheduledFor}`);
  res.json(newRequest);
});

// Session Logs Post
app.post('/api/sessions', (req, res) => {
  const logData = req.body;
  if (!logData.id || !logData.memberId || !logData.trainerId) {
    return res.status(400).json({ error: 'id, memberId, and trainerId are required' });
  }

  const existingIdx = sessionLogs.findIndex(s => s.id === logData.id);
  if (existingIdx !== -1) {
    sessionLogs[existingIdx] = { ...sessionLogs[existingIdx], ...logData, updatedAt: new Date().toISOString() };
    console.log(`[SCHEDULE] Updated Session Log ${logData.id}`);
    return res.json(sessionLogs[existingIdx]);
  }

  const newLog = {
    id: logData.id,
    memberId: logData.memberId,
    trainerId: logData.trainerId,
    startedAt: logData.startedAt || new Date().toISOString(),
    endedAt: logData.endedAt || new Date().toISOString(),
    durationSec: logData.durationSec || 0,
    rating: logData.rating,
    trainerNotes: logData.trainerNotes,
    memberNotes: logData.memberNotes,
    updatedAt: new Date().toISOString()
  };

  sessionLogs.push(newLog);
  console.log(`[SCHEDULE] Created Session Log: duration ${newLog.durationSec}s`);
  res.json(newLog);
});

// Diagnostics panel stats
app.get('/api/debug', (req, res) => {
  res.json({
    env: {
      HMS_ACCESS_KEY: process.env.HMS_ACCESS_KEY ? 'MASKED' : 'NOT_SET',
      HMS_APP_SECRET: process.env.HMS_APP_SECRET ? 'MASKED' : 'NOT_SET',
      HMS_TEMPLATE_ID: process.env.HMS_TEMPLATE_ID || 'NOT_SET'
    },
    counts: {
      messages: messages.length,
      callRequests: callRequests.length,
      sessionLogs: sessionLogs.length,
      rooms: roomMetas.length
    }
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[AUTH] Local Sync and Token Server listening on port ${PORT}`);
});
