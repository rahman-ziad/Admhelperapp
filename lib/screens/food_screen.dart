import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/edit_food_item_screen.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
class CartItem {
  final String id;
  final String name;
  final double price;
  int quantity;

  CartItem({required this.id, required this.name, required this.price, this.quantity = 1});
}

final cartProvider = StateProvider<List<CartItem>>((ref) => []);

final foodItemsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, clubId) {
  return FirebaseFirestore.instance
      .collection('clubs')
      .doc(clubId)
      .collection('food_items')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
});

final playersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('players')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
});



class FoodScreen extends ConsumerStatefulWidget {
  final String clubId;

  const FoodScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  ConsumerState<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends ConsumerState<FoodScreen> {
  String? selectedCategory;

  final categories = [
    {'name': 'Appetizer', 'image': 'assets/1.png'},
    {'name': 'Main Dish', 'image': 'assets/2.png'},
    {'name': 'Beverage', 'image': 'assets/3.png'},
    {'name': 'Snacks', 'image': 'assets/4.png'},
  ];

  @override
  Widget build(BuildContext context) {
    final foodItemsAsync = ref.watch(foodItemsProvider(widget.clubId));

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: foodItemsAsync.when(
              data: (foodItems) {
                final filteredItems = selectedCategory == null
                    ? []
                    : foodItems.where((item) => item['category'] == selectedCategory).toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          itemBuilder: (_, index) {
                            final category = categories[index];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedCategory = category['name'];
                                });
                              },
                              child: Container(
                                width: 100,
                                margin: const EdgeInsets.only(right: 16),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.asset(
                                        category['image']!,
                                        fit: BoxFit.cover,
                                        width: 100,
                                        height: 80,
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        category['name']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (selectedCategory != null) ...[
                        Text(
                          'Showing: $selectedCategory',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (filteredItems.isEmpty)
                          const Text('No items found in this category')
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.5,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: filteredItems.length,
                            itemBuilder: (_, idx) {
                              final item = filteredItems[idx];
                              return FoodCard(item: item, clubId: widget.clubId);
                            },
                          ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'All Items:',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.95,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: foodItems.length,
                        itemBuilder: (_, idx) {
                          final item = foodItems[idx];
                          return FoodCard(item: item, clubId: widget.clubId);
                        },
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
          // Inside FoodScreen's build method, update the ElevatedButton for Checkout
          if (ref.watch(cartProvider).isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CartScreen(clubId: widget.clubId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${ref.watch(cartProvider).fold(0, (sum, item) => sum + item.quantity)}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Text(
                      'Checkout',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '৳${ref.watch(cartProvider).fold(0.0, (sum, item) => sum + item.price * item.quantity).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FoodCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  final String clubId;

  const FoodCard({Key? key, required this.item, required this.clubId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOutOfStock = (item['stock'] ?? 0) == 0;

    return GestureDetector(
      onTap: isOutOfStock
          ? null
          : () {
        final cart = ref.read(cartProvider);
        final existingItemIndex = cart.indexWhere((i) => i.id == item['id']);

        if (existingItemIndex == -1) {
          // Item doesn't exist in cart, add it
          cart.add(CartItem(
            id: item['id'],
            name: item['name'] ?? 'Unknown',
            price: (item['price'] ?? 0.0).toDouble(),
          ));
        } else {
          // Item exists, increase quantity
          cart[existingItemIndex].quantity++;
        }

        // Trigger state update
        ref.read(cartProvider.notifier).update((state) => [...state]);
      },
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditFoodItemScreen(
              clubId: clubId,
              foodItem: item,
            ),
          ),
        );
      },
      child: Opacity(
        opacity: isOutOfStock ? 0.5 : 1.0,
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          elevation: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  color: Colors.grey[200],
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: item['image_url'] != null
                          ? Image.network(
                        item['image_url'],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.fastfood, size: 40),
                      )
                          : const Icon(Icons.fastfood, size: 40),
                    ),
                    if (!isOutOfStock)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.green,
                          child: const Icon(Icons.add, size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? '',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item['description'] ?? 'No description available',
                      style: const TextStyle(fontSize: 8, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '৳${(item['price'] ?? 0.0).toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Stock: ${item['stock'] ?? 0}',
                          style: TextStyle(
                            fontSize: 9,
                            color: (item['stock'] ?? 0) == 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




class CartScreen extends ConsumerStatefulWidget {
  final String clubId;

  const CartScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  String? selectedPlayerId;
  List<Map<String, dynamic>> recentPlayers = [];
  List<Map<String, dynamic>> allPlayers = [];
  final TextEditingController searchController = TextEditingController();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRecentPlayers();
  }

  Future<void> _fetchRecentPlayers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('recent_players')
        .orderBy('timestamp', descending: true)
        .limit(15)
        .get();

    setState(() {
      recentPlayers = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  Future<void> _updateRecentPlayers(String playerId, Map<String, dynamic> playerData) async {
    final recentPlayersRef = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('recent_players');

    final existingPlayer = recentPlayers.firstWhere(
          (p) => p['player_id'] == playerId,
      orElse: () => {},
    );

    if (existingPlayer.isNotEmpty) {
      await recentPlayersRef.doc(existingPlayer['id']).update({
        'timestamp': Timestamp.now(),
      });
    } else {
      if (recentPlayers.length >= 15) {
        final oldestPlayer = recentPlayers.last;
        await recentPlayersRef.doc(oldestPlayer['id']).delete();
      }

      await recentPlayersRef.add({
        'player_id': playerId,
        'name': playerData['name'],
        'phone_number': playerData['phone_number'],
        'image_url': playerData['image_url'],
        'timestamp': Timestamp.now(),
      });
    }

    await _fetchRecentPlayers();
  }

  List<Map<String, dynamic>> _getDisplayPlayers() {
    if (selectedPlayerId == null) return recentPlayers;

    final selectedPlayer = allPlayers.firstWhere(
          (p) => p['id'] == selectedPlayerId,
      orElse: () => {},
    );

    if (selectedPlayer.isEmpty) return recentPlayers;

    final filteredRecentPlayers = recentPlayers
        .where((p) => p['player_id'] != selectedPlayerId)
        .take(15)
        .toList();

    return [
      {
        'player_id': selectedPlayerId,
        'name': selectedPlayer['name'],
        'phone_number': selectedPlayer['phone_number'],
        'image_url': selectedPlayer['image_url'],
      },
      ...filteredRecentPlayers,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final playersAsync = ref.watch(playersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: playersAsync.when(
        data: (players) {
          allPlayers = players;

          final displayPlayers = _getDisplayPlayers();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Player (IGN/Name/Phone)',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => searchController.clear(),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchPlayersScreen(
                          clubId: widget.clubId,
                          onSelect: (playerId) {
                            setState(() {
                              selectedPlayerId = playerId;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (displayPlayers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No recent players found',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                else
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: displayPlayers.length,
                      itemBuilder: (context, index) {
                        final player = displayPlayers[index];
                        final isSelected = selectedPlayerId == (player['player_id'] ?? player['id']);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedPlayerId = isSelected ? null : (player['player_id'] ?? player['id']);
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
                                  (player['name'] ?? 'Unknown').length > 8
                                      ? '${(player['name'] ?? 'Unknown').substring(0, 8)}...'
                                      : player['name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.red : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SUB TOTAL',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '৳${cart.fold(0.0, (sum, item) => sum + item.price * item.quantity).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: cart.isEmpty
                      ? const Center(child: Text('Cart is empty'))
                      : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final cartItem = cart[index];
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('clubs')
                            .doc(widget.clubId)
                            .collection('food_items')
                            .doc(cartItem.id)
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final foodItem = snapshot.data!.data() as Map<String, dynamic>;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              height: 90,
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.grey[200],
                                    ),
                                    child: foodItem['image_url'] != null
                                        ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        foodItem['image_url'],
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.fastfood),
                                      ),
                                    )
                                        : const Icon(Icons.fastfood),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          cartItem.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '৳${cartItem.price.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            if (cartItem.quantity > 1) {
                                              cartItem.quantity--;
                                            } else {
                                              cart.remove(cartItem);
                                            }
                                            ref.read(cartProvider.notifier).state = [...cart];
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            child: const Icon(Icons.remove, size: 16, color: Colors.red),
                                          ),
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 24),
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Text(
                                            '${cartItem.quantity}',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            cartItem.quantity++;
                                            ref.read(cartProvider.notifier).state = [...cart];
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            child: const Icon(Icons.add, size: 16, color: Colors.green),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '৳${(cartItem.price * cartItem.quantity).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // In _CartScreenState._build (replace the ElevatedButton onPressed logic)
                ElevatedButton.icon(
                  onPressed: selectedPlayerId != null && cart.isNotEmpty && !isLoading
                      ? () async {
                    setState(() => isLoading = true);
                    try {
                      // Pre-fetch and validate stock for all cart items
                      Map<String, int> stockCache = {};
                      for (var cartItem in cart) {
                        final foodItemDoc = await FirebaseFirestore.instance
                            .collection('clubs')
                            .doc(widget.clubId)
                            .collection('food_items')
                            .doc(cartItem.id)
                            .get();
                        if (foodItemDoc.exists) {
                          final currentStock = (foodItemDoc.data()!['stock'] ?? 0) as int;
                          if (currentStock < cartItem.quantity) {
                            throw Exception('Not enough stock for ${cartItem.name}. Available: $currentStock, Requested: ${cartItem.quantity}');
                          }
                          stockCache[cartItem.id] = currentStock;
                        } else {
                          throw Exception('Item ${cartItem.name} not found');
                        }
                      }

                      // Start Firestore transaction
                      await FirebaseFirestore.instance.runTransaction((transaction) async {
                        final totalAmount = cart.fold(0, (sum, item) => (sum + item.price * item.quantity).round());
                        final currentTimestamp = Timestamp.now();
                        final now = currentTimestamp.toDate();

                        // Query for existing unpaid invoice outside transaction
                        final invoicesRef = FirebaseFirestore.instance
                            .collection('clubs')
                            .doc(widget.clubId)
                            .collection('invoices');
                        final invoicesSnapshot = await invoicesRef
                            .where('player_id', isEqualTo: selectedPlayerId)
                            .where('status', isEqualTo: 'unpaid')
                            .where('practice_mode', isEqualTo: false)
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

                        final newServices = cart
                            .map((item) => {
                          'type': 'food',
                          'details': {
                            'food_item_id': item.id,
                            'food_item_name': item.name,
                            'quantity': item.quantity,
                            'price_at_time': item.price.round(),
                            'price': (item.price * item.quantity).round(),
                            'purchase_time': Timestamp.now(),
                            'split_bill': false,
                          },
                        })
                            .toList();

                        String invoiceId;
                        int updatedTotal = totalAmount;

                        if (existingInvoice != null) {
                          // Read existing services within transaction
                          final invoiceDoc = await transaction.get(invoicesRef.doc(existingInvoice.id));
                          final existingServices = List<Map<String, dynamic>>.from(invoiceDoc['services'] ?? []);
                          existingServices.addAll(newServices);

                          updatedTotal = existingServices.fold(0, (sum, service) {
                            final details = service['details'] as Map<String, dynamic>;
                            return sum + (details['price'] as num? ?? 0).toInt();
                          });

                          transaction.update(
                            invoicesRef.doc(existingInvoice.id),
                            {
                              'services': existingServices,
                              'gross_total': updatedTotal,
                              'net_total': updatedTotal,
                              'total_amount': updatedTotal,
                              'date': currentTimestamp,
                            },
                          );
                          invoiceId = existingInvoice.id;
                        } else {
                          // Create new invoice
                          final invoiceData = {
                            'player_id': selectedPlayerId,
                            'player_name': allPlayers.firstWhere((p) => p['id'] == selectedPlayerId)['name'],
                            'date': currentTimestamp,
                            'status': 'unpaid',
                            'gross_total': totalAmount,
                            'net_total': totalAmount,
                            'total_amount': totalAmount,
                            'paid_amount': 0,
                            'services': newServices,
                            'practice_mode': false,
                            'discount_amount': 0,
                            'discount_amounts': {'games': 0, 'food': 0},
                            'discount_codes': {'games': null, 'food': null},
                            'round_up': 0,
                          };

                          final invoiceRef = invoicesRef.doc();
                          transaction.set(invoiceRef, invoiceData);
                          invoiceId = invoiceRef.id;
                        }

                        // Update player's invoice subcollection
                        final playerInvoiceRef = FirebaseFirestore.instance
                            .collection('players')
                            .doc(selectedPlayerId)
                            .collection('invoices')
                            .doc(invoiceId);
                        transaction.set(playerInvoiceRef, {
                          'club_id': widget.clubId,
                          'invoice_id': invoiceId,
                          'date': currentTimestamp,
                          'gross_total': updatedTotal,
                          'net_total': updatedTotal,
                          'total_amount': updatedTotal,
                          'status': 'unpaid',
                          'practice_mode': false,
                          'discount_amount': 0,
                          'discount_amounts': {'games': 0, 'food': 0},
                          'discount_codes': {'games': null, 'food': null},
                          'round_up': 0,
                        });

                        // Add invoice ID to player's club-specific subcollection
                        final playerClubInvoiceRef = FirebaseFirestore.instance
                            .collection('players')
                            .doc(selectedPlayerId)
                            .collection('clubs')
                            .doc(widget.clubId)
                            .collection('invoices')
                            .doc(invoiceId);
                        transaction.set(playerClubInvoiceRef, {
                          'invoice_id': invoiceId,
                          'timestamp': currentTimestamp,
                        });

                        // Update stock within transaction
                        for (var cartItem in cart) {
                          final foodItemRef = FirebaseFirestore.instance
                              .collection('clubs')
                              .doc(widget.clubId)
                              .collection('food_items')
                              .doc(cartItem.id);
                          final cachedStock = stockCache[cartItem.id]!;
                          final newStock = cachedStock - cartItem.quantity;
                          transaction.update(foodItemRef, {'stock': newStock});
                        }
                      });

                      final selectedPlayer = allPlayers.firstWhere((p) => p['id'] == selectedPlayerId);
                      await _updateRecentPlayers(selectedPlayerId!, selectedPlayer);

                      // Clear cart after successful order
                      ref.read(cartProvider.notifier).state = [];
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order placed successfully')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to order: $e')),
                      );
                    }
                    setState(() => isLoading = false);
                  }
                      : null,
                  icon: isLoading
                      ? LoadingAnimationWidget.staggeredDotsWave(color: Colors.white, size: 24)
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Confirm & Add to Invoice'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.red,
                  ),
                )
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class SearchPlayersScreen extends ConsumerStatefulWidget {
  final String clubId;
  final Function(String) onSelect;

  const SearchPlayersScreen({
    Key? key,
    required this.clubId,
    required this.onSelect,
  }) : super(key: key);

  @override
  ConsumerState<SearchPlayersScreen> createState() => _SearchPlayersScreenState();
}

class _SearchPlayersScreenState extends ConsumerState<SearchPlayersScreen> {
  List<Map<String, dynamic>> filteredPlayers = [];
  List<Map<String, dynamic>> allPlayers = [];
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
  }

  Future<void> _fetchPlayers() async {
    final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
    setState(() {
      allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      filteredPlayers = allPlayers;
    });
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
    // Take first 12 digits and append **
    return '${phoneNumber.substring(0, phoneNumber.length > 12 ? 12 : phoneNumber.length)}**';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search Player (IGN/Name/Phone)',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            _filterPlayers(value);
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: filteredPlayers.isEmpty
          ? const Center(child: Text('No players found'))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredPlayers.length,
        itemBuilder: (context, index) {
          final player = filteredPlayers[index];
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
            trailing: Radio(
              value: player['id'],
              groupValue: null, // Will be managed in CartScreen
              onChanged: (value) {
                widget.onSelect(player['id']);
                Navigator.pop(context);
              },
            ),
            onTap: () {
              widget.onSelect(player['id']);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}