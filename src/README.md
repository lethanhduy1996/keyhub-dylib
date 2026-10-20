# KeyHubGate - thu vien gate License cho iOS (POC)

Day la **thu vien khong ky, chua duoc test tren iPhone**, du kien build bang iPhoneOS SDK tren GitHub Actions macOS. Khong phai file .dylib da test/ky co the cai truc tiep.

## Chuc nang

- Khi injector thuc su load `KeyHubGate.dylib` trong process app, constructor khoi dong giao dien khoa (window rieng) tai man hinh ung dung.
- Dung email + mat khau KeyHub de lay JWT (`POST /api/v1/auth/login`).
- Dung License cua tai khoan de kich hoat UUID thiet bi (`POST /api/v1/keys/activate`).
- Khi mo app/foreground: `POST /api/v1/keys/verify` de xac nhan chua het han, khong bi thu hoi, va dung UUID da dang ky.
- License va UUID duoc luu trong Keychain iOS (ThisDeviceOnly). KHONG luu password.
- API: `https://keyhub-api-s6t3.onrender.com/api/v1`, dung HTTPS.

## Bien dich tren GitHub Actions (iPhone)

1. Upload `src/KeyHubGate.m` va `.github/workflows/build-ios-dylib.yml` vao mot GitHub repository.
2. Vao tab **Actions** > `Build iOS KeyHub Gate dylib` > `Run workflow` (hoac push vao branch `keyhub-dylib-build`).
3. Cho `build` thanh cong, tai artifact `KeyHubGate-iOS17-arm64-unsigned`.
4. Giai nen artifact de lay `KeyHubGate.dylib`.
5. Dung cong cu injection tuong thich voi app va iOS (bat buoc sua load command cua binary); sau do ky lai toan bo IPA bang chung chi cua ban. Chung toi khong khang dinh app sua doi se chay khi chua test tren thiet bi.

## Gioi han quan trong

- **Khong phai bao ve khong the vuot qua**: mot UI window trong library co the bi go bo khi sua binary. Muon bao ve chuc nang cot loi can them backend enforcement.
- **Khong thay the backend**: can KeyHub API dang chay; muc test "health" chua du bao dam cac endpoint kich hoat/verify hoat dong.
- Key phai thuoc ve email nguoi dung dang nhap. Moi key chi duoc kich hoat theo gioi han thiet bi da cap.
- App tu dong phai mang theo library va load library khi khoi dong, neu khong thi gate **khong duoc chay**. Phai **resign IPA** (ma ID va entitlements hop le) sau injection.
- Test tren app ban co quyen sua doi; khong dong goi/phat tan app thu ba ma khong co quyen.
- Render free spin-down co the gay tre >50 giay; network timeout la 100 giay. Mac dinh fail-closed khi mat mang.
- Man hinh gate hien chu tieng Viet khong dau de tranh encoding hoac font tai bien dich, co the cai thien.
- Ban POC chua co offline grace period, rate limiting client, MFA, credential recovery, App Attest, hardening. Khong phu hop cho phat hanh thuong mai khi chua kiem thu.

## Ve file dylib mau

`1792522829497_48187_6.1.0BC.dylib` la Mach-O arm64 co LC_ID_DYLIB `@rpath/APIKey.dylib`, nhung `__LINKEDIT` ghi file length > bytes thuc te (thieu khoang 17 KB); llvm-objdump bao **malformed object**. Khong nen coi la dylib mau hop le de nhung/patch san.
