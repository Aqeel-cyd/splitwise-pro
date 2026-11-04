import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_contacts/flutter_contacts.dart' show FlutterContacts;

import 'firebase_options.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BillSplitterApp());
}

bool _googleReady = false;

Future<UserCredential> signInWithGoogle() async {
  if (kIsWeb) {
    return await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
  }

  if (!_googleReady) {
    await GoogleSignIn.instance.initialize();
    _googleReady = true;
  }
  final account = await GoogleSignIn.instance.authenticate();
  final credential = GoogleAuthProvider.credential(
    idToken: account.authentication.idToken,
  );
  return await FirebaseAuth.instance.signInWithCredential(credential);
}

Future<void> signOut() async {
  if (!kIsWeb) await GoogleSignIn.instance.signOut();
  await FirebaseAuth.instance.signOut();
}

// ============================================================
//  Helpers
// ============================================================

const List<String> categories = [
  'Food',
  'Transport',
  'Stay',
  'Shopping',
  'Entertainment',
  'Bills',
  'Other',
];

// ============================================================
//  Moving background (changes colour when you pick something)
// ============================================================

/// The item the user picked last (a category or a member name).
final ValueNotifier<String?> bgSelection = ValueNotifier<String?>(null);

/// Goes up by one every time something is picked, to "kick" the motion.
final ValueNotifier<int> bgKick = ValueNotifier<int>(0);

const Map<String, Color> _catColors = {
  'Food': Colors.orange,
  'Transport': Colors.blue,
  'Stay': Colors.purple,
  'Shopping': Colors.pink,
  'Entertainment': Colors.amber,
  'Bills': Colors.red,
  'Other': Colors.blueGrey,
};

Color bgColorFor(String? key) {
  if (key == null) return Colors.teal;
  final known = _catColors[key];
  if (known != null) return known;
  // Member names: same name always gives the same colour.
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0xFFFF;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.65, 0.5).toColor();
}

void bgPick(String? key) {
  bgSelection.value = key;
  bgKick.value++;
}

class AnimatedBackground extends StatefulWidget {
  final bool dark;
  const AnimatedBackground({super.key, required this.dark});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  // Slow loop that keeps the background floating all the time.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  // Extra swirl that plays each time something is picked.
  late final AnimationController _kick = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    bgKick.addListener(_onKick);
  }

  void _onKick() {
    _kick.animateTo(
      _kick.value.floor() + 1.0,
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    bgKick.removeListener(_onKick);
    _loop.dispose();
    _kick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<String?>(
        valueListenable: bgSelection,
        builder: (context, key, _) {
          final target = bgColorFor(key);
          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: target),
            duration: const Duration(milliseconds: 900),
            builder: (context, color, _) {
              final c = color ?? target;
              return AnimatedBuilder(
                animation: Listenable.merge([_loop, _kick]),
                builder: (context, _) => _paint(c),
              );
            },
          );
        },
      ),
    );
  }

  Widget _paint(Color c) {
    final dark = widget.dark;
    final t = _loop.value * 2 * pi;
    final swirl = _kick.value * 2.2;
    final f = _kick.value - _kick.value.floorToDouble();
    final pulse = sin(f * pi); // 0 -> 1 -> 0 during a pick

    final base = dark ? const Color(0xFF0E1114) : Colors.white;
    final top = Color.lerp(base, c, dark ? 0.20 : 0.14)!;
    final bottom = Color.lerp(base, c, dark ? 0.42 : 0.34)!;
    final hsl = HSLColor.fromColor(c);

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final blobs = <Widget>[];
        for (var i = 0; i < 4; i++) {
          final phase = i * 1.7 + swirl;
          final size = min(w, h) * (0.55 + 0.1 * i) * (1 + 0.5 * pulse);
          final x = w * (0.5 + 0.45 * sin(t * (1 + i % 2) + phase));
          final y = h * (0.5 + 0.45 * cos(t * (1 + (i + 1) % 2) + phase * 0.8));
          final blob = hsl
              .withHue((hsl.hue + 35 * i) % 360)
              .withLightness(0.55)
              .toColor();
          blobs.add(
            Positioned(
              left: x - size / 2,
              top: y - size / 2,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      blob.withAlpha(dark ? 110 : 90),
                      blob.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 0.4 * sin(t), -1),
                    end: Alignment(1 - 0.4 * cos(t), 1),
                    colors: [top, bottom],
                  ),
                ),
              ),
            ),
            ...blobs,
          ],
        );
      },
    );
  }
}

String rs(double v) => 'Rs. ${v.toStringAsFixed(2)}';
String _two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', ''));
String newId() => DateTime.now().microsecondsSinceEpoch.toString();
String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

Map<String, double> _dmap(dynamic m) =>
    (m as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));

// ============================================================
//  Models
// ============================================================

enum SplitMode { equal, exact, percent, shares }

extension SplitModeLabel on SplitMode {
  String get label {
    switch (this) {
      case SplitMode.equal:
        return 'Equal';
      case SplitMode.exact:
        return 'Exact';
      case SplitMode.percent:
        return '%';
      case SplitMode.shares:
        return 'Shares';
    }
  }
}

class Expense {
  final String id;
  final String title;
  final String category;
  final DateTime date;
  final Map<String, double> payers; // member -> amount paid
  final SplitMode mode;
  final Map<String, double>
  weights; // member -> weight (1 / amount / % / shares)

  Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.date,
    required this.payers,
    required this.mode,
    required this.weights,
  });

  double get total => payers.values.fold(0.0, (s, v) => s + v);

  // Every mode is a proportional split of the total paid.
  // (So tax/tip on top of itemised amounts is shared proportionally.)
  Map<String, double> get shares {
    final w = weights.values.fold(0.0, (s, v) => s + v);
    if (w <= 0) return {};
    final t = total;
    return {for (final e in weights.entries) e.key: t * e.value / w};
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'date': date.toIso8601String(),
    'payers': payers,
    'mode': mode.name,
    'weights': weights,
  };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    title: j['title'] as String,
    category: j['category'] as String,
    date: DateTime.parse(j['date'] as String),
    payers: _dmap(j['payers']),
    mode: SplitMode.values.byName(j['mode'] as String),
    weights: _dmap(j['weights']),
  );
}

class Payment {
  final String id;
  final String from;
  final String to;
  final double amount;
  final DateTime date;

  Payment({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'amount': amount,
    'date': date.toIso8601String(),
  };

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: j['id'] as String,
    from: j['from'] as String,
    to: j['to'] as String,
    amount: (j['amount'] as num).toDouble(),
    date: DateTime.parse(j['date'] as String),
  );
}

class Transfer {
  final String from;
  final String to;
  final double amount;
  Transfer(this.from, this.to, this.amount);
}

class _Bal {
  final String name;
  double amount;
  _Bal(this.name, this.amount);
}

class Group {
  String id;
  String name;
  List<String> members;
  List<Expense> expenses;
  List<Payment> payments;

  Group({
    required this.id,
    required this.name,
    List<String>? members,
    List<Expense>? expenses,
    List<Payment>? payments,
  }) : members = members ?? [],
       expenses = expenses ?? [],
       payments = payments ?? [];

  factory Group.create(String name) => Group(id: newId(), name: name);

  double get totalSpent => expenses.fold(0.0, (s, e) => s + e.total);

  // Positive = is owed money, negative = owes money
  Map<String, double> balances() {
    final b = <String, double>{for (final m in members) m: 0.0};
    void add(String k, double v) => b[k] = (b[k] ?? 0) + v;
    for (final e in expenses) {
      e.payers.forEach((k, v) => add(k, v));
      e.shares.forEach((k, v) => add(k, -v));
    }
    for (final p in payments) {
      add(p.from, p.amount);
      add(p.to, -p.amount);
    }
    return b;
  }

  // Greedy simplification: biggest debtor pays biggest creditor
  List<Transfer> settlements() {
    final creditors = <_Bal>[];
    final debtors = <_Bal>[];
    balances().forEach((name, v) {
      if (v > 0.01) {
        creditors.add(_Bal(name, v));
      } else if (v < -0.01) {
        debtors.add(_Bal(name, -v));
      }
    });
    creditors.sort((a, b) => b.amount.compareTo(a.amount));
    debtors.sort((a, b) => b.amount.compareTo(a.amount));

    final result = <Transfer>[];
    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final pay = min(debtors[i].amount, creditors[j].amount);
      result.add(Transfer(debtors[i].name, creditors[j].name, pay));
      debtors[i].amount -= pay;
      creditors[j].amount -= pay;
      if (debtors[i].amount < 0.01) i++;
      if (creditors[j].amount < 0.01) j++;
    }
    return result;
  }

  Map<String, double> byCategory() {
    final m = <String, double>{};
    for (final e in expenses) {
      m[e.category] = (m[e.category] ?? 0) + e.total;
    }
    return m;
  }

  String summaryText() {
    final t = settlements();
    final sb = StringBuffer()
      ..writeln('Splitwise Pro - $name')
      ..writeln('Total spent: ${rs(totalSpent)}')
      ..writeln();
    if (t.isEmpty) {
      sb.writeln('Everyone is settled up.');
    } else {
      sb.writeln('Settle up:');
      for (final x in t) {
        sb.writeln('- ${x.from} pays ${x.to}: ${rs(x.amount)}');
      }
    }
    return sb.toString();
  }

  String csv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final sb = StringBuffer('Date,Title,Category,Total,Paid by,Split mode\n');
    for (final e in expenses) {
      final payers = e.payers.entries.map(
        (p) => '${p.key} ${p.value.toStringAsFixed(2)}',
      );
      sb.writeln(
        '${fmtDate(e.date)},${q(e.title)},${e.category},${e.total.toStringAsFixed(2)},${q(payers.join('; '))},${e.mode.label}',
      );
    }
    return sb.toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'payments': payments.map((p) => p.toJson()).toList(),
  };

  factory Group.fromJson(Map<String, dynamic> j) => Group(
    id: j['id'] as String,
    name: j['name'] as String,
    members: (j['members'] as List).cast<String>().toList(),
    expenses: (j['expenses'] as List)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList(),
    payments: (j['payments'] as List)
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ============================================================
//  Store (state + saving to the browser / device)
// ============================================================

class AppStore extends ChangeNotifier {
  static const _key = 'splitwise_pro_v1';

  List<Group> groups = [];
  String? currentId;
  bool dark = false;
  bool loaded = false;

  Group get current =>
      groups.firstWhere((g) => g.id == currentId, orElse: () => groups.first);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        groups = (j['groups'] as List)
            .map((g) => Group.fromJson(g as Map<String, dynamic>))
            .toList();
        currentId = j['currentId'] as String?;
        dark = j['dark'] as bool? ?? false;
      }
    } catch (_) {
      // Corrupt or missing data: start fresh
    }
    if (groups.isEmpty) {
      groups = [Group.create('My Group')];
      currentId = groups.first.id;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'groups': groups.map((g) => g.toJson()).toList(),
          'currentId': currentId,
          'dark': dark,
        }),
      );
    } catch (_) {}
  }

  // Call after any change
  void changed() {
    notifyListeners();
    _save();
  }
}

final AppStore store = AppStore();

// ============================================================
//  App
// ============================================================

class BillSplitterApp extends StatefulWidget {
  const BillSplitterApp({super.key});

  @override
  State<BillSplitterApp> createState() => _BillSplitterAppState();
}

class _BillSplitterAppState extends State<BillSplitterApp> {
  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Splitwise Pro',
          themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: store.loaded
              ? const AuthGate(child: HomeScreen())
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        );
      },
    );
  }
}

// ============================================================
//  Google sign-in
// ============================================================

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return child;
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _isSignUp = false;
  bool _hidePass = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email looks wrong';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password';
      case 'email-already-in-use':
        return 'This email already has an account. Try logging in';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return e.message ?? 'Sign-in failed';
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      _msg(_friendly(e));
    } catch (_) {
      _msg('Something went wrong. Try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.isEmpty) {
      _msg('Enter your email and password');
      return;
    }
    if (_isSignUp && pass != _confirm.text) {
      _msg('Passwords do not match');
      return;
    }
    await _run(() async {
      if (_isSignUp) {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: pass);
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: pass);
      }
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _msg('Type your email first');
      return;
    }
    await _run(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _msg('Password reset email sent');
    });
  }

  Future<void> _google() => _run(() async {
        await signInWithGoogle();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.receipt_long, size: 64, color: Colors.teal),
                const SizedBox(height: 12),
                const Text(
                  'Splitwise Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _hidePass,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hidePass
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _hidePass = !_hidePass),
                    ),
                  ),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _hidePass,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (!_isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _forgot,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  FilledButton(
                    onPressed: _submit,
                    child: Text(_isSignUp ? 'Create account' : 'Log in'),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('or'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google'),
                    onPressed: _google,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp
                        ? 'Already have an account? Log in'
                        : "Don't have an account? Sign up"),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final GlobalKey<_ExpenseFormState> _formKey = GlobalKey<_ExpenseFormState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _askText(String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _newGroup() async {
    final name = await _askText('New group (e.g., Galle trip)', '');
    if (name == null || name.isEmpty) return;
    final g = Group.create(name);
    _formKey.currentState?.reset();
    store.groups.add(g);
    store.currentId = g.id;
    store.changed();
  }

  Future<void> _renameGroup() async {
    final g = store.current;
    final name = await _askText('Rename group', g.name);
    if (name == null || name.isEmpty) return;
    g.name = name;
    store.changed();
  }

  Future<void> _deleteGroup() async {
    if (store.groups.length <= 1) {
      _snack('You need at least one group.');
      return;
    }
    final g = store.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${g.name}"?'),
        content: const Text('All its expenses and payments will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _formKey.currentState?.reset();
    store.groups.remove(g);
    store.currentId = store.groups.first.id;
    store.changed();
  }

  void _edit(Expense e) {
    _formKey.currentState?.loadForEdit(e);
    _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: AnimatedBackground(dark: store.dark)),
            Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            title: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: store.current.id,
                dropdownColor: Colors.teal.shade700,
                iconEnabledColor: Colors.white,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  for (final g in store.groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  _formKey.currentState?.reset();
                  store.currentId = id;
                  store.changed();
                },
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: () => signOut(),
              ),
              IconButton(
                tooltip: store.dark ? 'Light mode' : 'Dark mode',
                icon: Icon(store.dark ? Icons.light_mode : Icons.dark_mode),
                onPressed: () {
                  store.dark = !store.dark;
                  store.changed();
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'new') _newGroup();
                  if (v == 'rename') _renameGroup();
                  if (v == 'delete') _deleteGroup();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'new', child: Text('New group')),
                  PopupMenuItem(value: 'rename', child: Text('Rename group')),
                  PopupMenuItem(value: 'delete', child: Text('Delete group')),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(icon: Icon(Icons.add_circle_outline), text: 'Add'),
                Tab(icon: Icon(Icons.receipt_long), text: 'History'),
                Tab(icon: Icon(Icons.account_balance_wallet), text: 'Balances'),
              ],
            ),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: TabBarView(
                controller: _tabs,
                children: [
                  ExpenseForm(key: _formKey),
                  HistoryTab(onEdit: _edit),
                  const BalancesTab(),
                ],
              ),
            ),
          ),
        ),
          ],
        );
      },
    );
  }
}

// ============================================================
//  Tab 1: Add / edit expense (+ members)
// ============================================================

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key});

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm>
    with AutomaticKeepAliveClientMixin {
  final _title = TextEditingController();
  final _newMember = TextEditingController();
  String _category = categories.first;
  DateTime _date = DateTime.now();
  SplitMode _mode = SplitMode.equal;
  final Map<String, TextEditingController> _payers = {};
  final Map<String, TextEditingController> _parts = {};
  String? _editingId;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _title.dispose();
    _newMember.dispose();
    for (final c in _payers.values) {
      c.dispose();
    }
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void reset() {
    if (!mounted) return;
    setState(() {
      _payers.clear();
      _parts.clear();
      _editingId = null;
      _title.clear();
      _category = categories.first;
      _date = DateTime.now();
      _mode = SplitMode.equal;
    });
  }

  void loadForEdit(Expense e) {
    setState(() {
      _payers.clear();
      _parts.clear();
      _editingId = e.id;
      _title.text = e.title;
      _category = e.category;
      _date = e.date;
      _mode = e.mode;
      e.payers.forEach(
        (k, v) => _payers[k] = TextEditingController(text: _plain(v)),
      );
      e.weights.forEach(
        (k, v) => _parts[k] = TextEditingController(
          text: e.mode == SplitMode.equal ? '' : _plain(v),
        ),
      );
    });
  }

  double get _draftTotal =>
      _payers.values.fold(0.0, (s, c) => s + (parseNum(c.text) ?? 0));

  void _addMember() {
    final g = store.current;
    final name = _newMember.text.trim();
    if (name.isEmpty) return;
    if (g.members.any((m) => m.toLowerCase() == name.toLowerCase())) {
      _snack('"$name" is already in this group.');
      return;
    }
    g.members.add(name);
    _newMember.clear();
    store.changed();
  }

  Future<void> _pickFromContacts() async {
    final onPhone = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!onPhone) {
      _snack('Contacts work only in the phone app (Android or iPhone), not in Chrome.');
      return;
    }
    try {
      final ok = await FlutterContacts.requestPermission(readonly: true);
      if (!ok) {
        _snack('Contacts permission was denied. Allow it in your phone Settings.');
        return;
      }
      final all = await FlutterContacts.getContacts();
      final names = all
          .map((c) => c.displayName.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      final g = store.current;
      final picked = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ContactPickerSheet(names: names, existing: g.members),
      );
      if (picked == null || picked.isEmpty) return;
      var added = 0;
      for (final n in picked) {
        if (g.members.any((m) => m.toLowerCase() == n.toLowerCase())) continue;
        g.members.add(n);
        added++;
      }
      store.changed();
      _snack('Added $added member(s) from contacts.');
    } catch (_) {
      _snack('Could not open contacts on this device.');
    }
  }

  void _removeMember(String m) {
    final g = store.current;
    final used =
        g.expenses.any(
          (e) => e.payers.containsKey(m) || e.weights.containsKey(m),
        ) ||
        g.payments.any((p) => p.from == m || p.to == m);
    if (used) {
      _snack('$m is used in saved expenses or payments, so can\'t be removed.');
      return;
    }
    setState(() {
      _payers.remove(m);
      _parts.remove(m);
    });
    g.members.remove(m);
    store.changed();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  void _save() {
    final g = store.current;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('Please enter an expense name.');
      return;
    }

    final payers = <String, double>{};
    for (final e in _payers.entries) {
      final amt = parseNum(e.value.text);
      if (amt == null || amt <= 0) {
        _snack('Enter an amount greater than 0 for ${e.key}.');
        return;
      }
      payers[e.key] = amt;
    }
    if (payers.isEmpty) {
      _snack('Select who paid and enter the amounts.');
      return;
    }
    if (_parts.isEmpty) {
      _snack('Select who shares this expense.');
      return;
    }
    final total = payers.values.fold(0.0, (s, v) => s + v);

    final weights = <String, double>{};
    for (final e in _parts.entries) {
      if (_mode == SplitMode.equal) {
        weights[e.key] = 1;
      } else {
        final w = parseNum(e.value.text);
        if (w == null || w <= 0) {
          _snack('Enter a value greater than 0 for ${e.key}.');
          return;
        }
        weights[e.key] = w;
      }
    }
    final wsum = weights.values.fold(0.0, (s, v) => s + v);
    if (_mode == SplitMode.percent && (wsum - 100).abs() > 0.01) {
      _snack(
        'Percentages add up to ${wsum.toStringAsFixed(1)}%, they must total 100%.',
      );
      return;
    }
    if (_mode == SplitMode.exact && wsum > total + 0.01) {
      _snack(
        'Itemised amounts (${rs(wsum)}) are more than the total paid (${rs(total)}).',
      );
      return;
    }

    final expense = Expense(
      id: _editingId ?? newId(),
      title: title,
      category: _category,
      date: _date,
      payers: payers,
      mode: _mode,
      weights: weights,
    );

    if (_editingId != null) {
      final i = g.expenses.indexWhere((e) => e.id == _editingId);
      if (i >= 0) {
        g.expenses[i] = expense;
      } else {
        g.expenses.insert(0, expense);
      }
    } else {
      g.expenses.insert(0, expense);
    }
    final wasEditing = _editingId != null;
    reset();
    store.changed();
    _snack(wasEditing ? 'Expense updated' : 'Expense added');
  }

  Widget _splitSummary() {
    if (_parts.isEmpty) return const SizedBox.shrink();
    final total = _draftTotal;
    String text;
    if (_mode == SplitMode.equal) {
      text = total > 0
          ? 'Each of ${_parts.length} pays ${rs(total / _parts.length)}'
          : 'Each of ${_parts.length} pays an equal share';
    } else {
      final sum = _parts.values.fold(
        0.0,
        (s, c) => s + (parseNum(c.text) ?? 0),
      );
      if (_mode == SplitMode.percent) {
        text = 'Percent total: ${sum.toStringAsFixed(1)}% of 100%';
      } else if (_mode == SplitMode.exact) {
        text = 'Itemised ${rs(sum)} of ${rs(total)}';
        if (sum < total - 0.01) {
          text +=
              '. The remaining ${rs(total - sum)} (tax/tip) is shared in proportion.';
        }
      } else {
        text = 'Total shares: ${_plain(sum)}';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final g = store.current;
    final theme = Theme.of(context);
    // Drop selections of members that no longer exist (e.g. after switching group)
    _payers.removeWhere((k, _) => !g.members.contains(k));
    _parts.removeWhere((k, _) => !g.members.contains(k));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Members ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group members',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (g.members.isEmpty)
                  const Text('Add the people in this group first.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in g.members)
                      Chip(label: Text(m), onDeleted: () => _removeMember(m)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newMember,
                        onSubmitted: (_) => _addMember(),
                        decoration: const InputDecoration(
                          labelText: 'New member name',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.person_add_alt),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Add from contacts',
                      icon: const Icon(Icons.contacts),
                      onPressed: _pickFromContacts,
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addMember,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Editing banner ----
        if (_editingId != null)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editing an expense'),
              trailing: TextButton(
                onPressed: reset,
                child: const Text('Cancel'),
              ),
            ),
          ),

        // ---- Title, category, date ----
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Expense Name (e.g., Lunch, Taxi)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.receipt),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in categories)
              ChoiceChip(
                label: Text(c),
                selected: _category == c,
                onSelected: (_) {
                  bgPick(c);
                  setState(() => _category = c);
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${fmtDate(_date)}'),
          ),
        ),
        const Divider(height: 32),

        // ---- Who paid ----
        Text(
          'Who paid?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        if (g.members.isEmpty) const Text('Add members above to continue.'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in g.members)
              FilterChip(
                label: Text(m),
                selected: _payers.containsKey(m),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    bgPick(m);
                    _payers[m] = TextEditingController();
                  } else {
                    _payers.remove(m);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final e in _payers.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${e.key} paid',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Amount (Rs.)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_payers.isNotEmpty)
          Text(
            'Expense total: ${rs(_draftTotal)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        const Divider(height: 32),

        // ---- Who shares ----
        Row(
          children: [
            Expanded(
              child: Text(
                'Who shares it?',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final m in g.members) {
                  _parts.putIfAbsent(m, () => TextEditingController());
                }
              }),
              child: const Text('Select all'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in g.members)
              FilterChip(
                label: Text(m),
                selected: _parts.containsKey(m),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    bgPick(m);
                    _parts[m] = TextEditingController();
                  } else {
                    _parts.remove(m);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<SplitMode>(
          showSelectedIcon: false,
          segments: [
            for (final m in SplitMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        if (_mode != SplitMode.equal)
          for (final e in _parts.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.key, style: const TextStyle(fontSize: 15)),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: e.value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _mode == SplitMode.exact
                            ? 'Amount (Rs.)'
                            : _mode == SplitMode.percent
                            ? 'Percent (%)'
                            : 'Shares',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        _splitSummary(),
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          icon: Icon(_editingId != null ? Icons.save : Icons.add),
          label: Text(
            _editingId != null
                ? 'Save changes'
                : 'Add Expense & Calculate Owed',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ============================================================
//  Tab 2: History
// ============================================================

class HistoryTab extends StatefulWidget {
  final void Function(Expense) onEdit;
  const HistoryTab({super.key, required this.onEdit});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  String? _filter; // category filter

  void _deleteExpense(Group g, int index) {
    final removed = g.expenses.removeAt(index);
    store.changed();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${removed.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              g.expenses.insert(min(index, g.expenses.length), removed);
              store.changed();
            },
          ),
        ),
      );
  }

  void _deletePayment(Group g, int index) {
    final removed = g.payments.removeAt(index);
    store.changed();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Payment removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              g.payments.insert(min(index, g.payments.length), removed);
              store.changed();
            },
          ),
        ),
      );
  }

  Widget _expenseCard(Group g, int index) {
    final e = g.expenses[index];
    final shares = e.shares;
    final people = <String>{...e.payers.keys, ...shares.keys};
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${e.title} - ${rs(e.total)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => widget.onEdit(e),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteExpense(g, index),
                ),
              ],
            ),
            Text(
              '${e.category}  •  ${fmtDate(e.date)}  •  split: ${e.mode.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Paid by: ${e.payers.entries.map((p) => '${p.key} (${rs(p.value)})').join(', ')}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Divider(height: 14),
            for (final p in people)
              Builder(
                builder: (_) {
                  final paid = e.payers[p] ?? 0.0;
                  final share = shares[p] ?? 0.0;
                  final net = paid - share;
                  final result = net > 0.005
                      ? 'gets back ${rs(net)}'
                      : net < -0.005
                      ? 'owes ${rs(-net)}'
                      : 'is even';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '👉 $p: paid ${rs(paid)}, share ${rs(share)} → $result',
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = store.current;
    final usedCats = g.expenses.map((e) => e.category).toSet();
    if (_filter != null && !usedCats.contains(_filter)) _filter = null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (usedCats.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) {
                    bgPick(null);
                    setState(() => _filter = null);
                  },
                ),
                for (final c in categories.where(usedCats.contains))
                  ChoiceChip(
                    label: Text(c),
                    selected: _filter == c,
                    onSelected: (_) {
                      bgPick(c);
                      setState(() => _filter = c);
                    },
                  ),
              ],
            ),
          ),
        if (g.expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No expenses added yet. Add one in the Add tab!',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        for (int i = 0; i < g.expenses.length; i++)
          if (_filter == null || g.expenses[i].category == _filter)
            _expenseCard(g, i),
        if (g.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Payments recorded',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          for (int i = 0; i < g.payments.length; i++)
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(
                  '${g.payments[i].from} paid ${g.payments[i].to}: ${rs(g.payments[i].amount)}',
                ),
                subtitle: Text(fmtDate(g.payments[i].date)),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deletePayment(g, i),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ============================================================
//  Tab 3: Balances, settlement, category summary, export
// ============================================================

class BalancesTab extends StatelessWidget {
  const BalancesTab({super.key});

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addPayment(Group g, String from, String to, double amount) {
    g.payments.insert(
      0,
      Payment(
        id: newId(),
        from: from,
        to: to,
        amount: amount,
        date: DateTime.now(),
      ),
    );
    store.changed();
  }

  // Lets the payer enter how much they actually paid now.
  // The rest stays in the settle-up list until it is paid.
  Future<void> _partialPayment(
    BuildContext context,
    Group g,
    Transfer t,
  ) async {
    final c = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.from} pays ${t.to}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Still owed: ${rs(t.amount)}'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount paid now (Rs.)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, parseNum(v)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseNum(c.text)),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    if (!context.mounted) return;
    if (amount <= 0 || amount > t.amount + 0.01) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Enter an amount between 0 and ${rs(t.amount)}.'),
          ),
        );
      return;
    }
    _addPayment(g, t.from, t.to, min(amount, t.amount));
  }

  @override
  Widget build(BuildContext context) {
    final g = store.current;
    final theme = Theme.of(context);
    final balances = g.balances().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final transfers = g.settlements();
    final cats = g.byCategory().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = g.totalSpent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Total ----
        Card(
          elevation: 4,
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Expenses:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  rs(total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Per-person balances ----
        const Text(
          'Balance per person',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (balances.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Add members and expenses to see balances.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final b in balances)
          Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.person),
              title: Text(b.key),
              trailing: Text(
                b.value.abs() < 0.01
                    ? 'settled'
                    : b.value > 0
                    ? '+${rs(b.value)}'
                    : '-${rs(-b.value)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: b.value.abs() < 0.01
                      ? null
                      : b.value > 0
                      ? Colors.green.shade600
                      : Colors.red.shade400,
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),

        // ---- Settlement ----
        Card(
          elevation: 3,
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settle up (fewest payments)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                if (transfers.isEmpty)
                  Text(
                    'Everyone is settled up. 🎉',
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  )
                else
                  for (final t in transfers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💸 ${t.from} pays ${t.to}: ${rs(t.amount)}',
                            style: TextStyle(
                              fontSize: 15,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _addPayment(g, t.from, t.to, t.amount),
                                child: const Text('Paid in full'),
                              ),
                              TextButton(
                                onPressed: () => _partialPayment(context, g, t),
                                child: const Text('Partial payment'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copy(
                        context,
                        g.summaryText(),
                        'Summary copied. Paste it into WhatsApp.',
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy summary'),
                    ),
                    OutlinedButton.icon(
                      onPressed: g.expenses.isEmpty
                          ? null
                          : () => _copy(
                              context,
                              g.csv(),
                              'CSV copied. Paste it into Excel or Sheets.',
                            ),
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('Copy CSV'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Spending by category ----
        if (cats.isNotEmpty) ...[
          const Text(
            'Spending by category',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.key),
                      Text(
                        '${rs(c.value)}  (${(c.value / total * 100).toStringAsFixed(0)}%)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total > 0 ? c.value / total : 0,
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ============================================================
//  Pick members from the phone's contact list
// ============================================================

class _ContactPickerSheet extends StatefulWidget {
  final List<String> names;
  final List<String> existing;
  const _ContactPickerSheet({required this.names, required this.existing});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final Set<String> _chosen = {};
  String _q = '';

  bool _isIn(String n) =>
      widget.existing.any((m) => m.toLowerCase() == n.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final shown = widget.names
        .where((n) => n.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                'Pick from contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No contacts found'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final n = shown[i];
                          final already = _isIn(n);
                          return CheckboxListTile(
                            title: Text(n),
                            subtitle:
                                already ? const Text('Already in this group') : null,
                            value: already || _chosen.contains(n),
                            onChanged: already
                                ? null
                                : (v) => setState(() {
                                      if (v == true) {
                                        _chosen.add(n);
                                      } else {
                                        _chosen.remove(n);
                                      }
                                    }),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, _chosen.toList()),
                    child: Text(
                      _chosen.isEmpty
                          ? 'Select contacts'
                          : 'Add ${_chosen.length} member(s)',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}