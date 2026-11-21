<div align="center">

# ✦ SEN.AI

**Yerel GPU Üzerinde Çalışan Çok Modlu Yapay Zekâ Stüdyosu — Windows Masaüstü, Web/PWA & Native SwiftUI iOS**

[![Engine](https://img.shields.io/badge/Motor-Gemma%204%20(E2B%20%2F%20E4B)-2563eb?style=flat-square)](https://ai.google.dev/gemma)
[![CUDA](https://img.shields.io/badge/CUDA-llama.cpp%20GGUF%20Turbo-76b900?style=flat-square&logo=nvidia&logoColor=white)](https://github.com/ggml-org/llama.cpp)
[![Desktop](https://img.shields.io/badge/Masa%C3%BCst%C3%BC-Electron%20Windows%2011-0f172a?style=flat-square&logo=electron&logoColor=white)](desktop/)
[![iOS](https://img.shields.io/badge/iOS-SwiftUI%20Liquid%20Glass%20(iOS%2026%2B)-000000?style=flat-square&logo=apple&logoColor=white)](ios-app/)
[![Build iOS](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml/badge.svg)](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml)

*Verileriniz cihazınızdan çıkmadan, RTX GPU hızında Türkçe sesli, görsel, kod ve belge asistanı.*

</div>

---

## Öne Çıkan Özellikler

### ⚡ Yerel GPU Motoru & Akıllı Hızlandırma
- **Gemma 4 (`E2B` & `E4B`) GGUF CUDA Turbo:** `llama-server` üzerinde Flash Attention, Q8 KV Cache ve çok turlu `--cache-reuse` ile **60+ tok/sn** yerel üretim hızı.
- **Dinamik Temperature & Kişilik:** Genel sohbetlerde doğal ve akıcı (`0.73`), kod/Excel ve teknik analizlerde yüksek doğruluklu (`0.68`) otomatik ayarlama.
- **Akıllı Uzman Yönlendirme:** Konuya göre otomatik uzman modu (`Web & UI`, `Veri & Excel`, `Kıdemli Yazılımcı`, `Çevirmen`, `Özet & Editör`).

### 💎 Zengin Görsel Kartlar & Belge Üretimi
- **Otomatik Görsel Kartlar (`sen_card`):** Uyum/Skor halkası, Karşılaştırma, Öneri/Puanlama ve tıklanabilir Plan/Kontrol Listesi kartları.
- **Canlı Hava Durumu & Döviz:** 5 günlük Apple Weather tarzı tahmin şeridi ve anlık kur kartları.
- **Tek Tıkla Gerçek `.xlsx` / `.docx` / `.pdf`:** Markdown tablolarından otomatik formüllü Excel çalışma kitabı, Word ve PDF dışa aktarımı.
- **Canlı Split-Pane Kod Editörü:** HTML/CSS/JS canlı önizleme, görsel fark (`v1 ↔ v2`), Python sandbox ve yerel klasör çalışma alanı.

### 🌐 Akıllı Web Araştırması, RAG & MCP
- **İhtiyaç Odaklı Canlı Web:** Yalnızca güncel bilgi, haber, hava durumu, döviz veya açık arama istendiğinde internete çıkar; düşük kaliteli spam siteleri eler ve yanıt altında kompakt **`🌐 N kaynak`** kapsülü sunar.
- **Yerel Bilgi Kütüphanesi (RAG):** PDF, Word, TXT ve CSV belgelerinizi proje bazlı izole olarak indeksler.
- **Yerel MCP İstemcisi:** Masaüstü uygulamasında dahili çevrimdışı `filesystem`, `sqlite`, `git` ve `fetch` araçlarını kullanıcı onay kartıyla çalıştırır.

### 🗣️ Türkçe Sesli Sohbet & Eğitim Seti Motoru
- **Temiz ve Hızlı Türkçe TTS:** Emojileri ve kod bloklarını sessizce atlayıp yalnızca yazılı metni doğal tempoda (`+20%`) seslendirir; mikrofondan Türkçe sesli giriş destekler.
- **👍 / 👎 ile SFT & DPO Veri Seti:** Beğeni ve düzeltmelerinizden otomatik Unsloth uyumlu **SFT** ve **DPO (`prompt / chosen / rejected`)** eğitim setleri üretir, ücretsiz Google Colab T4 notebook'u ile kendi LoRA modelinizi eğitmenizi sağlar.

### 📱 Native SwiftUI iOS Uygulaması (iOS 26–27 Liquid Glass)
- **%100 Saf SwiftUI (~480 KB `.ipa`):** iOS 26–27 cihazlarda gerçek `GlassEffectContainer` ve `.glassEffect()` materyalleri, iOS 17–18 cihazlarda zarif `.ultraThinMaterial` uyumu.
- **Akıllı Çift Bağlantı:** Evde Wi-Fi LAN (`192.168.x.x:8070`), dışarıda sabit **GitHub Gist JSON + Cloudflare** köprüsü ile kesintisiz erişim.
- **Otomatik GitHub Actions Derleme:** Her güncellemede imzasız `SEN-AI.ipa`, Appetize.io için `SEN-AI-Simulator.app.zip` ve Açık/Koyu tema simülatör ekran görüntüleri otomatik üretilir.

---

## Hızlı Kurulum (Windows)

```powershell
# 1. Depoyu klonlayın
git clone https://github.com/byashera/yerelai.git
cd yerelai

# 2. Bağımlılıkları kurun
pip install -r requirements.txt

# 3. Sunucuyu başlatın (http://127.0.0.1:8070)
python backend.py
```

- **Masaüstü Uygulaması (Electron):** `desktop/` klasöründe `npm install && npm start`
- **Yerel Wi-Fi (LAN) Erişimi:** `lan_ac.bat` dosyasına sağ tıklayıp **Yönetici olarak çalıştır** seçin.

## iPhone'a Kurulum

1. [**Actions → Build SEN.AI iOS**](https://github.com/byashera/yerelai/actions/workflows/build-ios.yml) sayfasından en güncel **`SEN-AI-iOS-IPA`** dosyasını indirin.
2. `SEN-AI.ipa` paketini **Sideloadly**, **SideStore** veya **AltStore** ile iPhone'a yükleyin.
3. Uygulama içinden **SEN.AI ⌄ → Ayarlar & Sunucu** kısmına yerel IP veya sabit GitHub Gist JSON adresinizi girin.

---

## Proje Mimarisi

```text
yerelai/
├── backend.py                  # FastAPI SSE akış sunucusu, Gemma 4 CUDA motoru & Web/RAG/DPO API
├── modules/                    # Excel/Word/PDF/TTS, MCP istemcisi, Cloudflare+Gist tünel, Workspace
├── frontend/                   # Masaüstü & Mobil PWA arayüzü (index.html, app.js, styles/desktop/mobile.css)
├── desktop/                    # Windows 11 Electron uygulaması (Splash, Companion, Sistem Tepsisi)
├── ios-app/                    # Native SwiftUI iOS 26-27 Liquid Glass uygulaması (XcodeGen)
├── colab/                      # Ücretsiz T4 GPU Unsloth LoRA eğitim notebook'u
└── .github/workflows/          # Otomatik iOS .ipa, Simülatör & Ekran Görüntüsü derleyicisi
```
