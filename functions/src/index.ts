import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import twilio, { Twilio } from 'twilio';

admin.initializeApp();

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

// Read Twilio credentials from either environment variables or Firebase runtime config.
const _runtimeConfig = (() => {
  try {
    return functions.config?.() ?? {};
  } catch (_) {
    return {} as any;
  }
})();

const _twilioAccountSid =
  process.env.TWILIO_ACCOUNT_SID ?? (_runtimeConfig.twilio?.account_sid ?? null);
const _twilioAuthToken =
  process.env.TWILIO_AUTH_TOKEN ?? (_runtimeConfig.twilio?.auth_token ?? null);
const _twilioFromNumber =
  process.env.TWILIO_FROM_NUMBER ?? (_runtimeConfig.twilio?.from ?? null);

const twilioClient: Twilio | null =
  _twilioAccountSid && _twilioAuthToken ? twilio(_twilioAccountSid, _twilioAuthToken) : null;

const senderNumber = _twilioFromNumber ?? '';

const normalizePhone = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  const cleaned = trimmed.replace(/[\s()-]/g, '').replace(/\+/g, '');
  if (!/^\d{7,15}$/.test(cleaned)) return null;

  return `+${cleaned}`;
};

const getTrackingUrl = (token: string): string =>
  `https://medisense.app/sos/track?token=${encodeURIComponent(token)}`;

const buildAlertMessage = (userName: string, trackingToken: string): string => {
  const trackingUrl = getTrackingUrl(trackingToken);
  const friendlyName = userName.trim() || 'A MediSense user';
  return `${friendlyName} has activated an SOS emergency. Track their status here: ${trackingUrl}. If you cannot reach them, contact local emergency services immediately.`;
};

const sanitizeContacts = (rawContacts: unknown): Array<{ name: string; phone: string }> => {
  if (!Array.isArray(rawContacts)) return [];

  const contacts: Array<{ name: string; phone: string }> = [];
  for (const rawContact of rawContacts) {
    if (!rawContact || typeof rawContact !== 'object') continue;

    const candidate = rawContact as Record<string, unknown>;
    const phone = normalizePhone(candidate.phone);
    if (!phone) continue;

    contacts.push({
      name: String(candidate.name ?? 'Emergency contact'),
      phone,
    });
  }

  return contacts;
};

export const sendSosAlert = functions.https.onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const auth = request.auth;

  if (!auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required to send SOS alerts.');
  }

  const userId = auth.uid;
  const sosSessionId = typeof data?.sosSessionId === 'string' ? data.sosSessionId.trim() : '';
  const trackingToken = typeof data?.trackingToken === 'string' ? data.trackingToken.trim() : '';
  const userName = typeof data?.userName === 'string' ? data.userName.trim() : 'MediSense user';
  const contacts = sanitizeContacts(data?.contacts);

  if (!sosSessionId || !trackingToken) {
    throw new functions.https.HttpsError('invalid-argument', 'SOS session ID and tracking token are required.');
  }

  if (contacts.length === 0) {
    await db.collection('sos_sessions').doc(sosSessionId).update({
      contactNotificationStatus: 'failed',
      contactsDeliverySummary: 'No valid emergency contact numbers were available.',
      updatedAt: fieldValue.serverTimestamp(),
    });

    return {
      status: 'failed',
      sentCount: 0,
      totalCount: 0,
      message: 'No valid emergency contact numbers were available.',
    };
  }

  const sessionRef = db.collection('sos_sessions').doc(sosSessionId);
  const sessionSnap = await sessionRef.get();

  if (!sessionSnap.exists || sessionSnap.data()?.userId !== userId) {
    throw new functions.https.HttpsError('permission-denied', 'This SOS session does not belong to the signed-in user.');
  }

  if (!twilioClient || !senderNumber) {
    await sessionRef.update({
      contactNotificationStatus: 'failed',
      contactsDeliverySummary: 'SMS backend is not configured. Add Twilio credentials to deploy this feature.',
      updatedAt: fieldValue.serverTimestamp(),
    });

    return {
      status: 'failed',
      sentCount: 0,
      totalCount: contacts.length,
      message: 'SMS backend is not configured. Please configure the Twilio credentials first.',
    };
  }

  let sentCount = 0;
  const statusByContact: Array<{ name: string; phone: string; status: string }> = [];

  for (const contact of contacts) {
    try {
      await twilioClient.messages.create({
        from: senderNumber,
        to: contact.phone,
        body: buildAlertMessage(userName, trackingToken),
      });

      sentCount += 1;
      statusByContact.push({ name: contact.name, phone: contact.phone, status: 'sent' });
    } catch (error) {
      statusByContact.push({ name: contact.name, phone: contact.phone, status: 'failed' });
      functions.logger.error('SOS SMS send failed', { error, contact: contact.phone, sosSessionId });
    }
  }

  const overallStatus = sentCount > 0 ? 'sent' : 'failed';

  await sessionRef.update({
    contactNotificationStatus: overallStatus,
    contactsNotifiedAt: sentCount > 0 ? fieldValue.serverTimestamp() : null,
    contactsDeliverySummary:
      sentCount > 0 ? `Emergency alerts sent to ${sentCount} of ${contacts.length} contact(s).` : 'Emergency alerts could not be delivered.',
    contacts: statusByContact,
    updatedAt: fieldValue.serverTimestamp(),
  });

  await db.collection('tracking_sessions').doc(trackingToken).set(
    {
      token: trackingToken,
      sessionId: sosSessionId,
      userId,
      status: 'active',
      accessRestricted: false,
      notificationsSent: sentCount,
      updatedAt: fieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    status: overallStatus,
    sentCount,
    totalCount: contacts.length,
    message:
      sentCount > 0
        ? `Emergency alerts sent to ${sentCount} contact(s).`
        : 'Emergency alerts could not be delivered.',
  };
});

export const updateSosTrackingStatus = functions.https.onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const auth = request.auth;

  if (!auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required to update SOS tracking.');
  }

  const token = typeof data?.trackingToken === 'string' ? data.trackingToken.trim() : '';
  const status = typeof data?.status === 'string' ? data.status.trim() : '';
  const accessRestricted = Boolean(data?.accessRestricted);

  if (!token || !status) {
    throw new functions.https.HttpsError('invalid-argument', 'Tracking token and status are required.');
  }

  const trackingRef = db.collection('tracking_sessions').doc(token);
  const trackingSnap = await trackingRef.get();

  if (!trackingSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Tracking token was not found.');
  }

  const trackingData = trackingSnap.data() ?? {};
  if (trackingData.userId !== auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'This tracking session is not authorized for the signed-in user.');
  }

  await trackingRef.update({
    status,
    accessRestricted,
    updatedAt: fieldValue.serverTimestamp(),
    endedAt: status === 'resolved' || status === 'cancelled' ? fieldValue.serverTimestamp() : null,
  });

  return {
    status: 'updated',
    trackingToken: token,
    accessRestricted,
  };
});

export const getSosTrackingSession = functions.https.onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const token = typeof data?.token === 'string' ? data.token.trim() : '';
  if (!token) {
    throw new functions.https.HttpsError('invalid-argument', 'Tracking token is required.');
  }

  const trackingSnap = await db.collection('tracking_sessions').doc(token).get();
  if (!trackingSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Tracking session was not found.');
  }

  const trackingData = trackingSnap.data() ?? {};
  if (trackingData.accessRestricted === true) {
    return {
      status: 'restricted',
      message: 'This SOS tracking session is no longer active.',
    };
  }

  return {
    status: trackingData.status ?? 'active',
    sessionId: trackingData.sessionId ?? null,
    lastLocation: trackingData.lastLocation ?? null,
    updatedAt: trackingData.updatedAt ?? null,
    expiresAt: trackingData.expiresAt ?? null,
  };
});
