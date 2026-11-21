# YerelAI Studio — Aether 3.0 · Gemma 4 GGUF Turbo Yapay Zekâ Stüdyosu

Yerel NVIDIA GPU VRAM üzerinde **GGUF Turbo CUDA (`llama-server`)** hızında çalışan (RTX 4060'ta E2B ~95–100 tok/sn, E4B ~48–55 tok/sn); **yerleşik sesli konuşma**, **görsel anlama**, **4 kademeli Thinking Effort**, **akıllı canlı web & çoklu şehir hava durumu**, **canlı bayt bazlı model indirme**, **uzaktan erişim PIN kilidi** ve **Google Colab LoRA ince ayar** desteği sunan bağımsız yapay zekâ stüdyosu.

## Özellikler
- **Aether 3.0 Balanced Spatial Glass Arayüzü:** Koyu (Obsidian) ve Aydınlık (Seramik) temalarda yüzen cam adalar, `Ctrl + K` komut paleti, satır numaralı çok dilli kod editörü + **Canlı HTML/SVG Önizleme Çekmecesi**, animasyonlu bildirim merkezi ve etkileşimli veri tabloları.
- **GGUF Turbo CUDA + Dinamik VRAM:** Model yalnızca gerektiğinde GPU'ya yüklenir; canlı `GPU: %` ve çift katmanlı VRAM telemetrisi gösterir, boşta kalınca veya **"VRAM Boşalt"** ile belleği tamamen temizler.
- **Bayt Bazlı Canlı Model İndirme:** İndirilmeyen modeller (`E2B` / `E4B`) arka planda kaldığı yerden devam (resume) desteği, gerçek yüzde (`%`), hız (`MB/sn`) ve kalan süre (`ETA`) göstergesiyle indirilir.
- **Akıllı Web Araştırması & Bağlam Hafızası:** Gündelik sohbetlerde gereksiz web aramasını atlar; takip sorularını hatırlar (`Manisa hava durumu` → `Bolu için nasıl`), çoklu şehir hava durumu kartları ve doğrudan URL okuma sunar.
- **Sohbet Yönetimi & Güvenlik:** Mesaj düzenle & yeniden gönder, yanıtı yeniden üret, tarih gruplu/sabitlenebilir/yeniden adlandırılabilir sohbetler, Markdown (`.md`) & PDF dışa aktarma, 16K bağlam koruması ve Cloudflare tüneli için opsiyonel **PIN Kilidi**.
- **Doğrudan Sesli Konuşma & Türkçe Neural TTS:** 16 kHz WAV ses kaydı doğrudan Gemma 4'e iletilir; yanıtlar `edge-tts` (`Ahmet`/`Emel`) veya çevrimdışı Windows 11 `Tolga` ile satır içi seslendirilir.
- **Dosya & Tablo Analizi + Colab LoRA:** `.xlsx`, `.csv`, `.pdf`, `.docx`, kod ve görsel analizi; beğenilen yanıtları tek tıkla `JSONL` eğitim setine ekleyip `colab/Gemma4_YerelAI_Colab_FineTune.ipynb` ile eğitme.

## Kurulum ve Başlatma (Windows)
1. Depoyu klonlayın:
   ```bash
   git clone https://github.com/byashera/yerelai.git
   cd yerelai
   ```
2. Yerel kullanım için `Baslat.bat`, uzaktan Cloudflare HTTPS erişimi için `Uzaktan_Baslat.bat` dosyasına çift tıklayın (`http://127.0.0.1:8070`).
