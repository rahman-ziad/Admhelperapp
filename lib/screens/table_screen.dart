import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'bill_settlement_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class TableScreen extends StatefulWidget {
  final String clubId;

  const TableScreen({super.key, required this.clubId});

  @override
  _TableScreenState createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  List<Map<String, dynamic>> _tables = [];
  late StreamSubscription _timerSubscription;
  StreamSubscription<QuerySnapshot>? _tablesSubscription; // Already declared as nullable
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
    _tablesSubscription?.cancel(); // Safe cancellation
    super.dispose();
  }

  // Rest of _loadTables remains unchanged
  void _loadTables() {
    setState(() {
      _isLoading = true;
    });

    final tablesRef = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('tables');

    _tablesSubscription?.cancel(); // Cancel previous subscription if exists
    _tablesSubscription = tablesRef.snapshots().listen((snapshot) async {
      final List<Map<String, dynamic>> newTables = [];
      final Map<String, int> newActiveSessionStartEpochs = {};

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
          'billing_mode': null,
          'is_billing_info_added': false,
          'is_info_filled': false,
          'last_pause_start_epoch': null,
        };

        newTables.add(table);

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
            final sessionData = sessionDoc.data();
            final startEpoch = sessionData?['actual_start_epoch'] as int?;
            if (startEpoch != null) {
              newActiveSessionStartEpochs[docId] = startEpoch;
              table['billing_mode'] = sessionData?['billing_mode'] as String?;
              table['is_paused'] = sessionData?['is_paused'] as bool? ?? false;
              table['paused_duration_ms'] = sessionData?['paused_duration_ms'] as int? ?? 0;
              table['last_pause_start_epoch'] = sessionData?['last_pause_start_epoch'] as int?;
              table['is_billing_info_added'] = sessionData?['is_billing_info_added'] as bool? ?? false;
              table['is_info_filled'] = sessionData?['match_info'] != null;
            }
          }
        }

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

      newTables.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));

      if (mounted) {
        setState(() {
          _tables = newTables;
          _activeSessionStartEpochs = newActiveSessionStartEpochs;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      print('Error loading tables: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
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

      // Update local table state immediately
      if (mounted) {
        setState(() {
          final table = _tables.firstWhere((t) => t['id'] == tableId);
          table['is_paused'] = !isPaused;
          table['paused_duration_ms'] = isPaused
              ? pausedDurationMs + (lastPauseStartEpoch != null ? (currentEpoch - lastPauseStartEpoch) : 0)
              : pausedDurationMs;
          table['last_pause_start_epoch'] = isPaused ? null : currentEpoch;
        });
      }
    } catch (e) {
      print('Error toggling pause: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling pause: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
    }
  }

  Future<void> _startSession(String tableId, String mode) async {
    setState(() {
      _isButtonLoading[tableId] = true;
    });

    try {
      // Map tableId to Blynk virtual pin (v1 to v6)
      final tableIndex = _tables.indexWhere((t) => t['id'] == tableId) + 1;
      if (tableIndex <= 6) {
        await _controlBlynkSwitch('v$tableIndex', 1);
      }

      final tablesRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(tableId);
      final sessionId = const Uuid().v4();
      final sessionRef = tablesRef.collection('sessions').doc(sessionId);

      final startEpoch = DateTime.now().millisecondsSinceEpoch;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final tableDoc = await transaction.get(tablesRef);
        if (!tableDoc.exists) throw Exception('Table not found');

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

      if (mounted) {
        setState(() {
          final table = _tables.firstWhere((t) => t['id'] == tableId);
          table['is_active'] = true;
          table['current_session_id'] = sessionId;
          table['billing_mode'] = mode;
          table['is_paused'] = false;
          table['paused_duration_ms'] = 0;
          table['last_pause_start_epoch'] = null;
          table['is_billing_info_added'] = false;
          _activeSessionStartEpochs[tableId] = startEpoch;
        });
      }
    } catch (e) {
      print('Error starting session: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting session: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
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
      final sessionId = table['current_session_id'] as String?;
      if (sessionId == null) throw Exception('No active session found');

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
        setState(() {
          _isButtonLoading[tableId] = false;
        });
        return;
      }

      if (billingMode == 'coin') {
        final playerCoins = sessionDoc['player_coins'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final totalCoins = playerCoins.values.fold<int>(0, (sum, coins) => sum + (coins as int));
        if (totalCoins == 0 && !fromBillingSheet) {
          await _showBillingInfoBottomSheet(tableId, sessionId);
          setState(() {
            _isButtonLoading[tableId] = false;
          });
          return;
        }
      }

      // Move Blynk switch control here to ensure it only triggers when session actually stops
      final tableIndex = _tables.indexWhere((t) => t['id'] == tableId) + 1;
      if (tableIndex <= 6) {
        await _controlBlynkSwitch('v$tableIndex', 0);
      }

      int? durationMinutes;
      double? billingAmount;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshSessionDoc = await transaction.get(sessionRef);
        if (!freshSessionDoc.exists) throw Exception('Session not found');

        final startEpoch = freshSessionDoc['actual_start_epoch'] as int?;
        if (startEpoch == null) throw Exception('Start time not found');

        final endEpoch = DateTime.now().millisecondsSinceEpoch;
        int effectiveElapsedMs = endEpoch - startEpoch - pausedDurationMs;
        if (isPaused && lastPauseStartEpoch != null) {
          effectiveElapsedMs -= (endEpoch - lastPauseStartEpoch);
        }
        durationMinutes = (effectiveElapsedMs / 60000).round();
        billingAmount = billingMode == 'coin'
            ? (table['coin_price'] as double) * (freshSessionDoc['coin_used'] as int? ?? 0)
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
        transaction.update(tablesRef, {
          'is_active': false,
          'current_session_id': null,
        });
      });

      final bill = {
        'id': sessionId,
        'actual_start_epoch': sessionDoc['actual_start_epoch'],
        'duration_minutes': durationMinutes,
        'billing_amount': billingAmount,
        'billing_mode': billingMode,
        'coin_used': sessionDoc['coin_used'] ?? 0,
        'player_coins': sessionDoc['player_coins'] ?? <String, int>{},
        'assigned_player_ids': sessionDoc['assigned_player_ids'] ?? [],
      };

      if (bill['assigned_player_ids'] != null && (bill['assigned_player_ids'] as List).isNotEmpty) {
        for (String playerId in bill['assigned_player_ids'] as List) {
          final playerClubInvoiceRef = FirebaseFirestore.instance
              .collection('players')
              .doc(playerId)
              .collection('clubs')
              .doc(widget.clubId)
              .collection('is_billing')
              .doc(sessionId);
          final existingPlayerClubInvoice = await playerClubInvoiceRef.get();
          if (!existingPlayerClubInvoice.exists) {
            await playerClubInvoiceRef.set({
              'invoice_id': sessionId,
              'timestamp': Timestamp.now(),
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          table['is_active'] = false;
          table['current_session_id'] = null;
          table['is_paused'] = false;
          table['paused_duration_ms'] = 0;
          table['last_pause_start_epoch'] = null;
          table['is_billing_info_added'] = false;
          _activeSessionStartEpochs.remove(tableId);
        });

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
    } catch (e) {
      print('Error stopping session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping session: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isButtonLoading[tableId] = false;
        });
      }
    }
  }

  Future<void> _controlBlynkSwitch(String pin, int value) async {
    const token = "Y6tZE_VrveFe5r20WkayaucMIsyfqDvC";
    final url = 'https://sgp1.blynk.cloud/external/api/update?token=$token&$pin=$value';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('Switch $pin controlled successfully to $value');
      } else {
        print('Failed to control switch $pin: ${response.statusCode}');
      }
    } catch (e) {
      print('Error controlling Blynk switch $pin: $e');
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
                      : () async {
                    await _startSession(tableId, 'hour');
                    Navigator.pop(context);
                  },
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
                      : () async {
                    await _startSession(tableId, 'coin');
                    Navigator.pop(context);
                  },
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
                      : () async {
                    await _startSession(tableId, 'rental');
                    Navigator.pop(context);
                  },
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
        final isInfoFilled = table['is_info_filled'] as bool? ?? false;

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
                      : () async {
                    Navigator.pop(context);
                    await _stopSession(tableId);
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
                      : () async {
                    Navigator.pop(context);
                    await _togglePause(tableId, sessionId, isPaused);
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt, color: Colors.blue),
                  title: const Text('Billing Info'),
                  onTap: () async {
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
                  onTap: () {
                    Navigator.pop(context);
                    final table = _tables.firstWhere((t) => t['id'] == tableId);
                    if (isInfoFilled) {
                      FirebaseFirestore.instance
                          .collection('clubs')
                          .doc(widget.clubId)
                          .collection('tables')
                          .doc(tableId)
                          .collection('sessions')
                          .doc(sessionId)
                          .get()
                          .then((doc) {
                        final matchInfo = doc.data()?['match_info'] as Map<String, dynamic>? ?? {};
                        if (matchInfo.isNotEmpty) {
                          final matchUuid = matchInfo.keys.firstWhere(
                                (k) => matchInfo[k] != null,
                            orElse: () => '',
                          );
                          if (matchUuid.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ScorecardScreen(
                                  clubId: widget.clubId,
                                  tableId: tableId,
                                  sessionId: sessionId,
                                  matchUuid: matchUuid,
                                ),
                              ),
                            ).then((_) => _loadTables());
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MatchInfoScreen(
                                  clubId: widget.clubId,
                                  tableId: tableId,
                                  sessionId: sessionId,
                                ),
                              ),
                            ).then((_) => _loadTables());
                          }
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MatchInfoScreen(
                                clubId: widget.clubId,
                                tableId: tableId,
                                sessionId: sessionId,
                              ),
                            ),
                          ).then((_) => _loadTables());
                        }
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MatchInfoScreen(
                            clubId: widget.clubId,
                            tableId: tableId,
                            sessionId: sessionId,
                          ),
                        ),
                      ).then((_) => _loadTables());
                    }
                  },
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

  void _showMatchInfoScreen(String tableId, String sessionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchInfoScreen(
          clubId: widget.clubId,
          tableId: tableId,
          sessionId: sessionId,
        ),
      ),
    ).then((_) => _loadTables());
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
          .where((doc) => doc.id != currentSessionId)
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
                                        Text(uuid.isNotEmpty ? uuid.substring(0, min(8, uuid.length)) : 'N/A'), // Show first 8 chars or N/A
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
      List<Map<String, dynamic>> allPlayers = [];
      String? billingMode;
      bool isAssignLoading = false;
      bool isStopLoading = false;
      bool isAddCoinsLoading = false;

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

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BillingInfoScreen(
            clubId: widget.clubId,
            tableId: tableId,
            sessionId: sessionId,
            initialSelectedPlayers: selectedPlayers,
            allPlayers: allPlayers,
            billingMode: billingMode,
            stopSession: _stopSession,
            showAddCoinsBottomSheet: _showAddCoinsBottomSheet,
          ),
        ),
      );

      if (result != null && result is List<String>) {
        setState(() {
          selectedPlayers = result;
        });
      }
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
    if (!mounted) return;
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
              )
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
                  : isPaused
                  ? Colors.orange
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
                                color: edgeColor,
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
                                                table['billing_mode']?.toString().toUpperCase() ?? 'UNKNOWN',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        isActive ? ' ${_formatDuration(elapsed)}' : '00:00:00',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isActive ? Colors.black : Colors.grey,
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



























class BillingInfoScreen extends StatefulWidget {
  final String clubId;
  final String tableId;
  final String sessionId;
  final List<String> initialSelectedPlayers;
  final List<Map<String, dynamic>> allPlayers;
  final String? billingMode;
  final Future<void> Function(String, {bool fromBillingSheet}) stopSession;
  final Future<void> Function(String, String) showAddCoinsBottomSheet;

  const BillingInfoScreen({
    Key? key,
    required this.clubId,
    required this.tableId,
    required this.sessionId,
    required this.initialSelectedPlayers,
    required this.allPlayers,
    required this.billingMode,
    required this.stopSession,
    required this.showAddCoinsBottomSheet,
  }) : super(key: key);

  @override
  _BillingInfoScreenState createState() => _BillingInfoScreenState();
}

class _BillingInfoScreenState extends State<BillingInfoScreen> {
  late List<String> selectedPlayers;
  bool isAssignLoading = false;
  bool isStopLoading = false;
  bool isAddCoinsLoading = false;

  @override
  void initState() {
    super.initState();
    selectedPlayers = List.from(widget.initialSelectedPlayers);
  }

  Future<void> _openSearchScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchPlayersScreen(
          clubId: widget.clubId,
          selectedPlayers: selectedPlayers,
          onSelect: (updatedPlayers) {
            setState(() {
              selectedPlayers = updatedPlayers;
            });
          },
        ),
      ),
    );
    if (result != null && result is List<String>) {
      setState(() {
        selectedPlayers = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Info'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, selectedPlayers),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search Player (IGN/Name/Phone)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onTap: _openSearchScreen,
              readOnly: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: selectedPlayers.isEmpty
                    ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No player selected',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                ]
                    : widget.allPlayers
                    .where((player) => selectedPlayers.contains(player['id']))
                    .map((player) {
                  final isSelected = selectedPlayers.contains(player['id']);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          selectedPlayers.remove(player['id']);
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
            const SizedBox(height: 16),
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
                        setState(() {
                          isAssignLoading = true;
                        });
                        final sessionRef = FirebaseFirestore.instance
                            .collection('clubs')
                            .doc(widget.clubId)
                            .collection('tables')
                            .doc(widget.tableId)
                            .collection('sessions')
                            .doc(widget.sessionId);

                        await sessionRef.update({
                          'assigned_player_ids': selectedPlayers,
                          'is_billing_info_added': true,
                        });

                        setState(() {
                          isAssignLoading = false;
                        });
                        Navigator.pop(context, selectedPlayers);
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
                  if (widget.billingMode != 'coin') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedPlayers.isEmpty || isStopLoading
                            ? null
                            : () async {
                          setState(() {
                            isStopLoading = true;
                          });
                          final sessionRef = FirebaseFirestore.instance
                              .collection('clubs')
                              .doc(widget.clubId)
                              .collection('tables')
                              .doc(widget.tableId)
                              .collection('sessions')
                              .doc(widget.sessionId);

                          await sessionRef.update({
                            'assigned_player_ids': selectedPlayers,
                            'is_billing_info_added': true,
                          });

                          Navigator.pop(context, selectedPlayers);
                          await widget.stopSession(widget.tableId, fromBillingSheet: true);
                          setState(() {
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
                  if (widget.billingMode == 'coin') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedPlayers.isEmpty || isAddCoinsLoading
                            ? null
                            : () async {
                          setState(() {
                            isAddCoinsLoading = true;
                          });
                          final sessionRef = FirebaseFirestore.instance
                              .collection('clubs')
                              .doc(widget.clubId)
                              .collection('tables')
                              .doc(widget.tableId)
                              .collection('sessions')
                              .doc(widget.sessionId);

                          await sessionRef.update({
                            'assigned_player_ids': selectedPlayers,
                            'is_billing_info_added': true,
                          });

                          Navigator.pop(context, selectedPlayers);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            widget.showAddCoinsBottomSheet(widget.tableId, widget.sessionId);
                          });
                          setState(() {
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
      ),
    );
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
  List<String> recentPlayers = [];

  @override
  void initState() {
    super.initState();
    tempSelectedPlayers = List.from(widget.selectedPlayers);
    _fetchPlayers();
    _fetchRecentPlayers();
  }

  Future<void> _fetchPlayers() async {
    final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
    setState(() {
      allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      filteredPlayers = allPlayers;
    });
  }

  Future<void> _fetchRecentPlayers() async {
    final recentDoc = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('recent_players')
        .doc('seFmSt3yw1EKMb3XWIIT')
        .get();
    if (recentDoc.exists) {
      setState(() {
        recentPlayers = List<String>.from(recentDoc.data()?['recent_player_ids'] ?? []);
      });
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
          onPressed: () {
            widget.onSelect(tempSelectedPlayers);
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              widget.onSelect(tempSelectedPlayers);
              Navigator.pop(context); // Pop back to MatchInfoScreen
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (recentPlayers.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: recentPlayers.map((playerId) {
                  final player = allPlayers.firstWhere((p) => p['id'] == playerId, orElse: () => {'id': playerId, 'name': 'Unknown', 'ign': 'Unknown'});
                  final isSelected = tempSelectedPlayers.contains(player['id']);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          tempSelectedPlayers.remove(player['id']);
                        } else {
                          tempSelectedPlayers.add(player['id']);
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
          Expanded(
            child: sortedPlayers.isEmpty
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
                    player['phone_number'] ?? 'No number',
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
          ),
        ],
      ),
    );
  }
}

class MatchInfoScreen extends StatefulWidget {
  final String clubId;
  final String tableId;
  final String sessionId;
  final Map<String, dynamic>? initialMatchInfo; // Added for edit mode

  const MatchInfoScreen({
    Key? key,
    required this.clubId,
    required this.tableId,
    required this.sessionId,
    this.initialMatchInfo,
  }) : super(key: key);

  @override
  _MatchInfoScreenState createState() => _MatchInfoScreenState();
}

class _MatchInfoScreenState extends State<MatchInfoScreen> {
  String? selectedGameType;
  String? selectedBreakType;
  String? selectedRaceType;
  int raceToCount = 0;
  bool isHandicap = false;
  List<List<String>> teams = [[],[]]; // Changed to support multiple teams
  List<Map<String, dynamic>> allPlayers = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
    if (widget.initialMatchInfo != null) {
      final matchData = widget.initialMatchInfo!.values.first;
      selectedGameType = matchData['game_type'];
      selectedBreakType = matchData['break_type'];
      isHandicap = matchData['handicap'] ?? false;
      selectedRaceType = matchData['race_type'];
      raceToCount = matchData['race_to'] ?? 0;
      final teamsData = matchData['teams'] as Map<String, dynamic>? ?? {};
      teams = List.generate(
        (teamsData.keys.length / 2).ceil(),
            (index) => List<String>.from(teamsData['team_$index'] ?? []),
      );
    }
  }

  Future<void> _fetchPlayers() async {
    final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
    setState(() {
      allPlayers = playersSnapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'] ?? 'Unknown',
        'phone_number': doc.data()['phone_number'] ?? '',
        'ign': doc.data()['ign'] ?? '',
        'image_url': doc.data()['image_url'] ?? ''
      }).toList();
    });
  }

  Future<void> _saveMatchInfo() async {
    if (selectedGameType == null || selectedBreakType == null || selectedRaceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }
    if (teams.any((team) => team.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one player per team')));
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      final matchUuid = widget.initialMatchInfo != null ? widget.initialMatchInfo!.keys.first : FirebaseFirestore.instance.collection('match_info').doc().id;
      final sessionRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId);
      final teamsMap = {for (int i = 0; i < teams.length; i++) 'team_$i': teams[i]};
      await sessionRef.update({
        'match_info.$matchUuid': {
          'game_type': selectedGameType,
          'break_type': selectedBreakType,
          'handicap': isHandicap,
          'race_type': selectedRaceType,
          'race_to': raceToCount,
          'teams': teamsMap,
          'team_0_wins': widget.initialMatchInfo != null ? widget.initialMatchInfo![matchUuid]['team_0_wins'] ?? 0 : 0,
          'team_1_wins': widget.initialMatchInfo != null ? widget.initialMatchInfo![matchUuid]['team_1_wins'] ?? 0 : 0,
          'winner_id': widget.initialMatchInfo != null ? widget.initialMatchInfo![matchUuid]['winner_id'] : null,
          'is_completed': widget.initialMatchInfo != null ? widget.initialMatchInfo![matchUuid]['is_completed'] ?? false : false,
          'frame_winners': widget.initialMatchInfo != null ? List<String>.from(widget.initialMatchInfo![matchUuid]['frame_winners'] ?? []) : [],
        },
        'active_match': matchUuid,
        'is_info_filled': true,
      });
      Navigator.pop(context);
      if (widget.initialMatchInfo == null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScorecardScreen(
              clubId: widget.clubId,
              tableId: widget.tableId,
              sessionId: widget.sessionId,
              matchUuid: matchUuid,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving match info: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<List<String>?> _selectPlayers(List<String> currentPlayers, int teamIndex) async {
    final selected = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchPlayersScreen(
          clubId: widget.clubId,
          selectedPlayers: currentPlayers,
          onSelect: (selected) {
            setState(() => teams[teamIndex] = selected);
          },
        ),
      ),
    );
    return selected;
  }

  void _addTeam() {
    setState(() {
      teams.add([]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match Info')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedGameType,
              hint: const Text('Select Game Type'),
              items: ['9 ball single', '9 ball double', '10 ball single', '10 ball double', '5 snooker single']
                  .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => selectedGameType = value),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedBreakType,
              hint: const Text('Select Break Type'),
              items: ['Winners Break', 'Alternative Break']
                  .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => selectedBreakType = value),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SwitchListTile(title: const Text('Handicap (SSR)'), value: isHandicap, onChanged: (value) => setState(() => isHandicap = value)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedRaceType,
                    hint: const Text('Race To / Best Of'),
                    items: ['Race To', 'Best Of']
                        .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedRaceType = value),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.remove), onPressed: raceToCount > 0 ? () => setState(() => raceToCount--) : null, color: Colors.red),
                    Text('$raceToCount', style: const TextStyle(fontSize: 16)),
                    IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => raceToCount++), color: Colors.green),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: ListTile(
                      title: Text('Team ${index + 1}'),
                      subtitle: Text(teams[index].isNotEmpty ? teams[index].map((id) => allPlayers.firstWhere((p) => p['id'] == id, orElse: () => {'name': 'Unknown'})['name']).join(', ') : 'Tap to select'),
                      onTap: () async {
                        final selected = await _selectPlayers(teams[index], index);
                        if (selected != null) setState(() => teams[index] = selected);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addTeam,
              child: const Text('Add Team'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isLoading ? null : _saveMatchInfo,
              child: isLoading ? const CircularProgressIndicator() : const Text('Save and Proceed to Scorecard'),
            ),
          ],
        ),
      ),
    );
  }
}





class ScorecardScreen extends StatefulWidget {
  final String clubId;
  final String tableId;
  final String sessionId;
  final String matchUuid;

  const ScorecardScreen({
    super.key,
    required this.clubId,
    required this.tableId,
    required this.sessionId,
    required this.matchUuid,
  });

  @override
  _ScorecardScreenState createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  late Map<String, dynamic> _matchInfo;
  late Map<String, String> _playerNames;
  late Map<String, String> _playerPhotos;
  late int _totalFrames;
  final Map<String, int> _teamFrameWins = {};
  final Map<String, int> _currentFramePoints = {}; // Snooker only
  final Map<String, int> _highestBreaks = {}; // Snooker only
  final Map<String, int> _currentBreakPoints = {}; // Snooker only
  final Map<String, List<int>> _breakHistory = {}; // Snooker only
  String? _winnerId;
  bool _isLoading = false;
  List<String> _frameWinners = [];
  int _currentFrame = 0;
  late bool _isSnooker;
  late Stream<DocumentSnapshot> _matchStream;

  @override
  void initState() {
  super.initState();
  _matchInfo = {}; // Initialize to prevent uninitialized access
  _playerNames = {};
  _playerPhotos = {};
  _matchStream = FirebaseFirestore.instance
      .collection('clubs')
      .doc(widget.clubId)
      .collection('tables')
      .doc(widget.tableId)
      .collection('sessions')
      .doc(widget.sessionId)
      .snapshots();
  _fetchPlayerNames();
  }

  Future<void> _fetchPlayerNames() async {
    final sessionDoc = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('tables')
        .doc(widget.tableId)
        .collection('sessions')
        .doc(widget.sessionId)
        .get();
    final matchInfo = sessionDoc.data()?['match_info']?[widget.matchUuid] ?? {};
    final teams = matchInfo['teams'] as Map<String, dynamic>? ?? {};
    final playerIds = teams.values.expand((players) => players as Iterable).cast<String>();
    final playerNamesMap = <String, String>{};
    final playerPhotosMap = <String, String>{};
    for (var playerId in playerIds) {
      final playerDoc = await FirebaseFirestore.instance.collection('players').doc(playerId).get();
      if (playerDoc.exists) {
        playerNamesMap[playerId] = playerDoc.data()?['in_game_name'] ?? playerDoc.data()?['name'] ?? 'Unknown';
        playerPhotosMap[playerId] = playerDoc.data()?['image_url'] ?? '';
      }
    }
    if (mounted) {
      setState(() {
        _playerNames = playerNamesMap;
        _playerPhotos = playerPhotosMap;
      });
    }
  }

  void _updateStateFromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>?;
    _matchInfo = data?['match_info']?[widget.matchUuid] ?? {};
    _totalFrames = _matchInfo['race_to'] ?? 1;
    _isSnooker = _matchInfo['game_type'] == '5 snooker single';

    final teamsData = _matchInfo['teams'] as Map<String, dynamic>? ?? {};
    _teamFrameWins.clear();
    if (_isSnooker) {
      _currentFramePoints.clear();
      _highestBreaks.clear();
      _currentBreakPoints.clear();
      _breakHistory.clear();
    }
    teamsData.forEach((teamKey, players) {
      _teamFrameWins[teamKey] = _matchInfo['${teamKey}_wins'] ?? 0; // Safer null handling
      if (_isSnooker) {
        _currentFramePoints[teamKey] = _matchInfo['current_frame_points']?[teamKey] ?? 0;
        _highestBreaks[teamKey] = _matchInfo['highest_breaks']?[teamKey] ?? 0;
        _currentBreakPoints[teamKey] = _matchInfo['current_break_points']?[teamKey] ?? 0;
        _breakHistory[teamKey] = List<int>.from(_matchInfo['break_history']?[teamKey] ?? []);
      }
    });
    _winnerId = _matchInfo['winner_id'];
    _frameWinners = List<String>.from(_matchInfo['frame_winners'] ?? []);
    _currentFrame = _frameWinners.length;

    _checkWinner();
  }

  Future<void> _updateScore(String teamKey, int change, {bool isFoul = false}) async {
    if (_winnerId != null) return;

    setState(() => _isLoading = true);

    if (_isSnooker) {
      if (_currentFramePoints.containsKey(teamKey)) {
        if (isFoul) {
          final opponentKey = teamKey == 'team_0' ? 'team_1' : 'team_0';
          final newOpponentPoints = (_currentFramePoints[opponentKey] ?? 0) + change;
          if (newOpponentPoints >= 0) {
            _currentFramePoints[opponentKey] = newOpponentPoints;
            _currentBreakPoints[opponentKey] = (_currentBreakPoints[opponentKey] ?? 0) + change;
            // Update frame-specific highest break
            _highestBreaks[opponentKey] = max(_highestBreaks[opponentKey] ?? 0, _currentBreakPoints[opponentKey] ?? 0);
          }
        } else {
          final newPoints = (_currentFramePoints[teamKey] ?? 0) + change;
          if (newPoints >= 0) {
            _currentFramePoints[teamKey] = newPoints;
            _currentBreakPoints[teamKey] = (_currentBreakPoints[teamKey] ?? 0) + change;
            // Update frame-specific highest break
            _highestBreaks[teamKey] = max(_highestBreaks[teamKey] ?? 0, _currentBreakPoints[teamKey] ?? 0);
          }
        }
      }
    } else {
      if (_teamFrameWins.containsKey(teamKey)) {
        if (_teamFrameWins[teamKey]! + change >= 0) {
          if (change > 0) {
            _teamFrameWins[teamKey] = _teamFrameWins[teamKey]! + change;
            _frameWinners.add(teamKey);
            _currentFrame++;
          } else if (change < 0 && _teamFrameWins[teamKey]! > 0) {
            _teamFrameWins[teamKey] = _teamFrameWins[teamKey]! + change;
            for (int i = _frameWinners.length - 1; i >= 0; i--) {
              if (_frameWinners[i] == teamKey) {
                _frameWinners.removeAt(i);
                _currentFrame--;
                break;
              }
            }
          }
        }
      }
    }

    _checkWinner();
    await _saveMatchData();
    setState(() => _isLoading = false);
  }

  Future<void> _endBreak(String teamKey) async {
    if (!_isSnooker || _winnerId != null) return;

    setState(() => _isLoading = true);

    final breakScore = _currentBreakPoints[teamKey] ?? 0;
    if (breakScore > 0) {
      _breakHistory[teamKey]!.add(breakScore);
      await _savePlayerVisitScore(teamKey, breakScore); // Save visit score
    }
    _currentBreakPoints[teamKey] = 0;
    await _saveMatchData();
    setState(() => _isLoading = false);
  }

  Future<void> _endFrame() async {
    if (_winnerId != null) return;

    setState(() => _isLoading = true);

    if (_isSnooker) {
      String? frameWinner;
      int maxPoints = -1;
      _currentFramePoints.forEach((teamKey, points) {
        if (points > maxPoints) {
          maxPoints = points;
          frameWinner = teamKey;
        }
      });

      if (frameWinner != null && maxPoints > 0) {
        _teamFrameWins[frameWinner!] = (_teamFrameWins[frameWinner!] ?? 0) + 1;
        _frameWinners.add(frameWinner!);
        _currentFrame++;

        // Save frame data
        _matchInfo['frames'] ??= {};
        _matchInfo['frames'][(_currentFrame).toString()] = {
          'highest_breaks': Map<String, int>.from(_highestBreaks),
          'frame_points': Map<String, int>.from(_currentFramePoints),
          'winner': frameWinner,
        };

        _currentFramePoints.clear();
        _currentBreakPoints.clear();
        _highestBreaks.clear(); // Reset for next frame
      }
    }

    _checkWinner();
    await _saveMatchData();
    setState(() => _isLoading = false);
  }

  void _checkWinner() {
    final raceTo = _matchInfo['race_to'] ?? 1;
    final raceType = _matchInfo['race_type'] ?? 'Best Of';
    final framesNeeded = raceType == 'Best Of' ? (_totalFrames / 2).ceil() : raceTo;

    _winnerId = null; // Reset winner

    _teamFrameWins.forEach((teamKey, frames) {
      if (frames >= framesNeeded) {
        _winnerId = (_matchInfo['teams'][teamKey] as List<dynamic>).first;
      }
    });

    if (_winnerId != null && _winnerId != 'draw') {
      _saveWinnerStats();
    }
  }

  Future<void> _saveMatchData() async {
    final sessionRef = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('tables')
        .doc(widget.tableId)
        .collection('sessions')
        .doc(widget.sessionId);
    final updates = {
      'match_info.${widget.matchUuid}.winner_id': _winnerId,
      'match_info.${widget.matchUuid}.is_completed': _winnerId != null,
      'match_info.${widget.matchUuid}.frame_winners': _frameWinners,
      'match_info.${widget.matchUuid}.frames': _matchInfo['frames'] ?? {},
    };
    if (_isSnooker) {
      updates['match_info.${widget.matchUuid}.current_frame_points'] = _currentFramePoints;
      updates['match_info.${widget.matchUuid}.highest_breaks'] = _highestBreaks;
      updates['match_info.${widget.matchUuid}.current_break_points'] = _currentBreakPoints;
      updates['match_info.${widget.matchUuid}.break_history'] = _breakHistory;
    }
    _teamFrameWins.forEach((teamKey, wins) {
      updates['match_info.${widget.matchUuid}.${teamKey}_wins'] = wins;
    });
    await sessionRef.update(updates);
  }

  Future<void> _saveWinnerStats() async {
    if (_winnerId != null && _winnerId != 'draw') {
      final statsRef = FirebaseFirestore.instance
          .collection('players')
          .doc(_winnerId!)
          .collection('stats')
          .doc('match_history');
      await statsRef.set({
        'wins': FieldValue.increment(1),
        'last_win_date': DateTime.now(),
      }, SetOptions(merge: true));
    }
  }
  Future<void> _savePlayerVisitScore(String teamKey, int breakScore) async {
    if (!_isSnooker || breakScore <= 0) return;

    final players = _matchInfo['teams'][teamKey] as List<dynamic>;
    final visitId = FirebaseFirestore.instance.collection('visits').doc().id;
    final timestamp = DateTime.now();

    for (var playerId in players) {
      final visitRef = FirebaseFirestore.instance
          .collection('players')
          .doc(playerId)
          .collection('visits')
          .doc(visitId);
      await visitRef.set({
        'match_uuid': widget.matchUuid,
        'frame_number': _currentFrame + 1,
        'break_score': breakScore,
        'timestamp': timestamp,
        'team_key': teamKey,
      });
    }
  }


  void _showScoreAdjustmentSheet(String teamKey) {
    if (_winnerId != null) return;

    // Local state for real-time updates
    int localCurrentPoints = _currentFramePoints[teamKey] ?? 0;
    int localCurrentBreak = _currentBreakPoints[teamKey] ?? 0;
    TextEditingController breakController = TextEditingController(text: localCurrentBreak.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Transparent for custom shape
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with team name and close button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Team ${teamKey == 'team_0' ? 1 : 2} Score',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Current Break and Frame Points
                    if (_isSnooker) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Break',
                                style: TextStyle(fontSize: 14, color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: breakController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.grey[100],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  ),
                                  onSubmitted: (value) async {
                                    final newBreak = int.tryParse(value) ?? 0;
                                    if (newBreak >= 0) {
                                      final change = newBreak - localCurrentBreak;
                                      localCurrentBreak = newBreak;
                                      localCurrentPoints += change;
                                      breakController.text = localCurrentBreak.toString();
                                      await _updateScore(teamKey, change);
                                      setModalState(() {});
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Frame Points',
                                style: TextStyle(fontSize: 14, color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$localCurrentPoints',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Score Balls Section
                      const Text(
                        'Score Balls',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1,
                        children: [
                          _buildBallButton('Red', 1, Colors.red, teamKey, () async {
                            localCurrentPoints += 1;
                            localCurrentBreak += 1;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 1);
                            setModalState(() {});
                          }),
                          _buildBallButton('Yellow', 2, Colors.yellow, teamKey, () async {
                            localCurrentPoints += 2;
                            localCurrentBreak += 2;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 2);
                            setModalState(() {});
                          }),
                          _buildBallButton('Green', 3, Colors.green, teamKey, () async {
                            localCurrentPoints += 3;
                            localCurrentBreak += 3;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 3);
                            setModalState(() {});
                          }),
                          _buildBallButton('Brown', 4, Colors.brown, teamKey, () async {
                            localCurrentPoints += 4;
                            localCurrentBreak += 4;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 4);
                            setModalState(() {});
                          }),
                          _buildBallButton('Blue', 5, Colors.blue, teamKey, () async {
                            localCurrentPoints += 5;
                            localCurrentBreak += 5;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 5);
                            setModalState(() {});
                          }),
                          _buildBallButton('Pink', 6, Colors.pink, teamKey, () async {
                            localCurrentPoints += 6;
                            localCurrentBreak += 6;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 6);
                            setModalState(() {});
                          }),
                          _buildBallButton('Black', 7, Colors.black, teamKey, () async {
                            localCurrentPoints += 7;
                            localCurrentBreak += 7;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 7);
                            setModalState(() {});
                          }),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Foul Points Section
                      const Text(
                        'Foul Points',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildFoulButton(4, teamKey, () async {
                            final opponentKey = teamKey == 'team_0' ? 'team_1' : 'team_0';
                            localCurrentPoints = _currentFramePoints[opponentKey] ?? 0;
                            localCurrentPoints += 4;
                            localCurrentBreak = _currentBreakPoints[opponentKey] ?? 0;
                            localCurrentBreak += 4;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 4, isFoul: true);
                            setModalState(() {});
                          }),
                          _buildFoulButton(5, teamKey, () async {
                            final opponentKey = teamKey == 'team_0' ? 'team_1' : 'team_0';
                            localCurrentPoints = _currentFramePoints[opponentKey] ?? 0;
                            localCurrentPoints += 5;
                            localCurrentBreak = _currentBreakPoints[opponentKey] ?? 0;
                            localCurrentBreak += 5;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 5, isFoul: true);
                            setModalState(() {});
                          }),
                          _buildFoulButton(6, teamKey, () async {
                            final opponentKey = teamKey == 'team_0' ? 'team_1' : 'team_0';
                            localCurrentPoints = _currentFramePoints[opponentKey] ?? 0;
                            localCurrentPoints += 6;
                            localCurrentBreak = _currentBreakPoints[opponentKey] ?? 0;
                            localCurrentBreak += 6;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 6, isFoul: true);
                            setModalState(() {});
                          }),
                          _buildFoulButton(7, teamKey, () async {
                            final opponentKey = teamKey == 'team_0' ? 'team_1' : 'team_0';
                            localCurrentPoints = _currentFramePoints[opponentKey] ?? 0;
                            localCurrentPoints += 7;
                            localCurrentBreak = _currentBreakPoints[opponentKey] ?? 0;
                            localCurrentBreak += 7;
                            breakController.text = localCurrentBreak.toString();
                            await _updateScore(teamKey, 7, isFoul: true);
                            setModalState(() {});
                          }),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: localCurrentBreak > 0
                                  ? () async {
                                Navigator.pop(context);
                                await _endBreak(teamKey);
                              }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('End Break', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: localCurrentBreak > 0
                                  ? () async {
                                localCurrentPoints -= localCurrentBreak;
                                localCurrentBreak = 0;
                                breakController.text = '0';
                                await _updateScore(teamKey, -localCurrentBreak);
                                setModalState(() {});
                              }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Undo Last', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Non-snooker score adjustment
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, color: Colors.red),
                            onPressed: (_teamFrameWins[teamKey] ?? 0) > 0
                                ? () async {
                              Navigator.pop(context);
                              await _updateScore(teamKey, -1);
                            }
                                : null,
                          ),
                          Text(
                            '${_teamFrameWins[teamKey] ?? 0}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.green),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _updateScore(teamKey, 1);
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

// Updated Ball Button Widget
  Widget _buildBallButton(String label, int points, Color color, String teamKey, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, // Smaller size
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                label[0],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

// Updated Foul Button Widget
  Widget _buildFoulButton(int points, String teamKey, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(
        'Foul $points',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  void _showFrameDetails() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext context) {
        final frameWinners = List<String>.from(_matchInfo['frame_winners'] ?? []);
        final framesData = _matchInfo['frames'] as Map<String, dynamic>? ?? {};

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Frame Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Frame No', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Text('Winner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (_isSnooker)
                    const Text('Highest Break', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(frameWinners.length, (index) {
                      final winner = frameWinners[index];
                      final winnerName = (_matchInfo['teams'][winner] as List<dynamic>?)
                          ?.map((id) => _playerNames[id] ?? 'Unknown')
                          .join(', ') ?? 'Unknown';
                      final frameKey = (index + 1).toString();
                      final highestBreak = _isSnooker
                          ? (framesData[frameKey]?['highest_breaks']?[winner] ?? 0)
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${index + 1}', style: const TextStyle(fontSize: 16)),
                            Text(winnerName, style: const TextStyle(fontSize: 16)),
                            if (_isSnooker) Text('$highestBreak', style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamCard(String teamKey, List<dynamic> players, Map<String, dynamic> matchData) {
    final frameWins = matchData['${teamKey}_wins'] ?? 0;
    final currentPoints = _isSnooker ? (matchData['current_frame_points']?[teamKey] ?? 0) : 0;
    final highestBreak = _isSnooker ? (matchData['highest_breaks']?[teamKey] ?? 0) : 0;
    final isWinner = _winnerId != null && players.any((id) => (matchData['teams']?[teamKey] as List<dynamic>?)?.contains(id) == true);
    final teamName = 'Team ${int.parse(teamKey.split('_')[1]) + 1}';

    return GestureDetector(
      onTap: _winnerId == null ? () => _showScoreAdjustmentSheet(teamKey) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isWinner ? Colors.green[100] : Colors.grey[300],
          borderRadius: BorderRadius.circular(15),
          border: isWinner ? Border.all(color: Colors.green, width: 2) : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    players.map((id) => _playerNames[id] ?? 'Unknown').join(' & '),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${matchData['race_type'] == 'Best Of' ? 'Best Of $_totalFrames' : 'Race To $_totalFrames'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    children: players.asMap().entries.map((entry) {
                      final index = entry.key;
                      final playerId = entry.value;
                      final playerPhoto = _playerPhotos[playerId] ?? ''; // Fallback to empty string if null
                      return Positioned(
                        left: index * 15.0,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage: playerPhoto.isNotEmpty ? NetworkImage(playerPhoto) : null,
                          child: playerPhoto.isEmpty
                              ? Text(
                            teamName.substring(5, 6),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          )
                              : null,
                          backgroundColor: playerPhoto.isEmpty
                              ? (teamKey == 'team_0' ? Colors.orange : Colors.purple)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Frames: ${frameWins.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black54),
                    ),
                    if (_isSnooker) ...[
                      Text(
                        'Points: $currentPoints',
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      Text(
                        'Highest Break: $highestBreak',
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMatch() async {
    setState(() => _isLoading = true);
    try {
      final sessionRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId);
      final sessionData = (await sessionRef.get()).data();
      await sessionRef.update({
        'match_info.${widget.matchUuid}': FieldValue.delete(),
        'active_match': sessionData?['active_match'] == widget.matchUuid
            ? FieldValue.delete()
            : FieldValue.increment(0),
      });
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting match: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _matchStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.green)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.data() == null) {
          return const Scaffold(
            body: Center(child: Text('Error loading data', style: TextStyle(color: Colors.red))),
          );
        }

        _updateStateFromSnapshot(snapshot.data!);
        final teams = _matchInfo['teams'] as Map<String, dynamic>? ?? {};
        final currentMatch = _matchInfo;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: Text(
              _isSnooker ? 'Snooker Scorecard' : 'Scorecard',
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (_teamFrameWins.values.every((wins) => wins == 0))
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.black),
                  onPressed: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MatchInfoScreen(
                          clubId: widget.clubId,
                          tableId: widget.tableId,
                          sessionId: widget.sessionId,
                          initialMatchInfo: {widget.matchUuid: _matchInfo},
                        ),
                      ),
                    ).then((_) => setState(() {}));
                  },
                ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.black),
                onPressed: _showFrameDetails,
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteMatch,
              ),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'TABLE ${widget.tableId} - Frame ${_currentFrame + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              'Frame ${_currentFrame + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.sports, color: Colors.black54),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              '${_matchInfo['race_type'] == 'Best Of' ? 'Best Of $_totalFrames' : 'Race To $_totalFrames'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...teams.keys.map((teamKey) => Column(
                      children: [
                        _buildTeamCard(teamKey, teams[teamKey] as List<dynamic> ?? [], currentMatch),
                        const SizedBox(height: 16),
                      ],
                    )),
                    if (_winnerId == null && _isSnooker)
                      ElevatedButton(
                        onPressed: _endFrame,
                        child: const Text('End Frame'),
                      ),
                    if (_winnerId != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _winnerId == 'draw' ? Colors.grey[300] : Colors.amber[100],
                          borderRadius: BorderRadius.circular(15),
                          border: _winnerId == 'draw' ? null : Border.all(color: Colors.amber, width: 2),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _winnerId == 'draw' ? Icons.handshake : Icons.emoji_events,
                              color: _winnerId == 'draw' ? Colors.grey : Colors.amber,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _winnerId == 'draw' ? 'DRAW' : 'WINNER',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _winnerId == 'draw' ? Colors.grey[800] : Colors.amber[800],
                              ),
                            ),
                            if (_winnerId != 'draw')
                              Text(
                                (currentMatch['teams'][_winnerId!.startsWith('team_0') ? 'team_0' : 'team_1'] as List<dynamic>?)
                                    ?.map((id) => _playerNames[id] ?? id)
                                    .join(' & ') ??
                                    _winnerId!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () async {
                          final newMatchUuid = FirebaseFirestore.instance.collection('match_info').doc().id;
                          final newSessionRef = FirebaseFirestore.instance
                              .collection('clubs')
                              .doc(widget.clubId)
                              .collection('tables')
                              .doc(widget.tableId)
                              .collection('sessions')
                              .doc(widget.sessionId);
                          final teamsMap = {for (int i = 0; i < teams.length; i++) 'team_$i': []};
                          await newSessionRef.update({
                            'match_info.$newMatchUuid': {
                              'game_type': _matchInfo['game_type'],
                              'break_type': _matchInfo['break_type'],
                              'handicap': _matchInfo['handicap'],
                              'race_type': _matchInfo['race_type'],
                              'race_to': _matchInfo['race_to'],
                              'teams': teamsMap,
                              'team_0_wins': 0,
                              'team_1_wins': 0,
                              'winner_id': null,
                              'is_completed': false,
                              'frame_winners': [],
                              if (_isSnooker) 'current_frame_points': {for (var key in teams.keys) key: 0},
                              if (_isSnooker) 'highest_breaks': {for (var key in teams.keys) key: 0},
                              if (_isSnooker) 'current_break_points': {for (var key in teams.keys) key: 0},
                              if (_isSnooker) 'break_history': {for (var key in teams.keys) key: []},
                            },
                          });
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MatchInfoScreen(
                                clubId: widget.clubId,
                                tableId: widget.tableId,
                                sessionId: widget.sessionId,
                              ),
                            ),
                          );
                        },
                        child: const Text('Play Again'),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

