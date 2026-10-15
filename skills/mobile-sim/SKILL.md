---
name: mobile-sim
description: Use when a change to an iOS or Android app (Expo, React Native, native) needs to be SEEN working rather than reasoned about — "run it", "simülatörde aç", "ss al", "does this look right", "android'de nasıl görünüyor", "tap through the flow", after any visual edit, or when a bug only reproduces in the app. Drives the iOS simulator and the Android emulator. macOS only.
---

# mobile-sim

Bir UI değişikliğini "cihazda bakar mısın" demeden **kendin gör**. Tek araç, iki platform:

```bash
S=<bu skill'in klasörü>/sim.sh   # klasör: yüklenince verilen "Base directory"
$S <komut>                       # iOS
$S -a <komut>                    # aynı komut, Android
$S help                          # tüm komutlar
```

`idb yok` hatası → bir kez `$S setup`.

## Önce proje kartını oku

`<proje>/.claude/skills/*-run/SKILL.md` varsa ÖNCE onu oku: nasıl başlatılır, nasıl giriş
yapılır, deeplink haritası. Yoksa ve proje ayarı da yoksa bunları sahibine sor; öğrendiğini
README.md'deki şablonla o karta yaz. Proje ayarı `<proje>/.sim/config`'tedir (`BUNDLE_ID`, `DEVICE`, `AVD`).

## Döngü

```
1. $S boot                       (açıksa dokunmaz)
2. uygulamayı başlat             (proje kartındaki komut; JS değişikliğinde Metro yeniden yükler)
3. $S open "scheme://ekran"      hedef ekrana DOĞRUDAN git
4. $S shot ad                    → PNG'yi Read ile AÇ ve BAK
5. yanlışsa düzelt, 3'e dön
```

- **Deeplink varsa dokunma.** Dokunuş, deeplink'in gidemediği yerler içindir (buton, sheet, form, jest).
- **Dokunmadan önce `$S tree`.** Etikete dokun: `$S tap "Kaydet"`. Piksel ancak etiket yoksa.
- **Bakmadığın ekran doğrulanmış sayılmaz.** Yolu yazıp geçme; ne gördüğünü söyle.
- **Geçiş/animasyon ekran görüntüsüyle doğrulanmaz:** `$S rec başla` → işlem → `$S rec dur`, kareleri incele.
- İki platformu da destekleyen uygulamada iş ikisinde de görülünce biter — ama **sırayla**:
  biri bitince `xcrun simctl shutdown all` / `adb emu kill`; ikisi birden Mac'i kilitler.

## Tuzaklar

| Belirti | Sebep / çözüm |
|---|---|
| `tree` boş | Uygulama önde değil ya da sistem diyaloğu açık (iOS sistem diyalogları ağaçta yok) → `shot` al, pikselle dokun |
| `tree`'de iOS 26 alt sekmeleri yok (yalnız "Tab Bar") | Sistem tab bar'ı ağaca girmiyor → deeplink, ya da ekran görüntüsünden piksel |
| Ekran sen dokunmadan değişiyor | Sahibi simülatörü kullanıyor → dokunma, yalnız ekran görüntüsü |
| Giriş ekranı | Akışı oynatma (Apple/Google girişi otomasyonla geçilmez). `__DEV__` demo hesabı / otomatik giriş kullan; geçici yamayı iş bitince sil |
| iOS'ta klavye çıkmıyor | `type` donanım klavyesi gibi yazar; ekran klavyesine bağlı yerleşimi cihazda doğrulat |
| Android `type` Türkçe harfte bozuluyor | `adb input text` yalnız ASCII yazar |
| Android'de değişiklik gelmiyor | `$S -a launch` (zorla kapatıp açar) |
| Yeni native paket sonrası açılışta çökme / "Symbol missing" | Yeniden derle (`npx expo run:ios` / `run:android`), yalnız yenileme yetmez |
| Çöktü, sebep yok | `$S log`; iOS çökme raporu `~/Library/Logs/DiagnosticReports/<App>-*.ips` |
| Emülatör kendiliğinden kapandı, logda "hanging thread" | Mac'in belleği yetmiyor → iOS simülatörünü/fazlalıkları kapat, `$S -a boot` |
| Harita/ağır ekranda yarım görüntü | `shot`'tan önce birkaç saniye bekle |

Gerçek hesapla açık simülatörde sil / çıkış / satın al gibi butonlara yalnız görev buysa dokun.
`tap` ekran dışı koordinatı zaten reddeder; `tree` yalnız ekrandakileri gösterir.

Simülatör yok ya da macOS değilse → `eas-simulator` (bulut). Saf mantık değişikliği ve testi varsa simülatör açma.
