# update_war.py
import json
from datetime import datetime, timezone
import pybaseball
from pybaseball import batting_stats, pitching_stats, bwar_bat, bwar_pitch

pybaseball.cache.enable()
CURRENT_YEAR = 2026

# 大谷選手のみ is_two_way を True に設定（これで自動で両方の表を探しに行きます）
TARGET_PLAYERS = {
    660271: {"name": "Shohei Ohtani", "name_ja": "大谷 翔平", "is_two_way": True},
    808967: {"name": "Yoshinobu Yamamoto", "name_ja": "山本 由伸", "is_pitcher": True},
    684007: {"name": "Shota Imanaga", "name_ja": "今永 昇太", "is_pitcher": True},
    673548: {"name": "Seiya Suzuki", "name_ja": "鈴木 誠也", "is_pitcher": False},
    807799: {"name": "Masataka Yoshida", "name_ja": "吉田 正尚", "is_pitcher": False},
    673540: {"name": "Kodai Senga", "name_ja": "千賀 滉大", "is_pitcher": True},
    506433: {"name": "Yu Darvish", "name_ja": "ダルビッシュ 有", "is_pitcher": True},
    673513: {"name": "Yuki Matsui", "name_ja": "松井 裕樹", "is_pitcher": True},
}

def extract_war(df, last_name, col_name='WAR'):
    if df is None or df.empty:
        return 0.0
    name_col = 'Name' if 'Name' in df.columns else 'name_common'
    match = df[df[name_col].str.contains(last_name, case=False, na=False)]
    if not match.empty and col_name in match.columns:
        try:
            return round(float(match[col_name].iloc[0]), 1)
        except:
            return 0.0
    return 0.0

def fetch_war_data():
    output = {}
    print("最新テーブルから自動抽出中...")

    # 最新テーブルを取得
    try: bat_fg = batting_stats(CURRENT_YEAR, qual=0)
    except: bat_fg = None

    try: pitch_fg = pitching_stats(CURRENT_YEAR, qual=0)
    except: pitch_fg = None

    try:
        b_bat = bwar_bat()
        b_bat = b_bat[b_bat['year_ID'] == CURRENT_YEAR] if b_bat is not None else None
    except: b_bat = None

    try:
        b_pitch = bwar_pitch()
        b_pitch = b_pitch[b_pitch['year_ID'] == CURRENT_YEAR] if b_pitch is not None else None
    except: b_pitch = None

    # 各選手の最新WARを自動抽出
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
            fwar = extract_war(bat_fg, last_name, 'WAR')
            rwar = extract_war(b_bat, last_name, 'WAR')

        if is_pitcher or is_two_way:
            p_fwar = extract_war(pitch_fg, last_name, 'WAR')
            p_rwar = extract_war(b_pitch, last_name, 'WAR')
            if is_two_way:
                fwar_pitch = p_fwar
                rwar_pitch = p_rwar
            else:
                fwar = p_fwar
                rwar = p_rwar

        output[str(mlb_id)] = {
            "name": name,
            "name_ja": pinfo["name_ja"],
            "fwar": fwar,
            "rwar": rwar,
            "fwar_pitch": fwar_pitch,
            "rwar_pitch": rwar_pitch,
        }

    final_payload = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "players": output
    }

    with open("war_data.json", "w", encoding="utf-8") as f:
        json.dump(final_payload, f, indent=2, ensure_ascii=False)
    print("自動更新完了！")

if __name__ == "__main__":
    fetch_war_data()
