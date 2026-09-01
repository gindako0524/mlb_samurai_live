# update_war.py
import json
import math
from datetime import datetime, timezone
import pybaseball
from pybaseball import batting_stats, pitching_stats, bwar_bat, bwar_pitch

pybaseball.cache.enable()
CURRENT_YEAR = 2026
LEADER_TOP_N = 50

TARGET_PLAYERS = {
    # --- 打者・二刀流 ---
    660271: {"name": "Shohei Ohtani", "name_ja": "大谷 翔平", "is_two_way": True},
    673548: {"name": "Seiya Suzuki", "name_ja": "鈴木 誠也", "is_pitcher": False},
    807799: {"name": "Masataka Yoshida", "name_ja": "吉田 正尚", "is_pitcher": False},
    808959: {"name": "Munetaka Murakami", "name_ja": "村上 宗隆", "is_pitcher": False},
    672960: {"name": "Kazuma Okamoto", "name_ja": "岡本 和真", "is_pitcher": False},
    663457: {"name": "Lars Nootbaar", "name_ja": "ヌートバー", "is_pitcher": False},
    # --- 投手 ---
    808967: {"name": "Yoshinobu Yamamoto", "name_ja": "山本 由伸", "is_pitcher": True},
    808963: {"name": "Roki Sasaki", "name_ja": "佐々木 朗希", "is_pitcher": True},
    684007: {"name": "Shota Imanaga", "name_ja": "今永 昇太", "is_pitcher": True},
    506433: {"name": "Yu Darvish", "name_ja": "ダルビッシュ 有", "is_pitcher": True},
    673513: {"name": "Yuki Matsui", "name_ja": "松井 裕樹", "is_pitcher": True},
    579328: {"name": "Yusei Kikuchi", "name_ja": "菊池 雄星", "is_pitcher": True},
    673540: {"name": "Kodai Senga", "name_ja": "千賀 滉大", "is_pitcher": True},
    608372: {"name": "Tomoyuki Sugano", "name_ja": "菅野 智之", "is_pitcher": True},
    837227: {"name": "Tatsuya Imai", "name_ja": "今井 達也", "is_pitcher": True},
}

# TARGET_PLAYERSの英語名から日本人選手を逆引きするための辞書（ランキングに日本人フラグを付けるため）
JAPANESE_NAME_LOOKUP = {v["name"]: v["name_ja"] for v in TARGET_PLAYERS.values()}


def search_war(df, last_name):
    """データフレームから名字で検索して WAR 列を安全に取得"""
    if df is None or df.empty:
        return 0.0

    name_cols = [c for c in df.columns if c.lower() in ['name', 'name_common', 'playername']]
    if not name_cols:
        return 0.0
    target_col = name_cols[0]
    matched = df[df[target_col].astype(str).str.lower().str.contains(last_name.lower().strip(), na=False)]
    if not matched.empty:
        war_cols = [c for c in matched.columns if c.upper() == 'WAR']
        if war_cols:
            try:
                val = float(matched[war_cols[0]].iloc[0])
                if math.isnan(val):
                    return 0.0
                return round(val, 1)
            except Exception as e:
                print(f"  [WAR変換エラー] {last_name}: {e}")
                return 0.0
    return 0.0


def build_leaderboard(df, top_n=LEADER_TOP_N):
    """
    Baseball-Reference の WAR データフレームから、MLB全体・ア・リーグ・ナ・リーグ
    それぞれの上位 top_n 件のランキングを作成する。
    """
    empty = {"mlb_top": [], "al_top": [], "nl_top": []}
    if df is None or df.empty:
        return empty

    name_col = None
    for c in ['name_common', 'Name']:
        if c in df.columns:
            name_col = c
            break
    if name_col is None or 'WAR' not in df.columns:
        return empty

    work = df.copy()
    work = work.dropna(subset=['WAR'])
    work = work.sort_values('WAR', ascending=False)

    def to_entries(sub_df):
        entries = []
        for _, row in sub_df.head(top_n).iterrows():
            name = str(row.get(name_col, ''))
            team = str(row.get('team_ID', '-'))
            war_val = round(float(row.get('WAR', 0.0)), 1)
            entries.append({
                "name": name,
                "name_ja": JAPANESE_NAME_LOOKUP.get(name),
                "team": team,
                "war": war_val,
            })
        return entries

    mlb_top = to_entries(work)

    al_top = []
    nl_top = []
    if 'lg_ID' in work.columns:
        al_top = to_entries(work[work['lg_ID'] == 'AL'])
        nl_top = to_entries(work[work['lg_ID'] == 'NL'])

    return {"mlb_top": mlb_top, "al_top": al_top, "nl_top": nl_top}


def extract_war_by_year(df, last_name):
    """名字でマッチする選手の年度別WARを {年度: WAR} の辞書で返す（通算成績画面用）"""
    if df is None or df.empty:
        return {}
    name_cols = [c for c in df.columns if c.lower() in ['name', 'name_common', 'playername']]
    if not name_cols or 'WAR' not in df.columns or 'year_ID' not in df.columns:
        return {}
    target_col = name_cols[0]
    matched = df[df[target_col].astype(str).str.lower().str.contains(last_name.lower().strip(), na=False)]
    if matched.empty:
        return {}
    result = {}
    for _, row in matched.iterrows():
        year = row.get('year_ID')
        war = row.get('WAR')
        if year is None or war is None:
            continue
        try:
            war_float = float(war)
            if math.isnan(war_float):
                continue  # ★ NaNはJSON非対応（Python jsonはNaNを不正なリテラルとして出力してしまう）
            result[str(int(year))] = round(war_float, 1)
        except Exception:
            continue
    return result


def fetch_war_data():
    output = {}
    print("データ抽出開始...")

    # 1. FanGraphs（現状 403 でブロックされ取得できないことが多いが、念のため試行）
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

    # 2. Baseball-Reference
    try:
        b_bat_full = bwar_bat()
        b_bat = b_bat_full[b_bat_full['year_ID'] == CURRENT_YEAR] if b_bat_full is not None else None
    except Exception as e:
        print(f"[エラー] B-Ref打者データ取得失敗: {e}")
        b_bat_full = None
        b_bat = None

    try:
        b_pitch_full = bwar_pitch()
        b_pitch = b_pitch_full[b_pitch_full['year_ID'] == CURRENT_YEAR] if b_pitch_full is not None else None
    except Exception as e:
        print(f"[エラー] B-Ref投手データ取得失敗: {e}")
        b_pitch_full = None
        b_pitch = None

    # 3. 対象選手（日本人選手）ごとのWARを抽出
    for mlb_id, pinfo in TARGET_PLAYERS.items():
        name = pinfo["name"]
        last_name = name.split()[-1]
        is_two_way = pinfo.get("is_two_way", False)
        is_pitcher = pinfo.get("is_pitcher", False)

        fwar = 0.0
        rwar = 0.0
        fwar_pitch = 0.0
        rwar_pitch = 0.0

        if not is_pitcher or is_two_way:
            fwar = search_war(bat_fg, last_name)
            rwar = search_war(b_bat, last_name)

        if is_pitcher or is_two_way:
            p_fwar = search_war(pitch_fg, last_name)
            p_rwar = search_war(b_pitch, last_name)
            if is_two_way:
                fwar_pitch = p_fwar
                rwar_pitch = p_rwar
            else:
                fwar = p_fwar
                rwar = p_rwar

        # ★ 年度別WAR・通算WAR（打撃・投手それぞれ、Baseball-Reference全期間データより算出）
        war_by_year_bat = extract_war_by_year(b_bat_full, last_name) if (not is_pitcher or is_two_way) else {}
        war_by_year_pitch = extract_war_by_year(b_pitch_full, last_name) if (is_pitcher or is_two_way) else {}
        career_rwar_bat = round(sum(war_by_year_bat.values()), 1) if war_by_year_bat else 0.0
        career_rwar_pitch_total = round(sum(war_by_year_pitch.values()), 1) if war_by_year_pitch else 0.0

        output[str(mlb_id)] = {
            "name": name,
            "name_ja": pinfo["name_ja"],
            "fwar": fwar,
            "rwar": rwar,
            "fwar_pitch": fwar_pitch,
            "rwar_pitch": rwar_pitch,
            "war_by_year": war_by_year_bat,
            "war_by_year_pitch": war_by_year_pitch,
            "career_rwar": career_rwar_bat,
            "career_rwar_pitch": career_rwar_pitch_total,
        }
        print(f"[{pinfo['name_ja']}] fWAR: {fwar}, rWAR: {rwar}, fWAR(投): {fwar_pitch}, rWAR(投): {rwar_pitch}, 通算rWAR: {career_rwar_bat}, 通算rWAR(投): {career_rwar_pitch_total}")

    # 4. MLB全体・リーグ別のWARランキング（上位50件）を作成
    batter_leaders = build_leaderboard(b_bat)
    pitcher_leaders = build_leaderboard(b_pitch)
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
