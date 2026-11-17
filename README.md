# InseegoManager iOS (SwiftUI)

Ứng dụng iOS thuần SwiftUI để quản lý các thiết bị phát Wi-Fi **Inseego MiFi (M2000 / M3000 / M3100 / M3200 / FX3100)** qua Wi-Fi (`192.168.1.1`).

## Tính năng chính
- Đăng nhập WebUI (hỗ trợ cả SHA-1 và BCrypt `$2a$`, lưu mật khẩu vào iOS Keychain)
- Dashboard trực quan: Công nghệ mạng, Băng tần, RSRP/SNR, Nhiệt độ CPU & Pin, Lưu lượng hôm nay, % Pin
- Khóa băng tần **4G LTE**, **5G NR (NSA/SA)**, Quét dò băng tần 4G, đổi chế độ **Tiết kiệm / Turbo**
- Cấu hình **APN** (kèm preset Viettel, MobiFone, VinaPhone, Vietnamobile, Gmobile, iTel), **TTL**, **IMEI**
- Biểu đồ sóng trực tiếp RSRP / SNR / Nhiệt độ bằng Swift Charts
- Quản lý sức khỏe Pin (**Battery Health**), ngắt sạc thủ công & chế độ **Router 24/7**
- Cài đặt **Wi-Fi (SSID / Mật khẩu)**, **IP LAN**, **Tin nhắn SMS**, Đổi mật khẩu Admin & Nhật ký gỡ lỗi

## Tự động build `.ipa` (Unsigned)
Workflow `.github/workflows/build-ios.yml` sử dụng **XcodeGen** + `xcodebuild archive` (`CODE_SIGNING_ALLOWED=NO`) trên `macos-latest` để đóng gói `InseegoManager.ipa` trong mục Artifacts của GitHub Actions.
