// lib/main.dart
// Wortbit DE – German B1 Vocabulary Flashcard App
// AMOLED dark theme · SRS queue · lockscreen-aware overlay

import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/word_model.dart';
import 'services/tts_service.dart';
import 'services/lockscreen_service.dart';

// ─────────────────────────── Entry point ────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Start the lockscreen foreground service immediately on launch.
  // The service registers a BroadcastReceiver for ACTION_SCREEN_ON and
  // brings MainActivity to front (with FLAG_SHOW_WHEN_LOCKED) every time
  // the user presses the power button.
  await LockScreenService.start();

  runApp(const WortbitApp());
}

// ─────────────────────────── Root app ───────────────────────────────────────

class WortbitApp extends StatelessWidget {
  const WortbitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wortbit DE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF121212),
          primary: Color(0xFF2196F3),
          secondary: Color(0xFF4CAF50),
          error: Color(0xFFF44336),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const FlashcardScreen(),
    );
  }
}

// ─────────────────────────── Colour helpers ──────────────────────────────────

Color _articleColor(String article) {
  switch (article.toLowerCase()) {
    case 'der':
      return const Color(0xFF2196F3);
    case 'die':
      return const Color(0xFFF44336);
    case 'das':
      return const Color(0xFF4CAF50);
    default:
      return const Color(0xFFFFC107);
  }
}

String _articleLabel(String article) {
  switch (article.toLowerCase()) {
    case 'der':
      return 'DER';
    case 'die':
      return 'DIE';
    case 'das':
      return 'DAS';
    case 'verb':
      return 'VERB';
    case 'adj':
      return 'ADJ';
    case 'prep':
      return 'PRÄP';
    default:
      return article.toUpperCase();
  }
}

// ─────────────────────────── SRS logic ──────────────────────────────────────

class _SrsEntry {
  int interval;
  DateTime nextReview;

  _SrsEntry({this.interval = 1}) : nextReview = DateTime.now();

  void advance() {
    interval = (interval * 2).clamp(1, 64);
    nextReview = DateTime.now().add(Duration(days: interval));
  }

  void reset() {
    interval = 1;
    nextReview = DateTime.now();
  }
}

// ─────────────────────────── Main screen ────────────────────────────────────

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with TickerProviderStateMixin {
  // ── data
  List<WordModel> _allWords = [];
  List<WordModel> _queue = [];
  int _queueIndex = 0;
  bool _isLoaded = false;
  int _doneToday = 0;

  // ── SRS
  final Map<int, _SrsEntry> _srs = {};

  // ── UI state
  bool _meaningRevealed = false;
  bool _isSliding = false;
  bool _lockscreenEnabled = true;

  // ── services
  final TtsService _tts = TtsService();
  late SharedPreferences _prefs;

  // ── animations
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _revealController;
  late Animation<double> _blurAnimation;

  // ── filter
  Set<String> _activeArticles = {
    'der', 'die', 'das', 'verb', 'adj', 'prep'
  };
  bool _showFilterPanel = false;
  bool _showSettings = false;

  // ─────────────────────── Lifecycle ──────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _bootstrap();
  }

  void _initAnimations() {
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.2, 0),
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
    );

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _blurAnimation = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOut),
    );
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    await _tts.init();
    _lockscreenEnabled = _prefs.getBool('lockscreen_enabled') ?? true;
    await _loadWords();
    _buildQueue();
    setState(() => _isLoaded = true);
  }

  Future<void> _loadWords() async {
    final raw = await rootBundle.loadString('assets/data/words.json');
    final List<dynamic> jsonList = json.decode(raw) as List<dynamic>;
    _allWords = jsonList
        .map((e) => WordModel.fromJson(e as Map<String, dynamic>))
        .toList();

    for (final w in _allWords) {
      final key = 'srs_interval_${w.id}';
      final saved = _prefs.getInt(key) ?? 1;
      _srs[w.id] = _SrsEntry(interval: saved);
    }

    _doneToday = _prefs.getInt('done_today') ?? 0;
  }

  void _buildQueue() {
    final now = DateTime.now();
    final filtered = _allWords
        .where((w) => _activeArticles.contains(w.article.toLowerCase()))
        .toList();

    final due = filtered
        .where((w) => (_srs[w.id]?.nextReview ?? now).isBefore(now))
        .toList()
      ..shuffle(Random());

    final notDue = filtered
        .where((w) => !(_srs[w.id]?.nextReview ?? now).isBefore(now))
        .toList()
      ..shuffle(Random());

    _queue = [...due, ...notDue];
    if (_queue.isEmpty) _queue = [...filtered]..shuffle(Random());
    _queueIndex = 0;
  }

  WordModel get _current => _queue[_queueIndex % _queue.length];

  // ─────────────────────── SRS actions ────────────────────────────────────

  Future<void> _onKnow() async {
    if (_isSliding) return;
    HapticFeedback.lightImpact();
    _srs[_current.id]?.advance();
    await _prefs.setInt('srs_interval_${_current.id}',
        _srs[_current.id]?.interval ?? 1);
    _doneToday++;
    await _prefs.setInt('done_today', _doneToday);
    await _animateToNext();
  }

  Future<void> _onDontKnow() async {
    if (_isSliding) return;
    HapticFeedback.selectionClick();
    _srs[_current.id]?.reset();
    await _prefs.setInt('srs_interval_${_current.id}', 1);
    final word = _queue.removeAt(_queueIndex % _queue.length);
    _queue.add(word);
    await _animateToNext();
  }

  Future<void> _animateToNext() async {
    setState(() => _isSliding = true);
    await _slideController.forward();
    await _tts.stop();
    setState(() {
      _queueIndex++;
      _meaningRevealed = false;
      _isSliding = false;
    });
    _slideController.reset();
    _revealController.reset();
  }

  // ─────────────────────── Reveal ─────────────────────────────────────────

  void _revealMeaning() {
    if (_meaningRevealed) return;
    setState(() => _meaningRevealed = true);
    _revealController.forward();
  }

  // ─────────────────────── TTS ────────────────────────────────────────────

  Future<void> _speakWord() async {
    final w = _current;
    final isNoun = ['der', 'die', 'das'].contains(w.article.toLowerCase());
    final text = isNoun ? '${w.article} ${w.german}' : w.german;
    await _tts.speak(text);
  }

  // ─────────────────────── Lockscreen toggle ───────────────────────────────

  Future<void> _toggleLockscreen(bool value) async {
    setState(() => _lockscreenEnabled = value);
    await _prefs.setBool('lockscreen_enabled', value);
    if (value) {
      await LockScreenService.start();
    } else {
      await LockScreenService.stop();
    }
  }

  // ─────────────────────── Filter ─────────────────────────────────────────

  void _toggleFilter() =>
      setState(() => _showFilterPanel = !_showFilterPanel);

  void _toggleArticle(String art) {
    setState(() {
      if (_activeArticles.contains(art)) {
        if (_activeArticles.length > 1) _activeArticles.remove(art);
      } else {
        _activeArticles.add(art);
      }
    });
    _buildQueue();
  }

  // ─────────────────────── Dispose ────────────────────────────────────────

  @override
  void dispose() {
    _slideController.dispose();
    _revealController.dispose();
    _tts.dispose();
    super.dispose();
  }

  // ─────────────────────── Build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2196F3)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            SlideTransition(
              position: _slideAnimation,
              child: _buildCardPage(),
            ),
            if (_showFilterPanel) _buildFilterOverlay(),
            if (_showSettings) _buildSettingsOverlay(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── Card page ──────────────────────────────────────

  Widget _buildCardPage() {
    final word = _current;
    final accentColor = _articleColor(word.article);
    final total = _allWords.length;

    return Column(
      children: [
        _buildTopBar(word, accentColor),
        // Progress row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_doneToday / $total từ hôm nay',
                style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: total > 0 ? _doneToday / total : 0,
                backgroundColor: const Color(0xFF222222),
                color: accentColor,
                minHeight: 2,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                _buildHeroWord(word, accentColor),
                const SizedBox(height: 8),
                _buildSubInfo(word, accentColor),
                const SizedBox(height: 18),
                Expanded(child: _buildMeaningCard(word, accentColor)),
                const SizedBox(height: 12),
                _buildExampleCard(word, accentColor),
                const SizedBox(height: 10),
                // Swipe hint
                Text(
                  'VUỐT PHẢI: ĐÃ THUỘC  ·  VUỐT TRÁI: CHƯA THUỘC',
                  style: TextStyle(
                    color: const Color(0xFF333333),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionRow(),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────── Top bar ────────────────────────────────────────

  Widget _buildTopBar(WordModel word, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Row(
        children: [
          // CEFR badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: accentColor, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '[${word.level}] Telc / Goethe',
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          // Lockscreen status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _lockscreenEnabled
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              color: _lockscreenEnabled
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFF555555),
              size: 16,
            ),
          ),
          _IconBtn(
            icon: Icons.volume_up_rounded,
            color: const Color(0xFFBBBBBB),
            onTap: _speakWord,
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.tune_rounded,
            color: _showFilterPanel
                ? const Color(0xFFFFC107)
                : const Color(0xFFBBBBBB),
            onTap: _toggleFilter,
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.settings_rounded,
            color: _showSettings
                ? const Color(0xFF2196F3)
                : const Color(0xFFBBBBBB),
            onTap: () =>
                setState(() => _showSettings = !_showSettings),
          ),
          const SizedBox(width: 6),
          // Nút thoát ra màn hình chính (Unlock/Dismiss)
          _IconBtn(
            icon: Icons.close_rounded,
            color: const Color(0xFF888888),
            onTap: () => LockScreenService.dismiss(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Hero word ──────────────────────────────────────

  Widget _buildHeroWord(WordModel word, Color accentColor) {
    final isNoun =
        ['der', 'die', 'das'].contains(word.article.toLowerCase());

    return Column(
      children: [
        // Article chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor, width: 1.5),
          ),
          child: Text(
            _articleLabel(word.article),
            style: TextStyle(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Article italic + German word on same row (Wortbit style)
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            if (isNoun)
              Text(
                word.article,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  height: 1.1,
                ),
              ),
            Text(
              word.german,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────── Sub info ───────────────────────────────────────

  Widget _buildSubInfo(WordModel word, Color accentColor) {
    final String subText;
    if (word.article == 'verb' && word.conjugation.isNotEmpty) {
      subText = word.conjugation;
    } else if (word.plural.isNotEmpty) {
      subText = 'Pl. ${word.plural}';
    } else {
      subText = '';
    }
    if (subText.isEmpty) return const SizedBox.shrink();
    return Text(
      subText,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFF555555),
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  // ─────────────────────── Meaning card ───────────────────────────────────

  Widget _buildMeaningCard(WordModel word, Color accentColor) {
    return GestureDetector(
      onTap: _revealMeaning,
      child: AnimatedBuilder(
        animation: _blurAnimation,
        builder: (context, child) {
          final blurValue = _meaningRevealed ? _blurAnimation.value : 12.0;
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withAlpha(50),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      word.meaningVi,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (!_meaningRevealed || blurValue > 0.5)
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurValue,
                          sigmaY: blurValue,
                        ),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  if (!_meaningRevealed)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('👁', style: TextStyle(fontSize: 24)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: accentColor.withAlpha(120)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Chạm để xem nghĩa',
                            style: TextStyle(
                              color: accentColor.withAlpha(200),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────── Example card ───────────────────────────────────

  Widget _buildExampleCard(WordModel word, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
              full: word.exampleDe,
              keyword: word.german.split(' ').last,
              highlightColor: accentColor),
          const SizedBox(height: 4),
          Text(
            word.exampleVi,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Action row ─────────────────────────────────────

  Widget _buildActionRow() {
    return Row(
      children: [
        // Chưa thuộc
        Expanded(
          child: GestureDetector(
            onTap: _onDontKnow,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: const Color(0xFF3A3A3A), width: 1),
              ),
              child: const Center(
                child: Text(
                  'Chưa thuộc',
                  style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Đã thuộc
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _onKnow,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF262640),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: const Color(0xFF3A3A5A), width: 1),
              ),
              child: const Center(
                child: Text(
                  'Đã thuộc  ✓',
                  style: TextStyle(
                    color: Color(0xFFD0D0F0),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────── Settings overlay ───────────────────────────────

  Widget _buildSettingsOverlay() {
    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E2E2E)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(160),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cài đặt',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 14),

            // ── Lockscreen toggle
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    color: Color(0xFF4CAF50), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Hiện trên màn hình khoá',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tự động hiện flashcard khi mở màn hình',
                        style: TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _lockscreenEnabled,
                  onChanged: _toggleLockscreen,
                  activeColor: const Color(0xFF4CAF50),
                  trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? const Color(0xFF1E3A1E)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
              ],
            ),

            if (_lockscreenEnabled) ...[
              const SizedBox(height: 14),
              // Permission guidance box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E0A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFFC107).withAlpha(60)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '⚠️ Cần cấp quyền thủ công',
                      style: TextStyle(
                        color: Color(0xFFFFC107),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '1. Cài đặt → Ứng dụng → Wortbit DE\n'
                      '2. → Quyền → "Hiển thị trên ứng dụng khác" → Bật\n'
                      '3. Tắt tối ưu pin (Battery Optimization) cho app\n'
                      '4. Khởi động lại điện thoại một lần',
                      style: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────── Filter overlay ─────────────────────────────────

  Widget _buildFilterOverlay() {
    return Positioned(
      top: 60,
      right: 70,
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF333333)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(140),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lọc từ loại',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            ...[
              ('der', 'Danh từ (der)'),
              ('die', 'Danh từ (die)'),
              ('das', 'Danh từ (das)'),
              ('verb', 'Động từ'),
              ('adj', 'Tính từ'),
              ('prep', 'Giới từ'),
            ].map(
              (pair) => _FilterChip(
                label: pair.$2,
                color: _articleColor(pair.$1),
                selected: _activeArticles.contains(pair.$1),
                onTap: () => _toggleArticle(pair.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Widget helpers ──────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(30) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0xFF3A3A3A),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: selected ? color : const Color(0xFF555555),
              size: 15,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : const Color(0xFF888888),
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.full,
    required this.keyword,
    required this.highlightColor,
  });

  final String full;
  final String keyword;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    if (keyword.isEmpty ||
        !full.toLowerCase().contains(keyword.toLowerCase())) {
      return Text(
        full,
        style: const TextStyle(
            color: Color(0xFFCCCCCC), fontSize: 13, height: 1.5),
      );
    }

    final lower = full.toLowerCase();
    final lowerKey = keyword.toLowerCase();
    final idx = lower.indexOf(lowerKey);
    final before = full.substring(0, idx);
    final match = full.substring(idx, idx + keyword.length);
    final after = full.substring(idx + keyword.length);

    return RichText(
      text: TextSpan(
        style: const TextStyle(
            color: Color(0xFFCCCCCC), fontSize: 13, height: 1.5),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              color: highlightColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
