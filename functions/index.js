const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { setGlobalOptions } = require('firebase-functions/v2');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ================================================================
// CONFIGURAÇÕES GLOBAIS
// ================================================================
setGlobalOptions({
  region: 'us-central1',
  maxInstances: 10,
  memory: '256MiB',
  timeoutSeconds: 120,
  cpu: 1,
});

// ================================================================
// 1. NOTIFICAR GARÇONS QUANDO NOVO PEDIDO É CRIADO
// ================================================================
exports.notifyWaitersOnNewOrder = onDocumentCreated('orders/{orderId}', async (event) => {
  const snap = event.data;
  const order = snap.data();

  try {
    // Buscar todos os garçons do estabelecimento
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
      console.log('Nenhum garçom com FCM token disponível');
      return;
    }

    // Notificar todos os garçons
    const message = {
      notification: {
        title: '📦 Novo Pedido!',
        body: `Mesa ${order.tableId}: ${order.items?.length || 1} itens`,
      },
      data: {
        orderId: snap.id,
        tableId: order.tableId,
        tableName: establishment,
        establishmentId: order.establishmentId,
        type: 'new_order',
      },
      tokens,
    };

    const response = await messaging.sendMulticast(message);
    console.log(`✅ Notificações enviadas para garçons: ${response.successCount}/${tokens.length}`);

  } catch (error) {
    console.error('❌ Erro ao notificar garçons:', error);
  }
});

// ================================================================
// 2. NOTIFICAR CLIENTE QUANDO STATUS DO PEDIDO MUDA
// ================================================================
exports.notifyCustomerOrderStatus = onDocumentUpdated('orders/{orderId}', async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  // Só notificar se status mudou
  if (beforeData.status === afterData.status) return;

  try {
    const customerId = afterData.customerId;

    // Buscar token FCM do cliente
    const customerDoc = await db.collection('users').doc(customerId).get();
    const fcmToken = customerDoc.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`Cliente ${customerId} sem token FCM`);
      return;
    }

    const statusMessages = {
      'pending': '⏳ Pedido recebido',
      'accepting': '✅ Pedido aprovado',
      'preparing': '👨‍🍳 Preparando seu pedido',
      'ready': '🎉 Seu pedido está pronto!',
      'on_the_way': '🚴 Seu pedido está a caminho',
      'delivered': '✨ Pedido entregue',
      'rejected': '❌ Pedido recusado',
    };

    const message = statusMessages[afterData.status] || 'Status atualizado';

    await messaging.send({
      token: fcmToken,
      notification: {
        title: 'Seu Pedido',
        body: message,
      },
      data: {
        orderId: event.params.orderId,
        status: afterData.status,
        type: 'order_status_update',
      },
    });

    console.log(`✅ Notificação enviada ao cliente: ${message}`);

  } catch (error) {
    console.error('❌ Erro ao notificar cliente:', error);
  }
});

// ================================================================
// NOTIFICAR GARÇONS QUANDO CLIENTE CANCELA PEDIDO
// ================================================================
exports.notifyWaitersOnOrderCancelled = onDocumentUpdated('orders/{orderId}', async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  // Só prosseguir se status mudou para 'cancelled'
  if (beforeData.status !== 'cancelled' && afterData.status === 'cancelled') {
    try {
      const establishmentId = afterData.establishmentId;
      const tableId = afterData.tableId;
      const assignedWaiter = beforeData.assignedWaiter;  // Usar before para pegar o assigned antes do cancel

      // Buscar garçons
      const waitersSnapshot = await db
        .collection('establishments')
        .doc(establishmentId)
        .collection('waiters')
        .get();

      const tokens = [];
      for (const waiterDoc of waitersSnapshot.docs) {
        const waiterData = await db.collection('users').doc(waiterDoc.id).get();
        const fcmToken = waiterData.data()?.fcmToken;

        if (fcmToken) {
          // Se 'pending' (sem assigned), notificar todos
          // Se 'accepting' (com assigned), notificar apenas ele
          if (!assignedWaiter || waiterDoc.id === assignedWaiter) {
            tokens.push(fcmToken);
          }
        }
      }

      if (tokens.length === 0) return;

      const message = {
        notification: {
          title: '❌ Pedido Cancelado',
          body: `O cliente cancelou o pedido da Mesa ${tableId}`,
        },
        data: {
          orderId: event.params.orderId,
          tableId: tableId,
          type: 'order_cancelled',
        },
        tokens,
      };

      const response = await messaging.sendMulticast(message);
      console.log(`✅ Notificações de cancelamento enviadas: ${response.successCount}/${tokens.length}`);
    } catch (error) {
      console.error('❌ Erro ao notificar cancelamento:', error);
    }
  }
});

// ================================================================
// 3. ATUALIZAR ESTATÍSTICAS QUANDO PEDIDO FINALIZA
// ================================================================
exports.updateStatsOnOrderCompletion = onDocumentUpdated('orders/{orderId}', async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.status !== 'completed' && afterData.status === 'completed') {
    try {
      const createdAt = afterData.createdAt.toDate();
      const completedAt = afterData.completedAt?.toDate() || new Date();
      const serviceTime = (completedAt - createdAt) / 1000;

      const establishmentRef = db.collection('establishments').doc(afterData.establishmentId);

      // Atualizar stats do estabelecimento
      await establishmentRef.update({
        'stats.totalOrders': admin.firestore.FieldValue.increment(1),
        'stats.totalRevenue': admin.firestore.FieldValue.increment(afterData.totalPrice || 0),
      });

      // Atualizar stats do garçom (se houver um atribuído)
      if (afterData.assignedWaiter) {
        const waiterRef = establishmentRef.collection('waiters').doc(afterData.assignedWaiter);
        await waiterRef.update({
          totalOrders: admin.firestore.FieldValue.increment(1),
          avgResponseTime: admin.firestore.FieldValue.increment(serviceTime),
        });
      }

      console.log(`✅ Estatísticas atualizadas. Tempo de serviço: ${serviceTime}s`);

    } catch (error) {
      console.error('❌ Erro ao atualizar estatísticas:', error);
    }
  }
});

// ================================================================
// 4. VERIFICAR ASSINATURA EXPIRADA (DIÁRIO)
// ================================================================
exports.checkExpiredSubscriptions = onSchedule({
  schedule: '0 0 * * *',
  timeZone: 'America/Sao_Paulo',
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

      // Notificar dono que assinatura expirou
      const ownerData = await db.collection('users').doc(data.ownerId).get();
      if (ownerData.data()?.fcmToken) {
        await messaging.send({
          notification: {
            title: '⚠️ Assinatura Expirada',
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
    console.log(`✅ ${expiredSnapshot.size} assinaturas expiradas verificadas`);

  } catch (error) {
    console.error('❌ Erro ao verificar assinaturas:', error);
  }
});

// ================================================================
// 5. NOTIFICAR QUANDO CLIENTE FAZ ALERTA PARA GARÇOM
// ================================================================
exports.notifyOnWaiterAlert = onDocumentCreated(`waiter_alerts/{alertId}`, async (event) => {
  const snap = event.data;
  const alert = snap.data();

  console.log('\n========== ALERTA DO CLIENTE ==========');
  console.log('ID do alerta:', snap.id);
  console.log('Estabelecimento:', alert.establishmentId);
  console.log('Mesa:', alert.tableId);
  console.log('Razão:', alert.reason);

  try {
    // 1. Buscar garçons do estabelecimento
    console.log('1️⃣ Buscando garçons...');
    const waitersSnapshot = await db
      .collection('establishments')
      .doc(alert.establishmentId)
      .collection('waiters')
      .get();

    console.log(`   Garçons encontrados: ${waitersSnapshot.docs.length}`);

    // 2. Coletar tokens FCM
    console.log('2️⃣ Coletando tokens FCM...');
    const tokens = [];
    const waitersList = [];

    for (const waiterDoc of waitersSnapshot.docs) {
      const waiterData = await db.collection('users').doc(waiterDoc.id).get();
      
      if (!waiterData.exists) {
        console.log(`   ⚠️ Garçom ${waiterDoc.id} não encontrado em /users`);
        continue;
      }

      const userData = waiterData.data();
      const fcmToken = userData?.fcmToken;

      if (fcmToken) {
        tokens.push(fcmToken);
        waitersList.push({
          id: waiterDoc.id,
          name: userData?.name || 'N/A',
          token: fcmToken.substring(0, 20) + '...'
        });
        console.log(`   ✅ ${userData?.name || waiterDoc.id}: Token OK`);
      } else {
        console.log(`   ❌ ${userData?.name || waiterDoc.id}: SEM TOKEN FCM!`);
      }
    }

    if (tokens.length === 0) {
      console.error('❌ ERRO: Nenhum garçom com token FCM disponível!');
      console.error('   Ação necessária:');
      console.error('   1. Verificar se garçons abriram o app');
      console.error('   2. Verificar se têm permissão de notificação');
      console.error('   3. Verificar se fcmToken foi salvo em /users/{id}');
      
      await db.collection('waiter_alerts').doc(snap.id).update({
        status: 'failed',
        failureReason: 'No waiter tokens available',
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
        affectedWaiters: waitersList
      });
      return;
    }

    console.log(`   Total de tokens: ${tokens.length}`);

    // 3. Montar mensagem
    console.log('3️⃣ Montando mensagem FCM...');
    const reasonTexts = {
      'callwaiter': 'Cliente chamou o garçom',
      'helpneeded': 'Cliente precisa de ajuda',
      'payment': 'Cliente quer pagar',
      'complaint': 'Reclamação do cliente'
    };

    const message = {
      notification: {
        title: '⚠️ ALERTA DO CLIENTE',
        body: `Mesa ${alert.tableId}: ${reasonTexts[alert.reason] || alert.reason}`
      },
      data: {
        alertId: snap.id,
        tableId: alert.tableId,
        customerId: alert.customerId,
        establishmentId: alert.establishmentId,
        reason: alert.reason,
        type: 'waiter_alert',
        message: alert.message || '',
        createdAt: new Date().toISOString()
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'waiter_alerts'
        }
      },
      apns: {
        headers: {
          'apns-priority': '10'
        },
        payload: {
          aps: {
            sound: 'default',
            'content-available': 1,
            'mutable-content': 1
          }
        }
      }
    };

    // 4. Enviar FCM
    console.log('4️⃣ Enviando FCM para garçons...');
    const response = await messaging.sendMulticast({
      ...message,
      tokens: tokens
    });

    console.log(`✅ Resposta do FCM:`);
    console.log(`   Sucesso: ${response.successCount}/${tokens.length}`);
    console.log(`   Falhas: ${response.failureCount}`);

    // 5. Logs de falhas
    if (response.failures.length > 0) {
      console.log('❌ Tokens que falharam:');
      response.failures.forEach((failure, index) => {
        console.log(`   ${index + 1}. Erro: ${failure.error.code}`);
        console.log(`      Mensagem: ${failure.error.message}`);
      });
    }

    // 6. Atualizar status em waiter_alerts
    console.log('5️⃣ Atualizando status do alerta...');
    await db.collection('waiter_alerts').doc(snap.id).update({
      status: 'sent',
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      fcmSent: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
      affectedWaiters: waitersList
    });

    console.log('✅ ALERTA ENVIADO COM SUCESSO!');
    console.log('==========================================\n');

  } catch (error) {
    console.error('❌ ERRO CRÍTICO ao enviar alerta:');
    console.error('   Código:', error.code);
    console.error('   Mensagem:', error.message);
    console.error('   Stack:', error.stack);

    // Registrar erro no Firestore
    try {
      await db.collection('waiter_alerts').doc(snap.id).update({
        status: 'error',
        error: {
          code: error.code,
          message: error.message,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        },
        errorAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (updateError) {
      console.error('Não foi possível registrar erro:', updateError.message);
    }
  }
});

// ================================================================
// 6. WEBHOOK DE PAGAMENTO (STRIPE/MERCADO PAGO)
// ================================================================
exports.handlePaymentWebhook = onRequest({
  region: 'us-central1',
  cors: true,
}, async (req, res) => {
  try {
    const { type, transactionId, userId, establishmentId, amount } = req.body;

    if (type === 'subscription.payment.received') {
      // Salvar pagamento
      await db.collection('payments').add({
        userId,
        establishmentId,
        amount,
        transactionId,
        type: 'subscription',
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Atualizar status do estabelecimento
      await db.collection('establishments').doc(establishmentId).update({
        subscriptionStatus: 'active',
        subscriptionEndDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notificar dono
      const userData = await db.collection('users').doc(userId).get();
      if (userData.data()?.fcmToken) {
        await messaging.send({
          notification: {
            title: '✅ Pagamento Confirmado',
            body: 'Sua assinatura foi renovada com sucesso!',
          },
          token: userData.data().fcmToken,
        });
      }

      console.log(`✅ Pagamento processado: ${transactionId}`);
      res.status(200).json({ success: true });
    } else {
      res.status(400).json({ error: 'Tipo de evento não suportado' });
    }
  } catch (error) {
    console.error('❌ Erro no webhook:', error);
    res.status(500).json({ error: error.message });
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

    console.log(`✅ Documento de estatísticas criado: ${establishmentId}`);
  } catch (error) {
    console.error('❌ Erro ao criar estatísticas:', error);
  }
});

// ================================================================
// 8. LIMPEZA DE DADOS ANTIGOS (SEMANAL)
// ================================================================
exports.cleanupOldData = onSchedule({
  schedule: '0 2 * * 0',
  timeZone: 'America/Sao_Paulo',
}, async () => {
  try {
    console.log('🧹 Executando limpeza semanal de dados antigos...');
    // Implementar limpeza conforme necessário (ex: deletar pedidos antigos)
    console.log('✅ Limpeza concluída');
  } catch (error) {
    console.error('❌ Erro na limpeza:', error);
  }
});
