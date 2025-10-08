
import 'package:flutter/material.dart';
import 'summary.dart';

class ReportScreen extends StatelessWidget {
  final String clubId;

  const ReportScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reports')),
      body: Center(
        child: Card(
          elevation: 4,
          margin: EdgeInsets.all(16),
          child: SizedBox(
            width: 450,
            height: 80,
            child: ListTile(
              leading: Image.asset('assets/customer.png', width: 50, height: 50),
              title: Text('Player Wise Sales Summary', style: TextStyle(fontSize: 20)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SummaryScreen(clubId: clubId),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}