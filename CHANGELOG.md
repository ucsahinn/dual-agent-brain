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

## 1.6.1 - 2026-10-19 - Merkez: Claude isleri gorunur, canli kapasite, canli korelasyon

- **Claude Code Workflow / Agent iscileri merkezde (3. sekme):** takim kosusu kaydi birakmayan Workflow kosulari ve
  Agent araciyla acilan alt ajanlar `~/.claude/projects/<proje>/<oturum>/subagents` altindan salt okunur izlenir
  (journal olaylari + meta; transkript icerigi okunmaz). Satirda proje, tur, durum, biten/toplam, hata, acik ajan,
  faz, yas. Genel sekmesinde calisan Claude isi varken artik "calisan kosu yok" yazmaz; sekme cipi ikisini sayar.
- **`beyin kapasite [-Json]`:** canli es zamanli ajan onerisi tek formulden (commit esigi asildiysa 0-1; aksi halde
  (bos RAM - 2 GB) / 1,5 GB, tavan 8). Eski formul commit %88'de bile 4 oneriyordu. Her kaynak olcumu
  `.state\kapasite.json` (v1) yazar; AgentChef takim kosusu isci sayisini oradan alir.
- **Canli korelasyon:** teshis satiri onerilen komutun bugunku son calismasini gosterir ("son calistirma 2 dk once",
  makbuzdan); eski aktarim teshisinde `c` dogrudan `beyin aktar -Tamam <id>` kopyalar. Kaynak olcumu en cok 1 dk eski
  (eskiden 10 dk'lik dosya onbellegi: bekci %96 olcerken panel eski degeri gosterebiliyordu).
- **`beyin aktar dinle -Kime claude [-Proje x]`:** canli uyandirma. Claude Code Monitor araciyla baslatilir; yeni aktarim
  gelince tek satir basar (tam metin yok) ve bosta oturum uyanir (olculdu: aktarim yazildiktan hemen sonra olay).
  Eskiden `beyin aktar dinle` "dinle" metinli bir aktarim GONDERIRDI; dagitici artik dinleyiciye yonlendirir.
- **`r yenile`:** alt cubukta her zaman; kaynagi yeniden olcer, maliyet/bugun/aktarim/Claude isci onbelleklerini atar.
- KILAVUZ: takim kosusu isci sayisi sabit 1-4 degil; `aktar` kalici kayittir ve anlik degildir, bosta Claude oturumunu
  uyandiran kanal Claude Code oturumlar arasi mesajidir (SendMessage).

## 1.6.0 - Merkez: istege bagli ses, yardim katmani, filtre, sertlestirilmis guvenlik

Merkez ekrani hala **salt okunurdur**: `onayla` / `baslat` / `birlestir` satirlarini sohbete yine sen yazarsin;
`c` yalniz beyaz listedeki bir komutu panoya koyar, satir sonu eklemez.

- **Istege bagli ses (varsayilan kapali):** iki yeni ayar, `beyin ayar` ile degisir.
  - `BEYIN_MERKEZ_SES`: `kapali` (varsayilan) | `ton` | `toast`. `ton`: konsol bipi; hata inen (880/587 Hz), onay
    bekliyor cikan (659/988 Hz), kosu bitti uclu arpej, uyariyla biten kosu tek yumusak nota; iptal edilen ya da
    sahipsiz kosu sessiz. `toast`: Windows bildirimi kendi sesiyle gelir; ayar `toast` degilken bildirimler sessizdir
    (eskiden Windows'un varsayilan sesi her bildirimde caliyordu).
  - `BEYIN_MERKEZ_SESSIZ`: `SS-SS` ya da `yok` (varsayilan). `23-08` gece yarisini asar; ortam degiskeninden elle
    gelen `8-17` de kabul edilir. Gecersiz deger yok sayilir ve `?` yardiminda "gecersiz" diye gosterilir.
  - Ayni olay bir kez calar (hata > onay > uyari > kosu bitti, en agir olanin tonu). Esikte gidip gelen alarm
    (ornegin bellek commit %84/%85) 30 dk susar. Ilk cizimde var olan durumlar calmaz; yalniz sonradan olusanlar.
  - Ayarlar panel acilirken okunur: degistirince paneli kapatip yeniden ac. Kosu panosunun (`takim-izle`) toast'lari
    ayni iki ayara uyar (kosu panosu yalniz toast sesi verir, konsol bipi vermez).
- **`?` yardim katmani:** tuslar, renk ve simgeler, ses durumu (etkin kip ve sessiz saat) tek ekranda; `Esc` ya da
  `?` kapatir. Alt cubukta `? yardim` her zaman durur, dar pencerede de.
- **`f` filtre:** Genel ve Ajanlar sekmesinde hepsi -> sorunlu -> Claude -> Codex. "Sorunlu": engelli, incelemede,
  duraklatilmis, bayat ya da uzun aracta takili ajan. Alt cubuk etkin filtreyi yazar.
- **`g` ilk soruna atla:** ilk teshis satirina ya da engelli/incelemedeki ajana gider (gerekirse Genel sekmesine
  gecer); sorun yoksa "sorun yok" der.
- **BUGUN seridi:** saatlik seri artik kayan son 24 saat (dunun kalan saatleri + bugun); etiket gercek hucre sayisini
  yazar (170+ sutunda 24, daha darda 12). Gece yarisi gecince dunun saatleri seriden dusmez. Bugun icin maliyet
  taramasi yoksa serit "maliyet bugun taranmadi · dun $X" yazar (dunun tutari kaybolmaz); panel taramayi kendisi
  baslatmaz (`beyin maliyet`).
- **Sakin panel gercekten sakin:** baslikta canli noktasi artik nabiz atmaz (veri tazeyse yesil, bayatsa sari); hareket yokken
  saat dakika hassasiyetinde, veri 5/15 sn arayla tazelenir (`r` hemen tazeler), KANATLAR bolumu onbellekte. Olculen (bos
  fixture, 16 cekirdek, 208 sn): ortalama %4,7, yerlesik durumda %1,8-3,5 tek cekirdek. Calisan ajan varken (doner simge,
  120 ms kare) ~%20. Kare suresi (-Olcum 40, 120/210 sutun): ortalama 38-41 ms, p95 58-60 ms. Kaynak olcumu yuk altinda
  bos donerse son iyi olcum 10 dk kalir; bellek alarmi gidip gelip nabzi bastan baslatmaz. Cizim onbellekleri 2000 satirla sinirli
  (eskiden 8000). Bosta saatlerce acik kalan panelde ozel bellek ~5,5 MB/sa dogrusal buyuyordu; sanal saatli 3 saatlik
  testte panelin kendi durumu sinirli kaldi, buyume CLR yigininin geri verilmemesindendi: hareket yokken 10 dk'da bir tam
  toplama (buyuk nesne yigini sikistirmasiyla). Canli izde ozel bellek 68+ dk boyunca 129-131 MB duz. Olmayan kosu/oturum
  klasorunde Get-ChildItem artik her tazelemede hata kaydi birakmaz.
- **Calisan ama henuz adimi olmayan oturum:** transkripti bulunan yeni oturumda balon artik yanlislikla "transkript
  bu makinede yok" demez; "henuz arac adimi yok · ilk yanit bekleniyor" yazar.
- **Kosu panosu basligi:** uzun depo adi dar pencerede saati ve sag kenari itmez; baslik genislige gore kesilir.
- **Olaylar Turkce:** gercek makbuz adlari eslendi (vektor gomme / Ollama yok, `COMPILE_HATA_<neden>`,
  `FLUSH_HATA_<neden>`, flush mesgul/ertelendi, `ayar/*`, denetle, bahcivan, niyet, guncelle). Gurultu olan Laya golge
  atlandi/abstain olaylari gizlenir. Tanimsiz bir betik adi ham yazilmaz; Turkce ad ya da temizlenmis metinle gelir.
- **Bellek alarmi:** commit %85 ve ustunde TESHIS satiri ayrilmis bellege gore en buyuk 3 sureci adlariyla listeler
  ("bellek (commit) %91 · en cok: codex 2,2 GB, ...") ve `beyin bekci` ipucunu verir. Eski aktarim teshisi artik
  "oku; kapatma komutunu satirda c ile kopyala" der (c kopyalar, kapatmaz).
- **Tasarim incelemesi:** KAYNAK karti hatada basliginda da ✕ tasir (yalniz renge dayanmaz); dar ekranda BUGUN
  maliyet parcasi kisalir; sekme sayaci "Ajanlar 3"; son kosu durumu Turkce ("iptal edildi"); `f filtre`; eski
  aktarimda yalniz yas hucresi amber; maliyet kartinda "%77'si 200K+ baglamda".
- **Guvenlik:**
  - Ekrana yazilan her satir son bir korumadan gecer: yalniz SGR renk kodlari (`ESC[...m`) kalir; OSC (pencere
    basligi), imlec/ekran silme, C1 kontrol ve cift yonlu (bidi) karakterler silinir.
  - `c` panoya kopyalama tur basina tam eslesen beyaz liste kullanir: yalniz `beyin aktar -Tamam <id>`,
    `beyin takim <izle|durum|status|collect|integrate|verify|resume|cleanup> [--run] R... [TASK-n|--wait|--recheck]`,
    `beyin pano show --task TASK-n`, yetim karti iptal komutu, `onayla TASK-n`, `baslat R...`, `birlestir R...`,
    `claude --resume <id>`, `codex resume <id>` ve `beyin bekci|maliyet|doktor|aktar` kopyalanir. Eski "beyin
    <her sey>" kalibi kalkti; ajan metninden gelen kuyruk ("· beyin guncelle -Uygula" gibi), Unicode rakam ve
    kabuk islecleri reddedilir.
  - Maskeleme guclendi: JSON `password/token/secret/cookie` alanlari, `Cookie:` basliklari, `sig`, `signature`,
    `session_id`, `sid`, `access_token` parametreleri; ev dizini `~` olur.
  - Kosu panosu, tirnak ya da `;` iceren ya da bicimi bozuk kosu/kart kimligini reddeder (`gecersiz kosu/kart
    kimligi`); bicimi `[A-Za-z0-9._-]{1,64}` disinda kalan (kontrol karakterli dahil) isci gorev kimligi hicbir dosya
    yolunda kullanilmaz. Balon metni ust siniri 400 karakter (ekran kendi genisligine keser).

## 1.5.1 - Merkez: canli etkinlik, sakin islemci, ic ice surec yok, QA duzeltmeleri

Uc uzman ajanin (QA lideri, performans denetcisi, tasarim incelemecisi) bulgulari:

- **Ic ice surec yok:** yeniden yukleme eskiden yeni panel surecini iceriden baslatip bekliyordu; her yayin bellekte
  135-205 MB'lik bir surec birakiyordu (11 saatlik panelde dort surec zinciri). Simdi kucuk bir baslatici dongusu
  paneli acik sekmesiyle yeniden baslatir (cikis kodu 75); bellekte en cok baslatici + bir panel kalir.
- **Islemci:** bostaki panel cekirdegin ~%35'ini yiyordu (her 120 ms'de butun kare). Simdi: canlanmayan bolumler
  (BUGUN, kartlar, SIRADA/TESHIS, pano/aktarim, olaylar) veri degismedikce yeniden kurulmaz; ajan satiri saniyede bir
  kurulur, yalniz doner simge ve nabiz yerlestirilir; olcum/kesme/satir onbellekli; hareket yokken kare saniyede bir
  (tuslar yine aninda); aktarim listesi (426 dosya, 20 sn'de bir ~400 ms) yalniz klasor degisince okunur; 7 gunden eski
  kosu kayitlari okunmaz.
- **Canli etkinlik seridi:** her calisan ajanin satirinda son 2 dakikanin etkinligi (kimlik renginden yesile); yeni
  olayda son hucre atar. Ozdes tarama cubuklari kalkti: kim gercekten is yapiyor, kim takili, bir bakista.
- **Anlamli hareket:** hata rozeti 60 sn, onay rozeti 30 sn atar sonra sabit (alarm yorgunlugu yok); baslik koseleri
  en agir durumun renginde; calisan kosunun guncel adimi atar; BUGUN sayilari yeni degere yuvarlanir.
- **Temiz akis:** ayni ajanin ardisik rutin olaylari tek satir ("✎ özet ×8 · ⇄ aktarım ×4  20:31–22:16");
  gorulmemis olay sayaci yalniz anlamli olaylari sayar (99 ust sinir).
- **Kartlar:** bos KOSULAR/ONAYLAR kartlari tek sessiz satira iner; maliyet kartinda 7 gunluk harcama seridi; ajan
  egilimi sabitse "sabit N", degisiyorsa farki gosterir; eski maliyet taramasi uyari renginde ve TESHIS'te tazeleme
  komutu (sabahki kismi rakam dunun tam gunuyle kiyaslanmaz).
- **QA duzeltmeleri:** secim ekran disina tasarsa liste kayar (gorunmeyen satir kopyalanmaz); engelli isci teshis alir
  ve kanatta "aktif" sayilmaz; kosu panosu basligi/isci tablosu alanlari temizlenir ve kesilir (OSC/ANSI enjeksiyonu,
  tasma); tek olayli gunde "OLAYLAR (9)" hatasi; 32+ karakterlik proje adlari "***" maskelenmiyordu; 90 sutundan dar
  pencerede net uyari; "sigmadi" bildirimi kismen gizlenen bolumleri de sayar; kosu kaydi silinmis kart yetim; bozuk
  maliyet dosyasi kareyi dusurmez; ortadan kisaltilan uzun komut (bas + son gorunur).
- **Hata SIRADA'da:** aciklama baslikta, komutu kopyalanabilir "ilk adim" olarak.

## 1.5.0 - Merkez: sekmeler, Aurora paleti, ajan ayrintisi, BUGUN, panoya kopyalama

- **Sekmeler:** 1 Genel, 2 Ajanlar, 3 Kosular, 4 Olaylar (`Tab` / `1`-`4`). Dar ekranda her sey
  tek sayfaya sigmak zorunda kalmaz; sekme cipinde calisan ajan, acik kosu ve gorulmemis olay sayisi.
- **Ajan ayrintisi** (`Enter`): son 5 arac adimi, model, baglam cubugu, oturum suresi, "siranı bekliyor"
  suresi, bugunku maliyet, surdurme komutu. 170 sutun ve ustunde yan panel, daha darda satir ici.
- **BUGUN seridi** ve Olaylar sekmesinde bugun/dun tablosu: oturum, ozet, commit (git calistirmadan
  reflog'dan), yayin, derleme, hata, Claude maliyeti ve saatlik etkinlik. "dun" = dunun ayni saatine kadar.
- **`c` panoya kopyala:** secili satirin guvenli komutu (aktarim kapatma, yetim kart iptali, teshis komutu,
  oturum surdurme, onay satiri). Beyaz liste, kabuk islecli metin reddedilir, satir sonu eklenmez.
- **Aurora paleti** ve ortak cizim katmani `beyin-ciz.ps1`: renk anlam rolu olarak tek yerde, olculmus
  kontrast (soluk metin 4.3:1, cerceve 2.4:1; eski cerceve gercek ekranda gorunmuyordu). Zemin `BEYIN_MERKEZ_ZEMIN`:
  `osc` (Windows Terminal sekmesi laciverte boyanir, cikista geri alinir), `boya`, `kapali`.
- **Anlamli hareket:** uyari rozeti ve uyari durumundaki SIRADA artik sabit (yalniz hata nabiz atar),
  baslik noktasi yalniz veri bayatsa atar, cubuklar yumusak gecisle dolar, yeni olay/durum degisimi 2.5 sn parlar.
- **Simge politikasi:** emoji yalniz bolum/kart basliginda; satir ici durum tek hucreli simge. Ajan metnindeki
  ✅ ❌ ⚠ gibi BMP emojiler guvenli simgeye cevrilir; kesim emoji ciftini bolmez.
- **Kosu panosu (takim-izle) hatalari:** Windows Terminal'de 2 hucre cizilip yanindaki harfe binen
  ⚠ ✔ ✖ ▶ ⚙ ℹ ⟡ simgeleri, tam genislikteki satirda sag kenari silen `ESC[K`, kesimde sonraki metne sizan
  renk, `.Length` ile olculen sarma (CJK/emoji tasmasi), koyu zeminde gorunmeyen ░ cubuk izi ve kart
  satirinin sag bosluğu giderildi; tek kare modu (`-Tek`) ve testleri eklendi.
- **Diger:** durdurulan (aborted) isci kosu ozetinde sorunlu sayilmaz (durum kurali ile tutarli); kendini
  yeniden yukleme yalniz butun motor dosyalari 3 sn oturduktan sonra (yayin sirasinda karisik surum yok).

## 1.4.8 - Merkez: yetim kartlar, izin bekleyen oturumlar, sikisik kanatlar

- **Yetim kart:** kosusu iptal/basarisiz/ana dalda olan acik pano karti artik "bekliyor" degil
  `yetim` gorunur; TESHIS kapatma komutunu verir (`beyin pano transition ... --status cancelled
  --reason ...`). Incelemedeki (`review`) kart yetim sayilmaz: o senin `onayla` satirini bekler.
- **Uzun islem:** 2+ dk tek arac/dusunce kaydinda kalan lider `◷ uzun işlem` gorunur; 5+ dk ise
  mavi bilgi satiri "izin onayi bekliyor olabilir" der. Bilgi satiri uyari sayilmaz, ilk adim olmaz.
- **Kanatlar:** tek ajanli kanat tek satir (baslik + ajan), sira sabit (once dikkat isteyen, sonra
  ad; eskiden nabza gore her karede yer degistiriyordu). Dar ekranda aktarim ve olaylar sigar.
- **SIRADA:** ilk adim komutu kesilmez, sarilir (kesik komut kopyalanamiyordu).
- **Pano satiri:** takim kartlari repo · kosu kimligi · rol · ilk dosya ile ayirt edilir.
- **Balon** ekran genisligini doldurur (kaynakta 64 karakter kesimi 160'a cikti).
- **Olay akisi:** zamanli gorev, copcu, bagla, maliyet, bekci, onay atlandi/yok olaylari Turkce;
  bilinmeyen olayda betik adi tekrari ("zamanli · zamanli ok") yok.
- Baslik "etkinlik … 0 kayit" yerine `motor … olay` (motor makbuzu sayar, ajan mesajini degil);
  egilim grafigi 3 ornek birikmeden cizilmez; `5,3 milyar jeton`; alt bilgi `a boştakiler (+N)`.

## 1.4.7 - Merkez: daha akici cizim

- Bir kare ~180 ms yerine ~100 ms: ajan metni temizligi (saf islev, ~10 regex) sonucu
  onbellekten gelir (18 kat), Pad sigan metni bir kez olcer, mini grafik pipeline kullanmaz.

## 1.4.6 - Merkez: egilim grafikleri ve bir bakista okunur panel

- **Egilim grafikleri (sparkline):** baslikta son 2 saatin sistem etkinligi (10 dk'lik
  dilimler, makbuz sayisi); AJANLAR ve KAYNAK kartlarinda panel acik kaldikca biriken
  calisan ajan ve commit egilimi.
- **Baslik:** uyari/hata rozeti nabiz gibi atar; "son olay N sn" gostergesi, veri 2 dk+
  bayatsa nokta kehribar olur (pano canli mi, yalniz saat mi akiyor ayirt edilir).
- **SIRADA:** "hata yok · N uyari bekliyor"; kopyalanacak komut satirin en parlak ogesi.
- **Tarama hizi nabza bagli:** taze ajan hizli, yavas olan yavas, 60 sn+ sessiz ajanin
  cubugu donar (takilan ajan sayi okumadan gorunur). Calisan ajanin yasi tazeyse yesil.
- **Aktarimlar:** yas isisi (3 gun+ kalin sari, proje adi da), konu parlak / ayrinti soluk.
- **Kartlar:** sari kenar yalniz hatada; uyarida yalniz baslik ve `▲`; sakin ONAYLAR `✓`.
- **Tus satiri:** tuslar vurgulu, `a` basta; bosta kanat satirindaki tekrar ipucu kalkti.
- **Gizlilik:** ev dizini her yol biciminde (tek/cift ters bolu, /c/Users) `~` olur.

## 1.4.5 - Merkez: canli, akici, emojili panel

- **Canli:** calisan ajanin yaninda gidip gelen tarama cubugu (her ajan kendi fazinda),
  baslikta nabiz gibi atan "canli" noktasi, uyari/hata varken SIRADA seridi nabiz gibi
  atar. Kare araligi 250 -> 120 ms.
- **Renk gecisli cubuklar:** AJANLAR turkuaz -> yesil; commit kullanimi yesil -> sari -> kirmizi isinir.
- **Emoji:** bolum ve kart basliklari (🧭 🩺 🏢 🏃 📋 📨 📜 🤖 💾 💰 🔔), saglik rozeti 🟢/🟡/🔴/🔔,
  teshis 🔴/🟡. Yalniz her terminalde 2 hucre cizilen emojiler kullanilir; Windows Terminal'de
  harfin ustune binen belirsiz simgeler (⚠ ✔ ✖ ▶ ⏸) metin karsiliklariyla degisti.
- **SON OLAYLAR:** motor makbuzlarindan canli akis (ozet yazildi, aktarim, onay, yayin,
  kill guard reddi, hatirlanan kavram); gurultu atilir, ayni ajanin ardisik olaylari xN
  birlesir. Ekranda kalan bos yuksekligi doldurur, baska bolumu disari itmez.
- **Hiz:** bir kare 1,1 sn yerine ~0,1-0,2 sn (genislik olcumu regex, kesme parca parca,
  Get-Command onbellekte); aktarim/kaynak 20 sn'de bir, olay akisi yalniz makbuz buyuyunce
  okunur (tam tazeleme 475 -> ~100 ms). Kanatlar iki sutuna yalniz 200+ sutunda bolunur.

## 1.4.4 - Merkez: gercek terminalde dogrulama duzeltmeleri

- Tek kanat varken ekran yanlislikla iki sutuna bolunup sag yarisi bos kaliyordu
  (PowerShell tek ogeli diziyi acinca .Count ajan sayisini veriyordu); duzeldi.
- Pano bos ya da aktarim yoksa iki liste yan yana konmaz (bos sutun kalmaz).
- Ilerleme cubuklarinin bos kismi koyu dolu blokla cizilir; eskiden tarama
  deseni koyu zeminde gorunmuyordu.
- Bagimsiz dogrulama: xterm.js 5.5.0 ile 90/120/170/210 sutun, canli ve kenar
  durumlarinda 8 karenin hepsinde cerceve kapali, tasma yok.

## 1.4.3 - Merkez: eksiksiz ve okunur panel

- **Kartlar satiri tam doldurur** (sagda bosluk kalmaz) ve ucuncu satir kazandi:
  Claude/Codex sayisi, son biten kosu, commit GB, sessiz oturum, 200K+ baglam
  maliyet payi, en eski aktarim. Uyari/hata durumundaki kartin kenari o renkte.
- **SIRADA celiskisi giderildi:** uyari varken "her sey yolunda" yerine
  "sorun yok · N uyari" ve ilk adimin komutu yazar.
- **Inceleme kosusu** (salt okunur, raporlar toplandi) adim cizgisi `topla`da
  biter; sef'in `--covers` ile kapsadigi isci "1 sef kapsadi" olarak gorunur.
  Karari `fail` olan isci cubukta kirmizi (eskiden sari) sayilir.
- **Kanatlar:** bostaki oturumun eski "dusunuyor" balonu gizlenir; Codex kisa
  kimligi son 4 haneden (UUIDv7 oneki cakisiyordu); balonda ev dizini `~`;
  "sakin" yerine "bosta"; bosta kanat listesi sigmazsa `+N`.
- **Aktarimlar:** en eski ustte, kisa kimlik (`-Tamam` icin), 3 gunden eski
  satir uyari renginde, hedefsiz aktarim "her yer". Teshis sayiyi ve en eskisini yazar.
- Dar ekran ozeti iki satir; uzun teshis satiri ikinci satira sarilir;
  tus satiri gizli bosta ajan sayisini soyler; `-Tek -Aktifler` canli varsayilan
  gorunumu cizer.

## 1.4.2 - Merkez: sag kenar, kart genisligi, inceleme kosusu rozeti

- **Sag kenar artik kaybolmuyor.** Satir tam pencere genisligindeyken satir sonu silme komutu son sutunu (cercevenin
  sag kenarini) siliyordu (Windows Terminal'in kaydirma-bekliyor durumu). Tam genislikteki satira silme komutu yazilmaz.
- **Kartlar en az 36 hucre.** Cok genis ekranda alti kart tek satira sikisip metni kesiyordu; artik uclu satirlara bolunur.
- **Inceleme kosusu rozeti.** Raporlarini teslim etmis salt okunur bir koşu kapatildiginda IPTAL yerine
  'RAPORLAR ALINDI' rozetiyle gorunur.
- **Web balonu.** Codex web araci yalniz gercek bir arama sorgusu varsa sorguyu gosterir (ref_id gibi degerler gizlenir).

## 1.4.1 - Merkez: kosu panosu gorunumu

- **Beyin merkez yenilendi.** Dis cerceve, saglik rozeti, ozet kartlari ve SIRADA satiri sistem durumunu hizla okunur kilarken; ONAY BEKLIYOR bandi kullanici kararlarini baglamiyla one cikarir.
- **Kosu ayrintilari eklendi.** Alti asamali ilerleme cizgisi, durum rozeti, isci ilerlemesi ve sonraki adim; kosu ozetinde degisen dosya sayisi, token kullanimi, sure ve baslangic bilgisiyle birlikte gorunur. KANATLAR, PANO, AKTARIMLAR ve TESHIS ekranin bolumleri olarak duzenlendi.
- **Yenileme dongusu hizlandi**; hizli canli veriler ile onbellekli yavas ozetler ayrildi.
- Dar ekran genislikleri (90/120/170) icin cizim testleri eklendi; dolu veriyle cizim sonraki adimda.
- Calisma takim kosusuyla yapildi; ardindan tasarim, kod, guvenlik ve performans incelemeleri gerceklestirildi.

## 1.4.0 - Beyin merkez: tum sistemin tek izleme ekrani

- **Yeni komut `beyin merkez` (`-Sekme`).** Liderler (Claude/Codex oturumlari), takim kosulari ve
  Codex iscileri, onay bekleyen satirlar, pano kartlari, aktarimlar, kaynak, 7 gunluk maliyet ve
  teshis seridi tek ekranda. Projeler kanat kutulari; isi olan ajanlar ustte, bostakiler tek satirda.
  Yalniz okur, hicbir sey yazmaz.
- **Tek durum kurali.** Ajan durumu kanittan tek yerde turetilir (surec, transkript nabzi, kart,
  kosu kaydi, gozetmen) ve kaynagiyla birlikte gosterilir; bayat durum ⌛ ile isaretlenir. Oturum
  dosyasi yalniz kullanici mesajinda yazildigi icin nabiz artik transkriptin son kaydindan okunur.
- **Etkinlik balonu.** Her ajanin son eylemi transkriptin kuyrugundan okunur (Claude ve Codex
  bicimleri; dosyanin yalniz son 64 KB'si, onbellekli), 64 karaktere kisaltilir ve sirlar maskelenir.
- **Odak.** Enter isci panelini acar, `k` kosu panosunu; onay ve hata olaylari Windows bildirimi verir.
- Kavramlar AgentSpace ofis davranis spec'inden (durum onceligi, masada/geziniyor ayrimi, balon,
  teshis seridi, iki hizda yoklama); kod, sprite ya da gorsel alinmadi.

## 1.3.6 - Panelden isci paneli ve kota sonrasi kendiliginden devam

- **1-4 tuslari.** Kosu genel gorunumunde 1-4 tuslari o isciye ait paneli yeni Windows Terminal sekmesinde
  acar; alt satir hangi tuslarin gecerli oldugunu ve sonucu gosterir.
- **Kota sonrasi kendiliginden devam.** Kota yuzunden duran kosuda SIRADA satiri artik
  `beyin takim resume --run <runId> --wait` onerir: AgentChef 1.7.7 sinir mesajindan sifirlanma saatini
  okur, bekler ve kosuyu surdurur.

## 1.3.5 - Kosu paneli sagligi, bildirim ve gomme karantinasi

- **Windows bildirimi.** Kosu genel gorunumu (`beyin takim izle <runId>`) acikken kosu senden bir sey
  bekledigi ya da bir sorun ciktigi anda tek bildirim gelir: onay bekliyor (`baslat` / `birlestir`), isci
  bitti, kota siniri, dogrulama ya da butunlestirme dustu, gozetmen durdu. Panel acilirken zaten var olan
  durumlar bildirilmez. Kapatmak icin: `beyin ayar BEYIN_BILDIRIM kapali`.
- **Gozetmen durdu rozeti.** Uyku, cokme ya da yeniden baslatma sonrasi kosu `running` gorunup gozetmeni
  yoksa (nabiz 60 sn'den eski, surec yok) panel "GOZETMEN DURDU" rozetini ve SIRADA satirinda
  `beyin takim resume --run <runId>` komutunu gosterir (AgentChef 1.7.6 kurtarmasi).
- **Panel hatasi artik gizlenmez.** Cizim hatasi eskiden sessizce yutuluyor, donmus panel canli gibi
  gorunuyordu. Simdi son satirda hata sayisi ve son basarili cizimin yasi kirmizi rozetle gorunur.
- **Gomme karantinasi.** `beyin gom` sirasinda bir parti dusunce notlar tek tek denenir; tek basina da
  gomulemeyen not tum kosuyu durdurmaz. Eski vektoru varsa korunur ve bir sonraki kosu yeniden dener;
  yoksa o kosuda indekse girmez. Cikti satiri `karantina=N (...)` ile hangi notlar oldugunu yazar.
  Ollama tamamen yoksa davranis eskisi gibidir: kosu durur, eski indeks korunur.

## 1.3.4 - Kota sonrasi devam ve kill guard son acigi

- **Kota dolunca koşu sürer.** AgentChef 1.7.3'un `resume` komutuyla: `beyin takim resume --run <runId>`.
  Kosu panosu kota yuzunden duran kosuyu "KOTA SINIRI" rozetiyle gosterir; SIRADA satiri `resume`
  komutunu onerir (vazgecilirse `collect`).
- **Kill guard:** `Start-Process <claude> -ArgumentList '-p',...` bicimi de alt ajan oturumu sayilir
  (1.3.3'te bilinen sinir olarak kalmisti).

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
