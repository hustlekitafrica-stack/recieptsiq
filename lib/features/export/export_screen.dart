import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/receipt.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTimeRange? _range;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  List<Receipt> _filtered(List<Receipt> receipts) {
    if (_range == null) return receipts;
    return receipts
        .where((r) =>
            !r.date.isBefore(_range!.start) &&
            !r.date.isAfter(_range!.end))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _exportCsv(List<Receipt> receipts, String currency) async {
    setState(() => _exporting = true);
    try {
      final rows = <List<dynamic>>[
        ['Date', 'Merchant', 'Amount', 'Currency', 'Category', 'VAT', 'Notes'],
        ...receipts.map((r) => [
              DateFormat('yyyy-MM-dd').format(r.date),
              r.merchant,
              r.total.amount.toStringAsFixed(2),
              r.total.currency,
              r.category.label,
              r.vat?.amount.toStringAsFixed(2) ?? '',
              r.notes ?? '',
            ]),
      ];
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/expenses_${_rangeLabel()}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Expense Report ${_rangeLabel()}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf(List<Receipt> receipts, String currency) async {
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      final total =
          receipts.fold<double>(0, (s, r) => s + r.total.amount);
      final byCategory = <String, double>{};
      for (final r in receipts) {
        byCategory.update(r.category.label, (v) => v + r.total.amount,
            ifAbsent: () => r.total.amount);
      }
      final sortedCats = byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Business Expense Report',
                          style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(_rangeLabel(),
                          style: const pw.TextStyle(
                              fontSize: 13,
                              color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Text('ReceiptIQ',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#4F46E5'))),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0F4FF'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _pdfStat('Total Expenses',
                      Money(total, currency).format()),
                  _pdfStat('Receipts', receipts.length.toString()),
                  _pdfStat(
                      'Top Category',
                      sortedCats.isNotEmpty
                          ? sortedCats.first.key
                          : '—'),
                ],
              ),
            ),
            if (sortedCats.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text('Spending by Category',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#4F46E5')),
                    children: [
                      _pdfCell('Category', isHeader: true),
                      _pdfCell('Amount', isHeader: true),
                      _pdfCell('%', isHeader: true),
                    ],
                  ),
                  ...sortedCats.map((e) => pw.TableRow(children: [
                        _pdfCell(e.key),
                        _pdfCell(Money(e.value, currency).format()),
                        _pdfCell(total > 0
                            ? '${(e.value / total * 100).toStringAsFixed(1)}%'
                            : '—'),
                      ])),
                ],
              ),
            ],
            pw.SizedBox(height: 20),
            pw.Text('Receipt Detail',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.5),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: PdfColor.fromHex('#4F46E5')),
                  children: [
                    _pdfCell('Date', isHeader: true),
                    _pdfCell('Merchant', isHeader: true),
                    _pdfCell('Category', isHeader: true),
                    _pdfCell('Amount', isHeader: true),
                  ],
                ),
                ...receipts.map((r) => pw.TableRow(children: [
                      _pdfCell(DateFormat('dd/MM/yy').format(r.date)),
                      _pdfCell(r.merchant),
                      _pdfCell(r.category.label),
                      _pdfCell(r.total.format()),
                    ])),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated by ReceiptIQ · ${DateFormat('d MMM yyyy').format(DateTime.now())}',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/expense_report_${_rangeLabel()}.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Expense Report ${_rangeLabel()}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.Widget _pdfStat(String label, String value) {
    return pw.Column(children: [
      pw.Text(value,
          style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 2),
      pw.Text(label,
          style:
              const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
    ]);
  }

  pw.Widget _pdfCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight:
              isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  String _rangeLabel() {
    if (_range == null) return 'all_time';
    final fmt = DateFormat('MMMyyyy');
    final start = fmt.format(_range!.start).toLowerCase();
    final end = fmt.format(_range!.end).toLowerCase();
    return start == end ? start : '${start}_to_$end';
  }

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (receipts) {
          final filtered = _filtered(receipts);
          final total =
              filtered.fold<double>(0, (s, r) => s + r.total.amount);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _DateRangeCard(
                range: _range,
                onTap: _pickRange,
              ),
              const SizedBox(height: 16),
              _PreviewCard(
                count: filtered.length,
                total: total,
                currency: currency,
              ),
              const SizedBox(height: 24),
              if (filtered.isEmpty)
                const Center(
                  child: Text(
                    'No receipts in selected date range.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                )
              else ...[
                const Text('Export format',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                _ExportButton(
                  icon: Icons.table_chart_outlined,
                  title: 'Export as CSV',
                  subtitle:
                      'Opens in Excel or Google Sheets',
                  color: const Color(0xFF22C55E),
                  loading: _exporting,
                  onTap: () => _exportCsv(filtered, currency),
                ),
                const SizedBox(height: 10),
                _ExportButton(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Export as PDF',
                  subtitle: 'Formatted business expense report',
                  color: const Color(0xFFEF4444),
                  loading: _exporting,
                  onTap: () => _exportPdf(filtered, currency),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DateRangeCard extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onTap;
  const _DateRangeCard({required this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final label = range == null
        ? 'Select date range'
        : '${fmt.format(range!.start)} — ${fmt.format(range!.end)}';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.date_range_outlined,
            color: AppTheme.brand),
        title: const Text('Date range',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(label),
        trailing: const Icon(Icons.chevron_right,
            color: Color(0xFFCBD5E1)),
        onTap: onTap,
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final int count;
  final double total;
  final String currency;
  const _PreviewCard(
      {required this.count, required this.total, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.brand.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(count.toString(),
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brand)),
              const Text('receipts',
                  style: TextStyle(
                      color: Color(0xFF64748B), fontSize: 13)),
            ],
          ),
          Container(width: 1, height: 40, color: AppTheme.brand.withValues(alpha: 0.2)),
          Column(
            children: [
              Text(Money(total, currency).format(),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brand)),
              const Text('total',
                  style: TextStyle(
                      color: Color(0xFF64748B), fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ExportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.share_outlined,
            color: Color(0xFF94A3B8), size: 18),
        onTap: loading ? null : onTap,
      ),
    );
  }
}
