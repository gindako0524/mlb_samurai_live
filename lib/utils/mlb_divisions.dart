// lib/utils/mlb_divisions.dart

// MLB地区ID → 表示名（standings APIのdivision.idに対応、値は変わらない固定値）
const Map<int, String> mlbDivisionNames = {
  200: 'アメリカン・リーグ 西地区',
  201: 'アメリカン・リーグ 東地区',
  202: 'アメリカン・リーグ 中地区',
  203: 'ナショナル・リーグ 西地区',
  204: 'ナショナル・リーグ 東地区',
  205: 'ナショナル・リーグ 中地区',
};

// 表示順（アメリカン・リーグ→ナショナル・リーグ、東→中→西の慣例に合わせる）
const List<int> mlbDivisionDisplayOrder = [201, 202, 200, 204, 205, 203];
