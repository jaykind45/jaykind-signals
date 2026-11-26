
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'biquote_market_data_provider.dart';
import 'market_data_provider.dart';
import 'signal_engine.dart';

const _gold = Color(0xFFD6AD55);
const _brightGold = Color(0xFFFFD98A);
const _background = Color(0xFF090909);
const _surface = Color(0xFF151515);
const _surfaceLight = Color(0xFF202020);
const _muted = Color(0xFFAAA39A);

const _symbols = <String>['XAUUSD', 'US30'];

const _maxSpread = <String, double>{
  'XAUUSD': 1.50,
  'US30': 10.0,
};

void main() => runApp(const LeloMuhleApp());

class LeloMuhleApp extends StatelessWidget {
  const LeloMuhleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LELOMUHLE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _gold,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: _brightGold,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const SignalsHomePage(),
    );
  }
}

class _SymbolState {
  const _SymbolState({
    required this.result,
    this.snapshot,
    this.error,
  });

  final SignalResult result;
  final MarketDataSnapshot? snapshot;
  final String? error;
}

class SignalsHomePage extends StatefulWidget {
  const SignalsHomePage({super.key});

  @override
  State<SignalsHomePage> createState() => _SignalsHomePageState();
}

class _SignalsHomePageState extends State<SignalsHomePage>
    with WidgetsBindingObserver {
  final BiquoteMarketDataProvider _provider =
      BiquoteMarketDataProvider();

  final SignalService _service = const SignalService();

  final Map<String, _SymbolState> _states = {};

  Timer? _refreshTimer;

  bool _loading = false;
  bool _disposed = false;
  int _iosPageIndex = 0;

  String _status = 'Waiting for live market data...';
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _startForegroundRefresh();
    refreshAll();
  }

  void _startForegroundRefresh() {
    _refreshTimer?.cancel();

    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshAll(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundRefresh();
      refreshAll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _refreshTimer?.cancel();
    }
  }

  Future<void> refreshAll() async {
    if (_loading || _disposed) return;

    setState(() {
      _loading = true;
      _status = 'Checking H1, M15, M5 and live quotes...';
    });

    try {
      final updates = <String, _SymbolState>{};

      await Future.wait(
        _symbols.map((symbol) async {
          try {
            final snapshot = await _provider.fetchMarketData(
              symbol,
              m5Limit: 288,
              m15Limit: 192,
              h1Limit: 168,
            );

            final result = _service.evaluate(
              snapshot,
              maximumSpread: _maxSpread[symbol],
            );

            updates[symbol] = _SymbolState(
              result: result,
              snapshot: snapshot,
            );
          } catch (error) {
            updates[symbol] = _SymbolState(
              result: SignalResult(
                symbol: symbol,
                signal: 'WAIT',
                reason: 'Live market data could not be verified.',
                timeframe: SignalEngine.timeframe,
              ),
              error: _safeError(error),
            );
          }
        }),
      );

      if (!mounted || _disposed) return;

      setState(() {
        _states.addAll(updates);
        _lastRefresh = DateTime.now();

        final good = updates.values
            .where((state) => state.snapshot != null)
            .length;

        _status = good == _symbols.length
            ? 'All market feeds received. Strategy conditions are being evaluated.'
            : 'One or more market feeds could not be verified. Those symbols remain on WAIT.';
      });
    } catch (error) {
      if (!mounted || _disposed) return;

      setState(() {
        _status =
            'Refresh failed. Signals remain unavailable until data is verified.';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _safeError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');

    return text.length > 150
        ? '${text.substring(0, 150)}...'
        : text;
  }

  @override
  void dispose() {
    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _provider.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _iosPageIndex,
            children: [
              _buildMarketSignalsPage(),
              _buildMorePage(),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _iosPageIndex,
          onTap: (index) => setState(() => _iosPageIndex = index),
          backgroundColor: _surface,
          selectedItemColor: _brightGold,
          unselectedItemColor: _muted,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart_rounded),
              label: 'MARKET SIGNALS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'MORE',
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshAll,
          color: _gold,
          backgroundColor: _surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
            children: [
              _header(),
              const SizedBox(height: 22),
              _statusCard(),
              const SizedBox(height: 22),
              _sectionHeading('MARKET SIGNALS', 'LIVE ANALYSIS'),
              const SizedBox(height: 12),
              for (final symbol in _symbols) ...[
                _signalCard(symbol),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 8),
              _strategyCard(),
              const SizedBox(height: 14),
              _informationCard(),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'LELOMUHLE  •  PREMIUM SIGNALS',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarketSignalsPage() {
    return RefreshIndicator(
      onRefresh: refreshAll,
      color: _gold,
      backgroundColor: _surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          _header(),
          const SizedBox(height: 22),
          _sectionHeading('MARKET SIGNALS', 'LIVE ANALYSIS'),
          const SizedBox(height: 12),
          for (final symbol in _symbols) ...[
            _signalCard(symbol),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildMorePage() {
    return RefreshIndicator(
      onRefresh: refreshAll,
      color: _gold,
      backgroundColor: _surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          _header(),
          const SizedBox(height: 22),
          _statusCard(),
          const SizedBox(height: 14),
          _strategyCard(),
          const SizedBox(height: 14),
          _informationCard(),
        ],
      ),
    );
  }
  Widget _header() {
    return Row(
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: _surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _gold.withValues(alpha: 0.65),
            ),
          ),
          child: const Icon(
            Icons.show_chart_rounded,
            color: _brightGold,
            size: 29,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isIOS ? 'JAYKIND_SIGNALS' : 'LELOMUHLE',
                style: TextStyle(
                  color: _brightGold,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'PREMIUM SIGNALS',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: IconButton(
            tooltip: 'Refresh market data',
            onPressed: _loading ? null : refreshAll,
            icon: Icon(
              Icons.refresh_rounded,
              color: _loading ? _muted : _brightGold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeading(String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _brightGold,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Text(
          subtitle,
          style: const TextStyle(
            color: _muted,
            fontSize: 9,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF242017), Color(0xFF121212)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _gold.withValues(alpha: 0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.07),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.smartphone_rounded,
                color: _brightGold,
                size: 22,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'PHONE-ONLY SIGNAL MODE',
                  style: TextStyle(
                    color: _brightGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF382C13),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _gold),
                ),
                child: const Text(
                  'NO AUTO-TRADING',
                  style: TextStyle(
                    color: _brightGold,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _loading ? Icons.sync : Icons.verified_rounded,
                color: _loading ? _gold : Colors.lightGreenAccent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: const LinearProgressIndicator(
                minHeight: 3,
                color: _gold,
                backgroundColor: _surfaceLight,
              ),
            ),
          ],
          if (_lastRefresh != null) ...[
            const SizedBox(height: 13),
            Text(
              'LAST CHECK  ${_lastRefresh!.toLocal().toString().substring(0, 19)}',
              style: const TextStyle(
                color: _muted,
                fontSize: 9,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signalCard(String symbol) {
    final state = _states[symbol];
    final result = state?.result;
    final snapshot = state?.snapshot;

    final signal = result?.signal ?? 'WAIT';

    final Color signalColor = signal == 'BUY'
        ? Colors.lightGreenAccent
        : signal == 'SELL'
            ? Colors.redAccent
            : _brightGold;

    String price(double? value) {
      if (value == null || !value.isFinite) return '--';

      return value.toStringAsFixed(
        symbol == 'US30' ? 1 : 2,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _gold.withValues(alpha: 0.38),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF302613),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  symbol == 'XAUUSD'
                      ? Icons.monetization_on_rounded
                      : Icons.trending_up_rounded,
                  color: _brightGold,
                  size: 25,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                    Text(
                      symbol == 'XAUUSD'
                          ? 'GOLD / US DOLLAR'
                          : 'DOW JONES INDEX',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              _signalBadge(signal, signalColor),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            result?.reason ??
                'No verified data yet. Waiting for market feed.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _priceColumn(
                  'ENTRY',
                  price(result?.isActionable == true
                      ? result?.entry
                      : null),
                ),
                _verticalDivider(),
                _priceColumn('STOP LOSS', price(result?.stopLoss)),
                _verticalDivider(),
                _priceColumn('TAKE PROFIT', price(result?.takeProfit)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _smallMetric(
                  'REWARD : RISK',
                  result?.riskReward == null
                      ? '--'
                      : '1:${result!.riskReward!.toStringAsFixed(0)}',
                ),
              ),
              Expanded(
                child: _smallMetric(
                  'BID',
                  price(snapshot?.bid),
                ),
              ),
              Expanded(
                child: _smallMetric(
                  'ASK',
                  price(snapshot?.ask),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF35302A), height: 1),
          const SizedBox(height: 12),
          _detailRow(
            'Analysis timeframes',
            result?.timeframe ?? SignalEngine.timeframe,
          ),
          _detailRow(
            'M5 completed candles',
            '${snapshot?.candlesM5.length ?? 0}',
          ),
          _detailRow(
            'M15 completed candles',
            '${snapshot?.candlesM15.length ?? 0}',
          ),
          _detailRow(
            'H1 completed candles',
            '${snapshot?.candlesH1.length ?? 0}',
          ),
          _detailRow(
            'Market data source',
            snapshot?.providerName ?? 'Not connected',
          ),
          if (state?.error != null) ...[
            const SizedBox(height: 9),
            Text(
              state!.error!,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
              ),
            ),
          ],
          if (snapshot != null) ...[
            const SizedBox(height: 9),
            Text(
              'QUOTE TIME  ${snapshot.receivedAtUtc.toLocal().toString().substring(0, 19)}',
              style: const TextStyle(
                color: _muted,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signalBadge(String signal, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 17,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        signal,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _priceColumn(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 8,
              letterSpacing: 0.7,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: _brightGold,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      height: 32,
      width: 1,
      color: const Color(0xFF39332A),
    );
  }

  Widget _smallMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 8,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strategyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: _gold.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: _brightGold,
                size: 21,
              ),
              SizedBox(width: 9),
              Text(
                'MULTI-TIMEFRAME STRATEGY',
                style: TextStyle(
                  color: _brightGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _strategyLine('H1', 'Market direction'),
          _strategyLine('M15', 'Pullback and rejection'),
          _strategyLine('M5', 'Completed-candle confirmation'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2110),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _gold.withValues(alpha: 0.5),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: _brightGold,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Fixed reward-to-risk ratio',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  '1 : 2',
                  style: TextStyle(
                    color: _brightGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _strategyLine(String timeframe, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Colors.lightGreenAccent,
            size: 17,
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 39,
            child: Text(
              timeframe,
              style: const TextStyle(
                color: _brightGold,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _informationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF211A10),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: _gold.withValues(alpha: 0.65),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: _brightGold,
              ),
              SizedBox(width: 9),
              Text(
                'IMPORTANT INFORMATION',
                style: TextStyle(
                  color: _brightGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          Text(
            'This application calculates signals on the phone. It does not place trades and does not require an MT5 login. It uses an independent market-data reference feed, so prices and spreads may differ from your broker. Compare every setup with your broker before making a trading decision.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          SizedBox(height: 11),
          Text(
            'Signals refresh once per minute while the app is open. Updates can pause when Android backgrounds or force-stops the app.',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              height: 1.5,
            ),
          ),
          SizedBox(height: 13),
          Text(
            'READ-ONLY  •  NO ORDERS  •  NO BROKER PASSWORD REQUIRED',
            style: TextStyle(
              color: _brightGold,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
