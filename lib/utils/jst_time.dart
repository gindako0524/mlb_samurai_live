// lib/utils/jst_time.dart

/// 日本時間 (UTC+9固定、サマータイム無し) への変換ユーティリティ。
/// 端末のタイムゾーン設定に依存する `.toLocal()` の代わりに使用することで、
/// 海外で利用した場合でも常に日本時間で表示されるようにする。

/// 現在時刻を日本時間で取得
DateTime nowJst() => DateTime.now().toUtc().add(const Duration(hours: 9));

/// 任意の DateTime を日本時間に変換
DateTime toJst(DateTime dt) => (dt.isUtc ? dt : dt.toUtc()).add(const Duration(hours: 9));

/// MLB公式APIが返す日付文字列 (ISO8601) を日本時間の DateTime に変換
DateTime parseToJst(String isoString) => toJst(DateTime.parse(isoString));