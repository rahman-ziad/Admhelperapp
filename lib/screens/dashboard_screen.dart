import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer_animation/shimmer_animation.dart';

class DashboardScreen extends StatefulWidget {
  final String clubId;

  const DashboardScreen({super.key, required this.clubId});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedPeriod = 'Today';
  final List<String> _periods = ['Today', '7 Days', 'Monthly'];

  Future<Map<String, dynamic>> _getReportData(String period) async {
    final now = DateTime.now();
    DateTime start, end, prevStart, prevEnd;

    if (period == 'Today') {
      start = DateTime(now.year, now.month, now.day, 0, 0);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      prevStart = start.subtract(const Duration(days: 1));
      prevEnd = DateTime(prevStart.year, prevStart.month, prevStart.day, 23, 59, 59, 999);
    } else if (period == '7 Days') {
      start = now.subtract(const Duration(days: 6));
      end = now;
      prevStart = start.subtract(const Duration(days: 7));
      prevEnd = start;
    } else {
      start = DateTime(now.year, now.month, 1);
      end = now;
      prevStart = DateTime(now.year, now.month - 1, 1);
      prevEnd = DateTime(now.year, now.month, 0);
    }

    // Query invoices for the current period
    final currentInvoicesQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    // Query invoices for the previous period
    final prevInvoicesQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(prevEnd))
        .get();

    // Query payments for the current period
    final currentPaymentsQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('payments')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    // Query payments for the previous period
    final prevPaymentsQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('payments')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(prevEnd))
        .get();

    final results = await Future.wait([
      currentInvoicesQuery,
      prevInvoicesQuery,
      currentPaymentsQuery,
      prevPaymentsQuery,
    ]);
    final currentInvoicesSnapshot = results[0];
    final prevInvoicesSnapshot = results[1];
    final currentPaymentsSnapshot = results[2];
    final prevPaymentsSnapshot = results[3];

    // Parse current invoices data
    int todayPlayers = 0;
    double todayOrderTotal = 0.0;
    double todayDues = 0.0;
    Set<String> uniquePlayers = {};

    for (var doc in currentInvoicesSnapshot.docs) {
      final data = doc.data();
      final playerId = data['player_id'] as String?;
      final totalAmount = (data['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (data['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = (data['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final roundUpAmount = (data['round_up'] as num?)?.toDouble() ?? 0.0;
      final discountedTotal = totalAmount - discountAmount;
      final adjustedTotal = discountedTotal + roundUpAmount;
      final dueAmount = adjustedTotal - paidAmount;

      if (playerId != null && !uniquePlayers.contains(playerId)) {
        uniquePlayers.add(playerId);
        todayPlayers++;
      }
      todayOrderTotal += adjustedTotal;
      todayDues += dueAmount > 0 ? dueAmount : 0.0;
    }

    // Parse previous invoices data
    int prevPlayers = 0;
    double prevOrderTotal = 0.0;
    double prevDues = 0.0;
    Set<String> prevUniquePlayers = {};

    for (var doc in prevInvoicesSnapshot.docs) {
      final data = doc.data();
      final playerId = data['player_id'] as String?;
      final totalAmount = (data['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (data['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = (data['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final roundUpAmount = (data['round_up'] as num?)?.toDouble() ?? 0.0;
      final discountedTotal = totalAmount - discountAmount;
      final adjustedTotal = discountedTotal + roundUpAmount;
      final dueAmount = adjustedTotal - paidAmount;

      if (playerId != null && !prevUniquePlayers.contains(playerId)) {
        prevUniquePlayers.add(playerId);
        prevPlayers++;
      }
      prevOrderTotal += adjustedTotal;
      prevDues += dueAmount > 0 ? dueAmount : 0.0;
    }

    // Parse current payments data
    double paymentReceived = 0.0;
    Map<String, double> paymentMethods = {
      'Cash': 0.0,
      'Bkash': 0.0,
      'Nagad': 0.0,
      'Bank': 0.0,
      'Stars': 0.0,
    };

    for (var doc in currentPaymentsSnapshot.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final method = data['method'] as String?;

      paymentReceived += amount;
      if (method != null && paymentMethods.containsKey(method)) {
        paymentMethods[method] = (paymentMethods[method] ?? 0.0) + amount;
      }
    }

    // Parse previous payments data
    double prevPaymentReceived = 0.0;
    for (var doc in prevPaymentsSnapshot.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      prevPaymentReceived += amount;
    }

    // Calculate percentages
    double playerPercent = prevPlayers > 0 ? ((todayPlayers - prevPlayers) / prevPlayers * 100) : 0.0;
    double orderPercent = prevOrderTotal > 0 ? ((todayOrderTotal - prevOrderTotal) / prevOrderTotal * 100) : 0.0;
    double paymentPercent = prevPaymentReceived > 0 ? ((paymentReceived - prevPaymentReceived) / prevPaymentReceived * 100) : 0.0;
    double duesPercent = prevDues > 0 ? ((todayDues - prevDues) / prevDues * 100) : 0.0;

    return {
      'todayPlayers': todayPlayers,
      'todayOrderTotal': todayOrderTotal,
      'paymentReceived': paymentReceived,
      'dues': todayDues,
      'paymentMethods': paymentMethods,
      'prevPlayers': prevPlayers,
      'prevOrderTotal': prevOrderTotal,
      'prevPaymentReceived': prevPaymentReceived,
      'prevDues': prevDues,
      'playerPercent': playerPercent,
      'orderPercent': orderPercent,
      'paymentPercent': paymentPercent,
      'duesPercent': duesPercent,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _periods.map((period) {
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPeriod = period;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedPeriod == period ? Colors.red : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          period,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _selectedPeriod == period ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _getReportData(_selectedPeriod),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Shimmer(
                    child: ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        Container(height: 20, color: Colors.white),
                        const SizedBox(height: 16),
                        Container(height: 150, color: Colors.white),
                        const SizedBox(height: 16),
                        Row(children: [
                          Container(width: 150, height: 100, color: Colors.white),
                          Container(width: 150, height: 100, color: Colors.white),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Container(width: 150, height: 100, color: Colors.white),
                          Container(width: 150, height: 100, color: Colors.white),
                        ]),
                        const SizedBox(height: 16),
                        Container(height: 20, color: Colors.white),
                        const SizedBox(height: 8),
                        Row(children: [
                          Container(width: 70, height: 80, color: Colors.white),
                          Container(width: 70, height: 80, color: Colors.white),
                          Container(width: 70, height: 80, color: Colors.white),
                          Container(width: 70, height: 80, color: Colors.white),
                        ]),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!;
                final todayPlayers = data['todayPlayers'];
                final todayOrderTotal = data['todayOrderTotal'];
                final paymentReceived = data['paymentReceived'];
                final dues = data['dues'];
                final paymentMethods = data['paymentMethods'];
                final prevPlayers = data['prevPlayers'];
                final prevOrderTotal = data['prevOrderTotal'];
                final prevPaymentReceived = data['prevPaymentReceived'];
                final prevDues = data['prevDues'];
                final playerPercent = data['playerPercent'];
                final orderPercent = data['orderPercent'];
                final paymentPercent = data['paymentPercent'];
                final duesPercent = data['duesPercent'];

                // Calculate maxY including both current and previous data
                double maxY = [
                  todayPlayers.toDouble(),
                  todayOrderTotal,
                  paymentReceived,
                  dues,
                  prevPlayers.toDouble(),
                  prevOrderTotal,
                  prevPaymentReceived,
                  prevDues,
                ].reduce((a, b) => a > b ? a : b) * 1.2;
                if (maxY == 0) maxY = 1.0; // Avoid zero maxY to prevent rendering issues

                return ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 150,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY,
                          barTouchData: BarTouchData(enabled: false),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  switch (value.toInt()) {
                                    case 0:
                                      return const Text('Players', style: TextStyle(fontSize: 12));
                                    case 1:
                                      return const Text('Orders', style: TextStyle(fontSize: 12));
                                    case 2:
                                      return const Text('Received', style: TextStyle(fontSize: 12));
                                    case 3:
                                      return const Text('Dues', style: TextStyle(fontSize: 12));
                                    default:
                                      return const Text('');
                                  }
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const Text('0', style: TextStyle(fontSize: 12));
                                  if (value >= maxY) return const Text('');
                                  return Text(
                                    '${(value / 1000).toStringAsFixed(0)}k',
                                    style: const TextStyle(fontSize: 12),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(show: false),
                          barGroups: [
                            BarChartGroupData(
                              x: 0,
                              barRods: [
                                BarChartRodData(
                                  toY: todayPlayers.toDouble(),
                                  color: const Color(0xFFFF6384),
                                  width: 16,
                                ),
                                BarChartRodData(
                                  toY: prevPlayers.toDouble(),
                                  color: const Color(0xFFFF6384).withOpacity(0.5),
                                  width: 16,
                                ),
                              ],
                            ),
                            BarChartGroupData(
                              x: 1,
                              barRods: [
                                BarChartRodData(
                                  toY: todayOrderTotal,
                                  color: const Color(0xFF36A2EB),
                                  width: 16,
                                ),
                                BarChartRodData(
                                  toY: prevOrderTotal,
                                  color: const Color(0xFF36A2EB).withOpacity(0.5),
                                  width: 16,
                                ),
                              ],
                            ),
                            BarChartGroupData(
                              x: 2,
                              barRods: [
                                BarChartRodData(
                                  toY: paymentReceived,
                                  color: const Color(0xFFFFCE56),
                                  width: 16,
                                ),
                                BarChartRodData(
                                  toY: prevPaymentReceived,
                                  color: const Color(0xFFFFCE56).withOpacity(0.5),
                                  width: 16,
                                ),
                              ],
                            ),
                            BarChartGroupData(
                              x: 3,
                              barRods: [
                                BarChartRodData(
                                  toY: dues,
                                  color: const Color(0xFF4BC0C0),
                                  width: 16,
                                ),
                                BarChartRodData(
                                  toY: prevDues,
                                  color: const Color(0xFF4BC0C0).withOpacity(0.5),
                                  width: 16,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCard('Players', '$todayPlayers', Icons.people, prevPlayers > 0 ? '${playerPercent.toStringAsFixed(1)}%' : ''),
                        _buildCard('Order Total', '৳${todayOrderTotal.toStringAsFixed(0)}', Icons.receipt, prevOrderTotal > 0 ? '${orderPercent.toStringAsFixed(1)}%' : ''),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCard('Payment Received', '৳${paymentReceived.toStringAsFixed(0)}', Icons.payment, prevPaymentReceived > 0 ? '${paymentPercent.toStringAsFixed(1)}%' : ''),
                        _buildCard('Dues', '৳${dues.toStringAsFixed(0)}', Icons.error, prevDues > 0 ? '${duesPercent.toStringAsFixed(1)}%' : ''),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Payment Methods',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPaymentMethodCard('Cash', '৳${paymentMethods['Cash']?.toStringAsFixed(0) ?? '0'}'),
                        _buildPaymentMethodCard('Bkash', '৳${paymentMethods['Bkash']?.toStringAsFixed(0) ?? '0'}'),
                        _buildPaymentMethodCard('Nagad', '৳${paymentMethods['Nagad']?.toStringAsFixed(0) ?? '0'}'),
                        _buildPaymentMethodCard('Bank', '৳${paymentMethods['Bank']?.toStringAsFixed(0) ?? '0'}'),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, String value, IconData icon, String percent) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: Colors.red, size: 30),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (percent.isNotEmpty)
                Text(
                  percent,
                  style: TextStyle(
                    fontSize: 12,
                    color: _getPercentageValue(percent) >= 0 ? Colors.green : Colors.red,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _getPercentageValue(String percentString) {
    try {
      return double.parse(percentString.replaceAll('%', ''));
    } catch (e) {
      return 0.0;
    }
  }

  Widget _buildPaymentMethodCard(String method, String amount) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(method, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Text(amount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}