# YerelAI Studio — Gemma 4 Multimodal Yerel VRAM Yapay Zekâ Stüdyosu

Tamamen internet bağlantısı olmadan yerel NVIDIA GPU VRAM üzerinde çalışan; **yerleşik sesli konuşma**, **görsel anlama**, **4 kademeli Thinking Effort (düşünme seviyesi)**, **Excel/PDF/Word/Kod analizi** ve **Google Colab LoRA ince ayar** desteği sunan bağımsız yapay zekâ stüdyosu.

## Özellikler
- **Dinamik VRAM & Otomatik Boşaltma:** Model yalnızca istek geldiğinde GPU'ya yüklenir; 15 dk boşta kalınca veya **"VRAM'i Boşalt"** butonuna basılınca VRAM tamamen temizlenir.
- **4 GB / 8 GB Otomatik Donanım Profili:**
  - **4 GB VRAM (RTX 3050 Laptop - `low_vram`):** `Gemma 4 E2B (4-Bit)` %100 GPU'da çalışır (~2.8 GB VRAM).
  - **8 GB VRAM (RTX 4060 - `turbo`):** Hem `Gemma 4 E2B` hem `Gemma 4 E4B (4-Bit)` tam hızda çalışır.
- **4 Kademeli Düşünme Seviyesi (`Thinking Effort`):** `Kapalı`, `Düşük (256 token)`, `Orta (768 token)`, `Yüksek (2048 token)`.
- **Doğrudan Sesli Konuşma & Sesli Yanıt:** Tarayıcıdan 16 kHz WAV ses kaydı doğrudan Gemma 4 ses enkoderine iletilir; yanıtlar çevrimdışı Türkçe ses sentezi ile okunabilir.
- **Dosya & Tablo Analizi:** `.xlsx`, `.xls`, `.csv`, `.pdf`, `.docx`, kod dosyaları ve görseller sürükle-bırak ile incelenir.
- **Google Colab LoRA Eğitimi:** Sohbetlerde beğendiğiniz veya düzelttiğiniz yanıtları tek tıkla `JSONL` eğitim setine ekleyip `colab/Gemma4_YerelAI_Colab_FineTune.ipynb` ile ücretsiz Colab T4 GPU üzerinde eğitebilirsiniz. Çıkan adaptörü `models/loras/<adaptor_adi>/` klasörüne koymanız yeterlidir.

## Kurulum ve Başlatma (Windows)
1. Depoyu klonlayın:
   ```bash
   git clone https://github.com/byashera/yerelai.git
   cd yerelai
   ```
2. `Baslat.bat` dosyasına çift tıklayın (ilk çalıştırmada izole Python + CUDA PyTorch + paketler kurulur ve `http://127.0.0.1:8070` açılır).
