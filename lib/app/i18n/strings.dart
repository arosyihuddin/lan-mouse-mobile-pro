import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's display name. A brand string, not translated.
const String appName = 'Lan Mouse Pro';

/// The UI language (Indonesian or English), persisted across
/// launches. Defaults to the device language: Indonesian devices
/// get Indonesian, everything else gets English. Native surfaces
/// (the IME bar, the accessibility-service description) follow the
/// device language through Android's own resource system instead.
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const String _prefKey = 'app_language';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  bool get isIndonesian => _locale.languageCode == 'id';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      _locale = Locale(saved);
    } else {
      final device = ui.PlatformDispatcher.instance.locale.languageCode;
      _locale = Locale(device == 'id' ? 'id' : 'en');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (_locale.languageCode == languageCode) return;
    _locale = Locale(languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, languageCode);
  }
}

/// Translates [key] into the active language. Falls back to the
/// English text, then to the key itself, so a missing string is
/// visible in the UI instead of crashing it.
String tr(String key) {
  final table = LocaleController.instance.isIndonesian ? idStrings : enStrings;
  return table[key] ?? enStrings[key] ?? key;
}

const Map<String, String> enStrings = {
  'tagline': 'easily use your mouse and keyboard on multiple computers',
  'clientModeTitle': 'Controlled from a PC',
  'clientModeSubtitle': 'Client mode: receive keyboard & mouse from a desktop',
  'remoteSection': 'Remote',
  'remoteModeTitle': 'Control a PC',
  'remoteModeSubtitle': 'This device controls a PC',
  'language': 'Language',
  'general': 'General',
  'port': 'Port',
  'hostname': 'Hostname',
  'host': 'Host',
  'certFingerprint': 'Certificate Fingerprint',
  'hostnameCopied': 'Hostname copied to clipboard',
  'fingerprintCopied': 'Fingerprint copied to clipboard',
  'failedFingerprint': 'Failed to get fingerprint',
  'connections': 'Connections',
  'add': 'Add',
  'noClients': 'No Clients',
  'addClient': 'Add Client',
  'enterValidHost': 'Please enter valid host',
  'enterValidPort': 'Please enter valid port',
  'cancel': 'Cancel',
  'statusActive': 'Desktop connected - pointer is on this device',
  'statusConnected': 'Desktop connected - pointer is on the PC',
  'statusListening': 'Waiting for desktop - listening on UDP {port}',
  'statusStopped': 'Not listening',
  'statusCardSubtitle':
      'The desktop runs lan-mouse and crosses into this device '
          'through the screen edge. Move the cursor back to the edge '
          'facing the PC to return.',
  'startListening': 'Start Listening',
  'a11yRequired': 'Accessibility Service is not active - enable it first so the desktop cursor can appear on this device.',
  'openSettings': 'Open Settings',
  'stopListening': 'Stop Listening',
  'thisDevice': 'This Device',
  'copiedToClipboard': '{label} copied to clipboard',
  'setup': 'Setup',
  'a11yTitle': 'Accessibility Service (pointer)',
  'a11yOn': 'Active — cursor and clicks from the desktop run on this device.',
  'a11yOff': 'Must be active so the overlay cursor and clicks from the '
      'desktop work.',
  'keyboardTitle': 'Lan Mouse Pro Keyboard (typing)',
  'keyboardSubtitle':
      'Selected automatically when the PC pointer enters (if the '
          'system allows) and stays active until you change it '
          'manually; or tap to choose.',
  'androidKbSettings': 'Android Keyboard Settings',
  'androidKbSettingsSub':
      'All keyboards — where a new keyboard is enabled for the '
          'first time.',
  'onDesktop': 'On the desktop',
  'desktopSteps': '1. Run lan-mouse on the PC.\n'
      '2. Add a client: this device\'s hostname/IP, port 4242, '
      'position matching where the device sits relative to the '
      'monitor.\n'
      '3. On first connection, match the fingerprint on the PC '
      'with this device\'s fingerprint above, then authorize.\n'
      '4. Move the PC pointer past the screen edge toward this '
      'device.',
  'sensitivity': 'Sensitivity',
};

const Map<String, String> idStrings = {
  'tagline': 'gunakan mouse dan keyboard yang sama di banyak komputer '
      'dengan mudah',
  'clientModeTitle': 'Dikendalikan dari PC',
  'clientModeSubtitle': 'Mode client: terima keyboard & mouse dari desktop',
  'remoteSection': 'Remote',
  'remoteModeTitle': 'Mengendalikan PC',
  'remoteModeSubtitle': 'Perangkat ini mengendalikan PC',
  'language': 'Bahasa',
  'general': 'Umum',
  'port': 'Port',
  'hostname': 'Hostname',
  'host': 'Host',
  'certFingerprint': 'Fingerprint Sertifikat',
  'hostnameCopied': 'Hostname tersalin ke clipboard',
  'fingerprintCopied': 'Fingerprint tersalin ke clipboard',
  'failedFingerprint': 'Gagal mengambil fingerprint',
  'connections': 'Koneksi',
  'add': 'Tambah',
  'noClients': 'Belum ada client',
  'addClient': 'Tambah Client',
  'enterValidHost': 'Masukkan host yang valid',
  'enterValidPort': 'Masukkan port yang valid',
  'cancel': 'Batal',
  'statusActive': 'Desktop terhubung - pointer sedang di perangkat ini',
  'statusConnected': 'Desktop terhubung - pointer sedang di PC',
  'statusListening': 'Menunggu desktop - mendengarkan di UDP {port}',
  'statusStopped': 'Tidak mendengarkan',
  'statusCardSubtitle':
      'Desktop menjalankan lan-mouse dan menembus ke perangkat ini '
          'lewat tepi layar. Geser kursor kembali ke tepi yang menghadap '
          'PC untuk pulang.',
  'startListening': 'Mulai Mendengarkan',
  'a11yRequired': 'Layanan Aksesibilitas belum aktif - aktifkan dulu supaya kursor dari desktop bisa tampil di perangkat ini.',
  'openSettings': 'Buka Pengaturan',
  'stopListening': 'Berhenti Mendengarkan',
  'thisDevice': 'Perangkat Ini',
  'copiedToClipboard': '{label} tersalin ke clipboard',
  'setup': 'Persiapan',
  'a11yTitle': 'Layanan Aksesibilitas (pointer)',
  'a11yOn': 'Aktif — kursor dan klik dari desktop akan dijalankan di '
      'perangkat ini.',
  'a11yOff': 'Wajib aktif agar kursor overlay dan klik dari desktop '
      'berfungsi.',
  'keyboardTitle': 'Keyboard Lan Mouse Pro (ketikan)',
  'keyboardSubtitle': 'Dipilih otomatis saat pointer PC masuk (bila sistem '
      'mengizinkan) dan tetap aktif sampai diganti manual; atau '
      'ketuk untuk memilih.',
  'androidKbSettings': 'Pengaturan Keyboard Android',
  'androidKbSettingsSub':
      'Daftar semua keyboard — tempat mengaktifkan keyboard baru '
          'untuk pertama kali.',
  'onDesktop': 'Di desktop',
  'desktopSteps': '1. Jalankan lan-mouse di PC.\n'
      '2. Tambah client: hostname/IP perangkat ini, port 4242, '
      'posisi sesuai letak perangkat terhadap monitor.\n'
      '3. Saat pertama terhubung, cocokkan fingerprint di PC dengan '
      'fingerprint perangkat ini di atas, lalu otorisasi.\n'
      '4. Geser pointer PC melewati tepi layar ke arah perangkat ini.',
  'sensitivity': 'Sensitivitas',
};
