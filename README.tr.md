# ios-android-simulator-testing — Claude uygulamanı kendisi açıp test etsin

[English](README.md) · Türkçe

Claude Code bir ekranı değiştirdiğinde genelde "bir bak, oldu mu?" diye sana sorar. Bu skill ile
bunu kendisi yapar: simülatörü açar, ekrana gider, butonlara basar, ekran görüntüsü alıp bakar,
yanlışsa düzeltip tekrar bakar. Sana kalan şey bitmiş işi görmek.

iOS simülatörü ve Android emülatörüyle çalışır. Gereken: **macOS + Xcode** (Android için ayrıca Android Studio).

## Kurulum (bir kerelik, ~2 dk)

```bash
npx skills add bartwo21/ios-android-simulator-testing -g     # skill'i kur (Claude Code'u seç)
~/.claude/skills/ios-android-simulator-testing/sim.sh setup  # iOS dokunuşu için idb'yi kurar
```

Android'de ek kurulum yok; `adb` Android Studio ile gelir. Bir emülatör (AVD) oluşturmuş olman yeter.
Güncellemek için: `npx skills update`.

## Projeye bağlama

Proje kökünde `.sim/config`:

```sh
BUNDLE_ID=com.firma.uygulama
DEVICE="iPhone 17 Pro"     # isteğe bağlı
AVD=Pixel_8_API_36         # isteğe bağlı (Android)
```

`.sim/` satırını `.gitignore`'a ekle — ekran görüntüleri buraya düşer.

**Asıl farkı yaratan:** projeye küçük bir "nasıl çalıştırılır" kartı yaz. Claude her seferinde
bunu okur ve ilk denemede doğru yere gider. `.claude/skills/<uygulama>-run/SKILL.md`:

```markdown
---
name: myapp-run
description: Use when myapp must be run, screenshotted or tapped through on the simulator.
---
Genel araç: ios-android-simulator-testing skill'i.

## Başlat
`npx expo start` arka planda, sonra `npx expo run:ios`. Native paket eklenince yeniden derle.

## Giriş
Giriş ekranında "Demo" butonu var (yalnız __DEV__). Hesap: demo / Demo123!

## Deeplink'ler
| ekran | url |
|---|---|
| profil | myapp://profile |
| ürün | myapp://product/<id> |

## Bilinen tuzaklar
- (Claude bir şeyde takıldıkça buraya eklesin.)
```

İki şey testi gerçekten kolaylaştırır:
1. **Deeplink** — Claude ekrana dokuna dokuna değil, doğrudan gider. En sağlam yol.
2. **Geliştirme girişi** — Apple/Google girişini otomasyon geçemez. `__DEV__` altında bir demo
   hesap butonu ya da otomatik giriş koy.

## Kullanımı

Bir şey istemen yeter: *"profil ekranını düzelt ve simülatörde kontrol et"*, *"android'de nasıl
duruyor, ss al"*, *"giriş → sepet → ödeme akışını dene"*. Claude skill'i kendisi açar.

Elle de kullanılabilir:

```bash
S=~/.claude/skills/ios-android-simulator-testing/sim.sh     # Android için: $S -a <komut>
$S open "myapp://profile"   # ekrana git
$S shot profil              # ekran görüntüsü → .sim/shots/profil.png
$S tree                     # ekrandaki butonlar/yazılar + koordinatları
$S tap "Kaydet"             # yazısına göre dokun
$S type "merhaba"           # yaz
$S rec start / $S rec stop   # video (animasyon kontrolü için)
$S dark                     # karanlık mod
$S help                     # hepsi
```

## Bilmekte fayda var

- Simülatörü Claude kullanırken sen de dokunursan birbirinize karışırsınız; o çalışırken izle.
- iOS ve Android'i aynı anda açma, Mac çok yavaşlar. Biri bitince öbürüne geç.
- Gerçek hesabınla açık simülatörde Claude'a "silme/satın alma" gibi işleri test ettirme; demo hesap kullan.
- Bir şey takılırsa Claude'a "bunu proje kartına tuzak olarak yaz" de — bir dahaki sefere takılmaz.
