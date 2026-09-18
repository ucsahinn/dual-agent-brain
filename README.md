# 🧠 dual-agent-brain

**Claude Code ve Codex için ortak kalıcı hafıza.**

`v1.0.0` · Windows + PowerShell 5.1 · [MIT](LICENSE) · [Değişiklikler](CHANGELOG.md) · [Kullanım kılavuzu](kurulum/KILAVUZ.md)

---

## 🤔 Neden?

Ajanlar oturum bitince her şeyi unutur. Ertesi gün aynı şeyi baştan anlatırsın.

Bu motor araya girer: oturum kapanınca konuşmayı **özetler**, günlük loga yazar, geceleri kavram notlarına **damıtır** ve bir sonraki oturum açılırken ilgili hafızayı **kendiliğinden enjekte eder**.

İki ajan da aynı kasaya yazar. Codex'te konuştuğun şey Claude Code'da hatırlanır.

---

## ✨ Ne yapar

| | |
|---|---|
| 📝 **Otomatik özet** | Oturum kapanınca transkript özetlenir → `85-daylogs/` |
| 🌙 **Gece damıtma** | Günlük loglardan kavram notları üretilir → `86-compiled/` |
| 💉 **Bağlam enjeksiyonu** | Oturum açılışında ilgili notlar modele verilir |
| 🔍 **Anlamsal geri getirme** | Yazdığın konuyla örtüşen eski notlar yüzeye çıkar (bge-m3 vektör + kelime) |
| 🎯 **Niyet** | Haftalık hedefini kaydet, iki ajana da 7 gün boyunca hatırlatılır |
| 🩺 **Doktor** | Doksanı aşkın kontrol: ne çalışıyor, ne sessizce kayboluyor |
| 🔒 **Sır redaksiyonu** | API anahtarı, parola, token diske yazılmadan maskelenir (başarısız olursa yazım durur) |
| 🛡️ **Injection farkında** | Not ve web içeriği **veri** olarak işaretlenir, talimat olarak değil |

---

## 🚀 Kurulum

```powershell
git clone https://github.com/ucsahinn/dual-agent-brain.git Beyin
powershell -NoProfile -ExecutionPolicy Bypass -File .\Beyin\kurulum\kur.ps1
```

Sonra **yeni bir terminal aç** (PATH girdisi ancak orada geçerli olur):

```powershell
beyin durum
```

Git istemiyorsan [son sürümün arşivini](https://github.com/ucsahinn/dual-agent-brain/releases/latest) indirip açman da yeter — `beyin guncelle` git gerektirmez, zip indirir.

---

## 📋 Komutlar

**Günlük kullanımda aslında hiçbir şey yapman gerekmez** — ajanla konuşursun, motor kendiliğinden çalışır. Yine de işine yarayacaklar:

| Komut | Ne yapar |
|---|---|
| `beyin durum` | Kısa sağlık özeti — en sık kullanılan |
| `beyin doktor` | Tam kontrol tablosu |
| `beyin canli` | Şu an ne oluyor: açık oturumlar, kuyruk, bütçe |
| `beyin makbuz` | Motor ne yazdı, kaç bayt, kaç bütçe |
| `beyin niyet "..."` | Hedefini kaydet, iki ajana enjekte edilsin |
| `beyin al <yol>` | Makale/rapor/doküman oku, kavram notuna çevir |
| `beyin denetle` | Notlar arasında yakın-ikiz ve çelişki taraması |
| `beyin ayar` | Tüm ayarları tek yerden gör/değiştir |
| `beyin guncelle` | Motoru güncelle — **notlara dokunmaz** |
| `beyin yedek` | Tam vault yedeği |

Tam liste: `beyin yardim` · Ayrıntılı anlatım: [kurulum/KILAVUZ.md](kurulum/KILAVUZ.md)

🌙 **Gece görevleri** (`beyin zamanla` ile opt-in): 8 iş — derleme, gömme, çapraz bağlama, toparlama, yedek, disk raporu, kullanım raporu, anlamsal denetim.

---

## 🗂️ Kasa yapısı

```
80-memory/      👤 senin        kalıcı bağlam, kurallar, açık başlıklar
30-projects/    👤 senin        proje notları
40-knowledge/   👤 senin        kalıcı bilgi
85-daylogs/     🤖 motor        günlük oturum logları
86-compiled/    🤖 motor        damıtılmış kavram notları
90-archive/     🤖 motor        eskiyen içerik
```

👤 **Kuratörlü bölgeler motor tarafından yazılmaz.** Ajan oraya yazmadan önce sana önizleme gösterir.
🤖 **Makine bölgelerini elle düzenleme** — bir sonraki koşu üzerine yazar.

---

## 🔒 Bu depoda ne YOK

**Hiç kimsenin notu yok.** Ne günlük log, ne kavram notu, ne oturum geçmişi, ne makbuz, ne ayar sırrı.

Burada yalnız **motor**, **kurulum katmanı**, **boş kasa iskeleti** ve **kılavuz** var. Beynin içeriği senin makinende kalır ve hiçbir yere gönderilmez.

Bu bir tercih değil, mekanizma: yayın adımı **izin verilenler listesi** kullanır (ne gideceği tek tek sayılır) ve giden her dosyayı mutlak yol, kullanıcı adı, e-posta, sır deseni ve yerel proje adı için tarar. Bir şey bulursa yayın durur.

🔑 **Yedeğini sen tutarsın.** `beyin yedek` yerel yedek alır; uzak yedek bilerek yoktur.

---

## ⚙️ Gereksinimler

| | Gerekli mi | Yoksa ne olur |
|---|---|---|
| Windows + PowerShell 5.1 | ✅ zorunlu | — |
| Claude Code ve/veya Codex CLI | ✅ zorunlu | Özetleme yapılamaz |
| Git | ⬜ opsiyonel | Arşivden kur; `beyin guncelle` zaten git istemez |
| [Ollama](https://ollama.com) + `bge-m3` | ⬜ opsiyonel | Geri getirme kelime eşleşmesine düşer |
| Node.js + brain-cli | ⬜ opsiyonel | `beyin yedek` yine çalışır (motorun kendi yedeği); brain-cli varsa o tercih edilir |
| [Obsidian](https://obsidian.md) | ⬜ opsiyonel | Notları düz metin olarak okursun |

---

## 📖 Daha fazlası

- 📘 [Kullanım kılavuzu](kurulum/KILAVUZ.md) — kurulum, tüm komutlar, ayarlar, sorun giderme
- 📜 [Değişiklik günlüğü](CHANGELOG.md) — sürüm sürüm ne değişti
- 📄 [Lisans](LICENSE) — MIT

Sorun mu var? Önce `beyin doktor`. Her kırmızı satır ne yapman gerektiğini yazar.
