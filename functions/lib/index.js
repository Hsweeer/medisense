"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.tokenCleanup = exports.respondCaregiverRequest = exports.onReminderCreate = exports.onCaregiverLinkUpdate = exports.onCaregiverLinkCreate = exports.sendSosAlert = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
admin.initializeApp();
const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;
const sendFcmToUser = async (recipientUid, payload) => {
    const tokensSnap = await db.collection('users').doc(recipientUid).collection('devices').get();
    const tokens = tokensSnap.docs.map(d => d.data().token).filter(Boolean);
    if (tokens.length === 0)
        return { success: false, reason: 'no_tokens' };
    try {
        const res = await admin.messaging().sendEachForMulticast({ ...payload, tokens });
        return { success: true, results: res };
    }
    catch (e) {
        functions.logger.error('FCM send error', { error: e, recipientUid });
        return { success: false, error: e };
    }
};
const createNotificationDoc = async (recipientUid, payload) => {
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
};
exports.sendSosAlert = functions.https.onCall(async (request) => {
    const data = (request.data ?? {});
    const auth = request.auth;
    if (!auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required to send SOS alerts.');
    }
    const userId = auth.uid;
    const sosSessionId = typeof data?.sosSessionId === 'string' ? data.sosSessionId.trim() : '';
    const trackingToken = typeof data?.trackingToken === 'string' ? data.trackingToken.trim() : '';
    const userName = typeof data?.userName === 'string' ? data.userName.trim() : 'MediSense user';
    const rawContacts = data?.contacts;
    if (!sosSessionId || !trackingToken) {
        throw new functions.https.HttpsError('invalid-argument', 'SOS session ID and tracking token are required.');
    }
    // Find registered MediSense users among provided contacts (by phone)
    const contacts = [];
    if (Array.isArray(rawContacts)) {
        for (const c of rawContacts) {
            const phone = (typeof c?.phone === 'string') ? c.phone.trim().replace(/[^0-9+]/g, '') : '';
            if (!phone)
                continue;
            contacts.push({ name: c?.name ?? 'Emergency contact', phone });
        }
    }
    if (contacts.length === 0) {
        await db.collection('sos_sessions').doc(sosSessionId).update({
            contactNotificationStatus: 'failed',
            contactsDeliverySummary: 'No valid MediSense contacts were provided.',
            updatedAt: fieldValue.serverTimestamp(),
        });
        return { status: 'failed', sentCount: 0, totalCount: 0, message: 'No valid MediSense contacts were provided.' };
    }
    let sentCount = 0;
    const statusByContact = [];
    for (const contact of contacts) {
        // Attempt to find a MediSense user with this phone
        const usersSnap = await db.collection('users').where('phone', '==', contact.phone).limit(1).get();
        if (usersSnap.empty) {
            statusByContact.push({ name: contact.name, phone: contact.phone, status: 'not_registered' });
            continue;
        }
        const recipientUid = usersSnap.docs[0].id;
        // Create Firestore notification doc
        const notificationPayload = {
            senderUserId: userId,
            type: 'sos_alert',
            title: 'SOS Alert',
            body: `${userName} has triggered an SOS alert. Open the app to view live tracking.`,
            meta: { sosSessionId, trackingToken },
            relatedEntityId: sosSessionId,
            relatedEntityType: 'sos_session',
            route: { name: 'sos', params: { sosSessionId } },
        };
        try {
            await createNotificationDoc(recipientUid, notificationPayload);
            // Send FCM
            const fcmPayload = {
                notification: { title: notificationPayload.title, body: notificationPayload.body },
                data: {
                    type: 'sos_alert',
                    sosSessionId,
                    trackingToken,
                    senderUserId: userId,
                },
                tokens: [],
            };
            const res = await sendFcmToUser(recipientUid, fcmPayload);
            if (res?.success) {
                sentCount += 1;
                statusByContact.push({ name: contact.name, phone: contact.phone, status: 'sent' });
            }
            else {
                statusByContact.push({ name: contact.name, phone: contact.phone, status: 'failed' });
            }
        }
        catch (e) {
            functions.logger.error('Failed to notify contact', { error: e, contact });
            statusByContact.push({ name: contact.name, phone: contact.phone, status: 'failed' });
        }
    }
    const overallStatus = sentCount > 0 ? 'sent' : 'failed';
    await db.collection('sos_sessions').doc(sosSessionId).update({
        contactNotificationStatus: overallStatus,
        contactsNotifiedAt: sentCount > 0 ? fieldValue.serverTimestamp() : null,
        contactsDeliverySummary: sentCount > 0 ? `Emergency alerts sent to ${sentCount} of ${contacts.length} contact(s).` : 'Emergency alerts could not be delivered to any registered contacts.',
        contacts: statusByContact,
        updatedAt: fieldValue.serverTimestamp(),
    });
    // Also update tracking_sessions as before
    await db.collection('tracking_sessions').doc(trackingToken).set({
        token: trackingToken,
        sessionId: sosSessionId,
        userId,
        status: 'active',
        accessRestricted: false,
        notificationsSent: sentCount,
        updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });
    return { status: overallStatus, sentCount, totalCount: contacts.length, message: overallStatus === 'sent' ? `Emergency alerts sent to ${sentCount} contact(s).` : 'Emergency alerts could not be delivered.' };
});
// Trigger: when a caregiver_links doc is created, notify the recipient
exports.onCaregiverLinkCreate = functions.firestore.document('caregiver_links/{linkId}').onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const recipientUid = data.recipientUid;
    const senderUid = data.senderUid;
    const senderName = data.senderName ?? 'Someone';
    if (!recipientUid || !senderUid)
        return;
    const payload = {
        senderUserId: senderUid,
        type: 'caregiver_request',
        title: 'Caregiver Request',
        body: `${senderName} wants to add you as a caregiver.`,
        meta: { linkId: snap.id },
        relatedEntityId: snap.id,
        relatedEntityType: 'caregiver_link',
        route: { name: 'caregiver_request', params: { requestId: snap.id } },
    };
    await createNotificationDoc(recipientUid, payload);
    await sendFcmToUser(recipientUid, { notification: { title: payload.title, body: payload.body }, data: { type: 'caregiver_request', requestId: snap.id, senderUid }, tokens: [] });
});
// Trigger: when a caregiver_links doc updates (status change), notify the original sender
exports.onCaregiverLinkUpdate = functions.firestore.document('caregiver_links/{linkId}').onUpdate(async (change, ctx) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeStatus = before.status;
    const afterStatus = after.status;
    if (beforeStatus === afterStatus)
        return;
    const linkId = change.after.id;
    const senderUid = after.senderUid;
    const recipientName = after.recipientName ?? 'User';
    if (!senderUid)
        return;
    const title = 'Caregiver Request Update';
    const body = `Your caregiver request to ${recipientName} is now ${afterStatus}.`;
    const payload = {
        senderUserId: after.recipientUid ?? null,
        type: `caregiver_request_${afterStatus}`,
        title,
        body,
        meta: { linkId },
        relatedEntityId: linkId,
        relatedEntityType: 'caregiver_link',
        route: { name: 'caregiver_requests', params: {} },
    };
    await createNotificationDoc(senderUid, payload);
    await sendFcmToUser(senderUid, { notification: { title, body }, data: { type: payload.type, requestId: linkId }, tokens: [] });
});
// Trigger: when a reminder is created in users/{uid}/reminders — send notification to recipient if createdByUid exists and is not the recipient
exports.onReminderCreate = functions.firestore.document('users/{uid}/reminders/{reminderId}').onCreate(async (snap, ctx) => {
    const data = snap.data() || {};
    const recipientUid = ctx.params.uid;
    const createdByUid = data.createdByUid;
    const title = data.title ?? 'Reminder';
    const dose = data.dose ?? '';
    const time = data.time ?? '';
    if (!createdByUid || createdByUid === recipientUid)
        return; // ignore self-created
    const body = dose.trim().length === 0
        ? `${title} at ${time}`
        : `${title} · ${dose} at ${time}`;
    const payload = {
        senderUserId: createdByUid,
        type: 'reminder_created',
        title: 'New reminder added for you',
        body,
        meta: { reminderId: snap.id },
        relatedEntityId: snap.id,
        relatedEntityType: 'reminder',
        route: { name: 'reminder', params: { reminderId: snap.id } },
    };
    await createNotificationDoc(recipientUid, payload);
    await sendFcmToUser(recipientUid, { notification: { title: payload.title, body: payload.body }, data: { type: 'reminder_created', reminderId: snap.id, senderUid: createdByUid }, tokens: [] });
});
// Callable: accept/reject a caregiver request (recipient performs this)
exports.respondCaregiverRequest = functions.https.onCall(async (req) => {
    const data = (req.data ?? {});
    const auth = req.auth;
    if (!auth)
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    const action = data.action === 'accept' ? 'accept' : data.action === 'reject' ? 'reject' : null;
    const requestId = typeof data.requestId === 'string' ? data.requestId : null;
    if (!action || !requestId)
        throw new functions.https.HttpsError('invalid-argument', 'action and requestId are required.');
    const linkRef = db.collection('caregiver_links').doc(requestId);
    const snap = await linkRef.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Caregiver request not found.');
    const link = snap.data() || {};
    const recipientUid = link.recipientUid;
    const senderUid = link.senderUid;
    if (!recipientUid || !senderUid)
        throw new functions.https.HttpsError('failed-precondition', 'Malformed caregiver link.');
    if (auth.uid !== recipientUid)
        throw new functions.https.HttpsError('permission-denied', 'Only the recipient may respond to this request.');
    const currentStatus = link.status ?? 'pending';
    if (currentStatus !== 'pending') {
        return { status: 'already_answered', currentStatus };
    }
    const newStatus = action === 'accept' ? 'accepted' : 'rejected';
    await linkRef.update({ status: newStatus, respondedAt: fieldValue.serverTimestamp() });
    // Update caregiver relationships if accepted
    if (newStatus === 'accepted') {
        // create caregiver relationship doc (idempotent)
        const relRef = db.collection('caregiver_relationships').doc();
        await relRef.set({ caregiverUid: senderUid, patientUid: recipientUid, createdAt: fieldValue.serverTimestamp() });
    }
    // Notify the original sender
    const title = newStatus === 'accepted' ? 'Caregiver Request Accepted' : 'Caregiver Request Rejected';
    const body = newStatus === 'accepted' ? `${link.recipientName ?? 'User'} accepted your caregiver request.` : `${link.recipientName ?? 'User'} rejected your caregiver request.`;
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
    await sendFcmToUser(senderUid, { notification: { title, body }, data: { type: payload.type, requestId }, tokens: [] });
    return { status: 'ok', newStatus };
});
// Scheduled: token cleanup — remove invalid registration tokens
exports.tokenCleanup = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
    functions.logger.info('Starting token cleanup');
    const usersSnap = await db.collection('users').get();
    let removed = 0;
    for (const userDoc of usersSnap.docs) {
        const uid = userDoc.id;
        const devicesSnap = await db.collection('users').doc(uid).collection('devices').get();
        const tokens = devicesSnap.docs.map(d => ({ id: d.id, token: d.data().token }));
        if (tokens.length === 0)
            continue;
        // Send a silent data message to each token in batches to detect invalid tokens
        const batchSize = 500;
        for (let i = 0; i < tokens.length; i += batchSize) {
            const chunk = tokens.slice(i, i + batchSize);
            const msgs = chunk.map(t => ({ token: t.token, data: { ping: '1' } }));
            try {
                const res = await admin.messaging().sendEach(msgs);
                for (let j = 0; j < res.responses.length; j++) {
                    const r = res.responses[j];
                    if (!r.success) {
                        const err = r.error;
                        if (err && (err.code === 'messaging/registration-token-not-registered' || err.code === 'messaging/invalid-registration-token')) {
                            const docId = chunk[j].id;
                            await db.collection('users').doc(uid).collection('devices').doc(docId).delete().catch(() => { });
                            removed += 1;
                        }
                    }
                }
            }
            catch (e) {
                functions.logger.warn('sendEach failed during token cleanup', { error: e, uid });
            }
        }
    }
    functions.logger.info(`Token cleanup complete. Removed ${removed} tokens.`);
    return { removed };
});
//# sourceMappingURL=index.js.map