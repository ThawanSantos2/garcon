const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { setGlobalOptions } = require('firebase-functions/v2');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// Configurações globais recomendadas para v2
setGlobalOptions({
  region: 'us-central1',     // região com quota alta quota
  maxInstances: 10,          // 10 é mais que suficiente para seu app
  memory: '256MiB',
  timeoutSeconds: 120,
  cpu: 1,
});

// ================================================================
// 1. ENVIAR NOTIFICAÇÃO QUANDO NOVO PEDIDO É CRIADO
// ================================================================

exports.notifyWaitersOnNewOrder = onDocumentCreated('orders/{orderId}', async (event) => {
  const snap = event.data;
  const order = snap.data();
  
  try {
    const waitersSnapshot = await db
      .collection('establishments')
      .doc(order.establishmentId)
      .collection('waiters')
      .get();

    const tokens = [];
    for (const waiterDoc of waitersSnapshot.docs) {
      const waiterData = await db.collection('users').doc(waiterDoc.id).get();
      if (waiterData.data()?.fcmToken) {
        tokens.push(waiterData.data().fcmToken);
      }
    }

    if (tokens.length === 0) {
      console.log('Nenhum garçom disponível');
      return;
    }

    const message = {
      notification: {
        title: 'Novo Pedido!',
        body: `Mesa ${order.tableId}: ${order.items.length} itens`,
      },
      data: {
        orderId: order.id || snap.id,
        tableId: order.tableId,
        type: 'new_order',
      },
      webpush: {
        fcmOptions: {
          link: 'https://garcon.app/orders',
        },
      },
      tokens,
    };

    const response = await messaging.sendMulticast(message);
    console.log(`Notificações enviadas: ${response.successCount}`);

  } catch (error) {
    console.error('Erro ao enviar notificações:', error);
  }
});

// ================================================================
// 2. ATUALIZAR ESTATÍSTICAS QUANDO PEDIDO FINALIZA
// ================================================================

exports.updateStatsOnOrderCompletion = onDocumentUpdated('orders/{orderId}', async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.status !== 'completed' && afterData.status === 'completed') {
    try {
      const createdAt = afterData.createdAt.toDate();
      const completedAt = afterData.completedAt.toDate();
      const serviceTime = (completedAt - createdAt) / 1000;

      const establishmentRef = db.collection('establishments').doc(afterData.establishmentId);

      await establishmentRef.update({
        'stats.totalOrders': admin.firestore.FieldValue.increment(1),
        'stats.totalRevenue': admin.firestore.FieldValue.increment(afterData.totalAmount || 0),
      });

      if (afterData.assignedWaiter) {
        const waiterRef = establishmentRef.collection('waiters').doc(afterData.assignedWaiter);
        await waiterRef.update({
          totalOrders: admin.firestore.FieldValue.increment(1),
          avgResponseTime: admin.firestore.FieldValue.increment(serviceTime),
        });
      }

      console.log(`Estatísticas atualizadas. Tempo: ${serviceTime}s`);

    } catch (error) {
      console.error('Erro ao atualizar estatísticas:', error);
    }
  }
});

// ================================================================
// 3. VERIFICAR ASSINATURA EXPIRADA (DIÁRIO)
// ================================================================

exports.checkExpiredSubscriptions = onSchedule({
  schedule: '0 0 * * *',
  timeZone: 'America/Sao_Paulo',
  region: 'us-central1',
}, async () => {
  try {
    const now = new Date();

    const expiredSnapshot = await db
      .collection('establishments')
      .where('subscriptionStatus', '==', 'active')
      .where('subscriptionEndDate', '<', now)
      .get();

    const batch = db.batch();

    for (const doc of expiredSnapshot.docs) {
      const data = doc.data();
      batch.update(doc.ref, {
        subscriptionStatus: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const ownerData = await db.collection('users').doc(data.ownerId).get();
      if (ownerData.data()?.fcmToken) {
        await messaging.send({
          notification: {
            title: 'Assinatura Expirada',
            body: 'Sua assinatura do Garçon expirou. Renove para continuar.',
          },
          data: {
            type: 'subscription_expired',
            establishmentId: doc.id,
          },
          token: ownerData.data().fcmToken,
        });
      }
    }

    await batch.commit();
    console.log(`${expiredSnapshot.size} assinaturas expiradas e canceladas`);

  } catch (error) {
    console.error('Erro ao verificar assinaturas:', error);
  }
});

// ================================================================
// 4. NOTIFICAR QUANDO GARÇOM RECEBE ALERTA DE CLIENTE
// ================================================================

exports.notifyOnWaiterAlert = onDocumentCreated('waiter_alerts/{alertId}', async (event) => {
  const snap = event.data;
  const alert = snap.data();

  try {
    const waitersSnapshot = await db
      .collection('establishments')
      .doc(alert.establishmentId)
      .collection('waiters')
      .where('isActive', '==', true)
      .get();

    const tokens = [];
    for (const waiterDoc of waitersSnapshot.docs) {
      const waiterData = await db.collection('users').doc(waiterDoc.id).get();
      if (waiterData.data()?.fcmToken) {
        tokens.push(waiterData.data().fcmToken);
      }
    }

    if (tokens.length === 0) {
      console.log('Nenhum garçom ativo');
      return;
    }

    const reasonText = {
      call_waiter: 'Cliente chamou o garçom',
      help_needed: 'Cliente precisa de ajuda',
      payment: 'Cliente quer pagar',
      complaint: 'Reclamação do cliente',
    };

    const message = {
      notification: {
        title: 'Alerta do Cliente',
        body: `Mesa ${alert.tableId}: ${reasonText[alert.reason] || alert.reason}`,
      },
      data: {
        alertId: snap.id,
        tableId: alert.tableId,
        type: 'waiter_alert',
      },
      tokens,
    };

    const response = await messaging.sendMulticast(message);
    console.log(`Alertas enviados: ${response.successCount}`);

  } catch (error) {
    console.error('Erro ao enviar alerta:', error);
  }
});

// ================================================================
// 5. WEBHOOK DE PAGAMENTO
// ================================================================

exports.handlePaymentWebhook = onRequest({
  region: 'us-central1',
  cors: true,
}, async (req, res) => {
  try {
    const { type, transactionId, userId, establishmentId, amount } = req.body;

    if (type === 'subscription.payment.received') {
      await db.collection('payments').add({
        userId,
        establishmentId,
        amount,
        transactionId,
        type: 'subscription',
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection('establishments').doc(establishmentId).update({
        subscriptionStatus: 'active',
        subscriptionEndDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      });

      const userData = await db.collection('users').doc(userId).get();
      if (userData.data()?.fcmToken) {
        await messaging.send({
          notification: {
            title: 'Pagamento Confirmado',
            body: 'Sua assinatura foi renovada com sucesso!',
          },
          token: userData.data().fcmToken,
        });
      }

      res.status(200).json({ success: true });
    } else {
      res.status(400).json({ error: 'Tipo de evento não suportado' });
    }
  } catch (error) {
    console.error('Erro no webhook:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================================================================
// 6. LIMPEZA DE DADOS ANTIGOS (SEMANAL)
// ================================================================

exports.cleanupOldData = onSchedule({
  schedule: '0 2 * * 0',
  timeZone: 'America/Sao_Paulo',
  region: 'us-central1',
}, async () => {
  try {
    console.log('Executando limpeza semanal de dados antigos...');
    // Adicione aqui regras de limpeza se quiser no futuro
    console.log('Limpeza concluída (sem ações por enquanto)');
  } catch (error) {
    console.error('Erro na limpeza:', error);
  }
});

// ================================================================
// 7. CRIAR DOCUMENTO DE ESTATÍSTICAS AO CRIAR ESTABELECIMENTO
// ================================================================

exports.createEstablishmentStatsDocument = onDocumentCreated('establishments/{establishmentId}', async (event) => {
  const establishmentId = event.params.establishmentId;

  try {
    await db
      .collection('establishments')
      .doc(establishmentId)
      .collection('statistics')
      .doc('monthly')
      .set({
        ordersThisMonth: 0,
        revenueThisMonth: 0,
        avgServiceTime: 0,
        totalCustomers: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log('Documento de estatísticas criado para:', establishmentId);
  } catch (error) {
    console.error('Erro ao criar estatísticas:', error);
  }
});