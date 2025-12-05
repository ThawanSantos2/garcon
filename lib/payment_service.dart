// payment_service.dart
// ignore_for_file: unused_import

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

// CORREÇÃO: Removidas as importações erradas/antigas
// import 'package:in_app_purchase_android/billing_client_wrappers.dart';
// import 'package:in_app_purchase_android/in_app_purchase_android.dart'; // <- NÃO TEM .instance mais!
// import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
// import 'package:in_app_purchase_storekit/store_kit_wrappers.dart.dart';

class PaymentService {
  static const String _subscriptionId = 'garcon_monthly_subscription';
  static const String _subscriptionIdYearly = 'garcon_yearly_subscription';

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  Future<void> initialize() async {
    final bool isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      throw Exception('In-app purchase not available');
    }

    _listenToPurchaseUpdated();

    // CORREÇÃO MODERNA (versões recentes do in_app_purchase)
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Não precisa mais chamar enablePendingPurchases() manualmente
      // O plugin faz isso automaticamente desde a versão 3.0+
      // Mas se quiser garantir, pode deixar assim:
      if (_iap is InAppPurchaseAndroidPlatformAddition) {
        (_iap as InAppPurchaseAndroidPlatformAddition);
      }
    }

    // Para iOS (StoreKit 2), não precisa de nada extra
  }

  void _listenToPurchaseUpdated() {
    _subscription = _iap.purchaseStream.listen(
      (purchaseDetailsList) {
        _handlePurchaseUpdates(purchaseDetailsList);
      },
      onError: (error) {
        debugPrint('Purchase stream error: $error');
      },
    );
  }

  Future<List<ProductDetails>> getSubscriptionProducts() async {
    final Set<String> ids = {_subscriptionId, _subscriptionIdYearly};
    final ProductDetailsResponse response = await _iap.queryProductDetails(ids);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Produtos não encontrados no store: ${response.notFoundIDs}');
    }

    return response.productDetails;
  }

  Future<void> buySubscription({
    required String productId,
    required String establishmentId,
  }) async {
    try {
      final ProductDetails productDetails = await _getProductDetails(productId);

      final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

      // Assinaturas são Non-Consumable (auto-renewable)
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('Erro ao iniciar compra: $e');
      rethrow;
    }
  }

  Future<ProductDetails> _getProductDetails(String productId) async {
    final products = await getSubscriptionProducts();
    return products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Produto não encontrado: $productId'),
    );
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _handlePending(purchase);
          break;
        case PurchaseStatus.error:
          debugPrint('Erro na compra: ${purchase.error}');
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchase);
          break;
        case PurchaseStatus.canceled:
          debugPrint('Compra cancelada pelo usuário');
          break;
      }

      // Finaliza a compra (obrigatória para todas as plataformas
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  void _handlePending(PurchaseDetails purchase) {
    debugPrint('Compra pendente: ${purchase.purchaseID}');
  }

  void _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    debugPrint('Compra bem-sucedida! ID: ${purchase.purchaseID}');

    // Aqui você envia o receipt para seu backend validar
    // Ex: await FirebaseService().recordSubscriptionPayment(...)

    // Importante: sempre chamar completePurchase após verificar
    if (purchase.pendingCompletePurchase) {
      _iap.completePurchase(purchase);
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Erro ao restaurar compras: $e');
      rethrow;
    }
  }

  void dispose() {
    _subscription.cancel();
  }
}

/*
CONFIGURAÇÃO NO GOOGLE PLAY CONSOLE:
1. Vá para "Monetizar" > "Produtos"
2. Crie um produto de assinatura:
   - ID do produto: garcon_monthly_subscription
   - Preço: R$ 10,99
   - Período de faturamento: Mensal
   
   - ID do produto: garcon_yearly_subscription
   - Preço: R$ 100,00
   - Período de faturamento: Anual

CONFIGURAÇÃO NO APP STORE CONNECT:
1. Vá para "Recursos" > "In-App Purchases"
2. Crie um produto de assinatura:
   - Type: Auto-Renewable Subscription
   - Reference Name: Garçon Monthly
   - Product ID: garcon_monthly_subscription
   - Billing Period: Monthly
   - Price: $2.99 USD
   
   - Reference Name: Garçon Yearly
   - Product ID: garcon_yearly_subscription
   - Billing Period: Yearly
   - Price: $29.99 USD

3. Configure a taxa de cancelamento e período de avaliação
*/
