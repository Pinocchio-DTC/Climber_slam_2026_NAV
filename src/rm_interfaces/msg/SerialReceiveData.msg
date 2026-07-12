# Source and frame type from talker parser: "three" or "seven"
string source_mode
uint32 match_time

# 3v3 frame fields
int16 score_diff
uint16 our_hero_blood
uint8 our_hero_level
uint16 our_infantry_blood
uint8 our_infantry_level
uint16 our_sentry_blood
uint16 enemy_hero_blood
uint8 enemy_hero_level
uint16 enemy_infantry_blood
uint8 enemy_infantry_level
uint16 enemy_sentry_blood

# 7v7 frame fields
uint16 hp
bool enemy_outpost_alive
bool our_outpost_alive
uint16 remaining_rounds
uint16 our_base_hp
uint8 sentry_mode
bool sentry_buff
