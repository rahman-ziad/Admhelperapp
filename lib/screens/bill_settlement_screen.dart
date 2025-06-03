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

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
    _fetchSessionDetails();
    _fetchTableDetails();
    _loadSessionInfo();
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
        selectedPlayers = List<String>.from(sessionDoc['assigned_player_ids'] ?? []);
        setState(() {
          billingMode = widget.bill['billing_mode'] as String? ?? 'hour';
        });
        _distributeBillAutomatically();
        setState(() {});
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
        setState(() {
          coinPrice = (tableDoc.data()?['coin_price'] as num?)?.toDouble() ?? 0.0;
          perMinCost = (tableDoc.data()?['per_min_cost'] as num?)?.toDouble() ?? 0.0;
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
    final subTotal = _calculateSubTotal();
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
            playerAmounts[playerId] = coins * coinPrice;
            playerPercentages[playerId] = totalCoins > 0 ? (coins / totalCoins * 100) : 0.0;
          }
          if (totalAssignedCoins != totalCoins && selectedPlayers.isNotEmpty) {
            final lastPlayerId = selectedPlayers.last;
            final adjustment = totalCoins - (totalAssignedCoins - (playerCoins[lastPlayerId] ?? 0));
            playerCoins[lastPlayerId] = adjustment as int;
            playerAmounts[lastPlayerId] = adjustment * coinPrice;
            playerPercentages[lastPlayerId] = totalCoins > 0 ? (adjustment / totalCoins * 100) : 0.0;
          }
        } else {
          final amountPerPlayer = subTotal / selectedPlayers.length;
          for (var playerId in selectedPlayers) {
            playerAmounts[playerId] = amountPerPlayer;
            playerPercentages[playerId] = 100.0 / selectedPlayers.length;
          }
        }
        customTotal = subTotal;
      } else if (splitMode == 'percentage') {
        for (var playerId in selectedPlayers) {
          final percentage = playerPercentages[playerId] ?? 0.0;
          playerAmounts[playerId] = subTotal * (percentage / 100);
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
          final amount = playerAmounts[playerId] ?? 0.0;
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

    setState(() {
      _isSettling = true;
    });

    try {
      final subTotal = _calculateSubTotal();
      final durationMinutes = widget.bill['duration_minutes'] as int? ?? 0;

      if ((splitMode == 'percentage' || splitMode == 'amount') && customTotal != subTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Total must equal the bill: ৳$subTotal')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables')
          .doc(widget.tableId)
          .collection('sessions')
          .doc(widget.sessionId)
          .update({
        'billing_amount': subTotal,
        'is_settled': true,
        if (billingMode == 'coin') 'player_coins': playerCoins,
      });

      final now = DateTime.now();
      final date = Timestamp.fromDate(DateTime(now.year, now.month, now.day));

      for (var playerId in selectedPlayers) {
        final amount = playerAmounts[playerId] ?? 0.0;
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
          },
        };

        final invoicesSnapshot = await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('invoices')
            .where('player_id', isEqualTo: playerId)
            .where('status', isEqualTo: 'unpaid')
            .get();

        QueryDocumentSnapshot<Map<String, dynamic>>? existingInvoice;
        for (var doc in invoicesSnapshot.docs) {
          final invoiceDate = (doc['date'] as Timestamp).toDate();
          if (invoiceDate.year == now.year &&
              invoiceDate.month == now.month &&
              invoiceDate.day == now.day) {
            existingInvoice = doc;
            break;
          }
        }

        String invoiceId;
        double updatedTotal = amount;
        if (existingInvoice != null) {
          final existingServices = List<Map<String, dynamic>>.from(existingInvoice['services']);
          existingServices.add(serviceDetails);

          updatedTotal = existingServices.fold(0.0, (sum, service) {
            final details = service['details'] as Map<String, dynamic>;
            return sum + (details['price'] as double? ?? 0.0);
          });

          await FirebaseFirestore.instance
              .collection('clubs')
              .doc(widget.clubId)
              .collection('invoices')
              .doc(existingInvoice.id)
              .update({
            'services': existingServices,
            'total_amount': updatedTotal,
          });
          invoiceId = existingInvoice.id;
        } else {
          final invoiceData = {
            'player_id': playerId,
            'player_name': playerNames[playerId] ?? 'Unknown',
            'date': date,
            'status': 'unpaid',
            'total_amount': amount,
            'paid_amount': 0.0,
            'services': [serviceDetails],
          };

          final invoiceRef = await FirebaseFirestore.instance
              .collection('clubs')
              .doc(widget.clubId)
              .collection('invoices')
              .add(invoiceData);
          invoiceId = invoiceRef.id;
        }

        await FirebaseFirestore.instance
            .collection('players')
            .doc(playerId)
            .collection('invoices')
            .doc(invoiceId)
            .set({
          'club_id': widget.clubId,
          'invoice_id': invoiceId,
          'date': date,
          'total_amount': updatedTotal,
          'status': 'unpaid',
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill settled successfully')),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Error settling bill: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to settle bill: $e')),
      );
    } finally {
      setState(() {
        _isSettling = false;
      });
    }
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
    final subTotal = _calculateSubTotal();
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
                  decoration: InputDecoration(
                    hintText: 'Search Player (IGN/Name/Phone)',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (value) {
                    final query = value.trim().toLowerCase();
                    setState(() {
                      filteredPlayers = allPlayers.where((player) {
                        return (player['name']?.toLowerCase().contains(query) ?? false) ||
                            (player['phone_number']?.toLowerCase().contains(query) ?? false) ||
                            (player['ign']?.toLowerCase().contains(query) ?? false);
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ...selectedPlayers.map((playerId) {
                        final player = allPlayers.firstWhere((p) => p['id'] == playerId);
                        final isSelected = selectedPlayers.contains(playerId);
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
                      ...filteredPlayers.where((player) => !selectedPlayers.contains(player['id'])).map((player) {
                        final isSelected = selectedPlayers.contains(player['id']);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedPlayers.add(player['id']);
                              playerAmounts[player['id']] = 0.0;
                              playerPercentages[player['id']] = 0.0;
                              playerCoins[player['id']] = 0;
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
                    ],
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
                                  fontSize: 16,
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
                if (selectedPlayers.isNotEmpty) ...[
                  const Text(
                    'Click any player to edit coins',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: selectedPlayers.map((playerId) {
                      final player = allPlayers.firstWhere((p) => p['id'] == playerId);
                      final amount = playerAmounts[playerId] ?? 0.0;
                      final percentage = splitMode == 'percentage' && subTotal > 0
                          ? (amount / subTotal * 100).toStringAsFixed(1)
                          : (playerPercentages[playerId] ?? 0.0).toStringAsFixed(1);
                      final coins = billingMode == 'coin' ? (playerCoins[playerId] ?? 0) : 0;
                      return GestureDetector(
                        onTap: () => _showAddCoinsBottomSheet(),
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
                                    'Value: ৳${(coins * coinPrice).toStringAsFixed(0)}',
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
                ],
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
      ),
    );
  }
}