---
brain_schema: "codex-chef.brain-note.v1"
id: "brn_2e23d4e7-6b09-4b50-ba38-573cb0ec02d0"
type: "knowledge"
title: "Komuta Merkezi"
project_id: "brain"
status: "active"
privacy: "local"
confidence: "confirmed"
retention: "permanent"
created: "2026-01-01T00:00:00.000Z"
updated: "2026-01-01T00:00:00.000Z"
source_refs: ["engine:kurulum/kur.ps1", "template:iskelet"]
---

# Komuta Merkezi

Beynin giriş kapısı. Obsidian'da bu notu açık tut.

## Hafıza

- [[../80-memory/current-context|Güncel bağlam]] - şu an ne üzerinde çalışıyoruz
- [[../80-memory/active-threads|Aktif başlıklar]] - açık kalan işler
- [[../80-memory/rules|Kurallar]] - bana öğrettiklerin
- [[../80-memory/decisions|Karar özeti]] - kapanmış tartışmalar

## Makine bölgesi (otomatik)

- `85-daylogs/` - her oturumun özeti, tarihe göre
- `86-compiled/` - günlük loglardan damıtılmış kavram notları
- `86-compiled/son-durum.md` - proje bazında son durum ve devam noktaları

## Görünümler

- [Günlük loglar](gunluk-loglar.base) - tüm oturum özetleri, tabloda
- [Kavramlar](kavramlar.base) - derlenmiş kavram notları

> `.base` hedefine **wikilink yazma**. Obsidian çözer ama `brain-cli audit`
> kırık bağlantı sayar; markdown bağlantısı ikisinde de çalışır.

## Haritalar

Motorun nasıl çalıştığını gösteren üç tuval (Obsidian Canvas):

- [Sistem haritası](system-map.canvas) - motorun bütünü: kancalar, gece görevleri, bölgeler
- [Oturum akışı](control-brain-flow.canvas) - bir oturum açılıştan kapanışa ne yapar
- [Proje haritası](proje-haritasi.canvas) - boş iskelet; projelerini ve ilişkilerini buraya çiz

## Sağlık

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
```

Tam liste için `beyin yardim`.
