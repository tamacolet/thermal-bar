#ifndef ThermalBarBridging_h
#define ThermalBarBridging_h

int tb_thermal_level(void);                  // -1=不明, 0..4=Nominal..Sleeping
int tb_smc_init(void);                       // 0=成功。Ta*キーを列挙して保持
double tb_smc_read(const char *key);         // NAN=失敗
int tb_smc_ta_count(void);
const char *tb_smc_ta_key(int index);
double tb_smc_ta_max(void);                  // Ta*キーの最大値
double tb_hid_max(const char *namePrefix);   // 名前prefix一致センサーの最大値, NAN=なし
void tb_hid_list(void);                      // 全HID温度センサーを標準出力へ（selftest用）

#endif
