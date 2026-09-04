# update_war.py
import json
import math
from datetime import datetime, timezone
import pybaseball
from pybaseball import batting_stats, pitching_stats, bwar_bat, bwar_pitch, playerid_reverse_lookup

pybaseball.cache.enable()
CURRENT_YEAR = 2026
LEADER_TOP_N = 50

# ★ 日本人選手の表示名（name_ja）を付けるためだけの対応表。
#   以前はこの辞書の「名字」で全選手データを検索していたが、同じ名字の別人
#   （例：鈴木誠也 と イチロー・鈴木）まで一致してしまい、通算WARが誤って
#   合算されるバグの原因になっていた。
#   今はIDベースの厳密な突き合わせ（bbrefID -> MLBAM ID）に全面的に切り替えたため、
#   この辞書は「MLBAM IDが分かっている選手に日本語名を付ける」表示用途だけに使う。
JAPANESE_PLAYERS_JA_NAME = {
    660271: "大谷 翔平",
    673548: "鈴木 誠也",
    807799: "吉田 正尚",
    808959: "村上 宗隆",
    672960: "岡本 和真",
    663457: "ヌートバー",
    808967: "山本 由伸",
    808963: "佐々木 朗希",
    684007: "今永 昇太",
    506433: "ダルビッシュ 有",
    673513: "松井 裕樹",
    579328: "菊池 雄星",
    673540: "千賀 滉大",
    608372: "菅野 智之",
    837227: "今井 達也",
}


def safe_float(val, default=0.0):
    """NaN・None・変換不可な値を安全にfloatへ変換する（JSON出力時のNaN混入を防止）。
    defaultにNoneを渡した場合は「値が無かった」ことを示すためNoneのまま返す。"""
    try:
        f = float(val)
        if math.isnan(f):
            return default
        return f
    except (TypeError, ValueError):
        return default


def find_column(df, candidates):
    """候補の列名リストから、実際にdfに存在する最初の列名を返す（無ければNone）"""
    if df is None:
        return None
    for c in candidates:
        if c in df.columns:
            return c
    return None


def build_leaderboard(df, top_n=LEADER_TOP_N):
    """
    Baseball-Reference の WAR データフレーム（通常はその年だけに絞ったもの）から、
    MLB全体・ア・リーグ・ナ・リーグそれぞれの上位 top_n 件のランキングを作成する。
    """
    empty = {"mlb_top": [], "al_top": [], "nl_top": []}
    if df is None or df.empty:
        return empty

    name_col = find_column(df, ['name_common', 'Name'])
    if name_col is None or 'WAR' not in df.columns:
        return empty

    work = df.copy()
    work = work.dropna(subset=['WAR'])
    work = work.sort_values('WAR', ascending=False)

    def to_entries(sub_df):
        entries = []
        for _, row in sub_df.head(top_n).iterrows():
            entries.append({
                "name": str(row.get(name_col, '')),
                "name_ja": None,
                "team": str(row.get('team_ID', '-')),
                "war": safe_float(row.get('WAR', 0.0)),
            })
        return entries

    mlb_top = to_entries(work)
    al_top = []
    nl_top = []
    if 'lg_ID' in work.columns:
        al_top = to_entries(work[work['lg_ID'] == 'AL'])
        nl_top = to_entries(work[work['lg_ID'] == 'NL'])

    return {"mlb_top": mlb_top, "al_top": al_top, "nl_top": nl_top}


def build_bbref_to_mlbam_map(bbref_ids):
    """
    bbrefID（Baseball-Referenceの選手ID）のリストから、MLBAM ID（MLB公式が使うID。
    このアプリの選手識別に使っているものと同じ）への対応表を作る。
    Chadwick BureauのID対応レジスタ（pybaseballのplayerid_reverse_lookup）を使う。

    ★ これがこのスクリプトの心臓部。以前は「名字の部分一致」で選手を特定していたため、
      同姓の別人のデータが混ざる事故が起きていた。IDベースの厳密な対応付けに
      切り替えることで、この種の事故を構造的に防ぐ。
    """
    if not bbref_ids:
        return {}
    unique_ids = sorted(set(bbref_ids))
    print(f"[ID対応表] bbrefID {len(unique_ids)}件をMLBAM IDに変換中...")

    mapping = {}
    chunk_size = 300  # 一度に大量のIDを渡すと失敗しやすいため分割して問い合わせる
    for i in range(0, len(unique_ids), chunk_size):
        chunk = unique_ids[i:i + chunk_size]
        try:
            result = playerid_reverse_lookup(chunk, key_type='bbref')
        except Exception as e:
            print(f"  [エラー] チャンク{i}〜{i + len(chunk)}件目の変換に失敗: {e}")
            continue
        if result is None or result.empty:
            continue

        bbref_col = find_column(result, ['key_bbref'])
        mlbam_col = find_column(result, ['key_mlbam'])
        if bbref_col is None or mlbam_col is None:
            print(f"  [警告] 変換結果に想定した列が見つかりません: {list(result.columns)}")
            continue

        for _, row in result.iterrows():
            bbref_id = row.get(bbref_col)
            mlbam_id = row.get(mlbam_col)
            if bbref_id is None or mlbam_id is None:
                continue
            try:
                mapping[str(bbref_id)] = int(mlbam_id)
            except (TypeError, ValueError):
                continue

    print(f"[ID対応表] {len(mapping)}件のMLBAM ID対応が見つかりました")
    return mapping


def build_war_by_year_lookup(df, id_col):
    """
    bbrefIDの列(id_col)でグループ化し、{bbrefID: {年度: WAR}} の辞書を一括で作る。
    1選手ずつ全データを検索し直すより効率的。
    同じ年に複数行ある場合（シーズン途中のトレード等）はその年のWARを合算する。
    """
    if df is None or df.empty or id_col not in df.columns or 'year_ID' not in df.columns or 'WAR' not in df.columns:
        return {}

    result = {}
    for bbref_id, group in df.groupby(id_col):
        year_war = {}
        for _, row in group.iterrows():
            year = row.get('year_ID')
            if year is None:
                continue
            war_val = safe_float(row.get('WAR'), default=None)
            if war_val is None:
                continue
            year_key = str(int(year))
            year_war[year_key] = round(year_war.get(year_key, 0.0) + war_val, 1)
        if year_war:
            result[str(bbref_id)] = year_war

    return result


def find_player_name(df, id_col, bbref_id):
    """表示用に選手の英語名を1件だけ取得する（無ければ空文字）"""
    if df is None or id_col is None or 'name_common' not in df.columns:
        return ''
    row = df[df[id_col] == bbref_id]
    if row.empty:
        return ''
    return str(row.iloc[0]['name_common'])


def fetch_war_data():
    output = {}
    print("データ抽出開始...")

    # 1. FanGraphs（現状403でブロックされ取得できないことが多いが、念のため試行する）
    try:
        bat_fg = batting_stats(CURRENT_YEAR, qual=0)
        print(f"[デバッグ] FanGraphs打者データ取得成功: {len(bat_fg)}行")
    except Exception as e:
        print(f"[エラー] FanGraphs打者データ取得失敗: {e}")
        bat_fg = None

    try:
        pitch_fg = pitching_stats(CURRENT_YEAR, qual=0)
        print(f"[デバッグ] FanGraphs投手データ取得成功: {len(pitch_fg)}行")
    except Exception as e:
        print(f"[エラー] FanGraphs投手データ取得失敗: {e}")
        pitch_fg = None
    # ★ FanGraphs個別選手へのIDベース対応付けは、そもそも403でブロックされ
    #   使えないことがほとんどのため、現時点では実装していない（fwar/fwar_pitchは0.0固定）。
    #   取得できた場合の全体傾向確認用にbat_fg/pitch_fgの行数だけログに残す。

    # 2. Baseball-Reference（全選手・全年度のWARデータを一括取得）
    try:
        b_bat_full = bwar_bat()
        print(f"[デバッグ] B-Ref打者データ取得成功: {len(b_bat_full)}行")
    except Exception as e:
        print(f"[エラー] B-Ref打者データ取得失敗: {e}")
        b_bat_full = None

    try:
        b_pitch_full = bwar_pitch()
        print(f"[デバッグ] B-Ref投手データ取得成功: {len(b_pitch_full)}行")
    except Exception as e:
        print(f"[エラー] B-Ref投手データ取得失敗: {e}")
        b_pitch_full = None

    bat_id_col = find_column(b_bat_full, ['player_ID', 'playerID', 'bbrefID'])
    pitch_id_col = find_column(b_pitch_full, ['player_ID', 'playerID', 'bbrefID'])
    print(f"[デバッグ] 打者ID列: {bat_id_col} / 投手ID列: {pitch_id_col}")

    # 3. 選手ごとの年度別WARを一括で整理（bbrefID単位）
    bat_war_lookup = build_war_by_year_lookup(b_bat_full, bat_id_col) if bat_id_col else {}
    pitch_war_lookup = build_war_by_year_lookup(b_pitch_full, pitch_id_col) if pitch_id_col else {}
    print(f"[デバッグ] 通算WARが算出できた打者: {len(bat_war_lookup)}人 / 投手: {len(pitch_war_lookup)}人")

    # 4. 「現役選手」の母集団を決める：今シーズン(CURRENT_YEAR)の実績があるbbrefIDのみを対象にする
    #    （歴代全選手を含めると数万人規模になり、アプリが表示に使う分には過大なため、
    #     実用上の範囲として「今シーズン出場した選手」に絞る）
    active_bbref_ids = set()
    for bbref_id, year_war in bat_war_lookup.items():
        if str(CURRENT_YEAR) in year_war:
            active_bbref_ids.add(bbref_id)
    for bbref_id, year_war in pitch_war_lookup.items():
        if str(CURRENT_YEAR) in year_war:
            active_bbref_ids.add(bbref_id)
    print(f"[デバッグ] 今シーズン(={CURRENT_YEAR})出場実績のある選手数: {len(active_bbref_ids)}")

    # 5. bbrefID → MLBAM ID の対応表を作る
    bbref_to_mlbam = build_bbref_to_mlbam_map(list(active_bbref_ids))

    # 6. 選手ごとにWARデータを組み立てる（IDベースの厳密な突き合わせのみを使用。名前検索は行わない）
    for bbref_id, mlbam_id in bbref_to_mlbam.items():
        war_by_year_bat = bat_war_lookup.get(bbref_id, {})
        war_by_year_pitch = pitch_war_lookup.get(bbref_id, {})

        if not war_by_year_bat and not war_by_year_pitch:
            continue  # 通算WARが無い選手は出力を無駄に膨らませないためスキップ

        career_rwar = round(sum(war_by_year_bat.values()), 1) if war_by_year_bat else 0.0
        career_rwar_pitch = round(sum(war_by_year_pitch.values()), 1) if war_by_year_pitch else 0.0
        rwar = war_by_year_bat.get(str(CURRENT_YEAR), 0.0)
        rwar_pitch = war_by_year_pitch.get(str(CURRENT_YEAR), 0.0)

        name = find_player_name(b_bat_full, bat_id_col, bbref_id) or find_player_name(b_pitch_full, pitch_id_col, bbref_id)

        output[str(mlbam_id)] = {
            "name": name,
            "name_ja": JAPANESE_PLAYERS_JA_NAME.get(mlbam_id),
            "fwar": 0.0,
            "rwar": rwar,
            "fwar_pitch": 0.0,
            "rwar_pitch": rwar_pitch,
            "war_by_year": war_by_year_bat,
            "war_by_year_pitch": war_by_year_pitch,
            "career_rwar": career_rwar,
            "career_rwar_pitch": career_rwar_pitch,
        }

    # ★ 日本人選手が万一ID対応表に含まれなかった場合の保険ログ（見落としに早く気づくため）
    for mlbam_id, name_ja in JAPANESE_PLAYERS_JA_NAME.items():
        if str(mlbam_id) not in output:
            print(f"  [警告] {name_ja} (MLBAM ID: {mlbam_id}) のWARデータが見つかりませんでした")
        else:
            p = output[str(mlbam_id)]
            print(f"  [{name_ja}] rWAR: {p['rwar']}, rWAR(投): {p['rwar_pitch']}, "
                  f"通算rWAR: {p['career_rwar']}, 通算rWAR(投): {p['career_rwar_pitch']}")

    print(f"[デバッグ] WARデータを出力する選手数(合計): {len(output)}")

    # 7. MLB全体・リーグ別のWARランキング（今シーズン単年、上位50件）
    b_bat_year = b_bat_full[b_bat_full['year_ID'] == CURRENT_YEAR] if b_bat_full is not None and 'year_ID' in b_bat_full.columns else None
    b_pitch_year = b_pitch_full[b_pitch_full['year_ID'] == CURRENT_YEAR] if b_pitch_full is not None and 'year_ID' in b_pitch_full.columns else None
    batter_leaders = build_leaderboard(b_bat_year)
    pitcher_leaders = build_leaderboard(b_pitch_year)
    print(f"[デバッグ] 打者リーダーボード: MLB全体{len(batter_leaders['mlb_top'])}件 / AL{len(batter_leaders['al_top'])}件 / NL{len(batter_leaders['nl_top'])}件")
    print(f"[デバッグ] 投手リーダーボード: MLB全体{len(pitcher_leaders['mlb_top'])}件 / AL{len(pitcher_leaders['al_top'])}件 / NL{len(pitcher_leaders['nl_top'])}件")

    final_payload = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "players": output,
        "war_leaders": {
            "batters": batter_leaders,
            "pitchers": pitcher_leaders,
        },
    }

    with open("war_data.json", "w", encoding="utf-8") as f:
        json.dump(final_payload, f, indent=2, ensure_ascii=False)
    print("war_data.json 自動更新完了")


if __name__ == "__main__":
    fetch_war_data()
