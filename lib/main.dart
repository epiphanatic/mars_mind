import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For encoding/decoding JSON
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  Timer? _simulationTimer; // Timer for simulation
  final Random _random = Random(); // For generating random numbers

  late StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    // Optionally listen to auth changes manually (you can skip this if using StreamBuilder)
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      if (user != null) {
        debugPrint('User signed in: ${user.uid}');
      } else {
        debugPrint('User signed out');
      }
      setState(() {}); // Trigger UI update
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel(); // Clean up the subscription
    _simulationTimer?.cancel(); // Clean up the timer
    super.dispose();
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Start the Google Sign-In process
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User canceled the sign-in
        return null;
      }

      // Get authentication details from Google
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a credential for Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the credential
      return await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Error during Google Sign-In: $e');
      return null;
    }
  }

  logOut() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
  }

  _createVital() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user is signed in. Please sign in first.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please sign in to create a vital.')),
      );
      return;
    }

    final String? idToken = await user.getIdToken(true); // Force refresh
    if (idToken == null && mounted) {
      debugPrint('Failed to retrieve ID token.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication error. Try signing in again.')),
      );
      return;
    }

    // Define the URL
    final url = Uri.parse('https://analyze-vitals-odc2umnfqa-uc.a.run.app');

    // Prepare the data to send (as a JSON object)
    final data = {
      "crew_id": "astro_001",
      "heart_rate": 95.0,
      "sleep_hours": 5.0,
      "timestamp": DateTime.now().toIso8601String(), // Use current timestamp
    };

    try {
      // Make the POST request
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(data),
      );

      // Check the response
      if (response.statusCode == 201) {
        // Success (201 Created is typical for POST success)
        debugPrint('Response: ${response.body}');
      } else {
        // Handle error
        debugPrint('Failed with status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
      }
    } catch (e) {
      // Handle network or other errors
      debugPrint('Error: $e');
    }
  }

  Future<void> runSimulation() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user is signed in. Please sign in first.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please sign in to start simulation.')),
      );
      return;
    }

    // Stop any existing simulation
    _simulationTimer?.cancel();

    final String? idToken = await user.getIdToken(true); // Force refresh

    if (idToken == null && mounted) {
      debugPrint('Failed to retrieve ID token for simulation.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication error. Try signing in again.')),
      );
      return;
    }

    // Start a periodic timer to send random vitals every 5 seconds
    _simulationTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      final randomHeartRate = 60 + _random.nextDouble() * 80; // 60-140 bpm
      final randomSleepHours = 2 + _random.nextDouble() * 4; // 2-6 hours
      final timestamp = DateTime.now().toIso8601String();

      // python cloud function
      // final url = Uri.parse('https://analyze-vitals-odc2umnfqa-uc.a.run.app');

      // rust local
      final url = Uri.parse('http://192.168.1.18:8080/analyze_vitals');
      final data = {
        "crew_id": user.uid,
        "heart_rate": randomHeartRate,
        "sleep_hours": randomSleepHours,
        "timestamp": timestamp,
      };

      try {
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json; charset=UTF-8',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(data),
        );

        debugPrint(response.body);

        if (response.statusCode == 201) {
          // final responseData = jsonDecode(response.body);
          debugPrint('Simulation: ${response.body}');
        } else {
          debugPrint(
            'Simulation failed with status: ${response.statusCode}, Body: ${response.body}',
          );
          timer.cancel(); // Stop simulation on failure
        }
      } catch (e) {
        debugPrint('Simulation error: $e');
        timer.cancel(); // Stop simulation on error
      }
    });
  }

  void stopSimulation() {
    if (_simulationTimer != null && _simulationTimer!.isActive) {
      _simulationTimer!.cancel();
      setState(() {
        // Optionally reset any simulation state
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Simulation stopped.')));
      debugPrint('Simulation stopped.');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No simulation is currently running.')),
      );
      debugPrint('No simulation is running.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final User? user = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: Text(widget.title),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (user == null) ...[
                  ElevatedButton(
                    onPressed: signInWithGoogle,
                    child: Text('Sign in with Google'),
                  ),
                ] else ...[
                  Text('User ID: ${user.uid}'),
                  ElevatedButton(onPressed: logOut, child: Text('Logout')),
                  StreamBuilder<List<Vitals>>(
                    stream: VitalsService().getLatestVitals(user.uid),
                    builder: (context, vitalsSnapshot) {
                      if (vitalsSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (vitalsSnapshot.hasError) {
                        return Center(
                          child: Text('Error: ${vitalsSnapshot.error}'),
                        );
                      }
                      if (!vitalsSnapshot.hasData ||
                          vitalsSnapshot.data!.isEmpty) {
                        return Center(
                          child: Text('No vitals available for ${user.uid}'),
                        );
                      }
                      final vitals = vitalsSnapshot.data!.first;
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
              ],
            ),
          ),

          // floatingActionButton:
          //     user == null
          //         ? null
          //         : FloatingActionButton.extended(
          //           onPressed: _createVital,
          //           tooltip: 'Increment',
          //           label: const Text('Create Vital'),
          //           icon: Icon(Icons.add),
          //         ),
          floatingActionButton:
              user == null
                  ? null
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: stopSimulation,
                        tooltip: 'Stops Vitals Simulation',
                        label: const Text('Stop Simulation'),
                        icon: Icon(Icons.add),
                      ),
                      SizedBox(width: 16), // Spacing between buttons
                      FloatingActionButton.extended(
                        onPressed: runSimulation,
                        tooltip: 'Start Vitals Simulation',
                        label: const Text('Vitals Simulation'),
                        icon: Icon(Icons.play_arrow),
                      ),
                    ],
                  ),
        );
      },
    );
  }
}
