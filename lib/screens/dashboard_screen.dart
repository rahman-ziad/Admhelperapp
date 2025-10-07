import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
  DateTime? _customStartDate, _customEndDate;
  TimeOfDay _customStartTime = const TimeOfDay(hour: 2, minute: 0);
  TimeOfDay _customEndTime = const TimeOfDay(hour: 2, minute: 0);

  Future<void> _showDateRangeFilter() async {
    DateTime? startDate = _customStartDate ?? DateTime.now();
    DateTime? endDate = _customEndDate ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay startTime = _customStartTime;
    TimeOfDay endTime = _customEndTime;

    final result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Date Range'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Start: ${DateFormat('dd/MM/yyyy').format(startDate!)}')),
                    IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now().subtract(const Duration(days: 1)),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => startDate = picked);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Text('End: ${DateFormat('dd/MM/yyyy').format(endDate!)}')),
                    IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => endDate = picked);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Text('Start Time: ${_formatTimeWithAMPM(startTime)}')),
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: startTime);
                        if (picked != null) setState(() => startTime = picked);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Text('End Time: ${_formatTimeWithAMPM(endTime)}')),
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: endTime);
                        if (picked != null) setState(() => endTime = picked);
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (startDate != null && endDate != null) {
                setState(() {
                  _customStartDate = DateTime(
                    startDate!.year,
                    startDate!.month,
                    startDate!.day,
                    startTime.hour,
                    startTime.minute,
                  );
                  _customEndDate = DateTime(
                    endDate!.year,
                    endDate!.month,
                    endDate!.day + 1,
                    endTime.hour,
                    endTime.minute,
                  );
                  _customStartTime = startTime;
                  _customEndTime = endTime;
                  _selectedPeriod = 'Custom';
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Apply'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatTimeWithAMPM(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<Map<String, dynamic>> _getReportData(String period) async {
    final now = DateTime.now();
    DateTime start, end, prevStart, prevEnd;

    // Set time ranges based on the selected period
    if (period == 'Custom' && _customStartDate != null && _customEndDate != null) {
      start = _customStartDate!;
      end = _customEndDate!;
      prevStart = start.subtract(Duration(days: end.difference(start).inDays + 1));
      prevEnd = start.subtract(const Duration(days: 1));
    } else if (period == 'Today') {
      start = DateTime(now.year, now.month, now.day, 2, 0, 0);
      end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
      if (now.hour < 2) {
        start = DateTime(now.year, now.month, now.day - 1, 2, 0, 0);
        end = DateTime(now.year, now.month, now.day, 2, 0, 0);
      }
      prevStart = DateTime(now.year, now.month, now.day - 1, 2, 0, 0);
      prevEnd = DateTime(now.year, now.month, now.day, 2, 0, 0);
    } else if (period == '7 Days') {
      start = DateTime(now.year, now.month, now.day - 6, 2, 0, 0);
      end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
      if (now.hour < 2) {
        start = DateTime(now.year, now.month, now.day - 7, 2, 0, 0);
        end = DateTime(now.year, now.month, now.day, 2, 0, 0);
      }
      prevStart = DateTime(now.year, now.month, now.day - 13, 2, 0, 0);
      prevEnd = DateTime(now.year, now.month, now.day - 7, 2, 0, 0);
    } else {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 1);
      prevStart = DateTime(now.year, now.month - 1, 1);
      prevEnd = DateTime(now.year, now.month, 1);
    }

    // Query invoices for current period (for metrics)
    final currentInvoicesQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .get();

    // Query invoices for previous period (for metrics)
    final prevInvoicesQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('date', isLessThan: Timestamp.fromDate(prevEnd))
        .get();

    // Query invoices with payment activity in current period
    final currentPaymentsQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('paymentUpdateTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('paymentUpdateTimestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    // Query invoices with payment activity in previous period
    final prevPaymentsQuery = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .where('paymentUpdateTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('paymentUpdateTimestamp', isLessThan: Timestamp.fromDate(prevEnd))
        .get();

    // Execute queries
    final results = await Future.wait([currentInvoicesQuery, prevInvoicesQuery, currentPaymentsQuery, prevPaymentsQuery]);
    final currentInvoicesSnapshot = results[0];
    final prevInvoicesSnapshot = results[1];
    final currentPaymentsSnapshot = results[2];
    final prevPaymentsSnapshot = results[3];

    // Initialize metrics
    int todayOrderGrossTotal = 0;
    int todayOrderNetTotal = 0;
    int todayDiscountedAmount = 0;
    int todayRoundedUpAmount = 0;
    int todayDues = 0;
    double paymentReceived = 0.0;
    Set<String> uniquePlayers = {};
    Map<String, double> paymentMethods = {
      'Cash': 0.0,
      'Bkash': 0.0,
      'Nagad': 0.0,
      'Bank': 0.0,
      'Stars': 0.0, // Added to handle Stars payments
    };

    // Calculate metrics for current period invoices
    for (var doc in currentInvoicesSnapshot.docs) {
      final data = doc.data();
      final playerId = data['player_id'] as String?;
      final grossTotal = (data['gross_total'] as num?)?.toInt() ?? 0;
      final netTotal = (data['net_total'] as num?)?.toInt() ?? 0;
      final paidAmount = (data['paid_amount'] as num?)?.toInt() ?? 0;
      final discountAmount = (data['discount_amount'] as num?)?.toInt() ?? 0;
      final roundUpAmount = (data['round_up'] as num?)?.toInt() ?? 0;
      final status = data['status'] as String? ?? 'unpaid';

      if (playerId != null && !uniquePlayers.contains(playerId)) {
        uniquePlayers.add(playerId);
      }
      todayOrderGrossTotal += grossTotal;
      todayOrderNetTotal += netTotal;
      todayDiscountedAmount += discountAmount;
      todayRoundedUpAmount += roundUpAmount;
      if (status == 'due' || status == 'unpaid') {
        todayDues += netTotal - paidAmount;
      }
    }

    // Calculate paymentReceived and paymentMethods for current period
    for (var doc in currentPaymentsSnapshot.docs) {
      final data = doc.data();
      final payments = (data['payments'] as List<dynamic>?) ?? [];
      for (var payment in payments) {
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
        final method = payment['method'] as String?;
        final timestamp = payment['timestamp'] as Timestamp?;
        if (method != null &&
            method != 'RoundUp' && // Exclude RoundUp as it’s not a payment method
            paymentMethods.containsKey(method) &&
            timestamp != null &&
            timestamp.toDate().isAfter(start) &&
            timestamp.toDate().isBefore(end)) {
          paymentReceived += amount;
          paymentMethods[method] = (paymentMethods[method] ?? 0.0) + amount;
        }
      }
    }

    // Calculate metrics for previous period invoices
    int prevOrderGrossTotal = 0;
    int prevOrderNetTotal = 0;
    int prevDiscountedAmount = 0;
    int prevRoundedUpAmount = 0;
    int prevDues = 0;
    double prevPaymentReceived = 0.0;
    Set<String> prevUniquePlayers = {};

    for (var doc in prevInvoicesSnapshot.docs) {
      final data = doc.data();
      final playerId = data['player_id'] as String?;
      final grossTotal = (data['gross_total'] as num?)?.toInt() ?? 0;
      final netTotal = (data['net_total'] as num?)?.toInt() ?? 0;
      final paidAmount = (data['paid_amount'] as num?)?.toInt() ?? 0;
      final discountAmount = (data['discount_amount'] as num?)?.toInt() ?? 0;
      final roundUpAmount = (data['round_up'] as num?)?.toInt() ?? 0;
      final status = data['status'] as String? ?? 'unpaid';

      if (playerId != null && !prevUniquePlayers.contains(playerId)) {
        prevUniquePlayers.add(playerId);
      }
      prevOrderGrossTotal += grossTotal;
      prevOrderNetTotal += netTotal;
      prevDiscountedAmount += discountAmount;
      prevRoundedUpAmount += roundUpAmount;
      if (status == 'due' || status == 'unpaid') {
        prevDues += netTotal - paidAmount;
      }
    }

    // Calculate prevPaymentReceived for previous period
    for (var doc in prevPaymentsSnapshot.docs) {
      final data = doc.data();
      final payments = (data['payments'] as List<dynamic>?) ?? [];
      for (var payment in payments) {
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
        final method = payment['method'] as String?;
        final timestamp = payment['timestamp'] as Timestamp?;
        if (method != null &&
            method != 'RoundUp' && // Exclude RoundUp
            paymentMethods.containsKey(method) &&
            timestamp != null &&
            timestamp.toDate().isAfter(prevStart) &&
            timestamp.toDate().isBefore(prevEnd)) {
          prevPaymentReceived += amount;
        }
      }
    }

    // Calculate percentage changes
    double orderGrossPercent = prevOrderGrossTotal > 0 ? ((todayOrderGrossTotal - prevOrderGrossTotal) / prevOrderGrossTotal * 100) : 0.0;
    double orderNetPercent = prevOrderNetTotal > 0 ? ((todayOrderNetTotal - prevOrderNetTotal) / prevOrderNetTotal * 100) : 0.0;
    double paymentPercent = prevPaymentReceived > 0 ? ((paymentReceived - prevPaymentReceived) / prevPaymentReceived * 100) : 0.0;
    double duesPercent = prevDues > 0 ? ((todayDues - prevDues) / prevDues * 100) : 0.0;
    double discountedPercent = prevDiscountedAmount > 0 ? ((todayDiscountedAmount - prevDiscountedAmount) / prevDiscountedAmount * 100) : 0.0;
    double roundedUpPercent = prevRoundedUpAmount > 0 ? ((todayRoundedUpAmount - prevRoundedUpAmount) / prevRoundedUpAmount * 100) : 0.0;

    // Determine maxY for the bar chart
    double maxY = [
      todayOrderGrossTotal.toDouble(),
      todayOrderNetTotal.toDouble(),
      paymentReceived,
      todayDues.toDouble(),
      prevOrderGrossTotal.toDouble(),
      prevOrderNetTotal.toDouble(),
      prevPaymentReceived,
      prevDues.toDouble(),
    ].reduce((a, b) => a > b ? a : b) * 1.2;
    if (maxY == 0) maxY = 1.0;

    return {
      'todayOrderGrossTotal': todayOrderGrossTotal.toDouble(),
      'todayOrderNetTotal': todayOrderNetTotal.toDouble(),
      'paymentReceived': paymentReceived,
      'dues': todayDues.toDouble(),
      'discountedAmount': todayDiscountedAmount.toDouble(),
      'roundedUpAmount': todayRoundedUpAmount.toDouble(),
      'paymentMethods': paymentMethods,
      'prevOrderGrossTotal': prevOrderGrossTotal.toDouble(),
      'prevOrderNetTotal': prevOrderNetTotal.toDouble(),
      'prevPaymentReceived': prevPaymentReceived,
      'prevDues': prevDues.toDouble(),
      'prevDiscountedAmount': prevDiscountedAmount.toDouble(),
      'prevRoundedUpAmount': prevRoundedUpAmount.toDouble(),
      'orderGrossPercent': orderGrossPercent,
      'orderNetPercent': orderNetPercent,
      'paymentPercent': paymentPercent,
      'duesPercent': duesPercent,
      'discountedPercent': discountedPercent,
      'roundedUpPercent': roundedUpPercent,
      'maxY': maxY,
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
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.91,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _periods.map((period) {
                      return Flexible(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPeriod = period;
                              _customStartDate = null;
                              _customEndDate = null;
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
              ],
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
                          Container(width: MediaQuery.of(context).size.width / 2 - 16, height: 100, color: Colors.white),
                          Container(width: MediaQuery.of(context).size.width / 2 - 16, height: 100, color: Colors.white),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Container(width: MediaQuery.of(context).size.width / 2 - 16, height: 100, color: Colors.white),
                          Container(width: MediaQuery.of(context).size.width / 2 - 16, height: 100, color: Colors.white),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Container(width: MediaQuery.of(context).size.width / 4 - 12, height: 80, color: Colors.white),
                          Container(width: MediaQuery.of(context).size.width / 4 - 12, height: 80, color: Colors.white),
                          Container(width: MediaQuery.of(context).size.width / 4 - 12, height: 80, color: Colors.white),
                          Container(width: MediaQuery.of(context).size.width / 4 - 12, height: 80, color: Colors.white),
                        ]),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!;
                final todayOrderGrossTotal = data['todayOrderGrossTotal'];
                final todayOrderNetTotal = data['todayOrderNetTotal'];
                final paymentReceived = data['paymentReceived'];
                final dues = data['dues'];
                final discountedAmount = data['discountedAmount'];
                final roundedUpAmount = data['roundedUpAmount'];
                final paymentMethods = data['paymentMethods'];
                final prevOrderGrossTotal = data['prevOrderGrossTotal'];
                final prevOrderNetTotal = data['prevOrderNetTotal'];
                final prevPaymentReceived = data['prevPaymentReceived'];
                final prevDues = data['prevDues'];
                final prevDiscountedAmount = data['prevDiscountedAmount'];
                final prevRoundedUpAmount = data['prevRoundedUpAmount'];
                final orderGrossPercent = data['orderGrossPercent'];
                final orderNetPercent = data['orderNetPercent'];
                final paymentPercent = data['paymentPercent'];
                final duesPercent = data['duesPercent'];
                final discountedPercent = data['discountedPercent'];
                final roundedUpPercent = data['roundedUpPercent'];
                final maxY = data['maxY'];

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
                return const Text('Gross Orders', style: TextStyle(fontSize: 12));
                case 1:
                return const Text('Net Orders', style: TextStyle(fontSize: 12));
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
                toY: todayOrderGrossTotal,
                color: const Color(0xFFFF6384),
                width: 16,
                ),
                BarChartRodData(
                toY: prevOrderGrossTotal,
                color: const Color(0xFFFF6384).withOpacity(0.5),
                width: 16,
                ),
                ],
                ),
                BarChartGroupData(
                x: 1,
                barRods: [
                BarChartRodData(
                toY: todayOrderNetTotal,
                color: const Color(0xFF36A2EB),
                width: 16,
                ),
                BarChartRodData(
                toY: prevOrderNetTotal,
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
                SizedBox(
                width: double.infinity,
                child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(
                child: _buildCard('Order Gross Total', '৳${todayOrderGrossTotal.toStringAsFixed(0)}', Icons.receipt, prevOrderGrossTotal > 0 ? '${orderGrossPercent.toStringAsFixed(1)}%' : ''),
                ),
                Expanded(
                child: _buildCard('Order Net Total', '৳${todayOrderNetTotal.toStringAsFixed(0)}', Icons.receipt, prevOrderNetTotal > 0 ? '${orderNetPercent.toStringAsFixed(1)}%' : ''),
                ),],
                ),
                ),
                ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                width: double.infinity,
                child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(
                child: _buildCard('Payment Received', '৳${paymentReceived.toStringAsFixed(0)}', Icons.payment, prevPaymentReceived > 0 ? '${paymentPercent.toStringAsFixed(1)}%' : ''),
                ),
                Expanded(
                child: _buildCard('Dues', '৳${dues.toStringAsFixed(0)}', Icons.error, prevDues > 0 ? '${duesPercent.toStringAsFixed(1)}%' : ''),
                ),],
                ),
                ),
                ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                width: double.infinity,
                child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(
                child: _buildCard('Discounted Amount', '-৳${discountedAmount.toStringAsFixed(0)}', Icons.discount, prevDiscountedAmount > 0 ? '${discountedPercent.toStringAsFixed(1)}%' : ''),
                ),
                Expanded(
                child: _buildCard('Rounded Up ', '-৳${roundedUpAmount.toStringAsFixed(0)}', Icons.adjust, prevRoundedUpAmount > 0 ? '${roundedUpPercent.toStringAsFixed(1)}%' : ''),
                ),],
                ),
                ),
                ),
                ),
                const SizedBox(height: 16),
                const Text(
                'Payment Methods',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                width: double.infinity,
                child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                children: [
                Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(child: _buildPaymentMethodCard('Cash', '৳${paymentMethods['Cash']?.toStringAsFixed(0) ?? '0'}')),
                Expanded(child: _buildPaymentMethodCard('Bkash', '৳${paymentMethods['Bkash']?.toStringAsFixed(0) ?? '0'}')),
                ],
                ),
                const SizedBox(height: 16),
                Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(child: _buildPaymentMethodCard('Nagad', '৳${paymentMethods['Nagad']?.toStringAsFixed(0) ?? '0'}')),
                Expanded(child: _buildPaymentMethodCard('Bank', '৳${paymentMethods['Bank']?.toStringAsFixed(0) ?? '0'}')),
                ],
                ),
                ],
                ),
                ),
                ),
                ),
                ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showDateRangeFilter,
        child: const Icon(Icons.filter_list),
        backgroundColor: Colors.red,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildCard(String title, String value, IconData icon, String percent) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 125,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(method, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(amount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}