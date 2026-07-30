import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  final int _selectedIndex = 2;

  final TextEditingController _weightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedUnit = 'kg';
  bool _isSaving = false;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushNamed('/home');
        break;
      case 1:
        Navigator.of(context).pushNamed('/add_exercise');
        break;
      case 2:
        // Already on weight
        break;
      case 3:
        Navigator.of(context).pushNamed('/settings');
        break;
    }
  }

  Future<void> _saveWeight() async {
    if (!_formKey.currentState!.validate()) return;

    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null) return;

    setState(() => _isSaving = true);
    try {
      await DBHelper().insertBodyWeight(weight, _selectedUnit);
      if (!mounted) return;
      _weightController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Weight saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _validateWeight(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter your weight';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'Enter a valid number';
    }
    if (parsed <= 0) {
      return 'Weight must be greater than 0';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Weight'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/weight/history'),
              icon: const Icon(Icons.history),
              label: const Text('View previous weight'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Log today\'s weight',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateWeight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedUnit,
                    items: const [
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'lb', child: Text('lb')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedUnit = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveWeight,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
