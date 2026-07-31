import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/weight_format.dart';
import 'package:gym_tracker/widgets/body_weight_chart.dart';

enum _ViewMode { log, graph }

class WeightHistoryScreen extends StatefulWidget {
  const WeightHistoryScreen({super.key});

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;
  String? _errorMessage;
  _ViewMode _viewMode = _ViewMode.log;

  // Converts a weight to kg so entries recorded in different units plot on
  // the same scale (mirrors the approach used for exercise weight charts).
  static const double _kgPerLb = 0.45359237;

  double _toKg(double weight, String unit) {
    switch (unit.toLowerCase()) {
      case 'lb':
        return weight * _kgPerLb;
      case 'kg':
      default:
        return weight;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final entries = await DBHelper().getBodyWeights();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatWeight(double weight) => formatWeight(weight);

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as int;
    final weightController = TextEditingController(
      text: _formatWeight((entry['weight'] as num).toDouble()),
    );
    String selectedUnit = entry['unit'] as String? ?? 'kg';
    DateTime selectedDate = entry['timestamp'] as DateTime;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit weight entry'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Weight',
                            ),
                            validator: (value) {
                              final trimmed = value?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return 'Required';
                              }
                              final parsed = double.tryParse(trimmed);
                              if (parsed == null || parsed <= 0) {
                                return 'Invalid';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: selectedUnit,
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(value: 'lb', child: Text('lb')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedUnit = value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              selectedDate.hour,
                              selectedDate.minute,
                            );
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(_formatDate(selectedDate)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    final newWeight = double.parse(weightController.text.trim());
    try {
      await DBHelper().updateBodyWeight(
        id,
        weight: newWeight,
        unit: selectedUnit,
        timestamp: selectedDate,
      );
      if (!mounted) return;
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as int;
    final weight = (entry['weight'] as num).toDouble();
    final unit = entry['unit'] as String? ?? '';
    final date = entry['timestamp'] as DateTime;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          '${_formatWeight(weight)} $unit on ${_formatDate(date)} will be '
          "removed. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await DBHelper().deleteBodyWeight(id);
      if (!mounted) return;
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildLogView() {
    if (_entries.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 64.0),
            child: Center(child: Text('No weight entries logged yet.')),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final weight = (entry['weight'] as num).toDouble();
        final unit = entry['unit'] as String? ?? '';
        final date = entry['timestamp'] as DateTime;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(
              '${_formatWeight(weight)} $unit'.trim(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(_formatDate(date)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editEntry(entry),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteEntry(entry),
                ),
              ],
            ),
            onTap: () => _editEntry(entry),
          ),
        );
      },
    );
  }

  Widget _buildGraphView() {
    final points =
        _entries
            .map(
              (entry) => BodyWeightPoint(
                date: entry['timestamp'] as DateTime,
                weightKg: _toKg(
                  (entry['weight'] as num).toDouble(),
                  entry['unit'] as String? ?? 'kg',
                ),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return BodyWeightChart(points: points);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Previous Weight')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: CupertinoSlidingSegmentedControl<_ViewMode>(
              groupValue: _viewMode,
              children: const {
                _ViewMode.log: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Log'),
                ),
                _ViewMode.graph: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Graph'),
                ),
              },
              onValueChanged: (value) {
                if (value == null) return;
                setState(() => _viewMode = value);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load weight history.\n$_errorMessage',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadEntries,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadEntries,
                    child: _viewMode == _ViewMode.log
                        ? _buildLogView()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                            child: _buildGraphView(),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
