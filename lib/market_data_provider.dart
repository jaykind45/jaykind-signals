
/// Broker-neutral market-data boundary for the phone-only application.
/// Missing, incomplete, stale or misaligned data must never produce
/// an actionable signal.

import 'signal_engine.dart';

class MarketDataSnapshot {
  const MarketDataSnapshot({
    required this.symbol,
    required this.candlesM5,
    required this.candlesM15,
    required this.candlesH1,
    required this.receivedAtUtc,
    this.bid,
    this.ask,
    this.providerName = 'Unknown provider',
  });

  final String symbol;
  final List<MarketCandle> candlesM5;
  final List<MarketCandle> candlesM15;
  final List<MarketCandle> candlesH1;

  final DateTime receivedAtUtc;
  final double? bid;
  final double? ask;
  final String providerName;

  List<MarketCandle> get candles => candlesM5;

  bool isFresh({
    DateTime? nowUtc,
    Duration maximumAge = const Duration(seconds: 120),
  }) {
    final now = nowUtc ?? DateTime.now().toUtc();
    final age = now.difference(receivedAtUtc.toUtc());

    return !age.isNegative && age <= maximumAge;
  }

  bool get hasValidQuote =>
      bid != null &&
      ask != null &&
      bid!.isFinite &&
      ask!.isFinite &&
      bid! > 0 &&
      ask! >= bid!;

  double? get spread => hasValidQuote ? ask! - bid! : null;

  bool get hasAllTimeframes =>
      candlesM5.isNotEmpty &&
      candlesM15.isNotEmpty &&
      candlesH1.isNotEmpty;
}

abstract interface class MarketDataProvider {
  String get providerId;

  Future<MarketDataSnapshot> fetchMarketData(
    String symbol, {
    int m5Limit = 288,
    int m15Limit = 192,
    int h1Limit = 168,
  });
}

/// Multi-timeframe signal service.
///
/// Stale data, invalid quotes, missing candles, misaligned timeframes
/// and excessive spreads always produce WAIT.
class SignalService {
  const SignalService({this.engine = const SignalEngine()});

  final SignalEngine engine;

  SignalResult evaluate(
    MarketDataSnapshot snapshot, {
    DateTime? nowUtc,
    double? maximumSpread,
  }) {
    final now = (nowUtc ?? DateTime.now()).toUtc();

    if (!snapshot.isFresh(nowUtc: now)) {
      return _wait(
        snapshot.symbol,
        'Market data is stale; new signals are paused.',
      );
    }

    if (!snapshot.hasValidQuote) {
      return _wait(
        snapshot.symbol,
        'A valid live bid/ask quote is unavailable.',
      );
    }

    if (!snapshot.hasAllTimeframes) {
      return _wait(
        snapshot.symbol,
        'H1, M15 and M5 data are all required.',
      );
    }

    if (maximumSpread != null &&
        (!maximumSpread.isFinite ||
            maximumSpread < 0 ||
            snapshot.spread! > maximumSpread)) {
      return _wait(
        snapshot.symbol,
        'Spread is above the configured limit.',
      );
    }

    final latestH1 = _latestCompleted(snapshot.candlesH1);
    final latestM15 = _latestCompleted(snapshot.candlesM15);
    final latestM5 = _latestCompleted(snapshot.candlesM5);

    if (latestH1 == null || latestM15 == null || latestM5 == null) {
      return _wait(
        snapshot.symbol,
        'Completed candles are required on all three timeframes.',
      );
    }

    if (!_isWithinAge(
      latestM5.timeUtc,
      now,
      const Duration(minutes: 10),
    )) {
      return _wait(
        snapshot.symbol,
        'The latest completed M5 candle is stale.',
      );
    }

    if (!_isWithinAge(
      latestM15.timeUtc,
      now,
      const Duration(minutes: 30),
    )) {
      return _wait(
        snapshot.symbol,
        'The latest completed M15 candle is stale.',
      );
    }

    if (!_isWithinAge(
      latestH1.timeUtc,
      now,
      const Duration(hours: 2),
    )) {
      return _wait(
        snapshot.symbol,
        'The latest completed H1 candle is stale.',
      );
    }

    // Candle timestamps must progress from the higher timeframe
    // to the lower timeframe.
    if (latestH1.timeUtc.isAfter(latestM15.timeUtc) ||
        latestM15.timeUtc.isAfter(latestM5.timeUtc)) {
      return _wait(
        snapshot.symbol,
        'H1, M15 and M5 candle timestamps are misaligned.',
      );
    }

    return engine.analyseMultiTimeframe(
      symbol: snapshot.symbol,
      h1Input: snapshot.candlesH1,
      m15Input: snapshot.candlesM15,
      m5Input: snapshot.candlesM5,
      bid: snapshot.bid!,
      ask: snapshot.ask!,
    );
  }

  MarketCandle? _latestCompleted(List<MarketCandle> candles) {
    final completed = candles.where((c) => c.isComplete).toList();

    if (completed.isEmpty) return null;

    completed.sort((a, b) => a.timeUtc.compareTo(b.timeUtc));

    return completed.last;
  }

  bool _isWithinAge(
    DateTime candleTime,
    DateTime now,
    Duration maximumAge,
  ) {
    final age = now.difference(candleTime.toUtc());

    return !age.isNegative && age <= maximumAge;
  }

  SignalResult _wait(String symbol, String reason) => SignalResult(
        symbol: symbol,
        signal: 'WAIT',
        reason: reason,
        timeframe: SignalEngine.timeframe,
      );
}
