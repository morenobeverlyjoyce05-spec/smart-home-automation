import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const cBg = Color(0xFF0A1220), cCard = Color(0xFF121C30), cCard2 = Color(0xFF17233B);
const cLine = Color(0xFF1D2A45), cMut = Color(0xFF7F8CA8), cIc = Color(0xFF8FB0FF);
const cGrn = Color(0xFF22C55E), cBlu = Color(0xFF3B82F6), cYel = Color(0xFFFBBF24), cRed = Color(0xFFEF4444);
const rooms = ['Living Room', 'Kitchen', 'Bedroom', 'Hallway', 'Porch'];

class Al {
  final IconData i;
  final Color c;
  final String t, d, k, w;
  Al(this.i, this.c, this.t, this.d, this.k, this.w);
}

class Hub extends ChangeNotifier {
  WebSocketChannel? _ch;
  String status = 'Disconnected', ip = '192.168.4.1', scr = 'home', dtab = 'All', atab = 'All', scn = '';
  List<bool> L = List.filled(5, false);
  double br = 70, lim = 35, dthr = 50;
  bool lock = true, auto = true, sec = false, siren = false, ir = false, near = false, hot = false;
  int temp = 0, hum = 0, dist = 0;
  final log = <String>[];
  final alerts = <Al>[
    Al(Icons.directions_walk, cRed, 'Entry Detected', 'IR Sensor • Main Door', 'Security', 'Sep 28 • 09:42 PM'),
    Al(Icons.notifications_none, cRed, 'Siren Activated', 'Security Mode', 'Security', 'Sep 28 • 09:41 PM'),
    Al(Icons.shield_outlined, cBlu, 'System Arming', 'Security Mode On', 'System', 'Sep 28 • 07:50 PM'),
  ];
  bool get on => status == 'Connected';
  int get cnt => L.where((x) => x).length;

  void go(String s) { scr = s; notifyListeners(); }
  void upd(void Function() f) { f(); notifyListeners(); }
  String _now() {
    final d = DateTime.now();
    var h = d.hour % 12;
    if (h == 0) h = 12;
    return 'Today • ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
  void _al(IconData i, Color c, String t, String d, String k) => alerts.insert(0, Al(i, c, t, d, k, _now()));
  void _log(String s) { log.add(s); if (log.length > 40) log.removeAt(0); }
  void send(String m) { _log('> $m'); if (on) _ch!.sink.add(m); }

  Future<void> connect() async {
    _ch?.sink.close();
    status = 'Connecting';
    notifyListeners();
    try {
      final ch = WebSocketChannel.connect(Uri.parse('ws://$ip:81'));
      await ch.ready.timeout(const Duration(seconds: 5));
      _ch = ch;
      status = 'Connected';
      _log('connected to $ip');
      notifyListeners();
      ch.stream.listen(_rx, onDone: _lost, onError: (_) => _lost());
    } catch (_) {
      status = 'Disconnected';
      _log('connection failed');
      notifyListeners();
    }
  }
  void disconnect() { _ch?.sink.close(); _lost(); }
  void _lost() { _ch = null; status = 'Disconnected'; notifyListeners(); }

  void _rx(dynamic m) {
    final s = m.toString().trim();
    _log('< $s');
    final p = s.split(':');
    if (p.length < 2) { notifyListeners(); return; }
    final v = int.tryParse(p[1]) ?? 0;
    switch (p[0]) {
      case 'IR':
        ir = v == 1;
        if (ir) _al(Icons.directions_walk, cRed, 'Entry Detected', 'IR Sensor • Main Door', 'Security');
      case 'TEMP':
        temp = v;
        if (v >= lim && !hot) _al(Icons.thermostat, cRed, 'High Temperature', '$v°C (limit ${lim.round()}°C)', 'System');
        hot = v >= lim;
      case 'HUM':
        hum = v;
      case 'DIST':
        final n = v > 0 && v < dthr;
        if (n && !near) _al(Icons.sensors, cYel, 'Visitor at Door', 'Ultrasonic • $v cm', 'Security');
        near = n;
        dist = v;
    }
    notifyListeners();
  }

  void tog(int i) { L[i] = !L[i]; send('L$i:${L[i] ? 1 : 0}'); notifyListeners(); }
  void all(bool v) { for (var i = 0; i < 5; i++) { L[i] = v; send('L$i:${v ? 1 : 0}'); } notifyListeners(); }
  void setBr(double v) { br = v; send('BR:${v.round()}'); notifyListeners(); }
  void setLock(bool v) {
    lock = v;
    send('LOCK:${v ? 1 : 0}');
    _al(v ? Icons.lock_outline : Icons.door_front_door_outlined, v ? cGrn : cYel, v ? 'Door Locked' : 'Door Unlocked', 'Main Door', 'Security');
    notifyListeners();
  }
  void setSec(bool v) { sec = v; send('SEC:${v ? 1 : 0}'); notifyListeners(); }
  void setSiren(bool v) { siren = v; send('BZ:${v ? 1 : 0}'); notifyListeners(); }
  void scene(String n) {
    scn = n;
    if (n == 'Leaving Home' || n == 'Sleep') { all(false); setLock(true); setSec(n == 'Leaving Home'); }
    if (n == 'Party') { all(true); setSec(false); }
    if (n == 'Security Mode') { setSec(true); setLock(true); }
    _al(Icons.shield_outlined, cBlu, 'Scene: $n', 'Activated', 'System');
    notifyListeners();
  }

  String command(String raw) {
    final t = raw.toLowerCase();
    final off = RegExp(r'off|disarm|stop|close').hasMatch(t);
    final room = rooms.indexWhere((r) => t.contains(r.toLowerCase()));
    var m = "Di ko gets: $raw";
    if (t.contains('sleep')) { scene('Sleep'); m = 'Sleep mode on'; }
    else if (t.contains('party')) { scene('Party'); m = 'Party mode on'; }
    else if (t.contains('leaving')) { scene('Leaving Home'); m = 'Leaving Home on'; }
    else if (t.contains('security mode')) { scene('Security Mode'); m = 'Security Mode on'; }
    else if (RegExp(r'temp|humid').hasMatch(t)) { m = '$temp°C • $hum% humidity'; }
    else if (RegExp(r'siren|buzzer').hasMatch(t)) { setSiren(!off); m = 'Siren ${off ? 'off' : 'on'}'; }
    else if (RegExp(r'arm|security').hasMatch(t)) { setSec(!off); m = 'Security ${off ? 'disarmed' : 'armed'}'; }
    else if (t.contains('light')) {
      if (room >= 0) { L[room] = !off; send('L$room:${off ? 0 : 1}'); m = '${rooms[room]} light ${off ? 'off' : 'on'}'; }
      else { all(!off); m = 'All lights ${off ? 'off' : 'on'}'; }
    }
    else if (RegExp(r'open|unlock').hasMatch(t)) { setLock(false); m = 'Door unlocked'; }
    else if (RegExp(r'lock|close').hasMatch(t)) { setLock(true); m = 'Door locked'; }
    notifyListeners();
    return m;
  }
}

final hub = Hub();
final ipCtl = TextEditingController(text: hub.ip);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Smart Home',
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: cBg,
          colorScheme: ColorScheme.fromSeed(seedColor: cBlu, brightness: Brightness.dark),
          sliderTheme: const SliderThemeData(
              activeTrackColor: Color(0xFF4F8DF0), thumbColor: Color(0xFF4F8DF0), inactiveTrackColor: Color(0xFF26324D)),
        ),
        home: const Shell(),
      );
}

// ---------- reusable widgets ----------
Widget box({required Widget child, Color? border, VoidCallback? onTap, double mb = 10}) => Padding(
    padding: EdgeInsets.only(bottom: mb),
    child: GestureDetector(
        onTap: onTap,
        child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: border ?? cLine)),
            child: child)));

Widget ib(IconData i, {bool on = false, Color? bg, Color? fg, double s = 42}) => Container(
    width: s,
    height: s,
    decoration: BoxDecoration(
        color: bg ?? (on ? const Color(0xFF3A2F14) : cCard2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: on && bg == null ? [BoxShadow(color: cYel.withValues(alpha: .4), blurRadius: 14)] : null),
    child: Icon(i, size: s * .52, color: fg ?? (on ? cYel : cIc)));

Widget sw(bool v, ValueChanged<bool> f) => Switch(
    value: v,
    onChanged: f,
    thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFDBE3F5)),
    trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cGrn : const Color(0xFF2B3750)),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent));

Widget item(IconData i, String t, String s,
        {Widget? tr, VoidCallback? tap, bool on = false, Color? sc}) =>
    box(
        onTap: tap,
        child: Row(children: [
          ib(i, on: on),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 15)),
            Text(s, style: TextStyle(fontSize: 12, color: sc ?? (on ? cGrn : cMut))),
          ])),
          tr ?? const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
        ]));

Widget hdr(String t, {bool back = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      if (back)
        GestureDetector(
            onTap: () => hub.go('home'),
            child: const Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.arrow_back, size: 22))),
      Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    ]));

Widget h3(String t, {Widget? r}) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      if (r != null) r,
    ]));

Widget tabs(List<String> t, String cur, void Function(String) f) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final x in t)
        GestureDetector(
            onTap: () => f(x),
            child: Container(
                margin: const EdgeInsets.only(right: 6, bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: x == cur ? const Color(0xFF4F8DF0) : cCard, borderRadius: BorderRadius.circular(10)),
                child: Text(x, style: TextStyle(fontSize: 13, color: x == cur ? Colors.white : cMut)))),
    ]));

Widget chipb(IconData i, String t, VoidCallback f) => GestureDetector(
    onTap: f,
    child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: cLine)),
        child: Row(children: [
          Icon(i, size: 20, color: const Color(0xFF7FB0FF)),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
        ])));

Widget grid(int n, double ar, List<Widget> c) => GridView.count(
    crossAxisCount: n,
    childAspectRatio: ar,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: c);

Widget tile(IconData i, String t, String s, String to, {bool on = false, bool bad = false}) => GestureDetector(
    onTap: () => hub.go(to),
    child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C3766), cCard])
                : null,
            color: on ? null : cCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? const Color(0xFF3B6BD0) : cLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(i, size: 22, color: on ? const Color(0xFF9CC2FF) : const Color(0xFF7FB0FF)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 14)),
            Text(s, style: TextStyle(fontSize: 12, color: bad ? cRed : on ? cGrn : cMut)),
          ]),
        ])));

Widget ring(IconData? i, Color c, {double s = 130, Widget? ch}) => Container(
    width: s,
    height: s,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cCard,
        border: Border.all(color: c, width: 4),
        boxShadow: [BoxShadow(color: cBlu.withValues(alpha: .2), blurRadius: 40)]),
    child: ch ?? Icon(i, size: s * .42, color: cIc));

Widget btn(String t, VoidCallback f, {bool g = false}) => GestureDetector(
    onTap: f,
    child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: g ? cGrn : cCard2, borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(fontSize: 14, color: g ? const Color(0xFF052E16) : Colors.white, fontWeight: g ? FontWeight.w600 : FontWeight.normal))));

Widget btns(Widget a, Widget b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]));

Widget pill() => GestureDetector(
    onTap: () => hub.go('conn'),
    child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFF16233D), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF284070))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: hub.on ? cGrn : hub.status == 'Connecting' ? cYel : cMut),
          const SizedBox(width: 6),
          Text(hub.on ? 'WiFi' : hub.status == 'Connecting' ? 'Connecting' : 'Offline', style: const TextStyle(fontSize: 11)),
        ])));

Widget slider(String label, double v, double mn, double mx, String txt, void Function(double) f, {void Function(double)? end}) =>
    box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: cMut)),
      Row(children: [
        Expanded(child: Slider(value: v, min: mn, max: mx, onChanged: f, onChangeEnd: end)),
        Text(txt, style: const TextStyle(fontSize: 12, color: cMut)),
      ]),
    ]));

// ---------- shell + nav ----------
class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
      listenable: hub,
      builder: (_, _) {
        final m = <String, List<Widget> Function()>{
          'home': home, 'devices': devices, 'lights': lightsScr, 'lock': lockScr, 'security': securityScr,
          'climate': climateScr, 'scenes': scenesScr, 'voice': () => [hdr('Voice Control', back: false), const VoicePanel()],
          'alerts': alertsScr, 'conn': connScr,
        };
        return Scaffold(
            backgroundColor: cBg,
            body: SafeArea(
                child: Column(children: [
              Expanded(child: ListView(key: ValueKey(hub.scr), padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), children: m[hub.scr]!())),
              nav(),
            ])));
      });
}

Widget nav() {
  const items = [
    ('home', 'Home', Icons.home_outlined), ('devices', 'Devices', Icons.memory), ('scenes', 'Scenes', Icons.layers_outlined),
    ('voice', 'Voice', Icons.mic_none), ('alerts', 'Alerts', Icons.notifications_none),
  ];
  final act = ['lights', 'lock'].contains(hub.scr) ? 'devices' : ['security', 'climate', 'conn'].contains(hub.scr) ? 'home' : hub.scr;
  return Container(
      decoration: const BoxDecoration(color: Color(0xFF0B1424), border: Border(top: BorderSide(color: cLine))),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      child: Row(children: [
        for (final x in items)
          Expanded(
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => hub.go(x.$1),
                  child: Column(children: [
                    Icon(x.$3, size: 22, color: act == x.$1 ? const Color(0xFF5AA0FF) : cMut),
                    const SizedBox(height: 2),
                    Text(x.$2, style: TextStyle(fontSize: 11, color: act == x.$1 ? const Color(0xFF5AA0FF) : cMut)),
                  ]))),
      ]));
}

// ---------- screens ----------
List<Widget> home() => [
      Row(children: [
        const Icon(Icons.home_outlined, size: 28, color: cIc),
        const SizedBox(width: 10),
        const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('My Home', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          Text('Smart Home', style: TextStyle(fontSize: 12, color: cMut)),
        ])),
        pill(),
      ]),
      const SizedBox(height: 12),
      Container(
          height: 128,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A2A52), Color(0xFF0E1830)])),
          child: Stack(children: [
            Positioned(
                right: -20,
                top: -20,
                child: Opacity(
                    opacity: .15 + hub.cnt / 5 * .5,
                    child: Container(
                        width: 150,
                        height: 150,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [cYel, Colors.transparent]))))),
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Good Evening,', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  Text('${hub.sec ? 'Security armed' : 'Your home is ready.'} • ${hub.temp}°C • ${hub.hum}%',
                      style: const TextStyle(fontSize: 13, color: Color(0xFFAAB6D3))),
                ])),
          ])),
      const SizedBox(height: 12),
      grid(3, 1.05, [
        tile(Icons.lightbulb_outline, 'Lights', '${hub.cnt}/5 ON', 'lights', on: hub.cnt > 0),
        tile(hub.lock ? Icons.lock_outline : Icons.lock_open, 'Door Lock', hub.lock ? 'Locked' : 'Unlocked', 'lock', on: hub.lock),
        tile(Icons.shield_outlined, 'Security', hub.sec ? 'ARMED' : 'OFF', 'security', on: hub.sec),
        tile(Icons.directions_walk, 'IR Sensor', hub.ir ? 'Detected!' : 'Clear', 'security', on: !hub.ir, bad: hub.ir),
        tile(Icons.thermostat, 'Climate', '${hub.temp}°C', 'climate', on: true),
        tile(Icons.sensors, 'Visitor', hub.near ? 'Near!' : 'None', 'security', on: !hub.near, bad: hub.near),
      ]),
      h3('Quick Controls'),
      grid(2, 3.2, [
        chipb(Icons.shield_outlined, hub.sec ? 'Disarm' : 'Arm', () => hub.setSec(!hub.sec)),
        chipb(Icons.notifications_none, 'Siren ${hub.siren ? 'Off' : 'On'}', () => hub.setSiren(!hub.siren)),
        chipb(hub.lock ? Icons.lock_open : Icons.lock_outline, hub.lock ? 'Unlock Door' : 'Lock Door', () => hub.setLock(!hub.lock)),
        chipb(Icons.lightbulb_outline, 'All Lights ${hub.cnt > 0 ? 'Off' : 'On'}', () => hub.all(hub.cnt == 0)),
      ]),
      h3('Quick Scenes',
          r: GestureDetector(onTap: () => hub.go('scenes'), child: const Text('See All ›', style: TextStyle(fontSize: 12, color: cMut)))),
      grid(2, 3.2, [
        for (final s in sceneData) chipb(s.$2, s.$1, () => hub.scene(s.$1)),
      ]),
    ];

List<Widget> lightRows() => [
      for (var i = 0; i < 5; i++)
        item(Icons.lightbulb_outline, rooms[i], hub.L[i] ? 'On' : 'Off',
            on: hub.L[i], tr: sw(hub.L[i], (v) => hub.tog(i)), tap: () => hub.tog(i)),
    ];
Widget lockRow() => item(hub.lock ? Icons.lock_outline : Icons.lock_open, 'Main Door Lock (Servo)', hub.lock ? 'Locked' : 'Unlocked',
    on: hub.lock, tap: () => hub.go('lock'));
Widget irRow() => item(Icons.directions_walk, 'IR Sensor', hub.ir ? 'Entry detected!' : 'Clear', sc: hub.ir ? cRed : null, tap: () => hub.go('security'));
Widget usRow() => item(Icons.sensors, 'Ultrasonic', hub.dist == 0 ? 'No echo' : '${hub.dist} cm', tap: () => hub.go('security'));
Widget dhtRow() => item(Icons.thermostat, 'DHT11', '${hub.temp}°C • ${hub.hum}%', tap: () => hub.go('climate'));
Widget bzRow() => item(Icons.notifications_none, 'Buzzer (Siren)', hub.siren ? 'Sounding' : 'Off',
    on: hub.siren, tr: sw(hub.siren, hub.setSiren), tap: () => hub.setSiren(!hub.siren));

List<Widget> devices() {
  final f = hub.dtab;
  bool s(String x) => f == 'All' || f == x;
  return [
    hdr('Devices'),
    tabs(['All', 'Lights', 'Door', 'Sensors'], f, (x) => hub.upd(() => hub.dtab = x)),
    if (s('Lights')) ...lightRows(),
    if (s('Door')) lockRow(),
    if (s('Sensors')) ...[irRow(), usRow(), dhtRow(), bzRow()],
  ];
}

List<Widget> lightsScr() => [
      hdr('Lights'),
      ...lightRows(),
      btns(btn('All On', () => hub.all(true), g: true), btn('All Off', () => hub.all(false))),
      slider('Brightness (Living Room)', hub.br, 0, 100, '${hub.br.round()}%', (v) => hub.upd(() => hub.br = v), end: hub.setBr),
    ];

List<Widget> lockScr() => [
      hdr('Door Lock'),
      Center(
          child: Column(children: [
        ring(hub.lock ? Icons.lock_outline : Icons.lock_open, hub.lock ? cGrn : cYel),
        Text(hub.lock ? 'Locked' : 'Unlocked', style: const TextStyle(fontSize: 20)),
        Text('Servo ${hub.lock ? '0°' : '90°'}', style: const TextStyle(fontSize: 12, color: cMut)),
      ])),
      btns(btn('Unlock', () => hub.setLock(false), g: !hub.lock), btn('Lock', () => hub.setLock(true), g: hub.lock)),
      box(
          child: Row(children: [
        const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Auto Lock', style: TextStyle(fontSize: 15)),
          Text('Automatically lock after 5 minutes of being open.', style: TextStyle(fontSize: 12, color: cMut)),
        ])),
        sw(hub.auto, (v) => hub.upd(() => hub.auto = v)),
      ])),
    ];

List<Widget> securityScr() => [
      hdr('Security & Controls'),
      Center(
          child: Column(children: [
        ring(Icons.shield_outlined, hub.sec ? cGrn : const Color(0xFF26406E)),
        Text(hub.sec ? 'Armed' : 'Disarmed', style: const TextStyle(fontSize: 20)),
        Text(hub.sec ? 'IR and Ultrasonic are active.' : 'Siren off.', style: const TextStyle(fontSize: 12, color: cMut)),
      ])),
      btns(btn('Arm', () => hub.setSec(true), g: hub.sec), btn('Disarm', () => hub.setSec(false), g: !hub.sec)),
      bzRow(),
      irRow(),
      usRow(),
      slider('Alert Distance', hub.dthr, 20, 200, '${hub.dthr.round()} cm', (v) => hub.upd(() => hub.dthr = v)),
    ];

List<Widget> climateScr() => [
      hdr('Climate (DHT11)'),
      Center(
          child: Column(children: [
        ring(null, hub.temp >= hub.lim ? cRed : cBlu, ch: Center(child: Text('${hub.temp}°', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600)))),
        Text(hub.temp >= hub.lim ? 'High Temperature' : 'Normal Temperature', style: const TextStyle(fontSize: 12, color: cMut)),
      ])),
      const SizedBox(height: 12),
      box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Humidity ${hub.hum}%'),
        const SizedBox(height: 8),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (hub.hum / 100).clamp(0.0, 1.0), minHeight: 8, backgroundColor: const Color(0xFF26324D), color: cBlu)),
      ])),
      slider('High Temperature Alert Limit', hub.lim, 25, 45, '${hub.lim.round()}°C', (v) => hub.upd(() => hub.lim = v)),
    ];

const sceneData = [
  ('Leaving Home', Icons.home_outlined, 'All lights off • Door locked • Security on'),
  ('Sleep', Icons.nightlight_outlined, 'Lights off • Door locked • Security off'),
  ('Party', Icons.celebration_outlined, 'All lights on • Security off'),
  ('Security Mode', Icons.shield_outlined, 'Armed • Door locked • Siren if triggered'),
];

List<Widget> scenesScr() => [
      hdr('Scenes', back: false),
      for (final s in sceneData)
        box(
            border: hub.scn == s.$1 ? const Color(0xFF5AA0FF) : null,
            onTap: () => hub.scene(s.$1),
            child: Row(children: [
              ib(s.$2, s: 54, fg: const Color(0xFF7FB0FF)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$1, style: const TextStyle(fontSize: 15)),
                Text(s.$3, style: const TextStyle(fontSize: 12, color: cMut)),
              ])),
              Icon(hub.scn == s.$1 ? Icons.check : Icons.chevron_right, size: 20, color: Colors.white70),
            ])),
    ];

List<Widget> alertsScr() => [
      hdr('Alerts', back: false),
      tabs(['All', 'Security', 'System'], hub.atab, (x) => hub.upd(() => hub.atab = x)),
      for (final a in hub.alerts.where((a) => hub.atab == 'All' || a.k == hub.atab))
        box(
            child: Row(children: [
          ib(a.i, bg: a.c, fg: Colors.white, s: 48),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.t, style: const TextStyle(fontSize: 15)),
            Text(a.d, style: const TextStyle(fontSize: 12, color: cMut)),
            Text(a.w, style: const TextStyle(fontSize: 12, color: cMut)),
          ])),
          const Icon(Icons.chevron_right, size: 20, color: Colors.white70),
        ])),
    ];

void toggleConn() {
  if (hub.on) {
    hub.disconnect();
  } else if (hub.status != 'Connecting') {
    hub.connect();
  }
}

List<Widget> connScr() => [
      hdr('WiFi Connection'),
      box(
          child: Column(children: [
        Row(children: [
          ib(hub.on ? Icons.wifi : Icons.wifi_off, on: hub.on, fg: hub.on ? cGrn : cMut),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hub.on ? 'Connected to ESP32-S3' : hub.status == 'Connecting' ? 'Connecting…' : 'Not connected', style: const TextStyle(fontSize: 15)),
            const Text('WebSocket • port 81', style: TextStyle(fontSize: 12, color: cMut)),
          ])),
          Icon(Icons.circle, size: 10, color: hub.on ? cGrn : cMut),
        ]),
        const SizedBox(height: 14),
        TextField(
            controller: ipCtl,
            enabled: !hub.on,
            onChanged: (v) => hub.ip = v.trim(),
            decoration: const InputDecoration(labelText: 'ESP32 IP address', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: btn(hub.on ? 'Disconnect' : 'Connect', toggleConn, g: !hub.on)),
      ])),
      h3('Serial Monitor', r: GestureDetector(onTap: () => hub.upd(() => hub.log.clear()), child: const Text('Clear', style: TextStyle(fontSize: 12, color: cMut)))),
      Container(
          height: 170,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF060B14), borderRadius: BorderRadius.circular(12), border: Border.all(color: cLine)),
          child: ListView(reverse: true, children: [
            for (final l in hub.log.reversed)
              Text(l, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: l.startsWith('>') ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80))),
          ])),
      const SizedBox(height: 10),
      const Text('Connect your phone to the ESP32 WiFi (SmartHome-ESP32), then tap Connect.',
          style: TextStyle(fontSize: 12, color: cMut)),
    ];

// ---------- voice ----------
class VoicePanel extends StatefulWidget {
  const VoicePanel({super.key});
  @override
  State<VoicePanel> createState() => _VoiceState();
}

class _VoiceState extends State<VoicePanel> {
  final stt = SpeechToText();
  final ctl = TextEditingController();
  bool ready = false, listening = false;
  String msg = 'Tap mic or type…';

  void run(String t) {
    if (t.trim().isEmpty) return;
    setState(() => msg = hub.command(t));
    ctl.clear();
  }

  Future<void> mic() async {
    if (listening) {
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    if (!ready) ready = await stt.initialize(onError: (_) => setState(() => listening = false));
    if (!ready) {
      setState(() => msg = 'Mic not available. Type instead.');
      return;
    }
    setState(() => listening = true);
    await stt.listen(onResult: (r) {
      if (r.finalResult) {
        setState(() => listening = false);
        run(r.recognizedWords);
      }
    });
  }

  @override
  Widget build(BuildContext c) => Column(children: [
        GestureDetector(
            onTap: mic,
            child: Container(
                width: 110,
                height: 110,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16286B),
                    border: Border.all(color: const Color(0xFF4F6BF0), width: 3),
                    boxShadow: listening ? [BoxShadow(color: const Color(0xFF4F6BF0).withValues(alpha: .5), blurRadius: 30)] : null),
                child: const Icon(Icons.mic_none, size: 46, color: Color(0xFFC9D4FF)))),
        Text(listening ? 'Listening…' : msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Try saying:', style: TextStyle(fontSize: 12, color: cMut))),
        for (final s in ['Turn off the living room light', 'Arm the security', 'Open the door', "What's the temperature"])
          box(
              mb: 8,
              onTap: () => run(s),
              child: Center(child: Text('“$s”', style: const TextStyle(fontSize: 13)))),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: ctl,
                  onSubmitted: run,
                  decoration: InputDecoration(
                      hintText: 'Type a command…',
                      isDense: true,
                      filled: true,
                      fillColor: cCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: cLine))))),
          const SizedBox(width: 6),
          GestureDetector(
              onTap: () => run(ctl.text),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFF4F8DF0), borderRadius: BorderRadius.circular(10)),
                  child: const Text('Send'))),
        ]),
      ]);
}
