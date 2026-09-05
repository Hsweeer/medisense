const express = require('express');
const admin = require('firebase-admin');

const app = express();
app.use(express.json({ limit: '1mb' }));

const serviceAccount = (() => {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;

  if (projectId && clientEmail && privateKey) {
    return {
      project_id: projectId,
      client_email: clientEmail,
      private_key: privateKey.replace(/\\n/g, '\n'),
    };
  }

  return null;
})();

if (serviceAccount) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
} else {
  admin.initializeApp();
}

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

function getExpectedCronSecret() {
  return process.env.CRON_SECRET || process.env.TOKEN_CLEANUP_SECRET || null;
}

async function verifyFirebaseToken(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const match = authHeader.match(/^Bearer\s+(.+)$/i);

  if (!match) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Missing or invalid Authorization header.' });
  }

  try {
    const token = match[1];
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    return next();
  } catch (error) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Invalid Firebase ID token.' });
  }
}

async function sendFcmToUser(recipientUid, payload) {
  const devicesSnap = await db.collection('users').doc(recipientUid).collection('devices').get();
  const tokens = devicesSnap.docs
    .map((doc) => doc.data().token)
    .filter(Boolean);

  if (!tokens.length) {
    return { success: false, reason: 'no_tokens' };
  }

  try {
    const result = await admin.messaging().sendEachForMulticast({ ...payload, tokens });
    return { success: true, results: result };
  } catch (error) {
    console.error('FCM send error', { error, recipientUid });
    return { success: false, error };
  }
}

async function createNotificationDoc(recipientUid, payload) {
  const docRef = await db.collection('users').doc(recipientUid).collection('notifications').add({
    recipientUserId: recipientUid,
    senderUserId: payload.senderUserId ?? null,
    type: payload.type ?? 'generic',
    title: payload.title ?? '',
    body: payload.body ?? '',
    meta: payload.meta ?? {},
    relatedEntityId: payload.relatedEntityId ?? null,
    relatedEntityType: payload.relatedEntityType ?? null,
    route: payload.route ?? {},
    createdAt: fieldValue.serverTimestamp(),
    isRead: false,
    status: payload.status ?? 'pending',
  });

  return docRef.id;
}

function normalizePhone(phone) {
  return String(phone || '').trim().replace(/[^\d+]/g, '');
}

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'medisense-notification-server' });
});

app.post('/send-sos-alert', verifyFirebaseToken, async (req, res) => {
  const userId = req.user.uid;
  const { sosSessionId, trackingToken, userName, contacts = [] } = req.body || {};

  if (!sosSessionId || !trackingToken) {
    return res.status(400).json({ error: 'invalid-argument', message: 'SOS session ID and tracking token are required.' });
  }

  const safeUserName = String(userName || 'MediSense user').trim() || 'MediSense user';
  const normalizedContacts = [];

  for (const contact of Array.isArray(contacts) ? contacts : []) {
    const phone = normalizePhone(contact?.phone);
    if (!phone) continue;
    normalizedContacts.push({ name: contact?.name || 'Emergency contact', phone });
  }

  if (!normalizedContacts.length) {
    await db.collection('sos_sessions').doc(sosSessionId).update({
      contactNotificationStatus: 'failed',
      contactsDeliverySummary: 'No valid MediSense contacts were provided.',
      updatedAt: fieldValue.serverTimestamp(),
    }).catch(() => {});

    return res.status(200).json({ status: 'failed', sentCount: 0, totalCount: 0, message: 'No valid MediSense contacts were provided.' });
  }

  let sentCount = 0;
  const statusByContact = [];

  for (const contact of normalizedContacts) {
    const usersSnap = await db.collection('users').where('phone', '==', contact.phone).limit(1).get();
    if (usersSnap.empty) {
      statusByContact.push({ name: contact.name, phone: contact.phone, status: 'not_registered' });
      continue;
    }

    const recipientUid = usersSnap.docs[0].id;
    const notificationPayload = {
      senderUserId: userId,
      type: 'sos_alert',
      title: 'SOS Alert',
      body: `${safeUserName} has triggered an SOS alert. Open the app to view live tracking.`,
      meta: { sosSessionId, trackingToken },
      relatedEntityId: sosSessionId,
      relatedEntityType: 'sos_session',
      route: { name: 'sos', params: { sosSessionId } },
    };

    try {
      await createNotificationDoc(recipientUid, notificationPayload);
      const fcmPayload = {
        notification: { title: notificationPayload.title, body: notificationPayload.body },
        data: {
          type: 'sos_alert',
          sosSessionId,
          trackingToken,
          senderUserId: userId,
        },
      };

      const res = await sendFcmToUser(recipientUid, fcmPayload);
      if (res.success) {
        sentCount += 1;
        statusByContact.push({ name: contact.name, phone: contact.phone, status: 'sent' });
      } else {
        statusByContact.push({ name: contact.name, phone: contact.phone, status: 'failed' });
      }
    } catch (error) {
      console.error('Failed to notify contact', { error, contact });
      statusByContact.push({ name: contact.name, phone: contact.phone, status: 'failed' });
    }
  }

  const overallStatus = sentCount > 0 ? 'sent' : 'failed';

  await db.collection('sos_sessions').doc(sosSessionId).update({
    contactNotificationStatus: overallStatus,
    contactsNotifiedAt: sentCount > 0 ? fieldValue.serverTimestamp() : null,
    contactsDeliverySummary: sentCount > 0 ? `Emergency alerts sent to ${sentCount} of ${normalizedContacts.length} contact(s).` : 'Emergency alerts could not be delivered to any registered contacts.',
    contacts: statusByContact,
    updatedAt: fieldValue.serverTimestamp(),
  }).catch(() => {});

  await db.collection('tracking_sessions').doc(trackingToken).set({
    token: trackingToken,
    sessionId: sosSessionId,
    userId,
    status: 'active',
    accessRestricted: false,
    notificationsSent: sentCount,
    updatedAt: fieldValue.serverTimestamp(),
  }, { merge: true }).catch(() => {});

  return res.json({
    status: overallStatus,
    sentCount,
    totalCount: normalizedContacts.length,
    message: overallStatus === 'sent' ? `Emergency alerts sent to ${sentCount} contact(s).` : 'Emergency alerts could not be delivered.',
  });
});

app.post('/notify-caregiver-request', verifyFirebaseToken, async (req, res) => {
  const { linkId } = req.body || {};
  if (!linkId) {
    return res.status(400).json({ error: 'invalid-argument', message: 'linkId is required.' });
  }

  const linkSnap = await db.collection('caregiver_links').doc(linkId).get();
  if (!linkSnap.exists) {
    return res.status(404).json({ error: 'not-found', message: 'Caregiver link not found.' });
  }

  const link = linkSnap.data() || {};
  const recipientUid = link.recipientUid;
  const senderUid = link.senderUid;
  const senderName = link.senderName || 'Someone';

  if (!recipientUid || !senderUid) {
    return res.status(400).json({ error: 'failed-precondition', message: 'Malformed caregiver link.' });
  }

  const payload = {
    senderUserId: senderUid,
    type: 'caregiver_request',
    title: 'Caregiver Request',
    body: `${senderName} wants to add you as a caregiver.`,
    meta: { linkId },
    relatedEntityId: linkId,
    relatedEntityType: 'caregiver_link',
    route: { name: 'caregiver_request', params: { requestId: linkId } },
  };

  await createNotificationDoc(recipientUid, payload);
  await sendFcmToUser(recipientUid, {
    notification: { title: payload.title, body: payload.body },
    data: { type: 'caregiver_request', requestId: linkId, senderUid },
  });

  return res.json({ status: 'ok' });
});

app.post('/notify-caregiver-response', verifyFirebaseToken, async (req, res) => {
  const { linkId } = req.body || {};
  if (!linkId) {
    return res.status(400).json({ error: 'invalid-argument', message: 'linkId is required.' });
  }

  const linkSnap = await db.collection('caregiver_links').doc(linkId).get();
  if (!linkSnap.exists) {
    return res.status(404).json({ error: 'not-found', message: 'Caregiver link not found.' });
  }

  const before = linkSnap.data() || {};
  const beforeStatus = before.status;
  const afterStatus = beforeStatus;
  const senderUid = before.senderUid;
  const recipientName = before.recipientName || 'User';

  if (!senderUid) {
    return res.status(400).json({ error: 'failed-precondition', message: 'Malformed caregiver link.' });
  }

  if (!beforeStatus) {
    return res.status(200).json({ status: 'skipped', message: 'No status change to notify.' });
  }

  const title = 'Caregiver Request Update';
  const body = `Your caregiver request to ${recipientName} is now ${afterStatus}.`;

  const payload = {
    senderUserId: before.recipientUid ?? null,
    type: `caregiver_request_${afterStatus}`,
    title,
    body,
    meta: { linkId },
    relatedEntityId: linkId,
    relatedEntityType: 'caregiver_link',
    route: { name: 'caregiver_requests', params: {} },
  };

  await createNotificationDoc(senderUid, payload);
  await sendFcmToUser(senderUid, {
    notification: { title, body },
    data: { type: payload.type, requestId: linkId },
  });

  return res.json({ status: 'ok', linkId, newStatus: afterStatus });
});

app.post('/notify-reminder', verifyFirebaseToken, async (req, res) => {
  const { recipientUid, reminderId } = req.body || {};
  if (!recipientUid || !reminderId) {
    return res.status(400).json({ error: 'invalid-argument', message: 'recipientUid and reminderId are required.' });
  }

  const reminderSnap = await db.collection('users').doc(recipientUid).collection('reminders').doc(reminderId).get();
  if (!reminderSnap.exists) {
    return res.status(404).json({ error: 'not-found', message: 'Reminder not found.' });
  }

  const reminder = reminderSnap.data() || {};
  const createdByUid = reminder.createdByUid;
  const title = reminder.title || 'Reminder';
  const dose = reminder.dose || '';
  const time = reminder.time || '';

  if (!createdByUid || createdByUid === recipientUid) {
    return res.json({ status: 'skipped', reason: 'self_created_or_missing_creator' });
  }

  const body = dose.trim().length === 0 ? `${title} at ${time}` : `${title} · ${dose} at ${time}`;
  const payload = {
    senderUserId: createdByUid,
    type: 'reminder_created',
    title: 'New reminder added for you',
    body,
    meta: { reminderId },
    relatedEntityId: reminderId,
    relatedEntityType: 'reminder',
    route: { name: 'reminder', params: { reminderId } },
  };

  await createNotificationDoc(recipientUid, payload);
  await sendFcmToUser(recipientUid, {
    notification: { title: payload.title, body: payload.body },
    data: { type: 'reminder_created', reminderId, senderUid: createdByUid },
  });

  return res.json({ status: 'ok' });
});

app.post('/respond-caregiver-request', verifyFirebaseToken, async (req, res) => {
  const authUid = req.user.uid;
  const { requestId, action } = req.body || {};

  const normalizedAction = action === 'accept' ? 'accept' : action === 'reject' ? 'reject' : null;
  if (!normalizedAction || !requestId) {
    return res.status(400).json({ error: 'invalid-argument', message: 'action and requestId are required.' });
  }

  const linkRef = db.collection('caregiver_links').doc(requestId);
  const snap = await linkRef.get();
  if (!snap.exists) {
    return res.status(404).json({ error: 'not-found', message: 'Caregiver request not found.' });
  }

  const link = snap.data() || {};
  const recipientUid = link.recipientUid;
  const senderUid = link.senderUid;

  if (!recipientUid || !senderUid) {
    return res.status(400).json({ error: 'failed-precondition', message: 'Malformed caregiver link.' });
  }

  if (authUid !== recipientUid) {
    return res.status(403).json({ error: 'permission-denied', message: 'Only the recipient may respond to this request.' });
  }

  const currentStatus = link.status || 'pending';
  if (currentStatus !== 'pending') {
    return res.status(200).json({ status: 'already_answered', currentStatus });
  }

  const newStatus = normalizedAction === 'accept' ? 'accepted' : 'rejected';
  await linkRef.update({ status: newStatus, respondedAt: fieldValue.serverTimestamp() });

  if (newStatus === 'accepted') {
    const relRef = db.collection('caregiver_relationships').doc();
    await relRef.set({ caregiverUid: senderUid, patientUid: recipientUid, createdAt: fieldValue.serverTimestamp() });
  }

  const title = newStatus === 'accepted' ? 'Caregiver Request Accepted' : 'Caregiver Request Rejected';
  const body = newStatus === 'accepted'
    ? `${link.recipientName || 'User'} accepted your caregiver request.`
    : `${link.recipientName || 'User'} rejected your caregiver request.`;

  const payload = {
    senderUserId: recipientUid,
    type: `caregiver_request_${newStatus}`,
    title,
    body,
    meta: { linkId: requestId },
    relatedEntityId: requestId,
    relatedEntityType: 'caregiver_link',
    route: { name: 'caregiver_requests', params: {} },
  };

  await createNotificationDoc(senderUid, payload);
  await sendFcmToUser(senderUid, {
    notification: { title, body },
    data: { type: payload.type, requestId },
  });

  return res.json({ status: 'ok', newStatus });
});

app.post('/update-sos-tracking-status', verifyFirebaseToken, async (req, res) => {
  const { trackingToken, status, accessRestricted } = req.body || {};

  if (!trackingToken) {
    return res.status(400).json({ error: 'invalid-argument', message: 'trackingToken is required.' });
  }

  await db.collection('tracking_sessions').doc(trackingToken).set({
    token: trackingToken,
    status,
    accessRestricted: Boolean(accessRestricted),
    updatedAt: fieldValue.serverTimestamp(),
  }, { merge: true });

  return res.json({ status: 'ok', trackingToken, status, accessRestricted: Boolean(accessRestricted) });
});

app.get('/token-cleanup', async (req, res) => {
  const expectedSecret = getExpectedCronSecret();
  const secret = req.query.secret;

  if (expectedSecret && secret !== expectedSecret) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Invalid cleanup secret.' });
  }

  if (!expectedSecret) {
    return res.status(500).json({ error: 'configuration-error', message: 'CRON_SECRET or TOKEN_CLEANUP_SECRET is not configured.' });
  }

  const usersSnap = await db.collection('users').get();
  let removed = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const devicesSnap = await db.collection('users').doc(uid).collection('devices').get();
    const tokens = devicesSnap.docs.map((doc) => ({ id: doc.id, token: doc.data().token }));

    if (!tokens.length) continue;

    const batchSize = 500;
    for (let i = 0; i < tokens.length; i += batchSize) {
      const chunk = tokens.slice(i, i + batchSize);
      const msgs = chunk.map((item) => ({ token: item.token, data: { ping: '1' } }));

      try {
        const result = await admin.messaging().sendEach(msgs);
        for (let j = 0; j < result.responses.length; j += 1) {
          const response = result.responses[j];
          const err = response.error;
          if (response.success) continue;

          if (err && (err.code === 'messaging/registration-token-not-registered' || err.code === 'messaging/invalid-registration-token')) {
            await db.collection('users').doc(uid).collection('devices').doc(chunk[j].id).delete().catch(() => {});
            removed += 1;
          }
        }
      } catch (error) {
        console.warn('sendEach failed during token cleanup', { error, uid });
      }
    }
  }

  return res.json({ status: 'ok', removed });
});

const port = Number(process.env.PORT) || 3000;
app.listen(port, () => {
  console.log(`MediSense notification server listening on port ${port}`);
});
