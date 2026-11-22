<div align="center">

# ✦ SEN.AI

**Yerel GPU Üzerinde Çalışan Çok Modlu Yapay Zekâ Stüdyosu — Windows Masaüstü, Web/PWA & Native SwiftUI iOS 26–27**

[![Engine](https://img.shields.io/badge/Motor-Gemma%204%20(E2B%20%2F%20E4B)-2563eb?style=flat-square)](https://ai.google.dev/gemma)
[![CUDA](https://img.shields.io/badge/CUDA-llama.cpp%20GGUF%20Turbo-76b900?style=flat-square&logo=nvidia&logoColor=white)](https://github.com/ggml-org/llama.cpp)
[![Desktop](https://img.shields.io/badge/Masa%C3%BCst%C3%BC-Electron%20Windows%2011-0f172a?style=flat-square&logo=electron&logoColor=white)](desktop/)
[![iOS](https://img.shields.io/badge/iOS-SwiftUI%20Liquid%20Glass%20(iOS%2026%E2%80%9327)-000000?style=flat-square&logo=apple&logoColor=white)](ios-app/)
[![Build iOS](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml/badge.svg)](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml)

*Verileriniz cihazınızdan çıkmadan, RTX GPU hızında Türkçe sesli, görsel, kod, canlı web araştırması ve belge asistanı.*

</div>

---

## Öne Çıkan Özellikler

### 📱 Native SwiftUI iOS 26–27 Liquid Glass Uygulaması
- **%100 Saf SwiftUI & Gerçek Liquid Glass:** iOS 26–27 cihazlarda `GlassEffectContainer` ve `.glassEffect()` materyalleri, 60 FPS `.drawingGroup()` arka plan kırılması ve **50 ms SSE token birleştirme (coalescing)** ile takılmasız akış.
- **Modern Sohbet & Yan Menü Mimarisi:** Ana ekranı `36pt` yuvarlatılmış gölgeli bir kart olarak sağa kaydıran yan menü çekmecesi (Sidebar Drawer), gruplu kart tasarımlı Ayarlar ve mesaj kutusu **içinde** beliren çerçevesiz `🌐 Araştır ×` / `📚 Kütüphane ×` rozetleri.
- **Yüzen Liquid Glass `+` Menüsü & Geçici Sohbet:** Tek dokunuşla açılan yarı saydam `+` menüsü (`Kamera`, `Fotoğraflar`, `Web'de araştır`, `Kütüphane`, `Ayarlar`) ve geçmişe/belleğe kaydedilmeyen **Geçici Sohbet** (*Kişiselleştirilmiş / Kişiselleştirilmemiş*) modu.
- **Cosmic Düşünme Eforu & Türkçe Sistem Uyumu:** `Kapalı · Düşük · Orta · Yüksek` parçacık animasyonlu düşünme kaydırıcısı ve yerel Türkçe metin seçim menüsü (`Kes | Kopyala | Otomatik Doldur`).
- **Akıllı Çift Bağlantı:** Evde Wi-Fi LAN (`192.168.x.x:8070`), dışarıda sabit **GitHub Gist JSON + Cloudflare** köprüsü ile otomatik geçiş.

### 🌐 Gerçek Zamanlı Web Araştırması, Akıllı Oto-Arama & RAG
- **Gerçek Zamanlı (`1 → 2 → 3 → 4 → 5`) Canlı Sayaç:** `asyncio.Queue` tabanlı SSE ilerlemesi sayesinde her site incelenirken sayaç ve aktif alan adı (`🌐 3 web sitesi aranıyor · referansturk.com.tr`) anlık olarak güncellenir.
- **Akıllı Otomatik Araştırma:** Uygulama açılışında `Araştır` etiketi varsayılan olarak kapalıdır; ancak mesajda ürün, film/dizi çekim mekânı, fiyat veya güncel doğrulama gerektiren bir ifade geçtiğinde (kişisel/burç/plan/kod soruları hariç) otomatik olarak web araştırması devreye girer.
- **Korsan/Spam Filtresi & Favicon'lu Kaynaklar:** Düşük kaliteli spam/korsan dizi sitelerini eler, `<article>`/`<main>` gövdesinden 3200 karakterlik temiz bağlam çıkarır ve yanıt altında gerçek site ikonlu (**Favicon**) **`Kaynaklar`** kapsülü sunar.
- **Yerel Bilgi Kütüphanesi (RAG) & MCP:** PDF, Word, TXT ve CSV belgelerinizi yerel olarak indeksler; masaüstünde `filesystem`, `sqlite`, `git` ve `fetch` MCP araçlarını çalıştırır.

### 💎 Zengin Görsel Kartlar (`sen_card`) & Belge Üretimi
- **6 İnteraktif Görsel Kart Türü:**
  - `image_spotlight`: Mekân, yapı ve konular için yüksek çözünürlüklü tekli fotoğraf ve konum kartı.
  - `choice_card`: Numaralı (`1.`, `2.`) çoktan seçmeli interaktif tercih kartı.
  - `media_list`: Afişli/görselli film, dizi ve ürün öneri listesi.
  - `image_compare`: Yan yana görselli 2'li ürün/seçenek karşılaştırma kartı.
  - `scorecard`: Uyum ve puanlama halkası, kategori barları, güçlü yönler ve zorluklar kartı.
  - `checklist`: Canlı ilerleme çubuklu, tıklanabilir günlük/haftalık rutin kartı.
- **Canlı Hava Durumu, Döviz & Temiz Tablolar:** 5 günlük Apple Weather tarzı tahmin kartı, anlık kur kartları, hücre içi kalın metin ve yeşil vurgu rozeti (`Çok iyi`, `En iyi`) destekli Markdown tabloları.
- **Tek Tıkla `.xlsx` / `.docx` / `.pdf` & Split-Pane Kod Editörü:** Markdown tablolarından formüllü Excel çalışma kitabı, Word/PDF dışa aktarımı ve canlı HTML/CSS/JS/Python önizleme.

### ⚡ Yerel GPU Motoru, Türkçe Ses & Canlı 👍/👎 Geri Bildirim Motoru
- **Gemma 4 (`E2B` & `E4B`) GGUF CUDA Turbo:** `llama-server` üzerinde Flash Attention, Q8 KV Cache ve `--cache-reuse` ile **60+ tok/sn** yerel üretim hızı.
- **Akıllı Uzman Yönlendirme:** Konuya göre otomatik uzman modu (`Web & UI Tasarımcısı`, `Veri & Excel Analisti`, `Kıdemli Yazılımcı`, `Çevirmen`, `Özet & Editör`).
- **Doğal Türkçe Sesli Sohbet (TTS & STT):** Emojileri ve kod bloklarını atlayarak yalnızca konuşma metnini doğal Neural seslerle (`Ahmet` / `Emel`) seslendirir; tam ekran dalga formlu canlı sesli sohbet modu sunar.
- **Canlı Etkili & Kalıcı 👍 / 👎 Sistemi:** Mesaj beğenileri sohbet geçmişinde kalıcı olarak saklanır, tekrar dokunulduğunda geri alınabilir (mükerrer kayıt üretmez), modelin sonraki canlı yanıt tarzını anında besler ve Unsloth uyumlu **SFT / DPO** eğitim seti oluşturur.

---

## Hızlı Kurulum (Windows)

SEN.AI, NVIDIA GPU sürücünüzün CUDA sürümünü (`cu124` / `cu121` / `cu118`) otomatik algılayarak izole Python 3.11 + CUDA PyTorch (`torch`) + Gemma 4 ortamını kendi kendine kurar:

```powershell
# 1. Depoyu klonlayın
git clone https://github.com/byashera/yerelai.git
cd yerelai

# 2. Otomatik kurulum ve başlatıcıyı çalıştırın:
#    - İzole Python 3.11 + CUDA PyTorch + tüm paketleri kurar
#    - Electron Masaüstü Uygulamasını kurar ve Windows Masaüstüne "SEN.AI Studio" kısayolu ekler
#    - Uygulamayı doğrudan masaüstü penceresinde (veya Node.js yoksa http://127.0.0.1:8070 tarayıcıda) açar
.\Baslat.bat
```

> **İpucu:** `.\Baslat.bat` (veya `powershell -NoProfile -ExecutionPolicy Bypass -File .\kurulum.ps1`) ilk çalıştırmada hem Python/CUDA hem de Electron masaüstü bağımlılıklarını otomatik kurar ve masaüstünüze **SEN.AI Studio** kısayolu oluşturur. Doğrudan `python backend.py` veya `cd desktop && npm install && npm start` komutlarını çalıştırsanız bile sistem otomatik olarak kurulu CUDA ortamına (`venv` / `.unsloth`) geçiş yapar.
>
> **İlk Model İndirme:** `.gguf` model ağırlıkları (3.4 GB – 5.6 GB) Git deposunda yer almaz. Bilgisayarınızda daha önce indirilmiş `models/gguf` varsa otomatik tanınır; ilk kez kuruyorsanız açılan arayüzde **Ayarlar → Modeller** sekmesinden **Gemma 4 E2B / E4B (GGUF Turbo)** modelini tek tıkla indirebilirsiniz.

- **Masaüstü Uygulaması (Electron):** `.\Baslat.bat` veya `YerelAI_Masaustu.vbs` (manuel başlatma için `cd desktop && npm install && npm start`)
- **Yerel Wi-Fi (LAN) Erişimi:** `lan_ac.bat` dosyasına sağ tıklayıp **Yönetici olarak çalıştır** seçin.

## iPhone'a Kurulum

1. [**Actions → Build SEN.AI iOS**](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml) sayfasından en güncel **`SEN-AI-iOS-IPA`** paketini indirin.
2. `SEN-AI.ipa` dosyasını **Sideloadly**, **SideStore** veya **AltStore** ile iPhone'a yükleyin.
3. Uygulama içinden **Sol Menü → SA (Ayarlar) → Sunucu Adresleri** bölümünden yerel LAN IP veya sabit GitHub Gist JSON adresinizi doğrulayın.

---

## Proje Mimarisi

```text
yerelai/
├── backend.py                  # FastAPI SSE akış sunucusu, Gemma 4 CUDA motoru & Gerçek Zamanlı Web/RAG/DPO API
├── modules/                    # Excel/Word/PDF/TTS, MCP istemcisi, Cloudflare+Gist tünel, Workspace
├── frontend/                   # Masaüstü & Mobil PWA arayüzü (index.html, app.js, styles/desktop/mobile.css)
├── desktop/                    # Windows 11 Electron uygulaması (Splash, Companion, Sistem Tepsisi)
├── ios-app/                    # Native SwiftUI iOS 26–27 Liquid Glass uygulaması (XcodeGen)
├── colab/                      # Ücretsiz T4 GPU Unsloth LoRA eğitim notebook'u
└── .github/workflows/          # Otomatik iOS .ipa, Simülatör & 10'lu Ekran Görüntüsü derleyicisi
```
