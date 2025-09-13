import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tsodrfgqmwpkokclbmfe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRzb2RyZmdxbXdwa29rY2xibWZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc3ODE5NjQsImV4cCI6MjA3MzM1Nzk2NH0.Lp1o3NN6nCuHmJ1e8U5QhyP3fLlBYy2uvGuhClTpJy0',
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Supabase Test App',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;
  bool _isConnected = false;
  String _connectionStatus = 'Testing connection...';
  List<Map<String, dynamic>> _testData = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _testConnection();
  }

  Future<void> _testConnection() async {
    try {
      // Test basic connection by trying to access a simple query
      await supabase.from('test_table').select().limit(1);
      setState(() {
        _isConnected = true;
        _connectionStatus = 'Connected to Supabase!';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Connection test: ${e.toString()}';
      });
    }
  }

  Future<void> _loadTestData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await supabase.from('test_table').select();
      setState(() {
        _testData = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: ${e.toString()}')),
      );
    }
  }

  Future<void> _addTestData() async {
    try {
      await supabase.from('test_table').insert({
        'name': 'Test Item ${DateTime.now().millisecondsSinceEpoch}',
        'created_at': DateTime.now().toIso8601String(),
      });
      _loadTestData(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test data added successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding data: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase Test App'),
        backgroundColor: _isConnected ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Status',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.error,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_connectionStatus),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _loadTestData,
                  child: const Text('Load Test Data'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addTestData,
                  child: const Text('Add Test Data'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Test Data (${_testData.length} items)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _testData.isEmpty
                      ? const Center(
                          child: Text('No data found. Try adding some test data!'),
                        )
                      : ListView.builder(
                          itemCount: _testData.length,
                          itemBuilder: (context, index) {
                            final item = _testData[index];
                            return Card(
                              child: ListTile(
                                title: Text(item['name'] ?? 'No name'),
                                subtitle: Text(
                                  'Created: ${item['created_at'] ?? 'Unknown'}',
                                ),
                                leading: const Icon(Icons.data_object),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
