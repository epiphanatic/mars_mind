import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For encoding/decoding JSON
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

class Vitals {
  final String crewId;
  final double heartRate;
  final double sleepHours;
  final String timestamp;
  final double stressScore;
  final String stressFlag;

  Vitals({
    required this.crewId,
    required this.heartRate,
    required this.sleepHours,
    required this.timestamp,
    required this.stressScore,
    required this.stressFlag,
  });

  factory Vitals.fromFirestore(Map<String, dynamic> data) {
    return Vitals(
      crewId: data['crew_id'] as String,
      heartRate: data['heart_rate'] as double,
      sleepHours: data['sleep_hours'] as double,
      timestamp: data['timestamp'] as String,
      stressScore: data['stress_score'] as double,
      stressFlag: data['stress_flag'] as String,
    );
  }
}

class VitalsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Vitals>> getLatestVitals(String crewId) {
    return _firestore
        .collection('vitals')
        .where('crew_id', isEqualTo: crewId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => Vitals.fromFirestore(doc.data()))
                  .toList(),
        );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mars Mind',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Mars Mind'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String crewId = 'astro_001';

  _createVital() async {
    // Define the URL
    final url = Uri.parse('https://analyze-vitals-odc2umnfqa-uc.a.run.app');

    // Prepare the data to send (as a JSON object)
    final data = {
      "crew_id": "astro_001",
      "heart_rate": 95.0,
      "sleep_hours": 5.0,
      "timestamp": "2025-03-02T12:34:56Z",
    };

    try {
      // Make the POST request
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(data), // Convert the data to JSON
      );

      // Check the response
      if (response.statusCode == 201) {
        // Success (201 Created is typical for POST success)
        final responseData = jsonDecode(response.body);
        print('Response: $responseData');
      } else {
        // Handle error
        print('Failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      // Handle network or other errors
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,

        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // const Text('You have pushed the button this many times:'),
            // Text(
            //   '$_counter',
            //   style: Theme.of(context).textTheme.headlineMedium,
            // ),
            StreamBuilder<List<Vitals>>(
              stream: VitalsService().getLatestVitals(crewId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final vitals = snapshot.data!.first; // Take the latest
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crew ID: ${vitals.crewId}',
                        style: TextStyle(fontSize: 18),
                      ),
                      Text(
                        'Heart Rate: ${vitals.heartRate}',
                        style: TextStyle(fontSize: 18),
                      ),
                      Text(
                        'Sleep Hours: ${vitals.sleepHours}',
                        style: TextStyle(fontSize: 18),
                      ),
                      Text(
                        'Stress Flag: ${vitals.stressFlag}',
                        style: TextStyle(
                          fontSize: 18,
                          color:
                              vitals.stressFlag == 'High'
                                  ? Colors.red
                                  : Colors.green,
                        ),
                      ),
                      Text(
                        'Timestamp: ${vitals.timestamp}',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createVital,
        tooltip: 'Increment',
        label: const Text('Create Vital'),
        icon: Icon(Icons.add),
      ),
    );
  }
}
