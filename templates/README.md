# Şablonlar

Obsidian'ın çekirdek **Templates** eklentisi bu klasörü kullanır (`Settings → Templates → Template folder: templates`).

Kullanım: `Ctrl+P` → `Templates: Insert template` → şablonu seç.

| Şablon | Ne zaman |
| --- | --- |
| `note.md` | Genel kalıcı bilgi notu (`40-knowledge/`) — **tek gerçek şablon**: frontmatter + başlık iskeleti taşır |

Diğer dört dosya (`project.md`, `decision.md`, `research.md`, `context.md`)
Obsidian şablonu **değildir**: modele o not türünü nasıl yazacağını anlatan
İngilizce yönergelerdir. Notuna eklemek istemezsin — `Insert template` ile
eklersen gövdene bir emir cümlesi düşer.

## Uyarı

Şablonlar `id`, `created`, `updated` alanlarını **yer tutucu** değerlerle doldurur (`brn_replace-with-uuid`, `2026-01-01`). Elle şablon kullanıyorsan bunları değiştir; bırakırsan şema doğrulaması ve tazelik kontrolleri yanlış sonuç verir.

Pratikte notları model yazar ve alanları doğru doldurur — bu şablonlar acil elle giriş içindir. Normal akış: Claude'a söyle, önizlemeyi onayla.

- Kasa sözleşmesi: [[../AGENTS|AGENTS.md]]
- Hafıza protokolü: [[../CLAUDE|CLAUDE.md]]
- Genel bakış: [[../10-command-center/dashboard|Komuta Merkezi]]
