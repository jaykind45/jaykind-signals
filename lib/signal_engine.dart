
/// LELOMUHLE_BOT multi-timeframe signal engine.
/// On-device and read-only. Never connects to a broker or places orders.
///
/// Strategy:
/// H1 = directional bias.
/// M15 = pullback and rejection.
/// M5 = completed-candle entry confirmation.
///
/// Risk/reward is fixed at 1:2 for every actionable signal.

class MarketCandle {
  const MarketCandle({
    required this.timeUtc,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.isComplete = true,
  });

  final DateTime timeUtc;
  final double open;
  final double high;
  final double low;
  final double close;
  final bool isComplete;
}

class SignalResult {
  const SignalResult({
    required this.symbol,
    required this.signal,
    required this.reason,
    required this.timeframe,
    this.entry,
    this.stopLoss,
    this.takeProfit,
    this.rsi,
    this.ema50,
    this.ema200,
    this.macd,
    this.macdSignal,
    this.atr,
    this.candleTimeUtc,
    this.riskReward,
  });

  final String symbol;
  final String signal;
  final String reason;
  final String timeframe;
  final double? entry;
  final double? stopLoss;
  final double? takeProfit;
  final double? rsi;
  final double? ema50;
  final double? ema200;
  final double? macd;
  final double? macdSignal;
  final double? atr;
  final DateTime? candleTimeUtc;
  final double? riskReward;

  bool get isActionable => signal == 'BUY' || signal == 'SELL';
}

class SignalEngine {
  const SignalEngine();

  static const timeframe = 'H1 / M15 / M5';

  // Kept for compatibility with the existing backtest engine.
  static const minimumCandles = 220;

  static const double _stopBufferAtr = 0.10;
  static const double _minimumStopAtr = 0.50;
  static const double _maximumStopAtr = 2.50;

  /// The old single-timeframe entry method is deliberately disabled.
  SignalResult analyse(String symbol, List<MarketCandle> input) {
    return _wait(
      symbol,
      'M5-only signals are disabled. H1, M15 and M5 confirmation are required.',
    );
  }

  SignalResult analyseMultiTimeframe({
    required String symbol,
    required List<MarketCandle> h1Input,
    required List<MarketCandle> m15Input,
    required List<MarketCandle> m5Input,
    required double bid,
    required double ask,
  }) {
    final h1 = _completed(h1Input);
    final m15 = _completed(m15Input);
    final m5 = _completed(m5Input);

    if (h1.length < 50) {
      return _wait(symbol, 'Insufficient completed H1 candles.');
    }

    if (m15.length < 30) {
      return _wait(symbol, 'Insufficient completed M15 candles.');
    }

    if (m5.length < 30) {
      return _wait(symbol, 'Insufficient completed M5 candles.');
    }

    if (!_validCandles(h1) ||
        !_validCandles(m15) ||
        !_validCandles(m5)) {
      return _wait(symbol, 'Invalid candle data detected.');
    }

    if (!_strictlyIncreasing(h1) ||
        !_strictlyIncreasing(m15) ||
        !_strictlyIncreasing(m5)) {
      return _wait(
        symbol,
        'Duplicate or invalid candle timestamps detected.',
      );
    }

    if (!bid.isFinite ||
        !ask.isFinite ||
        bid <= 0 ||
        ask < bid) {
      return _wait(
        symbol,
        'A valid executable bid/ask quote is required.',
      );
    }

    // H1 directional market bias.
    final h1Closes = h1.map((c) => c.close).toList();
    final h1Ema20 = _ema(h1Closes, 20);
    final h1Ema50 = _ema(h1Closes, 50);

    if (h1Ema20 == null || h1Ema50 == null) {
      return _wait(symbol, 'H1 trend indicators are not ready.');
    }

    final h1Bullish =
        h1Ema20 > h1Ema50 && h1.last.close > h1Ema20;

    final h1Bearish =
        h1Ema20 < h1Ema50 && h1.last.close < h1Ema20;

    if (h1Bullish == h1Bearish) {
      return _wait(symbol, 'H1 direction is not sufficiently aligned.');
    }

    // M15 pullback and rejection.
    final m15Closes = m15.map((c) => c.close).toList();
    final m15Ema20 = _ema(m15Closes, 20);
    final m15Atr = _atr(m15, 14);

    if (m15Ema20 == null || m15Atr == null || m15Atr <= 0) {
      return _wait(symbol, 'M15 pullback indicators are not ready.');
    }

    final pullbackCandle = m15.last;

    final bullishPullback = h1Bullish &&
        pullbackCandle.close > pullbackCandle.open &&
        pullbackCandle.low <= m15Ema20 + m15Atr * 0.25 &&
        pullbackCandle.close > m15Ema20;

    final bearishPullback = h1Bearish &&
        pullbackCandle.close < pullbackCandle.open &&
        pullbackCandle.high >= m15Ema20 - m15Atr * 0.25 &&
        pullbackCandle.close < m15Ema20;

    if (bullishPullback == bearishPullback) {
      return _wait(
        symbol,
        'M15 has not confirmed one clear pullback rejection.',
      );
    }

    // M5 completed-candle confirmation.
    final m5Atr = _atr(m5, 14);

    if (m5Atr == null || m5Atr <= 0) {
      return _wait(symbol, 'M5 volatility calculation is unavailable.');
    }

    final latest = m5.last;
    final previous = m5[m5.length - 2];

    final previousThree = m5.sublist(
      m5.length - 4,
      m5.length - 1,
    );

    final previousThreeHigh =
        previousThree.map((c) => c.high).reduce(_max);

    final previousThreeLow =
        previousThree.map((c) => c.low).reduce(_min);

    final bullishEngulfing = latest.close > latest.open &&
        previous.close < previous.open &&
        latest.open <= previous.close &&
        latest.close >= previous.open;

    final bearishEngulfing = latest.close < latest.open &&
        previous.close > previous.open &&
        latest.open >= previous.close &&
        latest.close <= previous.open;

    final bullishStructureBreak =
        latest.close > latest.open &&
        latest.close > previousThreeHigh;

    final bearishStructureBreak =
        latest.close < latest.open &&
        latest.close < previousThreeLow;

    final buyConfirmed = bullishPullback &&
        (bullishEngulfing || bullishStructureBreak);

    final sellConfirmed = bearishPullback &&
        (bearishEngulfing || bearishStructureBreak);

    if (buyConfirmed == sellConfirmed) {
      return _wait(
        symbol,
        'M5 has not confirmed one clear directional entry.',
      );
    }

    final isBuy = buyConfirmed;

    // Use executable quote side, not the previous candle close.
    final entry = isBuy ? ask : bid;

    // Structural stop from the latest five completed M5 candles.
    final structure = m5.sublist(m5.length - 5);

    final swingLow = structure.map((c) => c.low).reduce(_min);
    final swingHigh = structure.map((c) => c.high).reduce(_max);

    final stop = isBuy
        ? swingLow - m5Atr * _stopBufferAtr
        : swingHigh + m5Atr * _stopBufferAtr;

    final risk = isBuy ? entry - stop : stop - entry;

    if (!risk.isFinite ||
        risk <= 0 ||
        risk < m5Atr * _minimumStopAtr ||
        risk > m5Atr * _maximumStopAtr) {
      return _wait(
        symbol,
        'Structural stop distance is outside the permitted volatility range.',
      );
    }

    // Fixed 1:2 reward-to-risk.
    final target = isBuy
        ? entry + risk * 2.0
        : entry - risk * 2.0;

    if (!stop.isFinite ||
        !target.isFinite ||
        stop <= 0 ||
        target <= 0) {
      return _wait(symbol, 'Calculated trade prices are invalid.');
    }

    return SignalResult(
      symbol: symbol,
      signal: isBuy ? 'BUY' : 'SELL',
      reason: isBuy
          ? 'H1 bullish trend, M15 bullish pullback rejection and M5 bullish confirmation.'
          : 'H1 bearish trend, M15 bearish pullback rejection and M5 bearish confirmation.',
      timeframe: timeframe,
      entry: entry,
      stopLoss: stop,
      takeProfit: target,
      atr: m5Atr,
      candleTimeUtc: latest.timeUtc,
      riskReward: 2.0,
    );
  }

  List<MarketCandle> _completed(List<MarketCandle> input) {
    final candles = input.where((c) => c.isComplete).toList()
      ..sort((a, b) => a.timeUtc.compareTo(b.timeUtc));

    return candles;
  }

  bool _strictlyIncreasing(List<MarketCandle> candles) {
    for (var i = 1; i < candles.length; i++) {
      if (!candles[i].timeUtc.isAfter(candles[i - 1].timeUtc)) {
        return false;
      }
    }

    return true;
  }

  bool _validCandles(List<MarketCandle> candles) {
    for (final c in candles) {
      if (!c.open.isFinite ||
          !c.high.isFinite ||
          !c.low.isFinite ||
          !c.close.isFinite ||
          c.open <= 0 ||
          c.high <= 0 ||
          c.low <= 0 ||
          c.close <= 0 ||
          c.high < c.low ||
          c.high < c.open ||
          c.high < c.close ||
          c.low > c.open ||
          c.low > c.close) {
        return false;
      }
    }

    return true;
  }

  SignalResult _wait(String symbol, String reason) => SignalResult(
        symbol: symbol,
        signal: 'WAIT',
        reason: reason,
        timeframe: timeframe,
      );

  double? _ema(List<double> values, int period) {
    if (values.length < period) return null;

    final alpha = 2.0 / (period + 1);

    var result =
        values.take(period).reduce((a, b) => a + b) / period;

    for (final value in values.skip(period)) {
      result = value * alpha + result * (1 - alpha);
    }

    return result;
  }

  double? _atr(List<MarketCandle> candles, int period) {
    if (candles.length <= period) return null;

    final ranges = <double>[];

    for (var i = 1; i < candles.length; i++) {
      final current = candles[i];
      final previousClose = candles[i - 1].close;

      final range = _max(
        current.high - current.low,
        _max(
          (current.high - previousClose).abs(),
          (current.low - previousClose).abs(),
        ),
      );

      ranges.add(range);
    }

    if (ranges.length < period) return null;

    var result =
        ranges.take(period).reduce((a, b) => a + b) / period;

    for (final range in ranges.skip(period)) {
      result = (result * (period - 1) + range) / period;
    }

    return result;
  }

  static double _max(double a, double b) => a > b ? a : b;

  static double _min(double a, double b) => a < b ? a : b;
}
