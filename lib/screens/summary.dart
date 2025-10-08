import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class SummaryScreen extends ConsumerStatefulWidget {
  final String clubId;

  const SummaryScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  String _selectedPeriod = 'Today';
  final List<String> _periods = ['Today', '7 Days', 'Monthly', 'Custom'];
  DateTime? _customStartDate, _customEndDate;
  TimeOfDay _customStartTime = const TimeOfDay(hour: 2, minute: 0);
  TimeOfDay _customEndTime = const TimeOfDay(hour: 2, minute: 0);
  Map<String, Map<String, dynamic>> playerDetails = {};

  @override
  void initState() {
    super.initState();
    _fetchPlayerDetails();
  }

  Future<void> _fetchPlayerDetails() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      for (var doc in playersSnapshot.docs) {
        playerDetails[doc.id] = {
          'name': doc.data()['name'] ?? '',
        };
      }
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading player details: $e')),
      );
    }
  }

  Future<void> _showDateRangeFilter() async {
    DateTime? startDate = _customStartDate ?? DateTime.now();
    DateTime? endDate = _customEndDate ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay startTime = _customStartTime;
    TimeOfDay endTime = _customEndTime;

    await showDialog(
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

  Future<void> _generateAndUploadPDF(List<Map<String, dynamic>> tableData, int totalBill, int totalPaid, int totalDiscount, int totalDues) async {
    try {
      // Sort tableData by total_bill in descending order
      tableData.sort((a, b) => (b['total_bill'] as int).compareTo(a['total_bill'] as int));

      // Create a new PDF document
      final syncfusion.PdfDocument document = syncfusion.PdfDocument();
      final now = DateTime.now();
      final dateLabel = _selectedPeriod == 'Custom' && _customStartDate != null && _customEndDate != null
          ? '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}'
          : _selectedPeriod == 'Today'
          ? 'Today (${DateFormat('MMM d, yyyy').format(DateTime(now.year, now.month, now.day, 2))})'
          : _selectedPeriod == '7 Days'
          ? 'Last 7 Days'
          : 'This Month';

      // Add a page
      final syncfusion.PdfPage page = document.pages.add();
      final syncfusion.PdfGraphics graphics = page.graphics;
      final syncfusion.PdfFont titleFont = syncfusion.PdfStandardFont(syncfusion.PdfFontFamily.helvetica, 16, style: syncfusion.PdfFontStyle.bold);
      final syncfusion.PdfFont textFont = syncfusion.PdfStandardFont(syncfusion.PdfFontFamily.helvetica, 10);
      final syncfusion.PdfFont totalFont = syncfusion.PdfStandardFont(syncfusion.PdfFontFamily.helvetica, 10, style: syncfusion.PdfFontStyle.bold);

      // Draw title and period
      graphics.drawString('Summary Report', titleFont, bounds: const Rect.fromLTWH(0, 0, 500, 20));
      graphics.drawString('Period: $dateLabel', textFont, bounds: const Rect.fromLTWH(0, 25, 500, 20));

      // Create a grid
      final syncfusion.PdfGrid grid = syncfusion.PdfGrid();
      grid.columns.add(count: 5); // Increased to 5 for Dues column
      grid.headers.add(1);
      final syncfusion.PdfGridRow header = grid.headers[0];
      header.cells[0].value = 'Name';
      header.cells[1].value = 'Total Bill';
      header.cells[2].value = 'Paid Amount';
      header.cells[3].value = 'Discount';
      header.cells[4].value = 'Dues';
      header.style = syncfusion.PdfGridRowStyle(
        font: totalFont,
        backgroundBrush: syncfusion.PdfSolidBrush(syncfusion.PdfColor(224, 224, 224)),
      );

      // Add data rows
      for (final row in tableData) {
        final syncfusion.PdfGridRow gridRow = grid.rows.add();
        gridRow.cells[0].value = row['name'];
        gridRow.cells[1].value = 'Tk ${row['total_bill']}';
        gridRow.cells[2].value = 'Tk ${row['paid_amount']}';
        gridRow.cells[3].value = 'Tk ${row['discount']}';
        gridRow.cells[4].value = 'Tk ${row['dues']}';
        gridRow.style = syncfusion.PdfGridRowStyle(font: textFont);
      }

      // Add total row
      final syncfusion.PdfGridRow totalRow = grid.rows.add();
      totalRow.cells[0].value = 'Total';
      totalRow.cells[1].value = 'Tk $totalBill';
      totalRow.cells[2].value = 'Tk $totalPaid';
      totalRow.cells[3].value = 'Tk $totalDiscount';
      totalRow.cells[4].value = 'Tk $totalDues';
      totalRow.style = syncfusion.PdfGridRowStyle(
        font: totalFont,
        backgroundBrush: syncfusion.PdfSolidBrush(syncfusion.PdfColor(224, 224, 224)),
      );

      // Set column widths
      grid.columns[0].width = 180; // Adjusted to accommodate new column
      grid.columns[1].width = 90;
      grid.columns[2].width = 90;
      grid.columns[3].width = 90;
      grid.columns[4].width = 90;

      // Draw grid with automatic pagination
      grid.draw(page: page, bounds: const Rect.fromLTWH(0, 50, 0, 0));

      // Save PDF to file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/summary_${widget.clubId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await document.save());

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('reports/summary_${widget.clubId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      // Show AlertDialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('PDF Generated'),
          content: Text('PDF uploaded successfully. Link: $downloadUrl'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: downloadUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard')),
                );
                Navigator.pop(context);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () async {
                final url = Uri.parse(downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not launch URL')),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Open Link'),
            ),
          ],
        ),
      );

      document.dispose();
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to generate or upload PDF: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.clubId));
    final now = DateTime.now();
    String dateLabel;
    if (_selectedPeriod == 'Custom' && _customStartDate != null && _customEndDate != null) {
      dateLabel = '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}';
    } else if (_selectedPeriod == 'Today') {
      final todayStart = DateTime(now.year, now.month, now.day, 2);
      dateLabel = 'Today (${DateFormat('MMM d, yyyy').format(todayStart)})';
    } else if (_selectedPeriod == '7 Days') {
      dateLabel = 'Last 7 Days';
    } else {
      dateLabel = 'This Month';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              final invoices = await invoicesAsync.when(
                data: (data) => data,
                loading: () => [],
                error: (_, __) => [],
              );
              if (invoices.isEmpty) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('No Data'),
                    content: const Text('No invoices to generate PDF'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                return;
              }

              // Calculate date range
              DateTime start, end;
              if (_selectedPeriod == 'Custom' && _customStartDate != null && _customEndDate != null) {
                start = _customStartDate!;
                end = _customEndDate!;
              } else if (_selectedPeriod == 'Today') {
                start = DateTime(now.year, now.month, now.day, 2, 0, 0);
                end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
                if (now.hour < 2) {
                  start = DateTime(now.year, now.month, now.day - 1, 2, 0, 0);
                  end = DateTime(now.year, now.month, now.day, 2, 0, 0);
                }
              } else if (_selectedPeriod == '7 Days') {
                start = DateTime(now.year, now.month, now.day - 6, 2, 0, 0);
                end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
                if (now.hour < 2) {
                  start = DateTime(now.year, now.month, now.day - 7, 2, 0, 0);
                  end = DateTime(now.year, now.month, now.day, 2, 0, 0);
                }
              } else {
                start = DateTime(now.year, now.month, 1);
                end = DateTime(now.year, now.month + 1, 1);
              }

              // Filter invoices
              List<Map<String, dynamic>> filteredInvoices = invoices.where((invoice) {
                final invoiceDate = (invoice['date'] as Timestamp?)?.toDate();
                final paymentUpdateTimestamp = (invoice['paymentUpdateTimestamp'] as Timestamp?)?.toDate();
                final payments = (invoice['payments'] as List<dynamic>?) ?? [];

                // Include invoice if its date is within the period
                bool isDateInRange = invoiceDate != null && invoiceDate.isAfter(start) && invoiceDate.isBefore(end);

                // Include invoice if it has a payment within the period
                bool hasPaymentInRange = payments.any((payment) {
                  final paymentTimestamp = (payment['timestamp'] as Timestamp?)?.toDate();
                  return paymentTimestamp != null &&
                      paymentTimestamp.isAfter(start) &&
                      paymentTimestamp.isBefore(end) &&
                      payment['method'] != 'RoundUp';
                });

                // Include invoice if paymentUpdateTimestamp is within the period
                bool hasPaymentUpdateInRange = paymentUpdateTimestamp != null &&
                    paymentUpdateTimestamp.isAfter(start) &&
                    paymentUpdateTimestamp.isBefore(end);

                return isDateInRange || (hasPaymentUpdateInRange && hasPaymentInRange);
              }).toList().cast<Map<String, dynamic>>();

              // Aggregate by player
              Map<String, Map<String, dynamic>> playerAggregates = {};
              for (var invoice in filteredInvoices) {
                final playerId = invoice['player_id'] as String?;
                if (playerId == null) continue;

                final playerName = playerDetails[playerId]?['name'] ?? 'Unknown';
                final grossTotal = (invoice['gross_total'] as num?)?.toInt() ?? 0;
                final netTotal = (invoice['net_total'] as num?)?.toInt() ?? 0;
                final paidAmount = (invoice['paid_amount'] as num?)?.toInt() ?? 0;
                final discount = grossTotal - netTotal;
                final status = invoice['status'] as String? ?? 'unpaid';
                final dues = (status == 'due' || status == 'unpaid') ? (netTotal - paidAmount) : 0;

                if (!playerAggregates.containsKey(playerId)) {
                  playerAggregates[playerId] = {
                    'name': playerName,
                    'total_bill': 0,
                    'paid_amount': 0,
                    'discount': 0,
                    'dues': 0,
                  };
                }

                // Add invoice metrics only if it matches date criteria or has relevant payments
                final invoiceDate = (invoice['date'] as Timestamp?)?.toDate();
                final payments = (invoice['payments'] as List<dynamic>?) ?? [];
                bool includeInvoice = invoiceDate != null && invoiceDate.isAfter(start) && invoiceDate.isBefore(end);

                if (!includeInvoice) {
                  bool hasRelevantPayment = payments.any((payment) {
                    final paymentTimestamp = (payment['timestamp'] as Timestamp?)?.toDate();
                    return paymentTimestamp != null &&
                        paymentTimestamp.isAfter(start) &&
                        paymentTimestamp.isBefore(end) &&
                        payment['method'] != 'RoundUp';
                  });
                  includeInvoice = hasRelevantPayment;
                }

                if (includeInvoice) {
                  playerAggregates[playerId]!['total_bill'] += netTotal;
                  playerAggregates[playerId]!['paid_amount'] += paidAmount;
                  playerAggregates[playerId]!['discount'] += discount;
                  playerAggregates[playerId]!['dues'] += dues;
                }
              }

              // Convert aggregates to tableData
              int totalBill = 0, totalPaid = 0, totalDiscount = 0, totalDues = 0;
              List<Map<String, dynamic>> tableData = playerAggregates.values.map((data) {
                totalBill += data['total_bill'] as int;
                totalPaid += data['paid_amount'] as int;
                totalDiscount += data['discount'] as int;
                totalDues += data['dues'] as int;
                return {
                  'name': data['name'],
                  'total_bill': data['total_bill'],
                  'paid_amount': data['paid_amount'],
                  'discount': data['discount'],
                  'dues': data['dues'],
                };
              }).toList();

              await _generateAndUploadPDF(tableData, totalBill, totalPaid, totalDiscount, totalDues);
            },
            tooltip: 'Generate PDF',
          ),
        ],
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _showDateRangeFilter,
                  icon: const Icon(Icons.filter_alt),
                  label: const Text('Filter'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: invoicesAsync.when(
              data: (invoices) {
                if (invoices.isEmpty) {
                  return const Center(child: Text('No invoices available'));
                }

                // Calculate date range
                final now = DateTime.now();
                DateTime start, end;
                if (_selectedPeriod == 'Custom' && _customStartDate != null && _customEndDate != null) {
                  start = _customStartDate!;
                  end = _customEndDate!;
                } else if (_selectedPeriod == 'Today') {
                  start = DateTime(now.year, now.month, now.day, 2, 0, 0);
                  end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
                  if (now.hour < 2) {
                    start = DateTime(now.year, now.month, now.day - 1, 2, 0, 0);
                    end = DateTime(now.year, now.month, now.day, 2, 0, 0);
                  }
                } else if (_selectedPeriod == '7 Days') {
                  start = DateTime(now.year, now.month, now.day - 6, 2, 0, 0);
                  end = DateTime(now.year, now.month, now.day + 1, 2, 0, 0);
                  if (now.hour < 2) {
                    start = DateTime(now.year, now.month, now.day - 7, 2, 0, 0);
                    end = DateTime(now.year, now.month, now.day, 2, 0, 0);
                  }
                } else {
                  start = DateTime(now.year, now.month, 1);
                  end = DateTime(now.year, now.month + 1, 1);
                }

                // Filter invoices
                List<Map<String, dynamic>> filteredInvoices = invoices.where((invoice) {
                  final invoiceDate = (invoice['date'] as Timestamp?)?.toDate();
                  final paymentUpdateTimestamp = (invoice['paymentUpdateTimestamp'] as Timestamp?)?.toDate();
                  final payments = (invoice['payments'] as List<dynamic>?) ?? [];

                  // Include invoice if its date is within the period
                  bool isDateInRange = invoiceDate != null && invoiceDate.isAfter(start) && invoiceDate.isBefore(end);

                  // Include invoice if it has a payment within the period
                  bool hasPaymentInRange = payments.any((payment) {
                    final paymentTimestamp = (payment['timestamp'] as Timestamp?)?.toDate();
                    return paymentTimestamp != null &&
                        paymentTimestamp.isAfter(start) &&
                        paymentTimestamp.isBefore(end) &&
                        payment['method'] != 'RoundUp';
                  });

                  // Include invoice if paymentUpdateTimestamp is within the period
                  bool hasPaymentUpdateInRange = paymentUpdateTimestamp != null &&
                      paymentUpdateTimestamp.isAfter(start) &&
                      paymentUpdateTimestamp.isBefore(end);

                  return isDateInRange || (hasPaymentUpdateInRange && hasPaymentInRange);
                }).toList().cast<Map<String, dynamic>>();

                // Aggregate by player
                Map<String, Map<String, dynamic>> playerAggregates = {};
                for (var invoice in filteredInvoices) {
                  final playerId = invoice['player_id'] as String?;
                  if (playerId == null) continue;

                  final playerName = playerDetails[playerId]?['name'] ?? 'Unknown';
                  final grossTotal = (invoice['gross_total'] as num?)?.toInt() ?? 0;
                  final netTotal = (invoice['net_total'] as num?)?.toInt() ?? 0;
                  final paidAmount = (invoice['paid_amount'] as num?)?.toInt() ?? 0;
                  final discount = grossTotal - netTotal;
                  final status = invoice['status'] as String? ?? 'unpaid';
                  final dues = (status == 'due' || status == 'unpaid') ? (netTotal - paidAmount) : 0;

                  if (!playerAggregates.containsKey(playerId)) {
                    playerAggregates[playerId] = {
                      'name': playerName,
                      'total_bill': 0,
                      'paid_amount': 0,
                      'discount': 0,
                      'dues': 0,
                    };
                  }

                  // Add invoice metrics only if it matches date criteria or has relevant payments
                  final invoiceDate = (invoice['date'] as Timestamp?)?.toDate();
                  final payments = (invoice['payments'] as List<dynamic>?) ?? [];
                  bool includeInvoice = invoiceDate != null && invoiceDate.isAfter(start) && invoiceDate.isBefore(end);

                  if (!includeInvoice) {
                    bool hasRelevantPayment = payments.any((payment) {
                      final paymentTimestamp = (payment['timestamp'] as Timestamp?)?.toDate();
                      return paymentTimestamp != null &&
                          paymentTimestamp.isAfter(start) &&
                          paymentTimestamp.isBefore(end) &&
                          payment['method'] != 'RoundUp';
                    });
                    includeInvoice = hasRelevantPayment;
                  }

                  if (includeInvoice) {
                    playerAggregates[playerId]!['total_bill'] += netTotal;
                    playerAggregates[playerId]!['paid_amount'] += paidAmount;
                    playerAggregates[playerId]!['discount'] += discount;
                    playerAggregates[playerId]!['dues'] += dues;
                  }
                }

                // Convert aggregates to tableData
                int totalBill = 0, totalPaid = 0, totalDiscount = 0, totalDues = 0;
                List<Map<String, dynamic>> tableData = playerAggregates.values.map((data) {
                  totalBill += data['total_bill'] as int;
                  totalPaid += data['paid_amount'] as int;
                  totalDiscount += data['discount'] as int;
                  totalDues += data['dues'] as int;
                  return {
                    'name': data['name'],
                    'total_bill': data['total_bill'],
                    'paid_amount': data['paid_amount'],
                    'discount': data['discount'],
                    'dues': data['dues'],
                  };
                }).toList();

                // Sort tableData by total_bill in descending order
                tableData.sort((a, b) => (b['total_bill'] as int).compareTo(a['total_bill'] as int));

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Table(
                      border: TableBorder.all(),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1),
                        4: FlexColumnWidth(1), // Added for Dues
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey[200]),
                          children: [
                            _buildTableCell('Name', isHeader: true),
                            _buildTableCell('Total Bill', isHeader: true),
                            _buildTableCell('Paid Amount', isHeader: true),
                            _buildTableCell('Discount', isHeader: true),
                            _buildTableCell('Dues', isHeader: true),
                          ],
                        ),
                        ...tableData.map((row) => TableRow(
                          children: [
                            _buildTableCell(row['name']),
                            _buildTableCell('৳${row['total_bill']}'),
                            _buildTableCell('৳${row['paid_amount']}'),
                            _buildTableCell('৳${row['discount']}'),
                            _buildTableCell('৳${row['dues']}'),
                          ],
                        )),
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey[200]),
                          children: [
                            _buildTableCell('Total', isHeader: true),
                            _buildTableCell('৳$totalBill', isHeader: true),
                            _buildTableCell('৳$totalPaid', isHeader: true),
                            _buildTableCell('৳$totalDiscount', isHeader: true),
                            _buildTableCell('৳$totalDues', isHeader: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// Reusing the same provider from InvoiceScreen
final invoicesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
      (ref, clubId) {
    return FirebaseFirestore.instance
        .collection('clubs')
        .doc(clubId)
        .collection('invoices')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  },
);