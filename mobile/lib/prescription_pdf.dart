import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

Future<String> exportPrescriptionPdf({
  required Map<String, dynamic> prescription,
  required Map<String, dynamic> patient,
  required Map<String, dynamic> doctor,
}) async {
  final document = pw.Document();
  final lines = (prescription['lignes'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SALAMA',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text('Centre de santé'),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'ORDONNANCE',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text('Date : ${prescription['date_emission'] ?? ''}'),
              ],
            ),
          ],
        ),
        pw.Divider(),
        pw.SizedBox(height: 16),
        pw.Text('Patient', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'),
        if (patient['date_naissance'] != null)
          pw.Text('Ne(e) le : ${patient['date_naissance']}'),
        pw.SizedBox(height: 16),
        pw.Text(
          'Dr ${doctor['nom'] ?? ''}${doctor['specialite'] == null ? '' : ' - ${doctor['specialite']}'}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        if (doctor['numero_ordre'] != null)
          pw.Text('No ordre : ${doctor['numero_ordre']}'),
        pw.SizedBox(height: 24),
        pw.TableHelper.fromTextArray(
          headers: const ['Medicament', 'Dosage', 'Frequence', 'Duree'],
          data: lines
              .map(
                (line) => [
                  line['medicament'] ?? '',
                  line['dosage'] ?? '',
                  line['frequence'] ?? '',
                  line['duree'] ?? '',
                ],
              )
              .toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellPadding: const pw.EdgeInsets.all(8),
        ),
        if (prescription['instructions_generales'] != null) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            'Instructions',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(prescription['instructions_generales'].toString()),
        ],
        pw.SizedBox(height: 56),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Signature et cachet'),
        ),
      ],
    ),
  );

  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/ordonnance_${prescription['id']}.pdf');
  await file.writeAsBytes(await document.save());
  return file.path;
}

Future<void> sharePrescriptionPdf(String path) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path)], text: 'Ordonnance Salama'),
  );
}

Future<String> downloadPrescriptionPdf({
  required String baseUrl,
  required String token,
  required String prescriptionId,
}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/v1/ordonnances/$prescriptionId/pdf'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
    throw Exception('Téléchargement impossible (${response.statusCode})');
  }

  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/ordonnance_$prescriptionId.pdf');
  await file.writeAsBytes(response.bodyBytes, flush: true);
  return file.path;
}
