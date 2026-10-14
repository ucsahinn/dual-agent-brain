# Degisiklik gunlugu

Bu dosya motorun surumler arasinda **kullanici icin ne degistigini** anlatir:
hangi komut geldi, hangi davranis duzeldi, neyi bir daha eskisi gibi
yazamazsin. Ic kod ayrintisi burada degil, commit gecmisinde durur.

Kurulum ve komut referansi icin [kurulum/KILAVUZ.md](kurulum/KILAVUZ.md),
genel bakis icin [README.md](README.md).

## Surum numaralandirma

`MAJOR.MINOR.PATCH`:

- **MINOR** (`1.0.0` -> `1.1.0`): yeni ozellik ya da yeni komut.
- **PATCH** (`1.0.0` -> `1.0.1`): duzeltme turu. Yeni komut gelmez; sessizce
  yanlis davranan seyler duzelir. Kirici bir degisiklik yine de cikabilir ve
  o zaman ilgili surumun altinda **Kirici degisiklikler** basligiyla isaretlenir.

Surum damgasi vault kokundeki `.beyin-version` dosyasindadir; `beyin durum`
onu ve yayindaki surumu birlikte basar.

---

## 1.3.3 - Guvenlik ve saglamlik turu

Bagimsiz bir guvenlik denetimi ve iki kod incelemesinin Beyin tarafindaki bulgulari:

- **Onay taklidi kapandi.** Ajan kendi kabugundan alt ajan oturumu acip (Claude print modu ya da Codex exec)
  kendi "kullanici" satiriyla `baslat` / `birlestir` / `onayla` uretebilirdi; kill guard artik bu cagrilari
  reddeder (yalniz cagri konumunda: commit mesaji ya da heredoc icinde gecen metin engellenmez).
- **Dosya araclari da korunuyor.** Claude'un Write/Edit/MultiEdit/NotebookEdit araclari kill guard'in
  disindaydi; onay kaydi bu araclarla dogrudan yazilabiliyordu. Artik onay kayitlari, korunan PID listesi ve
  `~\.beyin` ayar/kesif dosyalari bu araclarla yazilamaz; kill guard ajan komutuyla kapatilamaz.
  Kayitli kurulumlar icin: `kur.ps1 -KillGuard` (Claude eslestiricisine dosya araclari eklenir).
- **Onay kancasi fail-closed.** Kosu kaydi okunamazsa onay yazilmaz (eskiden yaziliyordu); CRLF ile biten
  satirlar da taninir; onay makbuzuna oturum kaynagi bayraklari dusulur.
- **AgentChef kesfi guvenli ve hizli.** Taranan klasor git deposuysa origin adresi `agentchef` deposunu
  gostermeli (yedek/kopya/ilgisiz depolar elenir); esitlikte on-surum kaybeder; onbellek 24 saatte yenilenir,
  oturum acilisi bulunamayan AgentChef'i 10 dk boyunca yeniden taramaz.
- **Panel:** bos alanlar sahte cakisma/dosya/isci gostermez (PS 5.1 `@($null).Count`), calisan isci suresi
  UTC hatasi duzeldi, eksik onay saati bozuk tarih gostermez, "sandbox engeli" yalniz Codex'in `spawn EPERM`
  imzasinda.
- Oturumlar arasi mesajlasma icin `beyin aktar` (SendMessage kullaniciya her seferinde "Deliver" onayi cikarir).

## 1.3.2 - Beyin + AgentChef her makinede

Temiz profil provasi (sahte ev klasoru, iki depo GitHub'dan sifirdan) ve iki bagimsiz denetim, yeni bir
kullanicinin takim moduna ulasamadigi yerleri cikardi. Hepsi duzeldi:

- **AgentChef artik her yerde bulunur.** Yalniz `~\agentchef*` taraniyordu; README'ye uyup kodu Belgeler'e
  ya da `source\repos`'a klonlayan kullanicida `beyin pano`/`takim`/`bekci` dusuyordu ve hata mesaji
  yazarin kendi makinesindeki `Desktop\codex-chef` yolunu gosteriyordu. Simdi sira: ayar
  `BEYIN_AGENTCHEF_KOK` > ortam `AGENTCHEF_ROOT` > onbellek > tarama (ev, Belgeler, Masaustu, `source\repos`,
  `src`, `dev`, `code`, `kod`, `projects`, `repos`, `git`, `github`; bir seviye; `package.json` adi `agentchef`).
  Bulunamazsa tek, anlasilir mesaj: depo adresi, kurulum komutu ve `beyin ayar` satiri.
- **`beyin takim plan` panoyu kendisi olusturur.** Yeni kullanicinin ilk plani "Board state file does not
  exist" ile dusuyordu (`beyin pano` olusturuyordu, `takim` olusturmuyordu).
- **Onay kancasi dogru anda yazar.** `baslat` yalniz planlanmis, `birlestir` yalniz dogrulanmis kosu icin
  kaydedilir; erken satirda ajan nedenini soyler (eskiden Beyin onayi gecerli sayiyor, motor exit 3 veriyordu).
  Kosu kimligi kayittan alinir (buyuk/kucuk harf farki motoru reddettirmiyor).
- **Isci tanima** motorun kart kimligi deseniyle ayni (`TASK-A1` gibi kimlikler artik isci sayilir).
- **Windows Terminal yoksa** motorun izleyicisi kapatilmaz, kullaniciya `status` ile izlemesi soylenir.
- **`AGENTCHEF_TEAM_MODE=off`** iken acilista "Takim modu hazir" ipucu gosterilmez.
- **Kurulum (`kur.ps1`)** `CLAUDE_CONFIG_DIR` ve `CODEX_HOME`'u izler (eskiden hep `~\.claude`/`~\.codex`);
  sonda ORTAM bolumu: Claude Code, Codex, Node, Windows Terminal ve AgentChef var mi, yoksa ne yapilir.
- **Belgeler:** README'ye "AgentChef ile takim modu", KILAVUZ'a bolum 13 (kurulum, ilk kosu, onay satirlari,
  sinirlar); gereksinimlerde Node (pano/takim/bekci icin zorunlu), AgentChef ve Windows Terminal.
- Kucuk: `queued` isci calisiyor sayilir; doktor ve bekci AgentChef yokken ayni anlasilir mesaji verir.
- `beyin takim durdur <runId>` calismiyordu (motor `--reason` ister); simdi varsayilan neden verilir.
- `beyin pano show` bos kasada ham ENOENT veriyordu; pano yoksa olusturulur, bos liste doner.

## 1.3.1 - Isci paneli

- `beyin takim start` artik her isci icin **premium isci panelini** (`motor/scripts/takim-izle.ps1`) Windows
  Terminal sekmesinde acar; motorun ham `watch` sekmesi kapatilir (`AGENTCHEF_TEAM_PANE=off`). Panel motorun
  kosu kaydini ve iscinin `events.jsonl`'ini YALNIZ okur: durum bandi, su an + son soz, dogrulamalar | dosyalar,
  cozulmemis hata, sade akis; `t` dusunme, `e` akis, bosluk dondur, `q` cikar. Sekmeyi kapatmak isciyi durdurmaz.
- Yeni fiil: `beyin takim izle <runId> [TASK ...]` panelleri (yeniden) acar. Ayar `BEYIN_TAKIM_PANEL`:
  `on` (varsayilan) | `motor` (motorun kendi izleyicisi) | `off` (sekme acma; testler boyle kosar).
- Ilk gercek cok rollu kosuda (2026-10-13, 3 isci) ogrenilenler: Codex'in Windows `unelevated` sandbox'i
  `node --test` alt sureclerini `spawn EPERM` ile engeller (openai/codex #47868); isciler testlerini
  `node --test --test-isolation=none` ile kosmali, son soz motorun entegrasyon kontrolunde.
- **Kosu panosu** (ayni betik, yalniz `-Run`): tum takim tek ekranda - durum bandi, isci tablosu (TASK, rol,
  durum, sure, son olay, dosya, verdict), asama cizgisi (plan > start > collect > integrate > verify > merge) ve
  `SIRADA` satirinda sefin bir sonraki komutu. `beyin takim start` once kosu panosu sekmesini, sonra isci
  sekmelerini acar; `izle <runId> pano` yalniz kosu panosunu acar.
- Panel v12: Catppuccin Mocha paleti (tek vurgu rengi + uc durum rengi), cerceveye gomulu bolum basliklari,
  durum = glif + sozcuk (calisiyor sari, bitti yesil, hata kirmizi, `rejected_content` = icerik reddi),
  Turkce is adlari, Latin disi isci notlari gizlenir (`Yabanci`), kare degismediyse yeniden cizilmez (titreme yok).
- Panel v13 (2026-10-14, kullanici istegi "stat/widget kartlari, process bar, Turkce, premium"): kosu panosunda
  ASAMA ilerleme cubugu (n/6, yuzde, kirik asama kirmizi) ve alti kart (ISCILER bitti/toplam + mini bar, JETON
  giris/cikis/onbellek payi, SURE kosu + isci basina ortalama, KONTROL gecen/toplam, DOGRULAMA verdict + saat,
  DOSYA degisen dosya + teslim commit'i), isci tablosunda Turkce rol/durum/son olay; isci panelinde alti stat karti
  (SURE, JETON, KOMUT basarili/basarisiz, DOSYA, TEST, SON OLAY), Turkce rol ve pano durumu, yamali arka plan
  kutulari kalkti; kartlar dar ekranda satirlara boluunur (120 sutunda 3'lu, 100'de 2'li). Sure birimleri
  "sn/dk/sa" (eski "6d 6s" gun gibi okunuyordu).
- Panel v14-v15 (2026-10-14, tasarim incelemesi 12 madde): paneller dosyalari FileShare ReadWrite+Delete ile okur
  (motorun atomik yazmasini engellemez; R20261014-753a'da gozetmen EPERM ile dusmustu); rozet verdict'e gore
  (UYARIYLA DOGRULANDI); ASAMA satirinda onaylar ve olay cizelgesi; kartlar karar sirasiyla (DOGRULAMA, KONTROL,
  ISCILER, JETON, SURE, DOSYA), asama sureleri, bolunmus renkli isci cubugu; isci tablosunda sure cubugu, commit kodu,
  "kismen x/y"; butunlestirme tek satir ozet + [d] ayrinti; sandbox engeli (spawn EPERM) sari ve ayri sayilir;
  110 sutun altinda kompakt kartlar; terim birligi (butunlestir / ana dala al / denetim).
- Acilis ipucu: motor kuruluysa ve acik kosu yoksa sef oturumu `[Hafiza]` satirinda "Takim modu hazir" gorur
  (iki+ yazma kapsamina yayilan isi `beyin takim plan` ile iscilere bolme hatirlatmasi; baslatma yine kullanicinin
  `baslat <runId>` satiriyla). Isci oturumlarinda gosterilmez.
- `beyin takim` motorun deneysel opt-in bayragini (`AGENTCHEF_TEAM_MODE=experimental`) kendi surecinde verir:
  bayraksiz terminalden `start` "team-mode-disabled" ile dusuyor, `doctor` 9/10 veriyordu. Ortamdaki farkli bir
  degere dokunmaz. AgentChef 1.6.0 ile bayrak gereksizdir (takim modu herkese acik); `AGENTCHEF_TEAM_MODE=off` kapatir,
  sarmalayici bu degere dokunmaz.

## 1.3.0 - Takim kosusu: Claude sef, Codex isciler

**Yeni:**

- **`beyin takim <komut>`** - AgentChef `team-run.mjs` sarmalayicisi (AgentChef 1.5.0+ gerekir).
  Sef = kullanicinin konustugu Claude oturumu; 1-4 Codex iscisi (`codex exec`) her biri kendi git
  worktree'sinde, kendi pano kartiyla, gorunur terminal sekmesinde calisir. Komutlar motorla
  birebir (`plan | start | status | collect | integrate | verify | merge | pause | resume | abort |
  cleanup | doctor`); Beyin fiilleri `durum`, `baslat`, `birlestir`, `durdur`, `maliyet`.
- **Iki insan onayi, sohbete tek satir:** `baslat <runId>` (isciler baslasin) ve `birlestir <runId>`
  (ara dal `takim/<runId>` senin daline girsin). `onayla TASK-x` gibi: kullanicinin GERCEK
  mesajinda yakalanir, dosyaya duser, 7 gun gecerli, tek kullanimlik; ajan mesaji, sentetik tur ve
  isci oturumu onay SAYMAZ. Motor onay uretemez; `start`/`merge` onaysiz exit 5.
- **Isciye adresli aktarim (sema v3):** `beyin aktar "..." -Isci TASK-x` yalniz o isciye gider;
  genel `-Kime codex` mesaji iscilere dusmez. Isciden gelen mesaj `codex/TASK-x` etiketli.
- **Isci oturumu:** acilista vault baglami yerine kisa `[Hafiza: Takim]` blogu (worktree, push yok,
  kapsam disi dosya yok); toparlama atlanir (4 isci x 3 flush dongusu yok); kapanista sefe tek
  "isci bitti" brifingi; `beyin takim maliyet <runId>` kart basina jeton.
- Turetilmis gorunum `10-command-center/takim.md`; `beyin doktor` `takim` satiri; `bekci` iscileri
  kosu/kart ile listeler ve kapatmayi yalniz `beyin takim durdur` ile onerir (taskkill asla).

**Duzelen (1.2.1'den sonra bulunan):**

- **Ozetleyici reddedince serbest metin gunluk loga yaziliyordu.** Ozet biciminde
  (`**Ne konusuldu:**`) degilse artik loga YAZILMAZ, isaret ilerlemez, is en fazla 3 kez yeniden denenir.
- **Kanca testleri gercek makbuza sahte onay satiri yaziyordu** (52 satir temizlendi); testler
  artik gecici vault'ta kosar.
- **Doktor `injection uyarisi`** gozden gecirilmis gunleri (yanlis pozitif) sorun saymaz.

---

## 1.2.1 - Claude ile Codex konusabiliyor

**Duzelen (sessizce yanlis davraniyordu):**

- **Codex, Claude'un aktarimlarini hic gormuyordu.** Vault disinda bir ajan yalniz gonderenin
  proje adi kendi klasoruyle ayni olan aktarimlari goruyordu; Beyin klasorunden Codex'e yazilan
  mesaj codex-chef klasorundeki Codex'e hic ulasmadi. Artik aktarim hedef ajanin her proje
  klasorunde gorunur; gonderen isterse `-Hedef <proje>` ile sinirlar.
- **Ayni mesaj iki kez geliyordu.** Acilista gosterilen aktarim ilk komutta tekrar
  cikiyordu, paralel komutlarda cift geliyordu. Artik bir mesaj bir oturumda tek kez gosterilir.
- **Acilista uzun mesaj kayboluyordu.** Bloga sigmayan mesaj gosterilmeden "goruldu"
  sayiliyordu. Artik ilki kisaltilarak gosterilir, sigmayan sonraki sefere kalir.
- **Ajanlar `beyin` ciktisinda Turkce karakterleri bozuk goruyordu.** Komut ciktisi bir
  ajana gidince artik duz UTF-8; terminal ayarlarina dokunulmaz.
- Bos metinle gonderim, kapali ya da baska ajana yazilmis soruya yanit ve celisen bayraklar
  sessizce gecmek yerine acik hatayla reddedilir. Sinirda kesilen bir anahtarin maskeden
  kacmasi giderildi (maske artik kisaltmadan once).

**Yeni:**

- **Calisirken teslim:** hedef ajan calisiyorsa yeni aktarimi bir sonraki komutunda gorur;
  kullanici mesajini beklemez. Kill guard'in zaten kayitli kancasini kullanir: yeni kayit ya
  da Codex'te yeniden `/hooks` onayi gerekmez (kill guard girdisi bir kez onaylanmissa).
- `beyin aktar "..." -Yanit <id>`, `-Bekle <id>`, `-VeBekle`: ayni tur icinde soru-cevap.
- Terminalde renkli cikti: yanit ve kimlikler camgobegi, basari yesil, uyari sari, hata kirmizi.
- AgentChef yolu otomatik bulunur (gecerli ayar, yoksa en yeni `~\agentchef*` kurulumu).
- Belgeler: pano yalniz `beyin pano` ile; kart kullanici isteyince acilir; `done` icin hem
  isi yapmayan bir ajanin dogrulamasi hem kullanicinin `onayla TASK-x` satiri.

## 1.2.0 - insan onayi, maliyet, surec oldurme korumasi

**Kirici degisiklikler:**

- **Pano karti artik insan onayi olmadan `done` olmaz.** Kullanici sohbete yalniz
  `onayla TASK-012` satirini yazar (ya da gercek terminalde `beyin pano onayla TASK-012`
  ekrandaki kodu ister). Onay 7 gun gecerli ve tek kullanimlik. Ajan mesaji, oturumlar
  arasi mesaj ve cumle icinde gecen ifade onay SAYILMAZ. Eski davranis:
  `beyin ayar BEYIN_PANO_ONAY kapali`.

**Yeni:**

- `beyin maliyet [gun]`: iki ajanin jeton kullanimi ve API esdegeri maliyet; gun, proje
  ve oturum dokumu, oturum basi sabit yuk, 200K baglami asan oturumlar. Abonelikte gercek
  fatura bu degildir. Gece 04:10'da artimli tarar; her gunluk bloga oturumun toplami yazilir.
- `beyin skill-aday`: tekrar eden yordamsal kavram notlarindan skill adayi listesi
  (`86-compiled/skill-adaylari.md`, Pazar 05:30). Skill'i insan acar.
- **Surec oldurme korumasi (istege bagli):** `kur.ps1 -KillGuard` ile kaydedilir.
  Ajanlari AD ile toptan olduren (`taskkill /IM node.exe`, `Stop-Process -Name claude`...)
  ve baska bir ajan oturumunun PID'ini hedefleyen komutlari reddeder. Codex icin
  `-CodexZorla` + `/hooks` onayi. Zararsiz komuta ~250 ms ekler.
- **Devir blogu:** oturum kapanirken ya da sikistirilmadan once "nerede kaldim / siradaki
  adim" ayni ajanin ayni projedeki bir sonraki acilisinda bir kez gosterilir.
- **Kullanim sonmesi** (`BEYIN_SONME`): 14 gunde 5+ kez baglama gelip hic acilmayan
  kavram notlari siralamada geri duser.
- **Pano brifingi:** kart incelemeye ya da kilide gecince karsi ajana tek bildirim gider.
- **Model limitinde erteleme:** limit mesajindaki sifirlanma saatine kadar ozetleme
  denenmez, butce yakilmaz.
- Doktor: uc durum (OK / SORUN / OLCULEMEDI), kanca yorumlayicisi, auto-memory, yazma
  sondasi, ozetleyici bayraklari (model cagirmadan), maliyet ve kill guard satirlari.

**Duzelen (sessizce yanlis davraniyordu):**

- **Model limiti hatalari "genel hata" sayiliyordu.** Ozetleyicinin arac yasagi listesindeki
  bir ad CLI'da her cagrida uyari basiyordu; uyari stderr'i doldurdugu icin asil limit mesaji
  (stdout) hic okunmuyor, butce iade edilmiyordu. Ozetleyici artik tum araclari `--tools ""`
  ile kapatir ve hata ozeti iki akisi da okur.
- Ajan raporlari ve oturumlar arasi mesajlar kullanici mesaji sanilip kavram enjekte
  ediliyordu.
- Okuma yolundaki bloklarda (devam, aktarim, gunluk) sir maskesi yoktu.
- `kur.ps1 -KuruCalisma` Claude kancalari icin "kuruldu" diyordu (hicbir sey yazilmamisken).

## 1.1.0 - acilis tavani, ajanlar arasi kanal, olcum komutlari

**Duzelen (sessizce yanlis davraniyordu):**

- **Claude Code acilis hafizasi modele ulasmiyordu.** Claude Code kanca baglamini
  10.000 karakterde keser; asan kismi dosyaya atip 2 KB onizleme verir (resmi
  belge). Vault ici acilis 58 KB'ti: model yalniz saglik satirini ve kurallarin
  yarisini goruyordu. Artik toplam tavan `BEYIN_CLAUDE_TAVAN` (9500), kural ve
  guncel-baglam bloklarina karakter tavani, dusen bloklar gorunur bildirilir,
  acilis makbuzu (`beyin makbuz 1 session-start`) boyutu kaydeder.
- **"Ayni kavram bir oturumda bir kez" kurali calismiyordu**: prompt kancasinin
  geri yazimi PowerShell kapsam tuzagi yuzunden diske gitmiyordu; ayni not bes
  kez enjekte ediliyor, yansima notu hic yazilmiyordu.
- Oturum durumu yazimlari kilit altinda; engine.log eszamanli yazimda satir
  dusurmuyor; injection regex'leri zaman asimli; `BEYIN_FLUSH_BUTCE=0` artik tum
  ozetlemeyi durdurmuyor (1-1000'e sikisir); ozetleyici `claude -p` icin arac
  yasagi genisledi (Agent/Skill dahil) ve transkript kalicilig kapali.
- `gom` hata kodunu tasiyor (gece gomme sessizce olmuyor); `doktor` yerli
  `beyin yedek` klasorlerini sayiyor; `niyet -Temizle` silmeyi dogruluyor;
  `canli` bos slotu anlik kapatmiyor; `copcu` bos alani `-Kok` surucusunden
  olcuyor; `derin -SureSiniri` kabul ediyor.

**Yeni komutlar:**

- `beyin aktar` - ajanlar arasi soru/handoff kanali (Codex <-> Claude);
  hedef ajanin acilisinda `[Hafiza: Aktarim]` blogu.
- `beyin bekci` - kaynak bekcisi: commit/RAM, bosta oturumlar, yetim doktor,
  Codex MCP birikimi. YALNIZ gosterir; kapatma komutlarini panoya kopyalar.
- `beyin pano` - AgentChef coordination-board sarmalayicisi (sema v3/v4).
- `beyin kullanim` - enjekte edilen kavram notu sonradan gercekten acildi mi
  ("baglama geldi != kullanildi").
- `beyin geri-getirme-olc` - geri getirme regresyon kapisi: dondurulmus holdout,
  vektor/kelime rank-1; Pazar gece gorevi olarak da kayitli.
- `beyin kirp` - 80-memory'yi kayipsiz arsivler (eski tarihli bolum/satirlar
  `80-memory/arsiv/`); varsayilan kuru, `-Uygula` yazar.

**Degisen davranis:**

- Prompt kancasi sentetik turlarda (alt-ajan raporu, gorev bildirimi, sistem
  hatirlatmasi) arama yapmaz; istemde 2+ ayirt edici terim yoksa konu kapisi
  kapanir ve makbuza ATLANDI / KAPI_KAPALI / ESIK_ALTI yazilir.
- Kelime yolu hafif Turkce ek soyucu kullanir (sorgu ve indeks ayni fonksiyondan
  gecer); kavram satiri `[guncellendi YYYY-MM-DD]` tasir; guncellenen not ayni
  oturumda yeniden basilabilir; Aktif Basliklar'da son 14 gunde tarihli satirlar
  one gelir; current-context 8+ oturum geride kalinca `[Hafiza] UYARI kurator`.
- Sir redaksiyonuna Discord bot, Vercel, Stripe webhook ve Turkce etiket
  ("sifrem:", "parola =", "kurtarma kodu") desenleri eklendi.
- Acilista `[Hafiza] UYARI kaynak:` (commit/RAM) ve ayni klasorde es zamanli
  baska oturum uyarisi; `doktor -Ozet` 20 sn butceli, tek doktor kilidi.
- Laya yerel karar modeli denemesi kaldirildi (gercek vault verisinde sans
  duzeyi); Control koprusu betikleri kaldirildi.

**Kirici degisiklikler:** yok. `laya-makbuz` komutu ve `BEYIN_LAYA_*` ayarlari
kalkti (deneysel, hic duyurulmamisti).

---

## 1.0.0 - ilk kararli genel surum

Motor `2.x` boyunca ic gelistirme surumu olarak yasadi. `1.0.0`, **disaridan
kurulup kullanilmasi amaclanan** ilk surumdur: her komut kendi vaadini tutuyor,
her belge iddiasini kodla karsilastirildi, her yazici yol kum havuzunda
kosturuldu.

> **Surum numarasi geriye gidiyor (`2.4.3` -> `1.0.0`) ve bu bilinclidir.**
> Sayi karsilastirmasi dizge esitligidir, sira degil - yani kurulu bir motor
> guncellemeyi normal bicimde alir. `beyin guncelle` etiketlere ve release'lere
> degil `main` dalindaki `.beyin-version` dosyasina bakar.

### Bu surumde kapatilan davranis hatalari

Hepsi kosarak olculdu. Ortak konulari su: **bir kontrol KENDISI dustugunde
sonucu "hayir" degil "bilinmiyor" saymak**, ve dogrulanmadan "tamam" dememek.

#### Hafiza sessizce yariya dusmustu

- **Icerik-tabanli geri getirme iki gundur hic calismiyordu.** Oturum durumunu
  kilit altinda guncelleyen fonksiyon, PowerShell'in alt kapsam kurali yuzunden
  hicbir sey dondurmuyordu; diske yazim dogruydu, kaybolan yalniz donus
  degeriydi - bu yuzden hicbir hata gorunmedi. Sonuc: yazdigin konuyla ortusen
  eski notlari yuzeye cikaran yol sessizce oldu (makbuz kaniti: gunluk
  `retrieval` satiri 24, 19, 23 iken **0**), protokol hatirlatmasi 15 mesajda
  bir yerine **her** mesajda basildi, her promptta anahtarsiz bir cop durum
  dosyasi yazildi.
- **Ayni oturum durumunda bir yaris daha vardi:** kanca, kilitli artistan sonra
  tum durumu kilitsiz geri yaziyordu; arada gecen surede baska bir promptun
  artisi eziliyordu.

#### Alakasiz notlar enjekte ediliyordu

Geri getirmede kural "hic kelime tutmuyorsa yuksek benzerlik sart, tutuyorsa
dusuk yeter" idi. Yani **tek bir genel kelime** ('eski', 'test') benzerlik
esiginde buyuk bir indirim satin aliyordu ve alakasiz notlar geciyordu
(olculdu: uc gercek istemde gelen alti notun besi boyle gecmisti). Artik
indirim kanitin gucuyle oransal: iki baslik terimi > bir baslik terimi > iki
govde terimi > hicbiri. Ayrica durak listesine icerik tasimayan Turkce
sifat/zarflar ve **bu kasanin kendi gurultusu** ('beyin', 'vault', 'kasa')
eklendi - motorun adi her istemde geciyor, hicbir sey ayirt etmiyor.

#### Gece derlemesi sessizce iptal oluyordu

Model gerektiren gece gorevlerinden once kimlik on kontrolu yapilir; amac
oturum kapaliyken bosuna butce yakmamaktir. Bu kontrol **zaman asimina
ugradiginda da** "kimlik yok" sayiliyor ve gorev atlaniyordu - oturum ACIKKEN.
Artik uc durum var: acik (kosar), gercekten yok (atlar, `KIMLIK_YOK`),
**sonuclanmadi** (yine de dener ve bunu loglar). On kontrol bir tasarruf
onlemidir, bariyer degil.

#### Veri kaybi ve sir sizintisi yollari

- **`beyin sema-goc` okunamayan bir notu KOMSUSUNUN govdesi ve `id`'siyle
  yeniden yazabiliyordu** (okuma `try/catch` disindaydi; dusen okumada degisken
  onceki dongu turundan kalan icerigi tutuyordu). Geri donusu yoktu, ustelik
  cift `id` semayi da bozuyordu.
- **`beyin ice-aktar` sir redaksiyonunun sonucunu okumuyordu.** Motorun en
  buyuk hacimli ve en guvenilmez girdisi icin bir desen duserse maskelenmemis
  metin hem modele hem gunluk loga gidiyordu. Artik fail-closed. Ayni sozlesme
  `beyin niyet` ve geri getirme sorgusunda da kapatildi.

#### "Temiz" ile "bakilamadi" ayni cevap degil

- **`beyin yol-temizle`** okunamayan dosyalari taranmis sayip "temiz" diyordu.
- **`beyin bahcivan`** okunamayan bir kaynak not yuzunden YASAYAN bir kavrami
  arsivleyebiliyordu; ayrica indeks yazimi duserse bos bir `catch` yutup
  "basarili" diyordu - notlar arsive gitmis ama indeks onlari hala listeliyor
  ve o indeks her oturum acilisinda modele veriliyor.
- **`kur.ps1`** ayristirilamayan bir ayar dosyasinda "4 girdi yerinde" + `exit 0`
  diyordu; son dogrulama JSON ayristirmak yerine metin icinde ariyordu ve
  hicbir `HATA` adimi cikis koduna yansimiyordu.
- **`kaldir.ps1`** yazimi dogrulamadan "silindi" diyordu.
- **Doktor kendi hatasini yesil basiyordu:** `brain-cli` cagrisi patladiginda
  satir YESIL ve duzeltme metni bostu; ayni `catch` ikinci bir kontrolu de
  tamamen yutuyordu.
- **Yalniz-Codex bir makinede `beyin derin` duman testi hic kosmuyordu**,
  belgeler "claude yoksa codex'e duser" dedigi halde. Belge dogruydu, kodu tek
  satirlik bir kapi yalanliyordu.

#### Bir kurulumu kaldirmak BASKA bir kurulumu olduruyordu

Zamanlanmis gorevler makine genelindedir. `kaldir.ps1` orada buldugu her gorevi
siliyordu - yani ikinci bir kopyayi (test kurulumu, yedek disk) kaldirmak asil
kurulumun sekiz gece gorevini birden yok ediyordu. Bu, yayin oncesi testte
**canli olarak gerceklesti**. Artik gorevin eylemine bakiliyor.

#### Kucuk ama yanlis sayilar

- `beyin ayar` ile `beyin durum` ayni ayar icin farkli sayi basiyordu (gunluk
  tavan "80" vs "200"): varsayilan iki ayri yerde duruyordu. Ayni sinif iki
  ayarda daha vardi. Artik calisma zamani varsayilanlari **envanterden** gelir.
- **`BEYIN_BRAIN_CLI` ayari hicbir yerde okunmuyordu** - kullanici yazar,
  hicbir sey degisir, hata da almazdi.
- `beyin guncelle`nin "en yeni 3 yedek tutulur" vaadi bir bicim hatasi yuzunden
  olu koddu; her guncelleme motorun tam bir kopyasini birakiyordu.
- `beyin canli` alani hic olmayan eski oturumlar icin "1 kavram" gosteriyordu.

### Degisen komut davranislari

- **`beyin yedek` artik bagimliliksiz.** Eskiden bu depoda **gelmeyen** bir
  harici araca (`brain-cli.mjs`) bagliydi: komut yardimda tanitiliyor, Pazar
  gece gorevi olarak kaydedilmeye calisiliyor ve doktor onu oneriyordu - ama
  motoru yeni kuran biri icin hicbiri calismiyordu. Artik motorun kendi
  PowerShell yedegi var. `TAMAM.txt` tamamlanma isareti tasimayan klasor YARIM
  sayilir ve budamada korunur. `brain-cli` varsa dagitici yine onu tercih eder.
- **`beyin kaldir`** artik dagiticidan erisilebilir (`kur` vardi, `kaldir`
  yoktu).
- **`beyin zamanla -Zorla` ve `beyin copcu -Kok`** artik dagiticidan gecer;
  ikisi de gercek parametreydi ama dagitici tanimadigi icin reddediyordu -
  ustelik `zamanla` kullaniciya tam da `-Zorla`'yi oneriyordu.
- **Rota kendi bayragini iki kez gondermiyor.** `beyin durum -Ozet` gibi
  gereksiz ama makul bir yazim ham bir PowerShell baglama hatasi veriyordu;
  yedi rota etkileniyordu.
- **Gunluk log ozetine `Olculenler` bolumu eklendi:** oturumda gercekten
  olculmus sayilar icin ayri bir yer. "Tahmini degil, yalniz kosarak gorulen."

### Belgeler

- KILAVUZ'da dort komut "Yazar mi? **Evet**" diye listelenmisti; dordu de
  **varsayilan kuru** calisiyor (`-Uygula` sart). Tablo o bayragi hic yazmiyordu.
- `beyin guncelle`nin dokundugu kok dosya listesi `LICENSE` ve `CHANGELOG.md`
  dosyalarini atliyordu - ikisi de korumali degildir, kosulsuz uzerine yazilir.
- Gece gorevi cikis kodu tablosuna iki kod eklendi; "model gerektiren gorevler"
  cumlesinden `derin` cikarildi (zamanlanmis bir gorev degil).
- `CLAUDE.md` ve `AGENTS.md`'de `beyin ice-aktar` **iki dosyada da**,
  `beyin yedek` AGENTS.md'de eksikti.
- **Sozlesme denetcisinin kendisi bayatlamisti:** iki sozlesme dosyasinin esit
  olup olmadigina bakan doktor satiri elle bakimli bir liste kullaniyordu ve
  dokuz komutu kacirmisti. Artik komut adlari dagiticidan **turetiliyor**:
  yeni komut ya iki sozlesmeye de yazilir ya acikca muaf sayilir, sessizce
  kacamaz.
- Bos kasa iskeletindeki `dashboard.md` uc canvas haritasina hic baglanti
  vermiyordu; Obsidian grafik ayarinda iki olu renk grubu vardi.

> **Guncelleyen kullanicilar icin:** `CLAUDE.md` ve `AGENTS.md` korumali
> dosyalardir - yerelde degistirdiysen yeni sozlesme metni **gelmez**.
> Ustune yazmak icin `beyin guncelle -Zorla`.

### Taze kurulumda kalici kirmizi olmasin

Doktorun kendi felsefesi "surekli kirmizi bir satir tum sinyali korlestirir".
Uc satir bu ilkeye uymuyordu: `disk` (sabit 20 GB esigi, onerilen care cogu
zaman silinecek bir sey bulmuyordu), `ajan esligi` (kurulu olmayan ajan icin
kanca bekliyordu), `vault dosya izinleri` (motorun kendi desteklenen caresini
hic yazmiyordu).

---

## 2.x - ic gelistirme surumleri (arsiv)

`2.0` - `2.4.3` arasi surumler bu deponun **ic gelistirme** donemidir. Kisa
sureligine `v2.4.1` - `v2.4.3` etiketleriyle yayinlandilar; `1.0.0` ile
birlikte kaldirildilar. Ozetle o donemde olusan yapi:

- **2.1** - tasinabilirlik: gomulu yollar kalkti, motor baska bir makinede ve
  baska bir vault konumunda tek satir degismeden calisir hale geldi.
- **2.2** - motor iki ajanin ortak mali oldu (`motor/` altina tasindi;
  ozetleyici `claude -p` yoksa `codex exec`). Her kosu **makbuz** birakir;
  `niyet`, `canli`, `bahcivan`, `copcu`, `gom` komutlari ve **gece gorevleri**
  (Gorev Zamanlayici) geldi. Geri getirme `bge-m3` vektor + kelime hibriti oldu.
- **2.3** - kavram notlari **yerinde guncellenir** (yeni malzeme tarihli
  `## Guncelleme` bolumu olarak eklenir, eski govde yeniden yazilmaz);
  `beyin al <yol>` dis kaynagi kavram notuna cevirir; `beyin denetle`
  yakin-ikiz ve celiski tarar; `beyin bagla` her nota makine bakimli
  `## Ilgili notlar` bolumu dokur.
- **2.4** - "baskasi da kurabilsin": `beyin guncelle` tek komutla motoru
  gunceller (notlara dokunmaz), `beyin ayar` tum ayarlari tek yerde gosterir,
  kurulum `beyin` komutunu PATH'e koyar, `kurulum/KILAVUZ.md` yazildi ve yayin
  sizinti tarayicisi yerel proje adlarini da aramaya basladi.

O donemin duzeltmeleri bu dosyada tek tek sayilmiyor; hepsi `1.0.0`'in
davranisina dahildir.
