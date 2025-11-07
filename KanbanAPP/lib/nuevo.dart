import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// instancia global
final FlutterLocalNotificationsPlugin notiPlugin =
FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración inicial Android
  const AndroidInitializationSettings initAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: initAndroid,
  );

  // Inicializar plugin
  await notiPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) {
      debugPrint('El user tocó la notificación. payload=${resp.payload}');
    },
  );

  // Pedir permiso en Android 13+
  await notiPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  runApp(const MyTestApp());
}

class MyTestApp extends StatelessWidget {
  const MyTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test Noti',
      theme: ThemeData.dark(),
      home: const NotiDemoPage(),
    );
  }
}

class NotiDemoPage extends StatelessWidget {
  const NotiDemoPage({super.key});

  Future<void> _showTestNotification() async {
    // Definición del canal/carácter de la notificación en Android
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'canal_pruebas', // id interno del canal
      'Notificaciones de Prueba', // nombre visible del canal
      channelDescription: 'Canal para probar notificaciones locales',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    // Disparar la notificación inmediata
    await notiPlugin.show(
      1, // ID interno (puede ser cualquier int)
      'Hola 👋',
      'Si ves esto, las notificaciones locales funcionan.',
      platformDetails,
      payload: 'payload_de_ejemplo',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba Notificación')),
      body: Center(
        child: ElevatedButton(
          onPressed: _showTestNotification,
          child: const Text('ENVIAR NOTIFICACIÓN'),
        ),
      ),
    );
  }
}
