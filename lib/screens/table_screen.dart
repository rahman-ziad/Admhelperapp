  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:flutter/material.dart';
  import 'dart:async';
  import 'package:uuid/uuid.dart';
  import 'package:shimmer_animation/shimmer_animation.dart';
  import 'package:loading_animation_widget/loading_animation_widget.dart';
  import 'bill_settlement_screen.dart';
  
  class TableScreen extends StatefulWidget {
    final String clubId;
  
    const TableScreen({super.key, required this.clubId});
  
    @override
    _TableScreenState createState() => _TableScreenState();
  }
  
  class _TableScreenState extends State<TableScreen> {
    List<Map<String, dynamic>> _tables = [];
    late StreamSubscription _timerSubscription;
    Map<String, int> _activeSessionStartEpochs = {};
    bool _isLoading = false;
    bool _isTimerActive = true;
    Map<String, bool> _isButtonLoading = {};
  
    @override
    void initState() {
      super.initState();
      _loadTables();
      _startTimer();
    }
  
    void _startTimer() {
      _timerSubscription = Stream.periodic(const Duration(seconds: 1), (i) {
        if (mounted && _isTimerActive) setState(() {});
      }).listen((_) {});
    }
  
    @override
    void dispose() {
      _timerSubscription.cancel();
      super.dispose();
    }

    Future<void> _loadTables() async {
      setState(() {
        _isLoading = true;
      });

      try {
        final tablesRef = FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables');
        final snapshot = await tablesRef.get();

        _tables.clear();
        _activeSessionStartEpochs.clear();

        for (var doc in snapshot.docs) {
          final docId = doc.id;
          final order = int.tryParse(docId.replaceFirst('table_', '')) ?? 0;
          final data = doc.data();
          final table = {
            'id': docId,
            'name': data['name'] as String? ?? 'Table $order',
            'type': data['type'] as String? ?? 'Pool',
            'is_active': data['is_active'] as bool? ?? false,
            'per_min_cost': (data['per_min_cost'] as num?)?.toDouble() ?? 5.0,
            'coin_price': (data['coin_price'] as num?)?.toDouble() ?? 10.0,
            'current_session_id': data['current_session_id'] as String?,
            'order': order,
            'is_paused': false,
            'paused_duration_ms': 0,
            'unsettled_bills_count': 0,
          };

          _tables.add(table);

          if (table['is_active'] == true && table['current_session_id'] != null) {
            final sessionDoc = await FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('tables')
                .doc(docId)
                .collection('sessions')
                .doc(table['current_session_id'] as String)
                .get();
            if (sessionDoc.exists) {
              final startEpoch = sessionDoc.data()?['actual_start_epoch'] as int?;
              if (startEpoch != null) {
                _activeSessionStartEpochs[docId] = startEpoch;
                table['billing_mode'] = sessionDoc['billing_mode'] as String?;
                table['is_paused'] = sessionDoc['is_paused'] as bool? ?? false;
                table['paused_duration_ms'] = sessionDoc['paused_duration_ms'] as int? ?? 0;
                table['last_pause_start_epoch'] = sessionDoc['last_pause_start_epoch'] as int?;
                table['is_billing_info_added'] = sessionDoc['is_billing_info_added'] as bool? ?? false;
              }
            }
          }

          // Count unsettled bills, excluding the current session
          final unsettledBillsSnapshot = await FirebaseFirestore.instance
              .collection('clubs')
              .doc(widget.clubId)
              .collection('tables')
              .doc(docId)
              .collection('sessions')
              .where('is_settled', isEqualTo: false)
              .get();
          final currentSessionId = table['current_session_id'] as String?;
          table['unsettled_bills_count'] = unsettledBillsSnapshot.docs
              .where((doc) => doc.id != currentSessionId)
              .length;

        }

        _tables.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
      } catch (e) {
        print('Error loading tables: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  
    Future<void> _togglePause(String tableId, String sessionId, bool isPaused) async {
      setState(() {
        _isButtonLoading[tableId] = true;
      });
  
      final sessionRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(tableId)
          .collection('sessions')
          .doc(sessionId);
  
      try {
        final sessionDoc = await sessionRef.get();
        if (!sessionDoc.exists) throw Exception('Session not found');
  
        final currentEpoch = DateTime.now().millisecondsSinceEpoch;
        final pausedDurationMs = sessionDoc['paused_duration_ms'] as int? ?? 0;
        final lastPauseStartEpoch = sessionDoc['last_pause_start_epoch'] as int?;
  
        if (isPaused) {
          if (lastPauseStartEpoch != null) {
            final pauseDuration = currentEpoch - lastPauseStartEpoch;
            await sessionRef.update({
              'is_paused': false,
              'paused_duration_ms': pausedDurationMs + pauseDuration,
              'last_pause_start_epoch': null,
            });
          }
        } else {
          await sessionRef.update({
            'is_paused': true,
            'last_pause_start_epoch': currentEpoch,
          });
        }
  
        await _loadTables();
      } finally {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
    }
  
    Future<void> _startSession(String tableId, String mode) async {
      setState(() {
        _isButtonLoading[tableId] = true;
      });
  
      try {
        final tablesRef = FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(tableId);
        final sessionId = const Uuid().v4();
        final sessionRef = tablesRef.collection('sessions').doc(sessionId);
  
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final tableDoc = await transaction.get(tablesRef);
          if (!tableDoc.exists) throw Exception('Table not found');
  
          final startEpoch = DateTime.now().millisecondsSinceEpoch;
          transaction.update(tablesRef, {
            'is_active': true,
            'current_session_id': sessionId,
          });
  
          transaction.set(sessionRef, {
            'billing_mode': mode,
            'actual_start_epoch': startEpoch,
            'end_epoch': null,
            'duration_minutes': null,
            'billing_amount': null,
            'is_settled': false,
            'is_billing_info_added': false,
            'assigned_player_ids': [],
            'coin_used': mode == 'coin' ? 0 : null,
            'notes': null,
            'is_paused': false,
            'paused_duration_ms': 0,
            'last_pause_start_epoch': null,
            'player_coins': mode == 'coin' ? <String, int>{} : null,
          });
        });
  
        await _loadTables();
      } finally {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
    }

    Future<void> _stopSession(String tableId, {bool fromBillingSheet = false}) async {
      setState(() {
        _isButtonLoading[tableId] = true;
      });

      try {
        final tablesRef = FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(tableId);
        final table = _tables.firstWhere((t) => t['id'] == tableId);
        final sessionId = table['current_session_id'] as String;
        final sessionRef = tablesRef.collection('sessions').doc(sessionId);

        final sessionDoc = await sessionRef.get();
        if (!sessionDoc.exists) throw Exception('Session not found');

        final isBillingInfoAdded = sessionDoc['is_billing_info_added'] as bool? ?? false;
        final billingMode = sessionDoc['billing_mode'] as String? ?? 'hour';
        final isPaused = sessionDoc['is_paused'] as bool? ?? false;
        final pausedDurationMs = sessionDoc['paused_duration_ms'] as int? ?? 0;
        final lastPauseStartEpoch = sessionDoc['last_pause_start_epoch'] as int?;

        if (!fromBillingSheet && !isBillingInfoAdded && (billingMode == 'hour' || billingMode == 'rental')) {
          await _showBillingInfoBottomSheet(tableId, sessionId);
          return;
        }

        if (billingMode == 'coin') {
          final playerCoins = sessionDoc['player_coins'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final totalCoins = playerCoins.values.fold<int>(0, (sum, coins) => sum + (coins as int));
          if (totalCoins == 0 && !fromBillingSheet) {
            await _showBillingInfoBottomSheet(tableId, sessionId);
            return;
          }
        }

        int? durationMinutes;
        double? billingAmount;

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final sessionDoc = await transaction.get(sessionRef);
          if (!sessionDoc.exists) throw Exception('Session not found');

          final startEpoch = sessionDoc['actual_start_epoch'] as int?;
          if (startEpoch == null) throw Exception('Start time not found');

          final endEpoch = DateTime.now().millisecondsSinceEpoch;
          int effectiveElapsedMs = endEpoch - startEpoch - pausedDurationMs;
          if (isPaused && lastPauseStartEpoch != null) {
            effectiveElapsedMs -= (endEpoch - lastPauseStartEpoch);
          }
          durationMinutes = (effectiveElapsedMs / 60000).round();
          billingAmount = billingMode == 'coin'
              ? (table['coin_price'] as double) * (sessionDoc['coin_used'] as int? ?? 0)
              : billingMode == 'hour'
              ? durationMinutes! * (table['per_min_cost'] as double)
              : null;

          transaction.update(sessionRef, {
            'end_epoch': endEpoch,
            'duration_minutes': durationMinutes,
            'billing_amount': billingAmount,
            'paused_duration_ms': pausedDurationMs +
                (isPaused && lastPauseStartEpoch != null ? (endEpoch - lastPauseStartEpoch) : 0),
            'is_paused': false,
            'last_pause_start_epoch': null,
          });
          transaction.update(tablesRef, {'is_active': false, 'current_session_id': null});
        });

        final bill = {
          'id': sessionId,
          'actual_start_epoch': sessionDoc['actual_start_epoch'],
          'duration_minutes': durationMinutes,
          'billing_amount': billingAmount,
          'billing_mode': billingMode,
          'coin_used': sessionDoc['coin_used'],
          'player_coins': sessionDoc['player_coins'] ?? <String, int>{},
          'assigned_player_ids': sessionDoc['assigned_player_ids'] ?? [],
        };

        // Add invoice ID to player's club-specific subcollection
        if (bill['assigned_player_ids'] != null && bill['assigned_player_ids'].isNotEmpty) {
          for (String playerId in bill['assigned_player_ids']) {
            final playerClubInvoiceRef = FirebaseFirestore.instance
                .collection('players')
                .doc(playerId)
                .collection('clubs')
                .doc(widget.clubId)
                .collection('invoices')
                .doc(sessionId);

            // Check if invoice ID already exists to avoid duplicates
            final existingPlayerClubInvoice = await playerClubInvoiceRef.get();
            if (!existingPlayerClubInvoice.exists) {
              await playerClubInvoiceRef.set({
                'invoice_id': sessionId,
                'timestamp': Timestamp.now(),
              });
            }
          }
        }

        await _loadTables();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BillSettlementScreen(
                clubId: widget.clubId,
                tableId: tableId,
                sessionId: sessionId,
                bill: bill,
              ),
            ),
          ).then((_) => _loadTables());
        }
      } finally {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
    }
  
    void _showInitialOptions(String tableId) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Start Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.access_time, color: Colors.blue),
                    title: const Text('Hour'),
                    trailing: _isButtonLoading[tableId] == true
                        ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.blue, size: 24)
                        : null,
                    onTap: _isButtonLoading[tableId] == true
                        ? null
                        : () => _startSession(tableId, 'hour').then((_) => Navigator.pop(context)),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.money, color: Colors.green),
                    title: const Text('Coin'),
                    trailing: _isButtonLoading[tableId] == true
                        ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.green, size: 24)
                        : null,
                    onTap: _isButtonLoading[tableId] == true
                        ? null
                        : () => _startSession(tableId, 'coin').then((_) => Navigator.pop(context)),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.handshake, color: Colors.orange),
                    title: const Text('Rental'),
                    trailing: _isButtonLoading[tableId] == true
                        ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.orange, size: 24)
                        : null,
                    onTap: _isButtonLoading[tableId] == true
                        ? null
                        : () => _startSession(tableId, 'rental').then((_) => Navigator.pop(context)),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt, color: Colors.red),
                    title: const Text('View Unsettled Bills'),
                    onTap: () {
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _showUnsettledBillsBottomSheet(tableId);
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  
    void _showActiveOptions(String tableId) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) {
          final table = _tables.firstWhere((t) => t['id'] == tableId);
          final isPaused = table['is_paused'] as bool? ?? false;
          final sessionId = table['current_session_id'] as String;
  
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Active Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.stop, color: Colors.red),
                    title: const Text('Stop Now'),
                    trailing: _isButtonLoading[tableId] == true
                        ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.red, size: 24)
                        : null,
                    onTap: _isButtonLoading[tableId] == true
                        ? null
                        : () {
                      Navigator.pop(context);
                      _stopSession(tableId);
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(
                      isPaused ? Icons.play_arrow : Icons.pause,
                      color: isPaused ? Colors.green : Colors.orange,
                    ),
                    title: Text(isPaused ? 'Resume' : 'Pause'),
                    trailing: _isButtonLoading[tableId] == true
                        ? LoadingAnimationWidget.staggeredDotsWave(
                        color: isPaused ? Colors.green : Colors.orange, size: 24)
                        : null,
                    onTap: _isButtonLoading[tableId] == true
                        ? null
                        : () {
                      Navigator.pop(context);
                      _togglePause(tableId, sessionId, isPaused);
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt, color: Colors.blue),
                    title: const Text('Billing Info'),
                    onTap: () async {
                      final table = _tables.firstWhere((t) => t['id'] == tableId);
                      final sessionId = table['current_session_id'] as String;
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _showBillingInfoBottomSheet(tableId, sessionId);
                      });
                    },
                  ),
                ),
                if (_tables.firstWhere((t) => t['id'] == tableId)['current_session_id'] != null)
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('clubs')
                        .doc(widget.clubId)
                        .collection('tables')
                        .doc(tableId)
                        .collection('sessions')
                        .doc(_tables.firstWhere((t) => t['id'] == tableId)['current_session_id'])
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox.shrink();
                      }
                      if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                        return const SizedBox.shrink();
                      }
                      final billingMode = snapshot.data!['billing_mode'] as String?;
                      return billingMode == 'coin'
                          ? Card(
                        child: ListTile(
                          leading: const Icon(Icons.monetization_on, color: Colors.green),
                          title: const Text('Add Coins'),
                          onTap: () async {
                            final table = _tables.firstWhere((t) => t['id'] == tableId);
                            final sessionId = table['current_session_id'] as String;
                            Navigator.pop(context);
                            Future.delayed(const Duration(milliseconds: 300), () {
                              _showAddCoinsBottomSheet(tableId, sessionId);
                            });
                          },
                        ),
                      )
                          : const SizedBox.shrink();
                    },
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sports, color: Colors.green),
                    title: const Text('Match Info'),
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt, color: Colors.red),
                    title: const Text('View Unsettled Bills'),
                    onTap: () {
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _showUnsettledBillsBottomSheet(tableId);
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    Future<void> _showUnsettledBillsBottomSheet(String tableId) async {
      setState(() {
        _isTimerActive = false;
      });

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(tableId)
            .collection('sessions')
            .where('is_settled', isEqualTo: false)
            .get();

        final currentSessionId = _tables.firstWhere(
              (table) => table['id'] == tableId,
          orElse: () => {'current_session_id': null},
        )['current_session_id'] as String?;

        final unsettledBills = snapshot.docs
            .where((doc) => doc.id != currentSessionId) // Exclude current session
            .map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'actual_start_epoch': data['actual_start_epoch'] as int? ?? 0,
            'duration_minutes': data['duration_minutes'] as int? ?? 0,
            'billing_amount': data['billing_amount'] as double? ?? 0.0,
            'billing_mode': data['billing_mode'] as String? ?? 'Unknown',
            'coin_used': data['coin_used'] as int? ?? 0,
            'player_coins': data['player_coins'] as Map<String, dynamic>? ?? <String, int>{},
            'assigned_player_ids': data['assigned_player_ids'] as List<dynamic>? ?? [],
          };
        }).toList();

        if (!mounted) return;

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
                return FractionallySizedBox(
                  heightFactor: 0.75,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Unsettled Bills',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: unsettledBills.isEmpty
                            ? const Center(child: Text('No unsettled bills'))
                            : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: unsettledBills.length,
                          itemBuilder: (context, index) {
                            final bill = unsettledBills[index];
                            final actualStartEpoch = bill['actual_start_epoch'] as int? ?? 0;
                            final dateTime = DateTime.fromMillisecondsSinceEpoch(actualStartEpoch);
                            final formattedTime =
                                '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.hour >= 12 ? 'PM' : 'AM'}';
                            final formattedDate = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
                            final billingAmount = bill['billing_amount'] as double? ?? 0.0;

                            final uuid = bill['id'] as String;
                            final uuidPart1 = uuid.substring(0, uuid.length ~/ 2);
                            final uuidPart2 = uuid.substring(uuid.length ~/ 2);

                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BillSettlementScreen(
                                      clubId: widget.clubId,
                                      tableId: tableId,
                                      sessionId: bill['id'] as String,
                                      bill: bill,
                                    ),
                                  ),
                                ).then((_) => _loadTables());
                              },
                              child: Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Session ID:', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text(uuidPart1),
                                          Text(uuidPart2),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Order Time: $formattedDate $formattedTime'),
                                      Text('Duration: ${bill['duration_minutes']} minutes'),
                                      Text('Billing Mode: ${bill['billing_mode']}'),
                                      if (bill['billing_mode'] == 'coin')
                                        Text('Total Coins: ${bill['coin_used']}'),
                                      Text('Price: ৳${billingAmount.toStringAsFixed(0)}'),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      } catch (e) {
        print('Error fetching unsettled bills: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading unsettled bills: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isTimerActive = true;
          });
        }
      }
    }
  
    Future<void> _showBillingInfoBottomSheet(String tableId, String sessionId) async {
      setState(() {
        _isTimerActive = false;
      });
  
      try {
        List<String> selectedPlayers = [];
        Map<String, String> playerNames = {};
        List<Map<String, dynamic>> filteredPlayers = [];
        List<Map<String, dynamic>> allPlayers = [];
        String? billingMode;
        bool isAssignLoading = false; // Loading state for Assign Players
        bool isStopLoading = false; // Loading state for Stop Now
        bool isAddCoinsLoading = false; // Loading state for Add Coins
  
        final sessionDoc = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(tableId)
            .collection('sessions')
            .doc(sessionId)
            .get();
        if (sessionDoc.exists) {
          selectedPlayers = List<String>.from(sessionDoc['assigned_player_ids'] ?? []);
          billingMode = sessionDoc['billing_mode'] as String?;
        }
  
        final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
        for (var doc in playersSnapshot.docs) {
          playerNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown';
        }
        allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        filteredPlayers = List.from(allPlayers);
  
        if (!mounted) return;
  
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
                return FractionallySizedBox(
                  heightFactor: 0.8,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Select Players for Billing',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search Player (IGN/Name/Phone)',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (value) {
                            final query = value.trim().toLowerCase();
                            setSheetState(() {
                              filteredPlayers = allPlayers.where((player) {
                                return (player['name']?.toLowerCase().contains(query) ?? false) ||
                                    (player['phone_number']?.toLowerCase().contains(query) ?? false) ||
                                    (player['ign']?.toLowerCase().contains(query) ?? false);
                              }).toList();
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        height: 90,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: filteredPlayers.map((player) {
                            final isSelected = selectedPlayers.contains(player['id']);
                            return GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  if (isSelected) {
                                    selectedPlayers.remove(player['id']);
                                  } else {
                                    selectedPlayers.add(player['id']);
                                  }
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
                                          color: isSelected ? Colors.red : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 28,
                                        backgroundImage: player['image_url'] != null ? NetworkImage(player['image_url']) : null,
                                        child: player['image_url'] == null ? const Icon(Icons.person, size: 28) : null,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (player['ign'] ?? player['name'] ?? 'Unknown').length > 8
                                          ? '${(player['ign'] ?? player['name'] ?? 'Unknown').substring(0, 8)}...'
                                          : player['ign'] ?? player['name'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSelected ? Colors.red : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: selectedPlayers.isEmpty || isAssignLoading
                                    ? null
                                    : () async {
                                  setSheetState(() {
                                    isAssignLoading = true;
                                  });
                                  final sessionRef = FirebaseFirestore.instance
                                      .collection('clubs')
                                      .doc(widget.clubId)
                                      .collection('tables')
                                      .doc(tableId)
                                      .collection('sessions')
                                      .doc(sessionId);
  
                                  await sessionRef.update({
                                    'assigned_player_ids': selectedPlayers,
                                    'is_billing_info_added': true,
                                  });
  
                                  setSheetState(() {
                                    isAssignLoading = false;
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Billing info added successfully')),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: selectedPlayers.isEmpty ? Colors.grey : Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: isAssignLoading
                                    ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                                    : const Text(
                                  'Assign Players',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            if (billingMode != 'coin') ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: selectedPlayers.isEmpty || isStopLoading
                                      ? null
                                      : () async {
                                    setSheetState(() {
                                      isStopLoading = true;
                                    });
                                    final sessionRef = FirebaseFirestore.instance
                                        .collection('clubs')
                                        .doc(widget.clubId)
                                        .collection('tables')
                                        .doc(tableId)
                                        .collection('sessions')
                                        .doc(sessionId);
  
                                    await sessionRef.update({
                                      'assigned_player_ids': selectedPlayers,
                                      'is_billing_info_added': true,
                                    });
  
                                    Navigator.pop(context);
                                    await _stopSession(tableId, fromBillingSheet: true);
                                    setSheetState(() {
                                      isStopLoading = false;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: selectedPlayers.isEmpty ? Colors.grey : Colors.red,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: isStopLoading
                                      ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                                      : const Text(
                                    'Stop Now',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                            if (billingMode == 'coin') ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: selectedPlayers.isEmpty || isAddCoinsLoading
                                      ? null
                                      : () async {
                                    setSheetState(() {
                                      isAddCoinsLoading = true;
                                    });
                                    // Ensure players are assigned to Firestore before adding coins
                                    final sessionRef = FirebaseFirestore.instance
                                        .collection('clubs')
                                        .doc(widget.clubId)
                                        .collection('tables')
                                        .doc(tableId)
                                        .collection('sessions')
                                        .doc(sessionId);
  
                                    await sessionRef.update({
                                      'assigned_player_ids': selectedPlayers,
                                      'is_billing_info_added': true,
                                    });
  
                                    Navigator.pop(context);
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      _showAddCoinsBottomSheet(tableId, sessionId);
                                    });
                                    setSheetState(() {
                                      isAddCoinsLoading = false;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: selectedPlayers.isEmpty ? Colors.grey : Colors.green,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: isAddCoinsLoading
                                      ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                                      : const Text(
                                    'Add Coins',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
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
      } catch (e) {
        print('Error loading players: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading players: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isTimerActive = true;
          });
        }
      }
    }
  
    Future<void> _showAddCoinsBottomSheet(String tableId, String sessionId) async {
      if (!mounted) return; // Check if widget is still mounted
      setState(() {
        _isTimerActive = false;
      });
  
      try {
        List<String> selectedPlayers = [];
        Map<String, String> playerNames = {};
        Map<String, int> playerCoins = {};
        bool isSaveLoading = false;
        bool isStopLoading = false;
  
        final sessionDoc = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('tables')
            .doc(tableId)
            .collection('sessions')
            .doc(sessionId)
            .get();
        if (sessionDoc.exists) {
          selectedPlayers = List<String>.from(sessionDoc['assigned_player_ids'] ?? []);
          final coinsData = sessionDoc['player_coins'] as Map<String, dynamic>? ?? {};
          coinsData.forEach((playerId, coins) {
            playerCoins[playerId] = coins as int;
          });
        }
  
        if (selectedPlayers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please assign players in Billing Info first')),
          );
          return;
        }
  
        final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
        for (var doc in playersSnapshot.docs) {
          playerNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown';
        }
  
        if (!mounted) return;
  
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
                              onPressed: () {
                                Navigator.pop(context);
                              },
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
                            final coinCount = playerCoins[playerId] ?? 0;
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
                                          playerCoins[playerId] = coinCount - 1;
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
                                          playerCoins[playerId] = coinCount + 1;
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
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isSaveLoading
                                    ? null
                                    : () async {
                                  if (!mounted) return;
                                  setSheetState(() {
                                    isSaveLoading = true;
                                  });
                                  await FirebaseFirestore.instance
                                      .collection('clubs')
                                      .doc(widget.clubId)
                                      .collection('tables')
                                      .doc(tableId)
                                      .collection('sessions')
                                      .doc(sessionId)
                                      .update({
                                    'player_coins': playerCoins,
                                    'coin_used': playerCoins.values.fold<int>(0, (sum, coins) => sum + (coins as int)),
                                  });
                                  if (mounted) {
                                    setSheetState(() {
                                      isSaveLoading = false;
                                    });
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Coins assigned successfully')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
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
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: selectedPlayers.isEmpty || isStopLoading
                                    ? null
                                    : () async {
                                  if (!mounted) return;
                                  setSheetState(() {
                                    isStopLoading = true;
                                  });
                                  await FirebaseFirestore.instance
                                      .collection('clubs')
                                      .doc(widget.clubId)
                                      .collection('tables')
                                      .doc(tableId)
                                      .collection('sessions')
                                      .doc(sessionId)
                                      .update({
                                    'player_coins': playerCoins,
                                    'coin_used': playerCoins.values.fold<int>(0, (sum, coins) => sum + (coins as int)),
                                  });
                                  if (mounted) {
                                    Navigator.pop(context);
                                    await _stopSession(tableId, fromBillingSheet: true);
                                    setSheetState(() {
                                      isStopLoading = false;
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: selectedPlayers.isEmpty ? Colors.grey : Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: isStopLoading
                                    ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                                    : const Text(
                                  'Stop Now',
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
      } catch (e) {
        print('Error assigning coins: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error assigning coins: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isTimerActive = true;
          });
        }
      }
    }
  
    String _formatDuration(Duration duration) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final hours = twoDigits(duration.inHours);
      final minutes = twoDigits(duration.inMinutes.remainder(60));
      final seconds = twoDigits(duration.inSeconds.remainder(60));
      return '$hours:$minutes:$seconds';
    }
  
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _tables.length,
              itemBuilder: (context, index) {
                final table = _tables[index];
                final isActive = table['is_active'] as bool;
                final tableType = table['type'] as String;
                final isPaused = table['is_paused'] as bool? ?? false;
                final unsettledBillsCount = table['unsettled_bills_count'] as int? ?? 0;
                final isBillingInfoAdded = table['is_billing_info_added'] as bool? ?? false;
                Duration elapsed = Duration.zero;
  
                if (isActive && _activeSessionStartEpochs.containsKey(table['id'])) {
                  final startEpoch = _activeSessionStartEpochs[table['id']]!;
                  final currentEpoch = DateTime.now().millisecondsSinceEpoch;
                  final pausedDurationMs = table['paused_duration_ms'] as int? ?? 0;
                  final lastPauseStartEpoch = table['last_pause_start_epoch'] as int?;
  
                  int effectiveElapsedMs = currentEpoch - startEpoch - pausedDurationMs;
                  if (isPaused && lastPauseStartEpoch != null) {
                    effectiveElapsedMs -= (currentEpoch - lastPauseStartEpoch);
                  }
                  elapsed = Duration(milliseconds: effectiveElapsedMs.clamp(0, double.infinity).toInt());
                }
  
                Color edgeColor = !isActive
                    ? Colors.grey[400] ?? Colors.grey
                    : tableType == 'Pool'
                    ? Colors.blue[600]!
                    : Colors.green[600]!;
  
                return GestureDetector(
                  onTap: () {
                    if (isActive) {
                      _showActiveOptions(table['id']);
                    } else {
                      _showInitialOptions(table['id']);
                    }
                  },
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Stack(
                      children: [
                        SizedBox(
                          height: 90,
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: isPaused ? Colors.orange : edgeColor,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    bottomLeft: Radius.circular(12),
                                  ),
                                ),
                                child: RotatedBox(
                                  quarterTurns: -1,
                                  child: Center(
                                    child: Text(
                                      tableType,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        spreadRadius: 1,
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                table['name'] as String,
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              if (!isActive)
                                                Text(
                                                  'OFF',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey[600],
                                                  ),
                                                )
                                              else
                                                Text(
                                                  table['billing_mode'].toString().toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isActive)
                                          Text(
                                            ' ${_formatDuration(elapsed)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                          )
                                        else
                                          Text(
                                            '00:00:00',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            children: [
                              if (unsettledBillsCount > 0)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                ),
                              if (isActive && !isBillingInfoAdded)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_isLoading)
              Shimmer(
                color: Colors.grey[300]!,
                child: Container(
                  color: Colors.grey[200],
                ),
              ),
          ],
        ),
      );
    }
  }
  
  class BillingInfoScreen extends StatelessWidget {
    final String clubId;
    final String tableId;
    final String sessionId;
    final int durationMinutes;
    final double billingAmount;
  
    const BillingInfoScreen({
      Key? key,
      required this.clubId,
      required this.tableId,
      required this.sessionId,
      required this.durationMinutes,
      required this.billingAmount,
    }) : super(key: key);
  
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(title: const Text('Billing Info')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Time Elapsed: $durationMinutes minutes', style: const TextStyle(fontSize: 16)),
              Text('Total Cost: ৳${billingAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }
  }