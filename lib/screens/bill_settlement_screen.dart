import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class BillSettlementScreen extends StatefulWidget {
  final String clubId;
  final String tableId;
  final String sessionId;
  final Map<String, dynamic> bill;

  const BillSettlementScreen({
    Key? key,
    required this.clubId,
    required this.tableId,
    required this.sessionId,
    required this.bill,
  }) : super(key: key);

  @override
  _BillSettlementScreenState createState() => _BillSettlementScreenState();
}

class _BillSettlementScreenState extends State<BillSettlementScreen> {
  List<String> selectedPlayers = [];
  List<Map<String, dynamic>> filteredPlayers = [];
  List<Map<String, dynamic>> allPlayers = [];
  Map<String, String> playerNames = {};
  String splitMode = 'all';
  Map<String, double> playerAmounts = {};
  Map<String, double> playerPercentages = {};
  Map<String, double> originalPlayerAmounts = {};
  Map<String, int> playerCoins = {};
  double customTotal = 0.0;
  TextEditingController rentalAmountController = TextEditingController();
  double coinPrice = 0.0;
  double perMinCost = 0.0;
  Map<String, dynamic>? sessionInfo;
  bool _isLoading = true;
  bool _isSettling = false;
  String billingMode = 'hour';
  bool isPracticeMode = false;
  double? practiceModeDiscountPercentage;

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
    _fetchSessionDetails();
    _fetchTableDetails();
    _loadSessionInfo();
    _fetchPracticeModeDiscount();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    sessionInfo = null;
    rentalAmountController.dispose();
    super.dispose();
  }
  Future<void> _fetchPracticeModeDiscount() async {
    try {
      final clubDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .get();
      if (clubDoc.exists) {
        setState(() {
          practiceModeDiscountPercentage = (clubDoc.data()?['practice_mode_discount_percentage'] as num?)?.toDouble();
        });
      }
    } catch (e) {
      print('Error fetching practice mode discount: $e');
    }
  }
  Future<void> _loadSessionInfo() async {
    try {
      final sessionDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId)
          .get();
      if (sessionDoc.exists) {
        setState(() {
          sessionInfo = sessionDoc.data() as Map<String, dynamic>?;
          final coinsData = sessionDoc['player_coins'] as Map<String, dynamic>? ?? {};
          coinsData.forEach((playerId, coins) {
            playerCoins[playerId] = coins as int;
          });
        });
      }
    } catch (e) {
      print('Error loading session info: $e');
    }
  }

  Future<void> _fetchPlayers() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      for (var doc in playersSnapshot.docs) {
        playerNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown';
      }
      allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      filteredPlayers = List.from(allPlayers);
      setState(() {});
    } catch (e) {
      print('Error loading players: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading players: $e')),
      );
    }
  }

  Future<void> _fetchSessionDetails() async {
    try {
      final sessionDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId)
          .get();
      if (sessionDoc.exists) {
        final data = sessionDoc.data()!;
        selectedPlayers = List<String>.from(data['assigned_player_ids'] ?? []);
        setState(() {
          billingMode = widget.bill['billing_mode'] as String? ?? 'hour';
          // Ensure playerCoins are loaded as integers
          final coinsData = data['player_coins'] as Map<String, dynamic>? ?? {};
          coinsData.forEach((playerId, coins) {
            playerCoins[playerId] = (coins is num ? coins.toInt() : 0);
          });
        });
        _distributeBillAutomatically();
      }
    } catch (e) {
      print('Error fetching session details: $e');
    }
  }

  Future<void> _fetchTableDetails() async {
    try {
      final tableDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .get();
      if (tableDoc.exists) {
        final data = tableDoc.data()!;
        setState(() {
          coinPrice = (data['coin_price'] as num?)?.toDouble() ?? 0.0;
          perMinCost = (data['per_min_cost'] as num?)?.toDouble() ?? 0.0;
        });
        _distributeBillAutomatically();
      }
    } catch (e) {
      print('Error fetching table details: $e');
    }
  }

  double _calculateSubTotal() {
    final durationMinutes = widget.bill['duration_minutes'] as int? ?? 0;
    double billingAmount = 0.0;

    if (billingMode == 'hour') {
      billingAmount = durationMinutes * perMinCost;
    } else if (billingMode == 'coin') {
      final totalCoins = widget.bill['coin_used'] as int? ?? 0;
      billingAmount = totalCoins * coinPrice;
    } else if (billingMode == 'rental' && rentalAmountController.text.isNotEmpty) {
      billingAmount = double.tryParse(rentalAmountController.text) ?? 0.0;
    }

    return billingAmount;
  }

  void _distributeBillAutomatically() {
    final subTotal = _calculateSubTotal();
    if (selectedPlayers.isEmpty) return;

    final playerCoinsData = widget.bill['player_coins'] as Map<String, dynamic>? ?? {};

    setState(() {
      playerAmounts.clear();
      playerPercentages.clear();
      originalPlayerAmounts.clear();
      playerCoins.clear();
      if (billingMode == 'coin') {
        double totalAssignedCoins = 0;
        for (var playerId in selectedPlayers) {
          final coins = playerCoinsData[playerId] as int? ?? 0;
          totalAssignedCoins += coins;
          final amount = coins * coinPrice;
          playerCoins[playerId] = coins;
          playerAmounts[playerId] = amount;
          originalPlayerAmounts[playerId] = amount;
          playerPercentages[playerId] = totalAssignedCoins > 0 ? (coins / totalAssignedCoins * 100) : 0.0;
        }
        customTotal = totalAssignedCoins * coinPrice;
      } else {
        final amountPerPlayer = subTotal / selectedPlayers.length;
        for (var playerId in selectedPlayers) {
          playerAmounts[playerId] = amountPerPlayer;
          originalPlayerAmounts[playerId] = amountPerPlayer;
          playerPercentages[playerId] = 100.0 / selectedPlayers.length;
        }
        customTotal = subTotal;
      }
    });
  }

  void _distributeBill() {
    double subTotal = _calculateSubTotal();
    if (selectedPlayers.isEmpty) return;

    final totalCoins = widget.bill['coin_used'] as int? ?? 0;

    setState(() {
      playerAmounts.clear();
      customTotal = 0.0;

      if (splitMode == 'all') {
        if (billingMode == 'coin') {
          double totalAssignedCoins = 0;
          for (var playerId in selectedPlayers) {
            final coins = playerCoins[playerId] ?? 0;
            totalAssignedCoins += coins;
            double amount = coins * coinPrice;
            // Apply practice mode discount to individual player amount
            if (isPracticeMode && practiceModeDiscountPercentage != null) {
              amount *= (100 - practiceModeDiscountPercentage!) / 100;
            }
            playerAmounts[playerId] = amount;
            playerPercentages[playerId] = totalCoins > 0 ? (coins / totalCoins * 100) : 0.0;
          }
          if (totalAssignedCoins != totalCoins && selectedPlayers.isNotEmpty) {
            final lastPlayerId = selectedPlayers.last;
            final adjustment = totalCoins - (totalAssignedCoins - (playerCoins[lastPlayerId] ?? 0));
            playerCoins[lastPlayerId] = adjustment as int;
            double amount = adjustment * coinPrice;
            // Apply practice mode discount to adjusted amount
            if (isPracticeMode && practiceModeDiscountPercentage != null) {
              amount *= (100 - practiceModeDiscountPercentage!) / 100;
            }
            playerAmounts[lastPlayerId] = amount;
            playerPercentages[lastPlayerId] = totalCoins > 0 ? (adjustment / totalCoins * 100) : 0.0;
          }
          customTotal = playerAmounts.values.fold(0.0, (sum, amount) => sum + amount);
        } else {
          double amountPerPlayer = subTotal / selectedPlayers.length;
          // Apply practice mode discount to individual player amount
          if (isPracticeMode && practiceModeDiscountPercentage != null) {
            amountPerPlayer *= (100 - practiceModeDiscountPercentage!) / 100;
          }
          for (var playerId in selectedPlayers) {
            playerAmounts[playerId] = amountPerPlayer;
            playerPercentages[playerId] = 100.0 / selectedPlayers.length;
          }
          customTotal = playerAmounts.values.fold(0.0, (sum, amount) => sum + amount);
        }
      } else if (splitMode == 'percentage') {
        for (var playerId in selectedPlayers) {
          final percentage = playerPercentages[playerId] ?? 0.0;
          double amount = subTotal * (percentage / 100);
          // Apply practice mode discount to individual player amount
          if (isPracticeMode && practiceModeDiscountPercentage != null) {
            amount *= (100 - practiceModeDiscountPercentage!) / 100;
          }
          playerAmounts[playerId] = amount;
          if (percentage == 100.0) {
            for (var otherId in selectedPlayers) {
              if (otherId != playerId) {
                playerPercentages[otherId] = 0.0;
                playerAmounts[otherId] = 0.0;
              }
            }
          }
        }
        customTotal = playerAmounts.values.fold(0.0, (sum, amount) => sum + amount);
      } else if (splitMode == 'amount') {
        for (var playerId in selectedPlayers) {
          double amount = playerAmounts[playerId] ?? 0.0;
          // Apply practice mode discount to individual player amount
          if (isPracticeMode && practiceModeDiscountPercentage != null) {
            amount *= (100 - practiceModeDiscountPercentage!) / 100;
          }
          playerAmounts[playerId] = amount;
          if (amount == subTotal) {
            for (var otherId in selectedPlayers) {
              if (otherId != playerId) {
                playerAmounts[otherId] = 0.0;
                playerPercentages[otherId] = 0.0;
              }
            }
          }
        }
        customTotal = playerAmounts.values.fold(0.0, (sum, amount) => sum + amount);
      }
    });
  }

  Future<void> _settleBill() async {
    if (_isSettling || selectedPlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one player')),
      );
      return;
    }

    if (isPracticeMode && practiceModeDiscountPercentage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Practice mode discount not set. Please add it from the Edit Profile screen.'),
        ),
      );
      return;
    }

    setState(() {
      _isSettling = true;
    });

    try {
      final subTotal = _calculateSubTotal().round();
      final durationMinutes = widget.bill['duration_minutes'] as int? ?? 0;
      int netTotal = isPracticeMode && practiceModeDiscountPercentage != null
          ? (subTotal * (100 - practiceModeDiscountPercentage!) / 100).round()
          : subTotal;

      if ((splitMode == 'percentage' || splitMode == 'amount') && customTotal.round() != netTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Total must equal the bill: ৳$netTotal')),
        );
        return;
      }

      // Check for existing session in invoices to prevent duplicates
      final existingSessionCheck = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('invoices')
          .where('session_id', isEqualTo: widget.sessionId)
          .limit(1)
          .get();

      if (existingSessionCheck.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This session has already been settled')),
        );
        return;
      }

      final sessionUpdateData = {
        'billing_amount': subTotal,
        'is_settled': true,
        if (billingMode == 'coin') 'player_coins': playerCoins,
        'practice_mode': isPracticeMode,
      };

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId)
          .update(sessionUpdateData);

      final currentTimestamp = Timestamp.now();
      final now = currentTimestamp.toDate();
      final todayStart = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
      final tomorrowStart = Timestamp.fromDate(DateTime(now.year, now.month, now.day + 1));

      Map<String, String> playerInvoiceIds = {};
      Map<String, bool> isNewInvoice = {};
      Map<String, Map<String, dynamic>> expectedServiceDetails = {};

      // Batch for player invoices to reduce round-trips
      final batch = FirebaseFirestore.instance.batch();

      for (var playerId in selectedPlayers) {
        int amount = (playerAmounts[playerId] ?? 0.0).round();
        if (amount <= 0) continue;

        final serviceDetails = {
          'type': billingMode == 'hour'
              ? 'pool_hour'
              : billingMode == 'coin'
              ? 'pool_coin'
              : 'rental',
          'details': {
            'table_id': widget.tableId,
            'minutes': durationMinutes,
            'rate': billingMode == 'hour'
                ? perMinCost
                : billingMode == 'coin'
                ? coinPrice
                : (subTotal / (durationMinutes == 0 ? 1 : durationMinutes)),
            'coins': billingMode == 'coin' ? playerCoins[playerId] : null,
            'start_time': Timestamp.fromMillisecondsSinceEpoch(
                widget.bill['actual_start_epoch'] as int? ?? 0),
            'split_bill': selectedPlayers.length > 1,
            'price': amount,
            'practice_mode': isPracticeMode,
            if (isPracticeMode) 'discount_percentage': practiceModeDiscountPercentage,
            'session_id': widget.sessionId,
          },
        };

        // Use composite index for efficient query
        final invoicesSnapshot = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('invoices')
            .where('player_id', isEqualTo: playerId)
            .where('status', isEqualTo: 'unpaid')
            .where('practice_mode', isEqualTo: isPracticeMode)
            .where('date', isGreaterThanOrEqualTo: todayStart)
            .where('date', isLessThan: tomorrowStart)
            .limit(1)
            .get();

        QueryDocumentSnapshot<Map<String, dynamic>>? existingInvoice;
        if (invoicesSnapshot.docs.isNotEmpty) {
          existingInvoice = invoicesSnapshot.docs.first;
          final services = List<Map<String, dynamic>>.from(existingInvoice['services']);
          if (services.any((service) => service['details']['session_id'] == widget.sessionId)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This session is already included in an invoice')),
            );
            return;
          }
        }

        String invoiceId = '';
        int updatedGrossTotal = amount;
        int updatedNetTotal = amount;

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          if (existingInvoice != null) {
            final existingRef = FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc(existingInvoice.id);

            final existingData = await transaction.get(existingRef);
            if (!existingData.exists) {
              throw Exception('Existing invoice not found during transaction');
            }
            final existingServices = List<Map<String, dynamic>>.from(existingData['services']);
            existingServices.add(serviceDetails);

            updatedGrossTotal = existingServices.fold(0, (sum, service) {
              final details = service['details'] as Map<String, dynamic>;
              return sum + (details['price'] as num? ?? 0).toInt();
            });
            updatedNetTotal = updatedGrossTotal;

            transaction.update(existingRef, {
              'services': existingServices,
              'gross_total': updatedGrossTotal,
              'net_total': updatedNetTotal,
              'total_amount': updatedGrossTotal,
              'date': currentTimestamp,
            });
            invoiceId = existingInvoice.id;
            isNewInvoice[playerId] = false;
          } else {
            final invoiceRef = FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc();
            final invoiceData = {
              'player_id': playerId,
              'player_name': playerNames[playerId] ?? 'Unknown',
              'date': currentTimestamp,
              'status': 'unpaid',
              'gross_total': amount,
              'net_total': amount,
              'total_amount': amount,
              'paid_amount': 0,
              'services': [serviceDetails],
              'practice_mode': isPracticeMode,
              'discount_amount': 0,
              'discount_amounts': {'games': 0, 'food': 0},
              'discount_codes': {'games': null, 'food': null},
              'round_up': 0,
              'session_id': widget.sessionId,
            };
            transaction.set(invoiceRef, invoiceData);
            invoiceId = invoiceRef.id;
            isNewInvoice[playerId] = true;
          }
        });

        // Prepare player invoice data for batch write
        final playerInvoiceData = {
          'club_id': widget.clubId,
          'invoice_id': invoiceId,
          'date': currentTimestamp,
          'gross_total': updatedGrossTotal,
          'net_total': updatedNetTotal,
          'total_amount': updatedGrossTotal,
          'status': 'unpaid',
          'practice_mode': isPracticeMode,
          'discount_amount': 0,
          'discount_amounts': {'games': 0, 'food': 0},
          'discount_codes': {'games': null, 'food': null},
          'round_up': 0,
        };

        batch.set(
          FirebaseFirestore.instance
              .collection('players')
              .doc(playerId)
              .collection('invoices')
              .doc(invoiceId),
          playerInvoiceData,
        );

        // Prepare player club invoice reference for batch write
        final playerClubInvoiceRef = FirebaseFirestore.instance
            .collection('players')
            .doc(playerId)
            .collection('clubs')
            .doc(widget.clubId)
            .collection('invoices')
            .doc(invoiceId);

        if (!(await playerClubInvoiceRef.get()).exists) {
          batch.set(playerClubInvoiceRef, {
            'invoice_id': invoiceId,
            'timestamp': currentTimestamp,
          });
        }

        playerInvoiceIds[playerId] = invoiceId;
        expectedServiceDetails[playerId] = serviceDetails;
      }

      // Commit batch writes for player invoices
      await batch.commit();

      // Poll to ensure all invoices are written
      bool allInvoicesWritten = false;
      for (int attempt = 0; attempt < 15; attempt++) {
        bool allExist = true;
        for (var playerId in selectedPlayers) {
          if (playerAmounts[playerId] == null || playerAmounts[playerId]! <= 0) continue;
          final invoiceId = playerInvoiceIds[playerId]!;
          try {
            final clubInvoiceDoc = await FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc(invoiceId)
                .get();
            if (!clubInvoiceDoc.exists) {
              print('Polling attempt $attempt: Invoice $invoiceId not found for player $playerId');
              allExist = false;
              break;
            }
          } catch (e) {
            print('Error during polling attempt $attempt for player $playerId: $e');
            allExist = false;
            break;
          }
        }
        if (allExist) {
          allInvoicesWritten = true;
          break;
        }
        await Future.delayed(Duration(milliseconds: 300 + (attempt * 100)));
      }

      if (!allInvoicesWritten) {
        print('Warning: Proceeding with verification despite incomplete writes after 15 attempts.');
      }

      // Verification
      bool verificationPassed = true;
      String verificationError = '';

      // Verify session update
      try {
        final updatedSessionDoc = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(widget.tableId)
            .collection('sessions')
            .doc(widget.sessionId)
            .get();
        if (!updatedSessionDoc.exists) {
          verificationError = 'Updated session document not found';
          verificationPassed = false;
        } else {
          final sessionData = updatedSessionDoc.data()!;
          if (sessionData['billing_amount'] != subTotal ||
              sessionData['is_settled'] != true ||
              sessionData['practice_mode'] != isPracticeMode) {
            verificationError = 'Session update verification failed: '
                'billing_amount=${sessionData['billing_amount']} vs $subTotal, '
                'is_settled=${sessionData['is_settled']}, '
                'practice_mode=${sessionData['practice_mode']} vs $isPracticeMode';
            verificationPassed = false;
          }
          if (billingMode == 'coin' && verificationPassed) {
            final savedPlayerCoins = Map<String, dynamic>.from(sessionData['player_coins'] ?? {});
            for (var entry in playerCoins.entries) {
              if (savedPlayerCoins[entry.key] != entry.value) {
                verificationError = 'Player coins mismatch for ${entry.key}: ${savedPlayerCoins[entry.key]} vs ${entry.value}';
                verificationPassed = false;
                break;
              }
            }
          }
        }
      } catch (e) {
        verificationError = 'Error verifying session: $e';
        verificationPassed = false;
      }

      // Verify invoices
      if (verificationPassed) {
        for (var playerId in selectedPlayers) {
          if (playerAmounts[playerId] == null || playerAmounts[playerId]! <= 0) continue;
          final invoiceId = playerInvoiceIds[playerId]!;
          try {
            // Verify club invoice
            final clubInvoiceDoc = await FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc(invoiceId)
                .get();
            if (!clubInvoiceDoc.exists) {
              verificationError = 'Club invoice $invoiceId not found for player $playerId';
              verificationPassed = false;
              break;
            }
            final clubData = clubInvoiceDoc.data()!;
            if (clubData['practice_mode'] != isPracticeMode) {
              verificationError = 'Practice mode mismatch in invoice $invoiceId: ${clubData['practice_mode']} vs $isPracticeMode';
              verificationPassed = false;
              break;
            }
            // Verify service for new invoices
            final savedServices = List<Map<String, dynamic>>.from(clubData['services']);
            final expectedService = expectedServiceDetails[playerId]!;
            bool serviceFound = savedServices.any((service) =>
            service['details']['session_id'] == widget.sessionId);
            if (!serviceFound) {
              verificationError = 'Service for session ${widget.sessionId} not found in invoice $invoiceId';
              verificationPassed = false;
              break;
            }
            if (isNewInvoice[playerId]!) {
              final latestService = savedServices.last;
              if (latestService['type'] != expectedService['type'] ||
                  latestService['details']['table_id'] != expectedService['details']['table_id'] ||
                  latestService['details']['minutes'] != expectedService['details']['minutes'] ||
                  latestService['details']['price'] != expectedService['details']['price'] ||
                  latestService['details']['practice_mode'] != expectedService['details']['practice_mode'] ||
                  latestService['details']['session_id'] != expectedService['details']['session_id']) {
                verificationError = 'Service verification failed for $invoiceId: '
                    'type=${latestService['type']} vs ${expectedService['type']}, '
                    'table_id=${latestService['details']['table_id']} vs ${expectedService['details']['table_id']}, '
                    'minutes=${latestService['details']['minutes']} vs ${expectedService['details']['minutes']}, '
                    'price=${latestService['details']['price']} vs ${expectedService['details']['price']}, '
                    'practice_mode=${latestService['details']['practice_mode']} vs ${expectedService['details']['practice_mode']}, '
                    'session_id=${latestService['details']['session_id']} vs ${expectedService['details']['session_id']}';
                verificationPassed = false;
                break;
              }
            }

            // Verify player invoice
            final playerInvoiceDoc = await FirebaseFirestore.instance
                .collection('players')
                .doc(playerId)
                .collection('invoices')
                .doc(invoiceId)
                .get();
            if (!playerInvoiceDoc.exists) {
              verificationError = 'Player invoice $invoiceId not found for player $playerId';
              verificationPassed = false;
              break;
            }
            final playerData = playerInvoiceDoc.data()!;
            if (playerData['practice_mode'] != isPracticeMode) {
              verificationError = 'Practice mode mismatch in player invoice $invoiceId: ${playerData['practice_mode']} vs $isPracticeMode';
              verificationPassed = false;
              break;
            }

            // Verify player club invoice reference
            final playerClubInvoiceDoc = await FirebaseFirestore.instance
                .collection('players')
                .doc(playerId)
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc(invoiceId)
                .get();
            if (!playerClubInvoiceDoc.exists) {
              verificationError = 'Player club invoice reference $invoiceId not found for player $playerId';
              verificationPassed = false;
              break;
            }
            if (playerClubInvoiceDoc['invoice_id'] != invoiceId) {
              verificationError = 'Invoice ID mismatch in player club reference: ${playerClubInvoiceDoc['invoice_id']} vs $invoiceId';
              verificationPassed = false;
              break;
            }
          } catch (e) {
            verificationError = 'Error verifying invoice $invoiceId for player $playerId: $e';
            verificationPassed = false;
            break;
          }
        }
      }

      if (!verificationPassed) {
        print('Verification failed: $verificationError');
        throw Exception('Data verification failed: $verificationError');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill settled successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      print('Error settling bill: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to settle bill: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isSettling = false;
      });
    }
  }

  bool mapEquals(Map<dynamic, dynamic> map1, Map<dynamic, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (var key in map1.keys) {
      if (!map2.containsKey(key)) return false;
      final val1 = map1[key];
      final val2 = map2[key];
      if (val1 is Map && val2 is Map) {
        if (!mapEquals(val1, val2)) return false;
      } else if (val1 is Timestamp && val2 is Timestamp) {
        if (val1.millisecondsSinceEpoch != val2.millisecondsSinceEpoch) return false;
      } else if (val1 != val2) {
        return false;
      }
    }
    return true;
  }

  void _showSessionInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        if (sessionInfo == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final startEpoch = sessionInfo!['actual_start_epoch'] as int? ?? 0;
        final endEpoch = sessionInfo!['end_epoch'] as int? ?? 0;
        final pausedDurationMs = sessionInfo!['paused_duration_ms'] as int? ?? 0;
        final durationMinutes = widget.bill['duration_minutes'] as int? ?? 0;
        final playerCoins = sessionInfo!['player_coins'] as Map<String, dynamic>? ?? {};

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Session Info',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Table ID: ${widget.tableId}'),
              Text('Session ID: ${widget.sessionId}'),
              Text('Start Time: ${DateTime.fromMillisecondsSinceEpoch(startEpoch)}'),
              if (endEpoch > 0) Text('End Time: ${DateTime.fromMillisecondsSinceEpoch(endEpoch)}'),
              Text('Duration: $durationMinutes minutes'),
              Text('Billing Mode: $billingMode'),
              if (billingMode == 'coin')
                ...selectedPlayers.map((playerId) {
                  final coins = playerCoins[playerId] as int? ?? 0;
                  return Text('${playerNames[playerId] ?? 'Unknown'}: $coins coins');
                }),
              Text('Paused Duration: ${Duration(milliseconds: pausedDurationMs)}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRentalAmountBottomSheet() {
    final TextEditingController controller = TextEditingController();
    final FocusNode focusNode = FocusNode();
    controller.text = rentalAmountController.text.isNotEmpty ? rentalAmountController.text : '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter Rental Amount (৳)', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter amount',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final newAmount = double.tryParse(controller.text) ?? 0.0;
                    if (newAmount >= 0) {
                      setState(() {
                        rentalAmountController.text = newAmount.toString();
                        _distributeBill();
                      });
                      Navigator.pop(context);
                    }
                    focusNode.dispose();
                  },
                  child: const Text('Apply'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) => focusNode.dispose());
  }

  void _showPercentageBottomSheet(String playerId) {
    final TextEditingController controller = TextEditingController();
    final FocusNode focusNode = FocusNode();
    controller.text = playerPercentages[playerId] != null && playerPercentages[playerId]! > 0
        ? playerPercentages[playerId]!.toString()
        : '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter Percentage (%)', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter percentage',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        playerPercentages[playerId] = 33.3;
                        _distributeBill();
                      });
                      Navigator.pop(context);
                      focusNode.dispose();
                    },
                    child: const Text('33.3%'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        playerPercentages[playerId] = 50.0;
                        _distributeBill();
                      });
                      Navigator.pop(context);
                      focusNode.dispose();
                    },
                    child: const Text('50%'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        playerPercentages[playerId] = 100.0;
                        _distributeBill();
                      });
                      Navigator.pop(context);
                      focusNode.dispose();
                    },
                    child: const Text('100%'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final newPercentage = double.tryParse(controller.text) ?? 0.0;
                    if (newPercentage >= 0) {
                      setState(() {
                        playerPercentages[playerId] = newPercentage;
                        if (newPercentage == 100.0) {
                          for (var otherId in selectedPlayers) {
                            if (otherId != playerId) {
                              playerPercentages[otherId] = 0.0;
                              playerAmounts[otherId] = 0.0;
                            }
                          }
                        }
                        _distributeBill();
                      });
                      Navigator.pop(context);
                    }
                    focusNode.dispose();
                  },
                  child: const Text('Apply'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) => focusNode.dispose());
  }

  void _showAmountBottomSheet(String playerId) {
    final TextEditingController controller = TextEditingController();
    final FocusNode focusNode = FocusNode();
    controller.text = playerAmounts[playerId] != null && playerAmounts[playerId]! > 0
        ? playerAmounts[playerId]!.toString()
        : '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter Amount (৳)', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter amount',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final newAmount = double.tryParse(controller.text) ?? 0.0;
                    if (newAmount >= 0) {
                      setState(() {
                        playerAmounts[playerId] = newAmount;
                        final subTotal = _calculateSubTotal();
                        if (newAmount == subTotal) {
                          for (var otherId in selectedPlayers) {
                            if (otherId != playerId) {
                              playerAmounts[otherId] = 0.0;
                              playerPercentages[otherId] = 0.0;
                            }
                          }
                        }
                        customTotal = playerAmounts.values.fold(0.0, (sum, amount) => sum + amount);
                      });
                      Navigator.pop(context);
                    }
                    focusNode.dispose();
                  },
                  child: const Text('Apply'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) => focusNode.dispose());
  }

  Future<void> _showAddCoinsBottomSheet() async {
    if (selectedPlayers.isEmpty || billingMode != 'coin' || splitMode != 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No players selected or invalid mode')),
      );
      return;
    }

    final tempPlayerCoins = Map<String, int>.from(playerCoins);
    bool isSaveLoading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final totalAssignedCoins = tempPlayerCoins.values.fold<int>(0, (sum, coins) => sum + coins);
            final totalCoins = widget.bill['coin_used'] as int? ?? 0;

            return FractionallySizedBox(
              heightFactor: 0.6,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Assign Coins to Players',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: selectedPlayers.length,
                      itemBuilder: (context, index) {
                        final playerId = selectedPlayers[index];
                        final coinCount = tempPlayerCoins[playerId] ?? 0;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(playerNames[playerId] ?? 'Unknown'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: coinCount <= 0
                                      ? null
                                      : () {
                                    setSheetState(() {
                                      tempPlayerCoins[playerId] = coinCount - 1;
                                    });
                                  },
                                  color: Colors.red,
                                ),
                                Text(
                                  '$coinCount',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    setSheetState(() {
                                      tempPlayerCoins[playerId] = coinCount + 1;
                                    });
                                  },
                                  color: Colors.green,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          'Total Assigned: $totalAssignedCoins / $totalCoins',
                          style: TextStyle(
                            fontSize: 16,
                            color: totalAssignedCoins == totalCoins ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSaveLoading || totalAssignedCoins != totalCoins
                                ? null
                                : () async {
                              setSheetState(() {
                                isSaveLoading = true;
                              });
                              setState(() {
                                playerCoins = Map<String, int>.from(tempPlayerCoins);
                                _distributeBill();
                              });
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Coins assigned successfully')),
                              );
                              setSheetState(() {
                                isSaveLoading = false;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: totalAssignedCoins == totalCoins ? Colors.green : Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: isSaveLoading
                                ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                                : const Text(
                              'Save',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final durationMinutes = widget.bill['duration_minutes'] as int? ?? 0;
    double subTotal = _calculateSubTotal();
    // Apply practice mode discount to subTotal for display
    if (isPracticeMode && practiceModeDiscountPercentage != null) {
      subTotal *= (100 - practiceModeDiscountPercentage!) / 100;
    }
    final totalCoins = widget.bill['coin_used'] as int? ?? 0;

    return Scaffold(
        appBar: AppBar(
          title: const Text('Settle Bill'),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _showSessionInfo,
            ),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Players',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Search Player (IGN/Name/Phone)',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SearchPlayersScreen(
                            clubId: widget.clubId,
                            selectedPlayers: selectedPlayers,
                            onSelect: (newSelectedPlayers) {
                              setState(() {
                                selectedPlayers = newSelectedPlayers;
                                _distributeBill();
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: selectedPlayers.map((playerId) {
                        final player = allPlayers.firstWhere((p) => p['id'] == playerId);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedPlayers.remove(playerId);
                              playerAmounts.remove(playerId);
                              playerPercentages.remove(playerId);
                              playerCoins.remove(playerId);
                              _distributeBill();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 28,
                                    backgroundImage: player['image_url'] != null
                                        ? NetworkImage(player['image_url'])
                                        : null,
                                    child: player['image_url'] == null
                                        ? const Icon(Icons.person, size: 28)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (player['ign'] ?? player['name'] ?? 'Unknown').length > 8
                                      ? '${(player['ign'] ?? player['name'] ?? 'Unknown').substring(0, 8)}...'
                                      : player['ign'] ?? player['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      billingMode == 'coin' ? Icons.monetization_on : Icons.access_time,
                                      color: billingMode == 'coin' ? Colors.amber : Colors.blue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      billingMode == 'coin' ? 'Coins Used' : 'Duration',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  billingMode == 'coin'
                                      ? '${widget.bill['coin_used'] ?? 0} coins'
                                      : '$durationMinutes min',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.attach_money,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Amount',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (billingMode == 'rental') ...[
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _showRentalAmountBottomSheet,
                                        child: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: billingMode == 'rental' ? _showRentalAmountBottomSheet : null,
                                  child: Text(
                                    billingMode == 'rental' && subTotal == 0.0
                                        ? 'Tap to set'
                                        : '৳${subTotal.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: billingMode == 'rental' && subTotal == 0.0
                                          ? Colors.blue
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Practice Mode',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: isPracticeMode,
                        onChanged: practiceModeDiscountPercentage == null
                            ? null
                            : (value) {
                          setState(() {
                            isPracticeMode = value;
                            _distributeBill();
                          });
                        },
                        activeColor: Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              splitMode = 'all';
                              _distributeBill();
                            });
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: splitMode == 'all' ? Colors.blue : Colors.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'All',
                                style: TextStyle(
                                  color: splitMode == 'all' ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              splitMode = 'percentage';
                              for (var playerId in selectedPlayers) {
                                playerPercentages[playerId] = 0.0;
                                playerAmounts[playerId] = 0.0;
                              }
                              customTotal = 0.0;
                              _distributeBill();
                            });
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: splitMode == 'percentage' ? Colors.blue : Colors.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Percentage',
                                style: TextStyle(
                                  color: splitMode == 'percentage' ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              splitMode = 'amount';
                              for (var playerId in selectedPlayers) {
                                playerAmounts[playerId] = 0.0;
                                playerPercentages[playerId] = 0.0;
                              }
                              customTotal = 0.0;
                              _distributeBill();
                            });
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: splitMode == 'amount' ? Colors.blue : Colors.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Amount',
                                style: TextStyle(
                                  color: splitMode == 'amount' ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (selectedPlayers.isNotEmpty && billingMode == 'coin' && splitMode == 'all') ...[
                    const Text(
                      'Click any player to edit coins',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (selectedPlayers.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: selectedPlayers.map((playerId) {
                        final player = allPlayers.firstWhere((p) => p['id'] == playerId);
                        double amount = playerAmounts[playerId] ?? 0.0;
                        final percentage = splitMode == 'percentage' && subTotal > 0
                            ? (amount / subTotal * 100).toStringAsFixed(1)
                            : (playerPercentages[playerId] ?? 0.0).toStringAsFixed(1);
                        final coins = billingMode == 'coin' ? (playerCoins[playerId] ?? 0) : 0;
                        return GestureDetector(
                          onTap: billingMode == 'coin' && splitMode == 'all' ? () => _showAddCoinsBottomSheet() : null,
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundImage: player['image_url'] != null
                                        ? NetworkImage(player['image_url'])
                                        : null,
                                    child: player['image_url'] == null
                                        ? const Icon(Icons.person, size: 30)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playerNames[playerId] ?? 'Unknown',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                        if (billingMode == 'coin' && splitMode == 'all')
                                          Text(
                                            'Total Coins: $coins',
                                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                                          )
                                        else
                                          Text(
                                            splitMode == 'amount'
                                                ? 'Percentage: ${subTotal > 0 ? (amount / subTotal * 100).toStringAsFixed(1) : "0.0"}%'
                                                : 'Percentage: $percentage%',
                                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (billingMode == 'coin' && splitMode == 'all')
                                    Text(
                                      'Value: ৳${amount.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                                    )
                                  else if (splitMode == 'amount')
                                    ElevatedButton(
                                      onPressed: () => _showAmountBottomSheet(playerId),
                                      child: Text('Set: ৳${amount.toStringAsFixed(0)}'),
                                    )
                                  else if (splitMode == 'percentage')
                                      ElevatedButton(
                                        onPressed: () => _showPercentageBottomSheet(playerId),
                                        child: const Text('Set %'),
                                      )
                                    else
                                      Text(
                                        '৳${amount.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  if (splitMode != 'all')
                    Text(
                      'Total Assigned: ৳${customTotal.toStringAsFixed(0)} / ৳${subTotal.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: customTotal == subTotal ? Colors.green : Colors.red,
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSettling ? null : _settleBill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isSettling
                          ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                          : const Text(
                        'Settle Bill',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              Shimmer(
                color: Colors.grey[300]!,
                child: Container(
                  color: Colors.grey[200],
                ),
              ),
          ],
        ));
  }
}




class SearchPlayersScreen extends StatefulWidget {
  final String clubId;
  final List<String> selectedPlayers;
  final Function(List<String>) onSelect;

  const SearchPlayersScreen({
    Key? key,
    required this.clubId,
    required this.selectedPlayers,
    required this.onSelect,
  }) : super(key: key);

  @override
  _SearchPlayersScreenState createState() => _SearchPlayersScreenState();
}

class _SearchPlayersScreenState extends State<SearchPlayersScreen> {
  List<Map<String, dynamic>> filteredPlayers = [];
  List<Map<String, dynamic>> allPlayers = [];
  List<String> tempSelectedPlayers = [];
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    tempSelectedPlayers = List.from(widget.selectedPlayers);
    _fetchPlayers();
  }

  Future<void> _fetchPlayers() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      setState(() {
        allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        filteredPlayers = allPlayers;
      });
    } catch (e) {
      print('Error loading players: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading players: $e')),
      );
    }
  }

  void _filterPlayers(String query) {
    final filtered = allPlayers.where((player) {
      final nameMatch = player['name']?.toLowerCase().contains(query.toLowerCase()) ?? false;
      final phoneMatch = player['phone_number']?.toLowerCase().contains(query.toLowerCase()) ?? false;
      final ignMatch = player['ign']?.toLowerCase().contains(query.toLowerCase()) ?? false;
      return nameMatch || phoneMatch || ignMatch;
    }).toList();
    setState(() {
      filteredPlayers = filtered;
    });
  }

  String _formatPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.length < 10) {
      return 'No number';
    }
    // Take first 7 digits and append ***
    return '${phoneNumber.substring(0, phoneNumber.length > 12 ? 12 : phoneNumber.length)}***';
  }

  @override
  Widget build(BuildContext context) {
    final sortedPlayers = [
      ...filteredPlayers.where((player) => tempSelectedPlayers.contains(player['id'])),
      ...filteredPlayers.where((player) => !tempSelectedPlayers.contains(player['id'])),
    ];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search Player (IGN/Name/Phone)',
            border: InputBorder.none,
          ),
          onChanged: (value) => _filterPlayers(value),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              widget.onSelect(tempSelectedPlayers);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: sortedPlayers.isEmpty
          ? const Center(child: Text('No players found'))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedPlayers.length,
        itemBuilder: (context, index) {
          final player = sortedPlayers[index];
          final isSelected = tempSelectedPlayers.contains(player['id']);
          return ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundImage: player['image_url'] != null
                  ? NetworkImage(player['image_url'])
                  : null,
              child: player['image_url'] == null
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            title: Text(
              player['name'] ?? 'Unknown',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              _formatPhoneNumber(player['phone_number']),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    tempSelectedPlayers.add(player['id']);
                  } else {
                    tempSelectedPlayers.remove(player['id']);
                  }
                });
              },
            ),
            onTap: () {
              setState(() {
                if (isSelected) {
                  tempSelectedPlayers.remove(player['id']);
                } else {
                  tempSelectedPlayers.add(player['id']);
                }
              });
            },
          );
        },
      ),
    );
  }
}