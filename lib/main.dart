import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For encoding/decoding JSON

void main() {
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
  _createVital() async {
    // Define the URL
    final url = Uri.parse(
      'http://10.0.2.2:5001/mars-mind/us-central1/analyze_vitals',
    );

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
