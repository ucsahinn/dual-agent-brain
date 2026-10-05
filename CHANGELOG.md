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
