# 🌑 Nocta

Ekran qora bo'lib turganda video yozadigan va rasm oladigan iOS ilovasi.
Olingan fayllar galereyaga tushmaydi — ilova ichidagi albomda qoladi.

## Uchta ekran

```
[ Albom ]  ←— chapga surish —  [ Bosh ekran ]  — o'ngga surish —→  [ Qora ekran ]
```

### Bosh ekran
- **Video** yoki **Rasm** rejimini tanlaysiz
- Yuqori chapda albom tugmasi va undagi fayllar soni
- Kamera holati: yashil nuqta = tayyor

### Qora ekran (o'ngga surish)
Ekran qorayadi, yorug'lik 0 ga tushadi, status bar yashiriladi, avtomatik qulflash o'chiriladi.

| Amal | Natija |
|---|---|
| kirganda (Video) | yozish **o'zi boshlanadi** |
| **bosish** | Video: to'xtatadi / boshlaydi · Rasm: **rasm oladi** (ovozsiz, cheksiz) |
| **yuqoriga/pastga surish** | kamerani almashtiradi — **yozish paytida ham** |
| **chapga surish** | to'xtatadi, saqlaydi va bosh ekranga qaytadi |

Ekran ko'rinmagani uchun har amal **titrash** bilan tasdiqlanadi:
kirish = o'rtacha, rasm olindi = qisqa qattiq, yozish boshlandi = ikki marta, to'xtadi = ogohlantiruv.
Kamera almashtirilganda titrash **soni** qaysi kamera yoqilganini bildiradi:
**1 = orqa, 2 = old, 3 = ikkisi.**

### Kamera rejimlari

| Rejim | Nima bo'ladi |
|---|---|
| **Orqa** | faqat orqa kamera, to'liq ekran |
| **Old** | faqat old kamera (ko'zgusiz emas — to'g'ri tomonga aylantirilgan) |
| **Ikkisi** | orqa kamera to'liq ekran + old kamera o'ng yuqori burchakda PiP oynachada |

**Yozish paytida almashtirish uzilishsiz** — hammasi bitta faylga yoziladi, ovoz uzilmaydi.
Buning uchun `AVCaptureMovieFileOutput` o'rniga `AVAssetWriter` ishlatilgan: u sessiyadan
mustaqil, kadrlar qayerdan kelishidan qat'i nazar bitta uzluksiz faylga yozadi.

**"Ikkisi" rejimi** `AVCaptureMultiCamSession` talab qiladi — **iPhone XS/XR va yangiroq**
(A12+). Eski qurilmada bu rejim ko'rinmaydi, old↔orqa almashtirish esa ishlaydi, lekin
videoda qisqa (~0.2 s) uzilish bo'ladi, chunki sessiya kirishini almashtirish kerak.

### Albom (chapga surish)
- Barcha olingan video va rasmlar 3 ustunli to'rda, video uzunligi bilan
- Bosilsa — to'liq ekranda ko'rish (video pleer bilan)
- **Tanlash** → kerakli fayllarni belgilab:
  - **Galereyaga saqlash** — Fotosuratlarga **nusxalanadi**, asl nusxa albomda qoladi
  - **O'chirish** — tasdiqlash so'raladi
- Uzoq bosish ham tanlash rejimini yoqadi
- O'ngga surish yoki "← Kamera" — orqaga

## Nega albom kerak?

Fayllar to'g'ridan-to'g'ri galereyaga tushsa, telefon galereyasini ochgan har kim ularni ko'radi.
Nocta ularni ilova sandbox'ida (`Application Support/Media`) saqlaydi — boshqa ilovalar va Fayllar
ilovasi ko'rmaydi. Galereyaga faqat siz tanlagani o'tadi.

⚠️ **Ilovani o'chirsangiz albomdagi fayllar ham o'chadi.** Kerakli narsalarni galereyaga saqlab qo'ying.

## 📂 Fayllar

| Fayl | Vazifasi |
|---|---|
| `NoctaApp.swift` | Ilova kirish nuqtasi |
| `ContentView.swift` | Uch ekran navigatsiyasi, yorug'lik va auto-lock mantiqi |
| `HomeView.swift` | Bosh ekran: rejim tanlash, surish |
| `BlackScreenView.swift` | Qora ekran: bosish va chapga surish |
| `AlbumView.swift` | Albom: to'r, tanlash, galereyaga saqlash, o'chirish, ko'rish |
| `MediaStore.swift` | Fayllarni saqlash, thumbnail, galereyaga eksport |
| `CameraManager.swift` | AVFoundation: sessiya, kameralar, almashtirish |
| `RecordingEngine.swift` | `AVAssetWriter` orqali uzluksiz video yozish |
| `FrameCompositor.swift` | Kadrlarni bir o'lchamga keltirish va PiP kompozitsiyasi |
| `Haptics.swift` | Titrash bilan javob berish |
| `Assets.xcassets/` | Ilova ikonkasi (1024×1024) |
| `Info.plist` | Nom, ruxsat matnlari, portret rejim |

## 🔧 O'rnatish (Xcode)

1. Xcode → File → New → Project → **iOS App**
   - Product Name: `Nocta`
   - Interface: **SwiftUI**, Language: **Swift**
2. **Minimum Deployment: iOS 17.0**
3. Yaratilgan `ContentView.swift` va `NoctaApp.swift` fayllarini shu papkadagilar bilan
   almashtiring, qolgan `.swift` fayllarni loyihaga qo'shing (*Copy items if needed*)
4. `Assets.xcassets` papkasidagi `AppIcon.appiconset` ni loyiha asset katalogiga ko'chiring
5. **Ruxsatlar** — Xcode'da **Target → Info** bo'limiga qo'lda qo'shing:
   - `Privacy - Camera Usage Description`
   - `Privacy - Microphone Usage Description`
   - `Privacy - Photo Library Additions Usage Description`
6. **Target → General → Deployment Info** da faqat **Portrait**
7. Display Name: `Nocta`
8. iPhone'ni ulang → ▶️ Run → telefonda Settings → General → VPN & Device Management → **Trust**

⚠️ Bepul Apple ID bilan sertifikat **7 kun** ishlaydi. Qayta imzolaganda albomdagi fayllar
saqlanib qoladi, lekin ilovani **o'chirib qayta o'rnatsangiz** — yo'qoladi.

## ⚠️ iOS cheklovlari (kod xatosi emas)

1. **Fonda ishlamaydi.** iOS kameraga background rejim bermaydi. Ilova yopilsa yoki telefon
   qulflansa yozish to'xtaydi — kod bu holatda videoni darhol albomga saqlab qoladi.
2. **Yashil indikator.** Kamera ishlayotganda iOS yuqorida yashil nuqta ko'rsatadi,
   uni o'chirib bo'lmaydi.
3. **Yorug'lik 0 ham to'liq qora emas.** Qorong'i xonada ekran sezilib turadi.

## 📷 Rasm sifati haqida

Rasm `AVCapturePhotoOutput` bilan emas, video oqimidan kadr olish yo'li bilan saqlanadi.
Sababi: `AVCapturePhotoOutput` har safar tizim zatvor ovozini chaladi va uni rasmiy API bilan
o'chirib bo'lmaydi — qora ekran uchun bu mantiqsiz. Shuningdek "Ikkisi" rejimidagi PiP
kompozitsiyasi ham faqat shu yo'l bilan rasmga tushadi.

Natija: rasm **ovozsiz**, lekin o'lchami video o'lchamiga teng (1080×1920 atrofida, ~2 MP),
to'liq 12 MP emas. To'liq sifat kerak bo'lsa aytsangiz — `AVCapturePhotoOutput` ni "Orqa"/"Old"
rejimlari uchun qaytarib qo'shish mumkin (ovoz bilan).

## 📋 Talablar
- iPhone, iOS **17.0+**
- Xcode 15+, Apple ID

## ⚖️ Eslatma
Ko'p mamlakatlarda, O'zbekistonda ham, odamni roziligisiz yozib olish qonun bilan cheklanadi.
App Store qoidalari (2.5.9, 5.1.1) bunday ilovalarni qabul qilmaydi — faqat shaxsiy qurilmaga
sideloading orqali o'rnatiladi.
