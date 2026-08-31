# update_war.py
import json
from datetime import datetime, timezone
import pybaseball
from pybaseball import batting_stats, pitching_stats, bwar_bat, bwar_pitch

# キャッシュを有効化して高速化
pybaseball.cache.enable()

CURRENT_YEAR = 2026

# 追跡対象の日本人選手（MLB IDと名前）
TARGET_PLAYERS = {
    660271: {"name": "Shohei Ohtani", "name_ja": "大谷 翔平", "is_pitcher": False},
    808967: {"name": "Yoshinobu Yamamoto", "name_ja": "山本 由伸", "is_pitcher": True},
    684007: {"name": "Shota Imanaga", "name_ja": "今永 昇太", "is_pitcher": True},
    506433: {"name": "Yu Darvish", "name_ja": "ダルビッシュ 有", "is_pitcher": True},
    673540: {"name": "Kodai Senga", "name_ja": "千賀 滉大", "is_pitcher": True},
    673548: {"name": "Seiya Suzuki", "name_ja": "鈴木 誠也", "is_pitcher": False},
}

def fetch_war_data():
    output = {}
    print("FanGraphs & Baseball-Reference から最新データを取得中...")
    
    # 1. FanGraphs の今季データを取得 (fWAR)
    try:
        bat_fg = batting_stats(CURRENT_YEAR)
    except Exception as e:
        print(f"FanGraphs 打者データ取得エラー: {e}")
        bat_fg = None

    try:
        pitch_fg = pitching_stats(CURRENT_YEAR)
    except Exception as e:
        print(f"FanGraphs 投手データ取得エラー: {e}")
        pitch_fg = None

    # 2. Baseball-Reference の今季データを取得 (rWAR / bWAR)
    try:
        bwar_bat_df = bwar_bat()
        bwar_bat_df = bwar_bat_df[bwar_bat_df['year_ID'] == CURRENT_YEAR]
    except Exception as e:
        print(f"B-Ref 打者データ取得エラー: {e}")
        bwar_bat_df = None

    try:
        bwar_pitch_df = bwar_pitch()
        bwar_pitch_df = bwar_pitch_df[bwar_pitch_df['year_ID'] == CURRENT_YEAR]
    except Exception as e:
        print(f"B-Ref 投手データ取得エラー: {e}")
        bwar_pitch_df = None

    # 3. 各選手ごとの WAR を抽出
    for mlb_id, pinfo in TARGET_PLAYERS.items():
        name = pinfo["name"]
        is_pitcher = pinfo["is_pitcher"]
        fwar = 0.0
        rwar = 0.0

        # --- FanGraphs (fWAR) ---
        if is_pitcher and pitch_fg is not None and not pitch_fg.empty:
            match = pitch_fg[pitch_fg['Name'].str.contains(name.split()[-1], case=False, na=False)]
            if not match.empty and 'WAR' in match.columns:
                fwar = round(float(match['WAR'].iloc[0]), 1)
        elif not is_pitcher and bat_fg is not None and not bat_fg.empty:
            match = bat_fg[bat_fg['Name'].str.contains(name.split()[-1], case=False, na=False)]
            if not match.empty and 'WAR' in match.columns:
                fwar = round(float(match['WAR'].iloc[0]), 1)

        # --- Baseball-Reference (rWAR) ---
        if is_pitcher and bwar_pitch_df is not None and not bwar_pitch_df.empty:
            match = bwar_pitch_df[bwar_pitch_df['name_common'].str.contains(name.split()[-1], case=False, na=False)]
            if not match.empty and 'WAR' in match.columns:
                rwar = round(float(match['WAR'].iloc[0]), 1)
        elif not is_pitcher and bwar_bat_df is not None and not bwar_bat_df.empty:
            match = bwar_bat_df[bwar_bat_df['name_common'].str.contains(name.split()[-1], case=False, na=False)]
            if not match.empty and 'WAR' in match.columns:
                rwar = round(float(match['WAR'].iloc[0]), 1)

        output[str(mlb_id)] = {
            "name": name,
            "name_ja": pinfo["name_ja"],
            "fwar": fwar,
            "rwar": rwar,
        }
        print(f"[{pinfo['name_ja']}] fWAR: {fwar}, rWAR: {rwar}")

    final_payload = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "players": output
    }

    with open("war_data.json", "w", encoding="utf-8") as f:
        json.dump(final_payload, f, indent=2, ensure_ascii=False)
    
    print("war_data.json への書き出しが完了しました！")

if __name__ == "__main__":
    fetch_war_data()