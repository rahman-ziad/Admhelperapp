import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shimmer_animation/shimmer_animation.dart';

class InvoiceScreen extends ConsumerStatefulWidget {
  final String clubId;

  const InvoiceScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  ConsumerState<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends ConsumerState<InvoiceScreen> {
  String _searchQuery = '';
  String _statusFilter = 'All'; // All, Due, Unpaid
  String _dateFilter = 'All'; // All, Today, Last 7 Days
  final Map<String, String> playerPhotos = {};
  final Map<String, Map<String, dynamic>> playerDetails = {};

  @override
  void initState() {
    super.initState();
    _fetchPlayerDetails();
  }

  Future<void> _fetchPlayerDetails() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      for (var doc in playersSnapshot.docs) {
        playerPhotos[doc.id] = doc.data()['image_url'] ?? '';
        playerDetails[doc.id] = {
          'id': doc.id,
          'name': doc.data()['name'] ?? '',
          'ign': doc.data()['in_game_name'] ?? '',
          'phone_number': doc.data()['phone_number'] ?? '',
        };
      }
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading player details: $e')),
      );
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempDateFilter = _dateFilter;

        return AlertDialog(
          title: const Text('Filter Invoices by Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: tempDateFilter,
                isExpanded: true,
                items: ['All', 'Today', 'Last 7 Days']
                    .map((date) => DropdownMenuItem(
                  value: date,
                  child: Text(date),
                ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    tempDateFilter = value!;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _dateFilter = tempDateFilter;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.clubId));
    return Scaffold(
      body: invoicesAsync.when(
        data: (invoices) {
          if (invoices.isEmpty) {
            return const Center(child: Text('No invoices available'));
          }

          List<Map<String, dynamic>> filteredInvoices = invoices.where((invoice) {
            final playerId = invoice['player_id'] as String?;
            final player = playerDetails[playerId] ?? {};
            final playerName = (player['name'] ?? '').toString().toLowerCase();
            final playerIGN = (player['in_game_name'] ?? '').toString().toLowerCase();
            final playerPhone = (player['phone_number'] ?? '').toString().toLowerCase();
            final status = (invoice['status'] ?? '').toString().toLowerCase();
            final invoiceDate = (invoice['date'] as Timestamp?)?.toDate();

            final query = _searchQuery.toLowerCase();
            final matchSearch = playerName.contains(query) ||
                playerIGN.contains(query) ||
                playerPhone.contains(query);

            final matchStatus = _statusFilter == 'All'
                ? true
                : _statusFilter == 'Due'
                ? status == 'due'
                : status == 'unpaid';

            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final last7Days = today.subtract(const Duration(days: 7));
            bool matchDate = true;
            if (_dateFilter != 'All' && invoiceDate != null) {
              if (_dateFilter == 'Today') {
                matchDate = invoiceDate.year == today.year &&
                    invoiceDate.month == today.month &&
                    invoiceDate.day == today.day;
              } else if (_dateFilter == 'Last 7 Days') {
                matchDate = invoiceDate.isAfter(last7Days) || invoiceDate.isAtSameMomentAs(last7Days);
              }
            }

            return matchStatus && matchSearch && matchDate;
          }).toList();

          filteredInvoices.sort((a, b) {
            final dateComparison = (b['date'] as Timestamp).compareTo(a['date'] as Timestamp);
            if (dateComparison != 0) return dateComparison;
            final nameA = (a['player_name'] ?? '').toString().toLowerCase();
            final nameB = (b['player_name'] ?? '').toString().toLowerCase();
            return nameA.compareTo(nameB);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by Name, IGN, or Phone',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: _showFilterDialog,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildFilterButton('All'),
                    _buildFilterButton('Due'),
                    _buildFilterButton('Unpaid'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredInvoices.length,
                  itemBuilder: (_, index) {
                    final invoice = filteredInvoices[index];
                    final playerName = invoice['player_name'] ?? 'Unknown';
                    final status = invoice['status'] ?? 'unknown';
                    final totalAmount = (invoice['total_amount'] ?? 0.0).toDouble();
                    final paidAmount = (invoice['paid_amount'] ?? 0.0).toDouble();
                    final discountAmount = (invoice['discount_amount'] as num?)?.toDouble() ?? 0.0;
                    final discountedTotal = totalAmount - discountAmount;
                    final dueAmount = discountedTotal - paidAmount;
                    final playerId = invoice['player_id'];
                    final photoUrl = playerPhotos[playerId] ?? '';
                    final services = (invoice['services'] as List<dynamic>?) ?? [];
                    final billingMode = services.isNotEmpty
                        ? (services.first['type'] as String?)?.split('_').first ?? 'Unknown'
                        : 'Unknown';
                    final coinsUsed = services.isNotEmpty
                        ? (services.first['details']['coins'] as num?)?.toInt() ?? 0
                        : 0;

                    final nameWords = playerName.split(' ');
                    final truncatedName = nameWords.length > 2
                        ? '${nameWords.take(2).join(' ')}...'
                        : playerName;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(invoice: invoice, clubId: widget.clubId),
                          ),
                        ),
                        child: Container(
                          height: 90,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              photoUrl.isNotEmpty
                                  ? CircleAvatar(
                                radius: 30,
                                backgroundImage: NetworkImage(photoUrl),
                              )
                                  : CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.blue.shade200,
                                child: Text(
                                  playerName.isNotEmpty ? playerName[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            truncatedName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                          ),
                                        ),
                                        if (status == 'paid')
                                          const SizedBox()
                                        else if (status == 'due')
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'DUES',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        else if (status == 'unpaid')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: const Text(
                                                'UNPAID',
                                                style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                    Text(
                                      '${invoice['id'] ?? 'N/A'}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Center(
                                child: Text(
                                  status == 'paid'
                                      ? '৳${paidAmount.toStringAsFixed(0)}'
                                      : '৳${dueAmount.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: status == 'paid'
                                        ? Colors.green
                                        : (status == 'due' ? Colors.red : Colors.orange),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => Shimmer(
          child: Column(
            children: List.generate(5, (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            )),
          ),
        ),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildFilterButton(String title) {
    final bool selected = _statusFilter == title;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = title),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.blue : Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final invoicesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
        (ref, clubId) {
      return FirebaseFirestore.instance
          .collection('clubs')
          .doc(clubId)
          .collection('invoices')
          .orderBy('date', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
    });




class InvoiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String clubId;

  const InvoiceDetailScreen({super.key, required this.invoice, required this.clubId});

  @override
  _InvoiceDetailScreenState createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  String? playerPhotoUrl;
  String playerPhoneNumber = '';
  String playerIGN = '';
  final Map<String, String> foodImages = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    await _fetchPlayerDetails();
    await _fetchFoodImages();
    setState(() => isLoading = false);
  }

  Future<void> _fetchPlayerDetails() async {
    try {
      final playerId = widget.invoice['player_id'] as String?;
      if (playerId != null) {
        final playerDoc = await FirebaseFirestore.instance
            .collection('players')
            .doc(playerId)
            .get();
        if (playerDoc.exists) {
          setState(() {
            playerPhotoUrl = playerDoc.data()?['image_url'] as String?;
            playerPhoneNumber = playerDoc.data()?['phone_number'] as String? ?? 'N/A';
            playerIGN = playerDoc.data()?['in_game_name'] as String? ?? 'N/A';
          });
        }
      }
    } catch (e) {
      print('Error fetching player details: $e');
    }
  }

  Future<void> _fetchFoodImages() async {
    try {
      final services = (widget.invoice['services'] as List<dynamic>?) ?? [];
      for (var service in services) {
        if (service['type'] == 'food') {
          final foodItemId = service['details']['food_item_id'] as String?;
          if (foodItemId != null) {
            final foodDoc = await FirebaseFirestore.instance
                .collection('clubs')
                .doc(widget.clubId)
                .collection('food_items')
                .doc(foodItemId)
                .get();
            if (foodDoc.exists) {
              setState(() {
                foodImages[foodItemId] = foodDoc.data()?['image_url'] as String? ?? '';
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching food images: $e');
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final dateTime = timestamp.toDate();
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final dateTime = timestamp.toDate();
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    final services = (widget.invoice['services'] as List<dynamic>?) ?? [];
    final playerName = widget.invoice['player_name'] as String? ?? 'Unknown';
    final totalAmount = (widget.invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (widget.invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = (widget.invoice['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final roundUpAmount = (widget.invoice['round_up'] as num?)?.toDouble() ?? 0.0;
    final discountedTotal = totalAmount - discountAmount;
    final dueAmount = discountedTotal - paidAmount; // Round-up not included in dues
    final status = widget.invoice['status'] as String? ?? 'unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('sportsstation.'),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: isLoading
          ? Center(
        child: LoadingAnimationWidget.staggeredDotsWave(
          color: Colors.blue,
          size: 50,
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                playerPhotoUrl != null && playerPhotoUrl!.isNotEmpty
                    ? CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(playerPhotoUrl!),
                )
                    : CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade200,
                  child: Text(
                    playerName.isNotEmpty ? playerName[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$playerName ($playerIGN)',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$playerPhoneNumber',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Invoice no ',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            widget.invoice['id'] as String? ?? 'N/A',
                            style: const TextStyle(fontSize: 12, color: Colors.black),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: status == 'unpaid' ? Colors.red : Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        const Text(
                          '৳ ',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          totalAmount.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (discountAmount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Discount: -৳${discountAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 16, color: Colors.green),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Payable: ৳',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            discountedTotal.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                    if (roundUpAmount > 0)
                      Text(
                        'Rounded Up: +৳${roundUpAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 16, color: Colors.orange),
                      ),
                    if (widget.invoice['stars_used'] != null && (widget.invoice['stars_used'] as num).toInt() > 0)
                      Text(
                        'Stars Used: ${(widget.invoice['stars_used'] as num).toInt()}',
                        style: const TextStyle(fontSize: 16, color: Colors.yellow),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(widget.invoice['date'] as Timestamp?),
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      'Paid: ${paidAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    if (dueAmount > 0)
                      Text(
                        'Due: ${dueAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 14, color: Colors.red),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: services.length,
                itemBuilder: (context, index) {
                  final service = services[index];
                  final details = service['details'] as Map<String, dynamic>;
                  final price = details['price'] as double? ?? 0.0;
                  final splitBill = details['split_bill'] as bool? ?? false;

                  if (service['type'] == 'food') {
                    final foodItemId = details['food_item_id'] as String?;
                    final imageUrl = foodImages[foodItemId];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        height: 80,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            imageUrl != null && imageUrl.isNotEmpty
                                ? Image.network(
                              imageUrl,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.fastfood, size: 40),
                            )
                                : const Icon(Icons.fastfood, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${details['food_item_name'] ?? 'Unknown'} (FOOD)',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${details['quantity'] ?? 0} Nos x ${details['price_at_time'] ?? 0} tk',
                                  ),
                                  Text(
                                    _formatTime(details['purchase_time'] as Timestamp?),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '৳ ',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    price.toStringAsFixed(0),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  if (splitBill)
                                    const Text(
                                      ' (Split)',
                                      style: TextStyle(fontSize: 12, color: Colors.blue),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                    );
                  } else {
                    String title = '';
                    String subtitle = '';
                    double calculatedPrice = 0.0;
                    Timestamp? startTime;
                    if (service['type'] == 'pool_hour') {
                      title = 'POOL (HOUR)';
                      final minutes = (details['minutes'] as num?)?.toInt() ?? 0;
                      final rate = (details['rate'] as num?)?.toDouble() ?? 0;
                      subtitle = '$minutes mins x $rate tk';
                      calculatedPrice = minutes * rate;
                      startTime = details['start_time'] as Timestamp?;
                    } else if (service['type'] == 'pool_coin') {
                      title = 'POOL (COIN)';
                      final coins = (details['coins'] as num?)?.toInt() ?? 0;
                      final rate = (details['rate'] as num?)?.toDouble() ?? 0;
                      subtitle = '$coins coin x $rate tk';
                      calculatedPrice = coins * rate;
                      startTime = details['start_time'] as Timestamp?;
                    } else if (service['type'] == 'snooker_hour') {
                      title = 'SNOOKER (HOUR)';
                      final minutes = (details['minutes'] as num?)?.toInt() ?? 0;
                      final rate = (details['rate'] as num?)?.toDouble() ?? 0;
                      subtitle = '$minutes mins x $rate tk';
                      calculatedPrice = minutes * rate;
                      startTime = details['start_time'] as Timestamp?;
                    } else if (service['type'] == 'rental') {
                      title = 'RENTAL';
                      final minutes = (details['minutes'] as num?)?.toInt() ?? 0;
                      subtitle = '$minutes min';
                      calculatedPrice = price > 0 ? price : calculatedPrice;
                      startTime = details['start_time'] as Timestamp?;
                    }
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        height: 80,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.sports, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(subtitle),
                                  Text(
                                    _formatTime(startTime),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '৳ ',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    price > 0 ? price.toStringAsFixed(0) : calculatedPrice.toStringAsFixed(0),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  if (splitBill)
                                    const Text(
                                      ' (Split)',
                                      style: TextStyle(fontSize: 12, color: Colors.blue),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            if (status != 'paid') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvoicePaymentScreen(
                          invoice: widget.invoice,
                          clubId: widget.clubId,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Payment',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.touch_app, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}





class InvoicePaymentScreen extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final String clubId;

  const InvoicePaymentScreen({
    Key? key,
    required this.invoice,
    required this.clubId,
  }) : super(key: key);

  @override
  _InvoicePaymentScreenState createState() => _InvoicePaymentScreenState();
}

class _InvoicePaymentScreenState extends State<InvoicePaymentScreen> {
  double _discountAmount = 0.0;
  List<Map<String, dynamic>> _newPayments = []; // Only new payments for this session
  String? _selectedDiscountCode;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    setState(() => isLoading = true);
    _discountAmount = (widget.invoice['discount_amount'] as num?)?.toDouble() ?? 0.0;
    _selectedDiscountCode = widget.invoice['discount_code'] as String?;
    _newPayments = []; // Start fresh for new payments in this session
    setState(() => isLoading = false);
  }

  Future<void> _showDiscountSheet() async {
    final discountCodes = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('discount_codes')
        .where('is_active', isEqualTo: true)
        .get()
        .then((snapshot) => snapshot.docs.map((doc) => {
      'id': doc.id,
      ...doc.data(),
    }).toList());

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Discount Code',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: discountCodes.length,
                  itemBuilder: (context, index) {
                    final code = discountCodes[index];
                    final appliesToAll = code['applies_to_all'] ?? false;
                    final playerId = widget.invoice['player_id'];
                    final isApplicable = appliesToAll ||
                        (code['assigned_players'] as List<dynamic>?)!.contains(playerId) ??
                        false;
                    if (!isApplicable) return const SizedBox.shrink();
                    return ListTile(
                      title: Text(code['code'] ?? 'Unknown'),
                      subtitle: Text('Discount: ${code['discount_value']}%'),
                      trailing: _selectedDiscountCode == code['id']
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedDiscountCode = code['id'];
                          _discountAmount = (widget.invoice['total_amount'] as num? ?? 0) *
                              (code['discount_value'] as num? ?? 0) /
                              100;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                    setState(() => isLoading = true);
                    Navigator.pop(context);
                    setState(() => isLoading = false);
                  },
                  child: isLoading
                      ? LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.red,
                    size: 24,
                  )
                      : const Text('Apply', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showPaymentBottomSheet(String method, {int? index}) {
    final controller = TextEditingController();
    bool isLoading = false;

    final existingPayment = index != null ? _newPayments[index] : null;
    if (existingPayment != null) {
      controller.text = existingPayment['amount'].toString();
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter Amount for $method${existingPayment != null ? ' (Edit)' : ''}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Amount Received (৳):', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () {
                          setState(() => isLoading = true);
                          final entered = double.tryParse(controller.text) ?? 0.0;
                          if (entered > 0) {
                            if (index != null) {
                              setState(() {
                                _newPayments[index] = {
                                  'method': method,
                                  'amount': entered,
                                  'timestamp': Timestamp.now(),
                                };
                              });
                            } else {
                              setState(() {
                                _newPayments.add({
                                  'method': method,
                                  'amount': entered,
                                  'timestamp': Timestamp.now(),
                                });
                              });
                            }
                            Navigator.pop(context);
                            this.setState(() {}); // Refresh parent state
                          }
                          setState(() => isLoading = false);
                        },
                        child: isLoading
                            ? LoadingAnimationWidget.staggeredDotsWave(
                          color: Colors.blue,
                          size: 24,
                        )
                            : const Text('Save', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      if (existingPayment != null)
                        ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () {
                            setState(() => isLoading = true);
                            setState(() {
                              _newPayments.removeAt(index!);
                            });
                            Navigator.pop(context);
                            this.setState(() {}); // Refresh parent state
                            setState(() => isLoading = false);
                          },
                          child: isLoading
                              ? LoadingAnimationWidget.staggeredDotsWave(
                            color: Colors.red,
                            size: 24,
                          )
                              : const Text('Delete', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _updatePaymentTimestamp();
    });
  }

  Future<void> _showStarsSheet() async {
    int currentStars = await _fetchOrCreatePlayerStars();
    final controller = TextEditingController();
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final enteredStars = int.tryParse(controller.text) ?? 0;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Current Stars: $currentStars',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Use Stars (1 Star = 1 tk, Min 100 tk)',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Amount (Stars):', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : enteredStars >= 100 && enteredStars <= currentStars
                          ? () async {
                        setState(() => isLoading = true);
                        final total =
                        (widget.invoice['total_amount'] as num? ?? 0).toDouble();
                        final discountAmount = (widget.invoice['discount_amount']
                        as num?)
                            ?.toDouble() ??
                            0.0;
                        final discountedTotal = total - discountAmount;
                        final newTotalPaid = _newPayments.fold(
                            0.0, (sum, p) => sum + p['amount']) +
                            enteredStars;
                        final remaining = discountedTotal - newTotalPaid;

                        setState(() {
                          _newPayments.add({
                            'method': 'Stars',
                            'amount': enteredStars.toDouble(),
                            'timestamp': Timestamp.now(),
                          });
                          currentStars -= enteredStars;
                        });

                        await FirebaseFirestore.instance
                            .collection('players')
                            .doc(widget.invoice['player_id'])
                            .update({'stars': currentStars});

                        if (remaining <= 0) {
                          _saveInvoice();
                        } else {
                          Navigator.pop(context);
                        }
                        setState(() => isLoading = false);
                      }
                          : null,
                      child: isLoading
                          ? LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.yellow,
                        size: 24,
                      )
                          : const Text('Apply Stars', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    ).then((_) => _updatePaymentTimestamp());
  }

  Future<int> _fetchOrCreatePlayerStars() async {
    try {
      setState(() => isLoading = true);
      final playerId = widget.invoice['player_id'] as String?;
      if (playerId == null) {
        setState(() => isLoading = false);
        return 0;
      }

      final playerDoc =
      await FirebaseFirestore.instance.collection('players').doc(playerId).get();
      if (playerDoc.exists) {
        setState(() => isLoading = false);
        return (playerDoc.data()?['stars'] as num?)?.toInt() ?? 0;
      } else {
        await FirebaseFirestore.instance
            .collection('players')
            .doc(playerId)
            .set({'stars': 0});
        setState(() => isLoading = false);
        return 0;
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching stars: $e')),
      );
      return 0;
    }
  }

  Future<void> _showRoundUpSheet() async {
    final controller = TextEditingController();
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Round Up Amount (Max 100 tk)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Amount (tk):', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                    setState(() => isLoading = true);
                    final roundUp = double.tryParse(controller.text) ?? 0.0;
                    if (roundUp > 0 && roundUp <= 100) {
                      setState(() {
                        _newPayments.add({
                          'method': 'RoundUp',
                          'amount': roundUp,
                          'timestamp': Timestamp.now(),
                        });
                      });
                      Navigator.pop(context);
                    }
                    setState(() => isLoading = false);
                  },
                  child: isLoading
                      ? LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.orange,
                    size: 24,
                  )
                      : const Text('Apply Round Up', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) => _updatePaymentTimestamp());
  }

  void _updatePaymentTimestamp() {
    setState(() {
      FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('invoices')
          .doc(widget.invoice['id'])
          .update({'paymentUpdateTimestamp': Timestamp.now()});
    });
  }

  void _saveInvoice() async {
    setState(() => isLoading = true);
    double newPaymentAmount = _newPayments.fold(0.0, (sum, p) => sum + (p['amount'] as num?)!.toDouble() ?? 0.0);
    double previousPaidAmount = (widget.invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    double totalPaid = previousPaidAmount + newPaymentAmount;
    double total = (widget.invoice['total_amount'] as num? ?? 0).toDouble();
    double discountedTotal = total - _discountAmount;

    num starsEarned = newPaymentAmount >= 50 ? (newPaymentAmount / 100).floor() : 0;
    int currentStars = await _fetchOrCreatePlayerStars();
    await FirebaseFirestore.instance
        .collection('players')
        .doc(widget.invoice['player_id'])
        .update({'stars': currentStars + starsEarned});

    String newStatus = totalPaid >= discountedTotal ? 'paid' : totalPaid > 0 ? 'due' : 'unpaid';

    // Save to payments subcollection for dashboard (excluding round-up)
    for (var payment in _newPayments) {
      if (payment['method'] != 'RoundUp') {
        await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .collection('payments')
            .add({
          'amount': payment['amount'],
          'method': payment['method'],
          'invoice_id': widget.invoice['id'],
          'player_id': widget.invoice['player_id'],
          'timestamp': payment['timestamp'],
        });
      }
    }

    // Append new payments to existing payments
    List<Map<String, dynamic>> existingPayments =
    widget.invoice['payments'] != null ? List<Map<String, dynamic>>.from(widget.invoice['payments']) : [];
    existingPayments.addAll(_newPayments);

    // Update invoice with current subcollection
    await FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invoices')
        .doc(widget.invoice['id'])
        .update({
      'paid_amount': totalPaid, // Set the total paid amount
      'status': newStatus,
      'discount_amount': _discountAmount,
      'discount_code': _selectedDiscountCode,
      'stars_earned': FieldValue.increment(starsEarned),
      'paymentUpdateTimestamp': FieldValue.serverTimestamp(),
      'payments': existingPayments, // Append new payments
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice saved successfully')));
    Navigator.popUntil(context, (route) => route.isFirst);
    setState(() => isLoading = false);
  }

  Widget _buildInvoiceCard(double total, double discountedTotal, double totalPaid, double remaining, double change) {
    double roundUpAmount = _newPayments.where((p) => p['method'] == 'RoundUp').fold(0.0, (sum, p) => sum + (p['amount'] as num?)!.toDouble() ?? 0.0);
    remaining = discountedTotal - totalPaid; // Correct remaining amount
    change = totalPaid - discountedTotal;

    final invoiceDate = (widget.invoice['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final paymentUpdateDate = (widget.invoice['paymentUpdateTimestamp'] as Timestamp?)?.toDate() ?? invoiceDate;
    final formattedInvoiceDate = '${invoiceDate.day.toString().padLeft(2, '0')}/${invoiceDate.month.toString().padLeft(2, '0')}/${invoiceDate.year}';
    final formattedPaymentUpdateDate = '${paymentUpdateDate.day.toString().padLeft(2, '0')}/${paymentUpdateDate.month.toString().padLeft(2, '0')}/${paymentUpdateDate.year}';

    // Combine existing and new payments for display
    List<Map<String, dynamic>> allPayments =
    widget.invoice['payments'] != null ? List<Map<String, dynamic>>.from(widget.invoice['payments']) : [];
    allPayments.addAll(_newPayments);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invoice Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Invoice No: ${widget.invoice['id']}', style: const TextStyle(fontSize: 16)),
            Text('Invoice Date: $formattedInvoiceDate', style: const TextStyle(fontSize: 16)),
            Text('Last Payment Update: $formattedPaymentUpdateDate', style: const TextStyle(fontSize: 16)),
            Text('Sub Total: ৳${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16)),
            if (_discountAmount > 0) Text('Discount: -৳${_discountAmount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green, fontSize: 16)),
            if (totalPaid > 0) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Paid: ৳${totalPaid.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, color: Colors.grey)),
              if (allPayments.isNotEmpty) Column(children: allPayments.asMap().entries.map((entry) {
                final index = entry.key;
                final p = entry.value;
                return ListTile(
                  title: Text('${p['method']}: ৳${p['amount'].toStringAsFixed(0)}', style: const TextStyle(fontSize: 14)),
                  trailing: index >= (widget.invoice['payments']?.length ?? 0)
                      ? IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showPaymentBottomSheet(p['method'], index: (index - (widget.invoice['payments']?.length ?? 0)) as int?))
                      : null,
                );
              }).toList()),
            ]),
            const Divider(height: 20),
            Text('Total Payable: ৳${discountedTotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (remaining > 0 && remaining <= 100) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
              Text('Now Payable: ৳${remaining.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: isLoading ? null : _showRoundUpSheet, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)), child: isLoading ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24) : const Text('Round Up', style: TextStyle(color: Colors.white))),
            ])),
            if (remaining < 0) Text('Change to return: ৳${(-remaining).toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(String method, Color color, String logoPath) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color,
      child: InkWell(
        onTap: isLoading ? null : () => _showPaymentBottomSheet(method),
        child: Container(
          width: 70,
          height: 90,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                logoPath,
                height: 40,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, size: 40),
              ),
              const SizedBox(height: 4),
              Text(method, style: const TextStyle(color: Colors.black, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = (widget.invoice['total_amount'] as num? ?? 0).toDouble();
    final discountAmount = (widget.invoice['discount_amount'] as num?)?.toDouble() ?? _discountAmount;
    final discountedTotal = total - discountAmount;
    double previousPaidAmount = (widget.invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    double newPaymentAmount = _newPayments.fold(0.0, (sum, p) => sum + (p['amount'] as num?)!.toDouble() ?? 0.0);
    double totalPaid = previousPaidAmount + newPaymentAmount; // Correct total paid
    double remaining = discountedTotal - totalPaid;
    double change = totalPaid - discountedTotal;

    final status = widget.invoice['status'] as String? ?? 'unknown';
    final isDiscountApplicable = status == 'unpaid' && !(_discountAmount > 0 || _selectedDiscountCode != null);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? Center(child: LoadingAnimationWidget.staggeredDotsWave(color: Colors.blue, size: 50))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInvoiceCard(total, discountedTotal, totalPaid, remaining, change),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: isDiscountApplicable ? () => _showDiscountSheet() : null,
                  icon: const Icon(Icons.percent, color: Colors.red),
                  style: ElevatedButton.styleFrom(backgroundColor: !isDiscountApplicable ? Colors.grey : Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Colors.red)),
                  label: const Text('Add Discount', style: TextStyle(fontSize: 16, color: Colors.red)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _showStarsSheet,
                  icon: const Icon(Icons.star, color: Colors.red),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Colors.red)),
                  label: const Text('Use Stars', style: TextStyle(fontSize: 16, color: Colors.red)),
                )),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Select Payment Method:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPaymentCard('Cash', Colors.white70, 'assets/cash.png'),
                _buildPaymentCard('Bkash', Colors.white70, 'assets/bkash.png'),
                _buildPaymentCard('Nagad', Colors.white70, 'assets/nagad.png'),
                _buildPaymentCard('Bank', Colors.white70, 'assets/bank.png'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading || newPaymentAmount == 0 ? null : _saveInvoice,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white60, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: isLoading ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.black, size: 24) : const Text('Save Invoice', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}