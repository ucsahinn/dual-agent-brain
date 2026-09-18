---
name: beyin-doktor
description: Ikinci beynin (Claude Code + Codex ortak hafizasi) saglik kontrolu ve tek komutluk durum ozeti. Kancalar, betikler, hafiza dosyalari, derleme kuyrugu, sir taramasi, kayip kapilari, es zamanlilik, kurtarma yolu ve Obsidian yuzeyi taranir. "beyin doktor", "beyin saglik", "beynim ne durumda", "beyin durum", "hafiza calismiyor", "gunluk log yazilmadi", "kavram notu cikmiyor", "devam noktalari", "beyin nerede" gibi isteklerde kullan.
---

# beyin doktor

Beynin saglik kontrolu ve durum ozeti. **Salt-okunur tani** - hicbir sey
otomatik duzeltilmez.

## Tek giris noktasi

Butun komutlar `beyin` dagiticisindan gecer. Yolu **her makinede aynidir** ve
kullanici adi icermez:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" <komut>
```

> Git Bash / WSL'den: `"$USERPROFILE/.beyin/beyin.ps1"`.
> Dagitici yoksa kurulum yapilmamistir; `beyin nerede` yerine dogrudan
> `<vault>\kurulum\kur.ps1` calistir.

## Calistir

**"Beynim ne durumda?" -> ONCE BUNU** (8-12 satir: saglik, butce, kuyruk,
kuratorlu gecikme, kurtarma ve proje basina devam noktalari):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
```

Tam tablo (tum kontroller, satir satir): `beyin doktor`
Derin kontrol (**gunluk butceden bir ozetleyici cagrisi harcar** - `claude -p` ya da claude yoksa `codex exec`; butce doluysa
calistirma): `beyin derin`
Kurulum/yol sorunu: `beyin nerede`

Ciktiyi kullaniciya goster, sonra `TANI:` satirini ozetle. Sorun varsa yalniz
SORUN satirlarini ac; OK satirlarini tek tek anlatma.

## Neye bakar

Kontrol sayisi surumle degisir; raporun sonundaki `TANI:` satiri gercek sayiyi
basar. **Buraya sabit bir sayi yazma** - yazili sayi hemen bayatlar.

| Grup | Kontrol |
| --- | --- |
| Onkosul | `claude` CLI, PowerShell surumu |
| **Kultur tuzagi** | Kultur-bagimsiz regex oz-testi (asagiya bak) |
| **Pipe encoding** | Alt surecte `$OutputEncoding` utf-8 mi (Turkce karakter bozulmasi) |
| **Betik BOM** | Tum `.ps1` dosyalari BOM'lu mu (PS 5.1 BOM'suz dosyayi ANSI okur) |
| Kancalar | Dosyalar var mi, PowerShell sozdizimi temiz mi |
| Betikler | `motor\hooks`, `motor\scripts` ve `kurulum` altindaki TUM `.ps1` dosyalari: sozdizimi + BOM, dosya basina bir satir (sayi surumle degisir) |
| Yapilandirma | Global kanca ayari bagli mi, vault-kapsamli ayar cift tetiklenme yaratiyor mu |
| Kuratorlu hafiza | 6 dosya var mi, ne kadar taze |
| Makine bolgeleri | Kac gunluk log, kac kavram notu, en eski logun yasi |
| Derleme | Bekleyen log sayisi, **deneme tavanina carpip artik derlenmeyecek gunler** |
| **Watermark / karantina** | Kac transkript ozetlendi; kac tanesi hangi sebeple karantinada |
| **Durum surumu** | `.state` JSON dosyalari + claim kilidi sayisi |
| **Butunluk** | "yazildi" denen blok sayisi dosyadaki `### Oturum` sayisiyla tutuyor mu |
| **Makine bolgesi git** | Commit edilmemis makine dosyasi birikmis mi |
| **Gunluk butce** | Bugun kac ozetleyici cagrisi harcandi - `claude -p` ya da `codex exec` (**flush tavani** belirleyici) |
| **KAYIP KAPILARI** | Tavan ustu transkript atlandi mi · 72 saatlik pencereden dusen oturum var mi · Codex SessionEnd kaniti · kuratorlu katman kac blok geride |
| Es zamanlilik | Oturum durum dosyalari, bayat kayitlar, is kuyrugu, yansima kuyrugu |
| **Guvenlik** | Sir taramasi (desen sagligi dahil), injection uyarisi, mutlak yol sizintisi, git gecmisinde kalan yol |
| **KURTARMA** | Yedek tazeligi · uzak depo var mi · calisan kod commit edilmis mi |
| **Surum tutarliligi** | `current-context.md` icindeki motor surumu `.beyin-version` ile ayni mi |
| Gozlemlenebilirlik | Motor logunun son kaydi ve yolu, gercek hatalar (tavan dolmasi hata sayilmaz) |
| Obsidian | `.base` filtreleri gercekten not esliyor mu, dashboard baglantilari |
| `-Derin` ek | ozetleyici duman testi (aktif arka uc), brain-cli sema dogrulamasi, kirik link taramasi, upstream takibi |
| **Ajan esligi** | CLAUDE.md ile AGENTS.md ayni protokolu mu tasiyor; iki ajan ayni motoru mu bagliyor; ozetleyicinin yedegi var mi |
| **Ozetleyici** | claude ve codex CLI varligi, aktif arka uc, yedek. `BEYIN_OZETLEYICI=claude|codex|auto` ile secilir |
| **Makbuz** (2.2) | Son 24 saatte makbuz var mi · bir dosya SIFIR BAYTA dustu mu (`git checkout -- <dosya>`) · engine.log basari sayiyor ama makbuz yok mu |
| **Niyet** (2.2) | Kayitli niyet var mi, 7 gunden eski mi (bayat niyet enjekte edilmez) |
| **Bahcivan** (2.2) | Olu aday kavram sayisi; makbuz kapsami 90 gunu doldurmadan karar verilmez |
| **Disk** (2.2) | Bos alan 20 GB altinda mi; copcu'nun son olctugu geri kazanilabilir alan |
| **Embedding** (2.2) | Ollama + bge-m3 + vektor indeksi tutarli mi; Ollama yoksa YESIL (kelime yolu) |
| **Zamanlayici** (2.2) | `\Beyin\` gorevleri: basarisiz sonuc kodu ya da 3 gundur kosmayan gorev; kurulmamissa YESIL |
| **Not guncelligi** (2.3) | Diskteki `## Guncelleme` bolumu sayisi + engine.log'un uygulama katmani: 2.3'ten beri kac guncelleme INDI, kac blok REDDEDILDI, kac tanesi idempotent atlandi. SORUN iki durumda: (a) model guncelleme blogu uretti ama hicbiri inmedi, (b) acikca SEZGISEL kapi - 10 modelli derleme kostu ve model bir tek blok bile uretmedi. 2.3 inmemisse ya da henuz hic blok uretilmemisse YESIL. Frontmatter'daki `created != updated` farki 2.3 kaniti SAYILMAZ (sema gocu de o damgayi basar) - ayrica "eski sema damgasi" diye gosterilir. "2.3 ne zaman indi" bilgisi `motor\scripts\.state\surum-inis.json` icinde bir kez damgalanir |
| **Kaynak alimi** (2.3) | `86-compiled\sources` var mi, kac kaynak sayfasi, sonuncusu ne zaman geldi. Klasor yoksa ya da bossa YESIL - ozellik istege bagli; kirmizi olabilecegi tek durum klasorun OKUNAMAMASI |
| **Capraz baglanti** (2.3) | TAZELIK olcer, varlik degil: en yeni basarili `bagla` makbuzu (`BAGLA_OK`) ile kavram notlarinin / vektor indeksinin en yeni yazma zamani karsilastirilir. bagla o olaydan **2 gunden fazla** geride kaldiysa SORUN - gece gorevi (03:15) susmus demektir. Kapsam (`kac not '## Ilgili notlar' tasiyor`) ayrinti metninde durur, tek basina karar vermez: bagla bolumleri yalniz komsu esigin altina duserse kaldirir, yani gorev durdugunda bolumler diskte AYNEN kalir ve kapsam olcusu boyle bir olumu hic goremezdi. Tersi de dogruydu: tek bir `bagla-uygula -MinCos 0.9` kosusu bolumlerin cogunu mesru sekilde kaldirip satiri bosuna kirmiziya dusururdu. Vektor indeksi yoksa YESIL (ozellik ona bagli) |

## Kultur tuzagi kontrolu neden var

Makine kulturu **tr-TR** ise: .NET'te Turkce kultur altinda buyuk `I`
harfinin kucugu noktasiz `ı` (U+0131) olur. Sonuc: harf-duyarsiz eslesme buyuk
`I` iceren metinde **sessizce bozulur**:

```
'API_KEY' -match 'api_key'    ->  False
'ISTANBUL' -match 'istanbul'  ->  False
```

PowerShell'in `-match`, `-replace` operatorleri ve `Select-String` de
etkilenir. Motorun sir taramasi bu yuzden bir donem **yanlis negatif**
veriyordu. Cozum: `RegexOptions` icinde `CultureInvariant`. Motor bunu
`Test-BeyinMatch` / `Invoke-BeyinReplace` uzerinden yapar.

Bu kontrol SORUN gosteriyorsa sir taramasina ve injection tespitine
**guvenmeyin** - once `lib.ps1` icindeki `$script:BeyinRxCI` tanimini onarin.

## Sik gorulen sorunlar

**"Codex SessionEnd" SORUN diyor.**
Codex, SessionEnd kancasina en fazla **3 saniye** taniyor ve sure dolunca
**tum surec agacini** olduruyor. Motor bu yuzden Codex'te yalniz kuyruga yazar
(~0,6 sn) ve isi bir sonraki SessionStart drenaj eder. Satir hala kirmiziysa:

- **`~/.codex/hooks.json` dosyasina elle DOKUNMA.** Codex her kanca tanimini
  hash'liyor; degisen kanca `/hooks` ile yeniden onaylanana kadar SESSIZCE
  atlanir. Kurulum SessionEnd'i tavanda (3) yazar; eski bir kurulumdan 15
  kaldiysa (kur.ps1 dogrulama bolumu UYARI verir) tek onayli duzeltme yolu
  `kur.ps1 -CodexZorla`, ardindan `/hooks` ile yeniden onay.
- Codex TUI'de `/hooks` ac ve SessionEnd satirinin **Trusted** oldugunu
  dogrula. Modified/Untrusted ise oradan guven ver.
- Codex oturumlarini **`/exit`** ile kapat: Codex SessionEnd'i yalniz normal
  kapanista (veya arsivleme, ya da 30 dk bosta) atesler; pencereyi kapatinca
  hicbir sey atesmez.
- Kapanmayan oturumlar kaybolmaz: yetim tarayici 72 saat icinde toplar.

**"gunluk butce" SORUN / kuyruk buyuyor.**
Flush tavani varsayilan 200, derleyici rezervi her zaman bunun 10 ustu (210); `BEYIN_FLUSH_BUTCE` ile ayarlanir. Tavan dolunca yeni oturum ozeti
uretilmez, isler kuyruga alinir ve ertesi gun islenir - **kayip degil,
gecikme**. Acele ediyorsan tavan sifirlandiktan sonra: `beyin topla 7`
(kuru calisma) / `beyin topla-uygula 7` (gercekten isler).

**"yetim adaylari" SORUN.**
72 saatlik pencereden dusmus, hic ozetlenmemis oturum var. Ayni komut, uygun
bir gun degeriyle.

**"buyuk transkript" SORUN.**
100 MB ustu bir transkript atlanmis. Motor 2.1'den beri bunlar bayt
penceresiyle okunuyor; satir hala kirmiziysa `flush.ps1` eski surumdedir.

**"kuratorlu katman" SORUN.**
Makine bolgesi doluyor ama kanonik alana tasima yapilmiyor. Kullaniciya
`80-memory/current-context.md` + `active-threads.md` icin **onizleme** hazirla;
`86-compiled/concepts` icinden kalici olanlari `40-knowledge/` altina tasimayi
oner. Haftada 1-2 kavram normaldir; hepsini tasimak kasayi copluge cevirir.

**"yedek tazeligi" SORUN.**
`beyin yedek` calistir - bagimliligi yok, motorun kendi yedegini alir.
**Onemli:** tamamlanma isareti `TAMAM.txt` tasimayan klasor YARIM yedektir ve
sayilmaz; kopyalanamayan dosya varsa komut cikis 3 verir ve sesle soyler.
Yarim bir yedegi tam sanmak, yedegin hic olmamasindan kotudur.

**"kurtarma yedekliligi" bilgi satiri.**
Kirmizi olmaz ama her kosuda gorunur: uzak depo yoksa ve yedekler vault'un
icindeyse beynin **tek kopyasi** o makinededir. Motoru ve kurulumu uzak depoya
gondermek icin `beyin yayinla`. Notlar bilerek gonderilmez.

**"motor kodu commit edildi mi" SORUN.**
Calisan kod commit edilmemis. O pencerede bir dosya bozulursa geri alinacak
surum yoktur. `git -C <vault> add motor kurulum; git -C <vault> commit -m "..."`
(doktor kirliligi `motor` ve `kurulum` ile olcer; ikisi de BOM/sozdizimi
denetiminin parcasidir - motor `.claude\` altinda DEGIL).

**Gunluk log yazilmiyor.** Once `motor logu` satirina bak (detayda log yolu
yazili: `motor\scripts\.state\engine.log`, 1 MB'de `engine.1.log`'a doner).

- "cok kisa konusma" -> dogru davranis, iki mesajdan kisa konusma ozetlenmez.
- "claude CLI bulunamadi" -> `claude` PATH'te degil.
- Hic kayit yok -> kancalar hic tetiklenmemis; `global kanca ayari` satirina
  bak, sonra `beyin nerede` ile kurulumu dogrula.

**Kavram notu uretilmiyor.** Derleyici gunde bir kez calisir: tamamlanmis bir
gunun derlenmemis logu varsa ya da saat 18'i gectiyse, **oturum acilisinda**
veya kapanisinda. 30 dakika kilidi ve tek slot ust uste calismayi engeller.
Elle: `beyin derle-zorla`.

`-Force` "her seyi bastan derle" demek DEGIL: bekleyen gunlere ek olarak
**deneme tavanina carpmis** gunleri de dener.

**Sir taramasi SORUN veriyor.** Gunluk loga maskelenmemis bir sir sizmis.
Dosyayi kullaniciya goster, elle redakte etmeyi oner ve **degerin rotasyonunu**
tavsiye et - dosyayi temizlemek yeterli degildir, deger diske yazilmis ve git
gecmisine girmis olabilir. Satir "desen uygulanamadi" diyorsa tarama EKSIK
yapilmistir; "temiz" sonucuna guvenme.

**Obsidian Bases SORUN veriyor.** Bir `.base` gorunumunun filtresi hicbir notla
eslesmiyor (yani tablo bos geliyor). Filtreyi notlarin gercek frontmatter
alanina cevir - or. gunluk loglar `type: "session-summary"`, kavramlar
`tags` icinde `derlenmis`.

## Bakim komutlari

Bir kismi **kuru calisma** varsayilanidir (`arsivle`, `topla`, `bahcivan`,
`copcu`, `bagla`, `denetle`, `yayinla`, `ice-aktar`, `al -KuruCalisma`);
yazmasi icin `-Uygula` eklenir. **Digerleri DOGRUDAN YAZAR** (`gom`, `yedek`,
`niyet`, `zamanla`, `kur`, `ayar`, `guncelle`) - asagida her komutun kendi
satirina bak, "nasilsa kuru" diye calistirma.

```powershell
beyin arsivle        # eski gunluk loglari arsive tasi (90 gun; yalniz DERLENMIS)
beyin topla 7        # pencereden dusmus oturumlari topla
beyin sema-goc       # motorun yazdigi notlarin frontmatter'ini vault semasina tasi
beyin isaret-goc     # eski (v1) satir isaretlerini v2'ye tasi
beyin yol-temizle    # makine bolgesindeki mutlak kullanici yollarini kisalt
beyin ice-aktar      # dis sohbet gecmisini (ChatGPT/Claude/Gemini takeout) al
beyin yedek          # tam vault yedegi (--apply dahil)
beyin canli          # su an: oturumlar, kuyruk, calisan is, butce, niyet (yazmaz)
beyin makbuz 7       # motor makbuzlari: ne yazildi, kac bayt, kac butce
beyin niyet "..."    # ileriye donuk hedef (iki ajana 7 gun enjekte edilir); -Temizle siler
beyin bahcivan       # kavram/skill/betik kullanimi (kuru); bahcivan-uygula olu adaylari arsivler
beyin copcu          # disk copcusu raporu; copcu-uygula KALICI siler (kullanici karari)
beyin gom            # kavram notlarini bge-m3 ile gom (Ollama gerekir)
beyin bagla          # her kavram notuna en yakin kardeslerini "## Ilgili notlar" olarak doku (kuru); bagla-uygula yazar
                     # (bolume elle yazilmis satir varsa o not ATLANIR, silinmez; gece gorevi 03:15)
beyin al <yol>       # dis kaynagi (makale/rapor/dokuman) oku, kavram notuna cevir; -Proje x, -KuruCalisma
beyin denetle        # yakin-ikiz / celiski taramasi (semantik lint); -Derin tek sonnet cagrisi = 1 butce
beyin zamanla        # gece gorevlerini kaydet (-Liste / -Kaldir)
beyin kur            # kurulumu yenile (motor guncellemesinden sonra)
beyin yayinla        # motoru + kurulumu uzak depoya gonder (notlar gitmez)
beyin ayar           # tum ayarlari tek yerden gor/degistir (oncelik: ortam degiskeni > ayar.json > varsayilan)
beyin guncelle       # motoru yayin deposundan guncelle; NOTLARA DOKUNMAZ, kaynak vault'ta calismaz
                     # once -KuruCalisma (ne degisecegini yazmadan gosterir); bozulursa -GeriAl
```

(`beyin` GERCEK bir komuttur: `kur.ps1` `~\.beyin\beyin.cmd` sarmalayicisini yazar ve
`%USERPROFILE%\.beyin` girdisini kullanici PATH'ine ekler. Girdi ancak YENI acilan bir
terminalde gecerli olur. `kur.ps1 -PathAtla` ile kapatilabilir; o zaman tam bicim:
`powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" arsivle`)

## Kacis kapilari

```powershell
setx BEYIN_VAULT X:\kapali        # kalici: iki ajanda da tum kancalar susar (YENI terminal)
$env:BEYIN_VAULT = 'X:\kapali'    # yalniz bu terminal oturumu
setx BEYIN_VAULT ""               # geri ac
```

Tek ajan: Claude Code -> `~/.claude/settings.json` icine `"disableAllHooks": true`;
Codex -> `~/.codex/config.toml` icinde `[features]` altinda `hooks = false`.
**`~/.codex/hooks.json` dosyasina dokunma** (guven hash'i).

Vault'u baska bir diske tasidin mi? Iki ajanin ayarina dokunma. `~/.beyin/vault.txt`
kancalar icin yeter, ama skill baglantilari (junction) MUTLAK hedefe bakar ve olu
kalir; bu yuzden kurulumu yeni yerinden bir kez calistir - vault.txt'yi de yazar,
baglantilari da yeniler:
`powershell -NoProfile -ExecutionPolicy Bypass -File "<yeni yol>\kurulum\kur.ps1"`
(`beyin kur` eski vault.txt uzerinden kur.ps1'i aradigi icin tasima SONRASINDA calismaz.)

## Sinir

Bu skill tani koyar, onarim onerir. Kuratorlu alandaki (80-memory,
40-knowledge, 60-decisions, 30-projects) hicbir dosyayi kullanici onayi
olmadan degistirme.
